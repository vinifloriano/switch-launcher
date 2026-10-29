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
        ConsoleScaffold(
            title: "All Software",
            icon: .symbol("square.grid.3x3.fill"),
            trailing: "\(games.count) titles · Sort: \(model.sort.displayName)",
            hints: hints
        ) {
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
        } footerLeading: {
            if model.index == model.addIndex {
                Text("Add game apps, or folders that contain them")
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
    }

    private func addTile(isSelected: Bool) -> some View {
        VStack(spacing: ui(10)) {
            SymbolTile(symbol: "plus", title: "Add Software", size: ui(tile), isSelected: isSelected)
            Text("Add Software")
                .font(ui.font(14, isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)
                .lineLimit(1)
                .frame(width: ui(tile))
        }
    }

    private var hints: [ButtonHint] {
        let app = model.app
        if model.index == model.addIndex {
            return [
                ButtonHint("Y", "Sort") { app.handle(.y) },
                ButtonHint("B", "Back") { app.handle(.b) },
                ButtonHint("A", "Add") { app.handle(.a) },
            ]
        }
        return [
            ButtonHint("Y", "Sort") { app.handle(.y) },
            ButtonHint("+", "Options") { app.handle(.plus) },
            ButtonHint("B", "Back") { app.handle(.b) },
            ButtonHint("A", "Start") { app.handle(.a) },
        ]
    }
}
