import AppKit
import Combine
import DesignSystem
import InputKit
import LauncherCore
import SwiftUI

struct HomeView: View {
    let app: AppModel
    let home: HomeModel

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    private let tileSize: CGFloat = 256
    private let tileSpacing: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
            StatusBar(
                time: app.status.now,
                network: networkGlyph,
                batteryLevel: app.status.battery?.level,
                isCharging: app.status.battery?.isCharging ?? false
            ) {
                UserAvatar(
                    symbol: app.settings.value.avatarSymbol,
                    color: AvatarPalette.color(at: app.settings.value.avatarColorIndex),
                    diameter: ui(54),
                    isSelected: home.row == .user
                )
                .onTapGesture { home.tapUser() }
            }
            .frame(height: ui(96))
            .padding(.top, ui(6))

            softwareRow
                .frame(height: ui(340))

            Spacer(minLength: 0)

            dock
                .padding(.bottom, ui(26))

            ConsoleFooter(hints: home.hints) { controllerIndicator }
        }
        .background(theme.background)
    }

    // MARK: Software row

    private var softwareRow: some View {
        let items = home.items
        let focused = home.row == .software
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .bottom, spacing: ui(tileSpacing)) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        tileColumn(item, index: index, count: items.count, isSelected: focused && index == home.softwareIndex)
                            .scrollAnchor(index, horizontal: ui(Self.scrollMargin))
                    }
                }
                .padding(.horizontal, ui(Self.edgeInset))
                .padding(.vertical, ui(18))
            }
            .scrollIndicators(.never)
            .onChange(of: home.softwareIndex) { _, index in
                // The anchor reaches `scrollMargin` past the tile, so the smallest scroll that
                // shows it keeps that much room to the edge (and the row's padding at the ends).
                rowFollower.scroll(proxy, to: index, duration: 0.2)
            }
            // Coming back to the HOME Menu (from a page, a game, a resize or another app) keeps the
            // selected tile in a predictable place instead of wherever the row was left.
            .onAppear { recentre(proxy, animated: false) }
            .onChange(of: app.stack.isEmpty) { _, isEmpty in
                if isEmpty { recentre(proxy, animated: false) }
            }
            .onChange(of: items.map(\.id)) { _, _ in recentre(proxy) }
            .onChange(of: ui.factor) { _, _ in recentre(proxy, animated: false) }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                // A controller press can make the launcher active; moving the row then would undo
                // the move the press just made.
                guard Date().timeIntervalSince(app.lastInput) > 1 else { return }
                recentre(proxy, animated: false)
            }
        }
        .overlay {
            if app.library.games.isEmpty {
                emptyLibraryHint.offset(x: ui(90), y: ui(24))
            }
        }
    }

    /// Space before the first and after the last tile.
    private static let edgeInset: CGFloat = 60
    /// While moving, the selected tile stays this far from the edges so the next one peeks in.
    private static let scrollMargin: CGFloat = 130

    @State private var rowFollower = ScrollFollower()

    private func recentre(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let index = home.softwareIndex
        rowFollower.cancel()
        DispatchQueue.main.async {
            let move = {
                if index <= 2 {
                    proxy.scrollTo(0, anchor: .leading)
                } else {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
            if animated {
                withAnimation(.easeOut(duration: 0.2), move)
            } else {
                move()
            }
        }
    }

    private func tileColumn(_ item: HomeItem, index: Int, count: Int, isSelected: Bool) -> some View {
        VStack(spacing: ui(14)) {
            title(isRunning(item) ? "\(item.title)  ·  Playing" : item.title, index: index, count: count)
                .frame(width: ui(tileSize))
                .opacity(isSelected ? 1 : 0)

            Group {
                switch item {
                case .game(let game):
                    GameTile(
                        image: IconCache.shared.icon(for: game),
                        title: game.title,
                        size: ui(tileSize),
                        isSelected: isSelected,
                        badgeSymbol: app.launcher.runningGameID == game.id ? "play.fill" : nil,
                        isLoading: IconCache.shared.isLoading(game)
                    )
                    .equatable()
                case .allSoftware:
                    SymbolTile(
                        symbol: "square.grid.3x3.fill",
                        title: "All Software",
                        size: ui(tileSize),
                        isSelected: isSelected
                    )
                }
            }
            .onTapGesture { home.tapSoftware(index) }
        }
    }

    private func isRunning(_ item: HomeItem) -> Bool {
        if case .game(let game) = item { return app.launcher.runningGameID == game.id }
        return false
    }

    /// The selected software's name, centred over its tile. On the first and last tiles a title
    /// too long to stay on screen is lined up with the tile's outer edge instead.
    private func title(_ text: String, index: Int, count: Int) -> some View {
        let isFirst = index == 0
        let isLast = index == count - 1
        let reach = ui(Self.edgeInset - 14)
        let room = isFirst || isLast ? ui(tileSize) + 2 * reach : ui(tileSize) * 3
        let label = Text(text)
            .font(ui.font(22, .medium))
            .foregroundStyle(theme.accent)
            .lineLimit(1)
            .fixedSize()
        return ViewThatFits(in: .horizontal) {
            label
            label
                .padding(isFirst ? .leading : .trailing, reach)
                .frame(width: room, alignment: isFirst ? .leading : .trailing)
        }
        .frame(width: room)
    }

    private var emptyLibraryHint: some View {
        let scanning = app.library.isScanning
        return VStack(alignment: .leading, spacing: ui(6)) {
            Text(scanning ? "Looking for software…" : "No software found")
                .font(ui.font(22, .medium))
                .foregroundStyle(theme.textPrimary)
            Text(scanning
                 ? "If macOS asks for access to your Documents folder, choose Allow."
                 : "Add folders with native ports in System Settings › Library.")
                .font(ui.font(16))
                .foregroundStyle(theme.textSecondary)
        }
    }


    // MARK: Dock

    /// The shortcut icons sit together on one rounded bar, as on the Switch 2. The selected
    /// shortcut's name floats above the bar.
    private var dock: some View {
        HStack(spacing: ui(18)) {
            ForEach(Array(DockItem.allCases.enumerated()), id: \.element.id) { index, item in
                let isSelected = home.row == .dock && home.dockIndex == index
                CircleIconButton(symbol: item.symbol, tint: item.tint, diameter: ui(66), isSelected: isSelected)
                    .overlay(alignment: .top) {
                        Text(item.title)
                            .font(ui.font(17, .medium))
                            .foregroundStyle(theme.accent)
                            .fixedSize()
                            .offset(y: -ui(48))
                            .opacity(isSelected ? 1 : 0)
                    }
                    .onTapGesture { home.tapDock(index) }
            }
        }
        .padding(.horizontal, ui(22))
        .padding(.vertical, ui(14))
        .background(
            Capsule(style: .continuous)
                .fill(theme.dockBar)
                .shadow(color: theme.shadow.opacity(0.5), radius: ui(2), y: ui(1))
        )
        .padding(.top, ui(44))
    }

    // MARK: Footer

    private var controllerIndicator: some View {
        HStack(spacing: ui(14)) {
            Image(systemName: "keyboard")
            ForEach(app.input.controllers) { _ in
                Image(systemName: "gamecontroller.fill")
            }
        }
        .font(.system(size: ui(20)))
        .foregroundStyle(theme.textSecondary)
    }

    private var networkGlyph: NetworkGlyph {
        switch app.status.network {
        case .wifi: .wifi
        case .wired: .wired
        case .offline: .offline
        }
    }
}
