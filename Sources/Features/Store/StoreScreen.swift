import AppKit
import DesignSystem
import InputKit
import LauncherCore
import Observation
import SwiftUI

/// Game Store: browse the games on your own S3 bucket, download and install them.
@MainActor @Observable
public final class StoreModel: InputResponder {
    static let columns = 5

    enum Status: Equatable {
        case available
        case installed
        case update
        case working(StoreService.Phase)
        case failed(String)
    }

    var index = 0
    /// Presigned icon URLs, made once per catalog so `AsyncImage` doesn't reload on every redraw.
    private(set) var iconURLs: [String: URL] = [:]
    @ObservationIgnored unowned let app: AppModel

    init(app: AppModel) {
        self.app = app
        Task { await reload() }
    }

    var store: StoreService { app.store }
    var games: [StoreGame] { store.catalog.games }

    var selected: StoreGame? {
        games.indices.contains(index) ? games[index] : nil
    }

    func reload() async {
        app.applyStoreConfig()
        await store.refresh()
        var urls: [String: URL] = [:]
        for game in games {
            if let key = game.icon, let url = store.url(for: key, expires: 24 * 3600) { urls[game.id] = url }
        }
        iconURLs = urls
        index = min(index, max(games.count - 1, 0))
    }

    func status(of game: StoreGame) -> Status {
        if let phase = store.jobs[game.id] {
            switch phase {
            case .failed(let message): return .failed(message)
            case .installed: break
            default: return .working(phase)
            }
        }
        guard let installed = app.library.game(id: game.id) else { return .available }
        if let latest = game.version, let current = installed.version,
           current.compare(latest, options: .numeric) == .orderedAscending {
            return .update
        }
        return .installed
    }

    public func handle(_ button: NintendoButton) {
        let count = games.count
        switch button {
        case .left: move(to: index - 1, count: count)
        case .right: move(to: index + 1, count: count)
        case .up: move(to: index - Self.columns, count: count)
        case .down: move(to: min(index + Self.columns, count - 1), count: count)
        case .a:
            if let selected { act(on: selected) } else if store.state == .notConfigured { signIn() }
        case .x:
            if let selected, case .working = status(of: selected) { confirmCancel(selected) }
        case .y:
            app.sound.play(.toggle)
            Task { await reload() }
        case .plus:
            openWebsite()
        case .b:
            app.pop()
        default:
            break
        }
    }

    private func move(to newIndex: Int, count: Int) {
        guard newIndex >= 0, newIndex < count, newIndex != index else { return }
        index = newIndex
        app.sound.play(.move)
    }

    func tap(_ tapped: Int) {
        if tapped == index {
            handle(.a)
        } else {
            index = tapped
            app.sound.play(.move)
        }
    }

    private func act(on game: StoreGame) {
        switch status(of: game) {
        case .working:
            confirmCancel(game)
        case .installed:
            if let installed = app.library.game(id: game.id) { app.launch(installed) }
        case .failed:
            store.clearFailure(game.id)
            confirmDownload(game, update: false)
        case .available:
            confirmDownload(game, update: false)
        case .update:
            confirmDownload(game, update: true)
        }
    }

    private func confirmDownload(_ game: StoreGame, update: Bool) {
        let folder = app.storeInstallFolder
        let needed = game.archiveSize + (game.installedSize ?? game.archiveSize)
        if let free = Self.freeSpace(at: folder), free < needed {
            app.sound.play(.error)
            app.showToast("Not enough space: \(ByteFormatter.string(needed)) needed, \(ByteFormatter.string(free)) free.",
                          symbol: "externaldrive.badge.exclamationmark")
            return
        }
        let size = ByteFormatter.string(game.archiveSize)
        app.confirm(
            message: update ? "Update \(game.title)?" : "Download \(game.title)?",
            detail: "\(size) download · installs to \(folder.path)",
            confirmTitle: update ? "Update" : "Download"
        ) { [weak self] in
            guard let self else { return }
            store.download(game, into: folder)
        }
    }

    private func confirmCancel(_ game: StoreGame) {
        app.confirm(message: "Stop downloading \(game.title)?", detail: nil, confirmTitle: "Stop") { [weak self] in
            self?.store.cancel(game.id)
        }
    }

    func retry() {
        Task { await reload() }
    }

    /// Asks for the server address if there is none, then username and password.
    func signIn() {
        if app.settings.value.store.endpoints.isEmpty {
            guard let address = app.promptText(
                "Store Address",
                message: "Address of your S3 server on the home network, e.g. http://192.168.1.10:30900.",
                value: app.settings.value.store.localEndpoint
            ), !address.isEmpty else { return }
            app.settings.value.store.localEndpoint = address
        }
        guard app.promptStoreSignIn() else { return }
        Task { await reload() }
    }

    func openSettings() {
        app.push(.menu(app.makeSettingsMenu(startingAt: "store")))
    }

    func openWebsite() {
        guard let url = URL(string: "https://www.nintendo.com/us/store/") else { return }
        app.push(.web(WebModel(app: app, title: "Nintendo eShop", symbol: "bag.fill", url: url)))
    }

    static func freeSpace(at folder: URL) -> Int64? {
        let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}

struct StoreScreen: View {
    let model: StoreModel

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    private let tile: CGFloat = 196

    var body: some View {
        ConsoleScaffold(title: "Game Store", icon: .symbol("bag.fill"), trailing: trailing, hints: hints) {
            switch model.store.state {
            case .notConfigured:
                message(
                    symbol: "server.rack",
                    title: "Sign in to your game server",
                    detail: "Enter your store's address, username and password. You can change them later in System Settings › Store.",
                    action: ("Sign In", model.signIn)
                )
            case .loading where model.games.isEmpty:
                ProgressView().controlSize(.large)
            case .failed(let error) where model.games.isEmpty:
                message(
                    symbol: "exclamationmark.icloud",
                    title: "Couldn't reach the store",
                    detail: error,
                    action: error.contains("password") ? ("Sign In Again", model.signIn) : ("Try Again", model.retry)
                )
            default:
                if model.games.isEmpty {
                    message(symbol: "tray", title: "No games yet",
                            detail: "Publish games with scripts/store-publish.sh.", action: nil)
                } else {
                    grid
                }
            }
        } footerLeading: {
            if let game = model.selected {
                Text(footer(for: game))
                    .font(ui.font(16))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private var trailing: String? {
        guard model.store.state == .ready else { return nil }
        let endpoint = model.store.activeEndpoint?.host() ?? ""
        let place = endpoint.hasPrefix("192.168.") || endpoint.hasSuffix(".local") ? "Home network" : endpoint
        let count = model.games.count
        return "\(count) \(count == 1 ? "game" : "games") · \(place)"
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(ui(tile)), spacing: ui(28)), count: StoreModel.columns),
                    spacing: ui(30)
                ) {
                    ForEach(Array(model.games.enumerated()), id: \.element.id) { index, game in
                        StoreTile(
                            game: game,
                            iconURL: model.iconURLs[game.id],
                            status: model.status(of: game),
                            size: ui(tile),
                            isSelected: index == model.index
                        )
                        .id(index)
                        .onTapGesture { model.tap(index) }
                    }
                }
                .padding(.vertical, ui(30))
            }
            .scrollIndicators(.never)
            .onChange(of: model.index) { _, index in
                withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(index) }
            }
        }
    }

    private func message(symbol: String, title: String, detail: String, action: (String, () -> Void)?) -> some View {
        VStack(spacing: ui(14)) {
            Image(systemName: symbol)
                .font(.system(size: ui(54), weight: .semibold))
                .foregroundStyle(theme.accent)
            Text(title)
                .font(ui.font(24, .medium))
                .foregroundStyle(theme.textPrimary)
            Text(detail)
                .font(ui.font(17))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: ui(620))
            if let action {
                Button(action: action.1) {
                    Text(action.0)
                        .font(ui.font(18, .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, ui(26))
                        .padding(.vertical, ui(12))
                        .background(Capsule().fill(theme.accent))
                }
                .buttonStyle(.plain)
                .padding(.top, ui(6))
            }
        }
    }

    private func footer(for game: StoreGame) -> String {
        var parts = [game.title]
        if let version = game.version { parts.append("v\(version)") }
        parts.append("\(ByteFormatter.string(game.archiveSize)) download")
        switch model.status(of: game) {
        case .installed: parts.append("Installed")
        case .update: parts.append("Update available")
        case .failed(let message): parts.append(message)
        default: break
        }
        return parts.joined(separator: " · ")
    }

    private var hints: [ButtonHint] {
        let app = model.app
        var hints = [
            ButtonHint("Y", "Refresh") { app.handle(.y) },
            ButtonHint("+", "eShop Website") { app.handle(.plus) },
            ButtonHint("B", "Back") { app.handle(.b) },
        ]
        if let game = model.selected {
            let verb: String = switch model.status(of: game) {
            case .installed: "Start"
            case .update: "Update"
            case .working: "Stop"
            default: "Download"
            }
            hints.append(ButtonHint("A", verb) { app.handle(.a) })
        }
        return hints
    }
}

/// Cover, title and download state of one store game.
struct StoreTile: View {
    let game: StoreGame
    let iconURL: URL?
    let status: StoreModel.Status
    let size: CGFloat
    let isSelected: Bool

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    var body: some View {
        let radius = size * 0.07
        VStack(spacing: ui(10)) {
            ZStack(alignment: .bottom) {
                AsyncImage(url: iconURL) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            theme.surfaceRaised
                            Text(game.title)
                                .font(.system(size: size * 0.08, weight: .bold, design: .rounded))
                                .foregroundStyle(theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(size * 0.08)
                        }
                    }
                }
                .frame(width: size, height: size)

                overlay
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(alignment: .topTrailing) { badge.padding(size * 0.04) }
            .shadow(color: theme.shadow, radius: isSelected ? ui(10) : ui(4), y: isSelected ? ui(4) : ui(2))
            .selectionFrame(isSelected, cornerRadius: radius)

            Text(game.title)
                .font(ui.font(15, isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? theme.accent : theme.textPrimary)
                .lineLimit(1)
                .frame(width: size)
            Text(subtitle)
                .font(ui.font(13))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .frame(width: size)
        }
    }

    @ViewBuilder private var overlay: some View {
        if case .working(let phase) = status {
            VStack(spacing: ui(6)) {
                Text(phaseText(phase))
                    .font(ui.font(14, .semibold))
                    .foregroundStyle(.white)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.3))
                        Capsule().fill(.white).frame(width: geo.size.width * fraction(phase))
                    }
                }
                .frame(height: ui(6))
            }
            .padding(ui(12))
            .frame(maxWidth: .infinity)
            .background(.black.opacity(0.55))
            .animation(.easeOut(duration: 0.25), value: fraction(phase))
        }
    }

    @ViewBuilder private var badge: some View {
        switch status {
        case .installed: symbol("checkmark", theme.accent)
        case .update: symbol("arrow.down", Color(hex: 0xF29B00))
        case .failed: symbol("exclamationmark", theme.destructive)
        default: EmptyView()
        }
    }

    private func symbol(_ name: String, _ color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.06, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size * 0.14, height: size * 0.14)
            .background(Circle().fill(color))
            .overlay(Circle().strokeBorder(.white, lineWidth: max(1.5, size * 0.008)))
    }

    private var subtitle: String {
        switch status {
        case .installed: "Installed"
        case .update: "Update · \(ByteFormatter.string(game.archiveSize))"
        case .failed: "Failed · press A to retry"
        case .working(let phase): phaseText(phase)
        case .available: ByteFormatter.string(game.archiveSize)
        }
    }

    private func fraction(_ phase: StoreService.Phase) -> CGFloat {
        switch phase {
        case .downloading(let received, let total): total > 0 ? CGFloat(Double(received) / Double(total)) : 0
        case .verifying, .installing, .installed: 1
        case .failed: 0
        }
    }

    private func phaseText(_ phase: StoreService.Phase) -> String {
        switch phase {
        case .downloading(let received, let total):
            total > 0 ? "\(Int(Double(received) / Double(total) * 100))% · \(ByteFormatter.string(received))" : "Downloading…"
        case .verifying: "Checking…"
        case .installing: "Installing…"
        case .installed: "Installed"
        case .failed: "Failed"
        }
    }
}
