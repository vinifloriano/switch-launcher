import AppKit
import DesignSystem
import SwiftUI

/// The whole launcher: HOME Menu, pushed screens, dialogs, toasts and the boot animation.
public struct RootView: View {
    let app: AppModel

    @Environment(\.colorScheme) private var colorScheme

    static let titleBarHeight: CGFloat = 28

    public init(app: AppModel) {
        self.app = app
    }

    public var body: some View {
        let theme = app.theme(systemIsDark: colorScheme == .dark)
        ConsoleCanvas {
            ZStack {
                theme.background.ignoresSafeArea()

                HomeView(app: app, home: app.home)

                ForEach(app.stack) { route in
                    screen(for: route)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 1.02)),
                            removal: .opacity
                        ))
                }

                if let quickSettings = app.quickSettings {
                    QuickSettingsPanel(model: quickSettings)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                if let game = app.launchingGame {
                    LaunchOverlay(game: game).transition(.opacity)
                }

                if let dialog = app.dialog {
                    DialogView(model: dialog).transition(.opacity)
                }

                if let toast = app.toast {
                    VStack {
                        ToastView(message: toast.text, symbol: toast.symbol)
                            .padding(.top, 24)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
                }

                if app.isBooting {
                    BootView(app: app).transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.18), value: app.stack.map(\.id))
            .animation(.easeOut(duration: 0.15), value: app.dialog == nil)
            .animation(.spring(duration: 0.3, bounce: 0.1), value: app.quickSettings == nil)
            .animation(.easeOut(duration: 0.25), value: app.launchingGame)
            .animation(.spring(duration: 0.3), value: app.toast)
            .animation(.easeInOut(duration: 0.5), value: app.isBooting)
        }
        // Room for the window buttons when not in full screen.
        .padding(.top, app.isFullScreen ? 0 : Self.titleBarHeight)
        .environment(\.theme, theme)
        .background(theme.background)
        .background(WindowConfigurator(app: app))
        .onAppear { app.start() }
    }

    @ViewBuilder private func screen(for route: Route) -> some View {
        switch route {
        case .library(let model): LibraryView(model: model)
        case .menu(let model): MenuView(model: model)
        case .album(let model): AlbumView(model: model)
        case .sleep(let model): SleepView(model: model)
        case .web(let model): WebScreen(model: model)
        case .controllers(let model): ControllersScreen(model: model)
        case .gripOrder(let model): GripOrderScreen(model: model)
        case .controllerTest(let model): ControllerTestScreen(model: model)
        }
    }
}

/// Console-style window: transparent title bar with the standard close / minimise / full-screen
/// buttons, optional full screen at launch. Reports full-screen changes to the app.
private struct WindowConfigurator: NSViewRepresentable {
    let app: AppModel

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.collectionBehavior.insert(.fullScreenPrimary)

            let center = NotificationCenter.default
            for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
                context.coordinator.observers.append(
                    center.addObserver(forName: name, object: window, queue: .main) { [weak window] _ in
                        MainActor.assumeIsolated {
                            app.isFullScreen = window?.styleMask.contains(.fullScreen) ?? false
                        }
                    }
                )
            }
            app.isFullScreen = window.styleMask.contains(.fullScreen)
            if app.settings.value.startFullScreen && !app.isFullScreen {
                window.toggleFullScreen(nil)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var observers: [NSObjectProtocol] = []
    }
}
