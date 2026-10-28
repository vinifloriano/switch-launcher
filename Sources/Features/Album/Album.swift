import AppKit
import DesignSystem
import InputKit
import LauncherCore
import Observation
import SwiftUI

/// Album: screenshots from the Mac's screenshot folders, with a full-screen viewer.
@MainActor @Observable
public final class AlbumModel: InputResponder {
    static let columns = 4

    private(set) var items: [URL] = []
    private(set) var isLoading = true
    var index = 0
    var isViewing = false
    @ObservationIgnored unowned let app: AppModel

    init(app: AppModel) {
        self.app = app
        Task {
            items = await Task.detached(priority: .userInitiated) { ScreenshotLibrary.load() }.value
            isLoading = false
        }
    }

    var selected: URL? {
        items.indices.contains(index) ? items[index] : nil
    }

    public func handle(_ button: NintendoButton) {
        if isViewing {
            switch button {
            case .left: move(to: index - 1)
            case .right: move(to: index + 1)
            case .b, .a:
                isViewing = false
                app.sound.play(.back)
            case .plus:
                reveal()
            default: break
            }
            return
        }
        switch button {
        case .left: move(to: index - 1)
        case .right: move(to: index + 1)
        case .up: move(to: index - Self.columns)
        case .down: move(to: min(index + Self.columns, items.count - 1))
        case .a:
            guard selected != nil else { return }
            isViewing = true
            app.sound.play(.select)
        case .plus:
            reveal()
        case .b:
            app.pop()
        default: break
        }
    }

    private func move(to newIndex: Int) {
        guard items.indices.contains(newIndex), newIndex != index else { return }
        index = newIndex
        app.sound.play(.move)
    }

    private func reveal() {
        guard let selected else { return }
        app.sound.play(.select)
        NSWorkspace.shared.activateFileViewerSelecting([selected])
    }

    func tap(_ tapped: Int) {
        if tapped == index { handle(.a) } else { move(to: tapped) }
    }
}

struct AlbumView: View {
    let model: AlbumModel

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    var body: some View {
        ConsoleScaffold(
            title: "Album",
            icon: .symbol("photo.on.rectangle.angled"),
            trailing: model.isLoading ? nil : "\(model.items.count) screenshots",
            hints: hints
        ) {
            if model.items.isEmpty {
                Text(model.isLoading ? "Loading…" : "No screenshots yet. Press ⌘⇧3 in a game to take one.")
                    .font(ui.font(19))
                    .foregroundStyle(theme.textSecondary)
            } else {
                grid
            }
        } footerLeading: {
            if let url = model.selected {
                Text(url.lastPathComponent)
                    .font(ui.font(15))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .overlay {
            if model.isViewing, let url = model.selected {
                ZStack {
                    Color.black.ignoresSafeArea()
                    AsyncThumbnail(url: url, maxPixel: 2600)
                        .aspectRatio(contentMode: .fit)
                        .id(url)
                }
                .onTapGesture { model.handle(.b) }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.isViewing)
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(ui(262)), spacing: ui(20)), count: AlbumModel.columns),
                    spacing: ui(22)
                ) {
                    ForEach(Array(model.items.enumerated()), id: \.element) { index, url in
                        AsyncThumbnail(url: url, maxPixel: 600)
                            .frame(width: ui(262), height: ui(147))
                            .clipShape(RoundedRectangle(cornerRadius: ui(6), style: .continuous))
                            .selectionFrame(index == model.index, cornerRadius: ui(6))
                            .id(index)
                            .onTapGesture { model.tap(index) }
                    }
                }
                .padding(.vertical, ui(30))
            }
            .scrollIndicators(.never)
            .onChange(of: model.index) { _, index in
                withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(index) }
            }
        }
    }

    private var hints: [ButtonHint] {
        let app = model.app
        return [
            ButtonHint("+", "Show in Finder") { app.handle(.plus) },
            ButtonHint("B", "Back") { app.handle(.b) },
            ButtonHint("A", "View") { app.handle(.a) },
        ]
    }
}
