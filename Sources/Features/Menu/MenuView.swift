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

        ConsoleScaffold(title: model.title, icon: model.icon(), hints: hints) {
            HStack(alignment: .top, spacing: 0) {
                if !single {
                    ScrollView {
                        VStack(spacing: ui(4)) {
                            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                                SidebarRow(
                                    title: section.title,
                                    symbol: section.symbol,
                                    isCurrent: index == sectionIndex,
                                    isFocused: model.focus == .sidebar && index == sectionIndex
                                )
                                .onTapGesture { model.tapSection(index) }
                            }
                        }
                        .padding(.vertical, ui(26))
                        .padding(.horizontal, ui(30))
                    }
                    .scrollIndicators(.never)
                    .frame(width: ui(360))

                    Rectangle().fill(theme.divider).frame(width: 1)
                }

                if sections.indices.contains(sectionIndex) {
                    itemsPane(sections[sectionIndex])
                }
            }
        }
    }

    private func itemsPane(_ section: MenuSection) -> some View {
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
                    ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                        ItemRow(
                            title: item.title,
                            subtitle: item.subtitle,
                            image: item.image,
                            symbol: item.symbol,
                            accessory: accessory(for: item),
                            isFocused: model.focus == .items && index == model.itemIndex,
                            isDestructive: item.isDestructive
                        )
                        .id(index)
                        .onTapGesture { model.tapItem(index) }
                    }
                    if section.items.isEmpty {
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
            .onChange(of: model.itemIndex) { _, index in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(index) }
            }
            .onChange(of: model.sectionIndex) { _, _ in
                proxy.scrollTo(0, anchor: .top)
            }
        }
    }

    private func accessory(for item: MenuItem) -> ItemAccessory {
        switch item.kind {
        case .info(let value): .text(value)
        case .toggle(let isOn, _): .toggle(isOn)
        case .choice(let options, let index, _): .choice(options.indices.contains(index) ? options[index] : "")
        case .action: .none
        case .link: .chevron
        }
    }

    private var hints: [ButtonHint] {
        [
            ButtonHint("B", "Back") { model.app.handle(.b) },
            ButtonHint("A", "OK") { model.app.handle(.a) },
        ]
    }
}
