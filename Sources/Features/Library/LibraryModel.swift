import DesignSystem
import InputKit
import LauncherCore
import Observation

/// "All Software": every installed title in a grid, with sorting, and the Groups tab (L/R).
/// The last tile adds software. Opened on a group, it shows only that group's software.
@MainActor @Observable
public final class LibraryModel: InputResponder {
    enum Tab { case all, groups }

    static let columns = 6

    var sort: SoftwareSort = .recentlyPlayed
    var tab: Tab = .all
    var index = 0
    var groupIndex = 0
    /// Set when this page shows one group.
    let groupID: String?
    @ObservationIgnored unowned let app: AppModel

    init(app: AppModel, groupID: String? = nil) {
        self.app = app
        self.groupID = groupID
    }

    var group: SoftwareGroup? {
        groupID.flatMap { id in app.settings.value.groups.first { $0.id == id } }
    }

    var title: String { group?.name ?? "All Software" }

    var games: [Game] {
        let all = LibraryOrdering.sort(app.library.games, by: sort, history: app.history.records)
        guard let group else { return all }
        return all.filter { group.gameIDs.contains($0.id) }
    }

    var groups: [SoftwareGroup] { app.settings.value.groups }

    /// Position of the last tile: Add Software, or Add/Remove Software in a group.
    var addIndex: Int { games.count }
    /// Position of the Create Group tile, after the last group.
    var createIndex: Int { groups.count }

    var selectedGame: Game? {
        let all = games
        return all.indices.contains(index) ? all[index] : nil
    }

    var selectedGroup: SoftwareGroup? {
        groups.indices.contains(groupIndex) ? groups[groupIndex] : nil
    }

    public func handle(_ button: NintendoButton) {
        if groupID == nil, button == .l || button == .r {
            let next: Tab = button == .l ? .all : .groups
            if next != tab {
                tab = next
                app.sound.play(.toggle)
            }
            return
        }
        if tab == .groups {
            handleGroups(button)
            return
        }
        // One tile more than there are titles: Add Software.
        let count = games.count + 1
        index = min(index, count - 1)
        switch button {
        case .left: move(&index, to: index - 1, count: count)
        case .right: move(&index, to: index + 1, count: count)
        case .up: move(&index, to: index - Self.columns, count: count)
        case .down: move(&index, to: min(index + Self.columns, count - 1), count: count)
        case .a:
            if let game = selectedGame {
                app.launch(game)
            } else if index == addIndex {
                app.sound.play(.select)
                if let groupID { app.editGroup(groupID) } else { app.addToLibrary() }
            }
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

    private func handleGroups(_ button: NintendoButton) {
        let count = groups.count + 1
        groupIndex = min(groupIndex, count - 1)
        switch button {
        case .left: move(&groupIndex, to: groupIndex - 1, count: count)
        case .right: move(&groupIndex, to: groupIndex + 1, count: count)
        case .up: move(&groupIndex, to: groupIndex - Self.columns, count: count)
        case .down: move(&groupIndex, to: min(groupIndex + Self.columns, count - 1), count: count)
        case .a:
            if let group = selectedGroup {
                app.openGroup(group.id)
            } else {
                app.sound.play(.select)
                app.createGroup()
            }
        case .plus, .minus:
            if let group = selectedGroup { app.editGroup(group.id) }
        case .b:
            app.pop()
        default:
            break
        }
    }

    private func move(_ value: inout Int, to newIndex: Int, count: Int) {
        guard newIndex >= 0, newIndex < count, newIndex != value else { return }
        value = newIndex
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

    func tapGroup(_ tapped: Int) {
        if tapped == groupIndex {
            handle(.a)
        } else {
            groupIndex = tapped
            app.sound.play(.move)
        }
    }

    func tapTab(_ newTab: Tab) {
        handle(newTab == .all ? .l : .r)
    }
}
