import AppKit
import DesignSystem
import LauncherCore

extension AppModel {
    /// The page opened with + on a software tile.
    func makeOptionsMenu(for game: Game) -> MenuModel {
        storage.measure([game])
        return MenuModel(title: game.title, icon: .image(IconCache.shared.icon(for: game)), app: self) { [unowned self] in
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

            let usage = storage.software[game.id]
            let measuring = "Measuring…"
            var data = [
                MenuItem(id: "appSize", title: "Software", kind: .info(usage.map { ByteFormatter.string($0.app) } ?? measuring)),
                MenuItem(id: "dataSize", title: "Save Data", subtitle: "Saves, shader caches and temporary files.",
                         kind: .info(usage.map { $0.data > 0 ? ByteFormatter.string($0.data) : "None" } ?? measuring)),
            ]
            if let volume = StorageUsage.volume(for: game.url) {
                data.append(MenuItem(id: "free", title: "Free Space", subtitle: volume.name,
                                     kind: .info("\(ByteFormatter.string(volume.available)) of \(ByteFormatter.string(volume.total))")))
            }
            data += [
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
            if StorageUsage.dataFolder(for: game) != nil {
                data.append(MenuItem(id: "deleteData", title: "Delete Save Data", subtitle: "Your progress in this software will be lost.",
                                     symbol: "trash", isDestructive: true,
                                     kind: .action { [unowned self] in confirmDeleteData(game) }))
            }
            if isAddedApp(game) {
                data.append(MenuItem(id: "remove", title: "Remove from Library", subtitle: "The app itself stays where it is.",
                                     symbol: "minus.circle.fill", isDestructive: true,
                                     kind: .action { [unowned self] in confirmDelete(game) }))
            } else {
                data.append(MenuItem(id: "delete", title: "Delete Software", subtitle: "Moves the app to the Trash. Save data is kept.",
                                     symbol: "trash.fill", isDestructive: true,
                                     kind: .action { [unowned self] in confirmDelete(game) }))
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

    /// Apps added one by one with Add Software are only referenced, never deleted.
    func isAddedApp(_ game: Game) -> Bool {
        settings.value.extraApps.contains(game.url.path)
    }

    /// Delete Software (moves the app to the Trash), or Remove from Library for an added app.
    func confirmDelete(_ game: Game) {
        guard launcher.runningGameID != game.id else {
            sound.play(.error)
            showToast("Close \(game.title) first.", symbol: "exclamationmark.triangle.fill")
            return
        }
        if isAddedApp(game) {
            confirm(message: "Remove \(game.title) from the library?", detail: "The app itself stays where it is.",
                    confirmTitle: "Remove") { [unowned self] in
                settings.value.extraApps.removeAll { $0 == game.url.path }
                softwareRemoved(game, message: "\(game.title) was removed from the library.")
            }
            return
        }
        let size = storage.software[game.id].map { " (\(ByteFormatter.string($0.app)))" } ?? ""
        confirm(message: "Delete \(game.title)?",
                detail: "The software\(size) is moved to the Trash. Save data is kept, so you can pick up where you left off if you install it again.",
                confirmTitle: "Delete") { [unowned self] in
            do {
                try StorageUsage.trashSoftware(game)
                softwareRemoved(game, message: "\(game.title) was moved to the Trash.")
            } catch {
                sound.play(.error)
                showToast("Couldn't delete \(game.title).", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func confirmDeleteData(_ game: Game) {
        guard launcher.runningGameID != game.id else {
            sound.play(.error)
            showToast("Close \(game.title) first.", symbol: "exclamationmark.triangle.fill")
            return
        }
        confirm(message: "Delete save data for \(game.title)?",
                detail: "Your progress in this software will be lost. The data is moved to the Trash.",
                confirmTitle: "Delete") { [unowned self] in
            do {
                try StorageUsage.trashData(game)
                storage.remeasure(game)
                showToast("Save data was moved to the Trash.", symbol: "trash.fill")
            } catch {
                sound.play(.error)
                showToast("Couldn't delete the save data.", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    private func softwareRemoved(_ game: Game, message: String) {
        storage.forget(game)
        settings.value.ejectedGameIDs.remove(game.id)
        // Leave the options page of the software that no longer exists.
        if case .menu(let menu)? = stack.last, menu.title == game.title { pop() }
        showToast(message, symbol: "trash.fill")
        Task { await reloadLibrary() }
    }
}
