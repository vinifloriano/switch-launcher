import AppKit
import DesignSystem
import LauncherCore

extension AppModel {
    /// The page opened with + on a software tile.
    func makeOptionsMenu(for game: Game) -> MenuModel {
        MenuModel(title: game.title, icon: .image(IconCache.shared.icon(for: game)), app: self) { [unowned self] in
            let running = launcher.runningGameID == game.id
            let record = history.record(for: game.id)

            var info = [
                MenuItem(id: "start", title: running ? "Resume Software" : "Start Software", symbol: "play.fill",
                         kind: .action { [unowned self] in launch(game) }),
                MenuItem(id: "version", title: "Version", kind: .info(game.version ?? "—")),
            ]
            if let titleID = game.titleID {
                info.append(MenuItem(id: "titleID", title: "Title ID", kind: .info(titleID)))
            }
            if let category = game.category {
                info.append(MenuItem(id: "category", title: "Genre", kind: .info(category)))
            }
            info.append(MenuItem(id: "location", title: "Location", subtitle: game.url.path, kind: .info("")))

            var data = [
                MenuItem(id: "finder", title: "Show in Finder", symbol: "folder.fill", kind: .action {
                    NSWorkspace.shared.activateFileViewerSelecting([game.url])
                }),
                MenuItem(id: "loaded", title: "Show on HOME Menu", subtitle: "Load or eject the virtual game card.",
                         kind: .toggle(isLoaded(game)) { [unowned self] in setLoaded(game, $0) }),
            ]
            if running {
                data.append(MenuItem(id: "close", title: "Close Software", symbol: "xmark.circle.fill", isDestructive: true,
                                     kind: .action { [unowned self] in confirmClose(game) }))
            }

            return [
                MenuSection(id: "info", title: "Software Information", symbol: "info.circle.fill", items: info),
                MenuSection(id: "activity", title: "Play Activity", symbol: "chart.bar.fill", items: [
                    MenuItem(id: "total", title: "Total Play Time", kind: .info(
                        record.lastPlayed == nil ? "—" : PlayTimeFormatter.duration(record.totalSeconds))),
                    MenuItem(id: "launches", title: "Times Started", kind: .info("\(record.launches)")),
                    MenuItem(id: "first", title: "First Played", kind: .info(PlayTimeFormatter.relative(record.firstPlayed))),
                    MenuItem(id: "last", title: "Last Played", kind: .info(PlayTimeFormatter.relative(record.lastPlayed))),
                ]),
                MenuSection(id: "data", title: "Data Management", symbol: "externaldrive.fill", items: data),
            ]
        }
    }
}
