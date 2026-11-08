import Foundation

enum MarkdownCodec {
    /// Full export including a generated `# Title` heading.
    static func export(_ note: Note) -> String {
        var parts: [String] = []
        if let frontmatter = normalizedFrontmatter(note.frontmatter) {
            parts.append(frontmatter)
        }

        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            parts.append("# \(title)\n")
        }

        parts.append(renderBlocks(note.blocks))
        return parts.joined(separator: "\n")
    }

    /// The document body used when writing project files. The file name is the
    /// title in project mode, so it is deliberately not injected as an H1.
    static func body(for note: Note) -> String {
        var parts: [String] = []
        if let frontmatter = normalizedFrontmatter(note.frontmatter) {
            parts.append(frontmatter)
        }
        parts.append(renderBlocks(note.blocks))
        return parts.joined(separator: "\n")
    }

    static func renderBlocks(_ blocks: [Block]) -> String {
        var lines: [String] = []
        var numberCounters: [Int: Int] = [:]

        for block in blocks {
            let indent = String(repeating: "  ", count: block.indent)
            let text = block.text.markdown
            let isListLike = block.type == .bulletedList ||
                block.type == .numberedList ||
                block.type == .todo ||
                block.type == .toggle

            if !isListLike, let last = lines.last, !last.isEmpty {
                lines.append("")
            }

            switch block.type {
            case .paragraph:
                lines.append(indent + text)
                lines.append("")
                numberCounters = [:]

            case .heading1:
                lines.append("\(indent)# \(text)")
                lines.append("")
                numberCounters = [:]

            case .heading2:
                lines.append("\(indent)## \(text)")
                lines.append("")
                numberCounters = [:]

            case .heading3:
                lines.append("\(indent)### \(text)")
                lines.append("")
                numberCounters = [:]

            case .heading4:
                lines.append("\(indent)#### \(text)")
                lines.append("")
                numberCounters = [:]

            case .heading5:
                lines.append("\(indent)##### \(text)")
                lines.append("")
                numberCounters = [:]

            case .heading6:
                lines.append("\(indent)###### \(text)")
                lines.append("")
                numberCounters = [:]

            case .bulletedList:
                lines.append("\(indent)- \(text)")
                numberCounters = [:]

            case .numberedList:
                let next = (numberCounters[block.indent] ?? 0) + 1
                numberCounters[block.indent] = next
                lines.append("\(indent)\(next). \(text)")

            case .todo:
                lines.append("\(indent)- [\(block.checked ? "x" : " ")] \(text)")
                numberCounters = [:]

            case .toggle:
                lines.append("\(indent)- \(text)")
                numberCounters = [:]

            case .quote:
                let quoted = text
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map { "\(indent)> \($0)" }
                    .joined(separator: "\n")
                lines.append(quoted)
                lines.append("")
                numberCounters = [:]

            case .callout:
                lines.append("\(indent)> [!\(alertKeyword(for: block.calloutIcon))]")
                let quoted = text
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map { "\(indent)> \($0)" }
                    .joined(separator: "\n")
                lines.append(quoted)
                lines.append("")
                numberCounters = [:]

            case .divider:
                lines.append("\(indent)---")
                lines.append("")
                numberCounters = [:]

            case .mermaid:
                lines.append("\(indent)```mermaid")
                lines.append(block.text.plainText)
                lines.append("\(indent)```")
                lines.append("")
                numberCounters = [:]

            case .code:
                let language = block.codeLanguage.lowercased()
                lines.append("\(indent)```\(language)")
                lines.append(block.text.plainText)
                lines.append("\(indent)```")
                lines.append("")
                numberCounters = [:]

            case .math:
                lines.append("\(indent)$$")
                lines.append(block.text.plainText)
                lines.append("\(indent)$$")
                lines.append("")
                numberCounters = [:]

            case .pdf:
                if let path = block.pdfPath, !path.isEmpty {
                    var inner = path
                    if let page = block.pdfPage, page > 0 {
                        inner += "#page=\(page)"
                    }
                    let alias = block.text.markdown
                    if !alias.isEmpty {
                        inner += "|\(alias)"
                    }
                    lines.append("\(indent)![[\(inner)]]")
                }
                lines.append("")
                numberCounters = [:]

            case .image:
                let caption = block.text.markdown
                let path = block.imagePath ?? block.imageAsset.map { "Assets/\($0)" }
                if let path, !path.isEmpty {
                    if block.usesWikiImageSyntax {
                        if caption.isEmpty {
                            lines.append("\(indent)![[\(path)]]")
                        } else {
                            lines.append("\(indent)![[\(path)|\(caption)]]")
                        }
                    } else {
                        let destination = path.contains(" ") || path.contains("(") || path.contains(")")
                            ? "<\(path)>"
                            : path
                        lines.append("\(indent)![\(caption)](\(destination))")
                    }
                } else if !caption.isEmpty {
                    lines.append("\(indent)\(caption)")
                }
                lines.append("")
                numberCounters = [:]

            case .table:
                guard let table = block.table, !table.rows.isEmpty else { continue }
                let columns = table.columnCount
                for (rowIndex, row) in table.rows.enumerated() {
                    let cells = (0..<columns).map { column in
                        escapeTableCell(row.indices.contains(column) ? row[column] : "")
                    }
                    lines.append("\(indent)| \(cells.joined(separator: " | ")) |")
                    if rowIndex == 0 {
                        let separators = (0..<columns).map { _ in "---" }
                        lines.append("\(indent)| \(separators.joined(separator: " | ")) |")
                    }
                }
                lines.append("")
                numberCounters = [:]
            }
        }

        var result = lines.joined(separator: "\n")
        while result.hasSuffix("\n\n") {
            result.removeLast()
        }
        if !result.hasSuffix("\n") {
            result += "\n"
        }
        return result
    }

    private static func normalizedFrontmatter(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed + "\n"
    }

    private static func alertKeyword(for icon: String) -> String {
        switch icon {
        case "ℹ️": return "INFO"
        case "💡": return "TIP"
        case "📌": return "IMPORTANT"
        case "⚠️": return "WARNING"
        case "🔥": return "CAUTION"
        case "❝": return "QUOTE"
        case "📄": return "ABSTRACT"
        case "✅": return "SUCCESS"
        case "❓": return "QUESTION"
        case "❌": return "FAILURE"
        case "⚡": return "DANGER"
        case "🐞": return "BUG"
        case "🧪": return "EXAMPLE"
        case "☑️": return "TODO"
        default: return "NOTE"
        }
    }

    private static func escapeTableCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
