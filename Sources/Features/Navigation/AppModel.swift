import AppKit
import DesignSystem
import InputKit
import LauncherCore
import Observation
import SoundKit
import SwiftUI

/// A screen that reacts to controller buttons.
@MainActor
public protocol InputResponder: AnyObject {
    func handle(_ button: NintendoButton)
}

/// Screens pushed on top of the HOME Menu.
@MainActor
public enum Route: Identifiable {
    case library(LibraryModel)
    case menu(MenuModel)
    case album(AlbumModel)
    case sleep(SleepModel)
    case web(WebModel)
    case controllers(ControllersModel)
    case gripOrder(GripOrderModel)
    case controllerTest(ControllerTestModel)
    case store(StoreModel)

    public var id: ObjectIdentifier { ObjectIdentifier(responder) }

    public var responder: InputResponder {
        switch self {
        case .library(let model): model
        case .menu(let model): model
        case .album(let model): model
        case .sleep(let model): model
        case .web(let model): model
        case .controllers(let model): model
        case .gripOrder(let model): model
        case .controllerTest(let model): model
        case .store(let model): model
        }
    }
}

public struct ToastMessage: Identifiable, Equatable {
    public let id = UUID()
    public let text: String
    public let symbol: String
}

/// Owns the services and the navigation stack, and routes input to the screen on top.
@MainActor @Observable
public final class AppModel {
    public let settings = SettingsStore()
    public let history = PlayHistory()
    public let library = GameLibrary()
    public let launcher = GameLauncher()
    public let status = SystemStatus()
    public let input = InputRouter()
    public let store = StoreService()
    public let storage = StorageUsage()
    public let updates = UpdateChecker()
    public let controls = MacControls()
    @ObservationIgnored public let sound = UISoundPlayer()

    public private(set) var stack: [Route] = []
    public var dialog: DialogModel?
    public var quickSettings: QuickSettingsModel?
    /// Set while the launch animation for this game is playing.
    public private(set) var launchingGame: Game?
    public private(set) var toast: ToastMessage?
    public var isBooting = false
    /// Whether the launcher window is in full screen (no title bar strip needed).
    public var isFullScreen = false
    @ObservationIgnored public private(set) var home: HomeModel!
    @ObservationIgnored private var started = false
    @ObservationIgnored private var updatesStarted = false
    @ObservationIgnored private var gamesAppWatch: NSObjectProtocol?
    @ObservationIgnored private var lastInput = Date()

    public init() {
        home = HomeModel(app: self)
        isBooting = settings.value.showBootAnimation && !settings.value.reduceMotion
    }

    public func start() {
        guard !started else { return }
        started = true

        applySettings(settings.value)
        settings.onChange = { [weak self] in self?.applySettings($0) }

        input.handler = { [weak self] in self?.handle($0) }
        input.backgroundHomeHandler = { [weak self] in self?.returnFromGame() }
        // With no game running, a controller should always drive the launcher, even if another
        // app took focus.
        input.acceptsInputWhileInactive = { [weak self] in
            guard let self, launcher.session == nil else { return false }
            bringToFront()
            return true
        }
        // Keys go to the web page while one is open (Esc still closes it).
        input.shouldPassKeyEvent = { [weak self] event in
            guard let self, case .web? = stack.last, dialog == nil, quickSettings == nil else { return false }
            return event.keyCode != 53
        }
        input.start()
        status.start()
        startAutoSleep()

        launcher.onSessionEnded = { [weak self] id, seconds in self?.sessionEnded(id, seconds: seconds) }
        store.onInstalled = { [weak self] game, url in self?.storeInstalled(game, at: url) }
        Task {
            await reloadLibrary()
            openScreenFromLaunchArgument()
            captureFromLaunchArgument()
        }
    }

    /// `-launchGame <title>` starts a game at launch.
    /// `-openScreen settings|settings:<section>|groups|data|saves|system|storage|add|library|album|user|controllers|cards|options|dialog|web|tester|grip|quick|capture|last|middle` opens a page at launch
    /// (handy for screenshots and UI checks).
    private func openScreenFromLaunchArgument() {
        if let title = UserDefaults.standard.string(forKey: "launchGame"),
           let game = library.games.first(where: { $0.title.localizedCaseInsensitiveContains(title) }) {
            isBooting = false
            launch(game)
        }
        guard let screen = UserDefaults.standard.string(forKey: "openScreen") else { return }
        isBooting = false
        if screen.hasPrefix("settings:") {
            push(.menu(makeSettingsMenu(startingAt: String(screen.dropFirst("settings:".count)))))
            return
        }
        switch screen {
        case "groups":
            let model = LibraryModel(app: self)
            model.tab = .groups
            push(.library(model))
        case "settings": openDock(.settings)
        case "data": push(.menu(makeSettingsMenu(startingAt: "data")))
        case "saves": push(.menu(makeSettingsMenu(startingAt: "saves")))
        case "system": push(.menu(makeSettingsMenu(startingAt: "system")))
        case "library": openLibrary()
        case "album": openDock(.album)
        case "user": openUserPage()
        case "controllers": openDock(.controllers)
        case "cards": openDock(.virtualGameCard)
        case "options": library.games.first.map(openOptions)
        case "storage":
            if let game = library.games.first {
                let menu = makeOptionsMenu(for: game)
                menu.sectionIndex = menu.sections.firstIndex { $0.id == "data" } ?? 0
                push(.menu(menu))
            }
        case "add":
            let model = LibraryModel(app: self)
            model.index = model.addIndex
            push(.library(model))
        case "dialog": confirm(message: "Close the software?", detail: "Any unsaved progress will be lost.", confirmTitle: "Close") {}
        case "web": openDock(.news)
        case "tester": openControllerTest()
        case "grip": openGripOrder()
        case "quick": toggleQuickSettings()
        case "capture": captureScreenshot()
        case "store": openDock(.eShop)
        case "last": home.select(home.items.count - 1)
        case "middle": home.select(5)
        case "roundtrip":
            home.select(home.items.count - 1)
            Task {
                try? await Task.sleep(for: .seconds(Double(home.items.count) * 0.12 + 0.6))
                home.select(0)
            }
        default: break
        }
    }

    private func applySettings(_ value: LauncherSettings) {
        sound.isEnabled = value.soundsEnabled
        sound.volume = Float(value.soundVolume)
        input.useNintendoLayout = value.nintendoButtonLayout
        launcher.keepGameInFront = value.keepGameInFront
        store.configure(value.store)
        if value.checkForUpdates {
            if !updatesStarted {
                updatesStarted = true
                updates.startChecking { [weak self] release in self?.announceUpdate(release) }
            }
        } else if updatesStarted {
            updatesStarted = false
            updates.stopChecking()
        }
    }

    public func theme(systemIsDark: Bool) -> Theme {
        switch settings.value.theme {
        case .basicWhite: .basicWhite
        case .basicBlack: .basicBlack
        case .matchSystem: systemIsDark ? .basicBlack : .basicWhite
        }
    }

    // MARK: Library

    public func reloadLibrary() async {
        await library.reload(folders: settings.libraryFolderURLs, extraApps: settings.extraAppURLs)
        storage.remember(library.games)
        launcher.adoptRunning(from: library.games)
        IconCache.shared.load(homeGames + library.games)
    }

    /// Software on the HOME Menu: loaded virtual game cards, most recent first, up to 12.
    public var homeGames: [Game] {
        let loaded = library.games.filter { !settings.value.ejectedGameIDs.contains($0.id) }
        return Array(LibraryOrdering.sort(loaded, by: .recentlyPlayed, history: history.records).prefix(12))
    }

    public func isLoaded(_ game: Game) -> Bool {
        !settings.value.ejectedGameIDs.contains(game.id)
    }

    public func setLoaded(_ game: Game, _ loaded: Bool) {
        if loaded {
            settings.value.ejectedGameIDs.remove(game.id)
        } else {
            settings.value.ejectedGameIDs.insert(game.id)
        }
    }

    // MARK: Input & navigation

    public func handle(_ button: NintendoButton) {
        lastInput = Date()
        if isBooting {
            isBooting = false
            return
        }
        if button == .home {
            keepGamesAppAway()
            quickSettings = nil
            goHome()
            return
        }
        if button == .homeHold {
            toggleQuickSettings()
            return
        }
        if button == .capture, !(stack.last.map(isControllerTest) ?? false) {
            captureScreenshot()
            return
        }
        if let dialog {
            dialog.handle(button)
            return
        }
        if let quickSettings {
            quickSettings.handle(button)
            return
        }
        if let top = stack.last {
            top.responder.handle(button)
        } else {
            home.handle(button)
        }
    }

    public func push(_ route: Route) {
        sound.play(.select)
        stack.append(route)
    }

    public func pop() {
        guard !stack.isEmpty else { return }
        sound.play(.back)
        stack.removeLast()
    }

    func replaceStack(_ routes: [Route]) {
        stack = routes
    }

    private func isControllerTest(_ route: Route) -> Bool {
        if case .controllerTest = route { return true }
        return false
    }

    /// HOME button: back to the HOME Menu, or, when already there, back into the running game.
    public func goHome() {
        if stack.isEmpty && dialog == nil {
            if launcher.session != nil {
                sound.play(.home)
                launcher.resume()
                hideOnceGameIsInFront()
            } else {
                sound.play(.home)
            }
            return
        }
        dialog = nil
        stack.removeAll()
        sound.play(.home)
    }

    /// HOME pressed on a controller while a game is in front.
    private func returnFromGame() {
        guard settings.value.homeButtonReturnsToLauncher, launcher.session != nil else { return }
        keepGamesAppAway()
        bringToFront()
        dialog = nil
        stack.removeAll()
        home.selectRunningSoftware()
        sound.play(.home)
    }

    /// If macOS still opens its Games app for the HOME press, hide it again and come back.
    private func keepGamesAppAway() {
        gamesAppWatch.map(NSWorkspace.shared.notificationCenter.removeObserver)
        let observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == "com.apple.games" else { return }
            app?.hide()
            MainActor.assumeIsolated { self?.bringToFront() }
        }
        gamesAppWatch = observer
        Task {
            try? await Task.sleep(for: .seconds(3))
            if gamesAppWatch === observer {
                NSWorkspace.shared.notificationCenter.removeObserver(observer)
                gamesAppWatch = nil
            }
        }
    }

    /// macOS refuses `activate()` from a background app, so ask LaunchServices to open us
    /// again, which it always allows.
    func bringToFront() {
        NSApp.unhide(nil)
        NSApp.activate()
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        let bundleURL = Bundle.main.bundleURL
        if !NSApp.isActive, bundleURL.pathExtension == "app" {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
        }
    }

    // MARK: Software

    public func launch(_ game: Game) {
        guard launchAllowedByParentalControls(game) else { return }
        if let runningID = launcher.runningGameID, runningID != game.id {
            let runningTitle = library.game(id: runningID)?.title ?? "the software"
            confirm(
                message: "Close \(runningTitle) and start \(game.title)?",
                detail: "Any unsaved progress will be lost.",
                confirmTitle: "Close and Start"
            ) { [weak self] in
                Task {
                    await self?.launcher.close()
                    self?.startNow(game)
                }
            }
            return
        }
        startNow(game)
    }

    private func startNow(_ game: Game) {
        sound.play(.launch)
        if launcher.runningGameID != game.id, !settings.value.reduceMotion {
            launchingGame = game
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                if launchingGame == game { launchingGame = nil }
            }
        }
        Task {
            do {
                // The ports' host reads DM_FULLSCREEN and opens its window in full screen.
                let environment = settings.value.playInFullScreen ? ["DM_FULLSCREEN": "1"] : [:]
                let started = try await launcher.launch(game, environment: environment)
                if started { history.markLaunched(game.id) }
                hideOnceGameIsInFront()
            } catch {
                launchingGame = nil
                sound.play(.error)
                showToast("Couldn't start \(game.title).", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// "Hide Launcher While Playing": hiding gives up focus, which the game needs to be handed
    /// first, so wait until the game is in front.
    private func hideOnceGameIsInFront() {
        guard settings.value.hideWhilePlaying else { return }
        Task {
            for _ in 0..<60 {
                guard launcher.session != nil else { return }
                if !NSApp.isActive {
                    NSApp.hide(nil)
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    // MARK: Store

    /// Re-reads the store settings (address, username, password).
    func applyStoreConfig() {
        store.configure(settings.value.store, force: true)
    }

    /// Downloads install here: the folder set in Store settings, else the first library folder.
    var storeInstallFolder: URL {
        let custom = settings.value.store.installFolder
        let path = custom.isEmpty ? (settings.value.libraryFolders.first ?? "~/Documents/Switch/apps") : custom
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    private func storeInstalled(_ game: StoreGame, at url: URL) {
        let folder = url.deletingLastPathComponent().path
        if !settings.value.libraryFolders.contains(folder) {
            settings.value.libraryFolders.append(folder)
        }
        sound.play(.select)
        if settings.value.notifyDownloads {
            showToast(storage.hasSaveData(titleID: game.titleID)
                  ? "\(game.title) is ready to play. Your save data is back."
                  : "\(game.title) is ready to play.", symbol: "checkmark.circle.fill")
        }
        Task { await reloadLibrary() }
    }

    /// Asks for the store username and password together. Returns `false` when cancelled.
    @discardableResult
    func promptStoreSignIn() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Sign in to the Game Store"
        alert.informativeText = "Enter your store username and password."
        let user = NSTextField(frame: NSRect(x: 0, y: 30, width: 300, height: 24))
        user.placeholderString = "Username"
        user.stringValue = settings.value.store.username
        let password = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        password.placeholderString = "Password"
        let fields = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 54))
        fields.addSubview(user)
        fields.addSubview(password)
        alert.accessoryView = fields
        alert.addButton(withTitle: "Sign In")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = user.stringValue.isEmpty ? user : password
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        settings.value.store.username = user.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.value.store.password = password.stringValue
        return true
    }

    /// Asks for one line of text (or a secret) in a small sheet. `nil` when cancelled.
    func promptText(_ title: String, message: String, value: String = "", secure: Bool = false) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = secure ? NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
                           : NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = value
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func confirmClose(_ game: Game) {
        guard launcher.runningGameID == game.id else { return }
        confirm(
            message: "Close the software?",
            detail: "Any unsaved progress in \(game.title) will be lost.",
            confirmTitle: "Close"
        ) { [weak self] in
            Task { await self?.launcher.close() }
        }
    }

    private func sessionEnded(_ id: String, seconds: TimeInterval) {
        history.addPlaytime(id, seconds: seconds)
        launchingGame = nil
        stack.removeAll()
        home.selectFirstSoftware()
        if settings.value.homeButtonReturnsToLauncher {
            bringToFront()
        }
    }

    // MARK: Auto-Sleep

    /// Sleep Mode after the chosen minutes without input on the HOME Menu (never during play).
    private func startAutoSleep() {
        Task {
            while true {
                try? await Task.sleep(for: .seconds(30))
                let minutes = settings.value.autoSleepMinutes
                guard minutes > 0, launcher.session == nil, dialog == nil,
                      Date().timeIntervalSince(lastInput) >= TimeInterval(minutes * 60) else { continue }
                if case .sleep? = stack.last { continue }
                lastInput = Date()
                openDock(.sleep)
            }
        }
    }

    // MARK: Updates

    private func announceUpdate(_ release: AppRelease) {
        guard settings.value.notifyUpdates else { return }
        // Wait for the startup animation, so the message isn't missed.
        Task {
            while isBooting { try? await Task.sleep(for: .milliseconds(500)) }
            try? await Task.sleep(for: .seconds(1))
            showToast("Switch Launcher \(release.version) is available. See System Settings › System.",
                      symbol: "arrow.down.circle.fill")
        }
    }

    /// Software Update: offers the new version's download, or checks again.
    func openSoftwareUpdate() {
        guard let release = updates.availableRelease else {
            Task {
                await updates.check()
                switch updates.state {
                case .upToDate: showToast("Switch Launcher is up to date.", symbol: "checkmark.circle.fill")
                case .failed(let message): showToast(message, symbol: "exclamationmark.triangle.fill")
                default: break
                }
            }
            return
        }
        sound.play(.select)
        let current = updates.currentVersion ?? "this version"
        dialog = DialogModel(
            app: self,
            message: "Switch Launcher \(release.version) is available",
            detail: "You have \(current). The download opens in your browser; unzip it and replace Switch Launcher in Applications.",
            buttons: ["Later", "What's New", "Download"],
            destructiveIndex: nil
        ) { index in
            switch index {
            case 1: NSWorkspace.shared.open(release.pageURL)
            case 2: NSWorkspace.shared.open(release.downloadURL ?? release.pageURL)
            default: break
            }
        }
    }

    // MARK: Overlays

    public func confirm(message: String, detail: String?, confirmTitle: String, action: @escaping () -> Void) {
        sound.play(.select)
        dialog = DialogModel(
            app: self,
            message: message,
            detail: detail,
            buttons: ["Cancel", confirmTitle],
            destructiveIndex: 1
        ) { index in
            if index == 1 { action() }
        }
    }

    func dismissDialog() {
        dialog = nil
    }

    /// Quick Settings: the console's hold-HOME panel.
    public func toggleQuickSettings() {
        if quickSettings == nil {
            sound.play(.panel)
            quickSettings = QuickSettingsModel(app: self)
        } else {
            sound.play(.back)
            quickSettings = nil
        }
    }

    /// Capture button: saves the launcher window to ~/Pictures/Screenshots (shown in Album).
    public func captureScreenshot() {
        guard let data = windowPNG() else { return }
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Screenshots")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = folder.appendingPathComponent("Switch Launcher \(formatter.string(from: Date())).png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url)
            sound.play(.capture)
            showToast("Screenshot saved to Album.", symbol: "camera.fill")
        } catch {
            sound.play(.error)
            showToast("Couldn't save the screenshot.", symbol: "exclamationmark.triangle.fill")
        }
    }

    /// The launcher window as PNG data, drawn from its views (works when the window isn't in front).
    private func windowPNG() -> Data? {
        guard let view = NSApp.windows.first(where: { $0.canBecomeMain })?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// `-captureTo <file.png>`: saves the window a few seconds after launch, then quits. Used with
    /// `-openScreen` to check screens without bringing the launcher to the front.
    private func captureFromLaunchArgument() {
        guard let path = UserDefaults.standard.string(forKey: "captureTo") else { return }
        let delay = UserDefaults.standard.double(forKey: "captureDelay")
        Task {
            try? await Task.sleep(for: .seconds(delay > 0 ? delay : 4))
            if let data = windowPNG() { try? data.write(to: URL(fileURLWithPath: path)) }
            NSApp.terminate(nil)
        }
    }

    public func showToast(_ text: String, symbol: String = "info.circle.fill") {
        let message = ToastMessage(text: text, symbol: symbol)
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            if toast == message { toast = nil }
        }
    }

    // MARK: Window

    public func toggleFullScreen() {
        NSApp.windows.first { $0.canBecomeMain }?.toggleFullScreen(nil)
    }
}
