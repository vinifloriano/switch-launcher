import AppKit
import DesignSystem
import LauncherCore
import SwiftUI

/// Data Management (drives, software by size, library folders) and Users (Mac accounts, save data).
extension AppModel {
    var dataSection: MenuSection {
        let games = library.games
        let usage = storage.software
        let measured = games.compactMap { usage[$0.id] }
        let drives = StorageUsage.drives()
        let gameDrive = Dictionary(uniqueKeysWithValues: games.map { ($0.id, StorageUsage.volume(for: $0.url)?.url) })
        let saveTotal = storage.saves.reduce(0) { $0 + $1.size }

        var items: [MenuItem] = [.header("Storage")]
        for drive in drives {
            let software = games.filter { gameDrive[$0.id] == drive.url }.compactMap { usage[$0.id]?.app }.reduce(0, +)
            let saves: Int64 = drive.url.path == "/" ? saveTotal : 0
            let other = max(drive.used - software - saves, 0)
            let total = Double(max(drive.total, 1))
            var segments = [
                MeterSegment(id: "software", label: "Software", detail: ByteFormatter.string(software),
                             fraction: Double(software) / total, color: Color(hex: 0x00B4E6)),
            ]
            if drive.url.path == "/" {
                segments.append(MeterSegment(id: "saves", label: "Save Data", detail: ByteFormatter.string(saves),
                                             fraction: Double(saves) / total, color: Color(hex: 0x2BB673)))
            }
            segments += [
                MeterSegment(id: "other", label: "Other", detail: ByteFormatter.string(other),
                             fraction: Double(other) / total, color: Color(hex: 0x9A9A9A)),
                MeterSegment(id: "free", label: "Free", detail: ByteFormatter.string(drive.available),
                             fraction: 0, color: Color(hex: 0xD0D0D0)),
            ]
            items.append(MenuItem(
                id: "drive:" + drive.id,
                title: drive.url.path == "/" ? "\(drive.name) · System Memory" : "\(drive.name) · External",
                subtitle: "\(ByteFormatter.string(drive.available)) free of \(ByteFormatter.string(drive.total))",
                symbol: drive.isInternal ? "internaldrive.fill" : "externaldrive.fill",
                meter: Meter(segments: segments),
                kind: .info("")
            ))
        }

        let progress = measured.count == games.count ? "" : " · measuring \(measured.count) of \(games.count)…"
        items += [
            .header("Software"),
            MenuItem(id: "softwareTotal", title: "All Software", subtitle: "\(games.count) titles\(progress)",
                     kind: .info(ByteFormatter.string(measured.reduce(0) { $0 + $1.app }))),
        ]
        let several = drives.count > 1
        let sorted = games.sorted { (usage[$0.id]?.total ?? -1) > (usage[$1.id]?.total ?? -1) }
        items += sorted.map { game in
            var parts: [String] = []
            if let move = storage.moving[game.id] {
                parts.append("Moving… \(Int(move * 100))%")
            } else if let size = usage[game.id] {
                parts.append(ByteFormatter.string(size.app))
                if size.data > 0 { parts.append("save data \(ByteFormatter.string(size.data))") }
            } else {
                parts.append("Measuring…")
            }
            if several, let drive = drives.first(where: { $0.url == gameDrive[game.id] }) { parts.append(drive.name) }
            return MenuItem(id: "size:" + game.id, title: game.title, subtitle: parts.joined(separator: " · "),
                            image: IconCache.shared.icon(for: game),
                            options: { [unowned self] in confirmMove(game) },
                            kind: .link { [unowned self] in openOptions(for: game) })
        }
        items.append(.header("Library Folders"))
        items += libraryItems
        return MenuSection(
            id: "data", title: "Data Management", symbol: "externaldrive.fill",
            footnote: "Select software to see its details or delete it. Press + to move it to another drive.",
            items: items
        )
    }

    var usersSection: MenuSection {
        let users = MacUsers.all()
        let current = users.first(where: \.isCurrent)
        var items: [MenuItem] = [.header("Users on This Mac")]
        items += users.map { user in
            MenuItem(id: "user:" + user.id, title: user.fullName,
                     subtitle: user.isCurrent ? "Signed in · \(user.accountName)" : user.accountName,
                     image: user.picture ?? initialsImage(user.fullName),
                     kind: .info(user.isCurrent ? "Playing now" : ""))
        }
        items += [
            .header("Launcher Profile"),
            MenuItem(id: "profile", title: settings.value.userName, subtitle: "Nickname, icon and play activity",
                     image: avatarImage(), kind: .link { [unowned self] in openUserPage() }),
        ]
        let saves = storage.saves
        items.append(.header("Save Data · \(current?.fullName ?? NSFullUserName())"))
        items.append(MenuItem(id: "savesTotal", title: "Total", subtitle: "\(saves.count) titles",
                              kind: .info(ByteFormatter.string(saves.reduce(0) { $0 + $1.size }))))
        items += saves.map { save in
            let game = library.games.first { $0.titleID?.uppercased() == save.titleID }
            return MenuItem(id: "save:" + save.titleID, title: saveTitle(save),
                            subtitle: "\(game == nil ? "Not installed" : "Installed") · \(ByteFormatter.string(save.size))",
                            image: game.flatMap { IconCache.shared.icon(for: $0) },
                            symbol: game == nil ? "externaldrive.badge.person.crop" : nil,
                            kind: .action { [unowned self] in confirmDeleteSave(save) })
        }
        let others = users.filter { !$0.isCurrent }
        return MenuSection(
            id: "users", title: "Users", symbol: "person.2.fill",
            footnote: "Each person on this Mac has their own save data. It stays when software is deleted and comes back when it's installed again, from the Game Store too. Select a title to delete its save data."
                + (others.isEmpty ? "" : " To see \(others.map(\.fullName).joined(separator: ", "))'s save data, sign in to the Mac as them."),
            items: items
        )
    }
}
