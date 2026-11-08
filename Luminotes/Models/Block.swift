import Foundation

enum BlockType: String, Codable, CaseIterable, Identifiable, Sendable {
    case paragraph
    case heading1
    case heading2
    case heading3
    case heading4
    case heading5
    case heading6
    case bulletedList
    case numberedList
    case todo
    case toggle
    case quote
    case callout
    case divider
    case code
    case math
    case image
    case pdf
    case mermaid
    case table

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paragraph: return "Text"
        case .heading1: return "Heading 1"
        case .heading2: return "Heading 2"
        case .heading3: return "Heading 3"
        case .heading4: return "Heading 4"
        case .heading5: return "Heading 5"
        case .heading6: return "Heading 6"
        case .bulletedList: return "Bulleted list"
        case .numberedList: return "Numbered list"
        case .todo: return "To-do list"
        case .toggle: return "Toggle list"
        case .quote: return "Quote"
        case .callout: return "Callout"
        case .divider: return "Divider"
        case .code: return "Code"
        case .math: return "Math equation"
        case .image: return "Image"
        case .pdf: return "PDF"
        case .mermaid: return "Mermaid diagram"
        case .table: return "Table"
        }
    }

    var icon: String {
        switch self {
        case .paragraph: return "text.alignleft"
        case .heading1, .heading2, .heading3: return "textformat.size"
        case .heading4, .heading5, .heading6: return "textformat"
        case .bulletedList: return "list.bullet"
        case .numberedList: return "list.number"
        case .todo: return "checkmark.square"
        case .toggle: return "chevron.right"
        case .quote: return "text.quote"
        case .callout: return "rectangle"
        case .divider: return "minus"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .math: return "function"
        case .image: return "photo"
        case .pdf: return "doc.text"
        case .mermaid: return "flowchart"
        case .table: return "tablecells"
        }
    }

    var isHeading: Bool {
        switch self {
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            return true
        default:
            return false
        }
    }

    var isList: Bool {
        switch self {
        case .bulletedList, .numberedList, .todo:
            return true
        default:
            return false
        }
    }

    var hasTextEditor: Bool {
        switch self {
        case .divider, .table, .pdf, .mermaid:
            return false
        default:
            return true
        }
    }

    var supportsInlineStyles: Bool {
        switch self {
        case .divider, .table, .code, .math, .pdf, .mermaid:
            return false
        default:
            return true
        }
    }

    var isFocusableForNavigation: Bool {
        switch self {
        case .divider, .table, .pdf, .mermaid:
            return false
        default:
            return true
        }
    }

    var placeholder: String {
        switch self {
        case .paragraph: return "Type '/' for commands"
        case .heading1: return "Heading 1"
        case .heading2: return "Heading 2"
        case .heading3: return "Heading 3"
        case .heading4: return "Heading 4"
        case .heading5: return "Heading 5"
        case .heading6: return "Heading 6"
        case .bulletedList: return "List"
        case .numberedList: return "List"
        case .todo: return "To-do"
        case .toggle: return "Toggle"
        case .quote: return "Quote"
        case .callout: return "Write something…"
        case .code: return "Code"
        case .math: return "E = mc²"
        case .image: return "Write a caption…"
        case .pdf, .mermaid, .divider, .table: return ""
        }
    }
}

struct TableData: Codable, Equatable, Hashable, Sendable {
    var rows: [[String]]

    init(rows: [[String]] = [["Column 1", "Column 2"], ["", ""]]) {
        self.rows = rows
        normalize()
    }

    var columnCount: Int {
        rows.map(\.count).max() ?? 0
    }

    var rowCount: Int {
        rows.count
    }

    mutating func normalize() {
        if rows.isEmpty {
            rows = [[""]]
        }
        let columns = max(columnCount, 1)
        for index in rows.indices {
            if rows[index].count < columns {
                rows[index].append(contentsOf: Array(repeating: "", count: columns - rows[index].count))
            }
        }
    }

    mutating func addRow() {
        normalize()
        rows.append(Array(repeating: "", count: max(columnCount, 1)))
    }

    mutating func addColumn() {
        normalize()
        for index in rows.indices {
            rows[index].append("")
        }
    }

    mutating func removeLastRow() {
        guard rows.count > 1 else { return }
        rows.removeLast()
    }

    mutating func removeLastColumn() {
        guard columnCount > 1 else { return }
        for index in rows.indices {
            rows[index].removeLast()
        }
    }

    func cell(row: Int, column: Int) -> String {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return "" }
        return rows[row][column]
    }

    mutating func setCell(row: Int, column: Int, value: String) {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return }
        rows[row][column] = value
    }
}

struct Block: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var type: BlockType
    var text: RichText
    var checked: Bool
    var collapsed: Bool
    var indent: Int
    var codeLanguage: String
    var imageAsset: String?
    var imagePath: String?
    var usesWikiImageSyntax: Bool
    var pdfPath: String?
    var pdfPage: Int?
    var table: TableData?
    var calloutIcon: String

    init(
        id: UUID = UUID(),
        type: BlockType = .paragraph,
        text: RichText = .empty,
        checked: Bool = false,
        collapsed: Bool = false,
        indent: Int = 0,
        codeLanguage: String = "",
        imageAsset: String? = nil,
        imagePath: String? = nil,
        usesWikiImageSyntax: Bool = false,
        pdfPath: String? = nil,
        pdfPage: Int? = nil,
        table: TableData? = nil,
        calloutIcon: String = "💡"
    ) {
        self.id = id
        self.type = type
        self.text = text
        self.checked = checked
        self.collapsed = collapsed
        self.indent = max(0, min(indent, 8))
        self.codeLanguage = codeLanguage
        self.imageAsset = imageAsset
        self.imagePath = imagePath
        self.usesWikiImageSyntax = usesWikiImageSyntax
        self.pdfPath = pdfPath
        self.pdfPage = pdfPage
        self.table = table
        self.calloutIcon = calloutIcon
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        type = try container.decodeIfPresent(BlockType.self, forKey: .type) ?? .paragraph
        text = try container.decodeIfPresent(RichText.self, forKey: .text) ?? .empty
        checked = try container.decodeIfPresent(Bool.self, forKey: .checked) ?? false
        collapsed = try container.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        indent = try container.decodeIfPresent(Int.self, forKey: .indent) ?? 0
        codeLanguage = try container.decodeIfPresent(String.self, forKey: .codeLanguage) ?? ""
        imageAsset = try container.decodeIfPresent(String.self, forKey: .imageAsset)
        imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath)
        usesWikiImageSyntax = try container.decodeIfPresent(Bool.self, forKey: .usesWikiImageSyntax) ?? false
        pdfPath = try container.decodeIfPresent(String.self, forKey: .pdfPath)
        pdfPage = try container.decodeIfPresent(Int.self, forKey: .pdfPage)
        table = try container.decodeIfPresent(TableData.self, forKey: .table)
        calloutIcon = try container.decodeIfPresent(String.self, forKey: .calloutIcon) ?? "💡"
    }

    var placeholder: String {
        type.placeholder
    }

    var isTextEmpty: Bool {
        text.isEmpty
    }

    static func make(_ type: BlockType, indent: Int = 0) -> Block {
        Block(
            type: type,
            indent: indent,
            table: type == .table ? TableData() : nil,
            calloutIcon: type == .callout ? "💡" : ""
        )
    }
}

struct Note: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var blocks: [Block]
    var createdAt: Date
    var updatedAt: Date
    var frontmatter: String?

    init(
        id: UUID = UUID(),
        title: String = "Untitled",
        blocks: [Block] = [Block()],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        frontmatter: String? = nil
    ) {
        self.id = id
        self.title = title
        self.blocks = blocks
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.frontmatter = frontmatter
    }

    static var welcome: Note {
        let callout = Block(
            type: .callout,
            text: RichText(runs: [
                RichText.Run(text: "Select text and press ⌘B, ⌘I, or ⌘E to style it — or just type Markdown like "),
                RichText.Run(text: "this", bold: true),
                RichText.Run(text: ".")
            ]),
            calloutIcon: "💡"
        )
        let code = Block(
            type: .code,
            text: RichText("let blocks = note.blocks\n    .filter { !$0.text.isEmpty }"),
            codeLanguage: "Swift"
        )
        let table = Block(
            type: .table,
            table: TableData(rows: [
                ["Block", "What it does"],
                ["/h1", "Large heading"],
                ["/todo", "Task with a checkbox"],
                ["/table", "Simple table"]
            ])
        )

        return Note(
            title: "Welcome to Luminotes",
            blocks: [
                Block(text: RichText("A quiet, block-based place to think. Everything on this page is a block — write, rearrange, and shape it as you go. Open a folder from the sidebar to edit a collection of Markdown files in place.")),
                Block(type: .heading2, text: RichText("Try it out")),
                Block(type: .bulletedList, text: RichText("Type / anywhere for the block menu")),
                Block(type: .bulletedList, text: RichText("Type /math for a LaTeX equation")),
                Block(type: .bulletedList, text: RichText("Drag the handle on the left to move a block")),
                Block(type: .todo, text: RichText("Press ⌘O to open a folder as a project")),
                Block(type: .todo, text: RichText("Press ⌘N for a fresh note")),
                Block(type: .todo, text: RichText("Open the Format menu to turn a block into something else")),
                callout,
                Block(type: .divider),
                Block(type: .heading2, text: RichText("Markdown, all the way down")),
                Block(text: RichText("Luminotes understands Markdown shortcuts as you type: # for a heading, - for a list, [] for a to-do, > for a toggle, and \" for a quote.")),
                Block(type: .quote, text: RichText("The best tools disappear while you are thinking.")),
                code,
                table,
                Block(type: .heading3, text: RichText("Keep going")),
                Block(text: RichText("This scratch note is saved automatically. Open a Markdown project and every change is written back to its file.")),
                Block()
            ]
        )
    }
}
