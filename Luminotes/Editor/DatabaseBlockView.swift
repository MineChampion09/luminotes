import AppKit
import SwiftUI

struct DatabaseBlockView: View {
    @ObservedObject var viewModel: EditorViewModel
    let block: Block

    @State private var config: DatabaseConfig?
    @State private var rows: [DatabaseRow] = []
    @State private var folderURL: URL?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingSettings = false
    @State private var settingsInitialTab: DatabaseSettingsTab = .properties
    @State private var showingNewRow = false
    @State private var showingRenameView = false
    @State private var renamingViewID: String?
    @State private var renameText = ""
    @State private var newRowGroupValue: String?
    @State private var dropTargetColumn: String?

    private var currentView: DatabaseView? {
        guard let config else { return nil }
        return config.view(for: block.databaseViewID)
    }

    private var visibleProperties: [DatabaseProperty] {
        guard let config, let view = currentView else { return [] }
        let selected = config.properties.filter { view.visiblePropertyIDs.contains($0.id) }
        let title = config.properties.first { $0.type == .title }
        if let title, !selected.contains(where: { $0.id == title.id }) {
            return [title] + selected
        }
        return selected.isEmpty ? config.properties : selected
    }

    var body: some View {
        Group {
            if block.databasePath == nil {
                chooseFolderView
            } else if let config, let folderURL {
                databaseView(config: config, folderURL: folderURL)
            } else if isLoading {
                loadingView
            } else {
                errorView
            }
        }
        .onAppear(perform: reload)
        .onChange(of: block.databasePath) { _, _ in reload() }
        .onChange(of: block.databaseViewID) { _, _ in reload() }
        .onChange(of: viewModel.projectFiles) { _, _ in reloadRows() }
        .sheet(isPresented: $showingSettings) {
            settingsSheet
        }
        .sheet(isPresented: $showingNewRow) {
            newRowSheet
        }
        .sheet(isPresented: $showingRenameView) {
            renameViewSheet
        }
    }

    // MARK: - Main shell

    private func databaseView(config: DatabaseConfig, folderURL: URL) -> some View {
        VStack(spacing: 0) {
            header(config: config, folderURL: folderURL)
            if hasActiveOptions(config) {
                optionsBar(config: config)
            }
            Divider().overlay(Palette.border.opacity(0.55))
            content(config: config)
        }
        .glassPanel(cornerRadius: 14)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.border.opacity(0.45), lineWidth: 0.6)
        )
    }

    private func header(config: DatabaseConfig, folderURL: URL) -> some View {
        let view = config.view(for: block.databaseViewID)

        return VStack(spacing: 0) {
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(folderURL.lastPathComponent)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Palette.primaryText)
                        .lineLimit(1)
                    Text("\(rows.count) \(rows.count == 1 ? "page" : "pages")")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.tertiaryText)
                }

                Spacer(minLength: 12)

                Button {
                    newRowGroupValue = nil
                    showingNewRow = true
                } label: {
                    Label("New", systemImage: "plus")
                        .padding(.horizontal, 6)
                }
                .glassButtonStyle(prominent: true)
                .help("Create a page in this database")

                Button {
                    settingsInitialTab = .properties
                    showingSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.secondaryText)
                        .frame(width: 26, height: 26)
                        .glassPanel(cornerRadius: 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Database settings")
            }
            .padding(.horizontal, 11)
            .frame(height: 42)

            HStack(spacing: 4) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(config.views) { item in
                            viewTab(item, isActive: item.id == view.id, config: config)
                        }
                    }
                    .padding(.horizontal, 1)
                }

                Spacer(minLength: 4)

                Menu {
                    ForEach(DatabaseLayout.allCases) { layout in
                        Button {
                            addView(layout: layout, config: config)
                        } label: {
                            Label(layout.title, systemImage: layout.icon)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryText)
                        .frame(width: 22, height: 22)
                        .glassPanel(cornerRadius: 5)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Add view")
            }
            .padding(.horizontal, 9)
            .padding(.bottom, 7)
        }
        .background(Palette.hover.opacity(0.32))
    }

    private func viewTab(
        _ item: DatabaseView,
        isActive: Bool,
        config: DatabaseConfig
    ) -> some View {
        Button {
            viewModel.setDatabaseViewID(item.id, for: block.id)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: item.layout.icon)
                    .font(.system(size: 9, weight: .medium))
                Text(item.name)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isActive ? Palette.primaryText : Palette.secondaryText)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .glassPanel(
                cornerRadius: 6,
                tint: isActive ? Palette.selection : nil
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename…") {
                beginRename(item)
            }
            Button("Duplicate") {
                duplicateView(item, config: config)
            }
            Divider()
            Button("Delete", role: .destructive) {
                deleteView(item, config: config)
            }
            .disabled(config.views.count <= 1)
        }
    }

    private func optionsBar(config: DatabaseConfig) -> some View {
        let view = config.view(for: block.databaseViewID)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(view.filters) { filter in
                    DatabaseFilterChip(
                        text: filterDescription(filter, config: config),
                        onRemove: {
                            mutateView { $0.filters.removeAll { $0.id == filter.id } }
                        }
                    )
                }

                ForEach(view.sorts) { sort in
                    if let property = config.property(for: sort.propertyID) {
                        DatabaseSortChip(
                            text: "\(property.name) \(sort.ascending ? "↑" : "↓")",
                            onRemove: {
                                mutateView { $0.sorts.removeAll { $0.id == sort.id } }
                            }
                        )
                    }
                }

                if let groupID = view.groupPropertyID,
                   let property = config.property(for: groupID) {
                    DatabaseGroupChip(
                        text: property.name,
                        onRemove: {
                            mutateView { $0.groupPropertyID = nil }
                        }
                    )
                }

                if !view.filters.isEmpty || !view.sorts.isEmpty {
                    Button("Clear filters & sorts") {
                        mutateView {
                            $0.filters.removeAll()
                            $0.sorts.removeAll()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.tertiaryText)
                    .padding(.horizontal, 5)
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 32)
        }
        .background(Palette.hover.opacity(0.18))
    }

    private func filterDescription(_ filter: DatabaseFilter, config: DatabaseConfig) -> String {
        let name = config.property(for: filter.propertyID)?.name ?? "Property"
        if filter.op.needsValue {
            return "\(name) \(filter.op.title) \(filter.value)"
        }
        return "\(name) \(filter.op.title)"
    }

    // MARK: - Content

    @ViewBuilder
    private func content(config: DatabaseConfig) -> some View {
        let view = config.view(for: block.databaseViewID)
        let properties = visibleProperties
        let filtered = filteredRows(rows, view: view, config: config)
        let sorted = sortedRows(filtered, view: view, config: config)

        if rows.isEmpty {
            emptyDatabaseView
        } else if sorted.isEmpty {
            noResultsView
        } else {
            switch view.layout {
            case .table:
                tableContent(rows: sorted, properties: properties, config: config)
            case .board:
                boardContent(rows: sorted, properties: properties, config: config)
            case .list:
                listContent(rows: sorted, properties: properties, config: config)
            case .gallery:
                galleryContent(rows: sorted, properties: properties, config: config)
            }
        }
    }

    // MARK: - Table

    private func tableContent(
        rows: [DatabaseRow],
        properties: [DatabaseProperty],
        config: DatabaseConfig
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(spacing: 0) {
                tableHeader(properties: properties, config: config)

                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            DatabaseTableRow(
                                row: row,
                                properties: properties,
                                config: config,
                                onSetValue: { property, value in
                                    setValue(value, property: property, row: row)
                                },
                                onOpen: {
                                    viewModel.openDatabaseRow(row)
                                }
                            )
                            Divider().overlay(Palette.border.opacity(0.55))
                        }
                    }
                }
                .frame(maxHeight: 430)
            }
        }
    }

    private func tableHeader(
        properties: [DatabaseProperty],
        config: DatabaseConfig
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(properties) { property in
                DatabaseTableHeaderCell(
                    property: property,
                    config: config,
                    view: config.view(for: block.databaseViewID),
                    width: columnWidth(for: property),
                    onSort: { ascending in
                        mutateView { view in
                            view.sorts.removeAll { $0.propertyID == property.id }
                            view.sorts.insert(
                                DatabaseSort(propertyID: property.id, ascending: ascending),
                                at: 0
                            )
                        }
                    },
                    onRemoveSort: {
                        mutateView { view in
                            view.sorts.removeAll { $0.propertyID == property.id }
                        }
                    },
                    onHide: {
                        mutateView {
                            $0.visiblePropertyIDs.removeAll { $0 == property.id }
                        }
                    },
                    onEdit: {
                        settingsInitialTab = .properties
                        showingSettings = true
                    },
                    onDelete: property.type == .title
                        ? nil
                        : { deleteProperty(property) }
                )
            }
        }
        .glassPanel(cornerRadius: 0)
    }

    private func columnWidth(for property: DatabaseProperty) -> CGFloat {
        switch property.type {
        case .title: return 235
        case .text: return 180
        case .number: return 110
        case .select: return 150
        case .multiSelect: return 185
        case .date: return 140
        case .checkbox: return 90
        case .url: return 200
        case .fileType: return 110
        case .createdTime, .lastEditedTime: return 150
        case .formula: return 170
        }
    }

    // MARK: - Board

    private func boardContent(
        rows: [DatabaseRow],
        properties: [DatabaseProperty],
        config: DatabaseConfig
    ) -> some View {
        let view = config.view(for: block.databaseViewID)
        let groupProperty = config.property(for: view.groupPropertyID ?? "")
            ?? config.properties.first(where: { $0.type == .select })

        guard let groupProperty else {
            return AnyView(boardEmptyView(config: config))
        }

        var columns = groupProperty.options
        for row in rows {
            let value = row.rawValue(for: groupProperty, config: config)
            if !value.isEmpty, !columns.contains(value) {
                columns.append(value)
            }
        }

        let grouped = Dictionary(grouping: rows) { row -> String in
            let value = row.rawValue(for: groupProperty, config: config)
            return value.isEmpty ? "No group" : value
        }
        if grouped["No group"] != nil, !columns.contains("No group") {
            columns.append("No group")
        }

        return AnyView(
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(columns, id: \.self) { option in
                        boardColumn(
                            option: option,
                            rows: grouped[option] ?? [],
                            properties: properties,
                            groupProperty: groupProperty,
                            config: config
                        )
                    }
                }
                .padding(12)
            }
            .frame(minHeight: 200)
        )
    }

    private func boardColumn(
        option: String,
        rows: [DatabaseRow],
        properties: [DatabaseProperty],
        groupProperty: DatabaseProperty,
        config: DatabaseConfig
    ) -> some View {
        let isTargeted = dropTargetColumn == option

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Palette.tertiaryText.opacity(0.5))
                    .frame(width: 7, height: 7)

                Text(option)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(1)

                Text("\(rows.count)")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Palette.tertiaryText)
                    .padding(.horizontal, 5)
                    .frame(height: 16)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Palette.hover)
                    )

                Spacer(minLength: 4)

                Button {
                    newRowGroupValue = option == "No group" ? "" : option
                    showingNewRow = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryText)
                        .frame(width: 20, height: 20)
                        .glassPanel(cornerRadius: 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New page in \(option)")
            }
            .padding(.horizontal, 9)
            .padding(.top, 9)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 7) {
                    ForEach(rows) { row in
                        boardCard(
                            row: row,
                            properties: properties,
                            groupProperty: groupProperty,
                            config: config
                        )
                    }

                    if rows.isEmpty {
                        Text("Drop pages here")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.tertiaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 9)
            }
            .frame(maxHeight: 360)
        }
        .frame(width: 250, alignment: .top)
        .glassPanel(
            cornerRadius: 10,
            tint: isTargeted ? Palette.selection : nil
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isTargeted ? Palette.secondaryText.opacity(0.35) : Palette.border.opacity(0.4),
                    lineWidth: isTargeted ? 1.2 : 0.6
                )
        )
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first,
                  let row = self.rows.first(where: { $0.id == id }) else {
                return false
            }
            setValue(
                option == "No group" ? "" : option,
                property: groupProperty,
                row: row
            )
            dropTargetColumn = nil
            return true
        } isTargeted: { targeted in
            dropTargetColumn = targeted ? option : (dropTargetColumn == option ? nil : dropTargetColumn)
        }
    }

    private func boardCard(
        row: DatabaseRow,
        properties: [DatabaseProperty],
        groupProperty: DatabaseProperty,
        config: DatabaseConfig
    ) -> some View {
        DatabaseBoardCard(
            row: row,
            properties: properties,
            groupProperty: groupProperty,
            config: config,
            onOpen: { viewModel.openDatabaseRow(row) }
        )
        .onDrag {
            NSItemProvider(object: row.id as NSString)
        }
    }

    private func boardEmptyView(config: DatabaseConfig) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Palette.tertiaryText)
            Text("Group this board")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Palette.primaryText)
            Text("Choose a select property to create columns.")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.secondaryText)
            Menu("Choose property") {
                ForEach(config.properties.filter { $0.type == .select || $0.type == .multiSelect }) { property in
                    Button(property.name) {
                        mutateView { $0.groupPropertyID = property.id }
                    }
                }
            }
            .fixedSize()
            .glassButtonStyle()
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }

    // MARK: - List

    private func listContent(
        rows: [DatabaseRow],
        properties: [DatabaseProperty],
        config: DatabaseConfig
    ) -> some View {
        let view = config.view(for: block.databaseViewID)
        let groupProperty = config.property(for: view.groupPropertyID ?? "")
        let grouped = groupedRows(rows, property: groupProperty, config: config)
        let order = groupOrder(rows, property: groupProperty, config: config)

        return ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 0) {
                if let groupProperty {
                    ForEach(order, id: \.self) { option in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Palette.tertiaryText.opacity(0.5))
                                .frame(width: 6, height: 6)
                            Text(option)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Palette.secondaryText)
                            Text("\(grouped[option]?.count ?? 0)")
                                .font(.system(size: 9.5))
                                .foregroundStyle(Palette.tertiaryText)
                            Spacer()
                        }
                        .padding(.horizontal, 11)
                        .frame(height: 28)
                        .background(Palette.hover.opacity(0.22))

                        ForEach(grouped[option] ?? []) { row in
                            listRow(
                                row,
                                properties: properties,
                                config: config,
                                groupProperty: groupProperty
                            )
                        }
                    }
                } else {
                    ForEach(rows) { row in
                        listRow(
                            row,
                            properties: properties,
                            config: config,
                            groupProperty: nil
                        )
                    }
                }
            }
        }
        .frame(maxHeight: 430)
    }

    private func groupedRows(
        _ rows: [DatabaseRow],
        property: DatabaseProperty?,
        config: DatabaseConfig
    ) -> [String: [DatabaseRow]] {
        guard let property else { return [:] }
        return Dictionary(grouping: rows) { row -> String in
            let value = row.rawValue(for: property, config: config)
            return value.isEmpty ? "No group" : value
        }
    }

    private func groupOrder(
        _ rows: [DatabaseRow],
        property: DatabaseProperty?,
        config: DatabaseConfig
    ) -> [String] {
        guard let property else { return [] }
        var order = property.options
        for row in rows {
            let value = row.rawValue(for: property, config: config)
            if !value.isEmpty, !order.contains(value) {
                order.append(value)
            }
        }
        let hasUngrouped = rows.contains {
            $0.rawValue(for: property, config: config).isEmpty
        }
        if hasUngrouped, !order.contains("No group") {
            order.append("No group")
        }
        return order
    }

    private func listRow(
        _ row: DatabaseRow,
        properties: [DatabaseProperty],
        config: DatabaseConfig,
        groupProperty: DatabaseProperty?
    ) -> some View {
        DatabaseListRow(
            row: row,
            properties: properties,
            groupProperty: groupProperty,
            config: config,
            onOpen: { viewModel.openDatabaseRow(row) }
        )
    }

    // MARK: - Gallery

    private func galleryContent(
        rows: [DatabaseRow],
        properties: [DatabaseProperty],
        config: DatabaseConfig
    ) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 200), spacing: 12)],
                spacing: 12
            ) {
                ForEach(rows) { row in
                    DatabaseGalleryCard(
                        row: row,
                        properties: properties,
                        config: config,
                        onOpen: { viewModel.openDatabaseRow(row) }
                    )
                }
            }
            .padding(12)
        }
        .frame(maxHeight: 460)
    }

    // MARK: - Empty and error states

    private var emptyDatabaseView: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Palette.tertiaryText)
            Text("No pages yet")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Palette.primaryText)
            Text("Create the first page in this database.")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.secondaryText)
            Button {
                newRowGroupValue = nil
                showingNewRow = true
            } label: {
                Label("New page", systemImage: "plus")
                    .padding(.horizontal, 6)
            }
            .glassButtonStyle(prominent: true)
        }
        .frame(maxWidth: .infinity)
        .padding(34)
    }

    private var noResultsView: some View {
        VStack(spacing: 9) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Palette.tertiaryText)
            Text("No rows match this view")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.primaryText)
            Text("Adjust the filters or clear them to see every page.")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.secondaryText)
            Button("Clear filters") {
                mutateView {
                    $0.filters.removeAll()
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(Palette.primaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }

    private var loadingView: some View {
        HStack(spacing: 9) {
            ProgressView()
                .controlSize(.small)
            Text("Loading database…")
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(26)
        .glassPanel(cornerRadius: 12)
    }

    private var errorView: some View {
        VStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Palette.tertiaryText)
            Text(errorMessage ?? "Database unavailable")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
            if viewModel.projectURL != nil {
                Menu("Choose another folder") {
                    folderMenuItems
                }
                .fixedSize()
                .glassButtonStyle()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(26)
        .glassPanel(cornerRadius: 12)
    }

    private var chooseFolderView: some View {
        VStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Palette.hover)
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Palette.secondaryText)
            }
            .frame(width: 48, height: 48)

            Text("Database")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.primaryText)
            Text("Turn a project folder into a table, board, list, or gallery.")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)

            if viewModel.projectURL == nil {
                Text("Open a project first.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.tertiaryText)
            } else {
                Menu("Choose folder") {
                    folderMenuItems
                }
                .fixedSize()
                .glassButtonStyle(prominent: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .glassPanel(cornerRadius: 14)
    }

    @ViewBuilder
    private var folderMenuItems: some View {
        Button("Project root") {
            viewModel.setDatabasePath(".", for: block.id)
        }
        let folders = viewModel.databaseFolders()
        if !folders.isEmpty {
            Divider()
            ForEach(folders, id: \.self) { folder in
                Button(folder) {
                    viewModel.setDatabasePath(folder, for: block.id)
                }
            }
        }
    }

    // MARK: - Settings

    private var settingsSheet: some View {
        Group {
            if let config, let folderURL {
                DatabaseSettingsView(
                    config: config,
                    currentViewID: config.view(for: block.databaseViewID).id,
                    folderURL: folderURL,
                    initialTab: settingsInitialTab,
                    onChange: { updated in
                        applyConfig(updated)
                    },
                    onClose: {
                        showingSettings = false
                    }
                )
            }
        }
    }

    private var newRowSheet: some View {
        DatabaseNewRowSheet(
            folderName: folderURL?.lastPathComponent ?? "Database",
            groupValue: newRowGroupValue,
            onCreate: { title in
                createRow(title: title)
            },
            onCancel: {
                showingNewRow = false
                newRowGroupValue = nil
            }
        )
    }

    private var renameViewSheet: some View {
        DatabaseRenameViewSheet(
            name: renameText,
            onSave: { newName in
                renameView(to: newName)
            },
            onCancel: {
                showingRenameView = false
                renamingViewID = nil
            }
        )
    }

    // MARK: - Data loading

    private func reload() {
        guard let projectURL = viewModel.projectURL else {
            isLoading = false
            errorMessage = "Open a project to use databases."
            return
        }
        guard let path = block.databasePath, !path.isEmpty else {
            isLoading = false
            return
        }
        guard let folder = DatabaseStore.folderURL(for: path, projectRoot: projectURL) else {
            isLoading = false
            errorMessage = "Database folder not found."
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            isLoading = false
            errorMessage = "Database folder not found."
            return
        }

        folderURL = folder
        let configURL = DatabaseStore.configURL(for: folder)
        var loaded: DatabaseConfig
        if FileManager.default.fileExists(atPath: configURL.path) {
            loaded = DatabaseStore.loadConfig(for: folder)
        } else {
            loaded = .defaultConfig()
            try? DatabaseStore.saveConfig(loaded, for: folder)
        }
        if loaded.views.isEmpty {
            loaded = .defaultConfig()
            try? DatabaseStore.saveConfig(loaded, for: folder)
        }

        config = loaded
        if !loaded.views.contains(where: { $0.id == block.databaseViewID }) {
            viewModel.setDatabaseViewID(loaded.views[0].id, for: block.id)
        }
        isLoading = false
        errorMessage = nil
        reloadRows()
    }

    private func reloadRows() {
        guard let config, let folderURL, let projectURL = viewModel.projectURL else { return }
        rows = (try? DatabaseStore.listRows(
            folderURL: folderURL,
            projectRoot: projectURL,
            config: config
        )) ?? []
    }

    private func applyConfig(_ updated: DatabaseConfig) {
        guard let folderURL, !updated.views.isEmpty else { return }
        config = updated
        try? DatabaseStore.saveConfig(updated, for: folderURL)
        if !updated.views.contains(where: { $0.id == block.databaseViewID }) {
            viewModel.setDatabaseViewID(updated.views[0].id, for: block.id)
        }
        reloadRows()
    }

    private func mutateView(_ transform: (inout DatabaseView) -> Void) {
        guard var config, folderURL != nil else { return }
        let viewID = config.view(for: block.databaseViewID).id
        guard let index = config.views.firstIndex(where: { $0.id == viewID }) else { return }
        transform(&config.views[index])
        applyConfig(config)
    }

    private func mutateConfig(_ transform: (inout DatabaseConfig) -> Void) {
        guard var config else { return }
        transform(&config)
        applyConfig(config)
    }

    private func setValue(_ value: String, property: DatabaseProperty, row: DatabaseRow) {
        guard let config, let folderURL else { return }
        guard !property.type.isComputed else { return }
        do {
            let updated = try DatabaseStore.setValue(
                value,
                for: property,
                row: row,
                config: config,
                folderURL: folderURL
            )
            self.config = updated
            if row.isMarkdown {
                viewModel.syncDatabasePropertyValue(
                    value,
                    propertyID: property.id,
                    for: row.url
                )
            }
            reloadRows()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteProperty(_ property: DatabaseProperty) {
        guard property.type != .title else { return }
        mutateConfig { config in
            config.properties.removeAll { $0.id == property.id }
            for index in config.views.indices {
                config.views[index].visiblePropertyIDs.removeAll { $0 == property.id }
                config.views[index].sorts.removeAll { $0.propertyID == property.id }
                config.views[index].filters.removeAll { $0.propertyID == property.id }
                if config.views[index].groupPropertyID == property.id {
                    config.views[index].groupPropertyID = nil
                }
            }
        }
    }

    // MARK: - Rows

    private func createRow(title: String) {
        guard let folderURL else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmed.isEmpty ? "Untitled" : trimmed

        var initialValues: [String: String] = [:]
        if let groupValue = newRowGroupValue,
           !groupValue.isEmpty,
           let config,
           let view = currentView,
           let groupProperty = config.property(for: view.groupPropertyID ?? "") {
            initialValues[groupProperty.id] = groupValue
        }

        showingNewRow = false
        newRowGroupValue = nil
        viewModel.createDatabaseRow(
            in: folderURL,
            title: finalTitle,
            values: initialValues
        )
    }

    // MARK: - View management

    private func addView(layout: DatabaseLayout, config: DatabaseConfig) {
        var updated = config
        let name = uniqueViewName(layout.title, existing: updated.views.map(\.name))
        var visible = updated.properties.map(\.id)
        if layout == .board, let title = updated.properties.first(where: { $0.type == .title }) {
            visible = [title.id]
        }
        var groupID: String?
        if layout == .board {
            groupID = updated.properties.first(where: { $0.type == .select })?.id
            if let groupID {
                visible.append(groupID)
            }
        }
        let newView = DatabaseView(
            id: UUID().uuidString,
            name: name,
            layout: layout,
            visiblePropertyIDs: visible,
            groupPropertyID: groupID
        )
        updated.views.append(newView)
        applyConfig(updated)
        viewModel.setDatabaseViewID(newView.id, for: block.id)
    }

    private func duplicateView(_ item: DatabaseView, config: DatabaseConfig) {
        var updated = config
        var copy = item
        copy.id = UUID().uuidString
        copy.name = uniqueViewName("\(item.name) copy", existing: updated.views.map(\.name))
        if let index = updated.views.firstIndex(where: { $0.id == item.id }) {
            updated.views.insert(copy, at: index + 1)
        } else {
            updated.views.append(copy)
        }
        applyConfig(updated)
        viewModel.setDatabaseViewID(copy.id, for: block.id)
    }

    private func deleteView(_ item: DatabaseView, config: DatabaseConfig) {
        guard config.views.count > 1 else { return }
        var updated = config
        updated.views.removeAll { $0.id == item.id }
        applyConfig(updated)
        if block.databaseViewID == item.id, let first = updated.views.first {
            viewModel.setDatabaseViewID(first.id, for: block.id)
        }
    }

    private func beginRename(_ item: DatabaseView) {
        renamingViewID = item.id
        renameText = item.name
        showingRenameView = true
    }

    private func renameView(to newName: String) {
        guard let renamingViewID, var config else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = config.views.firstIndex(where: { $0.id == renamingViewID }) else {
            showingRenameView = false
            return
        }
        config.views[index].name = trimmed
        applyConfig(config)
        showingRenameView = false
        self.renamingViewID = nil
    }

    private func uniqueViewName(_ base: String, existing: [String]) -> String {
        let names = Set(existing.map { $0.lowercased() })
        if !names.contains(base.lowercased()) {
            return base
        }
        var counter = 2
        while names.contains("\(base) \(counter)".lowercased()) {
            counter += 1
        }
        return "\(base) \(counter)"
    }

    // MARK: - Filtering and sorting

    private func hasActiveOptions(_ config: DatabaseConfig) -> Bool {
        let view = config.view(for: block.databaseViewID)
        return !view.filters.isEmpty || !view.sorts.isEmpty || view.groupPropertyID != nil
    }

    private func filteredRows(
        _ rows: [DatabaseRow],
        view: DatabaseView,
        config: DatabaseConfig
    ) -> [DatabaseRow] {
        guard !view.filters.isEmpty else { return rows }
        return rows.filter { row in
            view.filters.allSatisfy { filter in
                DatabaseStore.matches(row, filter: filter, config: config)
            }
        }
    }

    private func sortedRows(
        _ rows: [DatabaseRow],
        view: DatabaseView,
        config: DatabaseConfig
    ) -> [DatabaseRow] {
        guard !view.sorts.isEmpty else { return rows }

        return rows.sorted { left, right in
            for sort in view.sorts {
                guard let property = config.property(for: sort.propertyID) else { continue }
                let result = compare(left, right, property: property, config: config)
                if result == .orderedSame { continue }
                return sort.ascending
                    ? result == .orderedAscending
                    : result == .orderedDescending
            }
            return left.title.localizedStandardCompare(right.title) == .orderedAscending
        }
    }

    private func compare(
        _ left: DatabaseRow,
        _ right: DatabaseRow,
        property: DatabaseProperty,
        config: DatabaseConfig
    ) -> ComparisonResult {
        switch property.type {
        case .number:
            let leftValue = Double(left.rawValue(for: property, config: config)) ?? 0
            let rightValue = Double(right.rawValue(for: property, config: config)) ?? 0
            if leftValue == rightValue { return .orderedSame }
            return leftValue < rightValue ? .orderedAscending : .orderedDescending

        case .date:
            let leftValue = DatabaseRow.isoFormatter.date(
                from: left.rawValue(for: property, config: config)
            ) ?? left.modifiedAt
            let rightValue = DatabaseRow.isoFormatter.date(
                from: right.rawValue(for: property, config: config)
            ) ?? right.modifiedAt
            if leftValue == rightValue { return .orderedSame }
            return leftValue < rightValue ? .orderedAscending : .orderedDescending

        case .createdTime, .lastEditedTime:
            let leftValue = property.type == .createdTime ? left.createdAt : left.modifiedAt
            let rightValue = property.type == .createdTime ? right.createdAt : right.modifiedAt
            if leftValue == rightValue { return .orderedSame }
            return leftValue < rightValue ? .orderedAscending : .orderedDescending

        case .checkbox:
            let leftValue = left.rawValue(for: property, config: config) == "true"
            let rightValue = right.rawValue(for: property, config: config) == "true"
            if leftValue == rightValue { return .orderedSame }
            return leftValue ? .orderedDescending : .orderedAscending

        default:
            return left.displayValue(for: property, config: config)
                .localizedStandardCompare(
                    right.displayValue(for: property, config: config)
                )
        }
    }
}

// MARK: - Table header

private struct DatabaseTableHeaderCell: View {
    let property: DatabaseProperty
    let config: DatabaseConfig
    let view: DatabaseView
    let width: CGFloat
    let onSort: (Bool) -> Void
    let onRemoveSort: () -> Void
    let onHide: () -> Void
    let onEdit: () -> Void
    let onDelete: (() -> Void)?

    @State private var isHovering = false

    private var sortIndex: Int? {
        view.sorts.firstIndex(where: { $0.propertyID == property.id })
    }

    private var sortAscending: Bool? {
        sortIndex.map { view.sorts[$0].ascending }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: property.type.icon)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(Palette.tertiaryText)

            Text(property.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(1)

            if let sortIndex {
                HStack(spacing: 1) {
                    Image(systemName: sortAscending == true ? "arrow.up" : "arrow.down")
                        .font(.system(size: 7.5, weight: .bold))
                    if view.sorts.count > 1 {
                        Text("\(sortIndex + 1)")
                            .font(.system(size: 7, weight: .bold))
                    }
                }
                .foregroundStyle(Palette.secondaryText)
            }

            Spacer(minLength: 0)

            Menu {
                Button("Sort ascending") { onSort(true) }
                Button("Sort descending") { onSort(false) }
                if sortIndex != nil {
                    Button("Remove sort") {
                        onRemoveSort()
                    }
                }
                Divider()
                Button("Hide property") { onHide() }
                Button("Edit property…") { onEdit() }
                if let onDelete {
                    Divider()
                    Button("Delete property", role: .destructive) { onDelete() }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(isHovering ? Palette.secondaryText : Palette.tertiaryText)
                    .frame(width: 16, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 8)
        .frame(width: width, height: 30)
        .background(
            Rectangle()
                .fill(isHovering ? Palette.hover : Color.clear)
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Palette.border.opacity(0.45))
                .frame(width: 0.6)
        }
        .onHover { isHovering = $0 }
    }
}

// MARK: - Table row

private struct DatabaseTableRow: View {
    let row: DatabaseRow
    let properties: [DatabaseProperty]
    let config: DatabaseConfig
    let onSetValue: (DatabaseProperty, String) -> Void
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(properties) { property in
                DatabaseCellView(
                    row: row,
                    property: property,
                    config: config,
                    onSetValue: { value in
                        onSetValue(property, value)
                    },
                    onOpen: onOpen
                )
                .frame(width: columnWidth(for: property), alignment: .leading)
            }
        }
        .background(isHovering ? Palette.hover.opacity(0.45) : Color.clear)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Open") { onOpen() }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([row.url])
            }
        }
    }

    private func columnWidth(for property: DatabaseProperty) -> CGFloat {
        switch property.type {
        case .title: return 235
        case .text: return 180
        case .number: return 110
        case .select: return 150
        case .multiSelect: return 185
        case .date: return 140
        case .checkbox: return 90
        case .url: return 200
        case .fileType: return 110
        case .createdTime, .lastEditedTime: return 150
        case .formula: return 170
        }
    }
}

// MARK: - Board card

private struct DatabaseBoardCard: View {
    let row: DatabaseRow
    let properties: [DatabaseProperty]
    let groupProperty: DatabaseProperty
    let config: DatabaseConfig
    let onOpen: () -> Void

    @State private var isHovering = false

    private var pills: [DatabaseProperty] {
        properties.filter {
            $0.type != .title && $0.id != groupProperty.id
        }
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    DatabaseRowIcon(row: row, size: 18)
                    Text(row.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    if isHovering {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Palette.tertiaryText)
                    }
                }

                if !pills.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(pills.prefix(2)) { property in
                            HStack(spacing: 4) {
                                Text(property.name)
                                    .font(.system(size: 8.5, weight: .medium))
                                    .foregroundStyle(Palette.tertiaryText)
                                    .frame(width: 46, alignment: .leading)
                                DatabasePropertyPill(
                                    property: property,
                                    row: row,
                                    config: config,
                                    compact: true
                                )
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(cornerRadius: 7)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Palette.border.opacity(0.55), lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Open") { onOpen() }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([row.url])
            }
        }
    }
}

// MARK: - List row

private struct DatabaseListRow: View {
    let row: DatabaseRow
    let properties: [DatabaseProperty]
    let groupProperty: DatabaseProperty?
    let config: DatabaseConfig
    let onOpen: () -> Void

    @State private var isHovering = false

    private var pills: [DatabaseProperty] {
        properties.filter {
            $0.type != .title && $0.id != groupProperty?.id
        }
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                DatabaseRowIcon(row: row, size: 20)

                Text(row.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 10)

                ForEach(pills.prefix(3)) { property in
                    DatabasePropertyPill(
                        property: property,
                        row: row,
                        config: config,
                        compact: true
                    )
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryText)
                    .opacity(isHovering ? 1 : 0)
            }
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(isHovering ? Palette.hover.opacity(0.5) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.border.opacity(0.4))
                .frame(height: 0.6)
        }
    }
}

// MARK: - Gallery card

private struct DatabaseGalleryCard: View {
    let row: DatabaseRow
    let properties: [DatabaseProperty]
    let config: DatabaseConfig
    let onOpen: () -> Void

    @State private var isHovering = false

    private var pills: [DatabaseProperty] {
        properties.filter { $0.type != .title }
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                DatabaseCoverView(row: row)

                Text(row.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !pills.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(pills.prefix(2)) { property in
                            HStack(spacing: 5) {
                                Text(property.name)
                                    .font(.system(size: 8.5, weight: .medium))
                                    .foregroundStyle(Palette.tertiaryText)
                                    .frame(width: 48, alignment: .leading)
                                DatabasePropertyPill(
                                    property: property,
                                    row: row,
                                    config: config,
                                    compact: true
                                )
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(cornerRadius: 10)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Palette.border.opacity(0.55), lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Open") { onOpen() }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([row.url])
            }
        }
    }
}

// MARK: - New row sheet

private struct DatabaseNewRowSheet: View {
    let folderName: String
    let groupValue: String?
    let onCreate: (String) -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Palette.hover)
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.secondaryText)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text("New page")
                        .font(.system(size: 13, weight: .semibold))
                    Text(folderName)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.tertiaryText)
                }
            }

            if let groupValue, !groupValue.isEmpty {
                HStack(spacing: 5) {
                    Text("Group")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Palette.tertiaryText)
                    DatabaseOptionPill(text: groupValue, compact: true)
                }
            }

            TextField("Page title", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .focused($focused)
                .onSubmit(create)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .glassButtonStyle(prominent: true)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 340)
        .background(Palette.page.opacity(0.5))
        .presentationBackground(.ultraThinMaterial)
        .onAppear {
            focused = true
        }
    }

    private func create() {
        onCreate(title)
    }
}

// MARK: - Rename view sheet

private struct DatabaseRenameViewSheet: View {
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @FocusState private var focused: Bool

    init(name: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        _name = State(initialValue: name)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename view")
                .font(.system(size: 13, weight: .semibold))

            TextField("View name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .focused($focused)
                .onSubmit {
                    onSave(name)
                }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(name)
                }
                .glassButtonStyle(prominent: true)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 320)
        .background(Palette.page.opacity(0.5))
        .presentationBackground(.ultraThinMaterial)
        .onAppear {
            focused = true
        }
    }
}
