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

        return 8 + CGFloat(commands.count) * 45 + CGFloat(groupCount) * 22
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
                .overlay(Palette.border)

            if commands.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(groups, id: \.title) { group in
                                Text(group.title.uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .tracking(0.7)
                                    .foregroundStyle(Palette.tertiaryText)
                                    .padding(.horizontal, 10)
                                    .padding(.top, 9)
                                    .padding(.bottom, 3)

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
                .overlay(Palette.border)

            HStack(spacing: 12) {
                Text("↑↓ Navigate")
                Text("↵ Select")
                Text("esc Close")
                Spacer(minLength: 0)
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(Palette.tertiaryText)
            .padding(.horizontal, 12)
            .frame(height: 29)
        }
        .frame(width: 326)
        .background(Palette.menu.opacity(0.72))
        .glassPanel(cornerRadius: 10)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var header: some View {
        HStack {
            Text("Blocks")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.primaryText)
            Spacer()
            if !menu.query.isEmpty {
                Text("/\(menu.query)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }
        }
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
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.14) : Palette.hover)
                        .frame(width: 30, height: 30)
                    Image(systemName: command.icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : Palette.secondaryText)
                }

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
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryText)
                }
            }
            .padding(.horizontal, 7)
            .frame(height: 43)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : (isHovered ? Palette.hover : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredID = hovering ? command.id : nil
        }
    }
}
