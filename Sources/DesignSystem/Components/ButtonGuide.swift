import SwiftUI

/// A controller button glyph: a filled circle with the button's label ("A", "+", ...).
/// Pass an SF Symbol name prefixed with `sf:` to draw a symbol instead (e.g. `sf:house.fill`).
public struct ButtonGlyph: View {
    let glyph: String
    let size: CGFloat

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    /// `size` is in design units (unscaled).
    public init(_ glyph: String, size: CGFloat = 26) {
        self.glyph = glyph
        self.size = size
    }

    public var body: some View {
        Group {
            if glyph.hasPrefix("sf:") {
                Image(systemName: String(glyph.dropFirst(3)))
                    .font(.system(size: ui(size * 0.5), weight: .bold))
            } else {
                Text(glyph).font(ui.font(size * 0.62, .heavy))
            }
        }
        .foregroundStyle(theme.glyphForeground)
        .frame(width: ui(size), height: ui(size))
        .background(Circle().fill(theme.glyphBackground))
    }
}

public struct ButtonHint: Identifiable {
    public let id: String
    public let glyph: String
    public let title: String
    public let action: () -> Void

    public init(_ glyph: String, _ title: String, action: @escaping () -> Void) {
        self.id = glyph + title
        self.glyph = glyph
        self.title = title
        self.action = action
    }
}

/// The row of "(A) OK  (B) Back" hints at the bottom right. Each hint is clickable.
public struct ButtonGuide: View {
    let hints: [ButtonHint]

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    public init(_ hints: [ButtonHint]) {
        self.hints = hints
    }

    public var body: some View {
        HStack(spacing: ui(28)) {
            ForEach(hints) { hint in
                Button(action: hint.action) {
                    HStack(spacing: ui(8)) {
                        ButtonGlyph(hint.glyph)
                        Text(hint.title)
                            .font(ui.font(18))
                            .foregroundStyle(theme.textPrimary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
