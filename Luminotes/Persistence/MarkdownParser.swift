import Foundation

struct MarkdownDocument {
    var frontmatter: String?
    var blocks: [Block]
}

enum MarkdownParser {
    static func parse(_ markdown: String) -> MarkdownDocument {
        var text = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let frontmatter = extractFrontmatter(from: &text)
        var blocks = parseBlocks(text)
        if blocks.isEmpty {
            blocks = [Block()]
        }

        return MarkdownDocument(frontmatter: frontmatter, blocks: blocks)
    }

    private enum InlineToken {
        case math(String)
        case wiki(target: String, anchor: String?, display: String, embed: Bool)
    }

    private struct InlineTokenMatch {
        let range: NSRange
        let token: InlineToken
    }

    static func parseInline(_ text: String) -> RichText {
        guard !text.isEmpty else { return .empty }

        let nsText = text as NSString
        var tokens: [InlineTokenMatch] = []

        let mathPattern = #"(?<!\$)\$(?!\$)([^$\n]+?)(?<!\\)\$(?!\$)"#
        if let mathRegex = try? NSRegularExpression(pattern: mathPattern) {
            for match in mathRegex.matches(
                in: text,
                range: NSRange(location: 0, length: nsText.length)
            ) where match.numberOfRanges >= 2 {
                let latex = nsText.substring(with: match.range(at: 1))
                tokens.append(InlineTokenMatch(range: match.range, token: .math(latex)))
            }
        }

        let wikiPattern = #"(!?)\[\[([^\]|\n]+?)(?:\|([^\]\n]+))?\]\]"#
        if let wikiRegex = try? NSRegularExpression(pattern: wikiPattern) {
            for match in wikiRegex.matches(
                in: text,
                range: NSRange(location: 0, length: nsText.length)
            ) where match.numberOfRanges >= 3 {
                let embed = match.range(at: 1).length > 0
                let inside = nsText.substring(with: match.range(at: 2))
                let alias = match.range(at: 3).location == NSNotFound
                    ? nil
                    : nsText.substring(with: match.range(at: 3))

                var target = inside
                var anchor: String?
                if let hash = inside.firstIndex(of: "#") {
                    target = String(inside[..<hash])
                    let after = inside.index(after: hash)
                    if after < inside.endIndex {
                        anchor = String(inside[after...])
                    }
                }

                let numericAlias = alias?.allSatisfy(\.isNumber) == true
                let display = (embed && numericAlias) ? target : (alias ?? target)
                tokens.append(
                    InlineTokenMatch(
                        range: match.range,
                        token: .wiki(
                            target: target,
                            anchor: anchor,
                            display: display,
                            embed: embed
                        )
                    )
                )
            }
        }

        guard !tokens.isEmpty else { return parseInlineMarkdown(text) }
        tokens.sort { $0.range.location < $1.range.location }

        var result = RichText()
        var cursor = 0
        var lastEnd = 0

        for entry in tokens {
            guard entry.range.location >= lastEnd else { continue }
            if entry.range.location > cursor {
                let plain = nsText.substring(
                    with: NSRange(location: cursor, length: entry.range.location - cursor)
                )
                result.append(parseInlineMarkdown(plain))
            }

            switch entry.token {
            case .math(let latex):
                result.append(RichText.Run(text: "", math: latex))
            case .wiki(let target, let anchor, let display, let embed):
                if let url = wikiURL(target: target, anchor: anchor, embed: embed) {
                    result.append(
                        RichText.Run(
                            text: display,
                            link: url
                        )
                    )
                } else {
                    result.append(RichText(display))
                }
            }

            cursor = entry.range.location + entry.range.length
            lastEnd = cursor
        }

        if cursor < nsText.length {
            result.append(parseInlineMarkdown(nsText.substring(from: cursor)))
        }

        return result
    }

    private static func wikiURL(target: String, anchor: String?, embed: Bool) -> String? {
        var components = URLComponents()
        components.scheme = "luminotes"
        components.host = "open"
        var items = [URLQueryItem(name: "target", value: target)]
        if let anchor, !anchor.isEmpty {
            items.append(URLQueryItem(name: "anchor", value: anchor))
        }
        if embed {
            items.append(URLQueryItem(name: "embed", value: "1"))
        }
        components.queryItems = items
        return components.url?.absoluteString
    }

    private static func parseInlineMarkdown(_ text: String) -> RichText {
        guard !text.isEmpty else { return .empty }

        let normalized = text.replacingOccurrences(
            of: #"<br\s*/?>"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )

        if let attributed = try? AttributedString(
            markdown: normalized,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            var runs: [RichText.Run] = []
            for run in attributed.runs {
                let value = String(attributed[run.range].characters)
                guard !value.isEmpty else { continue }

                let intent = run.inlinePresentationIntent ?? []
                runs.append(
                    RichText.Run(
                        text: value,
                        bold: intent.contains(.stronglyEmphasized),
                        italic: intent.contains(.emphasized),
                        underline: false,
                        strikethrough: intent.contains(.strikethrough),
                        code: intent.contains(.code),
                        link: run.link?.absoluteString
                    )
                )
            }
            if !runs.isEmpty {
                return RichText(runs: runs)
            }
        }

        return RichText(text)
    }

    // MARK: - Frontmatter

    private static func extractFrontmatter(from text: inout String) -> String? {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }

        guard let closing = lines.dropFirst().firstIndex(where: {
            let value = $0.trimmingCharacters(in: .whitespaces)
            return value == "---" || value == "..."
        }) else {
            return nil
        }

        let payload = lines[1..<closing].filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !payload.isEmpty else { return nil }

        let frontmatter = lines[0...closing].joined(separator: "\n") + "\n"
        text = lines[(closing + 1)...].joined(separator: "\n")
        return frontmatter
    }

    // MARK: - Blocks

    private static func parseBlocks(_ text: String) -> [Block] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [Block] = []
        var index = 0

        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let math = mathBlock(lines: lines, start: index, end: &index) {
                blocks.append(math)
                continue
            }

            if let fence = codeFence(from: rawLine) {
                index += 1
                var codeLines: [String] = []

                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if candidate.hasPrefix(fence.marker) {
                        index += 1
                        break
                    }
                    codeLines.append(lines[index])
                    index += 1
                }

                if fence.language.lowercased() == "mermaid" {
                    blocks.append(
                        Block(
                            type: .mermaid,
                            text: RichText(codeLines.joined(separator: "\n"))
                        )
                    )
                } else {
                    blocks.append(
                        Block(
                            type: .code,
                            text: RichText(codeLines.joined(separator: "\n")),
                            codeLanguage: displayLanguage(fence.language)
                        )
                    )
                }
                continue
            }

            if let heading = heading(from: rawLine) {
                blocks.append(
                    Block(
                        type: heading.type,
                        text: parseInline(heading.text)
                    )
                )
                index += 1
                continue
            }

            if isThematicBreak(trimmed) {
                blocks.append(Block(type: .divider))
                index += 1
                continue
            }

            if rawLine.contains("|"),
               index + 1 < lines.count,
               isTableSeparator(lines[index + 1]) {
                if let table = parseTable(lines: lines, start: index, end: &index) {
                    blocks.append(table)
                    continue
                }
            }

            if startsWithBlockquote(rawLine) {
                let firstLine = rawLine
                var quotedLines: [String] = []
                while index < lines.count, startsWithBlockquote(lines[index]) {
                    quotedLines.append(stripBlockquoteMarker(from: lines[index]))
                    index += 1
                }

                let first = quotedLines.first?.trimmingCharacters(in: .whitespaces) ?? ""
                if let alert = calloutType(for: first) {
                    if !quotedLines.isEmpty { quotedLines.removeFirst() }
                    while quotedLines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
                        quotedLines.removeFirst()
                    }

                    var content = RichText()
                    if let title = alert.title, !title.isEmpty {
                        content.append(RichText.Run(text: title, bold: true))
                        if !quotedLines.isEmpty {
                            content.append(RichText.Run(text: "\n"))
                        }
                    }
                    content.append(parseInline(quotedLines.joined(separator: "\n")))

                    blocks.append(
                        Block(
                            type: .callout,
                            text: content,
                            calloutIcon: alert.icon
                        )
                    )
                } else {
                    let content = quotedLines.joined(separator: "\n")
                    blocks.append(
                        Block(
                            type: .quote,
                            text: parseInline(content),
                            indent: indentLevel(from: firstLine)
                        )
                    )
                }
                continue
            }

            if let item = listItem(from: rawLine) {
                var itemBlock = Block(
                    type: item.type,
                    text: parseInline(item.text),
                    checked: item.checked,
                    indent: item.indent
                )

                let leading = leadingSpaceCount(rawLine)
                var continuation: [String] = []
                var cursor = index + 1
                while cursor < lines.count {
                    let candidate = lines[cursor]
                    if candidate.trimmingCharacters(in: .whitespaces).isEmpty { break }
                    let candidateIndent = leadingSpaceCount(candidate)
                    if candidateIndent <= leading { break }
                    if startsBlock(candidate) { break }
                    continuation.append(candidate.trimmingCharacters(in: .whitespaces))
                    cursor += 1
                }

                if !continuation.isEmpty {
                    itemBlock.text.append(.init("\n"))
                    itemBlock.text.append(parseInline(continuation.joined(separator: "\n")))
                    index = cursor
                } else {
                    index += 1
                }

                blocks.append(itemBlock)
                continue
            }

            if let pdf = pdfBlock(from: rawLine) {
                blocks.append(pdf)
                index += 1
                continue
            }

            if let image = imageBlock(from: rawLine) {
                blocks.append(image)
                index += 1
                continue
            }

            var paragraphLines = [trimmed]
            var cursor = index + 1
            while cursor < lines.count {
                let candidate = lines[cursor]
                if candidate.trimmingCharacters(in: .whitespaces).isEmpty { break }
                if startsBlock(candidate) { break }
                if candidate.contains("|"),
                   cursor + 1 < lines.count,
                   isTableSeparator(lines[cursor + 1]) {
                    break
                }
                paragraphLines.append(candidate.trimmingCharacters(in: .whitespaces))
                cursor += 1
            }

            blocks.append(
                Block(text: parseInline(paragraphLines.joined(separator: "\n")))
            )
            index = cursor
        }

        return blocks
    }

    // MARK: - Block helpers

    private static func mathBlock(lines: [String], start: Int, end: inout Int) -> Block? {
        let raw = lines[start]
        let trimmed = raw.trimmingCharacters(in: .whitespaces)

        guard trimmed.hasPrefix("$$") else { return nil }
        let indent = indentLevel(from: raw)
        let afterOpening = String(trimmed.dropFirst(2))

        if afterOpening.hasSuffix("$$") {
            let source = String(afterOpening.dropLast(2)).trimmingCharacters(in: .whitespaces)
            end = start + 1
            return Block(type: .math, text: RichText(source), indent: indent)
        }

        if !afterOpening.trimmingCharacters(in: .whitespaces).isEmpty {
            end = start + 1
            return Block(
                type: .math,
                text: RichText(afterOpening.trimmingCharacters(in: .whitespaces)),
                indent: indent
            )
        }

        var sourceLines: [String] = []
        var cursor = start + 1
        while cursor < lines.count {
            let candidate = lines[cursor].trimmingCharacters(in: .whitespaces)
            if candidate == "$$" {
                cursor += 1
                break
            }
            sourceLines.append(lines[cursor])
            cursor += 1
        }

        end = cursor
        return Block(
            type: .math,
            text: RichText(sourceLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)),
            indent: indent
        )
    }

    private static func isMathFence(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("$$")
    }

    private struct CodeFence {
        let marker: String
        let language: String
    }

    private static func codeFence(from line: String) -> CodeFence? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["```", "~~~"] where trimmed.hasPrefix(marker) {
            let language = trimmed
                .dropFirst(marker.count)
                .trimmingCharacters(in: .whitespaces)
            return CodeFence(marker: marker, language: language)
        }
        return nil
    }

    private static func heading(from line: String) -> (type: BlockType, text: String)? {
        let leading = leadingSpaceCount(line)
        guard leading <= 3 else { return nil }

        let content = line.drop { $0 == " " }
        let hashes = content.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }

        let afterHashes = content.dropFirst(hashes.count)
        guard afterHashes.first == " " || afterHashes.first == "\t" else { return nil }

        var title = afterHashes.trimmingCharacters(in: .whitespaces)
        if let closing = title.range(of: #"\s+#+\s*$"#, options: .regularExpression) {
            title.removeSubrange(closing)
        }

        let type: BlockType
        switch hashes.count {
        case 1: type = .heading1
        case 2: type = .heading2
        case 3: type = .heading3
        case 4: type = .heading4
        case 5: type = .heading5
        default: type = .heading6
        }

        return (type, title)
    }

    private static func isThematicBreak(_ trimmed: String) -> Bool {
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3,
              let first = compact.first,
              first == "-" || first == "*" || first == "_" else {
            return false
        }
        return compact.allSatisfy { $0 == first }
    }

    private static func startsWithBlockquote(_ line: String) -> Bool {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        return trimmed.first == ">"
    }

    private static func stripBlockquoteMarker(from line: String) -> String {
        var value = line.drop { $0 == " " || $0 == "\t" }
        guard value.first == ">" else { return line }
        value = value.dropFirst()
        if value.first == " " { value = value.dropFirst() }
        return String(value)
    }

    private static func calloutType(for line: String) -> (icon: String, title: String?)? {
        let pattern = #"^\[!([A-Za-z]+)\](?:\s+(.*))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: line,
                  range: NSRange(location: 0, length: (line as NSString).length)
              ),
              let typeRange = Range(match.range(at: 1), in: line) else {
            return nil
        }

        let type = String(line[typeRange]).uppercased()
        var title: String?
        if match.range(at: 2).location != NSNotFound,
           let titleRange = Range(match.range(at: 2), in: line) {
            title = String(line[titleRange]).trimmingCharacters(in: .whitespaces)
        }

        let icons: [String: String] = [
            "NOTE": "📝",
            "INFO": "ℹ️",
            "TIP": "💡",
            "IMPORTANT": "📌",
            "WARNING": "⚠️",
            "CAUTION": "🔥",
            "QUOTE": "❝",
            "ABSTRACT": "📄",
            "SUCCESS": "✅",
            "QUESTION": "❓",
            "FAILURE": "❌",
            "DANGER": "⚡",
            "BUG": "🐞",
            "EXAMPLE": "🧪",
            "TODO": "☑️"
        ]
        guard let icon = icons[type] else { return nil }
        return (icon, title)
    }

    private struct ListItem {
        let type: BlockType
        let text: String
        let checked: Bool
        let indent: Int
    }

    private static func listItem(from line: String) -> ListItem? {
        let leading = leadingSpaceCount(line)
        let indent = min(leading / 2, 8)
        let content = line.drop { $0 == " " || $0 == "\t" }

        if let regex = try? NSRegularExpression(pattern: #"^([-*+])[ \t]+(.*)$"#),
           let match = regex.firstMatch(
               in: String(content),
               range: NSRange(location: 0, length: (String(content) as NSString).length)
           ),
           let textRange = Range(match.range(at: 2), in: String(content)) {
            var value = String(String(content)[textRange])
            var checked = false
            var type: BlockType = .bulletedList

            if value.hasPrefix("[ ] ") || value.hasPrefix("[] ") {
                checked = false
                value = String(value.dropFirst(value.hasPrefix("[ ] ") ? 4 : 3))
                type = .todo
            } else if value.lowercased().hasPrefix("[x] ") {
                checked = true
                value = String(value.dropFirst(4))
                type = .todo
            }

            return ListItem(type: type, text: value, checked: checked, indent: indent)
        }

        if let regex = try? NSRegularExpression(pattern: #"^([0-9]+|[a-zA-Z]|[ivxlcdmIVXLCDM]+)[.)][ \t]+(.*)$"#),
           let match = regex.firstMatch(
               in: String(content),
               range: NSRange(location: 0, length: (String(content) as NSString).length)
           ),
           let textRange = Range(match.range(at: 2), in: String(content)) {
            return ListItem(
                type: .numberedList,
                text: String(String(content)[textRange]),
                checked: false,
                indent: indent
            )
        }

        return nil
    }

    private static func pdfBlock(from line: String) -> Block? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let pattern = #"^!\[\[([^\]|\n]+?)(?:\|([^\]\n]+))?\]\]$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: trimmed,
                  range: NSRange(location: 0, length: (trimmed as NSString).length)
              ),
              let targetRange = Range(match.range(at: 1), in: trimmed) else {
            return nil
        }

        var target = String(trimmed[targetRange])
        var anchor: String?
        if let hash = target.firstIndex(of: "#") {
            anchor = String(target[target.index(after: hash)...])
            target = String(target[..<hash])
        }

        guard (target as NSString).pathExtension.lowercased() == "pdf" else {
            return nil
        }

        var pageNumber: Int?
        if let anchor,
           let pageRegex = try? NSRegularExpression(pattern: #"(?:^|&)page=(\d+)"#),
           let pageMatch = pageRegex.firstMatch(
               in: anchor,
               range: NSRange(location: 0, length: (anchor as NSString).length)
           ),
           let pageRange = Range(pageMatch.range(at: 1), in: anchor) {
            pageNumber = Int(anchor[pageRange])
        }

        var alias = ""
        if match.range(at: 2).location != NSNotFound,
           let aliasRange = Range(match.range(at: 2), in: trimmed) {
            alias = String(trimmed[aliasRange])
        }

        return Block(
            type: .pdf,
            text: parseInline(alias),
            pdfPath: target,
            pdfPage: pageNumber
        )
    }

    private static func wikiImageBlock(from line: String) -> Block? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let pattern = #"^!\[\[([^\]|\n]+?)(?:\|([^\]\n]+))?\]\]$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: trimmed,
                  range: NSRange(location: 0, length: (trimmed as NSString).length)
              ),
              let targetRange = Range(match.range(at: 1), in: trimmed) else {
            return nil
        }

        let target = String(trimmed[targetRange])
        let ext = (target as NSString).pathExtension.lowercased()
        let imageExtensions: Set<String> = [
            "png", "jpg", "jpeg", "gif", "webp", "heic", "heif",
            "tif", "tiff", "bmp", "svg"
        ]
        guard imageExtensions.contains(ext) else { return nil }

        var caption = ""
        if match.range(at: 2).location != NSNotFound,
           let aliasRange = Range(match.range(at: 2), in: trimmed) {
            let alias = String(trimmed[aliasRange])
            if alias.allSatisfy(\.isNumber) == false {
                caption = alias
            }
        }

        return Block(
            type: .image,
            text: parseInline(caption),
            imagePath: target,
            usesWikiImageSyntax: true
        )
    }

    private static func imageBlock(from line: String) -> Block? {
        if let wikiImage = wikiImageBlock(from: line) {
            return wikiImage
        }

        let pattern = #"^\s*!\[([^\]]*)\]\((.*?)\)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: line,
                  range: NSRange(location: 0, length: (line as NSString).length)
              ),
              let altRange = Range(match.range(at: 1), in: line),
              let destinationRange = Range(match.range(at: 2), in: line) else {
            return nil
        }

        let alt = String(line[altRange])
        var destination = String(line[destinationRange]).trimmingCharacters(in: .whitespaces)
        if destination.hasPrefix("<"), destination.hasSuffix(">") {
            destination = String(destination.dropFirst().dropLast())
        } else if let space = destination.firstIndex(of: " ") {
            destination = String(destination[..<space])
        }

        return Block(
            type: .image,
            text: parseInline(alt),
            imagePath: destination.isEmpty ? nil : destination
        )
    }

    // MARK: - Tables

    private static func isTableSeparator(_ line: String) -> Bool {
        let cells = splitTableRow(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let value = cell.trimmingCharacters(in: .whitespaces)
            return value.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
        }
    }

    private static func parseTable(lines: [String], start: Int, end: inout Int) -> Block? {
        let header = splitTableRow(lines[start])
        guard !header.isEmpty else { return nil }

        var rows: [[String]] = [header]
        var cursor = start + 2

        while cursor < lines.count {
            let candidate = lines[cursor]
            if candidate.trimmingCharacters(in: .whitespaces).isEmpty { break }
            if !candidate.contains("|") { break }
            if isTableSeparator(candidate) {
                cursor += 1
                continue
            }
            rows.append(splitTableRow(candidate))
            cursor += 1
        }

        end = cursor
        return Block(
            type: .table,
            indent: indentLevel(from: lines[start]),
            table: TableData(rows: rows)
        )
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }

        var cells: [String] = []
        var current = ""
        var escaped = false

        for character in value {
            if escaped {
                if character == "|" {
                    current.append("|")
                } else {
                    current.append("\\")
                    current.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }

        if escaped {
            current.append("\\")
        }

        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    // MARK: - Misc

    private static func startsBlock(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        if isMathFence(line) { return true }
        if codeFence(from: line) != nil { return true }
        if heading(from: line) != nil { return true }
        if isThematicBreak(trimmed) { return true }
        if startsWithBlockquote(line) { return true }
        if listItem(from: line) != nil { return true }
        if pdfBlock(from: line) != nil { return true }
        if imageBlock(from: line) != nil { return true }
        return false
    }

    private static func leadingSpaceCount(_ line: String) -> Int {
        var count = 0
        for character in line {
            if character == " " {
                count += 1
            } else if character == "\t" {
                count += 2
            } else {
                break
            }
        }
        return count
    }

    private static func indentLevel(from line: String) -> Int {
        min(leadingSpaceCount(line) / 2, 8)
    }

    private static func displayLanguage(_ language: String) -> String {
        let value = language.trimmingCharacters(in: .whitespaces).lowercased()
        switch value {
        case "": return ""
        case "swift": return "Swift"
        case "js", "javascript": return "JavaScript"
        case "ts", "typescript": return "TypeScript"
        case "py", "python": return "Python"
        case "sh", "bash", "shell", "zsh": return "Bash"
        case "json": return "JSON"
        case "sql": return "SQL"
        case "html": return "HTML"
        case "css": return "CSS"
        case "md", "markdown": return "Markdown"
        default: return value.capitalized
        }
    }
}
