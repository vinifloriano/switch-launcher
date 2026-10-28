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

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    public init(
        title: String,
        subtitle: String? = nil,
        image: NSImage? = nil,
        symbol: String? = nil,
        accessory: ItemAccessory = .none,
        isFocused: Bool,
        isDestructive: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.image = image
        self.symbol = symbol
        self.accessory = accessory
        self.isFocused = isFocused
        self.isDestructive = isDestructive
    }

    public var body: some View {
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
