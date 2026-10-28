import AppKit
import DesignSystem
import LauncherCore

extension AppModel {
    /// "My Page": profile and play activity.
    func makeUserMenu() -> MenuModel {
        MenuModel(
            title: settings.value.userName,
            icon: .avatar(
                symbol: self.settings.value.avatarSymbol,
                color: AvatarPalette.color(at: self.settings.value.avatarColorIndex)
            ),
            app: self
        ) { [unowned self] in
            [profileSection, activitySection]
        }
    }

    private var profileSection: MenuSection {
        let s = settings.value
        return MenuSection(
            id: "profile", title: "Profile", symbol: "person.crop.circle.fill",
            items: [
                MenuItem(id: "name", title: "Nickname", subtitle: s.userName, symbol: "pencil",
                         kind: .action { [unowned self] in editNickname() }),
                MenuItem(id: "icon", title: "Icon", kind: .choice(
                    AvatarPalette.symbolNames,
                    AvatarPalette.symbols.firstIndex(of: s.avatarSymbol) ?? 0
                ) { [unowned self] in
                    settings.value.avatarSymbol = AvatarPalette.symbols[$0]
                }),
                MenuItem(id: "color", title: "Background", kind: .choice(
                    AvatarPalette.colorNames,
                    s.avatarColorIndex % AvatarPalette.colors.count
                ) { [unowned self] in
                    settings.value.avatarColorIndex = $0
                }),
            ]
        )
    }

    private var activitySection: MenuSection {
        let played = library.games
            .filter { history.record(for: $0.id).lastPlayed != nil }
            .sorted { history.record(for: $0.id).totalSeconds > history.record(for: $1.id).totalSeconds }
        let total = played.reduce(0) { $0 + history.record(for: $1.id).totalSeconds }
        return MenuSection(
            id: "activity", title: "Play Activity", symbol: "chart.bar.fill",
            footnote: played.isEmpty
                ? "Software you play will show up here."
                : "Total play time: \(PlayTimeFormatter.duration(total))",
            items: played.map { game in
                let record = history.record(for: game.id)
                return MenuItem(
                    id: game.id,
                    title: game.title,
                    subtitle: "Played for \(PlayTimeFormatter.duration(record.totalSeconds)) · First played \(PlayTimeFormatter.relative(record.firstPlayed))",
                    image: IconCache.shared.icon(for: game),
                    kind: .info(PlayTimeFormatter.relative(record.lastPlayed))
                )
            }
        )
    }

    private func editNickname() {
        let alert = NSAlert()
        alert.messageText = "Nickname"
        alert.informativeText = "Enter a nickname of up to 10 characters."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = settings.value.userName
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = String(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).prefix(10))
        if !name.isEmpty { settings.value.userName = name }
    }
}
