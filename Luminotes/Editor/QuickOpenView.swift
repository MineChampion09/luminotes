import SwiftUI

struct QuickOpenView: View {
    @ObservedObject var viewModel: EditorViewModel
    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var entries: [QuickOpenEntry] = []
    @State private var results: [QuickOpenEntry] = []
    @State private var totalMatches = 0
    @FocusState private var isSearchFocused: Bool

    private let maxVisibleResults = 200

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            VStack(spacing: 0) {
                searchField

                Divider()
                    .overlay(Palette.border.opacity(0.6))

                if results.isEmpty {
                    emptyState
                } else {
                    resultList
                }

                Divider()
                    .overlay(Palette.border.opacity(0.6))

                footer
            }
            .frame(width: 560)
            .glassPanel(cornerRadius: 16, tint: Palette.sidebarTint)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.22), radius: 28, x: 0, y: 14)
            .padding(.top, 96)
        }
        .onAppear {
            query = ""
            selectedIndex = 0
            rebuildEntries()
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
            refreshResults()
        }
        .onChange(of: viewModel.projectFiles) { _, _ in
            rebuildEntries()
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.secondaryText)

            TextField("Search files…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(Palette.primaryText)
                .focused($isSearchFocused)
                .onSubmit(openSelected)
                .onKeyPress(.upArrow) {
                    moveSelection(-1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    moveSelection(1)
                    return .handled
                }
                .onExitCommand {
                    isPresented = false
                }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.tertiaryText)
                }
                .buttonStyle(.plainPointer)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                        Button {
                            selectedIndex = index
                            open(entry)
                        } label: {
                            QuickOpenRow(
                                file: entry.file,
                                isSelected: index == safeSelectedIndex
                            )
                        }
                        .buttonStyle(.plainPointer)
                        .onHover { hovering in
                            if hovering {
                                selectedIndex = index
                            }
                        }
                        .id(entry.id)
                    }
                }
                .padding(6)
            }
            .frame(height: min(CGFloat(results.count) * 44 + 12, 360))
            .onChange(of: selectedIndex) { _, newValue in
                guard results.indices.contains(newValue) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(results[newValue].id, anchor: .center)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: emptyIcon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Palette.tertiaryText)

            Text(emptyTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.primaryText)

            Text(emptyMessage)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)

            if !viewModel.isProjectOpen {
                Button("Open Folder…") {
                    isPresented = false
                    viewModel.openProjectPanel()
                }
                .glassButtonStyle(prominent: true)
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("↑↓ Navigate")
            Text("↵ Open")
            Text("esc Close")
            Spacer(minLength: 0)
            Text(fileCountLabel)
        }
        .font(.system(size: 10, weight: .regular))
        .foregroundStyle(Palette.tertiaryText)
        .padding(.horizontal, 14)
        .frame(height: 30)
    }

    private var fileCountLabel: String {
        if totalMatches > results.count {
            return "\(results.count) of \(totalMatches) files"
        }
        return "\(totalMatches) file\(totalMatches == 1 ? "" : "s")"
    }

    private var safeSelectedIndex: Int {
        guard !results.isEmpty else { return 0 }
        return min(max(0, selectedIndex), results.count - 1)
    }

    private var emptyIcon: String {
        if !viewModel.isProjectOpen { return "folder" }
        return viewModel.projectFiles.isEmpty ? "doc.text" : "magnifyingglass"
    }

    private var emptyTitle: String {
        if !viewModel.isProjectOpen { return "No project open" }
        if viewModel.projectFiles.isEmpty { return "No files in this project" }
        return "No files found"
    }

    private var emptyMessage: String {
        if !viewModel.isProjectOpen { return "Open a folder to search its files." }
        if viewModel.projectFiles.isEmpty { return "Add a note or asset to this folder." }
        return "Try a different search."
    }

    private func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(max(0, safeSelectedIndex + delta), results.count - 1)
    }

    private func openSelected() {
        guard results.indices.contains(safeSelectedIndex) else { return }
        open(results[safeSelectedIndex])
    }

    private func open(_ entry: QuickOpenEntry) {
        isPresented = false
        viewModel.openFile(entry.file)
    }

    private func rebuildEntries() {
        entries = viewModel.projectFiles
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .map { file in
                QuickOpenEntry(
                    file: file,
                    name: file.displayName.lowercased(),
                    path: file.relativePath.lowercased()
                )
            }
        refreshResults()
    }

    private func refreshResults() {
        let all = searchResults(for: query, in: entries)
        totalMatches = all.count
        results = Array(all.prefix(maxVisibleResults))
        selectedIndex = min(max(0, selectedIndex), max(0, results.count - 1))
    }

    private func searchResults(
        for query: String,
        in entries: [QuickOpenEntry]
    ) -> [QuickOpenEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return entries }

        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        var matches: [(entry: QuickOpenEntry, score: Int)] = []
        matches.reserveCapacity(min(entries.count, 128))

        for entry in entries {
            guard let score = matchScore(entry, tokens: tokens) else { continue }
            matches.append((entry, score))
        }

        matches.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            if lhs.entry.file.isMarkdown != rhs.entry.file.isMarkdown {
                return lhs.entry.file.isMarkdown
            }
            if lhs.entry.file.modifiedAt != rhs.entry.file.modifiedAt {
                return lhs.entry.file.modifiedAt > rhs.entry.file.modifiedAt
            }
            return lhs.entry.file.displayName.localizedStandardCompare(
                rhs.entry.file.displayName
            ) == .orderedAscending
        }

        return matches.map(\.entry)
    }

    private func matchScore(_ entry: QuickOpenEntry, tokens: [String]) -> Int? {
        var total = 0
        for token in tokens {
            guard let score = tokenScore(token, entry: entry) else { return nil }
            total += score
        }
        return total
    }

    private func tokenScore(_ token: String, entry: QuickOpenEntry) -> Int? {
        if entry.name == token { return 0 }
        if entry.name.hasPrefix(token) { return 1 }
        if entry.name.contains(token) { return 2 }
        if entry.path.contains(token) { return 3 }
        if isSubsequence(token, of: entry.name) { return 4 }
        if isSubsequence(token, of: entry.path) { return 5 }
        return nil
    }

    private func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var index = haystack.startIndex
        for character in needle {
            guard let found = haystack[index...].firstIndex(of: character) else {
                return false
            }
            index = haystack.index(after: found)
        }
        return true
    }
}

private struct QuickOpenEntry: Identifiable {
    let file: ProjectFile
    let name: String
    let path: String

    var id: String { file.id }
}

private struct QuickOpenRow: View {
    let file: ProjectFile
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: file.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? Palette.primaryText : Palette.secondaryText)
                .frame(width: 20, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                Text(file.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(1)

                if !file.parentPath.isEmpty {
                    Text(file.parentPath)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.tertiaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Palette.tertiaryText)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Palette.selection : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
