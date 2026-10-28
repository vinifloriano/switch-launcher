import AppKit
import DesignSystem
import InputKit
import LauncherCore
import Observation
import SwiftUI

/// Quick Settings: the panel that slides in when HOME is held (⇧H on the keyboard).
@MainActor @Observable
public final class QuickSettingsModel: InputResponder {
    struct Item: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let accessory: ItemAccessory
        let perform: () -> Void
    }

    var index = 0
    @ObservationIgnored unowned let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    var items: [Item] {
        let s = app.settings.value
        let isDark = s.theme == .basicBlack
        let fullScreen = NSApp.windows.first { $0.canBecomeMain }?.styleMask.contains(.fullScreen) ?? false
        let volumeNames = ["Low", "Medium", "High"]
        let volumes = [0.35, 0.7, 1.0]
        let volumeIndex = volumes.indices.min { abs(volumes[$0] - s.soundVolume) < abs(volumes[$1] - s.soundVolume) } ?? 1
        return [
            Item(id: "sleep", title: "Sleep Mode", symbol: "power", accessory: .none) { [unowned self] in
                app.quickSettings = nil
                app.openDock(.sleep)
            },
            Item(id: "theme", title: "Dark Theme", symbol: "moon.fill", accessory: .toggle(isDark)) { [unowned self] in
                app.settings.value.theme = isDark ? .basicWhite : .basicBlack
            },
            Item(id: "sounds", title: "HOME Menu Sounds", symbol: "speaker.wave.2.fill", accessory: .toggle(s.soundsEnabled)) { [unowned self] in
                app.settings.value.soundsEnabled.toggle()
            },
            Item(id: "volume", title: "Sound Volume", symbol: "speaker.plus.fill", accessory: .choice(volumeNames[volumeIndex])) { [unowned self] in
                app.settings.value.soundVolume = volumes[(volumeIndex + 1) % volumes.count]
            },
            Item(id: "fullscreen", title: "Full Screen", symbol: "arrow.up.left.and.arrow.down.right", accessory: .toggle(fullScreen)) { [unowned self] in
                app.toggleFullScreen()
            },
            Item(id: "controllers", title: "Controllers", symbol: "gamecontroller.fill", accessory: .chevron) { [unowned self] in
                app.quickSettings = nil
                app.openDock(.controllers)
            },
            Item(id: "settings", title: "System Settings", symbol: "gearshape.fill", accessory: .chevron) { [unowned self] in
                app.quickSettings = nil
                app.openDock(.settings)
            },
        ]
    }

    public func handle(_ button: NintendoButton) {
        let count = items.count
        switch button {
        case .up where index > 0:
            index -= 1
            app.sound.play(.move)
        case .down where index < count - 1:
            index += 1
            app.sound.play(.move)
        case .a:
            activate(index)
        case .b:
            app.toggleQuickSettings()
        default:
            break
        }
    }

    func activate(_ tapped: Int) {
        index = tapped
        app.sound.play(.toggle)
        items[tapped].perform()
    }
}

struct QuickSettingsPanel: View {
    let model: QuickSettingsModel

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    var body: some View {
        let status = model.app.status
        HStack(spacing: 0) {
            Color.black.opacity(0.35)
                .contentShape(Rectangle())
                .onTapGesture { model.app.toggleQuickSettings() }
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: ui(4)) {
                    Text(status.now, format: .dateTime.hour().minute())
                        .font(ui.font(46, .medium))
                        .monospacedDigit()
                    Text(status.now, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(ui.font(17))
                        .foregroundStyle(theme.textSecondary)
                    if let battery = status.battery {
                        Label("\(battery.level)%" + (battery.isCharging ? " · Charging" : ""),
                              systemImage: battery.isCharging ? "battery.100percent.bolt" : "battery.75percent")
                            .font(ui.font(16))
                            .foregroundStyle(theme.textSecondary)
                            .padding(.top, ui(6))
                    }
                }
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, ui(30))
                .padding(.top, ui(34))
                .padding(.bottom, ui(18))

                Rectangle().fill(theme.divider).frame(height: 1)

                VStack(spacing: 0) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        ItemRow(
                            title: item.title,
                            symbol: item.symbol,
                            accessory: item.accessory,
                            isFocused: index == model.index
                        )
                        .onTapGesture { model.activate(index) }
                    }
                }
                .padding(.horizontal, ui(14))
                .padding(.top, ui(10))

                Spacer()
                HStack {
                    Spacer()
                    ButtonGuide([
                        ButtonHint("B", "Close") { model.app.toggleQuickSettings() },
                        ButtonHint("A", "OK") { model.handle(.a) },
                    ])
                }
                .padding(ui(24))
            }
            .frame(width: ui(440))
            .background(theme.background)
            .shadow(color: .black.opacity(0.3), radius: ui(20))
        }
    }
}

/// Launch animation: the cover art zooms in on black, like the console starting software.
struct LaunchOverlay: View {
    let game: Game

    @State private var grown = false
    @Environment(\.ui) private var ui

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GameTile(
                image: IconCache.shared.icon(for: game),
                title: game.title,
                size: ui(256),
                isSelected: false
            )
            .scaleEffect(grown ? 1.25 : 0.85)
            .opacity(grown ? 0 : 1)
        }
        .onAppear {
            withAnimation(.easeIn(duration: 1.2).delay(0.15)) { grown = true }
        }
    }
}
