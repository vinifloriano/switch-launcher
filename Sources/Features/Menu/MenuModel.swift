import AppKit
import DesignSystem
import InputKit
import Observation

public struct MenuItem: Identifiable {
    public enum Kind {
        /// Read-only value, not focusable.
        case info(String)
        case toggle(Bool, (Bool) -> Void)
        /// Options, current index, setter. A cycles to the next option.
        case choice([String], Int, (Int) -> Void)
        case action(() -> Void)
        /// Opens another page.
        case link(() -> Void)
        /// A level from 0 to 1; left/right change it in steps.
        case slider(Double, (Double) -> Void)
        /// A small heading that groups the rows below it. Not focusable.
        case header
    }

    public let id: String
    public let title: String
    public var subtitle: String?
    public var image: NSImage?
    public var symbol: String?
    public var isDestructive = false
    public let kind: Kind
    /// A bar shown under the row, e.g. disk usage.
    public var meter: Meter?
    /// What + does on this row (e.g. software options).
    public var options: (() -> Void)?

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        image: NSImage? = nil,
        symbol: String? = nil,
        isDestructive: Bool = false,
        meter: Meter? = nil,
        options: (() -> Void)? = nil,
        kind: Kind
    ) {
        self.meter = meter
        self.options = options
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.image = image
        self.symbol = symbol
        self.isDestructive = isDestructive
        self.kind = kind
    }

    var isFocusable: Bool {
        switch kind {
        case .info, .header: false
        default: true
        }
    }

    /// A heading row: `MenuItem.header("Wi-Fi")`.
    static func header(_ title: String) -> MenuItem {
        MenuItem(id: "header:" + title, title: title, kind: .header)
    }
}

public struct MenuSection: Identifiable {
    public let id: String
    public let title: String
    public var symbol: String?
    public var footnote: String?
    public var items: [MenuItem]

    public init(id: String, title: String, symbol: String? = nil, footnote: String? = nil, items: [MenuItem]) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.footnote = footnote
        self.items = items
    }
}

/// Generic two-pane page (categories on the left, items on the right). System Settings, My Page,
/// software options, Controllers and Virtual Game Cards are all built from this.
/// Sections are rebuilt on every read, so the page always reflects current state.
@MainActor @Observable
public final class MenuModel: InputResponder {
    enum Focus { case sidebar, items }

    let title: String
    let icon: () -> HeaderIcon
    var sectionIndex = 0
    var itemIndex = 0
    var focus: Focus = .sidebar
    @ObservationIgnored unowned let app: AppModel
    @ObservationIgnored private let build: () -> [MenuSection]

    init(title: String, icon: @escaping @autoclosure () -> HeaderIcon, app: AppModel, build: @escaping () -> [MenuSection]) {
        self.title = title
        self.icon = icon
        self.app = app
        self.build = build
        let sections = build()
        if sections.count == 1 {
            focus = .items
            itemIndex = sections[0].items.firstIndex(where: \.isFocusable) ?? 0
        }
    }

    var sections: [MenuSection] { build() }

    /// The row with the selection, when the right-hand pane has focus.
    var focusedItem: MenuItem? {
        guard focus == .items, let items = currentSection?.items, items.indices.contains(itemIndex) else { return nil }
        return items[itemIndex]
    }

    var currentSection: MenuSection? {
        let all = sections
        guard !all.isEmpty else { return nil }
        return all[min(sectionIndex, all.count - 1)]
    }

    public func handle(_ button: NintendoButton) {
        let all = sections
        guard !all.isEmpty else {
            if button == .b { app.pop() }
            return
        }
        sectionIndex = min(sectionIndex, all.count - 1)
        let single = all.count == 1
        let items = all[sectionIndex].items
        let focusable = items.indices.filter { items[$0].isFocusable }

        switch focus {
        case .sidebar:
            switch button {
            case .up where sectionIndex > 0:
                sectionIndex -= 1
                itemIndex = 0
                app.sound.play(.move)
            case .down where sectionIndex < all.count - 1:
                sectionIndex += 1
                itemIndex = 0
                app.sound.play(.move)
            case .right, .a:
                if let first = focusable.first {
                    focus = .items
                    itemIndex = first
                    app.sound.play(.move)
                }
            case .b:
                app.pop()
            default:
                break
            }
        case .items:
            let position = focusable.firstIndex(of: itemIndex)
            switch button {
            case .up:
                if let position, position > 0 {
                    itemIndex = focusable[position - 1]
                    app.sound.play(.move)
                }
            case .down:
                if let position, position < focusable.count - 1 {
                    itemIndex = focusable[position + 1]
                    app.sound.play(.move)
                } else if position == nil, let first = focusable.first {
                    itemIndex = first
                }
            case .left, .right:
                if items.indices.contains(itemIndex), case .slider(let value, let set) = items[itemIndex].kind {
                    let step = 1.0 / 16
                    let next = min(max(value + (button == .right ? step : -step), 0), 1)
                    if next != value {
                        set(next)
                        app.sound.play(.move)
                    }
                } else if button == .left, !single {
                    focus = .sidebar
                    app.sound.play(.move)
                }
            case .plus:
                if items.indices.contains(itemIndex), let options = items[itemIndex].options {
                    app.sound.play(.select)
                    options()
                }
            case .b:
                if single {
                    app.pop()
                } else {
                    focus = .sidebar
                    app.sound.play(.back)
                }
            case .a:
                if items.indices.contains(itemIndex) { activate(items[itemIndex]) }
            default:
                break
            }
        }
    }

    func activate(_ item: MenuItem) {
        switch item.kind {
        case .info:
            break
        case .toggle(let isOn, let set):
            app.sound.play(.toggle)
            set(!isOn)
        case .choice(let options, let index, let set):
            app.sound.play(.toggle)
            set((index + 1) % max(options.count, 1))
        case .action(let perform):
            app.sound.play(.select)
            perform()
        case .link(let open):
            open()
        case .slider, .header:
            break
        }
    }

    // Mouse
    func tapSection(_ index: Int) {
        guard index != sectionIndex || focus != .sidebar else { return }
        sectionIndex = index
        itemIndex = 0
        focus = .sidebar
        app.sound.play(.move)
    }

    func tapItem(_ index: Int) {
        guard let items = currentSection?.items, items.indices.contains(index), items[index].isFocusable else { return }
        focus = .items
        itemIndex = index
        activate(items[index])
    }
}
