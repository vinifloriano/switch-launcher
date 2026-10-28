import AppKit
import SwiftUI

/// Square software tile with the game's cover icon.
public struct GameTile: View {
    let image: NSImage?
    let title: String
    let size: CGFloat
    let isSelected: Bool
    let badgeSymbol: String?
    let isLoading: Bool

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    /// `size` is in points (already scaled).
    /// `isLoading` shows a neutral tile while the cover art is still being decoded.
    public init(
        image: NSImage?,
        title: String,
        size: CGFloat,
        isSelected: Bool,
        badgeSymbol: String? = nil,
        isLoading: Bool = false
    ) {
        self.isLoading = isLoading
        self.image = image
        self.title = title
        self.size = size
        self.isSelected = isSelected
        self.badgeSymbol = badgeSymbol
    }

    /// Stable colour per title for software without cover art.
    private var placeholderColor: Color {
        let seed = title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return AvatarPalette.color(at: seed)
    }

    public var body: some View {
        let radius = size * 0.07
        ZStack(alignment: .topTrailing) {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                } else if isLoading {
                    theme.surfaceRaised
                } else {
                    ZStack {
                        LinearGradient(
                            colors: [placeholderColor.opacity(0.75), placeholderColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Text(title)
                            .font(.system(size: size * 0.09, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                            .padding(size * 0.08)
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))

            if let badgeSymbol {
                Image(systemName: badgeSymbol)
                    .font(.system(size: size * 0.06, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.13, height: size * 0.13)
                    .background(Circle().fill(theme.accent))
                    .overlay(Circle().strokeBorder(.white, lineWidth: max(1.5, size * 0.008)))
                    .padding(size * 0.04)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: theme.shadow, radius: isSelected ? ui(10) : ui(4), y: isSelected ? ui(4) : ui(2))
        .selectionFrame(isSelected, cornerRadius: radius)
    }
}

/// A tile that shows a symbol instead of cover art, e.g. "All Software".
public struct SymbolTile: View {
    let symbol: String
    let title: String
    let size: CGFloat
    let isSelected: Bool

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    public init(symbol: String, title: String, size: CGFloat, isSelected: Bool) {
        self.symbol = symbol
        self.title = title
        self.size = size
        self.isSelected = isSelected
    }

    public var body: some View {
        let radius = size * 0.07
        VStack(spacing: size * 0.06) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.24, weight: .semibold))
                .foregroundStyle(theme.accent)
            Text(title)
                .font(.system(size: size * 0.075, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
        }
        .frame(width: size, height: size)
        .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(theme.surface))
        .shadow(color: theme.shadow, radius: isSelected ? ui(10) : ui(4), y: isSelected ? ui(4) : ui(2))
        .selectionFrame(isSelected, cornerRadius: radius)
    }
}
