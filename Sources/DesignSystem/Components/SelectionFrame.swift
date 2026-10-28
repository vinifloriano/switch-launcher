import SwiftUI

/// The cyan focus border drawn around whatever the cursor is on.
///
/// The pulse only animates the opacity of a solid highlight stroke, so Core Animation can
/// composite it without redrawing anything; it pauses while the window isn't key.
public struct SelectionFrame<S: InsettableShape>: ViewModifier {
    let isSelected: Bool
    let shape: S

    @Environment(\.ui) private var ui

    public init(isSelected: Bool, shape: S) {
        self.isSelected = isSelected
        self.shape = shape
    }

    public func body(content: Content) -> some View {
        content.overlay {
            if isSelected {
                SelectionGlow(shape: shape.inset(by: -ui(7)), lineWidth: ui(5))
                    .allowsHitTesting(false)
                    .transition(.scale(scale: 1.06).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.22, bounce: 0.35), value: isSelected)
    }
}

private struct SelectionGlow<S: InsettableShape>: View {
    let shape: S
    let lineWidth: CGFloat

    @State private var bright = false
    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        ZStack {
            shape
                .strokeBorder(theme.accent, lineWidth: lineWidth)
                .shadow(color: theme.accent.opacity(0.5), radius: ui(8))
            shape
                .strokeBorder(Color.white.opacity(0.6), lineWidth: lineWidth * 0.45)
                .padding(lineWidth * 0.275)
                .opacity(bright && activeState == .key ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                bright = true
            }
        }
    }
}

public extension View {
    func selectionFrame(_ isSelected: Bool, cornerRadius: CGFloat) -> some View {
        modifier(SelectionFrame(
            isSelected: isSelected,
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ))
    }

    func selectionRing(_ isSelected: Bool) -> some View {
        modifier(SelectionFrame(isSelected: isSelected, shape: Circle()))
    }
}
