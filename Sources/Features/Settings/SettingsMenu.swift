import AppKit
import DesignSystem
import LauncherCore
import UniformTypeIdentifiers

extension AppModel {
    /// `startingAt` opens the page on a section (by id), e.g. "store".
    func makeSettingsMenu(startingAt section: String? = nil) -> MenuModel {
        let menu = MenuModel(title: "System Settings", icon: .symbol("gearshape.fill"), app: self) { [unowned self] in
            [
                themesSection,
                soundSection,
                librarySection,
                dataSection,
                savesSection,
                storeSection,
                launcherSection,
                controlsSection,
                systemSection,
            ]
        }
        storage.measure(library.games)
        storage.measureSaves()
        if let section, let index = menu.sections.firstIndex(where: { $0.id == section }) {
            menu.sectionIndex = index
        }
        return menu
    }

    private var storeSection: MenuSection {
        let config = settings.value.store
        func edit(_ id: String, _ title: String, _ value: String, placeholder: String, message: String,
                  _ keyPath: WritableKeyPath<StoreConfig, String>) -> MenuItem {
            MenuItem(id: id, title: title, subtitle: value.isEmpty ? placeholder : value, symbol: "pencil",
                     kind: .action { [unowned self] in
                guard let text = promptText(title, message: message, value: value) else { return }
                settings.value.store[keyPath: keyPath] = text
            })
        }
        var status = "Not set up"
        switch store.state {
        case .ready: status = "Connected · \(store.catalog.games.count) games"
        case .loading: status = "Connecting…"
        case .failed(let error): status = error
        case .notConfigured: break
        }
        return MenuSection(
            id: "store", title: "Store", symbol: "bag.fill",
            footnote: "Your own S3-compatible server (SeaweedFS, MinIO, AWS S3, R2…) that the Game Store downloads from. The password is saved in the launcher's settings file, readable only by your user.",
            items: [
                MenuItem(id: "storeStatus", title: "Status", kind: .info(status)),
                edit("storeLocal", "Home Network Address", config.localEndpoint, placeholder: "e.g. http://192.168.1.10:30900",
                     message: "Address of the S3 server on your home network. Tried first.", \.localEndpoint),
                edit("storeRemote", "Remote Address", config.remoteEndpoint, placeholder: "Optional, e.g. https://games.example.net",
                     message: "Address from anywhere, e.g. through a Cloudflare tunnel. Used when the home address doesn't answer.", \.remoteEndpoint),
                edit("storeBucket", "Bucket", config.bucket, placeholder: "switch-games",
                     message: "Name of the bucket that holds catalog.json and the games.", \.bucket),
                edit("storeUser", "Username", config.username, placeholder: "Not set",
                     message: "Your store username (the S3 access key).", \.username),
                MenuItem(id: "storePassword", title: "Password", subtitle: config.password.isEmpty ? "Not set" : "Saved",
                         symbol: "key.fill", kind: .action { [unowned self] in
                    guard let password = promptText("Password", message: "Password for \(settings.value.store.username.isEmpty ? "the store" : settings.value.store.username).", secure: true),
                          !password.isEmpty else { return }
                    settings.value.store.password = password
                }),
                MenuItem(id: "storeFolder", title: "Install Downloads To", subtitle: storeInstallFolder.path,
                         symbol: "folder.fill", kind: .action { [unowned self] in chooseStoreFolder() }),
                MenuItem(id: "storeTest", title: "Test Connection", symbol: "bolt.horizontal.circle.fill",
                         kind: .action { [unowned self] in
                    Task {
                        applyStoreConfig()
                        await store.refresh()
                        switch store.state {
                        case .ready: showToast("Connected: \(store.catalog.games.count) games.", symbol: "checkmark.circle.fill")
                        case .failed(let error): showToast(error, symbol: "exclamationmark.triangle.fill")
                        default: showToast("Fill in the address, username and password first.", symbol: "info.circle.fill")
                        }
                    }
                }),
            ]
        )
    }

    private func chooseStoreFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose where downloaded games are installed."
        panel.directoryURL = storeInstallFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.value.store.installFolder = url.path
    }

    private var themesSection: MenuSection {
        let choices = ThemeChoice.allCases
        return MenuSection(
            id: "themes", title: "Themes", symbol: "paintpalette.fill",
            footnote: "Choose a theme for the HOME Menu.",
            items: [
                MenuItem(id: "theme", title: "Theme", kind: .choice(
                    choices.map(\.displayName),
                    choices.firstIndex(of: settings.value.theme) ?? 0,
                    { [unowned self] in settings.value.theme = choices[$0] }
                )),
            ]
        )
    }

    private var soundSection: MenuSection {
        let levels: [(String, Double)] = [("Low", 0.35), ("Medium", 0.7), ("High", 1.0)]
        let current = levels.indices.min {
            abs(levels[$0].1 - settings.value.soundVolume) < abs(levels[$1].1 - settings.value.soundVolume)
        } ?? 1
        return MenuSection(
            id: "sound", title: "Sound", symbol: "speaker.wave.2.fill",
            items: [
                MenuItem(id: "sounds", title: "HOME Menu Sounds", kind: .toggle(settings.value.soundsEnabled) { [unowned self] in
                    settings.value.soundsEnabled = $0
                }),
                MenuItem(id: "volume", title: "Sound Volume", kind: .choice(levels.map(\.0), current) { [unowned self] in
                    settings.value.soundVolume = levels[$0].1
                    sound.play(.select)
                }),
            ]
        )
    }

    private var librarySection: MenuSection {
        var items: [MenuItem] = settings.value.libraryFolders.map { path in
            MenuItem(
                id: "folder:" + path,
                title: (path as NSString).lastPathComponent,
                subtitle: path,
                symbol: FileManager.default.fileExists(atPath: path) ? "folder.fill" : "questionmark.folder",
                kind: .action { [unowned self] in
                    confirm(message: "Remove this folder from the library?", detail: path, confirmTitle: "Remove") { [unowned self] in
                        settings.value.libraryFolders.removeAll { $0 == path }
                        Task { await reloadLibrary() }
                    }
                }
            )
        }
        items += settings.value.extraApps.map { path in
            MenuItem(
                id: "app:" + path,
                title: ((path as NSString).lastPathComponent as NSString).deletingPathExtension,
                subtitle: path,
                symbol: "app.fill",
                kind: .action { [unowned self] in
                    confirm(message: "Remove this software from the library?", detail: path, confirmTitle: "Remove") { [unowned self] in
                        settings.value.extraApps.removeAll { $0 == path }
                        Task { await reloadLibrary() }
                    }
                }
            )
        }
        items += [
            MenuItem(id: "addFolder", title: "Add Folder…", symbol: "folder.badge.plus", kind: .action { [unowned self] in
                addLibraryFolder()
            }),
            MenuItem(id: "addApp", title: "Add Software…", subtitle: "Any Mac app, shown like a game",
                     symbol: "plus.app.fill", kind: .action { [unowned self] in
                addSoftware()
            }),
            MenuItem(id: "rescan", title: "Rescan Library",
                     subtitle: library.isScanning ? "Scanning…" : "\(library.games.count) titles found",
                     symbol: "arrow.clockwise", kind: .action { [unowned self] in
                Task {
                    await reloadLibrary()
                    showToast("Found \(library.games.count) titles.", symbol: "checkmark.circle.fill")
                }
            }),
        ]
        return MenuSection(
            id: "library", title: "Library", symbol: "books.vertical.fill",
            footnote: "Folders scanned for native ports (apps built by nxnative / MacNativeGames). Select a folder to remove it.",
            items: items
        )
    }

    /// Data Management: free space on the disks that hold software, and what each title takes.
    private var dataSection: MenuSection {
        let games = library.games
        let usage = storage.software
        let measured = games.compactMap { usage[$0.id] }
        let done = measured.count == games.count

        // Every disk that holds software or receives downloads, once each.
        var volumes: [VolumeUsage] = []
        for url in games.map(\.url) + [storeInstallFolder] {
            if let volume = StorageUsage.volume(for: url), !volumes.contains(where: { $0.url == volume.url }) {
                volumes.append(volume)
            }
        }
        var items = volumes.map { volume in
            MenuItem(id: "volume:" + volume.url.path, title: volume.name,
                     subtitle: "\(ByteFormatter.string(volume.used)) used of \(ByteFormatter.string(volume.total))",
                     symbol: "internaldrive.fill",
                     kind: .info("\(ByteFormatter.string(volume.available)) free"))
        }
        let progress = done ? "" : " · measuring \(measured.count) of \(games.count)…"
        items += [
            MenuItem(id: "softwareTotal", title: "Software", subtitle: "\(games.count) titles\(progress)",
                     kind: .info(ByteFormatter.string(measured.reduce(0) { $0 + $1.app }))),
            MenuItem(id: "dataTotal", title: "Save Data",
                     kind: .info(ByteFormatter.string(measured.reduce(0) { $0 + $1.data }))),
        ]
        // Largest first; titles still being measured go last.
        let sorted = games.sorted { (usage[$0.id]?.total ?? -1) > (usage[$1.id]?.total ?? -1) }
        items += sorted.map { game in
            let size = usage[game.id].map { usage in
                usage.data > 0
                    ? "\(ByteFormatter.string(usage.app)) · save data \(ByteFormatter.string(usage.data))"
                    : ByteFormatter.string(usage.app)
            } ?? "Measuring…"
            return MenuItem(id: "size:" + game.id, title: game.title, subtitle: size,
                            image: IconCache.shared.icon(for: game),
                            kind: .link { [unowned self] in openOptions(for: game) })
        }
        return MenuSection(
            id: "data", title: "Data Management", symbol: "externaldrive.fill",
            footnote: "Select software to see its details or delete it. Deleted software and save data go to the Trash.",
            items: items
        )
    }

    /// Save Data: every title's saves on this Mac, installed or not. Deleting asks twice.
    private var savesSection: MenuSection {
        let saves = storage.saves
        var items = [MenuItem(id: "savesTotal", title: "Total", subtitle: "\(saves.count) titles",
                              kind: .info(ByteFormatter.string(saves.reduce(0) { $0 + $1.size })))]
        items += saves.map { save in
            let game = library.games.first { $0.titleID?.uppercased() == save.titleID }
            return MenuItem(id: "save:" + save.titleID, title: saveTitle(save),
                            subtitle: "\(game == nil ? "Not installed" : "Installed") · \(ByteFormatter.string(save.size))",
                            image: game.flatMap { IconCache.shared.icon(for: $0) },
                            symbol: game == nil ? "externaldrive.badge.person.crop" : nil,
                            kind: .action { [unowned self] in confirmDeleteSave(save) })
        }
        return MenuSection(
            id: "saves", title: "Save Data", symbol: "person.crop.square.filled.and.at.rectangle",
            footnote: "Save data stays on this Mac when you delete software, and comes back when you install it again, from the Game Store too. Select a title to delete its save data.",
            items: items
        )
    }

    private var launcherSection: MenuSection {
        MenuSection(
            id: "launcher", title: "Launcher", symbol: "house.fill",
            items: [
                toggle("fullscreen", "Start in Full Screen", \.startFullScreen),
                toggle("boot", "Startup Animation", \.showBootAnimation),
                toggle("gameFullScreen", "Play Software in Full Screen", \.playInFullScreen,
                       subtitle: "Games open full screen on top of the launcher."),
                toggle("keepFront", "Keep Software in Front", \.keepGameInFront,
                       subtitle: "Take focus back when a background app steals it during play."),
                toggle("hide", "Hide Launcher While Playing", \.hideWhilePlaying),
                toggle("homeReturn", "HOME Button Returns to Launcher", \.homeButtonReturnsToLauncher,
                       subtitle: "Press HOME on a controller during a game to come back here."),
            ]
        )
    }

    private var controlsSection: MenuSection {
        let keys: [(String, String)] = [
            ("Move", "Arrow keys"), ("A", "Return / Space"), ("B", "Esc / Delete"),
            ("X", "X"), ("Y", "Y"), ("+ / −", "= / -"), ("L / R", "Q / E"),
            ("HOME", "H"), ("Quick Settings (hold HOME)", "⇧H"), ("Capture", "P"), ("Full Screen", "⌃⌘F"),
        ]
        return MenuSection(
            id: "controls", title: "Controllers & Keys", symbol: "keyboard.fill",
            items: [
                MenuItem(id: "test", title: "Test Input Devices", subtitle: "Check buttons, sticks and triggers.",
                         symbol: "gamecontroller.fill", kind: .link { [unowned self] in openControllerTest() }),
                MenuItem(id: "grip", title: "Change Grip/Order", subtitle: "Assign player numbers with L + R.",
                         symbol: "arrow.left.arrow.right", kind: .link { [unowned self] in openGripOrder() }),
                toggle("layout", "Nintendo Button Layout", \.nintendoButtonLayout,
                       subtitle: "Use A/B/X/Y as printed on Nintendo controllers."),
            ] + keys.map { MenuItem(id: "key:" + $0.0, title: $0.0, kind: .info($0.1)) }
        )
    }

    private var systemSection: MenuSection {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info["CFBundleVersion"] as? String
        let commit = info["SLGitCommit"] as? String
        let version = [short, [build, commit].compactMap { $0 }.joined(separator: ", ")]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return MenuSection(
            id: "system", title: "System", symbol: "info.circle.fill",
            items: [
                MenuItem(id: "version", title: "Launcher Version", kind: .info(version)),
                MenuItem(id: "software", title: "Installed Software", kind: .info("\(library.games.count)")),
                MenuItem(id: "data", title: "Data Folder", subtitle: AppPaths.supportDirectory.path, symbol: "folder",
                         kind: .action { NSWorkspace.shared.open(AppPaths.supportDirectory) }),
                MenuItem(id: "fs", title: "Toggle Full Screen", symbol: "arrow.up.left.and.arrow.down.right",
                         kind: .action { [unowned self] in toggleFullScreen() }),
                MenuItem(id: "quit", title: "Quit Launcher", symbol: "power", isDestructive: true,
                         kind: .action { NSApp.terminate(nil) }),
            ]
        )
    }

    private func toggle(
        _ id: String,
        _ title: String,
        _ keyPath: WritableKeyPath<LauncherSettings, Bool>,
        subtitle: String? = nil
    ) -> MenuItem {
        MenuItem(id: id, title: title, subtitle: subtitle, kind: .toggle(settings.value[keyPath: keyPath]) { [unowned self] in
            settings.value[keyPath: keyPath] = $0
        })
    }

    /// Add to Library: a game app is added on its own, any other folder is scanned for software.
    func addToLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.applicationBundle, .folder]
        panel.directoryURL = storeInstallFolder
        panel.prompt = "Add"
        panel.message = "Choose game apps, or folders that contain them."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if url.pathExtension == "app" {
                // Already found through its folder: adding it again would make it a reference only.
                let scanned = settings.value.libraryFolders.contains(url.deletingLastPathComponent().path)
                if !scanned, !settings.value.extraApps.contains(url.path) { settings.value.extraApps.append(url.path) }
            } else if !settings.value.libraryFolders.contains(url.path) {
                settings.value.libraryFolders.append(url.path)
            }
        }
        let before = library.games.count
        Task {
            await reloadLibrary()
            let added = library.games.count - before
            showToast(added > 0 ? "Added \(added) \(added == 1 ? "title" : "titles")." : "No new software found.",
                      symbol: added > 0 ? "checkmark.circle.fill" : "info.circle.fill")
        }
    }

    private func addLibraryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folders that contain native game apps."
        guard panel.runModal() == .OK else { return }
        let new = panel.urls.map(\.path).filter { !settings.value.libraryFolders.contains($0) }
        settings.value.libraryFolders += new
        Task { await reloadLibrary() }
    }

    private func addSoftware() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        let new = panel.urls.map(\.path).filter { !settings.value.extraApps.contains($0) }
        settings.value.extraApps += new
        Task { await reloadLibrary() }
    }
}
