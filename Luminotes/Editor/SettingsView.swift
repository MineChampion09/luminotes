import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: EditorViewModel
    @AppStorage("Luminotes.appearance") private var appearance = "light"
    @AppStorage("Luminotes.justifyText") private var justifyText = true
    @AppStorage(BlockTypography.bodyFontSizeKey) private var bodyFontSize = 16.0
    @AppStorage(BlockTypography.lineSpacingKey) private var lineSpacing = 4.0
    @AppStorage("Luminotes.editorWidth") private var editorWidth = 872.0
    @AppStorage("Luminotes.tableLayoutMode") private var tableLayout = "fillWidth"
    @State private var attachmentFolder = ""

    private var preferredScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                    Text("System").tag("system")
                }
                .pickerStyle(.segmented)
            }

            Section("Text") {
                LabeledContent("Body font size") {
                    Stepper(value: $bodyFontSize, in: 12...24, step: 1) {
                        Text("\(Int(bodyFontSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(Palette.secondaryText)
                    }
                }

                LabeledContent("Line spacing") {
                    Stepper(value: $lineSpacing, in: 0...12, step: 1) {
                        Text("\(Int(lineSpacing)) pt")
                            .monospacedDigit()
                            .foregroundStyle(Palette.secondaryText)
                    }
                }

                Toggle("Justify text", isOn: $justifyText)
            }

            Section("Layout") {
                LabeledContent("Editor width") {
                    Stepper(value: $editorWidth, in: 600...1200, step: 20) {
                        Text("\(Int(editorWidth)) pt")
                            .monospacedDigit()
                            .foregroundStyle(Palette.secondaryText)
                    }
                }

                Picker("Table layout", selection: $tableLayout) {
                    Text("Fill width").tag("fillWidth")
                    Text("Fit content").tag("fitContent")
                }
                .pickerStyle(.segmented)
            }

            Section("Project") {
                if let projectURL = viewModel.projectURL {
                    LabeledContent("Attachment folder") {
                        HStack(spacing: 8) {
                            TextField("Assets", text: $attachmentFolder)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                            Button("Choose…") {
                                chooseAttachmentFolder()
                            }
                        }
                    }

                    Text("Relative to \(projectURL.lastPathComponent). Leave empty to use an Assets folder beside each note.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.tertiaryText)
                } else {
                    Text("Open a project to configure its attachment folder.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondaryText)
                }
            }

            Section {
                HStack {
                    Text("Changes apply immediately.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiaryText)
                    Spacer()
                    Button("Reset to Defaults") {
                        resetToDefaults()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 600)
        .preferredColorScheme(preferredScheme)
        .onAppear {
            attachmentFolder = viewModel.attachmentFolder
        }
        .onChange(of: viewModel.projectURL) { _, _ in
            attachmentFolder = viewModel.attachmentFolder
        }
        .onChange(of: attachmentFolder) { _, newValue in
            viewModel.setAttachmentFolder(newValue)
        }
    }

    private func resetToDefaults() {
        appearance = "light"
        justifyText = true
        bodyFontSize = 16
        lineSpacing = 4
        editorWidth = 872
        tableLayout = "fillWidth"
    }

    private func chooseAttachmentFolder() {
        guard let root = viewModel.projectURL?.standardizedFileURL else { return }

        let panel = NSOpenPanel()
        panel.title = "Choose Attachment Folder"
        panel.prompt = "Choose"
        panel.message = "Files dropped into a note will be copied here."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = root

        guard panel.runModal() == .OK, let selected = panel.url?.standardizedFileURL else {
            return
        }

        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        if selected.path == root.path {
            attachmentFolder = ""
        } else if selected.path.hasPrefix(rootPath) {
            attachmentFolder = String(selected.path.dropFirst(rootPath.count))
        } else {
            NSSound.beep()
        }
    }
}
