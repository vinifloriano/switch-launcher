import AppKit
import SwiftUI

public enum HeaderIcon {
    case symbol(String)
    case image(NSImage?)
    case avatar(symbol: String, color: Color)
}

/// Bottom bar: thin divider, optional leading content, button hints on the right.
public struct ConsoleFooter<Leading: View>: View {
    let hints: [ButtonHint]
    let leading: Leading

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    public init(hints: [ButtonHint], @ViewBuilder leading: () -> Leading) {
        self.hints = hints
        self.leading = leading()
    }

    public var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(theme.divider).frame(height: 1).padding(.horizontal, ui(30))
            HStack {
                leading
                Spacer()
                ButtonGuide(hints)
            }
            .padding(.horizontal, ui(60))
            .frame(height: ui(68))
        }
    }
}

public extension ConsoleFooter where Leading == EmptyView {
    init(hints: [ButtonHint]) {
        self.init(hints: hints) { EmptyView() }
    }
}

/// Standard full-screen page: icon + title header, content, footer with hints.
public struct ConsoleScaffold<Content: View, FooterLeading: View>: View {
    let title: String
    let icon: HeaderIcon
    let trailing: String?
    let hints: [ButtonHint]
    let content: Content
    let footerLeading: FooterLeading

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    public init(
        title: String,
        icon: HeaderIcon,
        trailing: String? = nil,
        hints: [ButtonHint],
        @ViewBuilder content: () -> Content,
        @ViewBuilder footerLeading: () -> FooterLeading
    ) {
        self.title = title
        self.icon = icon
        self.trailing = trailing
        self.hints = hints
        self.content = content()
        self.footerLeading = footerLeading()
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: ui(16)) {
                iconView
                Text(title)
                    .font(ui.font(28, .medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(ui.font(17))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .padding(.horizontal, ui(60))
            .frame(height: ui(86))
            Rectangle().fill(theme.divider).frame(height: 1).padding(.horizontal, ui(30))

            content.frame(maxWidth: .infinity, maxHeight: .infinity)

            ConsoleFooter(hints: hints) { footerLeading }
        }
        .background(theme.background)
    }

    @ViewBuilder private var iconView: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: ui(28), weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .frame(width: ui(44), height: ui(44))
        case .image(let image):
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: ui(48), height: ui(48))
                    .clipShape(RoundedRectangle(cornerRadius: ui(6), style: .continuous))
            }
        case .avatar(let symbol, let color):
            UserAvatar(symbol: symbol, color: color, diameter: ui(48))
        }
    }
}

public extension ConsoleScaffold where FooterLeading == EmptyView {
    init(
        title: String,
        icon: HeaderIcon,
        trailing: String? = nil,
        hints: [ButtonHint],
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, icon: icon, trailing: trailing, hints: hints, content: content) { EmptyView() }
    }
}
