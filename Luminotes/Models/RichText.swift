import AppKit
import Foundation

/// A small, codable rich-text model used by every text-bearing block.
///
/// Text is stored as a list of styled runs instead of raw Markdown so the editor
/// can behave like Notion (styles are applied live) while still exporting clean
/// Markdown. Adjacent runs with identical styling are coalesced.
struct RichText: Codable, Equatable, Hashable, Sendable {
    struct Run: Codable, Equatable, Hashable, Sendable {
        var text: String
        var bold: Bool = false
        var italic: Bool = false
        var underline: Bool = false
        var strikethrough: Bool = false
        var code: Bool = false
        var link: String?
        var math: String?

        func hasSameStyle(as other: Run) -> Bool {
            bold == other.bold &&
                italic == other.italic &&
                underline == other.underline &&
                strikethrough == other.strikethrough &&
                code == other.code &&
                link == other.link &&
                math == other.math
        }
    }

    private(set) var runs: [Run]

    init(_ text: String = "") {
        runs = []
        if !text.isEmpty {
            runs = [Run(text: text)]
        }
    }

    init(runs: [Run]) {
        self.runs = []
        for run in runs {
            append(run)
        }
    }

    static let empty = RichText()

    var plainText: String {
        runs.map { run in
            if let math = run.math {
                return "$\(math)$"
            }
            return run.text
        }.joined()
    }

    var isEmpty: Bool {
        runs.isEmpty
    }

    var utf16Count: Int {
        runs.reduce(0) { count, run in
            count + (run.math == nil ? run.text.utf16.count : 1)
        }
    }

    mutating func append(_ run: Run) {
        guard !run.text.isEmpty || run.math != nil else { return }
        if run.math == nil,
           let last = runs.last,
           last.math == nil,
           last.hasSameStyle(as: run) {
            runs[runs.count - 1].text += run.text
        } else {
            runs.append(run)
        }
    }

    mutating func append(_ other: RichText) {
        for run in other.runs {
            append(run)
        }
    }

    mutating func replaceAll(with text: String) {
        runs = []
        if !text.isEmpty {
            runs = [Run(text: text)]
        }
    }

    /// Splits using UTF-16 offsets, which are what AppKit text APIs use.
    @MainActor
    func split(atUTF16 offset: Int) -> (RichText, RichText) {
        let attributed = attributedString()
        let clamped = min(max(offset, 0), attributed.length)
        let left = attributed.attributedSubstring(from: NSRange(location: 0, length: clamped))
        let right = attributed.attributedSubstring(
            from: NSRange(location: clamped, length: attributed.length - clamped)
        )
        return (RichText(attributed: left), RichText(attributed: right))
    }

    /// Removes a UTF-16 range. Used when dismissing the slash-command query.
    @MainActor
    func removingUTF16Range(_ range: NSRange) -> RichText {
        let attributed = NSMutableAttributedString(attributedString: attributedString())
        let safe = NSIntersectionRange(range, NSRange(location: 0, length: attributed.length))
        attributed.replaceCharacters(in: safe, with: "")
        return RichText(attributed: attributed)
    }

    /// Adds plain text at the end while preserving the previous runs.
    func appending(_ text: RichText) -> RichText {
        var copy = self
        copy.append(text)
        return copy
    }

    // MARK: - AppKit bridging

    @MainActor
    func attributedString(
        baseFont: NSFont = .systemFont(ofSize: 16),
        color: NSColor = .labelColor,
        paragraphStyle: NSParagraphStyle? = nil,
        allowsInlineStyles: Bool = true,
        mathDisplayStyle: Bool = false
    ) -> NSAttributedString {
        let style = paragraphStyle ?? RichText.defaultParagraphStyle
        let result = NSMutableAttributedString()

        let sourceRuns = runs.isEmpty ? [Run(text: "")] : runs
        for run in sourceRuns {
            if allowsInlineStyles, let latex = run.math, !latex.isEmpty {
                let mathFontSize = max(baseFont.pointSize - 1, 11)
                if let image = MathImageRenderer.shared.image(
                    latex: latex,
                    fontSize: mathFontSize,
                    color: color,
                    displayStyle: mathDisplayStyle
                ) {
                    let descent = MathImageRenderer.shared.descent(
                        latex: latex,
                        fontSize: mathFontSize,
                        displayStyle: mathDisplayStyle
                    )
                    let attachment = NSTextAttachment()
                    attachment.image = image
                    attachment.bounds = CGRect(
                        x: 0,
                        y: -descent,
                        width: image.size.width,
                        height: image.size.height
                    )
                    let attachmentString = NSMutableAttributedString(attachment: attachment)
                    attachmentString.addAttributes(
                        [
                            .luminotesMath: latex,
                            .font: baseFont,
                            .foregroundColor: color,
                            .paragraphStyle: style
                        ],
                        range: NSRange(location: 0, length: attachmentString.length)
                    )
                    result.append(attachmentString)
                    continue
                } else {
                    result.append(
                        NSAttributedString(
                            string: "$\(latex)$",
                            attributes: [
                                .font: baseFont,
                                .foregroundColor: color,
                                .paragraphStyle: style
                            ]
                        )
                    )
                    continue
                }
            }

            guard !run.text.isEmpty else { continue }

            var attributes: [NSAttributedString.Key: Any] = [
                .font: font(for: run, baseFont: baseFont, allowsInlineStyles: allowsInlineStyles),
                .foregroundColor: color,
                .paragraphStyle: style
            ]

            if allowsInlineStyles {
                if run.bold { attributes[.luminotesBold] = true }
                if run.italic { attributes[.luminotesItalic] = true }
                if run.underline { attributes[.luminotesUnderline] = true }
                if run.strikethrough {
                    attributes[.luminotesStrikethrough] = true
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
                if run.code {
                    attributes[.luminotesCode] = true
                    attributes[.backgroundColor] = NSColor.luminotesInlineCodeBackground
                }
                if run.underline {
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                if let link = run.link, let url = URL(string: link) {
                    attributes[.link] = url
                    attributes[.foregroundColor] = NSColor.controlAccentColor
                }
            }

            result.append(NSAttributedString(string: run.text, attributes: attributes))
        }

        return result
    }

    init(attributed: NSAttributedString) {
        runs = []
        let fullRange = NSRange(location: 0, length: attributed.length)
        guard fullRange.length > 0 else { return }

        attributed.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            if let latex = attributes[.luminotesMath] as? String {
                append(
                    Run(
                        text: "",
                        math: latex
                    )
                )
                return
            }

            let text = (attributed.string as NSString).substring(with: range)
            guard !text.isEmpty else { return }

            let link: String?
            if let url = attributes[.link] as? URL {
                link = url.absoluteString
            } else if let string = attributes[.link] as? String {
                link = string
            } else {
                link = nil
            }

            append(
                Run(
                    text: text,
                    bold: attributes[.luminotesBold] as? Bool ?? false,
                    italic: attributes[.luminotesItalic] as? Bool ?? false,
                    underline: attributes[.luminotesUnderline] as? Bool ?? false,
                    strikethrough: attributes[.luminotesStrikethrough] as? Bool ?? false,
                    code: attributes[.luminotesCode] as? Bool ?? false,
                    link: link
                )
            )
        }
    }

    static let defaultParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.paragraphSpacing = 0
        return style
    }()

    private func font(for run: Run, baseFont: NSFont, allowsInlineStyles: Bool) -> NSFont {
        guard allowsInlineStyles else { return baseFont }

        if run.code {
            let weight: NSFont.Weight = run.bold ? .semibold : .regular
            return .monospacedSystemFont(ofSize: max(baseFont.pointSize - 1, 11), weight: weight)
        }

        var traits: NSFontDescriptor.SymbolicTraits = []
        if run.bold { traits.insert(.bold) }
        if run.italic { traits.insert(.italic) }

        guard !traits.isEmpty else { return baseFont }
        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: baseFont.pointSize) ?? baseFont
    }

    // MARK: - Markdown

    var markdown: String {
        runs.map { run in
            if let math = run.math {
                return "$\(math)$"
            }
            guard !run.text.isEmpty else { return "" }
            var value = run.text
            if run.code {
                value = "`\(value)`"
            } else {
                if run.bold { value = "**\(value)**" }
                if run.italic { value = "*\(value)*" }
                if run.strikethrough { value = "~~\(value)~~" }
            }
            if run.underline { value = "<u>\(value)</u>" }
            if let link = run.link {
                if let wiki = Self.wikiMarkdown(link: link, display: value) {
                    value = wiki
                } else {
                    value = "[\(value)](\(link))"
                }
            }
            return value
        }.joined()
    }

    private static func wikiMarkdown(link: String, display: String) -> String? {
        guard let components = URLComponents(string: link),
              components.scheme == "luminotes",
              components.host == "open" else {
            return nil
        }

        let items = components.queryItems ?? []
        guard let target = items.first(where: { $0.name == "target" })?.value,
              !target.isEmpty else {
            return nil
        }

        let anchor = items.first(where: { $0.name == "anchor" })?.value
        let embed = items.first(where: { $0.name == "embed" })?.value == "1"
        let targetWithAnchor = anchor.map { "\(target)#\($0)" } ?? target
        let prefix = embed ? "!" : ""

        if display == target || display == targetWithAnchor {
            return "\(prefix)[[\(targetWithAnchor)]]"
        }
        return "\(prefix)[[\(targetWithAnchor)|\(display)]]"
    }
}

extension NSAttributedString.Key {
    static let luminotesBold = NSAttributedString.Key("Luminotes.bold")
    static let luminotesItalic = NSAttributedString.Key("Luminotes.italic")
    static let luminotesUnderline = NSAttributedString.Key("Luminotes.underline")
    static let luminotesStrikethrough = NSAttributedString.Key("Luminotes.strikethrough")
    static let luminotesCode = NSAttributedString.Key("Luminotes.code")
    static let luminotesMath = NSAttributedString.Key("Luminotes.math")
}

extension NSColor {
    static var luminotesInlineCodeBackground: NSColor {
        NSColor(name: NSColor.Name("LuminotesInlineCodeBackground")) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(calibratedWhite: 1, alpha: 0.09)
                : NSColor(calibratedWhite: 0.25, alpha: 0.07)
        }
    }
}
