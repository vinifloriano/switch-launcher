import SwiftUI

/// Round shortcut button from the HOME Menu's bottom row.
public struct CircleIconButton: View {
    let symbol: String
    let tint: Color
    let diameter: CGFloat
    let isSelected: Bool

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    /// `diameter` is in points (already scaled).
    public init(symbol: String, tint: Color, diameter: CGFloat, isSelected: Bool) {
        self.symbol = symbol
        self.tint = tint
        self.diameter = diameter
        self.isSelected = isSelected
    }

    public var body: some View {
        ZStack {
            Circle().fill(theme.surface)
            Image(systemName: symbol)
                .font(.system(size: diameter * 0.4, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: theme.shadow, radius: ui(3), y: ui(1.5))
        .selectionRing(isSelected)
    }
}

/// Circular profile icon shown at the top-left of the HOME Menu.
public struct UserAvatar: View {
    let symbol: String
    let color: Color
    let diameter: CGFloat
    let isSelected: Bool

    @Environment(\.ui) private var ui
    @Environment(\.theme) private var theme

    public init(symbol: String, color: Color, diameter: CGFloat, isSelected: Bool = false) {
        self.symbol = symbol
        self.color = color
        self.diameter = diameter
        self.isSelected = isSelected
    }

    public var body: some View {
        ZStack {
            Circle().fill(
                LinearGradient(colors: [color.opacity(0.8), color], startPoint: .top, endPoint: .bottom)
            )
            Image(systemName: symbol)
                .font(.system(size: diameter * 0.46, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: diameter, height: diameter)
        .overlay(Circle().strokeBorder(.white, lineWidth: max(2, diameter * 0.05)))
        .shadow(color: theme.shadow, radius: ui(3), y: ui(1.5))
        .selectionRing(isSelected)
    }
}
