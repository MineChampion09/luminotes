import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var searchText = ""
    @State private var collapsedFolders: Set<String> = []
    @State private var hasInitializedFolders = false

    private var filteredFiles: [ProjectFile] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.projectFiles }
        return viewModel.projectFiles.filter {
            $0.relativePath.localizedCaseInsensitiveContains(query)
        }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var tree: [SidebarNode] {
        SidebarNode.build(from: viewModel.projectFiles)
    }

    private var allFolderPaths: Set<String> {
        var paths: Set<String> = []

        func collect(_ nodes: [SidebarNode]) {
            for node in nodes {
                guard case .folder(_, let path, _, let children) = node else { continue }
                paths.insert(path)
                collect(children)
            }
        }

        collect(tree)
        return paths
    }

    var body: some View {
        ZStack {
            Palette.sidebarTint
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if viewModel.isProjectOpen {
                    projectContent
                } else {
                    noProjectContent
                }
            }
            .padding(.bottom, 6)
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Palette.border.opacity(0.55))
                .frame(width: 1)
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            initializeFoldersIfNeeded()
            revealSelectedFile()
        }
        .onChange(of: viewModel.projectURL) { _, _ in
            searchText = ""
            collapsedFolders = []
            hasInitializedFolders = false
        }
        .onChange(of: viewModel.selectedFileID) { _, _ in
            revealSelectedFile()
        }
        .onChange(of: viewModel.projectFiles) { _, _ in
            initializeFoldersIfNeeded()
            revealSelectedFile()
        }
    }

    @ViewBuilder
    private var projectContent: some View {
        VStack(spacing: 0) {
            projectHeader
                .padding(.horizontal, 10)
                .frame(height: 50)
                .glassPanel(cornerRadius: 12)
                .padding(.horizontal, 10)
                .padding(.top, 8)

            searchField
                .padding(.horizontal, 12)
                .padding(.top, 8)

            sidebarDivider
                .padding(.top, 8)

            fileList

            sidebarDivider

            sidebarFooter
        }
    }

    private var projectHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: "folder.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.secondaryText)

            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.projectName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(1)

                Text("Markdown project")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.tertiaryText)
            }

            Spacer(minLength: 4)

            Button {
                viewModel.createProjectNote()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Palette.secondaryText)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New note")

            Button {
                viewModel.refreshProjectFiles()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Palette.secondaryText)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Refresh files")
        }
        .contextMenu {
            Button("New Note") {
                viewModel.createProjectNote()
            }
            Button("Open Folder…") {
                viewModel.openProjectPanel()
            }
            Button("Reveal in Finder") {
                viewModel.revealProjectInFinder()
            }
            Divider()
            Button("Close Project") {
                viewModel.closeProject()
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Palette.tertiaryText)

            TextField("Search files", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.primaryText)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .glassPanel(cornerRadius: 9)
    }

    @ViewBuilder
    private var fileList: some View {
        if viewModel.projectFiles.isEmpty {
            emptyFileView
        } else if isSearching {
            if filteredFiles.isEmpty {
                noMatchesView
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredFiles) { file in
                            SidebarFileRow(
                                viewModel: viewModel,
                                file: file,
                                depth: 0,
                                showsParent: true
                            )
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(tree) { node in
                            SidebarNodeView(
                                viewModel: viewModel,
                                node: node,
                                collapsedFolders: $collapsedFolders
                            )
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    scrollToSelected(proxy)
                }
                .onChange(of: viewModel.selectedFileID) { _, _ in
                    scrollToSelected(proxy)
                }
            }
        }
    }

    private func scrollToSelected(_ proxy: ScrollViewProxy) {
        guard let selected = viewModel.selectedFileID else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeInOut(duration: 0.15)) {
                proxy.scrollTo(selected, anchor: .center)
            }
        }
    }

    private var emptyFileView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "doc.text")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Palette.tertiaryText)
            Text("No Markdown files")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
            Button("Create a note") {
                viewModel.createProjectNote()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Palette.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
    }

    private var noMatchesView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Palette.tertiaryText)
            Text("No matches")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
    }

    private var sidebarFooter: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.openProjectPanel()
            } label: {
                Label("Open Folder", systemImage: "folder")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Palette.secondaryText)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
            }
            .buttonStyle(.plain)
            .glassPanel(cornerRadius: 7)

            Spacer()

            Button {
                viewModel.revealProjectInFinder()
            } label: {
                Image(systemName: "finder")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Palette.secondaryText)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Reveal project in Finder")
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
    }

    private var sidebarDivider: some View {
        Rectangle()
            .fill(Palette.border.opacity(0.55))
            .frame(height: 1)
            .padding(.horizontal, 12)
    }

    private var noProjectContent: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Palette.hover)
                        .frame(width: 64, height: 64)

                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 25, weight: .light))
                        .foregroundStyle(Palette.secondaryText)
                }

                VStack(spacing: 5) {
                    Text("Open a folder")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.primaryText)

                    Text("Choose a folder of Markdown files to turn it into a project.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }

                Button {
                    viewModel.openProjectPanel()
                } label: {
                    Label("Choose Folder…", systemImage: "folder")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .glassButtonStyle(prominent: true)
                .controlSize(.small)
            }
            .padding(.horizontal, 22)

            Spacer()

            Text("Your notes stay in the folder you choose.")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Palette.tertiaryText)
                .padding(.bottom, 6)
        }
    }

    private func initializeFoldersIfNeeded() {
        guard viewModel.isProjectOpen,
              !hasInitializedFolders,
              !viewModel.projectFiles.isEmpty else {
            return
        }
        collapsedFolders = allFolderPaths
        hasInitializedFolders = true
    }

    private func revealSelectedFile() {
        guard let selected = viewModel.selectedFileID else { return }
        let components = selected.split(separator: "/")
        guard components.count > 1 else { return }

        var path = ""
        for component in components.dropLast() {
            path = path.isEmpty ? String(component) : "\(path)/\(component)"
            collapsedFolders.remove(path)
        }
    }
}

private enum SidebarNode: Identifiable {
    case folder(name: String, path: String, depth: Int, children: [SidebarNode])
    case file(ProjectFile, depth: Int)

    var id: String {
        switch self {
        case .folder(_, let path, _, _):
            return "folder:\(path)"
        case .file(let file, _):
            return "file:\(file.id)"
        }
    }

    static func build(from files: [ProjectFile]) -> [SidebarNode] {
        build(files: files, prefix: "", depth: 0)
    }

    private static func build(files: [ProjectFile], prefix: String, depth: Int) -> [SidebarNode] {
        var directFiles: [ProjectFile] = []
        var folderGroups: [String: [ProjectFile]] = [:]

        for file in files {
            let relative = prefix.isEmpty
                ? file.relativePath
                : String(file.relativePath.dropFirst(prefix.count + 1))
            let parts = relative.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)

            if parts.count == 1 {
                directFiles.append(file)
            } else {
                let folder = String(parts[0])
                folderGroups[folder, default: []].append(file)
            }
        }

        let folders = folderGroups.keys
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { name -> SidebarNode in
                let path = prefix.isEmpty ? name : "\(prefix)/\(name)"
                return .folder(
                    name: name,
                    path: path,
                    depth: depth,
                    children: build(files: folderGroups[name] ?? [], prefix: path, depth: depth + 1)
                )
            }

        let files = directFiles
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            .map { SidebarNode.file($0, depth: depth) }

        return folders + files
    }
}

private struct SidebarNodeView: View {
    @ObservedObject var viewModel: EditorViewModel
    let node: SidebarNode
    @Binding var collapsedFolders: Set<String>

    var body: some View {
        switch node {
        case .folder(let name, let path, let depth, let children):
            SidebarFolderRow(
                name: name,
                depth: depth,
                isCollapsed: collapsedFolders.contains(path)
            ) {
                if collapsedFolders.contains(path) {
                    collapsedFolders.remove(path)
                } else {
                    collapsedFolders.insert(path)
                }
            }

            if !collapsedFolders.contains(path) {
                ForEach(children) { child in
                    SidebarNodeView(
                        viewModel: viewModel,
                        node: child,
                        collapsedFolders: $collapsedFolders
                    )
                }
            }

        case .file(let file, let depth):
            SidebarFileRow(
                viewModel: viewModel,
                file: file,
                depth: depth,
                showsParent: false
            )
        }
    }
}

private struct SidebarFolderRow: View {
    let name: String
    let depth: Int
    let isCollapsed: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryText)
                    .frame(width: 10)

                Image(systemName: isCollapsed ? "folder" : "folder.fill")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Palette.secondaryText)
                    .frame(width: 14)

                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.primaryText.opacity(0.88))
                    .lineLimit(1)

                Spacer(minLength: 4)
            }
            .padding(.leading, CGFloat(depth) * 14 + 4)
            .padding(.trailing, 8)
            .frame(height: 32)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Palette.hover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct SidebarFileRow: View {
    @ObservedObject var viewModel: EditorViewModel
    let file: ProjectFile
    let depth: Int
    let showsParent: Bool
    @State private var isHovering = false

    private var isSelected: Bool {
        file.isMarkdown && viewModel.selectedFileID == file.id
    }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                viewModel.openFile(file)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isSelected ? "doc.text.fill" : file.icon)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(isSelected ? Palette.primaryText : Palette.secondaryText)
                        .frame(width: 15)

                    Text(file.displayName)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(Palette.primaryText)
                        .lineLimit(1)
                        .layoutPriority(1)

                    Spacer(minLength: 4)

                    if showsParent && !file.parentPath.isEmpty {
                        Text(file.parentPath)
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.tertiaryText)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, CGFloat(depth) * 14 + (depth == 0 ? 8 : 22))
                .padding(.trailing, 4)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isHovering && file.isAsset {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryText)
                    .frame(width: 20, height: 32)
                    .contentShape(Rectangle())
                    .onDrag {
                        NSItemProvider(object: file.url as NSURL)
                    }
                    .help("Drag into a note")
                    .padding(.trailing, 6)
            } else {
                Spacer()
                    .frame(width: 8)
            }
        }
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    isSelected
                        ? Palette.selection
                        : (isHovering ? Palette.hover : Color.clear)
                )
        )
        .id(file.id)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Open") {
                viewModel.openFile(file)
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            }
            Divider()
            Button("New Note in Project") {
                viewModel.createProjectNote()
            }
        }
    }

}
