import AppKit
import CoreHaptics
import GameController
import Observation

public enum NintendoButton: String, CaseIterable, Sendable {
    case a, b, x, y, plus, minus, l, r, zl, zr, home, capture, c
    case leftStick, rightStick
    case up, down, left, right
    /// HOME held for half a second (opens Quick Settings).
    case homeHold

    public var isDirection: Bool {
        self == .up || self == .down || self == .left || self == .right
    }
}

public struct ControllerInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let category: String
    public let batteryLevel: Float?
    public let isNintendo: Bool
    /// 0-based player number, `nil` when unassigned.
    public let playerIndex: Int?
    public let supportsHaptics: Bool
}

/// Live state of one controller, for the input tester.
public struct GamepadSnapshot: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let pressed: Set<NintendoButton>
    public let leftStick: SIMD2<Float>
    public let rightStick: SIMD2<Float>
    public let leftTrigger: Float
    public let rightTrigger: Float
    public let batteryLevel: Float?
    public let isCharging: Bool
}

/// Turns keyboard and game controller input into Nintendo button presses.
///
/// Keyboard: arrows move, Return/Space = A, Esc/Delete = B, X, Y, `=` = +, `-` = −, H = HOME,
/// ⇧H = hold HOME, Q/E = L/R, C = C, P = Capture. Controllers keep working for HOME while a game
/// is in front, so HOME can bring the launcher back like on the console.
@MainActor @Observable
public final class InputRouter {
    public private(set) var controllers: [ControllerInfo] = []

    /// Swap A/B and X/Y on Nintendo controllers so the printed labels match.
    public var useNintendoLayout = true {
        didSet { if oldValue != useNintendoLayout { rebindAll() } }
    }

    @ObservationIgnored public var handler: ((NintendoButton) -> Void)?
    /// Called when HOME is pressed on a controller while another app is in front.
    @ObservationIgnored public var backgroundHomeHandler: (() -> Void)?
    /// Every press and release, per controller. Used by screens that care which controller it was.
    @ObservationIgnored public var rawHandler: ((_ controllerID: String, _ button: NintendoButton, _ pressed: Bool) -> Void)?
    /// Asked when a controller is used while the launcher isn't the active app. Return `true`
    /// to handle the input anyway (the app should bring itself to the front).
    @ObservationIgnored public var acceptsInputWhileInactive: (() -> Bool)?
    /// Return `true` to let a key event through untouched (e.g. while a web page has focus).
    @ObservationIgnored public var shouldPassKeyEvent: ((NSEvent) -> Bool)?

    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var repeaters: [String: DirectionRepeater] = [:]
    @ObservationIgnored private var gamepads: [String: GCController] = [:]
    @ObservationIgnored private var swapped: [String: Bool] = [:]
    @ObservationIgnored private var hapticEngines: [String: CHHapticEngine] = [:]
    @ObservationIgnored private var homeHoldTimer: Timer?
    @ObservationIgnored private var homeHoldFired = false

    public init() {}

    public func start() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                (self?.handleKey(event) ?? false) ? nil : event
            }
        }

        GCController.shouldMonitorBackgroundEvents = true
        let center = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebindAll() }
            })
        }
        rebindAll()
    }

    public func startControllerDiscovery() {
        GCController.startWirelessControllerDiscovery {}
    }

    // MARK: Controller features

    public func snapshots() -> [GamepadSnapshot] {
        controllers.compactMap { info in
            guard let controller = gamepads[info.id], let pad = controller.extendedGamepad else { return nil }
            let swap = swapped[info.id] ?? false
            var pressed = Set<NintendoButton>()
            func check(_ input: GCControllerButtonInput?, _ button: NintendoButton) {
                if input?.isPressed == true { pressed.insert(button) }
            }
            check(pad.buttonA, swap ? .b : .a)
            check(pad.buttonB, swap ? .a : .b)
            check(pad.buttonX, swap ? .y : .x)
            check(pad.buttonY, swap ? .x : .y)
            check(pad.leftShoulder, .l)
            check(pad.rightShoulder, .r)
            check(pad.leftTrigger, .zl)
            check(pad.rightTrigger, .zr)
            check(pad.buttonMenu, .plus)
            check(pad.buttonOptions, .minus)
            check(pad.buttonHome, .home)
            check(pad.leftThumbstickButton, .leftStick)
            check(pad.rightThumbstickButton, .rightStick)
            check(controller.physicalInputProfile.buttons[GCInputButtonShare], .capture)
            check(pad.dpad.up, .up)
            check(pad.dpad.down, .down)
            check(pad.dpad.left, .left)
            check(pad.dpad.right, .right)
            return GamepadSnapshot(
                id: info.id,
                name: info.name,
                pressed: pressed,
                leftStick: SIMD2(pad.leftThumbstick.xAxis.value, pad.leftThumbstick.yAxis.value),
                rightStick: SIMD2(pad.rightThumbstick.xAxis.value, pad.rightThumbstick.yAxis.value),
                leftTrigger: pad.leftTrigger.value,
                rightTrigger: pad.rightTrigger.value,
                batteryLevel: Self.batteryLevel(controller),
                isCharging: controller.battery?.batteryState == .charging
            )
        }
    }

    /// Lights the controller's player LEDs. Pass `nil` to clear.
    public func setPlayerIndex(_ index: Int?, for id: String) {
        guard let controller = gamepads[id] else { return }
        controller.playerIndex = index.flatMap(GCControllerPlayerIndex.init(rawValue:)) ?? .indexUnset
        refreshInfo()
    }

    /// Vibrates one controller (or all when `id` is nil). Returns how many could vibrate.
    @discardableResult
    public func rumble(_ id: String? = nil, duration: TimeInterval = 0.7) -> Int {
        var count = 0
        for (key, controller) in gamepads where id == nil || id == key {
            guard let engine = hapticEngine(for: key, controller) else { continue }
            do {
                try engine.start()
                let event = CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4),
                    ],
                    relativeTime: 0,
                    duration: duration
                )
                let player = try engine.makePlayer(with: CHHapticPattern(events: [event], parameters: []))
                try player.start(atTime: CHHapticTimeImmediate)
                count += 1
            } catch {
                continue
            }
        }
        return count
    }

    private func hapticEngine(for key: String, _ controller: GCController) -> CHHapticEngine? {
        if let engine = hapticEngines[key] { return engine }
        let engine = controller.haptics?.createEngine(withLocality: .default)
        hapticEngines[key] = engine
        return engine
    }

    // MARK: Keyboard

    private func handleKey(_ event: NSEvent) -> Bool {
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return false }
        // Let text fields (e.g. editing the nickname) receive typing.
        if event.window?.firstResponder is NSText { return false }
        if shouldPassKeyEvent?(event) == true { return false }
        guard let button = Self.map(event) else { return false }
        if event.isARepeat && !button.isDirection { return true }
        handler?(button)
        return true
    }

    static func map(_ event: NSEvent) -> NintendoButton? {
        switch event.keyCode {
        case 123: return .left
        case 124: return .right
        case 125: return .down
        case 126: return .up
        case 36, 76, 49: return .a
        case 53, 51: return .b
        default: break
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "x": return .x
        case "y": return .y
        case "=", "+": return .plus
        case "-": return .minus
        case "h": return event.modifierFlags.contains(.shift) ? .homeHold : .home
        case "q": return .l
        case "e": return .r
        case "c": return .c
        case "p": return .capture
        default: return nil
        }
    }

    // MARK: Game controllers

    private func rebindAll() {
        repeaters.values.forEach { $0.cancel() }
        repeaters.removeAll()
        gamepads.removeAll()
        swapped.removeAll()
        hapticEngines.removeAll()
        for controller in GCController.controllers() {
            bind(controller)
        }
        refreshInfo()
    }

    private func refreshInfo() {
        controllers = gamepads
            .sorted { lhs, rhs in
                let a = lhs.value.playerIndex.rawValue
                let b = rhs.value.playerIndex.rawValue
                if (a < 0) != (b < 0) { return a >= 0 }
                return a != b ? a < b : lhs.key < rhs.key
            }
            .map { key, controller in
                ControllerInfo(
                    id: key,
                    name: controller.vendorName ?? "Controller",
                    category: controller.productCategory,
                    batteryLevel: Self.batteryLevel(controller),
                    isNintendo: Self.isNintendo(controller),
                    playerIndex: controller.playerIndex == .indexUnset ? nil : controller.playerIndex.rawValue,
                    supportsHaptics: controller.haptics != nil
                )
            }
    }

    private func bind(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        let swap = Self.isNintendo(controller) && useNintendoLayout
        let key = String(describing: ObjectIdentifier(controller))
        gamepads[key] = controller
        swapped[key] = swap

        func on(_ input: GCControllerButtonInput?, _ button: NintendoButton) {
            input?.pressedChangedHandler = { [weak self] _, _, pressed in
                MainActor.assumeIsolated { self?.buttonChanged(key, button, pressed: pressed) }
            }
        }
        // GameController reports face buttons by position (south = A). Nintendo prints A on the east.
        on(pad.buttonA, swap ? .b : .a)
        on(pad.buttonB, swap ? .a : .b)
        on(pad.buttonX, swap ? .y : .x)
        on(pad.buttonY, swap ? .x : .y)
        on(pad.leftShoulder, .l)
        on(pad.rightShoulder, .r)
        on(pad.leftTrigger, .zl)
        on(pad.rightTrigger, .zr)
        on(pad.buttonMenu, .plus)
        on(pad.buttonOptions, .minus)
        on(pad.leftThumbstickButton, .leftStick)
        on(pad.rightThumbstickButton, .rightStick)
        on(controller.physicalInputProfile.buttons[GCInputButtonShare], .capture)
        pad.buttonHome?.pressedChangedHandler = { [weak self] _, _, pressed in
            MainActor.assumeIsolated { self?.homeChanged(key, pressed: pressed) }
        }

        let dpad = DirectionRepeater { [weak self] in self?.controllerDirection($0) }
        let stick = DirectionRepeater { [weak self] in self?.controllerDirection($0) }
        repeaters[key + ".dpad"] = dpad
        repeaters[key + ".stick"] = stick
        pad.dpad.valueChangedHandler = { _, x, y in
            MainActor.assumeIsolated { dpad.update(Self.direction(x: x, y: y)) }
        }
        pad.leftThumbstick.valueChangedHandler = { _, x, y in
            MainActor.assumeIsolated { stick.update(Self.direction(x: x, y: y)) }
        }
    }

    private func buttonChanged(_ key: String, _ button: NintendoButton, pressed: Bool) {
        rawHandler?(key, button, pressed)
        if pressed { deliver(button) }
    }

    private func deliver(_ button: NintendoButton) {
        if NSApp.isActive || acceptsInputWhileInactive?() == true {
            handler?(button)
        }
    }

    /// HOME fires on release; holding it for half a second sends `.homeHold` instead.
    private func homeChanged(_ key: String, pressed: Bool) {
        rawHandler?(key, .home, pressed)
        homeHoldTimer?.invalidate()
        if pressed {
            homeHoldFired = false
            homeHoldTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.homeHoldFired = true
                    self.homePressed(.homeHold)
                }
            }
        } else if !homeHoldFired {
            homePressed(.home)
        }
    }

    private func homePressed(_ button: NintendoButton) {
        if NSApp.isActive || acceptsInputWhileInactive?() == true {
            handler?(button)
        } else {
            backgroundHomeHandler?()
        }
    }

    private func controllerDirection(_ button: NintendoButton) {
        deliver(button)
    }

    static func direction(x: Float, y: Float) -> NintendoButton? {
        guard max(abs(x), abs(y)) >= 0.55 else { return nil }
        if abs(x) > abs(y) { return x > 0 ? .right : .left }
        return y > 0 ? .up : .down
    }

    /// `nil` when the controller doesn't report its battery (many report 0 with an unknown state).
    static func batteryLevel(_ controller: GCController) -> Float? {
        guard let battery = controller.battery, battery.batteryState != .unknown else { return nil }
        return battery.batteryLevel
    }

    static func isNintendo(_ controller: GCController) -> Bool {
        let text = (controller.vendorName ?? "") + " " + controller.productCategory
        return ["Switch", "Joy-Con", "Nintendo"].contains { text.localizedCaseInsensitiveContains($0) }
    }
}

/// Emits a direction once, then repeats it while held (like holding the stick on the console).
@MainActor
final class DirectionRepeater {
    private var current: NintendoButton?
    private var timer: Timer?
    private let fire: (NintendoButton) -> Void

    init(fire: @escaping (NintendoButton) -> Void) {
        self.fire = fire
    }

    func update(_ direction: NintendoButton?) {
        guard direction != current else { return }
        current = direction
        timer?.invalidate()
        timer = nil
        guard let direction else { return }
        fire(direction)
        timer = Timer.scheduledTimer(withTimeInterval: 0.38, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.startRepeating(direction) }
        }
    }

    private func startRepeating(_ direction: NintendoButton) {
        timer = Timer.scheduledTimer(withTimeInterval: 0.085, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.current == direction else { return }
                self.fire(direction)
            }
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        current = nil
    }
}
