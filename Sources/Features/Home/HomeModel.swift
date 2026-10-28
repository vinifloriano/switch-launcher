import AppKit
import DesignSystem
import InputKit
import LauncherCore
import Observation
import SwiftUI

public enum HomeItem: Identifiable, Hashable {
    case game(Game)
    case allSoftware

    public var id: String {
        switch self {
        case .game(let game): game.id
        case .allSoftware: "all-software"
        }
    }

    var title: String {
        switch self {
        case .game(let game): game.title
        case .allSoftware: "All Software"
        }
    }
}

/// The round shortcuts along the bottom of the HOME Menu, in the console's order.
public enum DockItem: String, CaseIterable, Identifiable {
    case online, gameChat, news, eShop, album, gameShare, controllers, virtualGameCard, settings, sleep

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .online: "Nintendo Switch Online"
        case .gameChat: "GameChat"
        case .news: "News"
        case .eShop: "Game Store"
        case .album: "Album"
        case .gameShare: "GameShare"
        case .controllers: "Controllers"
        case .virtualGameCard: "Virtual Game Cards"
        case .settings: "System Settings"
        case .sleep: "Sleep Mode"
        }
    }

    var symbol: String {
        switch self {
        case .online: "globe"
        case .gameChat: "bubble.left.and.bubble.right.fill"
        case .news: "newspaper.fill"
        case .eShop: "bag.fill"
        case .album: "photo.on.rectangle.angled"
        case .gameShare: "person.2.wave.2.fill"
        case .controllers: "gamecontroller.fill"
        case .virtualGameCard: "sdcard.fill"
        case .settings: "gearshape.fill"
        case .sleep: "power"
        }
    }

    var tint: Color {
        switch self {
        case .online: Color(hex: 0xE60012)
        case .gameChat: Color(hex: 0xF29B00)
        case .news: Color(hex: 0xE4473A)
        case .eShop: Color(hex: 0xF57C00)
        case .album: Color(hex: 0x2E8AE6)
        case .gameShare: Color(hex: 0x2BB673)
        case .controllers: Color(hex: 0x6A6A6A)
        case .virtualGameCard: Color(hex: 0x8A5CF6)
        case .settings: Color(hex: 0x6A6A6A)
        case .sleep: Color(hex: 0x6A6A6A)
        }
    }
}

@MainActor @Observable
public final class HomeModel: InputResponder {
    public enum Row { case user, software, dock }

    var row: Row = .software
    var softwareIndex = 0
    var dockIndex = 0
    @ObservationIgnored unowned let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    var items: [HomeItem] {
        app.homeGames.map(HomeItem.game) + [.allSoftware]
    }

    var selectedItem: HomeItem? {
        let all = items
        return all.indices.contains(softwareIndex) ? all[softwareIndex] : all.last
    }

    /// Moves the cursor to a software tile (one step at a time, so the row scrolls like it does
    /// when you move with the controller).
    func select(_ index: Int) {
        row = .software
        let target = max(0, min(index, items.count - 1))
        Task {
            while softwareIndex != target {
                softwareIndex += softwareIndex < target ? 1 : -1
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    func selectFirstSoftware() {
        row = .software
        softwareIndex = 0
    }

    public func handle(_ button: NintendoButton) {
        let count = items.count
        softwareIndex = min(softwareIndex, count - 1)

        switch (row, button) {
        case (.software, .left):
            step(&softwareIndex, by: -1, count: count)
        case (.software, .right):
            step(&softwareIndex, by: 1, count: count)
        case (.software, .l):
            if softwareIndex != 0 { softwareIndex = 0; app.sound.play(.move) }
        case (.software, .r):
            if softwareIndex != count - 1 { softwareIndex = count - 1; app.sound.play(.move) }
        case (.software, .up):
            row = .user
            app.sound.play(.move)
        case (.software, .down):
            row = .dock
            app.sound.play(.move)
        case (.software, .a):
            activateSoftware()
        case (.software, .plus), (.software, .minus):
            if case .game(let game)? = selectedItem { app.openOptions(for: game) }
        case (.software, .x):
            if case .game(let game)? = selectedItem, app.launcher.runningGameID == game.id {
                app.confirmClose(game)
            }

        case (.dock, .left):
            step(&dockIndex, by: -1, count: DockItem.allCases.count)
        case (.dock, .right):
            step(&dockIndex, by: 1, count: DockItem.allCases.count)
        case (.dock, .up):
            row = .software
            app.sound.play(.move)
        case (.dock, .a):
            app.openDock(DockItem.allCases[dockIndex])

        case (.user, .down):
            row = .software
            app.sound.play(.move)
        case (.user, .a):
            app.openUserPage()

        case (_, .c):
            app.openDock(.gameChat)
        default:
            break
        }
    }

    private func step(_ index: inout Int, by delta: Int, count: Int) {
        let next = index + delta
        guard next >= 0, next < count else { return }
        index = next
        app.sound.play(.move)
    }

    func activateSoftware() {
        switch selectedItem {
        case .game(let game)?: app.launch(game)
        case .allSoftware?: app.openLibrary()
        case nil: break
        }
    }

    // Mouse
    func tapSoftware(_ index: Int) {
        if row == .software && index == softwareIndex {
            activateSoftware()
        } else {
            row = .software
            softwareIndex = index
            app.sound.play(.move)
        }
    }

    func tapDock(_ index: Int) {
        if row == .dock && index == dockIndex {
            app.openDock(DockItem.allCases[index])
        } else {
            row = .dock
            dockIndex = index
            app.sound.play(.move)
        }
    }

    func tapUser() {
        if row == .user {
            app.openUserPage()
        } else {
            row = .user
            app.sound.play(.move)
        }
    }

    var hints: [ButtonHint] {
        var hints: [ButtonHint] = []
        if row == .software, case .game(let game)? = selectedItem {
            if app.launcher.runningGameID == game.id {
                hints.append(ButtonHint("X", "Close") { [unowned self] in handle(.x) })
            }
            hints.append(ButtonHint("+", "Options") { [unowned self] in handle(.plus) })
            let verb = app.launcher.runningGameID == game.id ? "Resume" : "Start"
            hints.append(ButtonHint("A", verb) { [unowned self] in handle(.a) })
        } else {
            hints.append(ButtonHint("A", "OK") { [unowned self] in handle(.a) })
        }
        return hints
    }
}

extension AppModel {
    func openDock(_ item: DockItem) {
        switch item {
        case .online:
            openWeb("https://www.nintendo.com/us/switch/online/", item)
        case .news:
            openWeb("https://www.nintendo.com/us/whatsnew/", item)
        case .eShop:
            push(.store(StoreModel(app: self)))
        case .gameChat, .gameShare:
            sound.play(.error)
            showToast("\(item.title) isn't available on Mac.", symbol: "exclamationmark.bubble.fill")
        case .album:
            push(.album(AlbumModel(app: self)))
        case .controllers:
            push(.controllers(ControllersModel(app: self)))
        case .virtualGameCard:
            push(.menu(makeVirtualCardMenu()))
        case .settings:
            push(.menu(makeSettingsMenu()))
        case .sleep:
            replaceStack(stack + [.sleep(SleepModel(app: self))])
            sound.play(.back)
        }
    }

    private func openWeb(_ address: String, _ item: DockItem) {
        guard let url = URL(string: address) else { return }
        push(.web(WebModel(app: self, title: item.title, symbol: item.symbol, url: url)))
    }

    func openControllerTest() {
        push(.controllerTest(ControllerTestModel(app: self)))
    }

    func openGripOrder() {
        push(.gripOrder(GripOrderModel(app: self)))
    }

    func openLibrary() {
        push(.library(LibraryModel(app: self)))
    }

    func openOptions(for game: Game) {
        push(.menu(makeOptionsMenu(for: game)))
    }

    func openUserPage() {
        push(.menu(makeUserMenu()))
    }
}
