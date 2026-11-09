import Foundation

enum DatabasePropertyType: String, Codable, CaseIterable, Identifiable, Sendable {
    case title
    case text
    case number
    case select
    case multiSelect
    case date
    case checkbox
    case url
    case fileType
    case createdTime
    case lastEditedTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .title: return "Title"
        case .text: return "Text"
        case .number: return "Number"
        case .select: return "Select"
        case .multiSelect: return "Multi-select"
        case .date: return "Date"
        case .checkbox: return "Checkbox"
        case .url: return "URL"
        case .fileType: return "File type"
        case .createdTime: return "Created time"
        case .lastEditedTime: return "Last edited"
        }
    }

    var isComputed: Bool {
        switch self {
        case .title, .fileType, .createdTime, .lastEditedTime:
            return true
        default:
            return false
        }
    }

    var supportsOptions: Bool {
        self == .select || self == .multiSelect
    }
}

struct DatabaseProperty: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String
    var name: String
    var type: DatabasePropertyType
    var options: [String]

    init(
        id: String = UUID().uuidString,
        name: String,
        type: DatabasePropertyType,
        options: [String] = []
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.options = options
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, type, options
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Property"
        type = try container.decodeIfPresent(DatabasePropertyType.self, forKey: .type) ?? .text
        options = try container.decodeIfPresent([String].self, forKey: .options) ?? []
    }
}

enum DatabaseLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case table
    case board
    case list
    case gallery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .table: return "Table"
        case .board: return "Board"
        case .list: return "List"
        case .gallery: return "Gallery"
        }
    }

    var icon: String {
        switch self {
        case .table: return "tablecells"
        case .board: return "rectangle.3.group"
        case .list: return "list.bullet"
        case .gallery: return "square.grid.2x2"
        }
    }
}

enum DatabaseRowSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case notes
    case assets
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes: return "Notes"
        case .assets: return "Assets"
        case .all: return "All files"
        }
    }
}

enum DatabaseFilterOperator: String, Codable, CaseIterable, Identifiable, Sendable {
    case contains
    case doesNotContain
    case isExactly
    case isNot
    case isEmpty
    case isNotEmpty
    case greaterThan
    case lessThan
    case isChecked
    case isNotChecked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contains: return "contains"
        case .doesNotContain: return "does not contain"
        case .isExactly: return "is"
        case .isNot: return "is not"
        case .isEmpty: return "is empty"
        case .isNotEmpty: return "is not empty"
        case .greaterThan: return "is greater than"
        case .lessThan: return "is less than"
        case .isChecked: return "is checked"
        case .isNotChecked: return "is not checked"
        }
    }

    var needsValue: Bool {
        switch self {
        case .isEmpty, .isNotEmpty, .isChecked, .isNotChecked:
            return false
        default:
            return true
        }
    }
}

struct DatabaseFilter: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String
    var propertyID: String
    var op: DatabaseFilterOperator
    var value: String

    init(
        id: String = UUID().uuidString,
        propertyID: String,
        op: DatabaseFilterOperator = .contains,
        value: String = ""
    ) {
        self.id = id
        self.propertyID = propertyID
        self.op = op
        self.value = value
    }

    private enum CodingKeys: String, CodingKey {
        case id, propertyID, op, value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        propertyID = try container.decodeIfPresent(String.self, forKey: .propertyID) ?? ""
        op = try container.decodeIfPresent(DatabaseFilterOperator.self, forKey: .op) ?? .contains
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
    }
}

struct DatabaseView: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String
    var name: String
    var layout: DatabaseLayout
    var visiblePropertyIDs: [String]
    var sortPropertyID: String?
    var sortAscending: Bool
    var groupPropertyID: String?
    var filters: [DatabaseFilter]

    init(
        id: String,
        name: String,
        layout: DatabaseLayout,
        visiblePropertyIDs: [String],
        sortPropertyID: String? = nil,
        sortAscending: Bool = true,
        groupPropertyID: String? = nil,
        filters: [DatabaseFilter] = []
    ) {
        self.id = id
        self.name = name
        self.layout = layout
        self.visiblePropertyIDs = visiblePropertyIDs
        self.sortPropertyID = sortPropertyID
        self.sortAscending = sortAscending
        self.groupPropertyID = groupPropertyID
        self.filters = filters
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, layout, visiblePropertyIDs, sortPropertyID, sortAscending, groupPropertyID, filters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "View"
        layout = try container.decodeIfPresent(DatabaseLayout.self, forKey: .layout) ?? .table
        visiblePropertyIDs = try container.decodeIfPresent([String].self, forKey: .visiblePropertyIDs) ?? []
        sortPropertyID = try container.decodeIfPresent(String.self, forKey: .sortPropertyID)
        sortAscending = try container.decodeIfPresent(Bool.self, forKey: .sortAscending) ?? true
        groupPropertyID = try container.decodeIfPresent(String.self, forKey: .groupPropertyID)
        filters = try container.decodeIfPresent([DatabaseFilter].self, forKey: .filters) ?? []
    }
}

struct DatabaseConfig: Codable, Equatable, Sendable {
    var version: Int
    var rowSource: DatabaseRowSource
    var properties: [DatabaseProperty]
    var views: [DatabaseView]
    var assetValues: [String: [String: String]]

    init(
        version: Int = 1,
        rowSource: DatabaseRowSource = .notes,
        properties: [DatabaseProperty],
        views: [DatabaseView],
        assetValues: [String: [String: String]] = [:]
    ) {
        self.version = version
        self.rowSource = rowSource
        self.properties = properties
        self.views = views
        self.assetValues = assetValues
    }

    private enum CodingKeys: String, CodingKey {
        case version, rowSource, properties, views, assetValues
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        rowSource = try container.decodeIfPresent(DatabaseRowSource.self, forKey: .rowSource) ?? .notes
        properties = try container.decodeIfPresent([DatabaseProperty].self, forKey: .properties)
            ?? Self.defaultConfig().properties
        views = try container.decodeIfPresent([DatabaseView].self, forKey: .views)
            ?? Self.defaultConfig().views
        assetValues = try container.decodeIfPresent([String: [String: String]].self, forKey: .assetValues)
            ?? [:]
    }

    static func defaultConfig() -> DatabaseConfig {
        let title = DatabaseProperty(id: "title", name: "Name", type: .title)
        let status = DatabaseProperty(
            id: "status",
            name: "Status",
            type: .select,
            options: ["Todo", "In progress", "Done"]
        )
        let type = DatabaseProperty(id: "fileType", name: "Type", type: .fileType)
        let modified = DatabaseProperty(id: "modifiedAt", name: "Modified", type: .lastEditedTime)

        return DatabaseConfig(
            properties: [title, status, type, modified],
            views: [
                DatabaseView(
                    id: DatabaseLayout.table.rawValue,
                    name: "Table",
                    layout: .table,
                    visiblePropertyIDs: ["title", "status", "fileType", "modifiedAt"]
                ),
                DatabaseView(
                    id: DatabaseLayout.board.rawValue,
                    name: "Board",
                    layout: .board,
                    visiblePropertyIDs: ["title", "status"],
                    groupPropertyID: "status"
                ),
                DatabaseView(
                    id: DatabaseLayout.list.rawValue,
                    name: "List",
                    layout: .list,
                    visiblePropertyIDs: ["title", "status", "fileType"]
                ),
                DatabaseView(
                    id: DatabaseLayout.gallery.rawValue,
                    name: "Gallery",
                    layout: .gallery,
                    visiblePropertyIDs: ["title", "status"]
                )
            ]
        )
    }

    func property(for id: String) -> DatabaseProperty? {
        properties.first { $0.id == id }
    }

    func view(for id: String?) -> DatabaseView {
        if let id, let view = views.first(where: { $0.id == id }) {
            return view
        }
        return views.first ?? Self.defaultConfig().views[0]
    }
}

struct DatabaseRow: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    let relativePath: String
    let title: String
    let fileExtension: String
    let isMarkdown: Bool
    let modifiedAt: Date
    var values: [String: String]

    var isPDF: Bool { fileExtension == "pdf" }
    var isImage: Bool {
        ["png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "heif",
         "tif", "tiff", "bmp", "avif"].contains(fileExtension)
    }

    var icon: String {
        if isPDF { return "doc.richtext" }
        if isImage { return "photo" }
        return "doc.text"
    }

    var fileTypeLabel: String {
        fileExtension.isEmpty ? "File" : fileExtension.uppercased()
    }

    func rawValue(for property: DatabaseProperty) -> String {
        switch property.type {
        case .title:
            return title
        case .fileType:
            return fileTypeLabel
        case .createdTime, .lastEditedTime:
            return Self.dateFormatter.string(from: modifiedAt)
        default:
            return values[property.id] ?? ""
        }
    }

    func displayValue(for property: DatabaseProperty) -> String {
        let value = rawValue(for: property)
        switch property.type {
        case .checkbox:
            return value == "true" ? "Yes" : "No"
        case .date:
            guard let date = Self.isoFormatter.date(from: value) else { return value }
            return Self.displayDateFormatter.string(from: date)
        default:
            return value
        }
    }

    static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

enum DatabaseStore {
    static func configURL(for folderURL: URL) -> URL {
        folderURL
            .appendingPathComponent(".luminotes", isDirectory: true)
            .appendingPathComponent("database.json")
    }

    static func loadConfig(for folderURL: URL) -> DatabaseConfig {
        guard let data = try? Data(contentsOf: configURL(for: folderURL)),
              let config = try? JSONDecoder().decode(DatabaseConfig.self, from: data) else {
            return .defaultConfig()
        }
        return config
    }

    static func saveConfig(_ config: DatabaseConfig, for folderURL: URL) throws {
        let url = configURL(for: folderURL)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }

    static func folderURL(
        for relativePath: String,
        projectRoot: URL
    ) -> URL? {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return projectRoot }
        let root = projectRoot.standardizedFileURL
        let candidate = root
            .appendingPathComponent(trimmed, isDirectory: true)
            .standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path == root.path || candidate.path.hasPrefix(rootPath) else {
            return nil
        }
        return candidate
    }

    static func listFolders(projectRoot: URL) -> [String] {
        let root = projectRoot.standardizedFileURL
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var folders: [String] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: Set(keys)))?.isDirectory == true else {
                continue
            }
            let name = url.lastPathComponent
            if [".git", ".obsidian", ".build", ".trash", "node_modules",
                "DerivedData", "xcuserdata"].contains(name) {
                enumerator.skipDescendants()
                continue
            }
            let relative = relativePath(from: root, to: url)
            if !relative.isEmpty {
                folders.append(relative)
            }
        }
        return folders.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    static func listRows(
        folderURL: URL,
        projectRoot: URL,
        config: DatabaseConfig
    ) throws -> [DatabaseRow] {
        let files = try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        let markdownExtensions: Set<String> = ["md", "markdown"]
        let assetExtensions: Set<String> = [
            "pdf", "png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "heif",
            "tif", "tiff", "bmp", "avif"
        ]

        var rows: [DatabaseRow] = []
        for url in files {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true else { continue }
            let ext = url.pathExtension.lowercased()
            let isMarkdown = markdownExtensions.contains(ext)
            let isAsset = assetExtensions.contains(ext)
            guard isMarkdown || isAsset else { continue }

            switch config.rowSource {
            case .notes where !isMarkdown: continue
            case .assets where !isAsset: continue
            default: break
            }

            let relative = relativePath(from: projectRoot, to: url)
            var propertyValues: [String: String] = [:]
            if isMarkdown {
                let markdown = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                propertyValues = frontmatterValues(from: markdown)
            } else {
                propertyValues = config.assetValues[relative] ?? [:]
            }

            rows.append(
                DatabaseRow(
                    id: relative,
                    url: url,
                    relativePath: relative,
                    title: isMarkdown
                        ? url.deletingPathExtension().lastPathComponent
                        : url.lastPathComponent,
                    fileExtension: ext,
                    isMarkdown: isMarkdown,
                    modifiedAt: values?.contentModificationDate ?? .distantPast,
                    values: propertyValues
                )
            )
        }

        return rows.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    static func matches(
        _ row: DatabaseRow,
        filter: DatabaseFilter,
        config: DatabaseConfig
    ) -> Bool {
        guard let property = config.property(for: filter.propertyID) else {
            return true
        }
        let raw = row.rawValue(for: property)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let needle = filter.value
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch filter.op {
        case .isEmpty:
            return raw.isEmpty
        case .isNotEmpty:
            return !raw.isEmpty
        case .isChecked:
            return raw == "true"
        case .isNotChecked:
            return raw != "true"
        case .contains:
            return raw.localizedCaseInsensitiveContains(needle)
        case .doesNotContain:
            return !raw.localizedCaseInsensitiveContains(needle)
        case .isExactly:
            return raw.localizedCaseInsensitiveCompare(needle) == .orderedSame
        case .isNot:
            return raw.localizedCaseInsensitiveCompare(needle) != .orderedSame
        case .greaterThan:
            if property.type == .number {
                return (Double(raw) ?? 0) > (Double(needle) ?? 0)
            }
            return raw.localizedStandardCompare(needle) == .orderedDescending
        case .lessThan:
            if property.type == .number {
                return (Double(raw) ?? 0) < (Double(needle) ?? 0)
            }
            return raw.localizedStandardCompare(needle) == .orderedAscending
        }
    }

    static func setValue(
        _ value: String,
        for property: DatabaseProperty,
        row: DatabaseRow,
        config: DatabaseConfig,
        folderURL: URL
    ) throws -> DatabaseConfig {        guard !property.type.isComputed else { return config }

        if row.isMarkdown {
            var markdown = (try? String(contentsOf: row.url, encoding: .utf8)) ?? ""
            markdown = updatingFrontmatter(markdown, values: [property.id: value])
            try markdown.write(to: row.url, atomically: true, encoding: .utf8)
            return config
        }

        var updated = config
        var values = updated.assetValues[row.relativePath] ?? [:]
        if value.isEmpty {
            values.removeValue(forKey: property.id)
        } else {
            values[property.id] = value
        }
        updated.assetValues[row.relativePath] = values
        try saveConfig(updated, for: folderURL)
        return updated
    }

    static func createRow(folderURL: URL, title: String) throws -> URL {
        let base = sanitizedFilename(title).isEmpty ? "Untitled" : sanitizedFilename(title)
        var candidate = folderURL.appendingPathComponent("\(base).md")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folderURL.appendingPathComponent("\(base) \(counter).md")
            counter += 1
        }
        try Data().write(to: candidate, options: .atomic)
        return candidate
    }

    static func frontmatterValues(from markdown: String) -> [String: String] {
        let lines = markdown.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return [:]
        }

        var values: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                break
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            var value = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            values[key] = value
        }
        return values
    }

    static func updatingFrontmatter(
        _ markdown: String,
        values: [String: String]
    ) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var header: [String] = []
        var bodyStart = 0

        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            header.append("---")
            var index = 1
            while index < lines.count,
                  lines[index].trimmingCharacters(in: .whitespaces) != "---" {
                header.append(lines[index])
                index += 1
            }
            if index < lines.count {
                header.append("---")
                bodyStart = index + 1
            } else {
                header.append("---")
                bodyStart = lines.count
            }
        } else {
            header = ["---"]
            bodyStart = 0
        }

        var existing: [String: String] = [:]
        var order: [String] = []
        for line in header.dropFirst().dropLast() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            existing[key] = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
            order.append(key)
        }

        for (key, value) in values {
            let cleaned = value.replacingOccurrences(of: "\n", with: " ")
            if cleaned.isEmpty {
                existing.removeValue(forKey: key)
                order.removeAll { $0 == key }
            } else {
                if existing[key] == nil {
                    order.append(key)
                }
                existing[key] = cleaned
            }
        }

        var updatedHeader = ["---"]
        for key in order {
            if let value = existing[key] {
                updatedHeader.append("\(key): \(value)")
            }
        }
        updatedHeader.append("---")

        let body = lines.dropFirst(bodyStart).joined(separator: "\n")
        return updatedHeader.joined(separator: "\n") + "\n" + body
    }

    static func relativePath(from root: URL, to url: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let base = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        let path = url.standardizedFileURL.path
        if path.hasPrefix(base) {
            return String(path.dropFirst(base.count))
        }
        return url.lastPathComponent
    }

    private static func sanitizedFilename(_ name: String) -> String {
        name
            .components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
