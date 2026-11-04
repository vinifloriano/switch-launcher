import AppKit
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

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        ZStack {
            shape
                .strokeBorder(theme.accent, lineWidth: lineWidth)
                .shadow(color: theme.accent.opacity(0.5), radius: ui(8))
            PulsingStroke(shape: shape, lineWidth: lineWidth, isActive: activeState == .key)
        }
    }
}

/// The white inner line that fades in and out. A SwiftUI `repeatForever` animation here updated
/// the view graph on every display frame (a third of a CPU core while idle); a Core Animation
/// opacity animation runs in the render server and costs the app nothing between frames.
private struct PulsingStroke<S: InsettableShape>: NSViewRepresentable {
    let shape: S
    let lineWidth: CGFloat
    let isActive: Bool

    func makeNSView(context: Context) -> PulseView { PulseView() }

    func updateNSView(_ view: PulseView, context: Context) {
        let shape = shape
        let inset = lineWidth * 0.5
        view.makePath = { rect in shape.inset(by: inset).path(in: rect).cgPath }
        view.update(lineWidth: lineWidth * 0.45, isActive: isActive)
    }
}

private final class PulseView: NSView {
    var makePath: ((CGRect) -> CGPath)?
    private let stroke = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        stroke.fillColor = nil
        stroke.strokeColor = NSColor.white.withAlphaComponent(0.6).cgColor
        stroke.opacity = 0
        layer?.addSublayer(stroke)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stroke.frame = bounds
        stroke.path = makePath?(bounds)
        CATransaction.commit()
    }

    func update(lineWidth: CGFloat, isActive: Bool) {
        if stroke.lineWidth != lineWidth { stroke.lineWidth = lineWidth }
        let running = stroke.animation(forKey: "pulse") != nil
        if isActive, !running {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0
            pulse.toValue = 1
            pulse.duration = 0.75
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            stroke.add(pulse, forKey: "pulse")
        } else if !isActive, running {
            stroke.removeAnimation(forKey: "pulse")
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
