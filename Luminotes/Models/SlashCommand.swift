import Foundation

struct SlashCommand: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case turnInto(BlockType)
        case pdf
        case duplicate
        case delete
    }

    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let group: String
    let keywords: [String]
    let kind: Kind

    func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return true }

        let haystack = ([title] + keywords).joined(separator: " ").lowercased()
        return trimmed.split(whereSeparator: \.isWhitespace).allSatisfy { token in
            haystack.contains(token)
        }
    }

    static let all: [SlashCommand] = [
        SlashCommand(
            id: "text",
            title: "Text",
            subtitle: "Just start writing",
            icon: "text.alignleft",
            group: "Basic blocks",
            keywords: ["paragraph", "plain", "body"],
            kind: .turnInto(.paragraph)
        ),
        SlashCommand(
            id: "heading1",
            title: "Heading 1",
            subtitle: "Big section heading",
            icon: "textformat.size.larger",
            group: "Basic blocks",
            keywords: ["h1", "#", "title", "large"],
            kind: .turnInto(.heading1)
        ),
        SlashCommand(
            id: "heading2",
            title: "Heading 2",
            subtitle: "Medium section heading",
            icon: "textformat.size",
            group: "Basic blocks",
            keywords: ["h2", "##", "subtitle", "medium"],
            kind: .turnInto(.heading2)
        ),
        SlashCommand(
            id: "heading3",
            title: "Heading 3",
            subtitle: "Small section heading",
            icon: "textformat.size.smaller",
            group: "Basic blocks",
            keywords: ["h3", "###", "small"],
            kind: .turnInto(.heading3)
        ),
        SlashCommand(
            id: "bulleted",
            title: "Bulleted list",
            subtitle: "A simple unordered list",
            icon: "list.bullet",
            group: "Basic blocks",
            keywords: ["bullet", "unordered", "list", "-", "*"],
            kind: .turnInto(.bulletedList)
        ),
        SlashCommand(
            id: "numbered",
            title: "Numbered list",
            subtitle: "An ordered list",
            icon: "list.number",
            group: "Basic blocks",
            keywords: ["number", "ordered", "list", "1."],
            kind: .turnInto(.numberedList)
        ),
        SlashCommand(
            id: "todo",
            title: "To-do list",
            subtitle: "Track tasks with checkboxes",
            icon: "checkmark.square",
            group: "Basic blocks",
            keywords: ["task", "checkbox", "check", "[]"],
            kind: .turnInto(.todo)
        ),
        SlashCommand(
            id: "toggle",
            title: "Toggle list",
            subtitle: "A collapsible section",
            icon: "chevron.right",
            group: "Basic blocks",
            keywords: ["collapse", "expand", "details", ">"],
            kind: .turnInto(.toggle)
        ),
        SlashCommand(
            id: "quote",
            title: "Quote",
            subtitle: "Capture a thought",
            icon: "text.quote",
            group: "Basic blocks",
            keywords: ["blockquote", "citation", "\""],
            kind: .turnInto(.quote)
        ),
        SlashCommand(
            id: "callout",
            title: "Callout",
            subtitle: "Make something stand out",
            icon: "rectangle",
            group: "Basic blocks",
            keywords: ["note", "tip", "info", "highlight"],
            kind: .turnInto(.callout)
        ),
        SlashCommand(
            id: "divider",
            title: "Divider",
            subtitle: "Visually separate sections",
            icon: "minus",
            group: "Basic blocks",
            keywords: ["line", "separator", "horizontal", "rule", "---"],
            kind: .turnInto(.divider)
        ),
        SlashCommand(
            id: "code",
            title: "Code",
            subtitle: "Capture a snippet",
            icon: "chevron.left.forwardslash.chevron.right",
            group: "Basic blocks",
            keywords: ["snippet", "pre", "fence", "```"],
            kind: .turnInto(.code)
        ),
        SlashCommand(
            id: "math",
            title: "Math equation",
            subtitle: "Render a LaTeX expression",
            icon: "function",
            group: "Basic blocks",
            keywords: ["latex", "math", "equation", "formula", "$$"],
            kind: .turnInto(.math)
        ),
        SlashCommand(
            id: "mermaid",
            title: "Mermaid diagram",
            subtitle: "Flowchart, sequence, or chart",
            icon: "flowchart",
            group: "Media",
            keywords: ["mermaid", "diagram", "flowchart", "sequence", "gantt", "chart"],
            kind: .turnInto(.mermaid)
        ),
        SlashCommand(
            id: "image",
            title: "Image",
            subtitle: "Upload or drop in a picture",
            icon: "photo",
            group: "Media",
            keywords: ["photo", "picture", "media", "upload"],
            kind: .turnInto(.image)
        ),
        SlashCommand(
            id: "pdf",
            title: "PDF",
            subtitle: "Embed a PDF document",
            icon: "doc.richtext",
            group: "Media",
            keywords: ["pdf", "document", "file", "embed"],
            kind: .pdf
        ),
        SlashCommand(
            id: "database",
            title: "Database",
            subtitle: "View a folder as a table, board, list, or gallery",
            icon: "rectangle.3.group",
            group: "Media",
            keywords: ["database", "db", "table", "board", "gallery", "folder"],
            kind: .turnInto(.database)
        ),
        SlashCommand(
            id: "table",
            title: "Table",
            subtitle: "A simple grid of cells",
            icon: "tablecells",
            group: "Media",
            keywords: ["grid", "rows", "columns", "spreadsheet"],
            kind: .turnInto(.table)
        ),
        SlashCommand(
            id: "heading4",
            title: "Heading 4",
            subtitle: "A smaller heading",
            icon: "textformat",
            group: "More headings",
            keywords: ["h4", "####"],
            kind: .turnInto(.heading4)
        ),
        SlashCommand(
            id: "heading5",
            title: "Heading 5",
            subtitle: "An even smaller heading",
            icon: "textformat",
            group: "More headings",
            keywords: ["h5", "#####"],
            kind: .turnInto(.heading5)
        ),
        SlashCommand(
            id: "heading6",
            title: "Heading 6",
            subtitle: "The smallest heading",
            icon: "textformat",
            group: "More headings",
            keywords: ["h6", "######"],
            kind: .turnInto(.heading6)
        ),
        SlashCommand(
            id: "duplicate",
            title: "Duplicate",
            subtitle: "Copy this block below",
            icon: "square.on.square",
            group: "Actions",
            keywords: ["copy", "clone"],
            kind: .duplicate
        ),
        SlashCommand(
            id: "delete",
            title: "Delete",
            subtitle: "Remove this block",
            icon: "trash",
            group: "Actions",
            keywords: ["remove", "trash"],
            kind: .delete
        )
    ]

    static func filtered(by query: String) -> [SlashCommand] {
        all.filter { $0.matches(query) }
    }
}
