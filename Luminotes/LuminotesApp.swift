import AppKit
import SwiftUI

@main
struct LuminotesApp: App {
    @StateObject private var viewModel = EditorViewModel()
    @AppStorage("Luminotes.appearance") private var appearanceMode = "light"

    init() {
        // One-time move to the light + justified-text defaults for every user.
        let defaults = UserDefaults.standard
        let migrationKey = "Luminotes.defaults.lightBlockText.v1"
        if !defaults.bool(forKey: migrationKey) {
            defaults.set("light", forKey: "Luminotes.appearance")
            defaults.set(true, forKey: "Luminotes.justifyText")
            defaults.set(true, forKey: migrationKey)
        }
    }

    private var preferredScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: viewModel)
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(preferredScheme)
                .onAppear(perform: applyAppearance)
                .onChange(of: appearanceMode) { _, _ in
                    applyAppearance()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1200, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    viewModel.newNote()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open Folder…") {
                    viewModel.openProjectPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                if viewModel.isProjectOpen {
                    Button("Close Project") {
                        viewModel.closeProject()
                    }

                    Button("Reveal in Finder") {
                        viewModel.revealCurrentFileInFinder()
                    }
                }
            }

            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    viewModel.toggleSidebar()
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }

            CommandGroup(after: .saveItem) {
                Button("Export as Markdown…") {
                    viewModel.exportMarkdown()
                }
                .keyboardShortcut("e", modifiers: [.command, .option])
            }

            CommandMenu("Format") {
                Button("Text") {
                    viewModel.turnFocusedBlock(into: .paragraph)
                }
                .keyboardShortcut("0", modifiers: [.command, .option])

                Divider()

                Button("Heading 1") {
                    viewModel.turnFocusedBlock(into: .heading1)
                }
                .keyboardShortcut("1", modifiers: [.command, .option])

                Button("Heading 2") {
                    viewModel.turnFocusedBlock(into: .heading2)
                }
                .keyboardShortcut("2", modifiers: [.command, .option])

                Button("Heading 3") {
                    viewModel.turnFocusedBlock(into: .heading3)
                }
                .keyboardShortcut("3", modifiers: [.command, .option])

                Button("To-do list") {
                    viewModel.turnFocusedBlock(into: .todo)
                }
                .keyboardShortcut("4", modifiers: [.command, .option])

                Button("Bulleted list") {
                    viewModel.turnFocusedBlock(into: .bulletedList)
                }
                .keyboardShortcut("5", modifiers: [.command, .option])

                Button("Numbered list") {
                    viewModel.turnFocusedBlock(into: .numberedList)
                }
                .keyboardShortcut("6", modifiers: [.command, .option])

                Button("Toggle list") {
                    viewModel.turnFocusedBlock(into: .toggle)
                }
                .keyboardShortcut("7", modifiers: [.command, .option])

                Button("Code") {
                    viewModel.turnFocusedBlock(into: .code)
                }
                .keyboardShortcut("8", modifiers: [.command, .option])

                Divider()

                Button("Quote") {
                    viewModel.turnFocusedBlock(into: .quote)
                }

                Button("Callout") {
                    viewModel.turnFocusedBlock(into: .callout)
                }

                Button("Divider") {
                    viewModel.turnFocusedBlock(into: .divider)
                }
            }
        }
    }

    private func applyAppearance() {
        switch appearanceMode {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
    }
}
