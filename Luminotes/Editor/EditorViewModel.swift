import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

struct FocusRequest: Equatable {
    let blockID: UUID
    let token: UUID
    let selection: Int?
}

struct SlashMenuState: Equatable {
    var blockID: UUID
    var range: NSRange
    var query: String
    var selectedIndex: Int
}

enum DropTarget: Equatable {
    case before(UUID)
    case end
}

enum SaveState {
    case saved
    case saving
    case error
}

@MainActor
final class EditorViewModel: ObservableObject {
    @Published private(set) var note: Note
    @Published var focusedBlockID: UUID?
    @Published var focusRequest: FocusRequest?
    @Published var slashMenu: SlashMenuState?
    @Published var dropTarget: DropTarget?
    @Published var titleFocusRequest: UUID?
    @Published var isSidebarVisible = true
    @Published var isQuickOpenPresented = false
    @Published private(set) var saveState: SaveState = .saved

    @Published private(set) var projectURL: URL?
    @Published private(set) var projectFiles: [ProjectFile] = []
    @Published private(set) var selectedFileID: String?
    @Published private(set) var currentFileURL: URL?
    @Published var presentedAsset: ProjectFile?
    @Published private(set) var navigationStack: [ProjectFile] = []

    var canGoBack: Bool {
        !navigationStack.isEmpty
    }

    let store: NoteStore

    private var projectStore: ProjectStore?
    private var hasUnsavedChanges = false
    private var lastFocusedBlockID: UUID?
    private var saveTask: Task<Void, Never>?
    private var terminationObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?

    private static let lastProjectPathKey = "Luminotes.lastProjectPath"
    private static let lastSelectedPathKey = "Luminotes.lastSelectedPath"
    private static let attachmentFoldersKey = "Luminotes.attachmentFolders"

    init(store: NoteStore = NoteStore()) {
        self.store = store

        if let loaded = store.load() {
            note = loaded
        } else {
            note = .welcome
            try? store.save(note)
        }

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.saveNow()
            }
        }

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshProjectFiles()
            }
        }

        restoreLastProject()
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        saveTask?.cancel()
    }

    // MARK: - Project presentation

    var isProjectOpen: Bool {
        projectURL != nil
    }

    var projectName: String {
        projectURL?.lastPathComponent ?? "Luminotes"
    }

    var currentFileName: String {
        currentFileURL?.lastPathComponent ?? ""
    }

    var currentRelativePath: String {
        selectedFileID ?? ""
    }

    /// Optional project-relative folder for imported PDFs and images. An empty
    /// value keeps the default `Assets` folder beside each note.
    var attachmentFolder: String {
        guard let projectURL else { return "" }
        let folders = UserDefaults.standard.dictionary(
            forKey: Self.attachmentFoldersKey
        ) as? [String: String] ?? [:]
        return folders[projectURL.standardizedFileURL.path] ?? ""
    }

    func setAttachmentFolder(_ folder: String) {
        guard let projectURL else { return }
        var folders = UserDefaults.standard.dictionary(
            forKey: Self.attachmentFoldersKey
        ) as? [String: String] ?? [:]
        let key = projectURL.standardizedFileURL.path
        let trimmed = folder.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            folders.removeValue(forKey: key)
        } else {
            folders[key] = trimmed
        }
        UserDefaults.standard.set(folders, forKey: Self.attachmentFoldersKey)
    }

    // MARK: - Presentation

    var visibleBlocks: [Block] {
        var result: [Block] = []
        var hiddenBelowIndent: Int?

        for block in note.blocks {
            if let hidden = hiddenBelowIndent {
                if block.indent > hidden {
                    continue
                } else {
                    hiddenBelowIndent = nil
                }
            }

            result.append(block)

            if block.type == .toggle && block.collapsed {
                hiddenBelowIndent = block.indent
            }
        }

        return result
    }

    func listNumber(for block: Block) -> Int? {
        guard block.type == .numberedList,
              let index = note.blocks.firstIndex(where: { $0.id == block.id }) else {
            return nil
        }

        var number = 1
        var cursor = index - 1

        while cursor >= 0 {
            let previous = note.blocks[cursor]
            if previous.indent < block.indent { break }
            if previous.indent == block.indent {
                if previous.type == .numberedList {
                    number += 1
                } else {
                    break
                }
            }
            cursor -= 1
        }

        return number
    }

    var commandTargetBlockID: UUID? {
        focusedBlockID ?? lastFocusedBlockID ?? note.blocks.last?.id
    }

    // MARK: - Persistence

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard hasUnsavedChanges else {
            saveState = .saved
            return
        }
        var snapshot = note
        snapshot.updatedAt = Date()
        persist(note: snapshot, fileURL: currentFileURL, projectURL: projectURL)
    }

    private func scheduleSave() {
        saveState = .saving
        let snapshot = note
        let fileURL = currentFileURL
        let projectURL = projectURL
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled, let self else { return }
            self.persist(note: snapshot, fileURL: fileURL, projectURL: projectURL)
        }
    }

    private func persist(note snapshot: Note, fileURL: URL?, projectURL: URL?) {
        var savedNote = snapshot

        if projectURL != nil {
            guard let fileURL, let projectStore else {
                return
            }
            guard currentFileURL?.standardizedFileURL == fileURL.standardizedFileURL else {
                return
            }

            do {
                var targetURL = fileURL
                let sanitizedTitle = ProjectStore.sanitizedFilename(snapshot.title)
                let currentStem = fileURL.deletingPathExtension().lastPathComponent

                if !sanitizedTitle.isEmpty, sanitizedTitle != currentStem {
                    targetURL = try projectStore.renameNote(at: fileURL, to: sanitizedTitle)
                    savedNote.title = targetURL.deletingPathExtension().lastPathComponent
                    currentFileURL = targetURL
                    refreshProjectFiles()
                    UserDefaults.standard.set(selectedFileID, forKey: Self.lastSelectedPathKey)

                    // Only adopt a generated collision suffix. Never clobber a
                    // title the user kept typing while the save task was running.
                    if savedNote.title != sanitizedTitle, note.title == snapshot.title {
                        note.title = savedNote.title
                    }
                }

                let markdown = MarkdownCodec.body(for: savedNote)
                try projectStore.writeMarkdown(markdown, to: targetURL)
                currentFileURL = targetURL
                if contentMatches(snapshot) {
                    hasUnsavedChanges = false
                }
                saveState = .saved
            } catch {
                NSLog("Luminotes: could not save project file: \(error)")
                saveState = .error
            }
        } else if projectURL == nil {
            do {
                try store.save(savedNote)
                if contentMatches(snapshot) {
                    hasUnsavedChanges = false
                }
                saveState = .saved
            } catch {
                NSLog("Luminotes: could not save note: \(error)")
                saveState = .error
            }
        }
    }

    private func contentMatches(_ snapshot: Note) -> Bool {
        note.title == snapshot.title &&
            note.blocks == snapshot.blocks &&
            note.frontmatter == snapshot.frontmatter
    }

    private func mutateNote(_ body: (inout Note) -> Void, save: Bool = true) {
        var copy = note
        body(&copy)
        copy.updatedAt = Date()
        note = copy
        if save {
            hasUnsavedChanges = true
            scheduleSave()
        }
    }

    // MARK: - Text and titles

    func setTitle(_ title: String) {
        guard title != note.title else { return }
        mutateNote { $0.title = title }
    }

    func updateText(_ blockID: UUID, text: RichText) {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }),
              note.blocks[index].text != text else {
            return
        }
        mutateNote { $0.blocks[index].text = text }
    }

    func toggleTodo(_ blockID: UUID) {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        mutateNote { $0.blocks[index].checked.toggle() }
    }

    func toggleCollapsed(_ blockID: UUID) {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        mutateNote { $0.blocks[index].collapsed.toggle() }
    }

    func setCodeLanguage(_ blockID: UUID, language: String) {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        mutateNote { $0.blocks[index].codeLanguage = language }
    }

    // MARK: - Focus

    func focusChanged(to blockID: UUID?) {
        focusedBlockID = blockID
        if let blockID {
            lastFocusedBlockID = blockID
            if slashMenu?.blockID != blockID {
                slashMenu = nil
            }
        }
    }

    func requestFocus(_ blockID: UUID, selection: Int? = nil) {
        focusRequest = FocusRequest(blockID: blockID, token: UUID(), selection: selection)
    }

    func consumeFocusRequest(_ token: UUID) {
        guard focusRequest?.token == token else { return }
        focusRequest = nil
    }

    func focusFirstBlock() {
        guard let first = note.blocks.first(where: { $0.type.isFocusableForNavigation }) else { return }
        requestFocus(first.id, selection: 0)
    }

    func focusTitle() {
        titleFocusRequest = UUID()
    }

    func toggleSidebar() {
        isSidebarVisible.toggle()
    }

    func focusPrevious(from blockID: UUID) {
        let visible = visibleBlocks
        guard let index = visible.firstIndex(where: { $0.id == blockID }) else { return }
        for candidate in visible[..<index].reversed() where candidate.type.isFocusableForNavigation {
            requestFocus(candidate.id, selection: candidate.text.utf16Count)
            return
        }
    }

    func focusNext(from blockID: UUID) {
        let visible = visibleBlocks
        guard let index = visible.firstIndex(where: { $0.id == blockID }) else { return }
        for candidate in visible[(index + 1)...] where candidate.type.isFocusableForNavigation {
            requestFocus(candidate.id, selection: 0)
            return
        }
    }

    // MARK: - Block creation and transformation

    @discardableResult
    func insertBlock(after blockID: UUID, type: BlockType) -> UUID? {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { return nil }
        let indent = note.blocks[index].indent
        let newBlock = Block.make(type, indent: indent)

        mutateNote { $0.blocks.insert(newBlock, at: index + 1) }

        if type == .divider {
            return insertParagraph(after: newBlock.id)
        }

        if type.isFocusableForNavigation {
            requestFocus(newBlock.id, selection: 0)
        }
        return newBlock.id
    }

    @discardableResult
    func insertParagraph(after blockID: UUID) -> UUID? {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { return nil }
        let indent = note.blocks[index].indent
        let newBlock = Block.make(.paragraph, indent: indent)
        mutateNote { $0.blocks.insert(newBlock, at: index + 1) }
        requestFocus(newBlock.id, selection: 0)
        return newBlock.id
    }

    func appendParagraph() {
        if let last = note.blocks.last, last.type == .paragraph, last.text.isEmpty {
            requestFocus(last.id, selection: 0)
            return
        }
        guard let last = note.blocks.last else {
            let block = Block()
            mutateNote { $0.blocks = [block] }
            requestFocus(block.id, selection: 0)
            return
        }
        _ = insertParagraph(after: last.id)
    }

    func turnInto(_ blockID: UUID, type: BlockType) {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        let block = note.blocks[index]

        if type == .divider {
            mutateNote { note in
                note.blocks[index].type = .divider
                note.blocks[index].text = .empty
                note.blocks[index].table = nil
                note.blocks[index].imageAsset = nil
                note.blocks[index].imagePath = nil
                note.blocks[index].checked = false
                note.blocks[index].collapsed = false
            }
            _ = insertParagraph(after: blockID)
            return
        }

        if type == .table {
            var table = block.table ?? TableData()
            if let first = table.rows.first, first.allSatisfy({ $0.isEmpty }), !block.text.isEmpty {
                table.rows[0][0] = block.text.plainText
            }
            mutateNote { note in
                note.blocks[index].type = .table
                note.blocks[index].table = table
                note.blocks[index].text = .empty
                note.blocks[index].checked = false
                note.blocks[index].collapsed = false
            }
            return
        }

        mutateNote { note in
            note.blocks[index].type = type
            note.blocks[index].checked = type == .todo ? note.blocks[index].checked : false
            note.blocks[index].collapsed = type == .toggle ? note.blocks[index].collapsed : false
            if type == .callout, note.blocks[index].calloutIcon.isEmpty {
                note.blocks[index].calloutIcon = "💡"
            }
            if type != .code {
                note.blocks[index].codeLanguage = ""
            }
            note.blocks[index].imageAsset = nil
            note.blocks[index].imagePath = nil
            note.blocks[index].databasePath = nil
            note.blocks[index].databaseViewID = nil
            if type != .table {
                note.blocks[index].table = nil
            }
        }

        if type.isFocusableForNavigation {
            requestFocus(blockID, selection: block.text.utf16Count)
        }
    }

    func turnFocusedBlock(into type: BlockType) {
        guard let blockID = commandTargetBlockID else { return }
        turnInto(blockID, type: type)
    }

    func handleEnter(_ blockID: UUID, before: RichText, after: RichText) {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        let block = note.blocks[index]

        if block.type.isList, before.isEmpty, after.isEmpty {
            mutateNote { note in
                note.blocks[index].type = .paragraph
                note.blocks[index].checked = false
            }
            requestFocus(blockID, selection: 0)
            return
        }

        var newType: BlockType = .paragraph
        var newIndent = block.indent

        switch block.type {
        case .bulletedList, .numberedList, .todo:
            newType = block.type
        case .toggle:
            newIndent = min(block.indent + 1, 8)
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6, .quote, .callout:
            newType = .paragraph
        default:
            newType = .paragraph
        }

        var newBlock = Block.make(newType, indent: newIndent)
        newBlock.text = after
        newBlock.checked = false
        newBlock.collapsed = false

        mutateNote { note in
            note.blocks[index].text = before
            if note.blocks[index].type == .toggle {
                note.blocks[index].collapsed = false
            }
            note.blocks.insert(newBlock, at: index + 1)
        }

        requestFocus(newBlock.id, selection: 0)
    }

    /// Returns true when the key press was consumed.
    @discardableResult
    func handleBackspaceAtStart(_ blockID: UUID) -> Bool {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { return false }
        let block = note.blocks[index]

        if !block.text.isEmpty {
            if block.indent > 0 {
                mutateNote { $0.blocks[index].indent -= 1 }
                return true
            }

            if index > 0 {
                let previous = note.blocks[index - 1]
                if previous.type.hasTextEditor, previous.type != .table {
                    let caret = previous.text.utf16Count
                    mutateNote { note in
                        note.blocks[index - 1].text.append(block.text)
                        note.blocks.remove(at: index)
                    }
                    requestFocus(previous.id, selection: caret)
                    return true
                }
            }

            if block.type != .paragraph {
                mutateNote { note in
                    note.blocks[index].type = .paragraph
                    note.blocks[index].checked = false
                    note.blocks[index].collapsed = false
                }
                requestFocus(blockID, selection: 0)
                return true
            }

            return true
        }

        if block.type != .paragraph {
            mutateNote { note in
                note.blocks[index].type = .paragraph
                note.blocks[index].checked = false
                note.blocks[index].collapsed = false
            }
            requestFocus(blockID, selection: 0)
            return true
        }

        if block.indent > 0 {
            mutateNote { $0.blocks[index].indent -= 1 }
            return true
        }

        guard index > 0 else { return true }

        let previous = note.blocks[index - 1]
        mutateNote { $0.blocks.remove(at: index) }

        if previous.type.isFocusableForNavigation {
            requestFocus(previous.id, selection: previous.text.utf16Count)
        } else {
            let visible = visibleBlocks
            if let fallback = visible.last(where: { $0.type.isFocusableForNavigation }) {
                requestFocus(fallback.id, selection: fallback.text.utf16Count)
            }
        }

        return true
    }

    func indentBlock(_ blockID: UUID, delta: Int) {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        let newIndent = max(0, min(note.blocks[index].indent + delta, 8))
        guard newIndent != note.blocks[index].indent else { return }
        mutateNote { $0.blocks[index].indent = newIndent }
    }

    func moveBlock(_ blockID: UUID, before targetID: UUID) {
        guard blockID != targetID,
              let sourceIndex = note.blocks.firstIndex(where: { $0.id == blockID }),
              let targetIndex = note.blocks.firstIndex(where: { $0.id == targetID }) else {
            return
        }

        mutateNote { note in
            let block = note.blocks.remove(at: sourceIndex)
            let insertionIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
            note.blocks.insert(block, at: insertionIndex)
        }
    }

    func moveBlockToEnd(_ blockID: UUID) {
        guard let sourceIndex = note.blocks.firstIndex(where: { $0.id == blockID }),
              sourceIndex < note.blocks.count - 1 else {
            return
        }
        mutateNote { note in
            let block = note.blocks.remove(at: sourceIndex)
            note.blocks.append(block)
        }
    }

    func moveBlockBy(_ blockID: UUID, offset: Int) {
        let visible = visibleBlocks
        guard let visibleIndex = visible.firstIndex(where: { $0.id == blockID }) else { return }
        let targetVisibleIndex = visibleIndex + offset
        guard visible.indices.contains(targetVisibleIndex) else { return }
        let target = visible[targetVisibleIndex]

        if offset < 0 {
            moveBlock(blockID, before: target.id)
        } else if targetVisibleIndex + 1 < visible.count {
            moveBlock(blockID, before: visible[targetVisibleIndex + 1].id)
        } else {
            moveBlockToEnd(blockID)
        }
    }

    func duplicateBlock(_ blockID: UUID) {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        var copy = note.blocks[index]
        copy.id = UUID()
        copy.collapsed = false
        mutateNote { $0.blocks.insert(copy, at: index + 1) }
        if copy.type.isFocusableForNavigation {
            requestFocus(copy.id, selection: copy.text.utf16Count)
        }
    }

    func deleteBlock(_ blockID: UUID) {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        let visible = visibleBlocks
        let visibleIndex = visible.firstIndex(where: { $0.id == blockID })

        mutateNote { $0.blocks.remove(at: index) }

        if note.blocks.isEmpty {
            let block = Block()
            mutateNote { $0.blocks = [block] }
            requestFocus(block.id, selection: 0)
            return
        }

        if let visibleIndex {
            if visibleIndex < visible.count - 1 {
                let next = visible[visibleIndex + 1]
                if next.type.isFocusableForNavigation {
                    requestFocus(next.id, selection: 0)
                }
            } else if visibleIndex > 0 {
                let previous = visible[visibleIndex - 1]
                if previous.type.isFocusableForNavigation {
                    requestFocus(previous.id, selection: previous.text.utf16Count)
                }
            }
        }
    }

    // MARK: - Markdown shortcuts

    /// Converts Markdown block prefixes typed at the start of a paragraph.
    /// Returns true when the block type changed.
    @discardableResult
    func handleMarkdownShortcut(_ blockID: UUID, text: RichText) -> Bool {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { return false }
        guard note.blocks[index].type == .paragraph else { return false }

        let plain = text.plainText
        guard !plain.isEmpty else { return false }

        if plain == "---" || plain == "***" || plain == "___" {
            mutateNote { note in
                note.blocks[index].type = .divider
                note.blocks[index].text = .empty
                note.blocks[index].table = nil
            }
            _ = insertParagraph(after: blockID)
            return true
        }

        let mappings: [(String, BlockType)] = [
            ("###### ", .heading6),
            ("##### ", .heading5),
            ("#### ", .heading4),
            ("### ", .heading3),
            ("## ", .heading2),
            ("# ", .heading1),
            ("``` ", .code),
            ("$$ ", .math),
            ("> ", .toggle),
            ("\" ", .quote),
            ("- ", .bulletedList),
            ("* ", .bulletedList),
            ("+ ", .bulletedList),
            ("[] ", .todo),
            ("[ ] ", .todo)
        ]

        for (prefix, type) in mappings where plain.hasPrefix(prefix) {
            let range = NSRange(location: 0, length: (prefix as NSString).length)
            let remaining = text.removingUTF16Range(range)
            mutateNote { note in
                note.blocks[index].type = type
                note.blocks[index].text = remaining
                note.blocks[index].checked = false
                note.blocks[index].collapsed = false
                if type == .callout {
                    note.blocks[index].calloutIcon = "💡"
                }
            }
            if type == .code || type == .math {
                requestFocus(blockID, selection: 0)
            }
            return true
        }

        if plain.hasPrefix("```") && plain.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            let trimmed = plain.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "```" {
                mutateNote { note in
                    note.blocks[index].type = .code
                    note.blocks[index].text = .empty
                }
                requestFocus(blockID, selection: 0)
                return true
            }
        }

        if let numbered = Self.numberedPrefixLength(in: plain) {
            let range = NSRange(location: 0, length: numbered)
            let remaining = text.removingUTF16Range(range)
            mutateNote { note in
                note.blocks[index].type = .numberedList
                note.blocks[index].text = remaining
            }
            return true
        }

        return false
    }

    private static func numberedPrefixLength(in text: String) -> Int? {
        let pattern = "^(?:[0-9]+|[a-zA-Z]|[ivxlcdmIVXLCDM]+)\\. "
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else {
            return nil
        }
        return match.range.length
    }

    // MARK: - Slash menu

    var filteredSlashCommands: [SlashCommand] {
        SlashCommand.filtered(by: slashMenu?.query ?? "")
    }

    func updateSlashMenu(blockID: UUID, range: NSRange, query: String) {
        if var state = slashMenu, state.blockID == blockID {
            if state.query != query {
                state.selectedIndex = 0
            }
            state.range = range
            state.query = query
            state.selectedIndex = min(state.selectedIndex, max(filteredSlashCommands.count - 1, 0))
            slashMenu = state
        } else {
            slashMenu = SlashMenuState(blockID: blockID, range: range, query: query, selectedIndex: 0)
        }
    }

    func closeSlashMenu(blockID: UUID? = nil) {
        guard let current = slashMenu else { return }
        if let blockID, current.blockID != blockID { return }
        slashMenu = nil
    }

    func moveSlashSelection(_ delta: Int) {
        guard var state = slashMenu else { return }
        let count = filteredSlashCommands.count
        guard count > 0 else { return }
        state.selectedIndex = (state.selectedIndex + delta + count) % count
        slashMenu = state
    }

    func chooseSelectedSlashCommand() {
        guard let state = slashMenu else { return }
        let commands = filteredSlashCommands
        guard commands.indices.contains(state.selectedIndex) else { return }
        chooseSlashCommand(commands[state.selectedIndex])
    }

    func chooseSlashCommand(_ command: SlashCommand) {
        guard let state = slashMenu else { return }
        slashMenu = nil
        applySlashCommand(command, blockID: state.blockID, removing: state.range)
    }

    private func applySlashCommand(_ command: SlashCommand, blockID: UUID, removing range: NSRange) {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        let cleanedText = note.blocks[index].text.removingUTF16Range(range)
        let oldBlock = note.blocks[index]

        switch command.kind {
        case .turnInto(let type):
            if type == .divider {
                mutateNote { note in
                    note.blocks[index].type = .divider
                    note.blocks[index].text = .empty
                    note.blocks[index].table = nil
                    note.blocks[index].imageAsset = nil
                    note.blocks[index].imagePath = nil
                    note.blocks[index].checked = false
                    note.blocks[index].collapsed = false
                }
                _ = insertParagraph(after: blockID)
                return
            }

            if type == .table {
                var table = oldBlock.table ?? TableData()
                if let first = table.rows.first, first.allSatisfy({ $0.isEmpty }), !cleanedText.isEmpty {
                    table.rows[0][0] = cleanedText.plainText
                }
                mutateNote { note in
                    note.blocks[index].type = .table
                    note.blocks[index].table = table
                    note.blocks[index].text = .empty
                    note.blocks[index].checked = false
                    note.blocks[index].collapsed = false
                }
                _ = insertParagraph(after: blockID)
                return
            }

            if type == .database {
                mutateNote { note in
                    note.blocks[index].type = .database
                    note.blocks[index].text = .empty
                    note.blocks[index].databasePath = nil
                    note.blocks[index].databaseViewID = nil
                    note.blocks[index].imageAsset = nil
                    note.blocks[index].imagePath = nil
                    note.blocks[index].table = nil
                    note.blocks[index].checked = false
                    note.blocks[index].collapsed = false
                }
                _ = insertParagraph(after: blockID)
                return
            }

            mutateNote { note in
                note.blocks[index].type = type
                note.blocks[index].text = cleanedText
                note.blocks[index].checked = false
                note.blocks[index].collapsed = false
                if type == .callout, note.blocks[index].calloutIcon.isEmpty {
                    note.blocks[index].calloutIcon = "💡"
                }
                if type != .code {
                    note.blocks[index].codeLanguage = ""
                }
                note.blocks[index].imageAsset = nil
                note.blocks[index].imagePath = nil
                note.blocks[index].databasePath = nil
                note.blocks[index].databaseViewID = nil
            }

            if type.isFocusableForNavigation {
                requestFocus(blockID, selection: cleanedText.utf16Count)
            }

        case .pdf:
            let panel = NSOpenPanel()
            panel.title = "Choose a PDF"
            panel.prompt = "Insert"
            panel.allowedContentTypes = [.pdf]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false

            guard panel.runModal() == .OK, let url = panel.url else {
                mutateNote { $0.blocks[index].text = cleanedText }
                return
            }

            guard let projectStore, let currentFileURL else {
                let alert = NSAlert()
                alert.messageText = "Open a project to insert a PDF"
                alert.informativeText = "PDF blocks are copied into the project's attachment folder."
                alert.runModal()
                mutateNote { $0.blocks[index].text = cleanedText }
                return
            }

            do {
                let path = try projectStore.importFile(
                    from: url,
                    forNoteAt: currentFileURL,
                    attachmentFolder: attachmentFolder
                )
                mutateNote { note in
                    note.blocks[index].type = .pdf
                    note.blocks[index].text = .empty
                    note.blocks[index].pdfPath = path
                    note.blocks[index].pdfPage = nil
                    note.blocks[index].imageAsset = nil
                    note.blocks[index].imagePath = nil
                    note.blocks[index].table = nil
                    note.blocks[index].checked = false
                    note.blocks[index].collapsed = false
                }
                refreshProjectFiles()
                _ = insertParagraph(after: blockID)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Could not import PDF"
                alert.informativeText = error.localizedDescription
                alert.runModal()
                mutateNote { $0.blocks[index].text = cleanedText }
            }
            return

        case .duplicate:
            var copy = oldBlock
            copy.id = UUID()
            copy.text = cleanedText
            copy.collapsed = false
            mutateNote { $0.blocks.insert(copy, at: index + 1) }
            if copy.type.isFocusableForNavigation {
                requestFocus(copy.id, selection: copy.text.utf16Count)
            }

        case .delete:
            mutateNote { $0.blocks.remove(at: index) }
            if note.blocks.isEmpty {
                let block = Block()
                mutateNote { $0.blocks = [block] }
                requestFocus(block.id, selection: 0)
            } else if index < note.blocks.count {
                let next = note.blocks[index]
                if next.type.isFocusableForNavigation {
                    requestFocus(next.id, selection: 0)
                }
            } else if let previous = note.blocks.last, previous.type.isFocusableForNavigation {
                requestFocus(previous.id, selection: previous.text.utf16Count)
            }
        }
    }

    // MARK: - Tables and images

    func setTableCell(blockID: UUID, row: Int, column: Int, value: String) {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }),
              var table = note.blocks[index].table,
              table.cell(row: row, column: column) != value else {
            return
        }
        table.setCell(row: row, column: column, value: value)
        mutateNote { $0.blocks[index].table = table }
    }

    func tableCell(blockID: UUID, row: Int, column: Int) -> String {
        guard let block = note.blocks.first(where: { $0.id == blockID }),
              let table = block.table else {
            return ""
        }
        return table.cell(row: row, column: column)
    }

    func addTableRow(_ blockID: UUID) {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }),
              var table = note.blocks[index].table else { return }
        table.addRow()
        mutateNote { $0.blocks[index].table = table }
    }

    func addTableColumn(_ blockID: UUID) {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }),
              var table = note.blocks[index].table else { return }
        table.addColumn()
        mutateNote { $0.blocks[index].table = table }
    }

    func removeTableRow(_ blockID: UUID) {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }),
              var table = note.blocks[index].table else { return }
        table.removeLastRow()
        mutateNote { $0.blocks[index].table = table }
    }

    func removeTableColumn(_ blockID: UUID) {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }),
              var table = note.blocks[index].table else { return }
        table.removeLastColumn()
        mutateNote { $0.blocks[index].table = table }
    }

    func imageURL(for block: Block) -> URL? {
        if let asset = block.imageAsset {
            return store.imageURL(for: asset)
        }
        if let path = block.imagePath, let projectStore {
            if let resolved = projectStore.resolveImagePath(path, relativeTo: currentFileURL) {
                if FileManager.default.fileExists(atPath: resolved.path) {
                    return resolved
                }
                if let found = projectStore.findFile(named: path) {
                    return found
                }
                return resolved
            }
        }
        return nil
    }

    func pdfURL(for block: Block) -> URL? {
        guard let path = block.pdfPath, let projectStore else { return nil }
        if let resolved = projectStore.resolveImagePath(path, relativeTo: currentFileURL) {
            if FileManager.default.fileExists(atPath: resolved.path) {
                return resolved
            }
            if let found = projectStore.findFile(named: path) {
                return found
            }
            return resolved
        }
        return nil
    }

    func importDroppedFiles(_ urls: [URL], before targetID: UUID?) {
        let blocks = urls.compactMap { makeDroppedBlock(from: $0) }
        guard !blocks.isEmpty else { return }

        let index: Int
        if let targetID,
           let targetIndex = note.blocks.firstIndex(where: { $0.id == targetID }) {
            index = targetIndex
        } else {
            index = note.blocks.count
        }

        mutateNote { note in
            note.blocks.insert(contentsOf: blocks, at: min(index, note.blocks.count))
        }
        refreshProjectFiles()
    }

    private func makeDroppedBlock(from url: URL) -> Block? {
        let ext = url.pathExtension.lowercased()
        let isPDF = ext == "pdf"
        let isImage = UTType(filenameExtension: ext)?.conforms(to: .image) == true

        guard isPDF || isImage else { return nil }

        guard let currentFileURL, let projectStore else {
            guard isImage,
                  let asset = try? store.importImage(from: url) else {
                return nil
            }
            return Block(type: .image, imageAsset: asset)
        }

        let path: String
        if let relative = projectStore.relativePath(from: currentFileURL, to: url) {
            path = relative
        } else if let imported = try? projectStore.importFile(
            from: url,
            forNoteAt: currentFileURL,
            attachmentFolder: attachmentFolder
        ) {
            path = imported
        } else {
            path = url.path
        }

        if isPDF {
            return Block(type: .pdf, pdfPath: path)
        }
        return Block(type: .image, imagePath: path, usesWikiImageSyntax: true)
    }

    func chooseImage(for blockID: UUID) {
        let panel = NSOpenPanel()
        panel.title = "Choose an image"
        panel.prompt = "Insert"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { return }

            if let projectStore, let currentFileURL {
                let path = try projectStore.importImage(
                    from: url,
                    forNoteAt: currentFileURL,
                    attachmentFolder: attachmentFolder
                )
                mutateNote { note in
                    note.blocks[index].imagePath = path
                    note.blocks[index].imageAsset = nil
                }
            } else {
                let asset = try store.importImage(from: url)
                mutateNote { note in
                    note.blocks[index].imageAsset = asset
                    note.blocks[index].imagePath = nil
                }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not import image"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    func removeImage(from blockID: UUID) {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        mutateNote { note in
            note.blocks[index].imageAsset = nil
            note.blocks[index].imagePath = nil
        }
    }

    // MARK: - Databases

    func databaseFolders() -> [String] {
        guard let projectURL else { return [] }
        return DatabaseStore.listFolders(projectRoot: projectURL)
    }

    func setDatabasePath(_ path: String, for blockID: UUID) {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        mutateNote { note in
            note.blocks[index].databasePath = path
            note.blocks[index].databaseViewID = DatabaseLayout.list.rawValue
        }
    }

    func setDatabaseViewID(_ viewID: String, for blockID: UUID) {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        mutateNote { note in
            note.blocks[index].databaseViewID = viewID
        }
    }

    func openDatabaseRow(_ row: DatabaseRow) {
        let file = projectFiles.first(where: {
            $0.url.standardizedFileURL == row.url.standardizedFileURL
        }) ?? ProjectFile(
            url: row.url,
            relativePath: row.relativePath,
            modifiedAt: row.modifiedAt
        )

        if row.isMarkdown {
            guard currentFileURL?.standardizedFileURL != row.url.standardizedFileURL else {
                return
            }
            pushCurrentFileForBackNavigation()
            openFile(file, skipSave: false)
        } else {
            presentAsset(file)
        }
    }

    @discardableResult
    func createDatabaseRow(
        in folderURL: URL,
        title: String = "Untitled",
        values: [String: String] = [:]
    ) -> URL? {
        do {
            let url = try DatabaseStore.createRow(
                folderURL: folderURL,
                title: title,
                values: values
            )
            refreshProjectFiles()
            let relative = projectURL.map {
                DatabaseStore.relativePath(from: $0, to: url)
            } ?? url.lastPathComponent
            let file = projectFiles.first(where: {
                $0.url.standardizedFileURL == url.standardizedFileURL
            }) ?? ProjectFile(
                url: url,
                relativePath: relative,
                modifiedAt: Date()
            )
            pushCurrentFileForBackNavigation()
            openFile(file, skipSave: false)
            return url
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not create database row"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return nil
        }
    }

    /// Keeps the open editor in sync when a database property is edited for
    /// the note that is currently open. Returns true when the URL matched.
    @discardableResult
    func syncDatabasePropertyValue(_ value: String, propertyID: String, for url: URL) -> Bool {
        guard currentFileURL?.standardizedFileURL == url.standardizedFileURL else {
            return false
        }
        mutateNote { note in
            let base = note.frontmatter ?? "---\n---\n"
            note.frontmatter = DatabaseStore.updatingFrontmatter(
                base,
                values: [propertyID: value]
            )
        }
        return true
    }

    /// Updates a database property on the note that is currently open. The
    /// value is written to frontmatter and saved with the note.
    func setNoteDatabaseValue(_ value: String, for property: DatabaseProperty) {
        guard !property.type.isComputed else { return }
        mutateNote { note in
            let base = note.frontmatter ?? "---\n---\n"
            note.frontmatter = DatabaseStore.updatingFrontmatter(
                base,
                values: [property.id: value]
            )
        }
    }

    // MARK: - Projects

    func openProjectPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open a Folder as a Project"
        panel.prompt = "Open Project"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = "Choose a folder of Markdown files."
        panel.directoryURL = projectURL

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(at: url)
    }

    func openProject(at url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            let alert = NSAlert()
            alert.messageText = "Could not open project"
            alert.informativeText = "Please choose a folder."
            alert.runModal()
            return
        }

        saveNow()

        let standardized = url.standardizedFileURL
        projectURL = standardized
        projectStore = ProjectStore(folderURL: standardized)
        currentFileURL = nil
        selectedFileID = nil
        focusedBlockID = nil
        slashMenu = nil
        dropTarget = nil
        navigationStack.removeAll()
        presentedAsset = nil

        UserDefaults.standard.set(standardized.path, forKey: Self.lastProjectPathKey)
        UserDefaults.standard.removeObject(forKey: Self.lastSelectedPathKey)
        refreshProjectFiles()

        // Opening a folder shows the empty state until the user picks a note.
        currentFileURL = nil
        selectedFileID = nil
        note = Note(title: "Untitled", blocks: [Block()])
        hasUnsavedChanges = false
        saveState = .saved
    }

    func closeProject() {
        saveNow()
        projectURL = nil
        projectStore = nil
        projectFiles = []
        selectedFileID = nil
        currentFileURL = nil
        UserDefaults.standard.removeObject(forKey: Self.lastProjectPathKey)

        if let loaded = store.load() {
            note = loaded
        } else {
            note = .welcome
            try? store.save(note)
        }

        focusedBlockID = nil
        focusRequest = nil
        slashMenu = nil
        dropTarget = nil
        navigationStack.removeAll()
        presentedAsset = nil
        hasUnsavedChanges = false
        saveState = .saved
        if let first = note.blocks.first(where: { $0.type.isFocusableForNavigation }) {
            requestFocus(first.id, selection: 0)
        }
    }

    func refreshProjectFiles() {
        guard let projectStore else {
            projectFiles = []
            return
        }

        do {
            let files = try projectStore.listProjectFiles()
            projectFiles = files

            if let currentFileURL,
               let match = files.first(where: {
                   $0.url.standardizedFileURL == currentFileURL.standardizedFileURL
               }) {
                selectedFileID = match.id
            } else if let selectedFileID,
                      !files.contains(where: { $0.id == selectedFileID }) {
                self.selectedFileID = nil
            }
        } catch {
            NSLog("Luminotes: could not list project files: \(error)")
        }
    }

    func openFile(_ file: ProjectFile) {
        guard file.isMarkdown else {
            presentAsset(file)
            return
        }
        navigationStack.removeAll()
        openFile(file, skipSave: false)
    }

    func presentAsset(_ file: ProjectFile) {
        guard file.isAsset else { return }
        presentedAsset = file
    }

    func goBack() {
        guard let previous = navigationStack.popLast() else { return }
        openFile(previous, skipSave: false)
    }

    private func pushCurrentFileForBackNavigation() {
        guard let currentFileURL, let projectURL else { return }
        if navigationStack.last?.url.standardizedFileURL == currentFileURL.standardizedFileURL {
            return
        }
        let relative = DatabaseStore.relativePath(from: projectURL, to: currentFileURL)
        let file = projectFiles.first(where: {
            $0.url.standardizedFileURL == currentFileURL.standardizedFileURL
        }) ?? ProjectFile(
            url: currentFileURL,
            relativePath: relative,
            modifiedAt: Date()
        )
        navigationStack.append(file)
    }

    private func openFile(_ file: ProjectFile, skipSave: Bool) {
        if !skipSave {
            saveNow()
        }

        guard let projectStore else { return }

        let previousURL = currentFileURL
        let targetURL: URL
        if let previousURL,
           previousURL.standardizedFileURL == file.url.standardizedFileURL,
           FileManager.default.fileExists(atPath: previousURL.path) {
            targetURL = previousURL
        } else {
            targetURL = file.url
        }

        do {
            let markdown = try projectStore.readMarkdown(at: targetURL)
            let document = MarkdownParser.parse(markdown)
            let title = targetURL.deletingPathExtension().lastPathComponent

            note = Note(
                title: title,
                blocks: document.blocks,
                frontmatter: document.frontmatter
            )
            currentFileURL = targetURL
            refreshProjectFiles()
            selectedFileID = projectFiles.first(where: {
                $0.url.standardizedFileURL == targetURL.standardizedFileURL
            })?.id ?? file.relativePath

            focusedBlockID = nil
            lastFocusedBlockID = nil
            slashMenu = nil
            focusRequest = nil
            dropTarget = nil
            hasUnsavedChanges = false
            saveState = .saved
            UserDefaults.standard.set(selectedFileID, forKey: Self.lastSelectedPathKey)

            if let first = note.blocks.first(where: { $0.type.isFocusableForNavigation }) {
                requestFocus(first.id, selection: 0)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not open Markdown file"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    func createProjectNote() {
        guard let projectStore else {
            newScratchNote()
            return
        }

        saveNow()

        do {
            let file = try projectStore.createNote()
            refreshProjectFiles()
            openFile(file, skipSave: true)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not create note"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    func openLink(_ url: URL) -> Bool {
        if let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            NSWorkspace.shared.open(url)
            return true
        }

        guard url.scheme?.lowercased() == "luminotes",
              url.host == "open",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let target = components.queryItems?
                .first(where: { $0.name == "target" })?.value?
                .removingPercentEncoding,
              !target.isEmpty else {
            return false
        }

        let normalized = target.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetStem = (normalized as NSString).deletingPathExtension

        if let file = projectFiles.first(where: { file in
            file.displayName.localizedCaseInsensitiveCompare(normalized) == .orderedSame ||
                file.displayName.localizedCaseInsensitiveCompare(targetStem) == .orderedSame ||
                file.relativePath.localizedCaseInsensitiveCompare(normalized) == .orderedSame ||
                file.url.lastPathComponent.localizedCaseInsensitiveCompare(normalized) == .orderedSame
        }) {
            openFile(file)
            return true
        }

        guard let projectStore else { return false }
        if let fileURL = projectStore.findFile(named: normalized) {
            let ext = fileURL.pathExtension.lowercased()
            if ext == "md" || ext == "markdown" {
                let base = projectURL?.standardizedFileURL.path ?? ""
                let path = fileURL.standardizedFileURL.path
                let relative = path.hasPrefix(base + "/")
                    ? String(path.dropFirst(base.count + 1))
                    : fileURL.lastPathComponent
                openFile(
                    ProjectFile(
                        url: fileURL.standardizedFileURL,
                        relativePath: relative,
                        modifiedAt: Date()
                    )
                )
            } else {
                NSWorkspace.shared.open(fileURL)
            }
            return true
        }

        return false
    }

    func revealCurrentFileInFinder() {
        guard let currentFileURL else {
            revealProjectInFinder()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([currentFileURL])
    }

    func revealProjectInFinder() {
        if let projectURL {
            NSWorkspace.shared.open(projectURL)
        }
    }

    private func restoreLastProject() {
        guard let path = UserDefaults.standard.string(forKey: Self.lastProjectPathKey) else { return }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            UserDefaults.standard.removeObject(forKey: Self.lastProjectPathKey)
            return
        }

        projectURL = url
        projectStore = ProjectStore(folderURL: url)
        refreshProjectFiles()
        navigationStack.removeAll()

        // Restore the note the user last had open, but never pick one for them.
        guard let preferred = UserDefaults.standard.string(forKey: Self.lastSelectedPathKey),
              let file = projectFiles.first(where: {
                  $0.isMarkdown && $0.relativePath == preferred
              }) else {
            currentFileURL = nil
            selectedFileID = nil
            note = Note(title: "Untitled", blocks: [Block()])
            hasUnsavedChanges = false
            saveState = .saved
            return
        }
        openFile(file, skipSave: true)
    }

    // MARK: - Note actions

    func newNote() {
        if isProjectOpen {
            createProjectNote()
        } else {
            newScratchNote()
        }
    }

    private func newScratchNote() {
        saveNow()
        let fresh = Note(title: "Untitled", blocks: [Block()])
        note = fresh
        lastFocusedBlockID = fresh.blocks.first?.id
        focusedBlockID = nil
        slashMenu = nil
        hasUnsavedChanges = true
        scheduleSave()
        if let first = fresh.blocks.first {
            requestFocus(first.id, selection: 0)
        }
    }

    func exportMarkdown() {
        let panel = NSSavePanel()
        let safeTitle = note.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        panel.nameFieldStringValue = (safeTitle.isEmpty ? "Untitled" : safeTitle) + ".md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let markdown = MarkdownCodec.export(note)
            try markdown.write(to: url, atomically: true, encoding: .utf8)

            let exportDirectory = url.deletingLastPathComponent()
            let imageAssets = note.blocks.compactMap(\.imageAsset)
            if !imageAssets.isEmpty {
                let assetsDirectory = exportDirectory.appendingPathComponent("Assets", isDirectory: true)
                try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
                for asset in imageAssets {
                    let source = store.imageURL(for: asset)
                    let destination = assetsDirectory.appendingPathComponent(asset)
                    if FileManager.default.fileExists(atPath: source.path),
                       !FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.copyItem(at: source, to: destination)
                    }
                }
            }

            if let projectStore {
                for path in note.blocks.compactMap(\.imagePath) {
                    guard !path.hasPrefix("/"),
                          !path.contains("://"),
                          let source = projectStore.resolveImagePath(path, relativeTo: currentFileURL) else {
                        continue
                    }
                    let destination = exportDirectory.appendingPathComponent(path)
                    guard FileManager.default.fileExists(atPath: source.path),
                          !FileManager.default.fileExists(atPath: destination.path) else {
                        continue
                    }
                    try FileManager.default.createDirectory(
                        at: destination.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try FileManager.default.copyItem(at: source, to: destination)
                }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not export Markdown"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
