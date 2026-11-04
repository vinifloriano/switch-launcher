import DesignSystem
import SwiftUI

struct MenuView: View {
    let model: MenuModel

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    var body: some View {
        let sections = model.sections
        let sectionIndex = min(model.sectionIndex, max(sections.count - 1, 0))
        let single = sections.count == 1
        // Rows are built once per update and shared by the pane and the button guide.
        let section = sections.indices.contains(sectionIndex) ? sections[sectionIndex] : nil
        let items = section?.items ?? []

        ConsoleScaffold(title: model.title, icon: model.icon(), hints: hints(items)) {
            HStack(alignment: .top, spacing: 0) {
                if !single {
                    ScrollViewReader { sidebar in
                        ScrollView {
                            VStack(spacing: ui(4)) {
                                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                                    SidebarRow(
                                        title: section.title,
                                        symbol: section.symbol,
                                        isCurrent: index == sectionIndex,
                                        isFocused: model.focus == .sidebar && index == sectionIndex
                                    )
                                    .equatable()
                                    .scrollAnchor(index, vertical: ui(Self.scrollMargin))
                                    .onTapGesture { model.tapSection(index) }
                                }
                            }
                            .padding(.vertical, ui(26))
                            .padding(.horizontal, ui(30))
                        }
                        .scrollIndicators(.never)
                        .onChange(of: model.sectionIndex) { old, new in
                            reveal(new, previous: old, count: sections.count, in: sidebar, with: sidebarFollower)
                        }
                        // Pages opened on a later section (e.g. from a game's options) start there.
                        .task {
                            guard model.sectionIndex > 0 else { return }
                            sidebar.scrollTo(model.sectionIndex, anchor: .center)
                        }
                    }
                    .frame(width: ui(360))

                    Rectangle().fill(theme.divider).frame(width: 1)
                }

                if let section {
                    itemsPane(section, items: items)
                }
            }
        }
    }

    private func itemsPane(_ section: MenuSection, items: [MenuItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let footnote = section.footnote {
                        Text(footnote)
                            .font(ui.font(16))
                            .foregroundStyle(theme.textSecondary)
                            .padding(.horizontal, ui(18))
                            .padding(.bottom, ui(14))
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if case .header = item.kind {
                            Text(item.title.uppercased())
                                .font(ui.font(14, .semibold))
                                .tracking(ui(0.6))
                                .foregroundStyle(theme.textSecondary)
                                .padding(.horizontal, ui(18))
                                .padding(.top, index == 0 ? 0 : ui(26))
                                .padding(.bottom, ui(6))
                                .scrollAnchor(index, vertical: ui(Self.scrollMargin))
                        } else {
                        ItemRow(
                            title: item.title,
                            subtitle: item.subtitle,
                            image: item.image,
                            symbol: item.symbol,
                            accessory: accessory(for: item),
                            isFocused: model.focus == .items && index == model.itemIndex,
                            isDestructive: item.isDestructive,
                            meter: item.meter,
                            onSlide: slideAction(for: item)
                        )
                        .equatable()
                        .scrollAnchor(index, vertical: ui(Self.scrollMargin))
                        .onTapGesture { model.tapItem(index) }
                        }
                    }
                    if items.isEmpty {
                        Text("Nothing here yet.")
                            .font(ui.font(18))
                            .foregroundStyle(theme.textSecondary)
                            .padding(ui(18))
                    }
                }
                .padding(.vertical, ui(26))
                .padding(.horizontal, ui(40))
            }
            .scrollIndicators(.never)
            .onChange(of: model.itemIndex) { old, new in
                reveal(new, previous: old, count: items.count, in: proxy, with: itemsFollower)
            }
            .onChange(of: model.sectionIndex) { _, _ in
                itemsFollower.cancel()
                proxy.scrollTo(0, anchor: .top)
            }
        }
    }

    /// Room kept between the selection (and the row after it) and the top or bottom edge. It
    /// matches the lists' padding, so the first and last rows show it too.
    private static let scrollMargin: CGFloat = 26

    /// Scrolls so the selected row is visible with the next one in the direction of travel, so
    /// it never ends up against the edge (and under the bottom bar's line).
    private func reveal(_ index: Int, previous: Int, count: Int, in proxy: ScrollViewProxy, with follower: ScrollFollower) {
        let ahead = index > previous ? min(index + 1, count - 1) : max(index - 1, 0)
        follower.scroll(proxy, to: ahead, duration: 0.15)
    }

    @State private var sidebarFollower = ScrollFollower()
    @State private var itemsFollower = ScrollFollower()

    private func accessory(for item: MenuItem) -> ItemAccessory {
        switch item.kind {
        case .info(let value): .text(value)
        case .toggle(let isOn, _): .toggle(isOn)
        case .choice(let options, let index, _): .choice(options.indices.contains(index) ? options[index] : "")
        case .action: .none
        case .link: .chevron
        case .slider(let value, _): .slider(value)
        case .header: .none
        }
    }

    private func slideAction(for item: MenuItem) -> ((Double) -> Void)? {
        if case .slider(_, let set) = item.kind { return set }
        return nil
    }

    private func hints(_ items: [MenuItem]) -> [ButtonHint] {
        let focused = model.focus == .items && items.indices.contains(model.itemIndex) ? items[model.itemIndex] : nil
        var hints: [ButtonHint] = []
        if focused?.options != nil {
            hints.append(ButtonHint("+", "Options") { model.app.handle(.plus) })
        }
        hints.append(ButtonHint("B", "Back") { model.app.handle(.b) })
        // A slider row changes with left/right, shown by its − and + marks.
        if case .slider? = focused?.kind {} else {
            hints.append(ButtonHint("A", "OK") { model.app.handle(.a) })
        }
        return hints
    }
}
