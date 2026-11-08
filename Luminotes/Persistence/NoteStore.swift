import AppKit
import Foundation

struct NoteStore {
    let rootURL: URL
    let noteURL: URL
    let assetsURL: URL

    init(rootURL: URL? = nil) {
        let root = rootURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Luminotes", isDirectory: true)

        self.rootURL = root
        noteURL = root.appendingPathComponent("note.json")
        assetsURL = root.appendingPathComponent("Assets", isDirectory: true)
    }

    func load() -> Note? {
        guard FileManager.default.fileExists(atPath: noteURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: noteURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Note.self, from: data)
        } catch {
            NSLog("Luminotes: could not load note: \(error)")
            return nil
        }
    }

    func save(_ note: Note) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(note)
        try data.write(to: noteURL, options: .atomic)
    }

    func importImage(from sourceURL: URL) throws -> String {
        try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let filename = "\(UUID().uuidString).\(ext)"
        let destination = assetsURL.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return filename
    }

    func imageURL(for asset: String) -> URL {
        assetsURL.appendingPathComponent(asset)
    }
}
