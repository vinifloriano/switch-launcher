import AppKit
import DesignSystem
import InputKit
import Observation
import SwiftUI

/// Controllers page: four player slots and the console's controller actions.
@MainActor @Observable
public final class ControllersModel: InputResponder {
    enum Action: CaseIterable {
        case gripOrder, find, test, pair

        var title: String {
            switch self {
            case .gripOrder: "Change Grip/Order"
            case .find: "Find Controllers"
            case .test: "Test Input Devices"
            case .pair: "Pair New Controller"
            }
        }

        var symbol: String {
            switch self {
            case .gripOrder: "arrow.left.arrow.right"
            case .find: "dot.radiowaves.left.and.right"
            case .test: "gamecontroller.fill"
            case .pair: "plus.circle.fill"
            }
        }
    }

    var index = 0
    private(set) var snapshots: [GamepadSnapshot] = []
    @ObservationIgnored unowned let app: AppModel
    @ObservationIgnored private var timer: Timer?

    init(app: AppModel) {
        self.app = app
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                self.refresh()
            }
        }
    }

    private func refresh() {
        let latest = app.input.snapshots()
        if latest != snapshots { snapshots = latest }
    }

    func snapshot(for id: String) -> GamepadSnapshot? {
        snapshots.first { $0.id == id }
    }

    public func handle(_ button: NintendoButton) {
        let count = Action.allCases.count
        switch button {
        case .left where index > 0:
            index -= 1
            app.sound.play(.move)
        case .right where index < count - 1:
            index += 1
            app.sound.play(.move)
        case .a:
            perform(Action.allCases[index])
        case .b:
            app.pop()
        default:
            break
        }
    }

    func perform(_ action: Action) {
        switch action {
        case .gripOrder:
            app.openGripOrder()
        case .test:
            app.openControllerTest()
        case .find:
            if app.input.controllers.isEmpty {
                app.sound.play(.error)
                app.showToast("No controllers are connected.", symbol: "gamecontroller")
            } else {
                app.sound.play(.select)
                let count = app.input.rumble(duration: 1.2)
                app.showToast(
                    count == 0 ? "These controllers can't vibrate on Mac." : "Vibrating \(count) controller(s)…",
                    symbol: "dot.radiowaves.left.and.right"
                )
            }
        case .pair:
            app.sound.play(.select)
            app.input.startControllerDiscovery()
            if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
                NSWorkspace.shared.open(url)
            }
            app.showToast("Hold the sync button on your controller.", symbol: "dot.radiowaves.left.and.right")
        }
    }

    func tap(_ tapped: Int) {
        if tapped == index {
            perform(Action.allCases[tapped])
        } else {
            index = tapped
            app.sound.play(.move)
        }
    }
}

struct ControllersScreen: View {
    let model: ControllersModel

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    var body: some View {
        let controllers = model.app.input.controllers
        ConsoleScaffold(title: "Controllers", icon: .symbol("gamecontroller.fill"), hints: hints) {
            VStack(spacing: ui(44)) {
                HStack(spacing: ui(20)) {
                    ForEach(0..<4, id: \.self) { slot in
                        PlayerSlotCard(
                            slot: slot,
                            controller: controllers.indices.contains(slot) ? controllers[slot] : nil,
                            snapshot: controllers.indices.contains(slot) ? model.snapshot(for: controllers[slot].id) : nil
                        )
                    }
                }
                HStack(spacing: ui(22)) {
                    ForEach(Array(ControllersModel.Action.allCases.enumerated()), id: \.offset) { index, action in
                        VStack(spacing: ui(14)) {
                            Image(systemName: action.symbol)
                                .font(.system(size: ui(36), weight: .semibold))
                                .foregroundStyle(theme.accent)
                            Text(action.title)
                                .font(ui.font(17, .medium))
                                .foregroundStyle(theme.textPrimary)
                        }
                        .frame(width: ui(220), height: ui(140))
                        .background(RoundedRectangle(cornerRadius: ui(14), style: .continuous).fill(theme.surface))
                        .shadow(color: theme.shadow, radius: ui(3), y: ui(1))
                        .selectionFrame(index == model.index, cornerRadius: ui(14))
                        .onTapGesture { model.tap(index) }
                    }
                }
            }
            .padding(.top, ui(10))
        } footerLeading: {
            Text("\(controllers.count) connected · The keyboard always works")
                .font(ui.font(16))
                .foregroundStyle(theme.textSecondary)
        }
    }

    private var hints: [ButtonHint] {
        [
            ButtonHint("B", "Back") { model.app.handle(.b) },
            ButtonHint("A", "OK") { model.app.handle(.a) },
        ]
    }
}

/// One player slot: controller name, battery and player light, or an empty outline.
struct PlayerSlotCard: View {
    let slot: Int
    let controller: ControllerInfo?
    let snapshot: GamepadSnapshot?
    var isHighlighted = false

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    var body: some View {
        VStack(spacing: ui(10)) {
            Text("P\(slot + 1)")
                .font(ui.font(15, .bold))
                .foregroundStyle(controller == nil ? theme.textSecondary : theme.accent)
            Image(systemName: controller == nil ? "plus" : "gamecontroller.fill")
                .font(.system(size: ui(controller == nil ? 26 : 44), weight: .semibold))
                .foregroundStyle(controller == nil ? theme.divider : theme.textPrimary)
                .frame(height: ui(52))
            Text(controller?.name ?? "Not connected")
                .font(ui.font(15, .medium))
                .foregroundStyle(controller == nil ? theme.textSecondary : theme.textPrimary)
                .lineLimit(1)
            if let controller {
                HStack(spacing: ui(10)) {
                    PlayerLights(playerIndex: controller.playerIndex)
                    if let level = snapshot?.batteryLevel ?? controller.batteryLevel {
                        BatteryBar(level: level, isCharging: snapshot?.isCharging ?? false)
                    }
                }
            }
        }
        .padding(ui(14))
        .frame(width: ui(250), height: ui(190))
        .background {
            if controller == nil {
                RoundedRectangle(cornerRadius: ui(14), style: .continuous)
                    .strokeBorder(theme.divider, style: StrokeStyle(lineWidth: ui(2), dash: [ui(7), ui(6)]))
            } else {
                RoundedRectangle(cornerRadius: ui(14), style: .continuous)
                    .fill(theme.surface)
                    .shadow(color: theme.shadow, radius: ui(3), y: ui(1))
            }
        }
        .selectionFrame(isHighlighted, cornerRadius: ui(14))
    }
}

struct BatteryBar: View {
    let level: Float
    let isCharging: Bool

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    var body: some View {
        HStack(spacing: ui(2)) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: ui(3)).strokeBorder(theme.textSecondary, lineWidth: ui(1.5))
                RoundedRectangle(cornerRadius: ui(1.5))
                    .fill(level < 0.2 ? theme.destructive : Color(hex: 0x2BD957))
                    .frame(width: max(ui(2), ui(26) * CGFloat(level)))
                    .padding(ui(2.5))
            }
            .frame(width: ui(32), height: ui(14))
            if isCharging {
                Image(systemName: "bolt.fill").font(.system(size: ui(11))).foregroundStyle(theme.textSecondary)
            }
        }
    }
}
