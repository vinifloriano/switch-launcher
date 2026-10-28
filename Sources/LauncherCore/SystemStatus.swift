import Foundation
import IOKit.ps
import Network
import Observation

public enum NetworkKind: Sendable {
    case wifi, wired, offline
}

public struct BatteryState: Equatable, Sendable {
    public let level: Int
    public let isCharging: Bool
}

/// Clock, network and battery for the status bar.
@MainActor @Observable
public final class SystemStatus {
    public private(set) var now = Date()
    public private(set) var network: NetworkKind = .offline
    public private(set) var battery: BatteryState?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var ticks = 0

    public init() {}

    public func start() {
        guard timer == nil else { return }
        now = Date()
        battery = Self.readBattery()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        monitor.pathUpdateHandler = { [weak self] path in
            let kind: NetworkKind = path.status != .satisfied
                ? .offline
                : (path.usesInterfaceType(.wifi) ? .wifi : .wired)
            Task { @MainActor in self?.network = kind }
        }
        monitor.start(queue: DispatchQueue(label: "SwitchLauncher.network"))
    }

    private func tick() {
        let date = Date()
        // Only publish when the displayed minute changes, so views don't redraw every second.
        if Calendar.current.component(.minute, from: date) != Calendar.current.component(.minute, from: now) {
            now = date
        }
        ticks += 1
        if ticks % 30 == 0 {
            let reading = Self.readBattery()
            if reading != battery { battery = reading }
        }
    }

    static func readBattery() -> BatteryState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            return BatteryState(level: current * 100 / max, isCharging: charging)
        }
        return nil
    }
}
