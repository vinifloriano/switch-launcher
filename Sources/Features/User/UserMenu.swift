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
            [userSettingsSection, activitySection]
        }
    }

    private var userSettingsSection: MenuSection {
        let s = settings.value
        let mac = MacUsers.all().first(where: \.isCurrent)
        return MenuSection(
            id: "userSettings", title: "User Settings", symbol: "person.crop.circle.badge.checkmark",
            items: [
                MenuItem(id: "card", title: s.userName, subtitle: "Your profile on this launcher",
                         image: avatarImage(diameter: 56), kind: .info("")),
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
                .header("Mac Account"),
                MenuItem(id: "macUser", title: mac?.fullName ?? NSFullUserName(),
                         subtitle: "Signed in as \(NSUserName()) · save data is kept per Mac user",
                         image: mac?.picture ?? initialsImage(mac?.fullName ?? NSFullUserName()),
                         kind: .link { [unowned self] in push(.menu(makeSettingsMenu(startingAt: "users"))) }),
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
        guard let text = promptText("Nickname", message: "Enter a nickname of up to 10 characters.",
                                    value: settings.value.userName) else { return }
        let name = String(text.prefix(10))
        if !name.isEmpty { settings.value.userName = name }
    }

}
