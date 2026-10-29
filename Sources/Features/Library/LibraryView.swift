import AppKit
import DesignSystem
import LauncherCore
import SwiftUI

struct LibraryView: View {
    let model: LibraryModel

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    private let tile: CGFloat = 166

    var body: some View {
        let games = model.games
        let showingGroups = model.tab == .groups
        ConsoleScaffold(
            title: model.title,
            icon: .symbol(model.groupID == nil ? "square.grid.3x3.fill" : "square.stack.fill"),
            trailing: showingGroups
                ? "\(model.groups.count) groups"
                : "\(games.count) titles · Sort: \(model.sort.displayName)",
            hints: hints
        ) {
            VStack(spacing: 0) {
                if model.groupID == nil { tabBar }
                if showingGroups { groupsGrid } else { softwareGrid(games) }
            }
        } footerLeading: {
            footer
        }
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: ui(10)) {
            tabButton("All Software", .all)
            tabButton("Groups", .groups)
        }
        .padding(ui(5))
        .background(Capsule(style: .continuous).fill(theme.dockBar))
        .padding(.top, ui(18))
    }

    private func tabButton(_ title: String, _ tab: LibraryModel.Tab) -> some View {
        let isCurrent = model.tab == tab
        return Text(title)
            .font(ui.font(17, isCurrent ? .semibold : .regular))
            .foregroundStyle(isCurrent ? theme.accent : theme.textSecondary)
            .padding(.horizontal, ui(26))
            .padding(.vertical, ui(9))
            .background(Capsule(style: .continuous).fill(isCurrent ? theme.surface : .clear))
            .contentShape(Capsule())
            .onTapGesture { model.tapTab(tab) }
    }

    // MARK: Groups

    private var groupsGrid: some View {
        let groups = model.groups
        return ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(ui(tile)), spacing: ui(26)), count: LibraryModel.columns),
                spacing: ui(30)
            ) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    labeled(group.name, isSelected: index == model.groupIndex) {
                        GroupTile(icons: groupIcons(group), size: ui(tile), isSelected: index == model.groupIndex)
                    }
                    .onTapGesture { model.tapGroup(index) }
                }
                labeled("Create Group", isSelected: model.groupIndex == model.createIndex) {
                    SymbolTile(symbol: "plus", title: "Create Group", size: ui(tile),
                               isSelected: model.groupIndex == model.createIndex)
                }
                .onTapGesture { model.tapGroup(model.createIndex) }
            }
            .padding(.vertical, ui(30))
        }
        .scrollIndicators(.never)
    }

    private func groupIcons(_ group: SoftwareGroup) -> [NSImage] {
        group.gameIDs.prefix(4).compactMap { id in
            model.app.library.game(id: id).flatMap { IconCache.shared.icon(for: $0) }
        }
    }

    private func labeled<Tile: View>(_ title: String, isSelected: Bool, @ViewBuilder tile: () -> Tile) -> some View {
        VStack(spacing: ui(10)) {
            tile()
            Text(title)
                .font(ui.font(14, isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)
                .lineLimit(1)
                .frame(width: ui(self.tile))
        }
    }

    // MARK: Software

    private func softwareGrid(_ games: [Game]) -> some View {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(ui(tile)), spacing: ui(26)), count: LibraryModel.columns),
                        spacing: ui(30)
                    ) {
                        ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                            let isSelected = index == model.index
                            VStack(spacing: ui(10)) {
                                GameTile(
                                    image: IconCache.shared.icon(for: game),
                                    title: game.title,
                                    size: ui(tile),
                                    isSelected: isSelected,
                                    badgeSymbol: model.app.launcher.runningGameID == game.id ? "play.fill" : nil,
                                    isLoading: IconCache.shared.isLoading(game)
                                )
                                Text(game.title)
                                    .font(ui.font(14, isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)
                                    .lineLimit(1)
                                    .frame(width: ui(tile))
                            }
                            .id(index)
                            .onTapGesture { model.tap(index) }
                        }
                        addTile(isSelected: model.index == model.addIndex)
                            .id(model.addIndex)
                            .onTapGesture { model.tap(model.addIndex) }
                    }
                    .padding(.vertical, ui(30))
                }
                .scrollIndicators(.never)
                // The lazy grid lays out far rows only once scrolled near them, so scroll again.
                .task {
                    guard model.index > 0 else { return }
                    proxy.scrollTo(model.index)
                    try? await Task.sleep(for: .milliseconds(100))
                    proxy.scrollTo(model.index)
                }
                .onChange(of: model.index) { _, index in
                    withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(index) }
                }
                .onChange(of: model.sort) { _, _ in proxy.scrollTo(0, anchor: .top) }
            }
    }

    @ViewBuilder private var footer: some View {
        if model.tab == .groups {
            Text(model.selectedGroup.map { "\($0.gameIDs.count) titles" } ?? "Group software you like to play together")
                .font(ui.font(16))
                .foregroundStyle(theme.textSecondary)
        } else if model.index == model.addIndex {
            Text(model.groupID == nil ? "Add game apps, or folders that contain them" : "Choose the software in this group")
                .font(ui.font(16))
                .foregroundStyle(theme.textSecondary)
        } else if let game = model.selectedGame {
                let record = model.app.history.record(for: game.id)
                Text(record.lastPlayed == nil
                     ? "Not played yet"
                     : "Played for \(PlayTimeFormatter.duration(record.totalSeconds)) · Last played \(PlayTimeFormatter.relative(record.lastPlayed))")
                    .font(ui.font(16))
                    .foregroundStyle(theme.textSecondary)
        }
    }

    private func addTile(isSelected: Bool) -> some View {
        let title = model.groupID == nil ? "Add Software" : "Add or Remove"
        return VStack(spacing: ui(10)) {
            SymbolTile(symbol: model.groupID == nil ? "plus" : "checklist", title: title, size: ui(tile), isSelected: isSelected)
            Text(title)
                .font(ui.font(14, isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)
                .lineLimit(1)
                .frame(width: ui(tile))
        }
    }

    private var hints: [ButtonHint] {
        let app = model.app
        let tabs: [ButtonHint] = model.groupID != nil ? []
            : model.tab == .all ? [ButtonHint("R", "Groups") { app.handle(.r) }]
            : [ButtonHint("L", "All Software") { app.handle(.l) }]
        if model.tab == .groups {
            return tabs + (model.selectedGroup == nil ? [] : [ButtonHint("+", "Edit") { app.handle(.plus) }]) + [
                ButtonHint("B", "Back") { app.handle(.b) },
                ButtonHint("A", model.selectedGroup == nil ? "Create" : "Open") { app.handle(.a) },
            ]
        }
        if model.index == model.addIndex {
            return tabs + [
                ButtonHint("Y", "Sort") { app.handle(.y) },
                ButtonHint("B", "Back") { app.handle(.b) },
                ButtonHint("A", "Add") { app.handle(.a) },
            ]
        }
        return tabs + [
            ButtonHint("Y", "Sort") { app.handle(.y) },
            ButtonHint("+", "Options") { app.handle(.plus) },
            ButtonHint("B", "Back") { app.handle(.b) },
            ButtonHint("A", "Start") { app.handle(.a) },
        ]
    }
}

/// A group's cover: up to four of its software icons in a grid.
struct GroupTile: View {
    let icons: [NSImage]
    let size: CGFloat
    let isSelected: Bool

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    var body: some View {
        let gap = ui(4)
        let cell = (size - gap * 3) / 2
        ZStack {
            RoundedRectangle(cornerRadius: ui(10), style: .continuous).fill(theme.surface)
            if icons.isEmpty {
                Image(systemName: "square.stack.fill")
                    .font(.system(size: size * 0.3, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
            } else {
                LazyVGrid(columns: [GridItem(.fixed(cell), spacing: gap), GridItem(.fixed(cell), spacing: gap)], spacing: gap) {
                    ForEach(Array(icons.enumerated()), id: \.offset) { _, icon in
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: cell, height: cell)
                            .clipShape(RoundedRectangle(cornerRadius: ui(6), style: .continuous))
                    }
                }
                .frame(width: size - gap * 2, height: size - gap * 2, alignment: .topLeading)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: theme.shadow, radius: ui(3), y: ui(1.5))
        .selectionFrame(isSelected, cornerRadius: ui(10))
    }
}
