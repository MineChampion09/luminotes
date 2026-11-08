import SwiftUI

struct SettingsView: View {
    @AppStorage("Luminotes.appearance") private var appearance = "light"
    @AppStorage("Luminotes.justifyText") private var justifyText = true
    @AppStorage(BlockTypography.bodyFontSizeKey) private var bodyFontSize = 16.0
    @AppStorage(BlockTypography.lineSpacingKey) private var lineSpacing = 4.0
    @AppStorage("Luminotes.editorWidth") private var editorWidth = 872.0
    @AppStorage("Luminotes.tableLayoutMode") private var tableLayout = "fillWidth"

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
        .frame(width: 460, height: 470)
        .preferredColorScheme(preferredScheme)
    }

    private func resetToDefaults() {
        appearance = "light"
        justifyText = true
        bodyFontSize = 16
        lineSpacing = 4
        editorWidth = 872
        tableLayout = "fillWidth"
    }
}
