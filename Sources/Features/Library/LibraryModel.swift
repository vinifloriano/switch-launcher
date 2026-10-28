import DesignSystem
import InputKit
import LauncherCore
import Observation

/// "All Software": every installed title in a grid, with sorting.
@MainActor @Observable
public final class LibraryModel: InputResponder {
    static let columns = 6

    var sort: SoftwareSort = .recentlyPlayed
    var index = 0
    @ObservationIgnored unowned let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    var games: [Game] {
        LibraryOrdering.sort(app.library.games, by: sort, history: app.history.records)
    }

    var selectedGame: Game? {
        let all = games
        return all.indices.contains(index) ? all[index] : nil
    }

    public func handle(_ button: NintendoButton) {
        let count = games.count
        switch button {
        case .left: move(to: index - 1, count: count)
        case .right: move(to: index + 1, count: count)
        case .up: move(to: index - Self.columns, count: count)
        case .down: move(to: min(index + Self.columns, count - 1), count: count)
        case .a:
            if let game = selectedGame { app.launch(game) }
        case .plus, .minus:
            if let game = selectedGame { app.openOptions(for: game) }
        case .x:
            if let game = selectedGame { app.confirmClose(game) }
        case .y:
            sort = sort.next
            index = 0
            app.sound.play(.toggle)
        case .b:
            app.pop()
        default:
            break
        }
    }

    private func move(to newIndex: Int, count: Int) {
        guard newIndex >= 0, newIndex < count, newIndex != index else { return }
        index = newIndex
        app.sound.play(.move)
    }

    func tap(_ tapped: Int) {
        if tapped == index {
            handle(.a)
        } else {
            index = tapped
            app.sound.play(.move)
        }
    }
}
