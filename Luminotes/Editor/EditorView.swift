import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @ObservedObject var viewModel: EditorViewModel
    @FocusState private var titleFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var blockFrames: [UUID: CGRect] = [:]
    @AppStorage("Luminotes.justifyText") private var justifyText = true
    @AppStorage("Luminotes.appearance") private var appearanceMode = "light"
    @AppStorage(BlockTypography.bodyFontSizeKey) private var bodyFontSize = 16.0
    @AppStorage("Luminotes.editorWidth") private var editorWidth = 872.0
    @State private var scrollToBottomToken = UUID()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        titleField
                        noteProperties
                        blockList
                        addBlockSpace
                    }
                    .frame(maxWidth: editorWidth, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 52)
                    .padding(.bottom, 60)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .scrollIndicators(.hidden)
                .onDrop(
                    of: [.fileURL, .url],
                    delegate: BlockDropDelegate(
                        targetID: nil,
                        viewModel: viewModel,
                        dropTarget: $viewModel.dropTarget
                    )
                )
                .id(viewModel.note.id)
                .onChange(of: scrollToBottomToken) { _, _ in
                    // A lazy stack realizes more rows as we scroll, so the
                    // bottom sentinel keeps moving. Chase it for a few layout
                    // passes so one click reaches the real end of the note.
                    for delay in [0.0, 0.05, 0.15, 0.3, 0.5] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            proxy.scrollTo("editorBottom", anchor: .bottom)
                        }
                    }
                }
            }

            topBar
                .padding(.leading, viewModel.isSidebarVisible ? 16 : 92)
                .padding(.trailing, 16)
                .padding(.top, 12)
        }
        .ignoresSafeArea(.container, edges: .top)
        .overlay(alignment: .topLeading) {
            if viewModel.canGoBack {
                backButton
            }
        }
        .coordinateSpace(name: "EditorViewport")
        .onPreferenceChange(BlockFramePreferenceKey.self) { frames in
            // Frames are only needed to position the slash menu. Tracking them
            // during ordinary scrolling makes every scroll tick re-render the
            // whole editor, so ignore them unless the menu is open.
            guard viewModel.slashMenu != nil else { return }
            blockFrames = frames
        }
        .overlay {
            slashMenuOverlay
        }
        .navigationTitle(viewModel.note.title.isEmpty ? "Untitled" : viewModel.note.title)
        .onChange(of: viewModel.titleFocusRequest) { _, _ in
            titleFocused = true
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                viewModel.saveNow()
            }
        }
        .onAppear {
            if viewModel.note.blocks.isEmpty {
                viewModel.appendParagraph()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if viewModel.focusedBlockID == nil {
                    titleFocused = false
                    if let first = viewModel.note.blocks.first(where: { $0.type.isFocusableForNavigation }) {
                        viewModel.requestFocus(first.id, selection: 0)
                    }
                }
            }
        }
    }

    private var slashMenuOverlay: some View {
        GeometryReader { geometry in
            if let menu = viewModel.slashMenu,
               let frame = blockFrames[menu.blockID] {
                let menuWidth: CGFloat = 326
                let contentEstimate = SlashCommandMenuView.estimatedContentHeight(for: menu.query)
                let chromeHeight = SlashCommandMenuView.chromeHeight
                let estimatedTotal = min(contentEstimate, 342) + chromeHeight
                let spaceBelow = geometry.size.height - frame.maxY - 10
                let spaceAbove = frame.minY - 10
                let placeAbove = spaceBelow < estimatedTotal && spaceAbove > spaceBelow
                let available = max(placeAbove ? spaceAbove : spaceBelow, 0)
                let maxContent = max(80, min(342, available - chromeHeight))
                let visibleContent = min(contentEstimate, maxContent)
                let totalHeight = visibleContent + chromeHeight
                let x = min(
                    max(8, frame.minX + 66),
                    max(8, geometry.size.width - menuWidth - 8)
                )
                let desiredY = placeAbove ? frame.minY - totalHeight - 6 : frame.maxY + 6
                let y = min(
                    max(8, desiredY),
                    max(8, geometry.size.height - totalHeight - 8)
                )

                SlashCommandMenuView(
                    viewModel: viewModel,
                    menu: menu,
                    maxContentHeight: maxContent
                )
                .offset(x: x, y: y)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
    }

    private var isDark: Bool {
        appearanceMode == "dark" || (appearanceMode == "system" && colorScheme == .dark)
    }

    private var backButton: some View {
        Button {
            viewModel.goBack()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassPanel(cornerRadius: 10)
        .padding(.leading, viewModel.isSidebarVisible ? 16 : 92)
        .padding(.top, 58)
        .help("Back to database")
    }

    private var topBar: some View {
        HStack(spacing: 9) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.toggleSidebar()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Palette.secondaryText)
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Toggle sidebar")

            breadcrumb
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                appearanceMode = isDark ? "light" : "dark"
            } label: {
                Image(systemName: isDark ? "sun.max" : "moon")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Palette.secondaryText)
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isDark ? "Switch to light mode" : "Switch to dark mode")
            .contextMenu {
                Button("Use System Appearance") {
                    appearanceMode = "system"
                }
            }

            Button {
                justifyText.toggle()
            } label: {
                Image(systemName: justifyText ? "text.justify" : "text.alignleft")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(justifyText ? Palette.primaryText : Palette.secondaryText)
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(justifyText ? "Use left-aligned text" : "Justify text")

            Button {
                scrollToBottomToken = UUID()
            } label: {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Palette.secondaryText)
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Go to bottom")

            SaveStatusView(state: viewModel.saveState)

            fileActionsMenu
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .glassPanel(cornerRadius: 16, tint: Palette.sidebarTint)
    }

    @ViewBuilder
    private var breadcrumb: some View {
        if viewModel.isProjectOpen {
            HStack(spacing: 5) {
                Text(viewModel.projectName)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)

                if !viewModel.currentFileName.isEmpty {
                    Text("/")
                        .foregroundStyle(Palette.tertiaryText)
                    Text(viewModel.currentFileName)
                        .foregroundStyle(Palette.primaryText)
                        .lineLimit(1)
                }
            }
            .font(.system(size: 11, weight: .medium))
        } else {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 10.5, weight: .medium))
                Text("Luminotes")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(Palette.secondaryText)
        }
    }

    private var fileActionsMenu: some View {
        Menu {
            Button {
                viewModel.newNote()
            } label: {
                Label("New Note", systemImage: "square.and.pencil")
            }

            Button {
                viewModel.focusTitle()
            } label: {
                Label("Rename Note…", systemImage: "character.cursor.ibeam")
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button {
                viewModel.openProjectPanel()
            } label: {
                Label("Open Folder…", systemImage: "folder")
            }

            if viewModel.isProjectOpen {
                Button {
                    viewModel.revealCurrentFileInFinder()
                } label: {
                    Label("Reveal in Finder", systemImage: "finder")
                }

                Button {
                    viewModel.closeProject()
                } label: {
                    Label("Close Project", systemImage: "xmark.circle")
                }
            }

            Divider()

            Button {
                viewModel.exportMarkdown()
            } label: {
                Label("Export as Markdown…", systemImage: "square.and.arrow.up")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Note actions")
    }

    @ViewBuilder
    private var noteProperties: some View {
        if let fileURL = viewModel.currentFileURL {
            NoteDatabasePropertiesView(viewModel: viewModel, fileURL: fileURL)
        }
    }

    private var titleField: some View {
        TextField(
            "Untitled",
            text: Binding(
                get: { viewModel.note.title },
                set: { viewModel.setTitle($0) }
            ),
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(.system(size: 40 * CGFloat(bodyFontSize / 16), weight: .bold))
        .foregroundStyle(Palette.primaryText)
        .lineLimit(1...3)
        .focused($titleFocused)
        .padding(.horizontal, 66)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .onSubmit {
            viewModel.focusFirstBlock()
        }
    }

    private var blockList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(viewModel.visibleBlocks) { block in
                BlockRowView(
                    viewModel: viewModel,
                    block: block,
                    number: viewModel.listNumber(for: block),
                    tracksFrame: viewModel.slashMenu != nil
                )
                .id(block.id)
            }

            endDropZone
        }
        .padding(.trailing, 66)
    }

    private var endDropZone: some View {
        Color.clear
            .frame(height: 84)
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.appendParagraph()
            }
            .onDrop(
                of: [.text, .fileURL, .url],
                delegate: BlockDropDelegate(
                    targetID: nil,
                    viewModel: viewModel,
                    dropTarget: $viewModel.dropTarget
                )
            )
            .overlay(alignment: .top) {
                if viewModel.dropTarget == .end {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .offset(y: -2)
                }
            }
    }

    private var addBlockSpace: some View {
        Color.clear
            .frame(height: 36)
            .id("editorBottom")
    }

}

private struct SaveStatusView: View {
    let state: SaveState

    private var color: Color {
        switch state {
        case .saved: return Palette.tertiaryText
        case .saving: return Color.orange.opacity(0.8)
        case .error: return Color.red.opacity(0.8)
        }
    }

    private var label: String {
        switch state {
        case .saved: return "Saved"
        case .saving: return "Saving…"
        case .error: return "Couldn't save"
        }
    }

    private var icon: String {
        switch state {
        case .saved: return "checkmark.circle"
        case .saving: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.triangle"
        }
    }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 20, height: 22)
            .help(label)
            .animation(.easeInOut(duration: 0.15), value: label)
    }
}
