import AppKit
import SwiftUI
import SwiftUIMath

struct MathBlockView: View {
    @ObservedObject var viewModel: EditorViewModel
    let block: Block
    @State private var isEditing = false
    @State private var draft = ""
    @State private var mathImage: NSImage?
    @Environment(\.colorScheme) private var colorScheme

    private var latex: String {
        block.text.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var previewLatex: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedLatex: String {
        isEditing ? previewLatex : latex
    }

    var body: some View {
        Group {
            if displayedLatex.isEmpty {
                Text("Click to add an equation")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.tertiaryText)
            } else if let mathImage {
                // Use the natural size when it fits; otherwise scale the
                // equation down so it is never clipped by the editor width.
                ViewThatFits(in: .horizontal) {
                    Image(nsImage: mathImage)
                        .interpolation(.high)

                    Image(nsImage: mathImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                // The image renderer is the primary path; this keeps a usable
                // fallback if an expression cannot be rasterized.
                Math(displayedLatex)
                    .mathFont(.init(name: .latinModern, size: 24))
                    .mathTypesettingStyle(.display)
                    .foregroundStyle(Palette.primaryText)
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            beginEditing()
        }
        .help("Click to edit equation")
        .popover(isPresented: $isEditing, arrowEdge: .bottom) {
            editorPopover
        }
        .onAppear {
            refreshImage()
            if latex.isEmpty {
                beginEditing()
            }
        }
        .onChange(of: latex) { _, _ in
            refreshImage()
        }
        .onChange(of: draft) { _, _ in
            refreshImage()
        }
        .onChange(of: isEditing) { _, editing in
            if !editing {
                refreshImage()
            }
        }
        .onChange(of: colorScheme) { _, _ in
            refreshImage()
        }
        .onChange(of: viewModel.focusRequest?.blockID) { _, requested in
            if requested == block.id {
                beginEditing()
            }
        }
    }

    private func refreshImage() {
        guard !displayedLatex.isEmpty else {
            mathImage = nil
            return
        }
        mathImage = MathImageRenderer.shared.image(
            latex: displayedLatex,
            fontSize: 24,
            color: .luminotesPrimaryText,
            displayStyle: true
        )
    }

    private var editorPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "function")
                    .font(.system(size: 10.5, weight: .semibold))
                Text("LaTeX equation")
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(Palette.secondaryText)

            SourceTextEditor(
                text: $draft,
                fontSize: 13,
                insets: NSSize(width: 8, height: 8)
            )
            .frame(width: 336, height: 96)
            .background(Palette.code)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Palette.border, lineWidth: 1)
            )

            HStack {
                Text("Changes update live · press Done to save")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.tertiaryText)
                Spacer()
                Button("Cancel") {
                    isEditing = false
                    refreshImage()
                }
                .buttonStyle(.plainPointer)
                .foregroundStyle(Palette.secondaryText)

                Button("Done") {
                    viewModel.updateText(block.id, text: RichText(previewLatex))
                    isEditing = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .font(.system(size: 11.5, weight: .medium))
        }
        .padding(14)
        .frame(width: 364)
    }

    private func beginEditing() {
        draft = latex
        isEditing = true
    }
}
