import AppKit
import Foundation

struct ProjectStore {
    let folderURL: URL

    private var fileManager: FileManager { .default }

    private static let excludedDirectories: Set<String> = [
        ".git", ".obsidian", ".build", ".trash", "node_modules",
        "DerivedData", "xcuserdata"
    ]

    private static let markdownExtensions: Set<String> = ["md", "markdown"]
    private static let assetExtensions: Set<String> = [
        "pdf", "png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "heif",
        "tif", "tiff", "bmp", "avif"
    ]

    func listMarkdownFiles() throws -> [ProjectFile] {
        try listFiles(extensions: Self.markdownExtensions)
    }

    func listProjectFiles() throws -> [ProjectFile] {
        try listFiles(extensions: Self.markdownExtensions.union(Self.assetExtensions))
    }

    private func listFiles(extensions: Set<String>) throws -> [ProjectFile] {
        let standardizedFolder = folderURL.standardizedFileURL
        let basePath = standardizedFolder.path.hasSuffix("/")
            ? standardizedFolder.path
            : standardizedFolder.path + "/"

        let keys: [URLResourceKey] = [
            .isRegularFileKey, .isDirectoryKey, .contentModificationDateKey
        ]

        guard let enumerator = fileManager.enumerator(
            at: standardizedFolder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [ProjectFile] = []

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))

            if values?.isDirectory == true {
                if Self.excludedDirectories.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values?.isRegularFile == true else { continue }
            guard extensions.contains(url.pathExtension.lowercased()) else { continue }

            let standardized = url.standardizedFileURL
            let relative: String
            if standardized.path.hasPrefix(basePath) {
                relative = String(standardized.path.dropFirst(basePath.count))
            } else {
                relative = standardized.lastPathComponent
            }

            files.append(
                ProjectFile(
                    url: standardized,
                    relativePath: relative,
                    modifiedAt: values?.contentModificationDate ?? .distantPast
                )
            )
        }

        return files.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
    }

    func findFile(named name: String) -> URL? {
        let normalized = (name.removingPercentEncoding ?? name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if Self.excludedDirectories.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values?.isRegularFile == true else { continue }
            if url.lastPathComponent.localizedCaseInsensitiveCompare(normalized) == .orderedSame {
                return url
            }
        }

        return nil
    }

    func createNote(baseName: String = "Untitled") throws -> ProjectFile {
        let safeBase = Self.sanitizedFilename(baseName)
        let url = uniqueURL(
            in: folderURL,
            baseName: safeBase.isEmpty ? "Untitled" : safeBase,
            ext: "md"
        )
        try Data().write(to: url, options: .atomic)
        return ProjectFile(
            url: url,
            relativePath: url.lastPathComponent,
            modifiedAt: Date()
        )
    }

    func readMarkdown(at url: URL) throws -> String {
        var text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            text = try String(contentsOf: url, encoding: .isoLatin1)
        }
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }
        return text
    }

    func writeMarkdown(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Copies a file into an `Assets` folder beside the note and returns a
    /// Markdown path relative to that note.
    func importFile(from sourceURL: URL, forNoteAt noteURL: URL) throws -> String {
        let noteDirectory = noteURL.deletingLastPathComponent()
        let assetsDirectory = noteDirectory.appendingPathComponent("Assets", isDirectory: true)
        try fileManager.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)

        let ext = sourceURL.pathExtension
        let base = Self.sanitizedFilename(sourceURL.deletingPathExtension().lastPathComponent)
        let destination = uniqueURL(
            in: assetsDirectory,
            baseName: base.isEmpty ? "asset" : base,
            ext: ext.isEmpty ? "png" : ext
        )

        try fileManager.copyItem(at: sourceURL, to: destination)
        return "Assets/\(destination.lastPathComponent)"
    }

    func importImage(from sourceURL: URL, forNoteAt noteURL: URL) throws -> String {
        try importFile(from: sourceURL, forNoteAt: noteURL)
    }

    /// Returns a path from the note's directory to a file inside the project.
    func relativePath(from noteURL: URL, to fileURL: URL) -> String? {
        let projectRoot = folderURL.standardizedFileURL
        let file = fileURL.standardizedFileURL
        let rootPrefix = projectRoot.path.hasSuffix("/") ? projectRoot.path : projectRoot.path + "/"
        guard file.path.hasPrefix(rootPrefix) else { return nil }

        let noteDirectory = noteURL.deletingLastPathComponent().standardizedFileURL
        let noteComponents = noteDirectory.pathComponents
        let fileComponents = file.pathComponents

        var common = 0
        while common < min(noteComponents.count, fileComponents.count),
              noteComponents[common] == fileComponents[common] {
            common += 1
        }

        let up = Array(repeating: "..", count: max(0, noteComponents.count - common))
        let down = Array(fileComponents.dropFirst(common))
        return (up + down).joined(separator: "/")
    }

    func resolveImagePath(_ path: String, relativeTo noteURL: URL?) -> URL? {
        let decoded = path.removingPercentEncoding ?? path
        if let scheme = URL(string: decoded)?.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return nil
        }
        if decoded.hasPrefix("file://") {
            return URL(string: decoded)
        }
        if decoded.hasPrefix("/") {
            return URL(fileURLWithPath: decoded)
        }

        let base = noteURL?.deletingLastPathComponent() ?? folderURL
        return URL(fileURLWithPath: decoded, relativeTo: base).standardizedFileURL
    }

    func renameNote(at url: URL, to title: String) throws -> URL {
        let safeTitle = Self.sanitizedFilename(title)
        guard !safeTitle.isEmpty else { return url }

        let ext = url.pathExtension.isEmpty ? "md" : url.pathExtension
        let directory = url.deletingLastPathComponent()
        let desired = uniqueURL(
            in: directory,
            baseName: safeTitle,
            ext: ext,
            excluding: url
        )

        guard desired.standardizedFileURL != url.standardizedFileURL else { return url }
        try fileManager.moveItem(at: url, to: desired)
        return desired
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func uniqueURL(
        in directory: URL,
        baseName: String,
        ext: String,
        excluding existingURL: URL? = nil
    ) -> URL {
        var candidate = directory.appendingPathComponent("\(baseName).\(ext)")
        var counter = 2

        while fileManager.fileExists(atPath: candidate.path) &&
            candidate.standardizedFileURL != existingURL?.standardizedFileURL {
            candidate = directory.appendingPathComponent("\(baseName) \(counter).\(ext)")
            counter += 1
        }

        return candidate
    }

    static func sanitizedFilename(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
    }
}
