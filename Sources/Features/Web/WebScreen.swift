import AppKit
import DesignSystem
import InputKit
import Observation
import SwiftUI
import WebKit

/// In-launcher web page for Nintendo Switch Online, News and Nintendo eShop.
/// The mouse and keyboard go straight to the page; a controller scrolls (stick/D-pad),
/// goes back/forward (L/R), reloads (Y) and closes (B).
@MainActor @Observable
public final class WebModel: InputResponder {
    let title: String
    let symbol: String
    private(set) var pageTitle = ""
    private(set) var host = ""
    private(set) var progress: Double = 0
    private(set) var isLoading = true
    private(set) var canGoBack = false
    private(set) var canGoForward = false

    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored unowned let app: AppModel
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init(app: AppModel, title: String, symbol: String, url: URL) {
        self.app = app
        self.title = title
        self.symbol = symbol
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.underPageBackgroundColor = .clear

        observations = [
            webView.observe(\.title) { [weak self] view, _ in
                let value = view.title ?? ""
                Task { @MainActor in self?.pageTitle = value }
            },
            webView.observe(\.url) { [weak self] view, _ in
                let value = view.url?.host() ?? ""
                Task { @MainActor in self?.host = value }
            },
            webView.observe(\.estimatedProgress) { [weak self] view, _ in
                let value = view.estimatedProgress
                Task { @MainActor in self?.progress = value }
            },
            webView.observe(\.isLoading) { [weak self] view, _ in
                let value = view.isLoading
                Task { @MainActor in self?.isLoading = value }
            },
            webView.observe(\.canGoBack) { [weak self] view, _ in
                let value = view.canGoBack
                Task { @MainActor in self?.canGoBack = value }
            },
            webView.observe(\.canGoForward) { [weak self] view, _ in
                let value = view.canGoForward
                Task { @MainActor in self?.canGoForward = value }
            },
        ]
        webView.load(URLRequest(url: url))
    }

    public func handle(_ button: NintendoButton) {
        switch button {
        case .b:
            app.pop()
        case .l:
            if canGoBack { webView.goBack(); app.sound.play(.back) }
        case .r:
            if canGoForward { webView.goForward(); app.sound.play(.select) }
        case .y:
            webView.reload()
            app.sound.play(.toggle)
        case .up: scroll(y: -260)
        case .down: scroll(y: 260)
        case .left: scroll(x: -260)
        case .right: scroll(x: 260)
        case .plus:
            if let url = webView.url {
                app.sound.play(.select)
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }

    private func scroll(x: Int = 0, y: Int = 0) {
        webView.evaluateJavaScript("window.scrollBy({left: \(x), top: \(y), behavior: 'smooth'})")
    }
}

struct WebScreen: View {
    let model: WebModel

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    var body: some View {
        ConsoleScaffold(
            title: model.title,
            icon: .symbol(model.symbol),
            trailing: model.host,
            hints: hints
        ) {
            ZStack(alignment: .top) {
                WebViewHost(webView: model.webView)
                    .clipShape(RoundedRectangle(cornerRadius: ui(10), style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: ui(10), style: .continuous)
                            .strokeBorder(theme.divider, lineWidth: 1)
                    )
                if model.isLoading {
                    GeometryReader { geo in
                        Capsule()
                            .fill(theme.accent)
                            .frame(width: max(ui(20), geo.size.width * model.progress), height: ui(4))
                            .animation(.easeOut(duration: 0.2), value: model.progress)
                    }
                    .frame(height: ui(4))
                    .padding(.horizontal, ui(6))
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, ui(30))
            .padding(.vertical, ui(14))
        } footerLeading: {
            Text(model.pageTitle)
                .font(ui.font(15))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: ui(420), alignment: .leading)
        }
    }

    private var hints: [ButtonHint] {
        var hints: [ButtonHint] = []
        if model.canGoBack { hints.append(ButtonHint("L", "Back") { model.handle(.l) }) }
        if model.canGoForward { hints.append(ButtonHint("R", "Forward") { model.handle(.r) }) }
        hints.append(ButtonHint("Y", "Reload") { model.handle(.y) })
        hints.append(ButtonHint("+", "Open in Browser") { model.handle(.plus) })
        hints.append(ButtonHint("B", "Close") { model.app.handle(.b) })
        return hints
    }
}

private struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        DispatchQueue.main.async {
            webView.window?.makeFirstResponder(webView)
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
