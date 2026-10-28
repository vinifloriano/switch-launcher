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

    public init() {
        home = HomeModel(app: self)
        isBooting = settings.value.showBootAnimation
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

        launcher.onSessionEnded = { [weak self] id, seconds in self?.sessionEnded(id, seconds: seconds) }
        store.onInstalled = { [weak self] game, url in self?.storeInstalled(game, at: url) }
        Task {
            await reloadLibrary()
            openScreenFromLaunchArgument()
        }
    }

    /// `-launchGame <title>` starts a game at launch.
    /// `-openScreen settings|library|album|user|controllers|cards|options|dialog|web|tester|grip|quick|capture|last|middle` opens a page at launch
    /// (handy for screenshots and UI checks).
    private func openScreenFromLaunchArgument() {
        if let title = UserDefaults.standard.string(forKey: "launchGame"),
           let game = library.games.first(where: { $0.title.localizedCaseInsensitiveContains(title) }) {
            isBooting = false
            launch(game)
        }
        guard let screen = UserDefaults.standard.string(forKey: "openScreen") else { return }
        isBooting = false
        switch screen {
        case "settings": openDock(.settings)
        case "library": openLibrary()
        case "album": openDock(.album)
        case "user": openUserPage()
        case "controllers": openDock(.controllers)
        case "cards": openDock(.virtualGameCard)
        case "options": library.games.first.map(openOptions)
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
        if isBooting {
            isBooting = false
            return
        }
        if button == .home {
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
        bringToFront()
        dialog = nil
        stack.removeAll()
        sound.play(.home)
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
        if launcher.runningGameID != game.id {
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
        showToast("\(game.title) is ready to play.", symbol: "checkmark.circle.fill")
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
        guard let view = NSApp.windows.first(where: { $0.canBecomeMain })?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
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
