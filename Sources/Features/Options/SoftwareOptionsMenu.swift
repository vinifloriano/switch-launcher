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
            if running {
                info.insert(
                    MenuItem(id: "close", title: "Close Software", subtitle: "Ends the running game.",
                             symbol: "xmark.circle.fill", isDestructive: true,
                             kind: .action { [unowned self] in confirmClose(game) }),
                    at: 1
                )
            }
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
                MenuItem(id: "dataSize", title: "Save Data",
                         subtitle: (usage.map { $0.data > 0 ? ByteFormatter.string($0.data) : "None" } ?? measuring)
                             + " · kept when the software is deleted",
                         symbol: "person.crop.square.filled.and.at.rectangle",
                         kind: .link { [unowned self] in push(.menu(makeSettingsMenu(startingAt: "users"))) }),
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
            if let save = storage.saveData(titleID: game.titleID) {
                data.append(MenuItem(
                    id: "saveBackups", title: "Save Data Backups",
                    subtitle: "Back up or restore this game's local save data.",
                    symbol: "externaldrive.badge.timemachine",
                    kind: .link { [unowned self] in openSaveDataOptions(save) }
                ))
            }
            if !isAddedApp(game), StorageUsage.drives().count > 1 {
                let moving = storage.moving[game.id]
                data.append(MenuItem(id: "move", title: "Move Software",
                                     subtitle: moving.map { "Moving… \(Int($0 * 100))%" } ?? "Move to another drive, such as an external SSD.",
                                     symbol: "arrow.right.doc.on.clipboard",
                                     kind: .action { [unowned self] in confirmMove(game) }))
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
        guard checkPIN("delete software") else { return }
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
                detail: "The software\(size) is moved to the Trash. Save data stays on this Mac and comes back when you install it again, from the Game Store too.",
                confirmTitle: "Delete") { [unowned self] in
            do {
                try StorageUsage.trashSoftware(game)
                softwareRemoved(game, message: storage.hasSaveData(titleID: game.titleID)
                                ? "\(game.title) was moved to the Trash. Its save data was kept."
                                : "\(game.title) was moved to the Trash.")
            } catch {
                sound.play(.error)
                showToast("Couldn't delete \(game.title).", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// Deleting save data can't be taken back in the launcher, so it asks twice.
    func confirmDeleteSave(_ save: SaveData) {
        guard checkPIN("delete save data") else { return }
        let title = saveTitle(save)
        if let game = library.games.first(where: { $0.titleID?.uppercased() == save.titleID }),
           launcher.runningGameID == game.id {
            sound.play(.error)
            showToast("Close \(game.title) first.", symbol: "exclamationmark.triangle.fill")
            return
        }
        confirm(message: "Delete save data for \(title)?",
                detail: "\(ByteFormatter.string(save.size)) · your progress, settings and shader caches for this software.",
                confirmTitle: "Continue") { [unowned self] in
            confirm(message: "Are you sure?",
                    detail: "All progress in \(title) will be lost. The save data is moved to the Trash.",
                    confirmTitle: "Delete Save Data") { [unowned self] in
                do {
                    try storage.trash(save)
                    library.games.filter { $0.titleID?.uppercased() == save.titleID }.forEach(storage.remeasure)
                    showToast("Save data for \(title) was moved to the Trash.", symbol: "trash.fill")
                } catch {
                    sound.play(.error)
                    showToast("Couldn't delete the save data.", symbol: "exclamationmark.triangle.fill")
                }
            }
        }
    }

    /// Name of the software a save belongs to, even once that software is deleted.
    func saveTitle(_ save: SaveData) -> String {
        library.games.first { $0.titleID?.uppercased() == save.titleID }?.title
            ?? store.catalog.games.first { $0.titleID?.uppercased() == save.titleID }?.title
            ?? storage.knownTitles[save.titleID]
            ?? save.titleID
    }

    var saveBackupRoot: URL {
        URL(
            fileURLWithPath: (settings.value.saveBackupFolder as NSString).expandingTildeInPath,
            isDirectory: true
        )
    }

    var saveBackupService: SaveBackupService {
        SaveBackupService(root: saveBackupRoot)
    }

    func openSaveDataOptions(_ save: SaveData) {
        push(.menu(makeSaveDataMenu(save)))
    }

    func makeSaveDataMenu(_ save: SaveData) -> MenuModel {
        MenuModel(title: saveTitle(save), icon: .symbol("externaldrive.badge.person.crop"), app: self) { [unowned self] in
            let backups = saveBackupService.backups(for: save.titleID)
            let latest = backups.first
            var items = [
                MenuItem(id: "size", title: "Current Save Data", kind: .info(ByteFormatter.string(save.size))),
                MenuItem(id: "backup", title: "Back Up Now", subtitle: "Creates a timestamped local snapshot.",
                         symbol: "externaldrive.badge.plus",
                         kind: .action { [unowned self] in backupSave(save) }),
            ]
            if let latest {
                items.append(MenuItem(
                    id: "restore", title: "Restore Latest Backup",
                    subtitle: "\(PlayTimeFormatter.relative(latest.createdAt)) · \(ByteFormatter.string(latest.size))",
                    symbol: "clock.arrow.circlepath", isDestructive: true,
                    kind: .action { [unowned self] in confirmRestore(latest, save: save) }
                ))
            }
            items += [
                MenuItem(id: "folder", title: "Show Backups in Finder", subtitle: saveBackupRoot.path,
                         symbol: "folder.fill", kind: .action { [unowned self] in showSaveBackupFolder() }),
                MenuItem(id: "changeFolder", title: "Change Backup Folder", symbol: "folder.badge.gearshape",
                         kind: .action { [unowned self] in chooseSaveBackupFolder() }),
                MenuItem(id: "delete", title: "Delete Save Data", subtitle: "Back up first if you may want it later.",
                         symbol: "trash.fill", isDestructive: true,
                         kind: .action { [unowned self] in confirmDeleteSave(save) }),
            ]
            return [MenuSection(
                id: "save", title: "Save Data",
                footnote: L10n.format(
                    backups.count == 1 ? "%@ timestamped backup. The current save is backed up automatically before a restore."
                        : "%@ timestamped backups. The current save is backed up automatically before a restore.",
                    String(backups.count)
                ),
                items: items
            )]
        }
    }

    func backupSave(_ save: SaveData) {
        let service = saveBackupService
        showToast("Backing up \(saveTitle(save))…", symbol: "externaldrive.badge.plus")
        Task {
            do {
                let backup = try await Task.detached(priority: .utility) { try service.backup(save) }.value
                showToast("Save data backed up · \(ByteFormatter.string(backup.size)).", symbol: "checkmark.circle.fill")
            } catch {
                sound.play(.error)
                showToast("Couldn't back up the save data. \(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func backupAllSaves() {
        let saves = storage.saves
        guard !saves.isEmpty else {
            showToast("No save data to back up.")
            return
        }
        let service = saveBackupService
        showToast("Backing up \(saves.count) saves…", symbol: "externaldrive.badge.plus")
        Task {
            let result = await Task.detached(priority: .utility) { () -> (Int, String?) in
                var count = 0
                for save in saves {
                    do {
                        try service.backup(save)
                        count += 1
                    } catch {
                        return (count, error.localizedDescription)
                    }
                }
                return (count, nil)
            }.value
            if let error = result.1 {
                sound.play(.error)
                showToast("Backed up \(result.0) of \(saves.count). \(error)", symbol: "exclamationmark.triangle.fill")
            } else {
                showToast("Backed up \(result.0) saves.", symbol: "checkmark.circle.fill")
            }
        }
    }

    func confirmRestore(_ backup: SaveBackup, save: SaveData) {
        if let game = library.games.first(where: { $0.titleID?.uppercased() == save.titleID }),
           launcher.runningGameID == game.id {
            sound.play(.error)
            showToast("Close \(game.title) before restoring its save.", symbol: "exclamationmark.triangle.fill")
            return
        }
        confirm(
            message: "Restore the latest save backup?",
            detail: "The current save is backed up first, then replaced with the snapshot from \(PlayTimeFormatter.relative(backup.createdAt)).",
            confirmTitle: "Restore"
        ) { [unowned self] in
            let service = saveBackupService
            Task {
                do {
                    try await Task.detached(priority: .utility) { try service.restore(backup, to: save.url) }.value
                    storage.measureSaves()
                    library.games.filter { $0.titleID?.uppercased() == save.titleID }.forEach(storage.remeasure)
                    showToast("Save data restored.", symbol: "clock.arrow.circlepath")
                } catch {
                    sound.play(.error)
                    showToast("Couldn't restore the save data. \(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
                }
            }
        }
    }

    func showSaveBackupFolder() {
        do {
            try FileManager.default.createDirectory(at: saveBackupRoot, withIntermediateDirectories: true)
            NSWorkspace.shared.open(saveBackupRoot)
        } catch {
            sound.play(.error)
            showToast("Couldn't open the backup folder.", symbol: "exclamationmark.triangle.fill")
        }
    }

    func chooseSaveBackupFolder() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("Choose Save Backup Folder")
        panel.prompt = L10n.text("Choose")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = saveBackupRoot
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.value.saveBackupFolder = url.path
        showToast("Save backups will be stored in \(url.lastPathComponent).", symbol: "folder.fill")
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
