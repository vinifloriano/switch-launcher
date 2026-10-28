import SwiftUI

public enum NetworkGlyph: Sendable {
    case wifi, wired, offline

    var symbol: String {
        switch self {
        case .wifi: "wifi"
        case .wired: "network"
        case .offline: "wifi.slash"
        }
    }
}

/// Top bar: profile icons on the left, clock, connection and battery on the right.
public struct StatusBar<Leading: View>: View {
    let time: Date
    let network: NetworkGlyph
    let batteryLevel: Int?
    let isCharging: Bool
    let leading: Leading

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    public init(
        time: Date,
        network: NetworkGlyph,
        batteryLevel: Int?,
        isCharging: Bool,
        @ViewBuilder leading: () -> Leading
    ) {
        self.time = time
        self.network = network
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.leading = leading()
    }

    public var body: some View {
        HStack(alignment: .center) {
            leading
            Spacer()
            HStack(spacing: ui(16)) {
                Text(time, format: .dateTime.hour().minute())
                    .font(ui.font(22, .medium))
                    .monospacedDigit()
                Image(systemName: network.symbol)
                    .font(.system(size: ui(19), weight: .semibold))
                if let batteryLevel {
                    HStack(spacing: ui(6)) {
                        Text("\(batteryLevel)%")
                            .font(ui.font(16, .medium))
                            .monospacedDigit()
                        Image(systemName: batterySymbol(batteryLevel))
                            .font(.system(size: ui(22)))
                    }
                }
            }
            .foregroundStyle(theme.textPrimary)
        }
        .padding(.horizontal, ui(40))
    }

    private func batterySymbol(_ level: Int) -> String {
        if isCharging { return "battery.100percent.bolt" }
        switch level {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}
