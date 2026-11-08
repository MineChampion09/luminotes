import SwiftUI

struct SlashCommandMenuView: View {
    @ObservedObject var viewModel: EditorViewModel
    let menu: SlashMenuState
    let maxContentHeight: CGFloat
    @State private var hoveredID: String?

    static let chromeHeight: CGFloat = 66

    static func estimatedContentHeight(for query: String) -> CGFloat {
        let commands = SlashCommand.filtered(by: query)
        guard !commands.isEmpty else { return 90 }

        var groupCount = 0
        var lastGroup: String?
        for command in commands where command.group != lastGroup {
            groupCount += 1
            lastGroup = command.group
        }

        return 8 + CGFloat(commands.count) * 40 + CGFloat(groupCount) * 22
    }

    private var commands: [SlashCommand] {
        viewModel.filteredSlashCommands
    }

    private var groups: [(title: String, commands: [(index: Int, command: SlashCommand)])] {
        var result: [(String, [(Int, SlashCommand)])] = []
        var currentGroup: String?
        var runningIndex = 0

        for command in commands {
            if command.group != currentGroup {
                currentGroup = command.group
                result.append((command.group, []))
            }
            result[result.count - 1].1.append((runningIndex, command))
            runningIndex += 1
        }
        return result
    }

    private var selectedCommandID: String? {
        commands.indices.contains(menu.selectedIndex) ? commands[menu.selectedIndex].id : nil
    }

    private var menuHeight: CGFloat {
        let estimated = Self.estimatedContentHeight(for: menu.query)
        return min(max(estimated, 46), maxContentHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .overlay(Palette.border.opacity(0.6))

            if commands.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(groups, id: \.title) { group in
                                Text(group.title)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(Palette.tertiaryText)
                                    .padding(.horizontal, 10)
                                    .padding(.top, 8)
                                    .padding(.bottom, 2)

                                ForEach(group.commands, id: \.command.id) { item in
                                    commandRow(item.command, index: item.index)
                                        .id(item.command.id)
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                    }
                    .frame(height: menuHeight)
                    .onChange(of: menu.selectedIndex) { _, _ in
                        if let selectedCommandID {
                            withAnimation(.easeOut(duration: 0.12)) {
                                proxy.scrollTo(selectedCommandID, anchor: .center)
                            }
                        }
                    }
                }
            }

            Divider()
                .overlay(Palette.border.opacity(0.6))

            HStack(spacing: 10) {
                Text("↑↓ Navigate")
                Text("↵ Select")
                Text("esc Close")
                Spacer(minLength: 0)
            }
            .font(.system(size: 10, weight: .regular))
            .foregroundStyle(Palette.tertiaryText)
            .padding(.horizontal, 12)
            .frame(height: 29)
        }
        .frame(width: 326)
        .glassPanel(cornerRadius: 12, tint: Palette.sidebarTint)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 18, x: 0, y: 8)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))

            Text(menu.query.isEmpty ? "Search blocks" : menu.query)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(menu.query.isEmpty ? Palette.tertiaryText : Palette.primaryText)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.tertiaryText)
        .padding(.horizontal, 12)
        .frame(height: 34)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(Palette.tertiaryText)
            Text("No blocks found")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
            if !menu.query.isEmpty {
                Text("Try /text, /h1, /todo, or /table")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func commandRow(_ command: SlashCommand, index: Int) -> some View {
        let isSelected = index == menu.selectedIndex
        let isHovered = hoveredID == command.id

        return Button {
            viewModel.chooseSlashCommand(command)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: command.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Palette.primaryText : Palette.secondaryText)
                    .frame(width: 20, alignment: .center)

                VStack(alignment: .leading, spacing: 1) {
                    Text(command.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Palette.primaryText)
                    Text(command.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "return")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Palette.tertiaryText)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        isSelected
                            ? Palette.selection
                            : (isHovered ? Palette.hover : Color.clear)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredID = hovering ? command.id : nil
        }
    }
}
