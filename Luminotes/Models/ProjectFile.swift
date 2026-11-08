import Foundation

struct ProjectFile: Identifiable, Hashable, Sendable {
    let url: URL
    let relativePath: String
    let modifiedAt: Date

    var id: String { relativePath }
    var displayName: String {
        isMarkdown ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
    }

    var fileExtension: String {
        url.pathExtension.lowercased()
    }

    var isMarkdown: Bool {
        fileExtension == "md" || fileExtension == "markdown"
    }

    var isPDF: Bool {
        fileExtension == "pdf"
    }

    var isImage: Bool {
        Self.imageExtensions.contains(fileExtension)
    }

    var isAsset: Bool {
        isPDF || isImage
    }

    var icon: String {
        if isPDF { return "doc.richtext" }
        if isImage { return "photo" }
        return "doc.text"
    }

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "heif",
        "tif", "tiff", "bmp", "avif"
    ]
    var parentPath: String {
        let parent = (relativePath as NSString).deletingLastPathComponent
        return parent == "." ? "" : parent
    }
}
