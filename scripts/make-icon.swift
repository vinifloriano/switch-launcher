// Draws the launcher icon (two Joy-Con-coloured halves on a dark rounded square) to a 1024px PNG.
import AppKit

let output = CommandLine.arguments[1]
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let base = NSBezierPath(roundedRect: rect.insetBy(dx: 100, dy: 100), xRadius: 185, yRadius: 185)
    NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
    base.fill()
    let halfWidth: CGFloat = 170, height: CGFloat = 520, gap: CGFloat = 26
    let y = (size - height) / 2
    let left = NSRect(x: size / 2 - gap / 2 - halfWidth, y: y, width: halfWidth, height: height)
    let right = NSRect(x: size / 2 + gap / 2, y: y, width: halfWidth, height: height)
    NSColor(srgbRed: 0, green: 0.765, blue: 0.89, alpha: 1).setFill()
    NSBezierPath(roundedRect: left, xRadius: 70, yRadius: 70).fill()
    NSColor(srgbRed: 1, green: 0.27, blue: 0.33, alpha: 1).setFill()
    NSBezierPath(roundedRect: right, xRadius: 70, yRadius: 70).fill()
    return true
}
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
