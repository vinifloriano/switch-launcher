import SwiftUI

public extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Colour tokens for one HOME Menu theme. Mirrors the console's two built-in themes.
public struct Theme: Equatable, Sendable {
    public let name: String
    public let isDark: Bool
    public let background: Color
    public let surface: Color
    public let surfaceRaised: Color
    public let textPrimary: Color
    public let textSecondary: Color
    public let divider: Color
    public let accent: Color
    public let accentSoft: Color
    public let destructive: Color
    public let glyphBackground: Color
    public let glyphForeground: Color
    public let shadow: Color

    public static let basicWhite = Theme(
        name: "Basic White",
        isDark: false,
        background: Color(hex: 0xEBEBEB),
        surface: .white,
        surfaceRaised: Color(hex: 0xF6F6F6),
        textPrimary: Color(hex: 0x2D2D2D),
        textSecondary: Color(hex: 0x737373),
        divider: Color(hex: 0xC8C8C8),
        accent: Color(hex: 0x00B4E6),
        accentSoft: Color(hex: 0x00B4E6, opacity: 0.12),
        destructive: Color(hex: 0xE6302F),
        glyphBackground: Color(hex: 0x2D2D2D),
        glyphForeground: .white,
        shadow: .black.opacity(0.18)
    )

    public static let basicBlack = Theme(
        name: "Basic Black",
        isDark: true,
        background: Color(hex: 0x2D2D2D),
        surface: Color(hex: 0x3C3C3C),
        surfaceRaised: Color(hex: 0x464646),
        textPrimary: .white,
        textSecondary: Color(hex: 0xA6A6A6),
        divider: Color(hex: 0x555555),
        accent: Color(hex: 0x1ED2FF),
        accentSoft: Color(hex: 0x1ED2FF, opacity: 0.16),
        destructive: Color(hex: 0xFF5A52),
        glyphBackground: .white,
        glyphForeground: Color(hex: 0x2D2D2D),
        shadow: .black.opacity(0.45)
    )
}

public extension EnvironmentValues {
    @Entry var theme: Theme = .basicWhite
    @Entry var ui: UIScale = UIScale()
}

/// Profile icon choices for the user avatar.
public enum AvatarPalette {
    public static let colors: [Color] = [
        Color(hex: 0xE60012), Color(hex: 0x00A8E8), Color(hex: 0x2BB673), Color(hex: 0xF5A623),
        Color(hex: 0x8A5CF6), Color(hex: 0xFF5FA2), Color(hex: 0x3C3C3C), Color(hex: 0x00C3B5),
    ]
    public static let colorNames = ["Red", "Blue", "Green", "Yellow", "Purple", "Pink", "Charcoal", "Teal"]

    public static let symbols = [
        "star.fill", "heart.fill", "leaf.fill", "flame.fill", "bolt.fill", "moon.fill",
        "sun.max.fill", "crown.fill", "pawprint.fill", "gamecontroller.fill", "music.note", "sparkles",
    ]
    public static let symbolNames = [
        "Star", "Heart", "Leaf", "Flame", "Bolt", "Moon",
        "Sun", "Crown", "Paw", "Controller", "Music", "Sparkles",
    ]

    public static func color(at index: Int) -> Color {
        colors[((index % colors.count) + colors.count) % colors.count]
    }
}
