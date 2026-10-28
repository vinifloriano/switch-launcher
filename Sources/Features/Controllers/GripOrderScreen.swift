import DesignSystem
import InputKit
import Observation
import SwiftUI

/// Change Grip/Order: each controller presses L + R to take the next player number.
@MainActor @Observable
public final class GripOrderModel: InputResponder {
    private(set) var assigned: [String] = []
    @ObservationIgnored private var held: [String: Set<NintendoButton>] = [:]
    @ObservationIgnored unowned let app: AppModel

    init(app: AppModel) {
        self.app = app
        for controller in app.input.controllers {
            app.input.setPlayerIndex(nil, for: controller.id)
        }
        app.input.rawHandler = { [weak self] id, button, pressed in
            self?.raw(id, button, pressed: pressed)
        }
    }

    private func raw(_ id: String, _ button: NintendoButton, pressed: Bool) {
        var buttons = held[id, default: []]
        if pressed { buttons.insert(button) } else { buttons.remove(button) }
        held[id] = buttons

        let pair = buttons.isSuperset(of: [.l, .r]) || buttons.isSuperset(of: [.zl, .zr])
        guard pair, !assigned.contains(id), assigned.count < 4 else { return }
        app.input.setPlayerIndex(assigned.count, for: id)
        assigned.append(id)
        app.sound.play(.select)
        app.input.rumble(id, duration: 0.25)
    }

    public func handle(_ button: NintendoButton) {
        switch button {
        case .a, .b:
            app.input.rawHandler = nil
            app.pop()
        default:
            break
        }
    }
}

struct GripOrderScreen: View {
    let model: GripOrderModel

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    var body: some View {
        let controllers = model.app.input.controllers
        ConsoleScaffold(title: "Change Grip/Order", icon: .symbol("arrow.left.arrow.right"), hints: hints) {
            VStack(spacing: ui(40)) {
                VStack(spacing: ui(10)) {
                    HStack(spacing: ui(12)) {
                        ButtonGlyph("L", size: 40)
                        Text("+").font(ui.font(26, .bold)).foregroundStyle(theme.textSecondary)
                        ButtonGlyph("R", size: 40)
                    }
                    Text("Press L + R on each controller, in player order.")
                        .font(ui.font(22, .medium))
                        .foregroundStyle(theme.textPrimary)
                }
                HStack(spacing: ui(20)) {
                    ForEach(0..<4, id: \.self) { slot in
                        let id = model.assigned.indices.contains(slot) ? model.assigned[slot] : nil
                        PlayerSlotCard(
                            slot: slot,
                            controller: controllers.first { $0.id == id },
                            snapshot: nil,
                            isHighlighted: slot == model.assigned.count
                        )
                    }
                }
                if controllers.isEmpty {
                    Text("No controllers are connected.")
                        .font(ui.font(17))
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
    }

    private var hints: [ButtonHint] {
        [ButtonHint("A", "Done") { model.app.handle(.a) }]
    }
}
