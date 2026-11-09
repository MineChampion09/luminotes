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
    @State private var showingPropertyEditor = false
    @State private var showingNewRow = false
    @State private var showingFilterEditor = false
    @State private var newPropertyName = ""
    @State private var newPropertyType: DatabasePropertyType = .text
    @State private var newPropertyOptions = ""
    @State private var newRowTitle = ""
    @State private var newFilterPropertyID = ""
    @State private var newFilterOperator: DatabaseFilterOperator = .contains
    @State private var newFilterValue = ""

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
                VStack(spacing: 0) {
                    header(config: config, folderURL: folderURL)
                    Divider().overlay(Palette.border)
                    content(config: config, folderURL: folderURL)
                }
                .glassPanel(cornerRadius: 8)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if isLoading {
                ProgressView("Loading database…")
                    .frame(maxWidth: .infinity)
                    .padding(30)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(errorMessage ?? "Database unavailable")
                }
                .foregroundStyle(Palette.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(30)
            }
        }
        .onAppear(perform: reload)
        .onChange(of: block.databasePath) { _, _ in reload() }
        .onChange(of: block.databaseViewID) { _, _ in reload() }
        .onChange(of: viewModel.projectFiles) { _, _ in reload() }
        .sheet(isPresented: $showingPropertyEditor) {
            propertyEditor
        }
        .sheet(isPresented: $showingFilterEditor) {
            filterEditor
        }
        .sheet(isPresented: $showingNewRow) {
            newRowSheet
        }
    }

    private var chooseFolderView: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 24, weight: .light))
            Text("Database")
                .font(.system(size: 13, weight: .semibold))
            Text("Choose a folder to use as a database.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondaryText)

            if viewModel.projectURL == nil {
                Text("Open a project first.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tertiaryText)
            } else {
                Menu("Choose Folder…") {
                    ForEach(viewModel.databaseFolders(), id: \.self) { folder in
                        Button(folder) {
                            viewModel.setDatabasePath(folder, for: block.id)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .glassButtonStyle()
            }
        }
        .foregroundStyle(Palette.secondaryText)
        .frame(maxWidth: .infinity)
        .padding(30)
        .glassPanel(cornerRadius: 8)
    }

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
        var loaded = DatabaseStore.loadConfig(for: folder)
        for layout in DatabaseLayout.allCases
            where !loaded.views.contains(where: { $0.layout == layout }) {
            loaded.views.append(
                DatabaseView(
                    id: layout.rawValue,
                    name: layout.title,
                    layout: layout,
                    visiblePropertyIDs: loaded.properties.map(\.id)
                )
            )
        }
        if !FileManager.default.fileExists(atPath: DatabaseStore.configURL(for: folder).path) {
            try? DatabaseStore.saveConfig(loaded, for: folder)
        }
        config = loaded
        rows = (try? DatabaseStore.listRows(
            folderURL: folder,
            projectRoot: projectURL,
            config: loaded
        )) ?? []
        isLoading = false
        errorMessage = nil
    }

    private func saveConfig(_ updated: DatabaseConfig, for folderURL: URL) {
        config = updated
        try? DatabaseStore.saveConfig(updated, for: folderURL)
        if let projectURL = viewModel.projectURL {
            rows = (try? DatabaseStore.listRows(
                folderURL: folderURL,
                projectRoot: projectURL,
                config: updated
            )) ?? []
        }
    }

    private func mutateView(_ transform: (inout DatabaseView) -> Void) {
        guard var config, let folderURL else { return }
        let viewID = block.databaseViewID ?? config.views.first?.id ?? DatabaseLayout.table.rawValue
        guard let index = config.views.firstIndex(where: { $0.id == viewID }) else { return }
        transform(&config.views[index])
        saveConfig(config, for: folderURL)
    }

    private func mutateConfig(_ transform: (inout DatabaseConfig) -> Void) {
        guard var config, let folderURL else { return }
        transform(&config)
        saveConfig(config, for: folderURL)
    }

    private func setValue(_ value: String, property: DatabaseProperty, row: DatabaseRow) {
        guard let config, let folderURL, let projectURL = viewModel.projectURL else { return }
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
            rows = try DatabaseStore.listRows(
                folderURL: folderURL,
                projectRoot: projectURL,
                config: updated
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func header(config: DatabaseConfig, folderURL: URL) -> some View {
        let view = config.view(for: block.databaseViewID)

        return HStack(spacing: 8) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.secondaryText)

            Text(folderURL.lastPathComponent)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.primaryText)
                .lineLimit(1)

            Spacer()

            Menu {
                ForEach(DatabaseLayout.allCases) { layout in
                    Button {
                        viewModel.setDatabaseViewID(layout.rawValue, for: block.id)
                    } label: {
                        Label(layout.title, systemImage: layout.icon)
                    }
                }
            } label: {
                Label(view.layout.title, systemImage: view.layout.icon)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Palette.secondaryText)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            settingsMenu(config: config, view: view)

            Button {
                showingNewRow = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Palette.secondaryText)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New page")
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
    }

    private func settingsMenu(config: DatabaseConfig, view: DatabaseView) -> some View {
        Menu {
            Section("Rows") {
                ForEach(DatabaseRowSource.allCases) { source in
                    Button {
                        mutateConfig { $0.rowSource = source }
                    } label: {
                        if config.rowSource == source {
                            Label(source.title, systemImage: "checkmark")
                        } else {
                            Text(source.title)
                        }
                    }
                }
            }

            Section("Properties") {
                ForEach(config.properties) { property in
                    Button {
                        toggleVisibility(property)
                    } label: {
                        if view.visiblePropertyIDs.contains(property.id) {
                            Label(property.name, systemImage: "checkmark")
                        } else {
                            Text(property.name)
                        }
                    }
                }
                Button("Add property…") {
                    showingPropertyEditor = true
                }
            }

            Section("Filter") {
                if view.filters.isEmpty {
                    Text("No filters")
                } else {
                    ForEach(view.filters) { filter in
                        Button {
                            mutateView { $0.filters.removeAll { $0.id == filter.id } }
                        } label: {
                            let name = config.property(for: filter.propertyID)?.name ?? "Property"
                            Label(
                                filter.op.needsValue
                                    ? "\(name) \(filter.op.title) \(filter.value)"
                                    : "\(name) \(filter.op.title)",
                                systemImage: "xmark.circle"
                            )
                        }
                    }
                }
                Button("Add filter…") {
                    newFilterPropertyID = config.properties.first?.id ?? ""
                    newFilterOperator = .contains
                    newFilterValue = ""
                    showingFilterEditor = true
                }
            }

            Section("Sort") {
                ForEach(config.properties) { property in
                    Button {
                        mutateView {
                            $0.sortPropertyID = property.id
                            $0.sortAscending = true
                        }
                    } label: {
                        if view.sortPropertyID == property.id {
                            Label(property.name, systemImage: "checkmark")
                        } else {
                            Text(property.name)
                        }
                    }
                }
                Button("Clear sort") {
                    mutateView { $0.sortPropertyID = nil }
                }
                Toggle("Ascending", isOn: Binding(
                    get: { config.view(for: block.databaseViewID).sortAscending },
                    set: { ascending in
                        mutateView { $0.sortAscending = ascending }
                    }
                ))
            }

            Section("Group by") {
                Button("None") {
                    mutateView { $0.groupPropertyID = nil }
                }
                ForEach(config.properties.filter { $0.type == .select || $0.type == .multiSelect }) { property in
                    Button(property.name) {
                        mutateView { $0.groupPropertyID = property.id }
                    }
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Database settings")
    }

    @ViewBuilder
    private func content(config: DatabaseConfig, folderURL: URL) -> some View {
        let view = config.view(for: block.databaseViewID)
        let properties = visibleProperties
        let filtered = filteredRows(rows, view: view, config: config)
        let sorted = sortedRows(filtered, view: view, config: config)

        switch view.layout {
        case .table:
            tableContent(rows: sorted, properties: properties, config: config)
        case .board:
            boardContent(rows: sorted, properties: properties, config: config)
        case .list:
            listContent(rows: sorted, properties: properties)
        case .gallery:
            galleryContent(rows: sorted, properties: properties)
        }
    }

    private func tableContent(
        rows: [DatabaseRow],
        properties: [DatabaseProperty],
        config: DatabaseConfig
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(properties) { property in
                        tableHeaderCell(property, view: config.view(for: block.databaseViewID))
                            .frame(width: columnWidth(for: property), alignment: .leading)
                    }
                }
                .background(Palette.hover)

                ForEach(rows) { row in
                    HStack(spacing: 0) {
                        ForEach(properties) { property in
                            DatabaseCellView(
                                row: row,
                                property: property,
                                value: row.rawValue(for: property),
                                onSetValue: { value in
                                    setValue(value, property: property, row: row)
                                },
                                onOpen: {
                                    viewModel.openDatabaseRow(row)
                                }
                            )
                            .frame(width: columnWidth(for: property), alignment: .leading)
                        }
                    }
                    .background(Palette.page)
                    Divider().overlay(Palette.border)
                }

                Button {
                    showingNewRow = true
                } label: {
                    Label("New page", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.secondaryText)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minHeight: 120)
    }

    private func tableHeaderCell(_ property: DatabaseProperty, view: DatabaseView) -> some View {
        HStack(spacing: 4) {
            Text(property.name)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
            Menu {
                Button("Sort ascending") {
                    mutateView {
                        $0.sortPropertyID = property.id
                        $0.sortAscending = true
                    }
                }
                Button("Sort descending") {
                    mutateView {
                        $0.sortPropertyID = property.id
                        $0.sortAscending = false
                    }
                }
                Button("Hide property") {
                    mutateView {
                        $0.visiblePropertyIDs.removeAll { $0 == property.id }
                    }
                }
                if property.type != .title {
                    Divider()
                    Button("Delete property", role: .destructive) {
                        deleteProperty(property)
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryText)
                    .frame(width: 14, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
    }

    private func columnWidth(for property: DatabaseProperty) -> CGFloat {
        switch property.type {
        case .title: return 220
        case .checkbox: return 80
        case .number: return 100
        case .date, .lastEditedTime, .createdTime: return 130
        default: return 160
        }
    }

    private func listContent(
        rows: [DatabaseRow],
        properties: [DatabaseProperty]
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                Button {
                    viewModel.openDatabaseRow(row)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: row.icon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.secondaryText)
                            .frame(width: 18)

                        Text(row.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.primaryText)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        ForEach(properties.filter { $0.type != .title }.prefix(3)) { property in
                            Text(row.displayValue(for: property))
                                .font(.system(size: 10.5))
                                .foregroundStyle(Palette.tertiaryText)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().overlay(Palette.border)
            }

            Button {
                showingNewRow = true
            } label: {
                Label("New page", systemImage: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.secondaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 120)
    }

    private func galleryContent(
        rows: [DatabaseRow],
        properties: [DatabaseProperty]
    ) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), spacing: 10)],
                spacing: 10
            ) {
                ForEach(rows) { row in
                    Button {
                        viewModel.openDatabaseRow(row)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Palette.hover)
                                Image(systemName: row.icon)
                                    .font(.system(size: 24, weight: .light))
                                    .foregroundStyle(Palette.secondaryText)
                            }
                            .frame(height: 84)

                            Text(row.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.primaryText)
                                .lineLimit(2)

                            ForEach(properties.filter { $0.type != .title }.prefix(2)) { property in
                                HStack(spacing: 4) {
                                    Text(property.name)
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundStyle(Palette.tertiaryText)
                                    Text(row.displayValue(for: property))
                                        .font(.system(size: 10))
                                        .foregroundStyle(Palette.secondaryText)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.menu)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Palette.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        }
        .frame(minHeight: 140)
    }

    private func boardContent(
        rows: [DatabaseRow],
        properties: [DatabaseProperty],
        config: DatabaseConfig
    ) -> some View {
        let view = config.view(for: block.databaseViewID)
        let groupProperty = config.property(for: view.groupPropertyID ?? "")
            ?? config.properties.first(where: { $0.type == .select })

        guard let groupProperty else {
            return AnyView(
                VStack(spacing: 8) {
                    Text("Choose a select property to group the board by.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondaryText)
                    Menu("Group by") {
                        ForEach(config.properties.filter { $0.type == .select || $0.type == .multiSelect }) { property in
                            Button(property.name) {
                                mutateView { $0.groupPropertyID = property.id }
                            }
                        }
                    }
                    .fixedSize()
                }
                .frame(maxWidth: .infinity)
                .padding(30)
            )
        }

        var columns = groupProperty.options
        // Include values that exist in frontmatter but are not declared as
        // options, so externally-authored notes are never hidden on the board.
        for row in rows {
            let value = row.rawValue(for: groupProperty)
            if !value.isEmpty, !columns.contains(value) {
                columns.append(value)
            }
        }
        let grouped = Dictionary(grouping: rows) { row -> String in
            let value = row.rawValue(for: groupProperty)
            return value.isEmpty ? "No group" : value
        }
        if grouped["No group"] != nil, !columns.contains("No group") {
            columns.append("No group")
        }

        return AnyView(
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(columns, id: \.self) { option in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(option)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Palette.primaryText)
                                Spacer()
                                Text("\(grouped[option]?.count ?? 0)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Palette.tertiaryText)
                            }
                            .padding(.horizontal, 8)

                            ScrollView {
                                VStack(spacing: 8) {
                                    ForEach(grouped[option] ?? []) { row in
                                        boardCard(
                                            row: row,
                                            properties: properties,
                                            groupProperty: groupProperty
                                        )
                                    }
                                }
                                .padding(8)
                            }
                        }
                        .frame(width: 230)
                        .background(Palette.hover)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .dropDestination(for: String.self) { items, _ in
                            guard let id = items.first,
                                  let row = rows.first(where: { $0.id == id }) else {
                                return false
                            }
                            setValue(
                                option == "No group" ? "" : option,
                                property: groupProperty,
                                row: row
                            )
                            return true
                        }
                    }
                }
                .padding(10)
            }
            .frame(minHeight: 180)
        )
    }

    private func boardCard(
        row: DatabaseRow,
        properties: [DatabaseProperty],
        groupProperty: DatabaseProperty
    ) -> some View {
        Button {
            viewModel.openDatabaseRow(row)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: row.icon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.secondaryText)
                    Text(row.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.primaryText)
                        .lineLimit(2)
                }

                ForEach(properties.filter {
                    $0.type != .title && $0.id != groupProperty.id
                }.prefix(2)) { property in
                    HStack(spacing: 4) {
                        Text(property.name)
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.tertiaryText)
                        Text(row.displayValue(for: property))
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.menu)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Palette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onDrag {
            NSItemProvider(object: row.id as NSString)
        }
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
        guard let propertyID = view.sortPropertyID,
              let property = config.property(for: propertyID) else {
            return rows
        }

        return rows.sorted { left, right in
            let result: ComparisonResult
            switch property.type {
            case .number:
                let leftValue = Double(left.rawValue(for: property)) ?? 0
                let rightValue = Double(right.rawValue(for: property)) ?? 0
                result = leftValue == rightValue
                    ? .orderedSame
                    : (leftValue < rightValue ? .orderedAscending : .orderedDescending)
            case .date, .createdTime, .lastEditedTime:
                let leftValue = DatabaseRow.isoFormatter.date(from: left.rawValue(for: property))
                    ?? left.modifiedAt
                let rightValue = DatabaseRow.isoFormatter.date(from: right.rawValue(for: property))
                    ?? right.modifiedAt
                result = leftValue == rightValue
                    ? .orderedSame
                    : (leftValue < rightValue ? .orderedAscending : .orderedDescending)
            case .checkbox:
                let leftValue = left.rawValue(for: property) == "true"
                let rightValue = right.rawValue(for: property) == "true"
                result = leftValue == rightValue
                    ? .orderedSame
                    : (leftValue ? .orderedDescending : .orderedAscending)
            default:
                result = left.displayValue(for: property)
                    .localizedStandardCompare(right.displayValue(for: property))
            }

            if result == .orderedSame {
                return left.title.localizedStandardCompare(right.title) == .orderedAscending
            }
            return view.sortAscending
                ? result == .orderedAscending
                : result == .orderedDescending
        }
    }

    private func toggleVisibility(_ property: DatabaseProperty) {
        mutateView { view in
            if view.visiblePropertyIDs.contains(property.id) {
                view.visiblePropertyIDs.removeAll { $0 == property.id }
            } else {
                view.visiblePropertyIDs.append(property.id)
            }
        }
    }

    private func deleteProperty(_ property: DatabaseProperty) {
        guard property.type != .title, var config, let folderURL else { return }
        config.properties.removeAll { $0.id == property.id }
        for index in config.views.indices {
            config.views[index].visiblePropertyIDs.removeAll { $0 == property.id }
            if config.views[index].sortPropertyID == property.id {
                config.views[index].sortPropertyID = nil
            }
            if config.views[index].groupPropertyID == property.id {
                config.views[index].groupPropertyID = nil
            }
        }
        saveConfig(config, for: folderURL)
    }

    private func addProperty() {
        guard var config, let folderURL else { return }
        let name = newPropertyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let options = newPropertyOptions
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let property = DatabaseProperty(
            name: name,
            type: newPropertyType,
            options: options
        )
        config.properties.append(property)
        for index in config.views.indices {
            if config.views[index].id == block.databaseViewID {
                config.views[index].visiblePropertyIDs.append(property.id)
            }
        }
        saveConfig(config, for: folderURL)
        newPropertyName = ""
        newPropertyOptions = ""
        newPropertyType = .text
    }

    private var propertyEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Properties")
                .font(.system(size: 13, weight: .semibold))

            if let config {
                ForEach(config.properties) { property in
                    HStack(spacing: 8) {
                        Text(property.name)
                            .font(.system(size: 11.5, weight: .medium))
                        Spacer()
                        Text(property.type.title)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.tertiaryText)
                        if property.type != .title {
                            Button {
                                deleteProperty(property)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Palette.tertiaryText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Divider()

            Text("Add property")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Palette.secondaryText)

            TextField("Property name", text: $newPropertyName)
                .textFieldStyle(.roundedBorder)

            Picker("Type", selection: $newPropertyType) {
                ForEach(
                    DatabasePropertyType.allCases.filter {
                        $0 != .title && !$0.isComputed
                    }
                ) { type in
                    Text(type.title).tag(type)
                }
            }

            if newPropertyType.supportsOptions {
                TextField("Options (comma separated)", text: $newPropertyOptions)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Add Property") {
                    addProperty()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newPropertyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private var filterEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filters")
                .font(.system(size: 13, weight: .semibold))

            if let config {
                let active = config.view(for: block.databaseViewID).filters
                if active.isEmpty {
                    Text("No filters applied.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiaryText)
                } else {
                    ForEach(active) { filter in
                        HStack(spacing: 8) {
                            Text(config.property(for: filter.propertyID)?.name ?? "Property")
                                .font(.system(size: 11.5, weight: .medium))
                            Text(filter.op.title)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Palette.secondaryText)
                            if filter.op.needsValue {
                                Text(filter.value)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Palette.tertiaryText)
                            }
                            Spacer()
                            Button {
                                mutateView { $0.filters.removeAll { $0.id == filter.id } }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Palette.tertiaryText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Divider()

            Text("Add filter")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Palette.secondaryText)

            if let config {
                Picker("Property", selection: $newFilterPropertyID) {
                    ForEach(config.properties) { property in
                        Text(property.name).tag(property.id)
                    }
                }

                Picker("Condition", selection: $newFilterOperator) {
                    ForEach(DatabaseFilterOperator.allCases) { op in
                        Text(op.title).tag(op)
                    }
                }

                if newFilterOperator.needsValue {
                    TextField("Value", text: $newFilterValue)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Spacer()
                Button("Add Filter") {
                    addFilter()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newFilterPropertyID.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private func addFilter() {
        guard !newFilterPropertyID.isEmpty else { return }
        let filter = DatabaseFilter(
            propertyID: newFilterPropertyID,
            op: newFilterOperator,
            value: newFilterValue
        )
        mutateView { $0.filters.append(filter) }
        newFilterValue = ""
    }

    private var newRowSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New page")
                .font(.system(size: 13, weight: .semibold))
            TextField("Title", text: $newRowTitle)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") {
                    showingNewRow = false
                    newRowTitle = ""
                }
                Button("Create") {
                    createRow()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func createRow() {
        guard let folderURL else { return }
        let title = newRowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        showingNewRow = false
        newRowTitle = ""
        viewModel.createDatabaseRow(
            in: folderURL,
            title: title.isEmpty ? "Untitled" : title
        )
    }
}

private struct DatabaseCellView: View {
    let row: DatabaseRow
    let property: DatabaseProperty
    let value: String
    let onSetValue: (String) -> Void
    let onOpen: () -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            switch property.type {
            case .title:
                Button(action: onOpen) {
                    HStack(spacing: 5) {
                        Image(systemName: row.icon)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Palette.secondaryText)
                        Text(row.title)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Palette.primaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

            case .checkbox:
                Button {
                    onSetValue(value == "true" ? "false" : "true")
                } label: {
                    Image(systemName: value == "true" ? "checkmark.square.fill" : "square")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            value == "true" ? Palette.primaryText : Palette.tertiaryText
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

            case .select:
                Menu {
                    Button("Empty") { onSetValue("") }
                    ForEach(property.options, id: \.self) { option in
                        Button(option) { onSetValue(option) }
                    }
                } label: {
                    Text(value.isEmpty ? "—" : value)
                        .font(.system(size: 11))
                        .foregroundStyle(value.isEmpty ? Palette.tertiaryText : Palette.primaryText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)

            case .multiSelect:
                Menu {
                    ForEach(property.options, id: \.self) { option in
                        Toggle(option, isOn: Binding(
                            get: { selectedOptions.contains(option) },
                            set: { selected in
                                var options = selectedOptions
                                if selected {
                                    options.insert(option)
                                } else {
                                    options.remove(option)
                                }
                                onSetValue(options.sorted().joined(separator: ", "))
                            }
                        ))
                    }
                } label: {
                    Text(value.isEmpty ? "—" : value)
                        .font(.system(size: 11))
                        .foregroundStyle(value.isEmpty ? Palette.tertiaryText : Palette.primaryText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)

            case .fileType, .createdTime, .lastEditedTime:
                Text(row.displayValue(for: property))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.tertiaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

            default:
                TextField(placeholder, text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.primaryText)
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused {
                            commit()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .contentShape(Rectangle())
        .onAppear {
            draft = value
        }
        .onChange(of: value) { _, newValue in
            draft = newValue
        }
    }

    private var selectedOptions: Set<String> {
        Set(value.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty })
    }

    private var placeholder: String {
        switch property.type {
        case .date: return "YYYY-MM-DD"
        case .number: return "0"
        case .url: return "https://"
        default: return ""
        }
    }

    private func commit() {
        guard draft != value else { return }
        if property.type == .date,
           let date = Self.inputDateFormatter.date(from: draft) {
            onSetValue(DatabaseRow.isoFormatter.string(from: date))
        } else {
            onSetValue(draft)
        }
    }

    private static let inputDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
