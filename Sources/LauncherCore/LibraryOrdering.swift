import Foundation

public enum SoftwareSort: String, CaseIterable, Sendable {
    case recentlyPlayed, playTime, title, recentlyAdded

    public var displayName: String {
        switch self {
        case .recentlyPlayed: "Most Recently Played"
        case .playTime: "Longest Play Time"
        case .title: "Title"
        case .recentlyAdded: "Recently Added"
        }
    }

    public var next: SoftwareSort {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

public enum LibraryOrdering {
    public static func sort(_ games: [Game], by order: SoftwareSort, history: [String: PlayRecord]) -> [Game] {
        func byTitle(_ a: Game, _ b: Game) -> Bool {
            a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
        switch order {
        case .title:
            return games.sorted(by: byTitle)
        case .playTime:
            return games.sorted { a, b in
                let ta = history[a.id]?.totalSeconds ?? 0
                let tb = history[b.id]?.totalSeconds ?? 0
                return ta != tb ? ta > tb : byTitle(a, b)
            }
        case .recentlyAdded:
            return games.sorted { a, b in
                let da = a.addedDate ?? .distantPast
                let db = b.addedDate ?? .distantPast
                return da != db ? da > db : byTitle(a, b)
            }
        case .recentlyPlayed:
            // Like the console: newly installed software appears up front too, so rank by the
            // most recent of "last played" and "installed".
            func activity(_ g: Game) -> Date {
                max(history[g.id]?.lastPlayed ?? .distantPast, g.addedDate ?? .distantPast)
            }
            func played(_ g: Game) -> Bool { history[g.id]?.lastPlayed != nil }
            return games.sorted { a, b in
                if played(a) != played(b) { return played(a) }
                let da = activity(a)
                let db = activity(b)
                return da != db ? da > db : byTitle(a, b)
            }
        }
    }
}
