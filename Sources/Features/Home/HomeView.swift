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
        return ScrollView(.horizontal) {
            HStack(alignment: .bottom, spacing: ui(tileSpacing)) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    tileColumn(item, index: index, count: items.count, isSelected: focused && index == home.softwareIndex)
                }
            }
            .padding(.horizontal, ui(Self.edgeInset))
            .padding(.vertical, ui(18))
        }
        .scrollIndicators(.never)
        .scrollPosition($rowPosition)
        .onScrollGeometryChange(for: RowGeometry.self) { geo in
            RowGeometry(offset: geo.contentOffset.x, viewport: geo.containerSize.width, content: geo.contentSize.width)
        } action: { _, new in
            rowGeometry = new
        }
        .onChange(of: home.softwareIndex) { _, index in reveal(index) }
        // Coming back to the HOME Menu (from a page, a game, a resize or another app) keeps the
        // selected tile in a predictable place instead of wherever the row was left.
        .onAppear { recentre(animated: false) }
        .onChange(of: app.stack.isEmpty) { _, isEmpty in
            if isEmpty { recentre(animated: false) }
        }
        .onChange(of: items.map(\.id)) { _, _ in recentre() }
        .onChange(of: ui.factor) { _, _ in recentre(animated: false) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            recentre(animated: false)
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

    private struct RowGeometry: Equatable {
        var offset: CGFloat = 0
        var viewport: CGFloat = 0
        var content: CGFloat = 0
    }

    @State private var rowPosition = ScrollPosition(edge: .leading)
    @State private var rowGeometry = RowGeometry()

    private func tileFrame(_ index: Int) -> ClosedRange<CGFloat> {
        let x = ui(Self.edgeInset) + CGFloat(index) * ui(tileSize + tileSpacing)
        return x...(x + ui(tileSize))
    }

    private func clampedOffset(_ x: CGFloat) -> CGFloat {
        min(max(0, x), max(0, rowGeometry.content - rowGeometry.viewport))
    }

    private func scroll(to x: CGFloat, animated: Bool) {
        let target = clampedOffset(x)
        guard abs(target - rowGeometry.offset) > 0.5 else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { rowPosition.scrollTo(x: target) }
        } else {
            rowPosition.scrollTo(x: target)
        }
    }

    /// Scrolls only when the selected tile would get closer than `scrollMargin` to an edge.
    private func reveal(_ index: Int) {
        guard rowGeometry.viewport > 0 else { return }
        let frame = tileFrame(index)
        let margin = ui(Self.scrollMargin)
        let visible = rowGeometry.offset...(rowGeometry.offset + rowGeometry.viewport)
        if frame.lowerBound - margin < visible.lowerBound {
            scroll(to: frame.lowerBound - margin, animated: true)
        } else if frame.upperBound + margin > visible.upperBound {
            scroll(to: frame.upperBound + margin - rowGeometry.viewport, animated: true)
        }
    }

    private func recentre(animated: Bool = true) {
        let index = home.softwareIndex
        DispatchQueue.main.async {
            guard rowGeometry.viewport > 0 else { return }
            if index <= 2 {
                scroll(to: 0, animated: animated)
            } else {
                let frame = tileFrame(index)
                scroll(to: (frame.lowerBound + frame.upperBound - rowGeometry.viewport) / 2, animated: animated)
            }
        }
    }

    private func tileColumn(_ item: HomeItem, index: Int, count: Int, isSelected: Bool) -> some View {
        VStack(spacing: ui(14)) {
            title(item.title, index: index, count: count)
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

    private var dock: some View {
        HStack(spacing: ui(20)) {
            ForEach(Array(DockItem.allCases.enumerated()), id: \.element.id) { index, item in
                let isSelected = home.row == .dock && home.dockIndex == index
                VStack(spacing: ui(12)) {
                    Text(item.title)
                        .font(ui.font(17, .medium))
                        .foregroundStyle(theme.accent)
                        .fixedSize()
                        .frame(width: ui(70))
                        .opacity(isSelected ? 1 : 0)
                    CircleIconButton(symbol: item.symbol, tint: item.tint, diameter: ui(70), isSelected: isSelected)
                        .onTapGesture { home.tapDock(index) }
                }
            }
        }
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
