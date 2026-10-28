import AppKit
import Observation

/// Starts games, tracks the one that is running (the console only runs one at a time) and
/// reports how long it ran when it quits.
///
/// A native port's executable (`nxnative`) has no window: it spawns `dmhost`, which opens the
/// game window, and waits for it. macOS won't let `dmhost` take focus on its own, so the launcher
/// keeps focus while the game starts and then hands it to the game window.
@MainActor @Observable
public final class GameLauncher {
    public struct Session: Equatable, Sendable {
        public let gameID: String
        /// The process LaunchServices started (lives as long as the game).
        public let pid: pid_t
        public let started: Date
        /// The process that owns the game window, once found (may equal `pid`).
        public var windowPID: pid_t?
    }

    public private(set) var session: Session?
    @ObservationIgnored public var onSessionEnded: ((_ gameID: String, _ seconds: TimeInterval) -> Void)?
    /// Take focus back for the game when a background app grabs it (see `guardFocus`).
    @ObservationIgnored public var keepGameInFront = true
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var games: [String: Game] = [:]
    @ObservationIgnored private var focusWatchdog: Task<Void, Never>?

    public init() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { self?.applicationTerminated(pid: pid) }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { self?.guardFocus(activatedPID: pid) }
        })
    }

    public var runningGameID: String? { session?.gameID }

    /// Picks up a game that was already running when the launcher started.
    public func adoptRunning(from games: [Game]) {
        guard session == nil else { return }
        for app in NSWorkspace.shared.runningApplications {
            if let game = games.first(where: { matches($0, app) }) {
                self.games[game.id] = game
                session = Session(gameID: game.id, pid: app.processIdentifier, started: Date())
                session?.windowPID = windowApp(for: game, launcherPID: app.processIdentifier)?.processIdentifier
                return
            }
        }
    }

    /// Returns `true` when a new process was started, `false` when an existing one was resumed.
    /// `environment` is added to the game's environment (e.g. `DM_FULLSCREEN`).
    @discardableResult
    public func launch(_ game: Game, environment: [String: String] = [:]) async throws -> Bool {
        if session?.gameID == game.id {
            resume()
            return false
        }
        let configuration = NSWorkspace.OpenConfiguration()
        // Stay active ourselves: only the active app can hand focus to the game window.
        configuration.activates = false
        // LaunchServices adds these to the app's normal environment (HOME, PATH... are kept).
        if !environment.isEmpty {
            configuration.environment = environment
        }
        Log.launcher.info("Starting \(game.title, privacy: .public)")
        let app = try await NSWorkspace.shared.openApplication(at: game.url, configuration: configuration)
        games[game.id] = game
        session = Session(gameID: game.id, pid: app.processIdentifier, started: Date())
        Task { await focusWhenReady(game, launcherPID: app.processIdentifier) }
        return true
    }

    /// Brings the running game to the front.
    @discardableResult
    public func resume() -> Bool {
        guard let app = gameWindowApp else { return false }
        return focus(app)
    }

    /// Asks the running game to quit and waits for it (force-quits after `timeout`).
    public func close(timeout: TimeInterval = 6) async {
        guard let current = session else { return }
        let window = gameWindowApp
        let main = NSRunningApplication(processIdentifier: current.pid)
        guard window != nil || main != nil else {
            session = nil
            return
        }
        // Quitting the window process lets nxnative's wait return, which ends the session.
        window?.terminate()
        if window?.processIdentifier != main?.processIdentifier { main?.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        while session != nil, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(150))
        }
        if session != nil {
            window?.forceTerminate()
            main?.forceTerminate()
        }
    }

    // MARK: Focus

    /// Waits for the game window process to show up, then gives it focus. Stops once the game is
    /// in front, after 30 s, or if the game ends.
    private func focusWhenReady(_ game: Game, launcherPID: pid_t) async {
        for _ in 0..<60 {
            guard session?.pid == launcherPID else { return }
            if let app = windowApp(for: game, launcherPID: launcherPID) {
                session?.windowPID = app.processIdentifier
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                    startFocusWatchdog()
                    return
                }
                focus(app)
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    /// Some apps activate themselves from the background without showing a window, which leaves
    /// the game on screen but deaf to the keyboard. While a game runs, whenever focus is elsewhere
    /// but the game window is still the topmost one, give focus back. Switching apps on purpose
    /// (⌘Tab, Dock, clicking a window) raises that app's window, so it's left alone.
    private func guardFocus(activatedPID: pid_t?) {
        guard keepGameInFront, session?.windowPID != nil,
              activatedPID != ProcessInfo.processInfo.processIdentifier else { return }
        startFocusWatchdog()
    }

    private func startFocusWatchdog() {
        guard focusWatchdog == nil else { return }
        focusWatchdog = Task { [weak self] in
            var lostSince: Date?
            var lastHandoff = Date.distantPast
            while !Task.isCancelled {
                guard let self, let current = self.session, let windowPID = current.windowPID else { break }
                let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
                let stolen = self.keepGameInFront
                    && front != windowPID
                    && front != ProcessInfo.processInfo.processIdentifier
                    && Self.topWindowOwner() == windowPID
                if stolen, let game = NSRunningApplication(processIdentifier: windowPID) {
                    let since = lostSince ?? Date()
                    lostSince = since
                    if Date().timeIntervalSince(since) > 0.5, Date().timeIntervalSince(lastHandoff) > 1.5 {
                        // macOS keeps refusing: become active ourselves (always allowed through
                        // LaunchServices), then hand focus straight to the game.
                        lastHandoff = Date()
                        Log.focus.info("Focus taken by pid \(front ?? 0); handing back to the game")
                        await self.handOffThroughLauncher(to: game)
                    } else {
                        game.activate(options: [.activateAllWindows])
                    }
                } else {
                    lostSince = nil
                }
                try? await Task.sleep(for: .milliseconds(stolen ? 250 : 500))
            }
            self?.focusWatchdog = nil
        }
    }

    private func handOffThroughLauncher(to game: NSRunningApplication) async {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try? await NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
        focus(game)
    }

    /// Owner of the frontmost normal window on screen.
    private static func topWindowOwner() -> pid_t? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        let top = list?.first { ($0[kCGWindowLayer as String] as? Int) == 0 }
        return top?[kCGWindowOwnerPID as String] as? pid_t
    }

    @discardableResult
    private func focus(_ app: NSRunningApplication) -> Bool {
        app.unhide()
        NSApp.yieldActivation(to: app)
        if app.activate(from: .current, options: [.activateAllWindows]) { return true }
        return app.activate(options: [.activateAllWindows])
    }

    private var gameWindowApp: NSRunningApplication? {
        guard let current = session else { return nil }
        if let pid = current.windowPID, let app = NSRunningApplication(processIdentifier: pid) { return app }
        if let game = games[current.gameID], let app = windowApp(for: game, launcherPID: current.pid) { return app }
        return NSRunningApplication(processIdentifier: current.pid)
    }

    /// The GUI process for this game: a `dmhost` (or similar) running from inside the bundle,
    /// or the launched process itself when it opens the window directly.
    private func windowApp(for game: Game, launcherPID: pid_t) -> NSRunningApplication? {
        let bundlePath = game.url.standardizedFileURL.path + "/"
        let helpers = NSWorkspace.shared.runningApplications.filter { app in
            app.processIdentifier != launcherPID
                && app.processIdentifier != ProcessInfo.processInfo.processIdentifier
                && (app.executableURL?.standardizedFileURL.path.hasPrefix(bundlePath) ?? false)
        }
        if let helper = helpers.first(where: { $0.activationPolicy == .regular }) ?? helpers.first {
            return helper
        }
        guard let main = NSRunningApplication(processIdentifier: launcherPID),
              main.activationPolicy == .regular,
              Self.hasWindow(pid: launcherPID) else { return nil }
        return main
    }

    private static func hasWindow(pid: pid_t) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return list.contains { info in
            info[kCGWindowOwnerPID as String] as? pid_t == pid && info[kCGWindowLayer as String] as? Int == 0
        }
    }

    private func matches(_ game: Game, _ app: NSRunningApplication) -> Bool {
        if let url = app.bundleURL, url.standardizedFileURL == game.url.standardizedFileURL { return true }
        if let id = game.bundleIdentifier, id == app.bundleIdentifier { return true }
        return false
    }

    private func applicationTerminated(pid: pid_t?) {
        guard let current = session, current.pid == pid || current.windowPID == pid else { return }
        // The window process quitting means the game is over even if nxnative lingers.
        session = nil
        Log.launcher.info("Game ended after \(Int(Date().timeIntervalSince(current.started)))s")
        focusWatchdog?.cancel()
        focusWatchdog = nil
        onSessionEnded?(current.gameID, Date().timeIntervalSince(current.started))
    }
}
