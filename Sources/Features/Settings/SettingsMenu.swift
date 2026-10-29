import AppKit
import DesignSystem
import LauncherCore
import UniformTypeIdentifiers

extension AppModel {
    /// `startingAt` opens the page on a section (by id), e.g. "internet".
    func makeSettingsMenu(startingAt section: String? = nil) -> MenuModel {
        // Older names for sections that were merged.
        let section = ["store": "internet", "saves": "users", "library": "data"][section ?? ""] ?? section
        controls.refresh()
        let menu = MenuModel(title: "System Settings", icon: .symbol("gearshape.fill"), app: self) { [unowned self] in
            [
                airplaneSection,
                brightnessSection,
                bluetoothSection,
                internetSection,
                parentalSection,
                accessibilitySection,
                dataSection,
                usersSection,
                controlsSection,
                audioSection,
                displaySection,
                themesSection,
                notificationsSection,
                sleepSection,
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

    /// Game Store server settings, shown under Internet.
    var storeItems: [MenuItem] {
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
        return [
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

    var themesSection: MenuSection {
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


    /// Library folders and Add/Rescan, shown in Data Management.
    var libraryItems: [MenuItem] {
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
        return items
    }




    var controlsSection: MenuSection {
        let keys: [(String, String)] = [
            ("Move", "Arrow keys"), ("A", "Return / Space"), ("B", "Esc / Delete"),
            ("X", "X"), ("Y", "Y"), ("+ / −", "= / -"), ("L / R", "Q / E"),
            ("HOME", "H"), ("Quick Settings (hold HOME)", "⇧H"), ("Capture", "P"), ("Full Screen", "⌃⌘F"),
        ]
        return MenuSection(
            id: "controls", title: "Controllers and Accessories", symbol: "gamecontroller.fill",
            items: [
                MenuItem(id: "test", title: "Test Input Devices", subtitle: "Check buttons, sticks and triggers.",
                         symbol: "gamecontroller.fill", kind: .link { [unowned self] in openControllerTest() }),
                MenuItem(id: "grip", title: "Change Grip/Order", subtitle: "Assign player numbers with L + R.",
                         symbol: "arrow.left.arrow.right", kind: .link { [unowned self] in openGripOrder() }),
                toggle("layout", "Nintendo Button Layout", \.nintendoButtonLayout,
                       subtitle: "Use A/B/X/Y as printed on Nintendo controllers."),
                .header("Keyboard"),
            ] + keys.map { MenuItem(id: "key:" + $0.0, title: $0.0, kind: .info($0.1)) }
        )
    }

    var systemSection: MenuSection {
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
                MenuItem(id: "update", title: "Software Update", subtitle: updateStatus,
                         symbol: updates.availableRelease == nil ? "arrow.clockwise.circle.fill" : "arrow.down.circle.fill",
                         kind: .action { [unowned self] in openSoftwareUpdate() }),
                toggle("autoUpdate", "Check for Updates Automatically", \.checkForUpdates,
                       subtitle: "Looks for a new release on GitHub at startup and every 6 hours."),
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

    private var updateStatus: String {
        switch updates.state {
        case .available(let release): return "Version \(release.version) is available. Select to download."
        case .checking: return "Checking…"
        case .failed(let message): return message
        case .upToDate, .idle:
            guard let checked = updates.lastChecked else { return "Select to check for a new version." }
            return "Up to date · checked \(checked.formatted(date: .omitted, time: .shortened))"
        }
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
