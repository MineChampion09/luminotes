import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BlockRowView: View {
    @ObservedObject var viewModel: EditorViewModel
    let block: Block
    let number: Int?

    @State private var isHovering = false

    private var isMenuOpen: Bool {
        viewModel.slashMenu?.blockID == block.id
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            gutter
                .frame(width: 58, alignment: .leading)
                .padding(.top, 1)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
        }
        .padding(.leading, CGFloat(block.indent) * 26)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .overlay(alignment: .top) {
            if viewModel.dropTarget == .before(block.id) {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .offset(y: -2)
                    .transition(.opacity)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: BlockFramePreferenceKey.self,
                    value: [block.id: proxy.frame(in: .named("EditorViewport"))]
                )
            }
        )
        .contextMenu {
            Menu("Turn into") {
                ForEach(BlockType.allCases.filter { $0 != .pdf }) { type in
                    Button {
                        viewModel.turnInto(block.id, type: type)
                    } label: {
                        Label(type.title, systemImage: type.icon)
                    }
                }
            }
            Divider()
            Button {
                viewModel.duplicateBlock(block.id)
            } label: {
                Label("Duplicate", systemImage: "square.on.square")
            }
            Button(role: .destructive) {
                viewModel.deleteBlock(block.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .onDrop(
            of: [.text, .fileURL, .url],
            delegate: BlockDropDelegate(
                targetID: block.id,
                viewModel: viewModel,
                dropTarget: $viewModel.dropTarget
            )
        )
    }

    private var topPadding: CGFloat {
        switch block.type {
        case .divider, .image, .pdf, .mermaid, .table:
            return 8
        default:
            return BlockTypography.topPadding(for: block.type)
        }
    }

    private var bottomPadding: CGFloat {
        switch block.type {
        case .divider, .image, .pdf, .mermaid, .table:
            return 8
        default:
            return BlockTypography.bottomPadding(for: block.type)
        }
    }

    private var gutter: some View {
        HStack(spacing: 1) {
            Menu {
                ForEach(BlockType.allCases.filter { $0 != .pdf }) { type in
                    Button {
                        viewModel.insertBlock(after: block.id, type: type)
                    } label: {
                        Label(type.title, systemImage: type.icon)
                    }
                }
                Divider()
                Button {
                    viewModel.duplicateBlock(block.id)
                } label: {
                    Label("Duplicate block", systemImage: "square.on.square")
                }
                Button(role: .destructive) {
                    viewModel.deleteBlock(block.id)
                } label: {
                    Label("Delete block", systemImage: "trash")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.secondaryText)
                    .frame(width: 18, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Insert block")

            if block.type == .table {
                TableOptionsMenu(viewModel: viewModel, block: block)
            }

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.tertiaryText)
                .frame(width: 16, height: 24)
                .contentShape(Rectangle())
                .onDrag {
                    NSItemProvider(object: block.id.uuidString as NSString)
                } preview: {
                    HStack(spacing: 7) {
                        Image(systemName: block.type.icon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.secondaryText)
                        Text(block.text.plainText.isEmpty ? block.type.title : block.text.plainText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.primaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: 320, alignment: .leading)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(Palette.menu)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Palette.border, lineWidth: 1)
                    )
                    .luminotesShadow()
                }
                .help("Drag to move")
        }
        .opacity(isHovering || isMenuOpen ? 1 : 0)
        .animation(.easeOut(duration: 0.1), value: isHovering)
    }

    @ViewBuilder
    private var content: some View {
        switch block.type {
        case .divider:
            DividerBlockView()

        case .code:
            CodeBlockView(viewModel: viewModel, block: block)

        case .math:
            MathBlockView(viewModel: viewModel, block: block)

        case .image:
            ImageBlockView(viewModel: viewModel, block: block)

        case .pdf:
            PDFBlockView(viewModel: viewModel, block: block)

        case .mermaid:
            MermaidBlockView(viewModel: viewModel, block: block)

        case .table:
            TableBlockView(viewModel: viewModel, block: block)

        default:
            textBlock
        }
    }

    private var editor: some View {
        RichTextEditor(
            viewModel: viewModel,
            block: block,
            placeholder: block.placeholder,
            minHeight: BlockTypography.minHeight(for: block.type)
        )
    }

    /// Text blocks all share one editor identity. Accessories (bullets,
    /// checkboxes, and quote rules) are drawn as overlays instead of siblings,
    /// so changing a block's type doesn't recreate its text view.
    private var textBlock: some View {
        editor
            .padding(.leading, textLeadingPadding)
            .padding(.trailing, block.type == .callout ? 14 : 0)
            .padding(.vertical, block.type == .callout ? 10 : 0)
            .background(calloutBackground)
            .overlay(alignment: .topLeading) {
                textAccessory
            }
            .overlay(calloutBorder)
            .opacity(block.type == .todo && block.checked ? 0.5 : 1)
    }

    private var textLeadingPadding: CGFloat {
        switch block.type {
        case .callout: return 14
        case .quote: return 16
        case .bulletedList, .numberedList, .todo, .toggle: return 24
        default: return 0
        }
    }

    @ViewBuilder
    private var calloutBackground: some View {
        if block.type == .callout {
            GlassSurface(cornerRadius: 8)
        }
    }

    @ViewBuilder
    private var calloutBorder: some View {
        if block.type == .callout {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Palette.border, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var textAccessory: some View {
        switch block.type {
        case .quote:
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Palette.primaryText.opacity(0.55))
                .frame(width: 3)
                .frame(maxHeight: .infinity)
                .padding(.vertical, 1)

        case .bulletedList:
            Text("•")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.primaryText.opacity(0.82))
                .frame(width: 20, alignment: .leading)
                .padding(.top, 2)

        case .numberedList:
            Text("\(number ?? 1).")
                .font(.system(size: 14.5, weight: .regular))
                .foregroundStyle(Palette.secondaryText)
                .monospacedDigit()
                .frame(width: 20, alignment: .trailing)
                .padding(.top, 3)

        case .todo:
            Button {
                viewModel.toggleTodo(block.id)
            } label: {
                Image(systemName: block.checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15.5, weight: .regular))
                    .foregroundStyle(block.checked ? Color.accentColor : Palette.secondaryText)
                    .frame(width: 20, height: 22, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

        case .toggle:
            Button {
                viewModel.toggleCollapsed(block.id)
            } label: {
                Image(systemName: block.collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Palette.secondaryText)
                    .frame(width: 20, height: 22, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

        default:
            EmptyView()
        }
    }

}

private struct DividerBlockView: View {
    var body: some View {
        Rectangle()
            .fill(Palette.border)
            .frame(height: 1)
            .padding(.vertical, 10)
    }
}

private struct CodeBlockView: View {
    @ObservedObject var viewModel: EditorViewModel
    let block: Block
    @State private var isHovering = false
    @State private var copied = false

    private let languages = ["Plain Text", "Swift", "JavaScript", "TypeScript", "Python", "SQL", "JSON", "Bash", "HTML", "CSS", "Markdown"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(languages, id: \.self) { language in
                        Button(language) {
                            viewModel.setCodeLanguage(block.id, language: language == "Plain Text" ? "" : language)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(block.codeLanguage.isEmpty ? "Plain Text" : block.codeLanguage)
                            .font(.system(size: 10.5, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundStyle(Palette.secondaryText)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Palette.hover)
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)

                Spacer()

                if isHovering {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(block.text.plainText, forType: .string)
                        copied = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_200_000_000)
                            copied = false
                        }
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Palette.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 31)

            Rectangle()
                .fill(Palette.border)
                .frame(height: 1)

            RichTextEditor(
                viewModel: viewModel,
                block: block,
                placeholder: "Code",
                minHeight: 34
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
        .glassPanel(cornerRadius: 8)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
    }
}

private struct ImageBlockView: View {
    @ObservedObject var viewModel: EditorViewModel
    let block: Block
    @State private var image: NSImage?
    @State private var isHovering = false
    @State private var loadToken = UUID()

    private static let imageCache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 24
        return cache
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 440)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    if isHovering {
                        HStack(spacing: 6) {
                            imageButton("Replace", icon: "arrow.triangle.2.circlepath") {
                                viewModel.chooseImage(for: block.id)
                            }
                            imageButton("Remove", icon: "trash") {
                                viewModel.removeImage(from: block.id)
                            }
                        }
                        .padding(8)
                        .transition(.opacity)
                    }
                }
                .onHover { isHovering = $0 }
            } else {
                Button {
                    viewModel.chooseImage(for: block.id)
                } label: {
                    VStack(spacing: 7) {
                        Image(systemName: "photo")
                            .font(.system(size: 21, weight: .light))
                        Text("Choose an image")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Palette.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 128)
                    .glassPanel(cornerRadius: 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                Palette.border,
                                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            RichTextEditor(
                viewModel: viewModel,
                block: block,
                placeholder: "Write a caption…",
                minHeight: 20
            )
        }
        .onAppear(perform: loadImage)
        .onChange(of: block.imageAsset) { _, _ in
            loadImage()
        }
        .onChange(of: block.imagePath) { _, _ in
            loadImage()
        }
        .onDisappear {
            loadToken = UUID()
            image = nil
        }
    }

    private func imageButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Palette.primaryText)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func loadImage() {
        let token = UUID()
        loadToken = token

        guard let url = viewModel.imageURL(for: block) else {
            image = nil
            return
        }

        let cacheKey = url as NSURL
        if let cached = Self.imageCache.object(forKey: cacheKey) {
            image = cached
            return
        }

        image = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = NSImage(contentsOf: url)

            DispatchQueue.main.async {
                guard loadToken == token else { return }
                if let loaded {
                    Self.imageCache.setObject(loaded, forKey: cacheKey)
                }
                image = loaded
            }
        }
    }
}

private enum TableLayoutMode: String {
    case fillWidth
    case fitContent
}

private struct TableBlockView: View {
    @ObservedObject var viewModel: EditorViewModel
    let block: Block

    @AppStorage("Luminotes.tableLayoutMode") private var layoutMode: TableLayoutMode = .fillWidth
    @State private var availableWidth: CGFloat = 0

    private var table: TableData {
        block.table ?? TableData()
    }

    private var columns: Int {
        max(table.columnCount, 1)
    }

    private var usableWidth: CGFloat {
        max(availableWidth > 80 ? availableWidth : 680, 180)
    }

    private var columnWidths: [CGFloat] {
        let count = columns
        guard count > 0 else { return [] }

        let dividers = CGFloat(max(count - 1, 0))
        let available = max(usableWidth - dividers, 0)

        switch layoutMode {
        case .fillWidth:
            let width = max(available / CGFloat(count), 96)
            return Array(repeating: width, count: count)

        case .fitContent:
            return (0..<count).map { column in
                let contentWidth = table.rows.enumerated().reduce(CGFloat(0)) { result, entry in
                    let (row, cells) = entry
                    let text = column < cells.count ? cells[column] : ""
                    let font = NSFont.systemFont(
                        ofSize: 12.5,
                        weight: row == 0 ? .semibold : .regular
                    )
                    let widestLine = text
                        .components(separatedBy: .newlines)
                        .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
                        .max() ?? 0
                    return max(result, widestLine)
                }
                return min(max(contentWidth + 28, 96), usableWidth)
            }
        }
    }

    var body: some View {
        let widths = columnWidths

        return VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(0..<table.rowCount, id: \.self) { row in
                        GridRow {
                            ForEach(0..<columns, id: \.self) { column in
                                cell(row: row, column: column)
                                    .frame(
                                        width: widths.indices.contains(column) ? widths[column] : 120,
                                        alignment: .leading
                                    )
                                    .frame(maxHeight: .infinity, alignment: .topLeading)
                                    .background(row == 0 ? Palette.hover : Color.clear)
                                    .overlay(alignment: .trailing) {
                                        if column < columns - 1 {
                                            Rectangle()
                                                .fill(Palette.border)
                                                .frame(width: 1)
                                        }
                                    }
                                    .overlay(alignment: .bottom) {
                                        if row < table.rowCount - 1 {
                                            Rectangle()
                                                .fill(Palette.border)
                                                .frame(height: 1)
                                        }
                                    }
                            }
                        }
                    }
                }
                .glassPanel(cornerRadius: 6)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TableWidthPreferenceKey.self,
                        value: proxy.size.width
                    )
                }
            )
        }
        .onPreferenceChange(TableWidthPreferenceKey.self) { width in
            guard width > 0, abs(width - availableWidth) > 0.5 else { return }
            availableWidth = width
        }
    }

    private func cell(row: Int, column: Int) -> some View {
        MathTableCell(
            text: Binding(
                get: { viewModel.tableCell(blockID: block.id, row: row, column: column) },
                set: { viewModel.setTableCell(blockID: block.id, row: row, column: column, value: $0) }
            ),
            isHeader: row == 0
        )
    }
}

private struct MathTableCell: View {
    @Binding var text: String
    let isHeader: Bool
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var hasInlineFormatting: Bool {
        text.contains("$")
            || text.contains("*")
            || text.contains("_")
            || text.contains("`")
            || text.contains("~")
            || text.contains("[[")
            || text.contains("](")
    }

    private var showsRenderedContent: Bool {
        !isFocused && hasInlineFormatting
    }

    private var minimumHeight: CGFloat? {
        if text.contains("$") { return 46 }
        if hasInlineFormatting { return 32 }
        return nil
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(nil)
                .font(.system(size: 12.5, weight: isHeader ? .semibold : .regular))
                .foregroundStyle(showsRenderedContent ? Color.clear : Palette.primaryText)
                .focused($isFocused)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .fixedSize(horizontal: false, vertical: true)

            if hasInlineFormatting {
                MathCellRenderedText(
                    text: text,
                    isHeader: isHeader,
                    colorScheme: colorScheme
                )
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .opacity(showsRenderedContent ? 1 : 0)
                .allowsHitTesting(false)
            }
        }
        .frame(minHeight: minimumHeight)
        .clipped()
    }
}

private struct MathCellRenderedText: NSViewRepresentable {
    let text: String
    let isHeader: Bool
    let colorScheme: ColorScheme

    private static let attributedCache = NSCache<NSString, NSAttributedString>()
    private static let heightCache = NSCache<NSString, NSNumber>()

    private var cacheKey: NSString {
        "\(text)|\(isHeader)|\(colorScheme == .dark ? "dark" : "light")" as NSString
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        textView.textStorage?.setAttributedString(makeAttributedString())
        textView.textColor = .luminotesPrimaryText
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSTextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }

        let heightKey = "\(cacheKey)|\(Int(width.rounded()))" as NSString
        if let cached = Self.heightCache.object(forKey: heightKey) {
            return CGSize(width: width, height: cached.doubleValue)
        }

        let textContainer = NSTextContainer(
            size: NSSize(width: width, height: .greatestFiniteMagnitude)
        )
        textContainer.lineFragmentPadding = 0

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        let storage = NSTextStorage(attributedString: makeAttributedString())
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        let used = layoutManager.usedRect(for: textContainer)
        let height = ceil(used.height)
        Self.heightCache.setObject(NSNumber(value: Double(height)), forKey: heightKey)
        return CGSize(width: width, height: height)
    }

    private func makeAttributedString() -> NSAttributedString {
        if let cached = Self.attributedCache.object(forKey: cacheKey) {
            return cached
        }

        let font = NSFont.systemFont(
            ofSize: 12.5,
            weight: isHeader ? .semibold : .regular
        )
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 0
        let attributed = MarkdownParser.parseInline(text).attributedString(
            baseFont: font,
            color: .luminotesPrimaryText,
            paragraphStyle: paragraphStyle,
            allowsInlineStyles: true,
            mathDisplayStyle: true
        )
        Self.attributedCache.setObject(attributed, forKey: cacheKey)
        return attributed
    }
}

private struct TableOptionsMenu: View {
    @ObservedObject var viewModel: EditorViewModel
    let block: Block
    @AppStorage("Luminotes.tableLayoutMode") private var layoutMode: TableLayoutMode = .fillWidth

    private var table: TableData {
        block.table ?? TableData()
    }

    var body: some View {
        Menu {
            Toggle(
                "Fit content",
                isOn: Binding(
                    get: { layoutMode == .fitContent },
                    set: { selected in
                        if selected { layoutMode = .fitContent }
                    }
                )
            )

            Toggle(
                "Fill width",
                isOn: Binding(
                    get: { layoutMode == .fillWidth },
                    set: { selected in
                        if selected { layoutMode = .fillWidth }
                    }
                )
            )

            Divider()

            Button {
                viewModel.addTableRow(block.id)
            } label: {
                Label("Add row", systemImage: "plus")
            }

            Button {
                viewModel.addTableColumn(block.id)
            } label: {
                Label("Add column", systemImage: "plus")
            }

            Divider()

            Button(role: .destructive) {
                viewModel.removeTableRow(block.id)
            } label: {
                Label("Remove last row", systemImage: "minus")
            }
            .disabled(table.rowCount <= 1)

            Button(role: .destructive) {
                viewModel.removeTableColumn(block.id)
            } label: {
                Label("Remove last column", systemImage: "minus")
            }
            .disabled(table.columnCount <= 1)
        } label: {
            Image(systemName: "tablecells")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 18, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Table options")
    }
}

private struct TableWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}


struct BlockFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
