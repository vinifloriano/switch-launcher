import DesignSystem
import LauncherCore

extension AppModel {
    /// Virtual Game Cards: load (show on HOME) or eject (hide from HOME) each title.
    func makeVirtualCardMenu() -> MenuModel {
        MenuModel(title: "Virtual Game Cards", icon: .symbol("sdcard.fill"), app: self) { [unowned self] in
            let games = LibraryOrdering.sort(self.library.games, by: .title, history: self.history.records)
            let loaded = games.filter(self.isLoaded).count
            return [MenuSection(
                id: "cards", title: "Virtual Game Cards",
                footnote: "\(loaded) of \(games.count) loaded. Ejected software leaves the HOME Menu but stays in All Software. Press + for a card's options.",
                items: games.map { game in
                    let running = self.launcher.runningGameID == game.id
                    return MenuItem(
                        id: game.id,
                        title: game.title,
                        subtitle: running ? "Playing now" : (self.isLoaded(game) ? "Loaded on this system" : "Ejected"),
                        image: IconCache.shared.icon(for: game),
                        options: { [unowned self] in self.openOptions(for: game) },
                        kind: .toggle(self.isLoaded(game)) { [unowned self] in self.setLoaded(game, $0) }
                    )
                }
            )]
        }
    }
}
