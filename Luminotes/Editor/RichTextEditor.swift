import AppKit
import SwiftUI

/// A single block's text editor. It wraps a TextKit view so Luminotes can
/// provide live inline styles, precise caret control, and keyboard navigation
/// between blocks while keeping SwiftUI's declarative layout.
struct RichTextEditor: NSViewRepresentable {
    @ObservedObject var viewModel: EditorViewModel
    let block: Block
    let placeholder: String
    let minHeight: CGFloat
    @AppStorage("Luminotes.justifyText") private var justifyText = true
    @AppStorage(BlockTypography.bodyFontSizeKey) private var bodyFontSize = 16.0
    @AppStorage(BlockTypography.lineSpacingKey) private var lineSpacing = 4.0
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, blockID: block.id)
    }

    func makeNSView(context: Context) -> BlockTextContainerView {
        let textView = BlockTextView()
        let container = BlockTextContainerView(textView: textView)
        container.minimumHeight = minHeight

        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = []
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.usesFindBar = true

        textView.delegate = context.coordinator
        textView.onKeyDown = { [weak coordinator = context.coordinator] event in
            coordinator?.handleKey(event) ?? false
        }
        textView.onMathAttachmentClick = { [weak coordinator = context.coordinator] index, latex in
            coordinator?.presentInlineMathEditor(at: index, latex: latex) ?? false
        }
        textView.onLinkClick = { [weak viewModel] url in
            viewModel?.openLink(url) ?? false
        }

        context.coordinator.attach(textView: textView, container: container)
        context.coordinator.update(block: block, placeholder: placeholder, minHeight: minHeight, force: true, justified: justifyText, fontSize: bodyFontSize, lineSpacing: lineSpacing, colorScheme: colorScheme)
        return container
    }

    func updateNSView(_ container: BlockTextContainerView, context: Context) {
        context.coordinator.update(block: block, placeholder: placeholder, minHeight: minHeight, force: false, justified: justifyText, fontSize: bodyFontSize, lineSpacing: lineSpacing, colorScheme: colorScheme)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: BlockTextContainerView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let height = nsView.requiredHeight(for: width)
        return CGSize(width: width, height: height)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let viewModel: EditorViewModel
        private var blockID: UUID
        private weak var textView: BlockTextView?
        private weak var container: BlockTextContainerView?

        private var lastPublished: RichText?
        private var lastType: BlockType?
        private var lastPlaceholder: String?
        private var lastMinHeight: CGFloat = 0
        private var lastBaseFont: NSFont?
        private var lastJustified = false
        private var lastFontSize: Double = 0
        private var lastLineSpacing: Double = 0
        private var lastColorScheme: ColorScheme?
        private var isProgrammaticUpdate = false
        private var handledFocusToken: UUID?
        private var suppressedSlashLocation: Int?
        private var inlineMathPopover: NSPopover?

        init(viewModel: EditorViewModel, blockID: UUID) {
            self.viewModel = viewModel
            self.blockID = blockID
        }

        func attach(textView: BlockTextView, container: BlockTextContainerView) {
            self.textView = textView
            self.container = container
        }

        func update(
            block: Block,
            placeholder: String,
            minHeight: CGFloat,
            force: Bool,
            justified: Bool,
            fontSize: Double,
            lineSpacing: Double,
            colorScheme: ColorScheme
        ) {
            guard let textView, let container else { return }
            blockID = block.id
            container.minimumHeight = minHeight

            let baseFont = BlockTypography.font(
                for: block.type,
                bodyFontSize: CGFloat(fontSize)
            )
            let textColor = BlockTypography.color(for: block.type)
            let paragraphStyle = BlockTypography.paragraphStyle(
                for: block.type,
                justified: justified,
                lineSpacing: CGFloat(lineSpacing)
            )
            let fontChanged = lastBaseFont != baseFont

            textView.placeholder = placeholder
            textView.baseFont = baseFont
            textView.insertionPointColor = .controlAccentColor
            textView.textContainerInset = NSSize(width: 0, height: block.type == .code ? 8 : 2)

            let isMonospaced = block.type == .code || block.type == .math
            textView.isAutomaticQuoteSubstitutionEnabled = !isMonospaced
            textView.isAutomaticDashSubstitutionEnabled = !isMonospaced
            textView.isAutomaticTextReplacementEnabled = !isMonospaced
            textView.isAutomaticSpellingCorrectionEnabled = !isMonospaced
            textView.isContinuousSpellCheckingEnabled = !isMonospaced
            textView.isGrammarCheckingEnabled = !isMonospaced

            let needsTextUpdate = force ||
                lastPublished != block.text ||
                lastType != block.type ||
                lastPlaceholder != placeholder ||
                abs(lastMinHeight - minHeight) > 0.5 ||
                lastJustified != justified ||
                lastFontSize != fontSize ||
                lastLineSpacing != lineSpacing ||
                lastColorScheme != colorScheme

            if needsTextUpdate {
                let previousSelection = textView.selectedRange()
                let wasFirstResponder = textView.window?.firstResponder === textView

                isProgrammaticUpdate = true
                let attributed = block.text.attributedString(
                    baseFont: baseFont,
                    color: textColor,
                    paragraphStyle: paragraphStyle,
                    allowsInlineStyles: block.type.supportsInlineStyles
                )
                textView.textStorage?.setAttributedString(attributed)

                let length = textView.string.utf16.count
                let location = min(previousSelection.location, length)
                textView.setSelectedRange(NSRange(location: location, length: 0))
                textView.typingAttributes = defaultTypingAttributes(
                    font: baseFont,
                    color: textColor,
                    paragraphStyle: paragraphStyle
                )
                isProgrammaticUpdate = false

                lastPublished = block.text
                lastType = block.type
                lastPlaceholder = placeholder
                lastMinHeight = minHeight
                lastBaseFont = baseFont
                lastJustified = justified
                lastFontSize = fontSize
                lastLineSpacing = lineSpacing
                lastColorScheme = colorScheme

                if wasFirstResponder {
                    textView.setSelectedRange(NSRange(location: location, length: 0))
                }

                container.invalidateIntrinsicContentSize()
                textView.needsDisplay = true
            } else if fontChanged {
                lastBaseFont = baseFont
                textView.typingAttributes = defaultTypingAttributes(
                    font: baseFont,
                    color: textColor,
                    paragraphStyle: paragraphStyle
                )
                textView.needsDisplay = true
                container.invalidateIntrinsicContentSize()
            }

            if let request = viewModel.focusRequest,
               request.blockID == blockID,
               request.token != handledFocusToken {
                handledFocusToken = request.token
                DispatchQueue.main.async { [weak self, weak textView] in
                    guard let self, let textView, let window = textView.window else { return }
                    window.makeFirstResponder(textView)
                    let length = textView.string.utf16.count
                    let location = min(max(request.selection ?? length, 0), length)
                    textView.setSelectedRange(NSRange(location: location, length: 0))
                    textView.scrollRangeToVisible(NSRange(location: location, length: 0))
                    self.viewModel.consumeFocusRequest(request.token)
                    self.container?.invalidateIntrinsicContentSize()
                }
            }
        }

        /// Applies a model change directly to the live text view. This keeps
        /// fast typing deterministic when a Markdown shortcut changes a block's
        /// type in the middle of a keystroke.
        private func applyModelBlock(_ block: Block, selection: Int) {
            guard let textView, let container else { return }
            let baseFont = BlockTypography.font(for: block.type)
            let textColor = BlockTypography.color(for: block.type)
            let paragraphStyle = BlockTypography.paragraphStyle(
                for: block.type,
                justified: lastJustified
            )

            isProgrammaticUpdate = true
            textView.textStorage?.setAttributedString(
                block.text.attributedString(
                    baseFont: baseFont,
                    color: textColor,
                    paragraphStyle: paragraphStyle,
                    allowsInlineStyles: block.type.supportsInlineStyles
                )
            )
            let length = textView.string.utf16.count
            textView.setSelectedRange(NSRange(location: min(max(selection, 0), length), length: 0))
            textView.typingAttributes = defaultTypingAttributes(
                font: baseFont,
                color: textColor,
                paragraphStyle: paragraphStyle
            )
            textView.placeholder = block.placeholder
            textView.baseFont = baseFont
            textView.textContainerInset = NSSize(width: 0, height: block.type == .code ? 8 : 2)
            isProgrammaticUpdate = false

            lastPublished = block.text
            lastType = block.type
            lastPlaceholder = block.placeholder
            lastBaseFont = baseFont
            textView.needsDisplay = true
            container.invalidateIntrinsicContentSize()
        }

        private func defaultTypingAttributes(
            font: NSFont,
            color: NSColor,
            paragraphStyle: NSParagraphStyle
        ) -> [NSAttributedString.Key: Any] {
            [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]
        }

        // MARK: - NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticUpdate,
                  let textView,
                  let storage = textView.textStorage,
                  !textView.hasMarkedText() else {
                return
            }

            if lastType != .code && lastType != .math {
                autoformatInlineMarkdown(in: textView, storage: storage)
                autoformatInlineMath(in: textView, storage: storage)
            }

            let text = RichText(attributed: textView.attributedString())
            if viewModel.handleMarkdownShortcut(blockID, text: text) {
                if let updated = viewModel.note.blocks.first(where: { $0.id == blockID }) {
                    applyModelBlock(updated, selection: 0)
                } else {
                    lastPublished = nil
                }
                container?.invalidateIntrinsicContentSize()
                return
            }

            lastPublished = text
            viewModel.updateText(blockID, text: text)
            updateSlashContext()
            container?.invalidateIntrinsicContentSize()
            textView.needsDisplay = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isProgrammaticUpdate else { return }
            updateSlashContext()
        }

        func textDidBeginEditing(_ notification: Notification) {
            suppressedSlashLocation = nil
            textView?.needsDisplay = true
            viewModel.focusChanged(to: blockID)
            updateSlashContext()
        }

        func textDidEndEditing(_ notification: Notification) {
            textView?.needsDisplay = true
            if viewModel.focusedBlockID == blockID {
                viewModel.focusChanged(to: nil)
            }
        }

        // MARK: - Inline math editing

        func presentInlineMathEditor(at index: Int, latex: String) -> Bool {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  index < (textView.textStorage?.length ?? 0) else {
                return false
            }

            inlineMathPopover?.performClose(nil)

            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = true

            let editor = InlineMathEditorView(
                initialLatex: latex,
                onSave: { [weak self] newLatex in
                    self?.replaceInlineMath(at: index, latex: newLatex)
                    popover.performClose(nil)
                },
                onChange: { [weak self] newLatex in
                    guard !newLatex.isEmpty else { return }
                    self?.replaceInlineMath(at: index, latex: newLatex, refocus: false)
                },
                onCancel: { [weak self] in
                    self?.replaceInlineMath(at: index, latex: latex)
                    popover.performClose(nil)
                }
            )

            let hosting = NSHostingController(rootView: editor)
            popover.contentViewController = hosting
            popover.contentSize = NSSize(width: 368, height: 150)

            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: index, length: 1),
                actualCharacterRange: nil
            )
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x += textView.textContainerInset.width
            rect.origin.y += textView.textContainerInset.height
            inlineMathPopover = popover
            popover.show(relativeTo: rect, of: textView, preferredEdge: .maxY)
            return true
        }

        private func inlineMathNearCaret() -> (index: Int, latex: String)? {
            guard let textView, let storage = textView.textStorage else { return nil }
            let selection = textView.selectedRange()
            let candidates = [selection.location - 1, selection.location]
            for index in candidates where index >= 0 && index < storage.length {
                if let latex = storage.attribute(.luminotesMath, at: index, effectiveRange: nil) as? String {
                    return (index, latex)
                }
            }
            return nil
        }

        private func replaceInlineMath(at index: Int, latex: String, refocus: Bool = true) {
            guard let textView, let storage = textView.textStorage else { return }
            let length = storage.length
            guard index < length,
                  storage.attribute(.luminotesMath, at: index, effectiveRange: nil) != nil else {
                return
            }

            let type = lastType ?? .paragraph
            let baseFont = BlockTypography.font(for: type)
            let color = BlockTypography.color(for: type)
            let paragraphStyle = BlockTypography.paragraphStyle(for: type, justified: lastJustified)

            isProgrammaticUpdate = true
            if latex.isEmpty {
                storage.replaceCharacters(in: NSRange(location: index, length: 1), with: "")
                textView.setSelectedRange(NSRange(location: min(index, storage.length), length: 0))
            } else {
                let replacement = RichText(runs: [RichText.Run(text: "", math: latex)]).attributedString(
                    baseFont: baseFont,
                    color: color,
                    paragraphStyle: paragraphStyle,
                    allowsInlineStyles: true
                )
                storage.replaceCharacters(in: NSRange(location: index, length: 1), with: replacement)
                textView.setSelectedRange(
                    NSRange(location: min(index + replacement.length, storage.length), length: 0)
                )
            }
            isProgrammaticUpdate = false

            textView.typingAttributes = defaultTypingAttributes(
                font: baseFont,
                color: color,
                paragraphStyle: paragraphStyle
            )
            publishCurrentText()
            if refocus {
                textView.window?.makeFirstResponder(textView)
            }
            container?.invalidateIntrinsicContentSize()
        }

        // MARK: - Keyboard

        func handleKey(_ event: NSEvent) -> Bool {
            guard let textView else { return false }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if viewModel.slashMenu?.blockID == blockID {
                switch event.keyCode {
                case 126: // up
                    viewModel.moveSlashSelection(-1)
                    return true
                case 125: // down
                    viewModel.moveSlashSelection(1)
                    return true
                case 36: // return
                    viewModel.chooseSelectedSlashCommand()
                    return true
                case 53: // escape
                    suppressedSlashLocation = currentSlashContext()?.range.location
                    viewModel.closeSlashMenu(blockID: blockID)
                    return true
                default:
                    break
                }
            }

            if flags.contains(.command) {
                if flags.contains(.shift), event.keyCode == 126 {
                    viewModel.moveBlockBy(blockID, offset: -1)
                    return true
                }
                if flags.contains(.shift), event.keyCode == 125 {
                    viewModel.moveBlockBy(blockID, offset: 1)
                    return true
                }
                if event.keyCode == 36 {
                    _ = viewModel.insertParagraph(after: blockID)
                    return true
                }

                let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
                if flags.contains(.shift), key == "m",
                   let math = inlineMathNearCaret() {
                    _ = presentInlineMathEditor(at: math.index, latex: math.latex)
                    return true
                }
                switch key {
                case "n":
                    viewModel.newNote()
                    return true
                case "r" where flags.contains(.shift):
                    viewModel.focusTitle()
                    return true
                case "b" where !flags.contains(.shift):
                    toggleTrait(.bold)
                    return true
                case "i" where !flags.contains(.shift):
                    toggleTrait(.italic)
                    return true
                case "u" where !flags.contains(.shift):
                    toggleTrait(.underline)
                    return true
                case "e" where flags.contains(.option):
                    viewModel.exportMarkdown()
                    return true
                case "e" where !flags.contains(.shift):
                    toggleTrait(.code)
                    return true
                case "x" where flags.contains(.shift):
                    toggleTrait(.strikethrough)
                    return true
                default:
                    break
                }
            }

            switch event.keyCode {
            case 36: // return
                if flags.contains(.shift) || lastType == .code || lastType == .math {
                    textView.insertText("\n", replacementRange: textView.selectedRange())
                } else {
                    splitBlockAtCaret()
                }
                return true

            case 48: // tab
                if lastType == .code || lastType == .math {
                    textView.insertText("    ", replacementRange: textView.selectedRange())
                } else {
                    viewModel.indentBlock(blockID, delta: flags.contains(.shift) ? -1 : 1)
                }
                return true

            case 51: // delete
                if textView.selectedRange().length == 0, textView.selectedRange().location == 0 {
                    viewModel.handleBackspaceAtStart(blockID)
                    return true
                }
                return false

            case 126: // up
                if textView.selectedRange().length == 0, textView.selectedRange().location == 0 {
                    viewModel.focusPrevious(from: blockID)
                    return true
                }
                return false

            case 125: // down
                if textView.selectedRange().length == 0,
                   textView.selectedRange().location == textView.string.utf16.count {
                    viewModel.focusNext(from: blockID)
                    return true
                }
                return false

            case 123: // left
                if textView.selectedRange().length == 0, textView.selectedRange().location == 0 {
                    viewModel.focusPrevious(from: blockID)
                    return true
                }
                return false

            case 124: // right
                if textView.selectedRange().length == 0,
                   textView.selectedRange().location == textView.string.utf16.count {
                    viewModel.focusNext(from: blockID)
                    return true
                }
                return false

            default:
                return false
            }
        }

        private func splitBlockAtCaret() {
            guard let textView else { return }
            let selection = textView.selectedRange()
            let attributed = textView.attributedString()
            let leftRange = NSRange(location: 0, length: selection.location)
            let rightLocation = min(selection.location + selection.length, attributed.length)
            let rightRange = NSRange(location: rightLocation, length: attributed.length - rightLocation)

            let before = RichText(attributed: attributed.attributedSubstring(from: leftRange))
            let after = RichText(attributed: attributed.attributedSubstring(from: rightRange))
            viewModel.handleEnter(blockID, before: before, after: after)
        }

        // MARK: - Inline styles

        private enum InlineTrait {
            case bold
            case italic
            case underline
            case strikethrough
            case code

            var attributeKey: NSAttributedString.Key {
                switch self {
                case .bold: return .luminotesBold
                case .italic: return .luminotesItalic
                case .underline: return .luminotesUnderline
                case .strikethrough: return .luminotesStrikethrough
                case .code: return .luminotesCode
                }
            }
        }

        private func toggleTrait(_ trait: InlineTrait) {
            guard let textView else { return }
            let selection = textView.selectedRange()

            if selection.length == 0 {
                var attributes = textView.typingAttributes
                let isOn = attributes[trait.attributeKey] as? Bool ?? false
                attributes[trait.attributeKey] = isOn ? nil : true
                attributes[.font] = font(for: attributes)
                textView.typingAttributes = attributes
                return
            }

            let isOn = textView.textStorage?.attribute(
                trait.attributeKey,
                at: selection.location,
                effectiveRange: nil
            ) as? Bool ?? false

            applyTrait(trait, add: !isOn, range: selection)
            publishCurrentText()
        }

        private func applyTrait(_ trait: InlineTrait, add: Bool, range: NSRange) {
            guard let textView, let storage = textView.textStorage else { return }
            let safe = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
            guard safe.length > 0 else { return }

            storage.beginEditing()
            storage.enumerateAttributes(in: safe, options: []) { attributes, subrange, _ in
                var updated = attributes
                updated[trait.attributeKey] = add ? true : nil

                switch trait {
                case .underline:
                    updated[.underlineStyle] = add ? NSUnderlineStyle.single.rawValue : nil
                case .strikethrough:
                    updated[.strikethroughStyle] = add ? NSUnderlineStyle.single.rawValue : nil
                case .code:
                    updated[.backgroundColor] = add ? NSColor.luminotesInlineCodeBackground : nil
                default:
                    break
                }

                updated[.font] = font(for: updated)
                storage.setAttributes(updated, range: subrange)
            }
            storage.endEditing()
        }

        private func font(for attributes: [NSAttributedString.Key: Any]) -> NSFont {
            let base = lastBaseFont ?? .systemFont(ofSize: 16)
            let bold = attributes[.luminotesBold] as? Bool ?? false
            let italic = attributes[.luminotesItalic] as? Bool ?? false
            let code = attributes[.luminotesCode] as? Bool ?? false

            if code {
                return .monospacedSystemFont(
                    ofSize: max(base.pointSize - 1, 11),
                    weight: bold ? .semibold : .regular
                )
            }

            var traits: NSFontDescriptor.SymbolicTraits = []
            if bold { traits.insert(.bold) }
            if italic { traits.insert(.italic) }
            guard !traits.isEmpty else { return base }
            let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
            return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
        }

        private func publishCurrentText() {
            guard let textView else { return }
            let text = RichText(attributed: textView.attributedString())
            lastPublished = text
            viewModel.updateText(blockID, text: text)
            container?.invalidateIntrinsicContentSize()
            textView.needsDisplay = true
        }

        // MARK: - Markdown autoformatting

        private struct InlinePattern {
            let regex: NSRegularExpression
            let trait: InlineTrait?
            let isLink: Bool

            init(pattern: String, trait: InlineTrait? = nil, isLink: Bool = false) {
                regex = try! NSRegularExpression(pattern: pattern)
                self.trait = trait
                self.isLink = isLink
            }
        }

        private func autoformatInlineMarkdown(in textView: BlockTextView, storage: NSTextStorage) {
            guard textView.selectedRange().length == 0 else { return }

            let patterns: [InlinePattern] = [
                InlinePattern(pattern: "\\[([^\\]\\n]+?)\\]\\(([^)\\s]+)\\)", isLink: true),
                InlinePattern(pattern: "\\*\\*(?=\\S)([^*\\n]+?)(?<=\\S)\\*\\*", trait: .bold),
                InlinePattern(pattern: "~~(?=\\S)([^~\\n]+?)(?<=\\S)~~", trait: .strikethrough),
                InlinePattern(pattern: "`(?=\\S)([^`\\n]+?)(?<=\\S)`", trait: .code),
                InlinePattern(pattern: "(?<!\\*)\\*(?!\\*)(?=\\S)([^*\\n]+?)(?<=\\S)\\*(?!\\*)", trait: .italic),
                InlinePattern(pattern: "(?<!\\w)_(?!_)(?=\\S)([^_\\n]+?)(?<=\\S)_(?!\\w)", trait: .italic)
            ]

            var cursor = textView.selectedRange().location
            var didChange = false

            for pattern in patterns {
                let result = apply(pattern: pattern, storage: storage, cursor: cursor)
                cursor = result.cursor
                didChange = didChange || result.changed
            }

            guard didChange else { return }

            textView.setSelectedRange(NSRange(location: min(cursor, storage.length), length: 0))
            textView.typingAttributes = defaultTypingAttributes(
                font: BlockTypography.font(for: lastType ?? .paragraph),
                color: BlockTypography.color(for: lastType ?? .paragraph),
                paragraphStyle: BlockTypography.paragraphStyle(for: lastType ?? .paragraph, justified: lastJustified)
            )
            textView.needsDisplay = true
            container?.invalidateIntrinsicContentSize()
        }

        private func autoformatInlineMath(in textView: BlockTextView, storage: NSTextStorage) {
            guard textView.selectedRange().length == 0 else { return }
            let source = storage.string
            guard source.contains("$") else { return }

            let pattern = #"(?<!\$)\$(?!\$)([^$\n]+?)(?<!\\)\$(?!\$)"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let nsSource = source as NSString
            let matches = regex.matches(in: source, range: NSRange(location: 0, length: nsSource.length))
            guard !matches.isEmpty else { return }

            let type = lastType ?? .paragraph
            let baseFont = BlockTypography.font(for: type)
            let color = BlockTypography.color(for: type)
            let paragraphStyle = BlockTypography.paragraphStyle(for: type, justified: lastJustified)
            var cursor = textView.selectedRange().location

            for match in matches.reversed() {
                guard match.numberOfRanges >= 2 else { continue }
                let latex = nsSource.substring(with: match.range(at: 1))
                let replacement = RichText(runs: [RichText.Run(text: "", math: latex)]).attributedString(
                    baseFont: baseFont,
                    color: color,
                    paragraphStyle: paragraphStyle,
                    allowsInlineStyles: true
                )
                guard replacement.length == 1,
                      replacement.attribute(.luminotesMath, at: 0, effectiveRange: nil) != nil else {
                    continue
                }

                let matchEnd = match.range.location + match.range.length
                let replacementLength = replacement.length
                if cursor >= matchEnd {
                    cursor += replacementLength - match.range.length
                } else if cursor > match.range.location {
                    cursor = match.range.location + replacementLength
                }

                storage.replaceCharacters(in: match.range, with: replacement)
            }

            textView.setSelectedRange(NSRange(location: min(max(cursor, 0), storage.length), length: 0))
            textView.typingAttributes = defaultTypingAttributes(
                font: baseFont,
                color: color,
                paragraphStyle: paragraphStyle
            )
            textView.needsDisplay = true
            container?.invalidateIntrinsicContentSize()
        }

        private func apply(
            pattern: InlinePattern,
            storage: NSTextStorage,
            cursor: Int
        ) -> (cursor: Int, changed: Bool) {
            let text = storage.string as NSString
            let matches = pattern.regex.matches(
                in: storage.string,
                range: NSRange(location: 0, length: text.length)
            )
            guard !matches.isEmpty else { return (cursor, false) }

            var newCursor = cursor
            var removedBeforeCursor = 0
            var changed = false

            for match in matches.reversed() {
                guard match.numberOfRanges >= 2 else { continue }
                let contentRange = match.range(at: 1)
                guard contentRange.location != NSNotFound, contentRange.length > 0 else { continue }

                let openingLength = contentRange.location - match.range.location
                let closingLength = (match.range.location + match.range.length) - (contentRange.location + contentRange.length)
                let matchEnd = match.range.location + match.range.length
                let contentEnd = contentRange.location + contentRange.length

                if cursor >= matchEnd {
                    removedBeforeCursor += openingLength + closingLength
                } else if cursor > contentEnd {
                    newCursor = contentEnd - openingLength
                } else if cursor > contentRange.location {
                    removedBeforeCursor += openingLength
                }

                if pattern.isLink {
                    applyLink(
                        to: contentRange,
                        url: text.substring(with: match.range(at: 2)),
                        storage: storage
                    )
                } else if let trait = pattern.trait {
                    applyTrait(trait, add: true, range: contentRange)
                }

                if closingLength > 0 {
                    storage.deleteCharacters(
                        in: NSRange(
                            location: contentRange.location + contentRange.length,
                            length: closingLength
                        )
                    )
                }
                if openingLength > 0 {
                    storage.deleteCharacters(
                        in: NSRange(location: match.range.location, length: openingLength)
                    )
                }

                changed = true
            }

            return (max(0, newCursor - removedBeforeCursor), changed)
        }

        private func applyLink(to range: NSRange, url: String, storage: NSTextStorage) {
            guard let linkURL = URL(string: url) else { return }
            let safe = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
            guard safe.length > 0 else { return }

            storage.beginEditing()
            storage.enumerateAttributes(in: safe, options: []) { attributes, subrange, _ in
                var updated = attributes
                updated[.link] = linkURL
                updated[.foregroundColor] = NSColor.controlAccentColor
                updated[.underlineStyle] = NSUnderlineStyle.single.rawValue
                storage.setAttributes(updated, range: subrange)
            }
            storage.endEditing()
        }

        // MARK: - Slash menu

        private func currentSlashContext() -> (range: NSRange, query: String)? {
            guard let textView else { return nil }
            let nsText = textView.string as NSString
            let caret = min(textView.selectedRange().location, nsText.length)
            guard caret > 0 else { return nil }

            let before = nsText.substring(to: caret) as NSString
            let slashRange = before.range(of: "/", options: .backwards)
            guard slashRange.location != NSNotFound else { return nil }
            let slashLocation = slashRange.location

            if slashLocation > 0 {
                let previous = nsText.substring(with: NSRange(location: slashLocation - 1, length: 1))
                if !previous.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return nil
                }
            }

            let queryLength = caret - slashLocation - 1
            guard queryLength >= 0 else { return nil }
            let query = nsText.substring(with: NSRange(location: slashLocation + 1, length: queryLength))
            if query.contains(where: { $0.isWhitespace || $0.isNewline }) {
                return nil
            }

            return (NSRange(location: slashLocation, length: caret - slashLocation), query)
        }

        private func updateSlashContext() {
            if lastType == .code || lastType == .math {
                suppressedSlashLocation = nil
                viewModel.closeSlashMenu(blockID: blockID)
                return
            }

            guard let context = currentSlashContext() else {
                suppressedSlashLocation = nil
                viewModel.closeSlashMenu(blockID: blockID)
                return
            }

            if let suppressedSlashLocation,
               suppressedSlashLocation == context.range.location {
                return
            }

            suppressedSlashLocation = nil
            viewModel.updateSlashMenu(blockID: blockID, range: context.range, query: context.query)
        }
    }
}

final class BlockTextView: NSTextView {
    var placeholder: String?
    var baseFont: NSFont = .systemFont(ofSize: 16)
    var onKeyDown: ((NSEvent) -> Bool)?
    var onMathAttachmentClick: ((Int, String) -> Bool)?
    var onLinkClick: ((URL) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        if let storage = textStorage,
           let layoutManager,
           let textContainer {
            let point = convert(event.locationInWindow, from: nil)
            let containerPoint = NSPoint(
                x: point.x - textContainerInset.width,
                y: point.y - textContainerInset.height
            )
            let index = layoutManager.characterIndex(
                for: containerPoint,
                in: textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )

            if index < storage.length {
                if event.modifierFlags.contains(.command),
                   let url = storage.attribute(.link, at: index, effectiveRange: nil) as? URL,
                   onLinkClick?(url) == true {
                    return
                }

                if let onMathAttachmentClick,
                   let latex = storage.attribute(.luminotesMath, at: index, effectiveRange: nil) as? String,
                   onMathAttachmentClick(index, latex) {
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard string.isEmpty,
              let placeholder,
              !placeholder.isEmpty,
              window?.firstResponder === self else {
            return
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.luminotesTertiaryText
        ]
        let origin = NSPoint(
            x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
            y: textContainerInset.height
        )
        (placeholder as NSString).draw(at: origin, withAttributes: attributes)
    }
}

final class BlockTextContainerView: NSView {
    let textView: BlockTextView
    var minimumHeight: CGFloat = 26
    private var cachedHeight: CGFloat = 0
    private var cachedWidth: CGFloat = 0
    private var heightDirty = true

    init(textView: BlockTextView) {
        self.textView = textView
        super.init(frame: .zero)
        addSubview(textView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        let width = bounds.width > 1 ? bounds.width : 640
        return NSSize(width: NSView.noIntrinsicMetric, height: requiredHeight(for: width))
    }

    override func invalidateIntrinsicContentSize() {
        heightDirty = true
        super.invalidateIntrinsicContentSize()
    }

    override func layout() {
        super.layout()
        let width = max(bounds.width, 1)
        if abs(textView.frame.width - width) > 0.25 || abs(textView.frame.height - bounds.height) > 0.25 {
            textView.frame = NSRect(x: 0, y: 0, width: width, height: max(bounds.height, 1))
            invalidateIntrinsicContentSize()
        }
    }

    func requiredHeight(for width: CGFloat) -> CGFloat {
        let safeWidth = max(width, 1)
        if !heightDirty, abs(safeWidth - cachedWidth) < 0.5 {
            return cachedHeight
        }

        textView.frame.size.width = safeWidth
        textView.textContainer?.containerSize = NSSize(width: safeWidth, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        let height: CGFloat
        if let layoutManager = textView.layoutManager,
           let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
            let used = layoutManager.usedRect(for: textContainer)
            height = max(minimumHeight, ceil(used.height + textView.textContainerInset.height * 2))
        } else {
            height = max(minimumHeight, textView.textContainerInset.height * 2 + 18)
        }

        cachedWidth = safeWidth
        cachedHeight = height
        heightDirty = false
        return height
    }
}
