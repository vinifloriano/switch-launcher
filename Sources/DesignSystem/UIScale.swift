import SwiftUI

/// Every metric in the UI is authored against a 1280×720 console screen and multiplied by this
/// factor, so text and strokes stay crisp at any window size (unlike `scaleEffect`).
public struct UIScale: Equatable, Sendable {
    public static let designSize = CGSize(width: 1280, height: 720)

    public var factor: CGFloat

    public init(_ factor: CGFloat = 1) {
        self.factor = factor
    }

    public func callAsFunction(_ value: CGFloat) -> CGFloat {
        value * factor
    }

    public func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * factor, weight: weight, design: .rounded)
    }
}

/// Fills the window and publishes the `ui` scale for the 1280×720 design grid.
public struct ConsoleCanvas<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        GeometryReader { geo in
            let factor = min(
                geo.size.width / UIScale.designSize.width,
                geo.size.height / UIScale.designSize.height
            )
            content
                .environment(\.ui, UIScale(max(factor, 0.4)))
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
