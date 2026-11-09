import SwiftUI

enum DatabaseSettingsTab: String, CaseIterable, Identifiable {
    case properties
    case filter
    case sort
    case group
    case rows

    var id: String { rawValue }

    var title: String {
        switch self {
        case .properties: return "Properties"
        case .filter: return "Filter"
        case .sort: return "Sort"
        case .group: return "Group"
        case .rows: return "Rows"
        }
    }

    var icon: String {
        switch self {
        case .properties: return "list.bullet.rectangle"
        case .filter: return "line.3.horizontal.decrease.circle"
        case .sort: return "arrow.up.arrow.down"
        case .group: return "rectangle.3.group"
        case .rows: return "tablecells"
        }
    }
}

struct DatabaseSettingsView: View {
    let currentViewID: String
    let folderURL: URL
    let onChange: (DatabaseConfig) -> Void
    let onClose: () -> Void

    @State private var draft: DatabaseConfig
    @State private var tab: DatabaseSettingsTab = .properties
    @State private var editingPropertyID: String?
    @State private var newPropertyName = ""
    @State private var newPropertyType: DatabasePropertyType = .text
    @State private var newPropertyOptions = ""
    @State private var newPropertyFormula = ""
    @State private var newFilterPropertyID = ""
    @State private var newFilterOperator: DatabaseFilterOperator = .contains
    @State private var newFilterValue = ""
    @State private var formulaError: String?

    init(
        config: DatabaseConfig,
        currentViewID: String,
        folderURL: URL,
        initialTab: DatabaseSettingsTab = .properties,
        onChange: @escaping (DatabaseConfig) -> Void,
        onClose: @escaping () -> Void
    ) {
        _draft = State(initialValue: config)
        _tab = State(initialValue: initialTab)
        self.currentViewID = currentViewID
        self.folderURL = folderURL
        self.onChange = onChange
        self.onClose = onClose
    }

    private var viewIndex: Int {
        draft.views.firstIndex(where: { $0.id == currentViewID }) ?? 0
    }

    private var view: DatabaseView {
        guard draft.views.indices.contains(viewIndex) else {
            return DatabaseView(
                id: currentViewID,
                name: "View",
                layout: .table,
                visiblePropertyIDs: draft.properties.map(\.id)
            )
        }
        return draft.views[viewIndex]
    }

    private var selectProperties: [DatabaseProperty] {
        draft.properties.filter { $0.type == .select || $0.type == .multiSelect }
    }

    private var titleProperty: DatabaseProperty? {
        draft.properties.first { $0.type == .title }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.border)
            HStack(spacing: 0) {
                sidebar
                Divider().overlay(Palette.border)
                ScrollView {
                    tabContent
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Divider().overlay(Palette.border)
            footer
        }
        .frame(width: 700, height: 620)
        .background(Palette.page.opacity(0.55))
        .presentationBackground(.ultraThinMaterial)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Palette.hover)
                Image(systemName: view.layout.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.secondaryText)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("Database settings")
                    .font(.system(size: 13.5, weight: .semibold))
                Text("\(folderURL.lastPathComponent) · \(view.name)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.tertiaryText)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(DatabaseSettingsTab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.icon)
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 16)
                        Text(item.title)
                            .font(.system(size: 11.5, weight: tab == item ? .semibold : .regular))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(tab == item ? Palette.primaryText : Palette.secondaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background {
                        if tab == item {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Palette.selection)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(10)
        .frame(width: 158)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .properties:
            propertiesTab
        case .filter:
            filterTab
        case .sort:
            sortTab
        case .group:
            groupTab
        case .rows:
            rowsTab
        }
    }

    // MARK: - Properties

    private var propertiesTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Properties", subtitle: "Choose which properties this view shows.")

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    ForEach(Array(draft.properties.enumerated()), id: \.element.id) { index, property in
                        propertyRow(property)
                        if index < draft.properties.count - 1 {
                            Divider().overlay(Palette.border.opacity(0.5))
                        }
                    }
                }
            }
            .frame(maxHeight: 260)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.hover.opacity(0.22))
            )

            Divider().overlay(Palette.border)

            if let editingPropertyID,
               let property = draft.properties.first(where: { $0.id == editingPropertyID }) {
                propertyEditor(property)
            } else {
                addPropertyForm
            }
        }
    }

    private func propertyRow(_ property: DatabaseProperty) -> some View {
        HStack(spacing: 9) {
            Image(systemName: property.type.icon)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Palette.tertiaryText)
                .frame(width: 16)

            Text(property.name)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.primaryText)
                .lineLimit(1)

            Text(property.type.title)
                .font(.system(size: 9.5))
                .foregroundStyle(Palette.tertiaryText)

            Spacer(minLength: 8)

            Button {
                toggleVisibility(property)
            } label: {
                Image(systemName: view.visiblePropertyIDs.contains(property.id)
                      ? "eye"
                      : "eye.slash")
                    .font(.system(size: 10.5))
                    .foregroundStyle(
                        view.visiblePropertyIDs.contains(property.id)
                            ? Palette.secondaryText
                            : Palette.tertiaryText
                    )
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show or hide in this view")

            Menu {
                Button("Edit") {
                    startEditing(property)
                }
                if property.type != .title {
                    Divider()
                    Button("Delete", role: .destructive) {
                        deleteProperty(property)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryText)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .padding(.horizontal, 9)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(editingPropertyID == property.id ? Palette.selection : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            startEditing(property)
        }
    }

    private func propertyEditor(_ property: DatabaseProperty) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Edit \(property.name)")
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Button("Cancel") {
                    editingPropertyID = nil
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.secondaryText)
            }

            TextField("Property name", text: binding(for: property).name)
                .settingsField()

            Picker("Type", selection: binding(for: property).type) {
                ForEach(property.type == .title ? [.title] : DatabasePropertyType.creatable) { type in
                    Label(type.title, systemImage: type.icon).tag(type)
                }
            }
            .disabled(property.type == .title)

            if property.type.supportsOptions {
                TextField(
                    "Options, separated by commas",
                    text: binding(for: property).optionsText
                )
                .settingsField()
            }

            if property.type == .formula {
                formulaEditor(text: binding(for: property).formula)
            }

            HStack {
                Spacer()
                Button("Save") {
                    let current = binding(for: property).get()
                    if current.type == .formula,
                       let error = DatabaseFormula.validate(current.formula) {
                        formulaError = error
                        return
                    }
                    commit()
                    editingPropertyID = nil
                }
                .glassButtonStyle(prominent: true)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Palette.hover.opacity(0.22))
        )
    }

    private var addPropertyForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add property")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Palette.secondaryText)

            TextField("Property name", text: $newPropertyName)
                .settingsField()

            Picker("Type", selection: $newPropertyType) {
                ForEach(DatabasePropertyType.creatable) { type in
                    Label(type.title, systemImage: type.icon).tag(type)
                }
            }

            if newPropertyType.supportsOptions {
                TextField("Options, separated by commas", text: $newPropertyOptions)
                    .settingsField()
            }

            if newPropertyType == .formula {
                formulaEditor(text: $newPropertyFormula)
            }

            HStack {
                Spacer()
                Button("Add Property") {
                    addProperty()
                }
                .glassButtonStyle(prominent: true)
                .disabled(newPropertyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Palette.hover.opacity(0.22))
        )
    }

    private func formulaEditor(text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            TextField("prop(\"Price\") * prop(\"Quantity\")", text: text)
                .settingsField()
                .font(.system(size: 11, design: .monospaced))

            if let formulaError {
                Text(formulaError)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.red.opacity(0.85))
            } else {
                Text("Use prop(\"Name\"), + - * /, comparisons, and functions like if, round, concat, dateFormat.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.tertiaryText)
            }
        }
        .onChange(of: text.wrappedValue) { _, newValue in
            formulaError = DatabaseFormula.validate(newValue)
        }
    }

    private func binding(for property: DatabaseProperty) -> PropertyDraftBinding {
        PropertyDraftBinding(
            get: {
                draft.properties.first(where: { $0.id == property.id }) ?? property
            },
            set: { updated in
                guard let index = draft.properties.firstIndex(where: { $0.id == property.id }) else {
                    return
                }
                draft.properties[index] = updated
            }
        )
    }

    // MARK: - Filter

    private var filterTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(
                "Filters",
                subtitle: "Rows must match every filter in this view."
            )

            if view.filters.isEmpty {
                emptyHint("No filters yet.", icon: "line.3.horizontal.decrease.circle")
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(view.filters.enumerated()), id: \.element.id) { index, filter in
                        filterRow(filter, index: index)
                    }
                }
            }

            Divider().overlay(Palette.border)

            VStack(alignment: .leading, spacing: 10) {
                Text("Add filter")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Palette.secondaryText)

                HStack(spacing: 8) {
                    settingsMenu(
                        title: selectedFilterProperty?.name ?? "Property",
                        width: 140,
                        items: draft.properties.map { ($0.id, $0.name) },
                        selection: $newFilterPropertyID
                    )

                    settingsMenu(
                        title: newFilterOperator.title,
                        width: 130,
                        items: operators(for: selectedFilterProperty?.type ?? .text)
                            .map { ($0.rawValue, $0.title) },
                        selection: Binding(
                            get: { newFilterOperator.rawValue },
                            set: { rawValue in
                                if let op = DatabaseFilterOperator(rawValue: rawValue) {
                                    newFilterOperator = op
                                }
                            }
                        )
                    )

                    if newFilterOperator.needsValue {
                        valueField(
                            property: selectedFilterProperty,
                            text: $newFilterValue
                        )
                        .frame(maxWidth: .infinity)
                    }

                    Button("Add") {
                        addFilter()
                    }
                    .glassButtonStyle()
                    .disabled(newFilterPropertyID.isEmpty)
                }
            }
        }
        .onAppear {
            if newFilterPropertyID.isEmpty {
                newFilterPropertyID = draft.properties.first?.id ?? ""
                newFilterOperator = operators(for: selectedFilterProperty?.type ?? .text).first ?? .contains
            }
        }
        .onChange(of: newFilterPropertyID) { _, newValue in
            let type = draft.property(for: newValue)?.type ?? .text
            let available = operators(for: type)
            if !available.contains(newFilterOperator) {
                newFilterOperator = available.first ?? .contains
                newFilterValue = ""
            }
        }
    }

    private func filterRow(_ filter: DatabaseFilter, index: Int) -> some View {
        let property = draft.property(for: filter.propertyID)
        return HStack(spacing: 8) {
            settingsMenu(
                title: property?.name ?? "Property",
                width: 140,
                items: draft.properties.map { ($0.id, $0.name) },
                selection: Binding(
                    get: { filter.propertyID },
                    set: { newValue in
                        guard draft.views.indices.contains(viewIndex),
                              draft.views[viewIndex].filters.indices.contains(index) else { return }
                        draft.views[viewIndex].filters[index].propertyID = newValue
                        let type = draft.property(for: newValue)?.type ?? .text
                        let available = operators(for: type)
                        if !available.contains(draft.views[viewIndex].filters[index].op) {
                            draft.views[viewIndex].filters[index].op = available.first ?? .contains
                            draft.views[viewIndex].filters[index].value = ""
                        }
                        commit()
                    }
                )
            )

            settingsMenu(
                title: filter.op.title,
                width: 130,
                items: operators(for: property?.type ?? .text)
                    .map { ($0.rawValue, $0.title) },
                selection: Binding(
                    get: { filter.op.rawValue },
                    set: { rawValue in
                        guard draft.views.indices.contains(viewIndex),
                              draft.views[viewIndex].filters.indices.contains(index),
                              let op = DatabaseFilterOperator(rawValue: rawValue) else { return }
                        draft.views[viewIndex].filters[index].op = op
                        commit()
                    }
                )
            )

            if filter.op.needsValue {
                valueField(
                    property: property,
                    text: Binding(
                        get: { filter.value },
                        set: { newValue in
                            guard draft.views.indices.contains(viewIndex),
                                  draft.views[viewIndex].filters.indices.contains(index) else { return }
                            draft.views[viewIndex].filters[index].value = newValue
                        }
                    )
                )
                .frame(maxWidth: .infinity)
            }

            Button {
                guard draft.views.indices.contains(viewIndex) else { return }
                draft.views[viewIndex].filters.removeAll { $0.id == filter.id }
                commit()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.tertiaryText)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 9)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Palette.hover.opacity(0.22))
        )
    }

    @ViewBuilder
    private func valueField(
        property: DatabaseProperty?,
        text: Binding<String>
    ) -> some View {
        if let property, property.type.supportsOptions, !property.options.isEmpty {
            settingsMenu(
                title: text.wrappedValue.isEmpty ? "Any" : text.wrappedValue,
                width: 150,
                items: [("", "Any")] + property.options.map { ($0, $0) },
                selection: text
            )
        } else {
            TextField("Value", text: text)
                .settingsField()
                .font(.system(size: 11))
        }
    }

    private var selectedFilterProperty: DatabaseProperty? {
        draft.property(for: newFilterPropertyID)
    }

    private func operators(for type: DatabasePropertyType) -> [DatabaseFilterOperator] {
        switch type {
        case .number:
            return [.isExactly, .isNot, .greaterThan, .lessThan, .isEmpty, .isNotEmpty]
        case .date:
            return [.isExactly, .isNot, .greaterThan, .lessThan, .isEmpty, .isNotEmpty]
        case .checkbox:
            return [.isChecked, .isNotChecked]
        case .select, .multiSelect, .fileType:
            return [.isExactly, .isNot, .isEmpty, .isNotEmpty]
        default:
            return [.contains, .doesNotContain, .isExactly, .isNot, .isEmpty, .isNotEmpty]
        }
    }

    // MARK: - Sort

    private var sortTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(
                "Sort",
                subtitle: "Sorts apply in order, top to bottom."
            )

            if view.sorts.isEmpty {
                emptyHint("No sorts yet.", icon: "arrow.up.arrow.down")
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(view.sorts.enumerated()), id: \.element.id) { index, sort in
                        sortRow(sort, index: index)
                    }
                }
            }

            Button {
                addSort()
            } label: {
                Label("Add sort", systemImage: "plus")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.secondaryText)
        }
    }

    private func sortRow(_ sort: DatabaseSort, index: Int) -> some View {
        HStack(spacing: 8) {
            settingsMenu(
                title: draft.property(for: sort.propertyID)?.name ?? "Property",
                width: 200,
                items: draft.properties.map { ($0.id, $0.name) },
                selection: Binding(
                    get: { sort.propertyID },
                    set: { newValue in
                        guard draft.views.indices.contains(viewIndex),
                              draft.views[viewIndex].sorts.indices.contains(index) else { return }
                        draft.views[viewIndex].sorts[index].propertyID = newValue
                        commit()
                    }
                )
            )

            Button {
                guard draft.views.indices.contains(viewIndex),
                      draft.views[viewIndex].sorts.indices.contains(index) else { return }
                draft.views[viewIndex].sorts[index].ascending.toggle()
                commit()
            } label: {
                Label(
                    sort.ascending ? "Ascending" : "Descending",
                    systemImage: sort.ascending ? "arrow.up" : "arrow.down"
                )
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Palette.hover.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Palette.border.opacity(0.6), lineWidth: 0.6)
                )
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                guard draft.views.indices.contains(viewIndex) else { return }
                draft.views[viewIndex].sorts.removeAll { $0.id == sort.id }
                commit()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.tertiaryText)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 9)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Palette.hover.opacity(0.22))
        )
    }

    private func addSort() {
        guard draft.views.indices.contains(viewIndex) else { return }
        let used = Set(draft.views[viewIndex].sorts.map(\.propertyID))
        let candidate = draft.properties.first(where: { !used.contains($0.id) })
            ?? draft.properties.first
        guard let candidate else { return }
        draft.views[viewIndex].sorts.append(DatabaseSort(propertyID: candidate.id))
        commit()
    }

    // MARK: - Group

    private var groupTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(
                "Group",
                subtitle: "Group board columns and list sections by a select property."
            )

            Picker("Group by", selection: Binding(
                get: { view.groupPropertyID ?? "" },
                set: { newValue in
                    guard draft.views.indices.contains(viewIndex) else { return }
                    draft.views[viewIndex].groupPropertyID = newValue.isEmpty ? nil : newValue
                    commit()
                }
            )) {
                Text("None").tag("")
                ForEach(selectProperties) { property in
                    Text(property.name).tag(property.id)
                }
            }
            .pickerStyle(.radioGroup)

            if selectProperties.isEmpty {
                emptyHint(
                    "Add a Select property to group rows.",
                    icon: "tag"
                )
            }

            if view.layout == .board, view.groupPropertyID == nil {
                Text("Board views need a group property to create columns.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.tertiaryText)
            }
        }
    }

    // MARK: - Rows

    private var rowsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(
                "Rows",
                subtitle: "Choose which files in this folder become database rows."
            )

            Picker("Row source", selection: Binding(
                get: { draft.rowSource },
                set: { newValue in
                    draft.rowSource = newValue
                    commit()
                }
            )) {
                ForEach(DatabaseRowSource.allCases) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.radioGroup)

            Text(rowSourceDescription)
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(Palette.border)

            VStack(alignment: .leading, spacing: 5) {
                Text("Folder")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.secondaryText)
                Text(folderURL.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Palette.tertiaryText)
                    .textSelection(.enabled)
                Text("Schema and views are stored in .luminotes/database.json.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.tertiaryText)
            }
        }
    }

    private var rowSourceDescription: String {
        switch draft.rowSource {
        case .notes:
            return "Markdown notes in the folder become rows. Assets stay in the sidebar."
        case .assets:
            return "PDFs and images in the folder become rows. Notes stay in the sidebar."
        case .all:
            return "Every note, PDF, and image directly inside the folder becomes a row."
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("Changes apply immediately.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.tertiaryText)
            Spacer()
            Button("Done") {
                commit()
                onClose()
            }
            .glassButtonStyle(prominent: true)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    // MARK: - Helpers

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.tertiaryText)
        }
    }

    private func emptyHint(_ text: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 11))
        }
        .foregroundStyle(Palette.tertiaryText)
        .padding(.vertical, 8)
    }

    private func startEditing(_ property: DatabaseProperty) {
        editingPropertyID = property.id
        formulaError = nil
    }

    private func toggleVisibility(_ property: DatabaseProperty) {
        guard draft.views.indices.contains(viewIndex) else { return }
        if let index = draft.views[viewIndex].visiblePropertyIDs.firstIndex(of: property.id) {
            draft.views[viewIndex].visiblePropertyIDs.remove(at: index)
        } else {
            draft.views[viewIndex].visiblePropertyIDs.append(property.id)
        }
        commit()
    }

    private func deleteProperty(_ property: DatabaseProperty) {
        guard property.type != .title else { return }
        draft.properties.removeAll { $0.id == property.id }
        for index in draft.views.indices {
            draft.views[index].visiblePropertyIDs.removeAll { $0 == property.id }
            draft.views[index].sorts.removeAll { $0.propertyID == property.id }
            draft.views[index].filters.removeAll { $0.propertyID == property.id }
            if draft.views[index].groupPropertyID == property.id {
                draft.views[index].groupPropertyID = nil
            }
        }
        if editingPropertyID == property.id {
            editingPropertyID = nil
        }
        commit()
    }

    private func addProperty() {
        let name = newPropertyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if newPropertyType == .formula,
           let error = DatabaseFormula.validate(newPropertyFormula) {
            formulaError = error
            return
        }
        let options = newPropertyOptions
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let property = DatabaseProperty(
            id: uniquePropertyID(for: name, existing: draft.properties.map(\.id)),
            name: name,
            type: newPropertyType,
            options: options,
            formula: newPropertyFormula
        )
        draft.properties.append(property)
        if draft.views.indices.contains(viewIndex) {
            draft.views[viewIndex].visiblePropertyIDs.append(property.id)
        }
        newPropertyName = ""
        newPropertyOptions = ""
        newPropertyFormula = ""
        newPropertyType = .text
        commit()
    }

    private func settingsMenu(
        title: String,
        width: CGFloat,
        items: [(String, String)],
        selection: Binding<String>
    ) -> some View {
        Menu {
            ForEach(items, id: \.0) { item in
                Button {
                    selection.wrappedValue = item.0
                } label: {
                    if selection.wrappedValue == item.0 {
                        Label(item.1, systemImage: "checkmark")
                    } else {
                        Text(item.1)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryText)
            }
            .padding(.horizontal, 8)
            .frame(width: width, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Palette.hover.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Palette.border.opacity(0.6), lineWidth: 0.6)
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func uniquePropertyID(for name: String, existing: [String]) -> String {
        let base = name
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        let candidate = base.isEmpty ? "property" : base
        guard existing.contains(candidate) else { return candidate }
        var counter = 2
        while existing.contains("\(candidate)_\(counter)") {
            counter += 1
        }
        return "\(candidate)_\(counter)"
    }

    private func addFilter() {
        guard draft.views.indices.contains(viewIndex),
              !newFilterPropertyID.isEmpty else { return }
        let filter = DatabaseFilter(
            propertyID: newFilterPropertyID,
            op: newFilterOperator,
            value: newFilterValue
        )
        draft.views[viewIndex].filters.append(filter)
        newFilterValue = ""
        commit()
    }

    private func commit() {
        onChange(draft)
    }
}

// MARK: - Property draft binding

private struct PropertyDraftBinding {
    let get: () -> DatabaseProperty
    let set: (DatabaseProperty) -> Void

    var name: Binding<String> {
        Binding(
            get: { get().name },
            set: { value in
                var property = get()
                property.name = value
                set(property)
            }
        )
    }

    var type: Binding<DatabasePropertyType> {
        Binding(
            get: { get().type },
            set: { value in
                var property = get()
                property.type = value
                set(property)
            }
        )
    }

    var formula: Binding<String> {
        Binding(
            get: { get().formula },
            set: { value in
                var property = get()
                property.formula = value
                set(property)
            }
        )
    }

    var optionsText: Binding<String> {
        Binding(
            get: { get().options.joined(separator: ", ") },
            set: { value in
                var property = get()
                property.options = value
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                set(property)
            }
        )
    }
}

// MARK: - Uniform controls

private extension View {
    func settingsField() -> some View {
        self
            .textFieldStyle(.plain)
            .font(.system(size: 11.5))
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Palette.hover.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Palette.border.opacity(0.6), lineWidth: 0.6)
            )
    }
}
