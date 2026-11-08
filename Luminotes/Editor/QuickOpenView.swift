import SwiftUI

struct QuickOpenView: View {
    @ObservedObject var viewModel: EditorViewModel
    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    private var results: [ProjectFile] {
        let files = viewModel.projectFiles
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !trimmed.isEmpty else {
            return files.sorted { $0.modifiedAt > $1.modifiedAt }
        }

        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)

        return files
            .filter { file in
                let haystack = (file.displayName + " " + file.relativePath).lowercased()
                return tokens.allSatisfy { haystack.contains($0) }
            }
            .sorted { lhs, rhs in
                let leftScore = score(lhs, tokens: tokens)
                let rightScore = score(rhs, tokens: tokens)
                if leftScore != rightScore { return leftScore < rightScore }
                if lhs.isMarkdown != rhs.isMarkdown { return lhs.isMarkdown }
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    private func score(_ file: ProjectFile, tokens: [String]) -> Int {
        guard let first = tokens.first else { return 0 }
        let name = file.displayName.lowercased()
        let path = file.relativePath.lowercased()

        if name == first { return 0 }
        if name.hasPrefix(first) { return 1 }
        if name.contains(first) { return 2 }
        if path.contains(first) { return 3 }
        return 4
    }

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
            DispatchQueue.main.async {
                isSearchFocused = true
            }
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
                .onChange(of: query) { _, _ in
                    selectedIndex = 0
                }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.tertiaryText)
                }
                .buttonStyle(.plain)
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
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, file in
                        Button {
                            selectedIndex = index
                            openSelected()
                        } label: {
                            QuickOpenRow(
                                file: file,
                                isSelected: index == safeSelectedIndex
                            )
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            if hovering {
                                selectedIndex = index
                            }
                        }
                        .id(file.id)
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
            Text("\(results.count) file\(results.count == 1 ? "" : "s")")
        }
        .font(.system(size: 10, weight: .regular))
        .foregroundStyle(Palette.tertiaryText)
        .padding(.horizontal, 14)
        .frame(height: 30)
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
        let file = results[safeSelectedIndex]
        isPresented = false
        viewModel.openFile(file)
    }
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
