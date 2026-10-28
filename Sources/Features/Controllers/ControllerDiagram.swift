import DesignSystem
import InputKit
import SwiftUI

/// Pro Controller drawing that lights up pressed buttons and shows stick positions and trails.
/// Drawn with `Canvas` on a 600×360 grid so it can redraw at 60 fps cheaply.
struct ControllerDiagram: View {
    var pressed: Set<NintendoButton>
    var leftStick: SIMD2<Float> = .zero
    var rightStick: SIMD2<Float> = .zero
    var leftTrigger: Float = 0
    var rightTrigger: Float = 0
    var leftTrail: [SIMD2<Float>] = []
    var rightTrail: [SIMD2<Float>] = []

    @Environment(\.theme) private var theme

    var body: some View {
        Canvas { ctx, size in
            let scale = min(size.width / 600, size.height / 360)
            ctx.translateBy(x: (size.width - 600 * scale) / 2, y: (size.height - 360 * scale) / 2)
            ctx.scaleBy(x: scale, y: scale)
            draw(in: &ctx)
        }
        .aspectRatio(600 / 360, contentMode: .fit)
    }

    private func draw(in ctx: inout GraphicsContext) {
        let line = theme.divider
        let idle = theme.surfaceRaised
        let lit = theme.accent

        func fill(_ path: Path, _ isOn: Bool) {
            ctx.fill(path, with: .color(isOn ? lit : idle))
            ctx.stroke(path, with: .color(isOn ? lit : line), lineWidth: 2)
        }
        func label(_ text: String, _ point: CGPoint, _ isOn: Bool, size: CGFloat = 15) {
            ctx.draw(
                Text(text)
                    .font(.system(size: size, weight: .heavy, design: .rounded))
                    .foregroundStyle(isOn ? Color.white : theme.textSecondary),
                at: point
            )
        }
        func roundRect(_ rect: CGRect, _ radius: CGFloat) -> Path {
            Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        }

        // Triggers (fill shows analog value) and bumpers.
        for (rect, value, name, button) in [
            (CGRect(x: 100, y: 6, width: 140, height: 26), leftTrigger, "ZL", NintendoButton.zl),
            (CGRect(x: 360, y: 6, width: 140, height: 26), rightTrigger, "ZR", NintendoButton.zr),
        ] {
            let shape = roundRect(rect, 10)
            ctx.fill(shape, with: .color(idle))
            var amount = rect
            amount.size.width *= CGFloat(max(value, pressed.contains(button) ? 1 : 0))
            ctx.fill(roundRect(amount, 10), with: .color(lit))
            ctx.stroke(shape, with: .color(line), lineWidth: 2)
            label(name, CGPoint(x: rect.midX, y: rect.midY), pressed.contains(button) || value > 0.5, size: 13)
        }
        for (rect, name, button) in [
            (CGRect(x: 110, y: 38, width: 130, height: 22), "L", NintendoButton.l),
            (CGRect(x: 360, y: 38, width: 130, height: 22), "R", NintendoButton.r),
        ] {
            fill(roundRect(rect, 9), pressed.contains(button))
            label(name, CGPoint(x: rect.midX, y: rect.midY), pressed.contains(button), size: 13)
        }

        // Body with grips, merged into one outline.
        let body = roundRect(CGRect(x: 88, y: 62, width: 424, height: 160), 72)
            .union(Path(ellipseIn: CGRect(x: 92, y: 132, width: 156, height: 210)))
            .union(Path(ellipseIn: CGRect(x: 352, y: 132, width: 156, height: 210)))
        ctx.fill(body, with: .color(theme.surface))
        ctx.stroke(body, with: .color(line), lineWidth: 2.5)

        // Sticks.
        drawStick(&ctx, center: CGPoint(x: 185, y: 140), value: leftStick, trail: leftTrail,
                  isPressed: pressed.contains(.leftStick))
        drawStick(&ctx, center: CGPoint(x: 395, y: 232), value: rightStick, trail: rightTrail,
                  isPressed: pressed.contains(.rightStick))

        // D-pad.
        let dpad = CGPoint(x: 205, y: 232)
        for (dx, dy, button) in [(0.0, -28.0, NintendoButton.up), (0, 28, .down), (-28, 0, .left), (28, 0, .right)] {
            fill(roundRect(CGRect(x: dpad.x + dx - 13, y: dpad.y + dy - 13, width: 26, height: 26), 6), pressed.contains(button))
        }

        // Face buttons in Nintendo positions.
        let face = CGPoint(x: 425, y: 126)
        for (dx, dy, name, button) in [
            (0.0, -32.0, "X", NintendoButton.x), (32, 0, "A", .a), (0, 32, "B", .b), (-32, 0, "Y", .y),
        ] {
            let point = CGPoint(x: face.x + dx, y: face.y + dy)
            fill(Path(ellipseIn: CGRect(x: point.x - 17, y: point.y - 17, width: 34, height: 34)), pressed.contains(button))
            label(name, point, pressed.contains(button))
        }

        // − + Capture HOME.
        fill(roundRect(CGRect(x: 242, y: 84, width: 26, height: 10), 5), pressed.contains(.minus))
        var plus = Path()
        plus.addRoundedRect(in: CGRect(x: 332, y: 84, width: 26, height: 10), cornerSize: CGSize(width: 5, height: 5))
        plus.addRoundedRect(in: CGRect(x: 340, y: 76, width: 10, height: 26), cornerSize: CGSize(width: 5, height: 5))
        fill(plus, pressed.contains(.plus))
        fill(roundRect(CGRect(x: 258, y: 112, width: 20, height: 20), 4), pressed.contains(.capture))
        fill(Path(ellipseIn: CGRect(x: 320, y: 110, width: 24, height: 24)), pressed.contains(.home))
        fill(roundRect(CGRect(x: 290, y: 150, width: 20, height: 20), 6), pressed.contains(.c))
        label("C", CGPoint(x: 300, y: 160), pressed.contains(.c), size: 11)
    }

    private func drawStick(
        _ ctx: inout GraphicsContext,
        center: CGPoint,
        value: SIMD2<Float>,
        trail: [SIMD2<Float>],
        isPressed: Bool
    ) {
        let radius: CGFloat = 42
        let travel: CGFloat = 30
        func point(_ v: SIMD2<Float>) -> CGPoint {
            CGPoint(x: center.x + CGFloat(v.x) * travel, y: center.y - CGFloat(v.y) * travel)
        }
        let ring = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        ctx.fill(ring, with: .color(theme.surfaceRaised))
        ctx.stroke(ring, with: .color(isPressed ? theme.accent : theme.divider), lineWidth: isPressed ? 4 : 2)

        // Dead-zone guide and crosshair.
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: center.x - travel, y: center.y))
            p.addLine(to: CGPoint(x: center.x + travel, y: center.y))
            p.move(to: CGPoint(x: center.x, y: center.y - travel))
            p.addLine(to: CGPoint(x: center.x, y: center.y + travel))
        }, with: .color(theme.divider.opacity(0.6)), lineWidth: 1)

        if trail.count > 1 {
            ctx.stroke(Path { p in
                p.move(to: point(trail[0]))
                for v in trail.dropFirst() { p.addLine(to: point(v)) }
            }, with: .color(theme.accent.opacity(0.45)), lineWidth: 2)
        }

        let dot = point(value)
        let moved = abs(value.x) > 0.1 || abs(value.y) > 0.1
        ctx.fill(Path(ellipseIn: CGRect(x: dot.x - 14, y: dot.y - 14, width: 28, height: 28)),
                 with: .color(moved || isPressed ? theme.accent : theme.textSecondary))
    }
}

/// The four player LEDs; the lit one shows the player number.
struct PlayerLights: View {
    let playerIndex: Int?

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    var body: some View {
        HStack(spacing: ui(5)) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: ui(2))
                    .fill(index == playerIndex ? Color(hex: 0x2BD957) : theme.divider)
                    .frame(width: ui(14), height: ui(5))
            }
        }
    }
}
