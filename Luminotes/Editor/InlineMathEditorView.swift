import SwiftUI

struct InlineMathEditorView: View {
    let onSave: (String) -> Void
    let onChange: (String) -> Void
    let onCancel: () -> Void

    @State private var latex: String
    @FocusState private var fieldFocused: Bool

    init(
        initialLatex: String,
        onSave: @escaping (String) -> Void,
        onChange: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _latex = State(initialValue: initialLatex)
        self.onSave = onSave
        self.onChange = onChange
        self.onCancel = onCancel
    }

    private var trimmedLatex: String {
        latex.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "function")
                    .font(.system(size: 10.5, weight: .semibold))
                Text("Inline equation")
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(Palette.secondaryText)

            TextField("E = mc^2", text: $latex)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Palette.primaryText)
                .padding(.horizontal, 9)
                .frame(height: 32)
                .background(Palette.hover)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .focused($fieldFocused)
                .onSubmit {
                    onSave(trimmedLatex)
                }

            HStack {
                Text("Return to save")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.tertiaryText)

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.secondaryText)

                Button("Done") {
                    onSave(trimmedLatex)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .font(.system(size: 11.5, weight: .medium))
        }
        .padding(14)
        .frame(width: 340)
        .onAppear {
            fieldFocused = true
        }
        .onChange(of: latex) { _, _ in
            onChange(trimmedLatex)
        }
        .onExitCommand {
            onCancel()
        }
    }
}
