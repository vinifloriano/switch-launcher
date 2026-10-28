import DesignSystem
import InputKit
import Observation
import SwiftUI

/// Test Input Devices: live buttons, sticks (with a trail for checking calibration) and
/// analog triggers. The controller that was used last is shown; the keyboard can be tested too.
@MainActor @Observable
public final class ControllerTestModel: InputResponder {
    static let keyboardID = "keyboard"

    private(set) var snapshots: [GamepadSnapshot] = []
    private(set) var leftTrails: [String: [SIMD2<Float>]] = [:]
    private(set) var rightTrails: [String: [SIMD2<Float>]] = [:]
    private(set) var keyboardPressed: Set<NintendoButton> = []
    var selectedID: String = keyboardID

    @ObservationIgnored unowned let app: AppModel
    @ObservationIgnored private var flashes: [NintendoButton: Date] = [:]
    @ObservationIgnored private var lastB: Date?
    @ObservationIgnored private var timer: Timer?

    init(app: AppModel) {
        self.app = app
        if let first = app.input.controllers.first { selectedID = first.id }
        app.input.rawHandler = { [weak self] id, _, pressed in
            guard let self, pressed, self.selectedID != id else { return }
            self.selectedID = id
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                self.tick()
            }
        }
    }

    var selected: GamepadSnapshot? {
        snapshots.first { $0.id == selectedID }
    }

    private func tick() {
        let latest = app.input.snapshots()
        if latest != snapshots { snapshots = latest }
        for snapshot in latest {
            append(snapshot.leftStick, to: &leftTrails, id: snapshot.id)
            append(snapshot.rightStick, to: &rightTrails, id: snapshot.id)
        }
        let now = Date()
        flashes = flashes.filter { now.timeIntervalSince($0.value) < 0.25 }
        let keys = Set(flashes.keys)
        if keys != keyboardPressed { keyboardPressed = keys }
    }

    private func append(_ value: SIMD2<Float>, to trails: inout [String: [SIMD2<Float>]], id: String) {
        var trail = trails[id, default: []]
        if trail.last == value { return }
        trail.append(value)
        if trail.count > 48 { trail.removeFirst(trail.count - 48) }
        trails[id] = trail
    }

    public func handle(_ button: NintendoButton) {
        let now = Date()
        // Controllers are drawn from their live state; this flash is for the keyboard.
        if snapshots.isEmpty || selectedID == Self.keyboardID {
            flashes[button] = now
            selectedID = Self.keyboardID
        }
        if button == .b {
            if let lastB, now.timeIntervalSince(lastB) < 0.6 {
                finish()
                return
            }
            lastB = now
        }
    }

    func finish() {
        timer?.invalidate()
        app.input.rawHandler = nil
        app.pop()
    }

    func resetTrails() {
        leftTrails.removeAll()
        rightTrails.removeAll()
    }
}

struct ControllerTestScreen: View {
    let model: ControllerTestModel

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    var body: some View {
        let snapshot = model.selected
        let isKeyboard = snapshot == nil
        ConsoleScaffold(
            title: "Test Input Devices",
            icon: .symbol("gamecontroller.fill"),
            trailing: "Press B twice or HOME to finish",
            hints: hints
        ) {
            VStack(spacing: ui(14)) {
                devicePicker
                HStack(alignment: .center, spacing: ui(36)) {
                    ControllerDiagram(
                        pressed: snapshot?.pressed ?? model.keyboardPressed,
                        leftStick: snapshot?.leftStick ?? .zero,
                        rightStick: snapshot?.rightStick ?? .zero,
                        leftTrigger: snapshot?.leftTrigger ?? 0,
                        rightTrigger: snapshot?.rightTrigger ?? 0,
                        leftTrail: snapshot.map { model.leftTrails[$0.id] ?? [] } ?? [],
                        rightTrail: snapshot.map { model.rightTrails[$0.id] ?? [] } ?? []
                    )
                    .frame(width: ui(640), height: ui(384))

                    VStack(alignment: .leading, spacing: ui(14)) {
                        if let snapshot {
                            readout("Left Stick", vector(snapshot.leftStick))
                            readout("Right Stick", vector(snapshot.rightStick))
                            readout("ZL", String(format: "%.2f", snapshot.leftTrigger))
                            readout("ZR", String(format: "%.2f", snapshot.rightTrigger))
                            if let level = snapshot.batteryLevel {
                                readout("Battery", "\(Int(level * 100))%" + (snapshot.isCharging ? " ⚡︎" : ""))
                            }
                            readout("Pressed", snapshot.pressed.map(name).sorted().joined(separator: " "))
                        } else {
                            Text("Keyboard")
                                .font(ui.font(20, .semibold))
                                .foregroundStyle(theme.textPrimary)
                            Text("Arrows · Return = A · Esc = B\nX · Y · = (+) · - (−)\nQ / E = L / R · C · P = Capture")
                                .font(ui.font(15))
                                .foregroundStyle(theme.textSecondary)
                            readout("Pressed", model.keyboardPressed.map(name).sorted().joined(separator: " "))
                        }
                    }
                    .frame(width: ui(300), alignment: .leading)
                }
                if isKeyboard && model.snapshots.isEmpty {
                    Text("Connect a controller to test its sticks and triggers.")
                        .font(ui.font(15))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .padding(.top, ui(12))
        }
    }

    private var devicePicker: some View {
        HStack(spacing: ui(10)) {
            chip(ControllerTestModel.keyboardID, "Keyboard", "keyboard")
            ForEach(Array(model.snapshots.enumerated()), id: \.element.id) { index, snapshot in
                chip(snapshot.id, "P\(index + 1) · \(snapshot.name)", "gamecontroller.fill")
            }
        }
    }

    private func chip(_ id: String, _ title: String, _ symbol: String) -> some View {
        let isOn = model.selectedID == id
        return Label(title, systemImage: symbol)
            .font(ui.font(15, .medium))
            .foregroundStyle(isOn ? Color.white : theme.textPrimary)
            .padding(.horizontal, ui(14))
            .padding(.vertical, ui(7))
            .background(Capsule().fill(isOn ? theme.accent : theme.surface))
            .onTapGesture { model.selectedID = id }
    }

    private func readout(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: ui(2)) {
            Text(title)
                .font(ui.font(14))
                .foregroundStyle(theme.textSecondary)
            Text(value.isEmpty ? "—" : value)
                .font(ui.font(19, .medium))
                .foregroundStyle(theme.textPrimary)
                .monospacedDigit()
        }
    }

    private func vector(_ v: SIMD2<Float>) -> String {
        String(format: "x %+.2f   y %+.2f", v.x, v.y)
    }

    private func name(_ button: NintendoButton) -> String {
        switch button {
        case .plus: "+"
        case .minus: "−"
        case .leftStick: "LS"
        case .rightStick: "RS"
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        case .homeHold: "HOME"
        default: button.rawValue.uppercased()
        }
    }

    private var hints: [ButtonHint] {
        [
            ButtonHint("sf:arrow.counterclockwise", "Clear Trails") { model.resetTrails() },
            ButtonHint("B", "Finish") { model.finish() },
        ]
    }
}
