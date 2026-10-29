import DesignSystem
import LauncherCore

/// Software groups: create, open, edit (add or remove software, rename) and delete.
extension AppModel {
    func openGroup(_ id: String) {
        push(.library(LibraryModel(app: self, groupID: id)))
    }

    func createGroup() {
        guard let name = promptText("Create Group", message: "Name the group, e.g. Party Games."),
              !name.isEmpty else { return }
        let group = SoftwareGroup(name: String(name.prefix(30)))
        settings.value.groups.append(group)
        editGroup(group.id)
    }

    /// Group page: tick the software in the group, rename or delete it.
    func editGroup(_ id: String) {
        guard let group = settings.value.groups.first(where: { $0.id == id }) else { return }
        push(.menu(MenuModel(title: group.name, icon: .symbol("square.stack.fill"), app: self) { [unowned self] in
            guard let index = settings.value.groups.firstIndex(where: { $0.id == id }) else { return [] }
            let current = settings.value.groups[index]
            let games = LibraryOrdering.sort(library.games, by: .title, history: history.records)
            return [
                MenuSection(
                    id: "software", title: "Software", symbol: "square.grid.3x3.fill",
                    footnote: "\(current.gameIDs.count) in this group. Software can be in several groups.",
                    items: games.map { game in
                        MenuItem(id: game.id, title: game.title, image: IconCache.shared.icon(for: game),
                                 kind: .toggle(current.gameIDs.contains(game.id)) { [unowned self] isIn in
                                     guard let i = settings.value.groups.firstIndex(where: { $0.id == id }) else { return }
                                     settings.value.groups[i].gameIDs.removeAll { $0 == game.id }
                                     if isIn { settings.value.groups[i].gameIDs.append(game.id) }
                                 })
                    }
                ),
                MenuSection(id: "group", title: "Group", symbol: "square.stack.fill", items: [
                    MenuItem(id: "rename", title: "Rename", subtitle: current.name, symbol: "pencil",
                             kind: .action { [unowned self] in
                                 guard let name = promptText("Rename Group", message: "New name for the group.", value: current.name),
                                       !name.isEmpty,
                                       let i = settings.value.groups.firstIndex(where: { $0.id == id }) else { return }
                                 settings.value.groups[i].name = String(name.prefix(30))
                             }),
                    MenuItem(id: "delete", title: "Delete Group", subtitle: "The software itself stays.",
                             symbol: "trash.fill", isDestructive: true,
                             kind: .action { [unowned self] in
                                 confirm(message: "Delete the group \(current.name)?", detail: "The software in it isn't deleted.",
                                         confirmTitle: "Delete") { [unowned self] in
                                     settings.value.groups.removeAll { $0.id == id }
                                     // Leave this page and the deleted group's page under it.
                                     pop()
                                     if case .library(let model)? = stack.last, model.groupID == id { pop() }
                                 }
                             }),
                ]),
            ]
        }))
    }
}
