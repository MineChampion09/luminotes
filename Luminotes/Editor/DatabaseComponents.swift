import AppKit
import SwiftUI

// MARK: - Pills

struct DatabaseOptionPill: View {
    let text: String
    var compact: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: compact ? 10 : 10.5, weight: .medium))
            .foregroundStyle(Palette.secondaryText)
            .lineLimit(1)
            .padding(.horizontal, compact ? 6 : 7)
            .padding(.vertical, compact ? 1.5 : 2)
            .glassPanel(cornerRadius: 999)
    }
}

struct DatabasePropertyPill: View {
    let property: DatabaseProperty
    let row: DatabaseRow
    let config: DatabaseConfig
    var compact: Bool = false

    private var value: String {
        row.rawValue(for: property, config: config)
    }

    var body: some View {
        switch property.type {
        case .select:
            if value.isEmpty {
                EmptyPill()
            } else {
                DatabaseOptionPill(text: value, compact: compact)
            }

        case .multiSelect:
            let options = value
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if options.isEmpty {
                EmptyPill()
            } else {
                HStack(spacing: 4) {
                    ForEach(options.prefix(compact ? 1 : 2), id: \.self) { option in
                        DatabaseOptionPill(text: option, compact: compact)
                    }
                    if options.count > (compact ? 1 : 2) {
                        Text("+\(options.count - (compact ? 1 : 2))")
                            .font(.system(size: compact ? 9 : 9.5, weight: .medium))
                            .foregroundStyle(Palette.tertiaryText)
                    }
                }
            }

        case .checkbox:
            Label {
                Text(value == "true" ? "Yes" : "No")
                    .font(.system(size: compact ? 10 : 10.5))
            } icon: {
                Image(systemName: value == "true" ? "checkmark.square.fill" : "square")
                    .font(.system(size: compact ? 9.5 : 10))
            }
            .foregroundStyle(value == "true" ? Palette.primaryText : Palette.tertiaryText)

        case .date:
            if value.isEmpty {
                EmptyPill()
            } else {
                Label {
                    Text(row.displayValue(for: property, config: config))
                        .font(.system(size: compact ? 10 : 10.5))
                } icon: {
                    Image(systemName: "calendar")
                        .font(.system(size: compact ? 9 : 9.5))
                }
                .foregroundStyle(Palette.secondaryText)
            }

        case .fileType:
            Label {
                Text(value)
                    .font(.system(size: compact ? 9.5 : 10, weight: .medium))
            } icon: {
                Image(systemName: row.icon)
                    .font(.system(size: compact ? 9 : 9.5))
            }
            .foregroundStyle(Palette.tertiaryText)

        case .url:
            if value.isEmpty {
                EmptyPill()
            } else {
                Label {
                    Text(displayURL)
                        .font(.system(size: compact ? 10 : 10.5))
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "link")
                        .font(.system(size: compact ? 9 : 9.5))
                }
                .foregroundStyle(Palette.secondaryText)
            }

        case .formula:
            if value.isEmpty {
                EmptyPill()
            } else {
                Label {
                    Text(value)
                        .font(.system(size: compact ? 10 : 10.5, design: .monospaced))
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "function")
                        .font(.system(size: compact ? 8.5 : 9))
                }
                .foregroundStyle(value == "#ERROR" ? Color.red : Palette.secondaryText)
            }

        case .number:
            Label {
                Text(value.isEmpty ? "—" : value)
                    .font(.system(size: compact ? 10 : 10.5, design: .monospaced))
            } icon: {
                Image(systemName: "number")
                    .font(.system(size: compact ? 8.5 : 9))
            }
            .foregroundStyle(value.isEmpty ? Palette.tertiaryText : Palette.secondaryText)

        case .createdTime, .lastEditedTime:
            Label {
                Text(row.displayValue(for: property, config: config))
                    .font(.system(size: compact ? 10 : 10.5))
            } icon: {
                Image(systemName: property.type.icon)
                    .font(.system(size: compact ? 9 : 9.5))
            }
            .foregroundStyle(Palette.tertiaryText)

        default:
            if value.isEmpty {
                EmptyPill()
            } else {
                Text(value)
                    .font(.system(size: compact ? 10 : 10.5))
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    private var displayURL: String {
        guard let url = URL(string: value),
              let host = url.host else {
            return value
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}

private struct EmptyPill: View {
    var body: some View {
        Text("—")
            .font(.system(size: 10.5))
            .foregroundStyle(Palette.tertiaryText)
    }
}

// MARK: - Row icon

struct DatabaseRowIcon: View {
    let row: DatabaseRow
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Palette.hover)
            Image(systemName: row.icon)
                .font(.system(size: size * 0.46, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Chips

struct DatabaseFilterChip: View {
    let text: String
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .frame(width: 12, height: 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.tertiaryText)
        }
        .foregroundStyle(Palette.secondaryText)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .glassPanel(
            cornerRadius: 999,
            tint: isHovering ? Palette.selection : nil
        )
        .onHover { isHovering = $0 }
    }
}

struct DatabaseSortChip: View {
    let text: String
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 8.5, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .frame(width: 12, height: 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.tertiaryText)
        }
        .foregroundStyle(Palette.secondaryText)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .glassPanel(
            cornerRadius: 999,
            tint: isHovering ? Palette.selection : nil
        )
        .onHover { isHovering = $0 }
    }
}

struct DatabaseGroupChip: View {
    let text: String
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 8.5, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .frame(width: 12, height: 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.tertiaryText)
        }
        .foregroundStyle(Palette.secondaryText)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .glassPanel(
            cornerRadius: 999,
            tint: isHovering ? Palette.selection : nil
        )
        .onHover { isHovering = $0 }
    }
}

// MARK: - Cell

struct DatabaseCellView: View {
    let row: DatabaseRow
    let property: DatabaseProperty
    let config: DatabaseConfig
    let onSetValue: (String) -> Void
    let onOpen: () -> Void

    @State private var draft = ""
    @State private var isHovering = false
    @State private var showingDatePicker = false
    @State private var dateDraft = Date()
    @FocusState private var focused: Bool

    private var value: String {
        row.rawValue(for: property, config: config)
    }

    var body: some View {
        content
            .padding(.horizontal, 7)
            .frame(height: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(cellBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(
                        focused ? Palette.secondaryText.opacity(0.35) : Color.clear,
                        lineWidth: 0.8
                    )
            )
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .onAppear {
                draft = value
                if property.type == .date {
                    dateDraft = Self.parseDate(value) ?? Date()
                }
            }
            .onChange(of: value) { _, newValue in
                draft = newValue
            }
    }

    private var cellBackground: Color {
        if focused { return Palette.page.opacity(0.75) }
        if isHovering { return Palette.hover }
        return Color.clear
    }

    @ViewBuilder
    private var content: some View {
        switch property.type {
        case .title:
            Button(action: onOpen) {
                HStack(spacing: 6) {
                    DatabaseRowIcon(row: row, size: 18)
                    Text(row.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if isHovering {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Palette.tertiaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        case .checkbox:
            Button {
                onSetValue(value == "true" ? "false" : "true")
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: value == "true" ? "checkmark.square.fill" : "square")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            value == "true" ? Palette.primaryText : Palette.tertiaryText
                        )
                    if value == "true" {
                        Text("Done")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.secondaryText)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        case .select:
            Menu {
                Button("Empty") { onSetValue("") }
                Divider()
                ForEach(property.options, id: \.self) { option in
                    Button {
                        onSetValue(option)
                    } label: {
                        if value == option {
                            Label(option, systemImage: "checkmark")
                        } else {
                            Text(option)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if value.isEmpty {
                        Text("—")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.tertiaryText)
                    } else {
                        DatabaseOptionPill(text: value)
                    }
                    Spacer(minLength: 0)
                }
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
                if !selectedOptions.isEmpty {
                    Divider()
                    Button("Clear") { onSetValue("") }
                }
            } label: {
                HStack(spacing: 4) {
                    if selectedOptions.isEmpty {
                        Text("—")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.tertiaryText)
                    } else {
                        ForEach(Array(selectedOptions).sorted().prefix(2), id: \.self) { option in
                            DatabaseOptionPill(text: option, compact: true)
                        }
                        if selectedOptions.count > 2 {
                            Text("+\(selectedOptions.count - 2)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Palette.tertiaryText)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

        case .date:
            Button {
                dateDraft = Self.parseDate(value) ?? Date()
                showingDatePicker = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.tertiaryText)
                    Text(
                        value.isEmpty
                            ? "—"
                            : row.displayValue(for: property, config: config)
                    )
                    .font(.system(size: 10.5))
                    .foregroundStyle(value.isEmpty ? Palette.tertiaryText : Palette.secondaryText)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingDatePicker, arrowEdge: .bottom) {
                datePopover
            }

        case .url:
            HStack(spacing: 5) {
                Image(systemName: "link")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.tertiaryText)
                TextField("Add link", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.primaryText)
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused { commit() }
                    }
                if !value.isEmpty, let url = URL(string: value) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Open link")
                }
            }

        case .number:
            TextField("0", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Palette.primaryText)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }

        case .formula:
            HStack(spacing: 5) {
                Image(systemName: "function")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.tertiaryText)
                Text(value.isEmpty ? "—" : value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(
                        value == "#ERROR" ? Color.red : Palette.secondaryText
                    )
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

        case .fileType, .createdTime, .lastEditedTime:
            HStack(spacing: 5) {
                Image(systemName: property.type.icon)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.tertiaryText)
                Text(
                    property.type == .fileType
                        ? value
                        : row.displayValue(for: property, config: config)
                )
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.tertiaryText)
                .lineLimit(1)
                Spacer(minLength: 0)
            }

        default:
            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.primaryText)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
        }
    }

    private var datePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker(
                "Date",
                selection: $dateDraft,
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()

            HStack {
                Button("Clear") {
                    onSetValue("")
                    showingDatePicker = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.secondaryText)
                Spacer()
                Button("Done") {
                    onSetValue(DatabaseRow.isoFormatter.string(from: dateDraft))
                    showingDatePicker = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .frame(width: 260)
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
        default: return "Empty"
        }
    }

    private func commit() {
        guard draft != value else { return }
        onSetValue(draft)
    }

    private static func parseDate(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        if let date = DatabaseRow.isoFormatter.date(from: value) {
            return date
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

// MARK: - Note properties

/// Shows the database properties for the note that is currently open, so a
/// database row can be edited from its own page instead of only from the
/// embedded database block.
struct NoteDatabasePropertiesView: View {
    @ObservedObject var viewModel: EditorViewModel
    let fileURL: URL

    @State private var config: DatabaseConfig?
    @State private var values: [String: String] = [:]
    @State private var createdAt = Date()
    @State private var modifiedAt = Date()

    private var properties: [DatabaseProperty] {
        guard let config else { return [] }
        return config.properties.filter { $0.type != .title }
    }

    private var folderName: String {
        fileURL.deletingLastPathComponent().lastPathComponent
    }

    private var row: DatabaseRow {
        DatabaseRow(
            id: fileURL.lastPathComponent,
            url: fileURL,
            relativePath: fileURL.lastPathComponent,
            title: viewModel.note.title,
            fileExtension: fileURL.pathExtension.lowercased(),
            isMarkdown: true,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            values: values
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let config, !properties.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        Text(folderName)
                        Text("·")
                        Text("\(properties.count) properties")
                        Spacer()
                    }
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Palette.tertiaryText)

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(minimum: 190), spacing: 18, alignment: .leading),
                            GridItem(.flexible(minimum: 190), spacing: 18, alignment: .leading)
                        ],
                        alignment: .leading,
                        spacing: 2
                    ) {
                        ForEach(properties) { property in
                            propertyRow(property, config: config)
                        }
                    }
                }
                .padding(12)
                .glassPanel(cornerRadius: 10)
                .padding(.horizontal, 66)
                .padding(.bottom, 14)
            }
        }
        .task(id: fileURL) {
            load()
        }
        .onChange(of: viewModel.note.frontmatter) { _, newValue in
            values = DatabaseStore.frontmatterValues(from: newValue ?? "")
        }
    }

    private func propertyRow(
        _ property: DatabaseProperty,
        config: DatabaseConfig
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: property.type.icon)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Palette.tertiaryText)
                .frame(width: 14)

            Text(property.name)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(1)
                .frame(width: 78, alignment: .leading)

            DatabaseCellView(
                row: row,
                property: property,
                config: config,
                onSetValue: { value in
                    viewModel.setNoteDatabaseValue(value, for: property)
                },
                onOpen: {}
            )
            .frame(maxWidth: .infinity)
        }
        .frame(height: 30)
    }

    private func load() {
        let folder = fileURL.deletingLastPathComponent()
        let configURL = DatabaseStore.configURL(for: folder)
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            config = nil
            return
        }
        config = DatabaseStore.loadConfig(for: folder)
        values = DatabaseStore.frontmatterValues(from: viewModel.note.frontmatter ?? "")
        let attributes = try? fileURL.resourceValues(forKeys: [
            .creationDateKey, .contentModificationDateKey
        ])
        createdAt = attributes?.creationDate ?? Date()
        modifiedAt = attributes?.contentModificationDate ?? Date()
    }
}
