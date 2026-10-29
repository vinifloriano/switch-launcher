import AppKit
import SwiftUI

/// Left-hand category entry in two-pane pages (System Settings, software options...).
public struct SidebarRow: View {
    let title: String
    let symbol: String?
    let isCurrent: Bool
    let isFocused: Bool

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    public init(title: String, symbol: String?, isCurrent: Bool, isFocused: Bool) {
        self.title = title
        self.symbol = symbol
        self.isCurrent = isCurrent
        self.isFocused = isFocused
    }

    public var body: some View {
        HStack(spacing: ui(14)) {
            RoundedRectangle(cornerRadius: ui(2))
                .fill(isCurrent ? theme.accent : .clear)
                .frame(width: ui(5), height: ui(34))
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: ui(18), weight: .semibold))
                    .frame(width: ui(24))
            }
            Text(title)
                .font(ui.font(20, isCurrent ? .semibold : .regular))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(isCurrent ? theme.accent : theme.textPrimary)
        .padding(.vertical, ui(10))
        .padding(.trailing, ui(12))
        .background(
            RoundedRectangle(cornerRadius: ui(4), style: .continuous)
                .fill(isFocused ? theme.surface : .clear)
        )
        .selectionFrame(isFocused, cornerRadius: ui(4))
        .contentShape(Rectangle())
    }
}

public enum ItemAccessory {
    case none
    case text(String)
    case toggle(Bool)
    case choice(String)
    case chevron
    /// A level from 0 to 1 (brightness, volume), changed with left/right.
    case slider(Double)
}

/// One coloured part of a `Meter`.
public struct MeterSegment: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let detail: String
    /// Share of the whole bar, 0...1.
    public let fraction: Double
    public let color: Color

    public init(id: String, label: String, detail: String, fraction: Double, color: Color) {
        self.id = id
        self.label = label
        self.detail = detail
        self.fraction = fraction
        self.color = color
    }
}

/// A bar split into coloured parts with a legend below, e.g. how a disk is used.
public struct Meter: Sendable {
    public let segments: [MeterSegment]

    public init(segments: [MeterSegment]) {
        self.segments = segments
    }
}

struct MeterView: View {
    let meter: Meter

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    var body: some View {
        VStack(alignment: .leading, spacing: ui(10)) {
            GeometryReader { geometry in
                HStack(spacing: ui(2)) {
                    ForEach(meter.segments.filter { $0.fraction > 0 }) { segment in
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: max(ui(3), geometry.size.width * min(segment.fraction, 1)))
                    }
                    Spacer(minLength: 0)
                }
                .background(theme.divider.opacity(0.45))
                .clipShape(Capsule(style: .continuous))
            }
            .frame(height: ui(16))
            HStack(spacing: ui(22)) {
                ForEach(meter.segments) { segment in
                    HStack(spacing: ui(7)) {
                        Circle().fill(segment.color).frame(width: ui(11), height: ui(11))
                        Text(segment.label)
                            .font(ui.font(14, .medium))
                            .foregroundStyle(theme.textPrimary)
                        Text(segment.detail)
                            .font(ui.font(14))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .lineLimit(1)
                }
            }
        }
    }
}

/// Level bar with a percentage, for `ItemAccessory.slider`.
struct LevelSlider: View {
    let value: Double
    let isFocused: Bool
    let onChange: ((Double) -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    var body: some View {
        HStack(spacing: ui(12)) {
            Image(systemName: "minus").opacity(isFocused ? 1 : 0.35)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.divider)
                    Capsule().fill(theme.accent).frame(width: geometry.size.width * min(max(value, 0), 1))
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    onChange?(min(max(drag.location.x / geometry.size.width, 0), 1))
                })
            }
            .frame(width: ui(220), height: ui(10))
            Image(systemName: "plus").opacity(isFocused ? 1 : 0.35)
            Text("\(Int((value * 100).rounded()))%")
                .font(ui.font(17, .medium))
                .foregroundStyle(theme.textSecondary)
                .frame(width: ui(52), alignment: .trailing)
        }
        .font(.system(size: ui(13), weight: .bold))
        .foregroundStyle(theme.textSecondary)
    }
}

/// A row in the right-hand pane: optional icon, title + subtitle, accessory value.
public struct ItemRow: View {
    let title: String
    let subtitle: String?
    let image: NSImage?
    let symbol: String?
    let accessory: ItemAccessory
    let isFocused: Bool
    let isDestructive: Bool
    let meter: Meter?
    let onSlide: ((Double) -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    public init(
        title: String,
        subtitle: String? = nil,
        image: NSImage? = nil,
        symbol: String? = nil,
        accessory: ItemAccessory = .none,
        isFocused: Bool,
        isDestructive: Bool = false,
        meter: Meter? = nil,
        onSlide: ((Double) -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.image = image
        self.symbol = symbol
        self.accessory = accessory
        self.isFocused = isFocused
        self.isDestructive = isDestructive
        self.meter = meter
        self.onSlide = onSlide
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ui(12)) {
            mainRow
            if let meter {
                MeterView(meter: meter).padding(.bottom, ui(6))
            }
        }
        .padding(.horizontal, ui(18))
        .padding(.vertical, ui(10))
        .frame(minHeight: ui(66))
        .background(
            RoundedRectangle(cornerRadius: ui(4), style: .continuous)
                .fill(isFocused ? theme.surface : .clear)
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.divider.opacity(0.7)).frame(height: 1)
        }
        .selectionFrame(isFocused, cornerRadius: ui(4))
        .contentShape(Rectangle())
    }

    private var mainRow: some View {
        HStack(spacing: ui(16)) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: ui(44), height: ui(44))
                    .clipShape(RoundedRectangle(cornerRadius: ui(5), style: .continuous))
            } else if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: ui(20), weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: ui(32))
            }
            VStack(alignment: .leading, spacing: ui(3)) {
                Text(title)
                    .font(ui.font(20))
                    .foregroundStyle(isDestructive ? theme.destructive : theme.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(ui.font(14))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: ui(12))
            accessoryView
        }
        .frame(minHeight: ui(46))
    }

    @ViewBuilder private var accessoryView: some View {
        switch accessory {
        case .none:
            EmptyView()
        case .text(let value):
            Text(value)
                .font(ui.font(18))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
        case .choice(let value):
            Text(value)
                .font(ui.font(19, .medium))
                .foregroundStyle(theme.accent)
        case .toggle(let isOn):
            ConsoleToggle(isOn: isOn)
        case .slider(let value):
            LevelSlider(value: value, isFocused: isFocused, onChange: onSlide)
        case .chevron:
            Image(systemName: "chevron.right")
                .font(.system(size: ui(16), weight: .semibold))
                .foregroundStyle(theme.textSecondary)
        }
    }
}

/// Console-style on/off switch.
public struct ConsoleToggle: View {
    let isOn: Bool

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    public init(isOn: Bool) {
        self.isOn = isOn
    }

    public var body: some View {
        HStack(spacing: ui(10)) {
            Text(isOn ? "On" : "Off")
                .font(ui.font(17, .medium))
                .foregroundStyle(isOn ? theme.accent : theme.textSecondary)
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? theme.accent : theme.divider)
                Circle()
                    .fill(.white)
                    .padding(ui(3))
                    .shadow(color: .black.opacity(0.2), radius: ui(1))
            }
            .frame(width: ui(52), height: ui(30))
        }
        .animation(.spring(duration: 0.2), value: isOn)
    }
}
