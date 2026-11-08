import AppKit
import SwiftUI

struct RootView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        ZStack {
            WindowGlassBackground()

            HStack(spacing: 0) {
                if viewModel.isSidebarVisible {
                    SidebarView(viewModel: viewModel)
                        .frame(width: 260)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .animation(.easeInOut(duration: 0.22), value: viewModel.isSidebarVisible)
        }
        .background(WindowConfigurator())
    }

    @ViewBuilder
    private var detail: some View {
        if viewModel.isProjectOpen && viewModel.currentFileURL == nil {
            ProjectEmptyView(viewModel: viewModel)
        } else {
            EditorView(viewModel: viewModel)
        }
    }
}

private struct ProjectEmptyView: View {
    @ObservedObject var viewModel: EditorViewModel

    private var hasNotes: Bool {
        viewModel.projectFiles.contains(where: { $0.isMarkdown })
    }

    var body: some View {
        ZStack {
            Color.clear

            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Palette.hover)
                        .frame(width: 88, height: 88)

                    Image(systemName: hasNotes ? "doc.text" : "doc.text.magnifyingglass")
                        .font(.system(size: 33, weight: .light))
                        .foregroundStyle(Palette.secondaryText)
                }

                VStack(spacing: 6) {
                    Text(hasNotes ? "Select a note" : "No Markdown files yet")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Palette.primaryText)

                    Text(
                        hasNotes
                            ? "Choose a note from the sidebar, or create a new one."
                            : "Create a note here, or choose a different folder from the sidebar."
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                }

                HStack(spacing: 8) {
                    Button {
                        viewModel.createProjectNote()
                    } label: {
                        Label("New Note", systemImage: "square.and.pencil")
                            .padding(.horizontal, 6)
                    }
                    .glassButtonStyle(prominent: true)

                    Button {
                        viewModel.openProjectPanel()
                    } label: {
                        Label("Open Folder…", systemImage: "folder")
                            .padding(.horizontal, 6)
                    }
                    .glassButtonStyle()
                }
                .padding(.top, 2)
            }
            .padding(40)
        }
        .overlay(alignment: .topLeading) {
            if !viewModel.isSidebarVisible {
                Button {
                    viewModel.toggleSidebar()
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.secondaryText)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassPanel(cornerRadius: 17)
                .padding(.leading, 24)
                .padding(.top, 28)
                .help("Show sidebar")
            }
        }
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.minSize = NSSize(width: 900, height: 600)
            window.styleMask.insert(.fullSizeContentView)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
