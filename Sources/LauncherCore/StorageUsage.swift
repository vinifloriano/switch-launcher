import Foundation
import Observation

/// Space on one disk, as Finder reports it.
public struct VolumeUsage: Hashable, Sendable {
    public let name: String
    public let url: URL
    public let total: Int64
    public let available: Int64

    public var used: Int64 { max(total - available, 0) }
}

/// Space one title takes: the app itself and what it keeps in Application Support (saves, shader
/// caches, temporary files).
public struct SoftwareUsage: Hashable, Sendable {
    public let app: Int64
    public let data: Int64

    public var total: Int64 { app + data }
}

/// Save data of one title, installed or not: `~/Library/Application Support/nxnative/<title ID>`.
public struct SaveData: Identifiable, Hashable, Sendable {
    public let titleID: String
    public let url: URL
    public let size: Int64

    public var id: String { titleID }
}

/// Measures and frees the space software takes. Sizes are measured in the background on request
/// and kept for the session, since walking a 15 GB bundle takes a moment.
@MainActor @Observable
public final class StorageUsage {
    public private(set) var software: [String: SoftwareUsage] = [:]
    public private(set) var isMeasuring = false
    /// Every title's save data on this Mac, largest first. Filled by `measureSaves()`.
    public private(set) var saves: [SaveData] = []
    /// Names of titles seen in the library, by title ID, so save data still has a name once its
    /// software is deleted.
    public private(set) var knownTitles: [String: String] = [:]
    @ObservationIgnored private var pending: [Game] = []
    @ObservationIgnored private let titlesFile = AppPaths.supportDirectory.appendingPathComponent("titles.json")

    public init() {
        if let data = try? Data(contentsOf: titlesFile),
           let titles = try? JSONDecoder().decode([String: String].self, from: data) {
            knownTitles = titles
        }
    }

    /// Remembers the names of these titles for their save data.
    public func remember(_ games: [Game]) {
        var titles = knownTitles
        for game in games {
            if let id = game.titleID?.uppercased(), !id.isEmpty { titles[id] = game.title }
        }
        guard titles != knownTitles else { return }
        knownTitles = titles
        if let data = try? JSONEncoder().encode(titles) { try? data.write(to: titlesFile, options: .atomic) }
    }

    /// Lists and measures the save data of every title, installed or not.
    public func measureSaves() {
        Task {
            saves = await Task.detached(priority: .utility) { Self.findSaves() }.value
        }
    }

    public func hasSaveData(titleID: String?) -> Bool {
        guard let titleID, !titleID.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: Self.savesRoot.appendingPathComponent(titleID.uppercased()).path)
    }

    /// Moves one title's save data to the Trash.
    public func trash(_ save: SaveData) throws {
        try FileManager.default.trashItem(at: save.url, resultingItemURL: nil)
        saves.removeAll { $0.titleID == save.titleID }
    }

    nonisolated static var savesRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("nxnative", isDirectory: true)
    }

    nonisolated static func findSaves() -> [SaveData] {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: savesRoot, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        return folders
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { SaveData(titleID: $0.lastPathComponent.uppercased(), url: $0, size: size(of: $0)) }
            .sorted { $0.size > $1.size }
    }

    /// Measures every title not measured yet.
    public func measure(_ games: [Game]) {
        let new = games.filter { software[$0.id] == nil && !pending.contains($0) }
        guard !new.isEmpty else { return }
        pending += new
        guard !isMeasuring else { return }
        isMeasuring = true
        Task {
            while let game = pending.first {
                let usage = await Task.detached(priority: .utility) {
                    SoftwareUsage(app: Self.size(of: game.url),
                                  data: Self.dataFolder(for: game).map(Self.size(of:)) ?? 0)
                }.value
                software[game.id] = usage
                pending.removeFirst()
            }
            isMeasuring = false
        }
    }

    /// Measures one title again, e.g. after its save data was deleted.
    public func remeasure(_ game: Game) {
        software[game.id] = nil
        measure([game])
    }

    public func forget(_ game: Game) {
        software[game.id] = nil
    }

    /// The disk that holds `url`.
    public nonisolated static func volume(for url: URL) -> VolumeUsage? {
        let keys: Set<URLResourceKey> = [.volumeURLKey, .volumeLocalizedNameKey, .volumeTotalCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else { return nil }
        // "Important usage" counts purgeable space as free, like Finder; network shares don't report it.
        let available = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
        return VolumeUsage(name: values.volumeLocalizedName ?? url.lastPathComponent,
                           url: values.volume ?? url,
                           total: Int64(total),
                           available: available)
    }

    /// Where an nxnative port keeps its save data and caches:
    /// `~/Library/Application Support/nxnative/<title ID>`.
    public nonisolated static func dataFolder(for game: Game) -> URL? {
        guard let titleID = game.titleID, !titleID.isEmpty else { return nil }
        let url = savesRoot.appendingPathComponent(titleID.uppercased(), isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Moves the app to the Trash, with the packer's `<name>.app.key` beside it.
    public nonisolated static func trashSoftware(_ game: Game) throws {
        try FileManager.default.trashItem(at: game.url, resultingItemURL: nil)
        let key = keyFile(for: game.url)
        if FileManager.default.fileExists(atPath: key.path) {
            try? FileManager.default.trashItem(at: key, resultingItemURL: nil)
        }
    }

    /// The packer's record of what went into an app: `<name>.app.key` beside it.
    nonisolated static func keyFile(for app: URL) -> URL {
        app.deletingLastPathComponent().appendingPathComponent(app.lastPathComponent + ".key")
    }

    /// Space a file or folder takes on disk.
    public nonisolated static func size(of url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        if let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }
}
