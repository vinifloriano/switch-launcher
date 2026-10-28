import Foundation
import Observation

@MainActor @Observable
public final class GameLibrary {
    public private(set) var games: [Game] = []
    public private(set) var isScanning = false
    @ObservationIgnored private let scanner = GameScanner()

    public init() {}

    public func reload(folders: [URL], extraApps: [URL]) async {
        isScanning = true
        let scanner = scanner
        let found = await Task.detached(priority: .userInitiated) {
            scanner.scan(folders: folders, extraApps: extraApps)
        }.value
        games = found
        isScanning = false
        Log.library.info("Found \(found.count) titles in \(folders.count) folders")
    }

    public func game(id: String) -> Game? {
        games.first { $0.id == id }
    }
}
