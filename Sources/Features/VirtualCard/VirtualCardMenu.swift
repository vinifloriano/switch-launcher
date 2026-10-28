import DesignSystem
import LauncherCore

extension AppModel {
    /// Virtual Game Cards: load (show on HOME) or eject (hide from HOME) each title.
    func makeVirtualCardMenu() -> MenuModel {
        MenuModel(title: "Virtual Game Cards", icon: .symbol("sdcard.fill"), app: self) { [unowned self] in
            let games = LibraryOrdering.sort(library.games, by: .title, history: history.records)
            let loaded = games.filter(isLoaded).count
            return [MenuSection(
                id: "cards", title: "Virtual Game Cards",
                footnote: "\(loaded) of \(games.count) loaded. Ejected software leaves the HOME Menu but stays in All Software.",
                items: games.map { game in
                    MenuItem(
                        id: game.id,
                        title: game.title,
                        subtitle: isLoaded(game) ? "Loaded on this system" : "Ejected",
                        image: IconCache.shared.icon(for: game),
                        kind: .toggle(isLoaded(game)) { [unowned self] in setLoaded(game, $0) }
                    )
                }
            )]
        }
    }
}
