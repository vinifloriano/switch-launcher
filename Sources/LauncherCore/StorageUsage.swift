import Foundation
import Observation

/// Space on one disk, as Finder reports it.
public struct VolumeUsage: Hashable, Sendable, Identifiable {
    public let name: String
    public let url: URL
    public let total: Int64
    public let available: Int64
    /// The Mac's own disk, as opposed to an external drive or card.
    public var isInternal = true

    public var id: String { url.path }
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

/// An app's measured size, with what identified the bundle when it was measured.
struct CachedAppSize: Codable, Equatable, Sendable {
    let stamp: String
    let size: Int64
    /// Save data size last measured, shown until it's measured again.
    var data: Int64?
}

/// Measures and frees the space software takes. Walking a 15 GB bundle takes a moment, so app
/// sizes are kept in `app-sizes.json` and measured again only when the app changes. Save data
/// changes while playing and is small to walk, so it's measured every time.
@MainActor @Observable
public final class StorageUsage {
    public private(set) var software: [String: SoftwareUsage] = [:]
    public private(set) var isMeasuring = false
    /// Every title's save data on this Mac, largest first. Filled by `measureSaves()`.
    public private(set) var saves: [SaveData] = []
    /// Names of titles seen in the library, by title ID, so save data still has a name once its
    /// software is deleted.
    public private(set) var knownTitles: [String: String] = [:]
    /// Software being moved to another drive, by game id: progress 0...1.
    public private(set) var moving: [String: Double] = [:]
    @ObservationIgnored private var pending: [Game] = []
    @ObservationIgnored private let titlesFile = AppPaths.supportDirectory.appendingPathComponent("titles.json")
    @ObservationIgnored private let sizesFile: URL
    /// App sizes by game id, saved between launches.
    @ObservationIgnored private var appSizes: [String: CachedAppSize] = [:]

    public init(sizesFile: URL = AppPaths.supportDirectory.appendingPathComponent("app-sizes.json")) {
        self.sizesFile = sizesFile
        if let data = try? Data(contentsOf: sizesFile),
           let sizes = try? JSONDecoder().decode([String: CachedAppSize].self, from: data) {
            appSizes = sizes
        }
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
        // Show cached sizes right away; save data is refreshed below.
        for game in new {
            if let cached = appSizes[game.id], cached.stamp == Self.stamp(for: game) {
                software[game.id] = SoftwareUsage(app: cached.size, data: cached.data ?? 0)
            }
        }
        pending += new
        guard !isMeasuring else { return }
        isMeasuring = true
        Task {
            var changed = false
            while let game = pending.first {
                let cached = appSizes[game.id]
                let (usage, fresh) = await Task.detached(priority: .utility) { () -> (SoftwareUsage, CachedAppSize) in
                    let stamp = Self.stamp(for: game)
                    let app = cached?.stamp == stamp ? cached!.size : Self.size(of: game.url)
                    let data = Self.dataFolder(for: game).map(Self.size(of:)) ?? 0
                    return (SoftwareUsage(app: app, data: data), CachedAppSize(stamp: stamp, size: app, data: data))
                }.value
                software[game.id] = usage
                if fresh != cached {
                    appSizes[game.id] = fresh
                    changed = true
                }
                pending.removeFirst()
            }
            isMeasuring = false
            if changed { saveAppSizes() }
        }
    }

    private func saveAppSizes() {
        if let data = try? JSONEncoder().encode(appSizes) { try? data.write(to: sizesFile, options: .atomic) }
    }

    /// Changes when the app is replaced or updated: its path, version and Info.plist date.
    nonisolated static func stamp(for game: Game) -> String {
        let plist = game.url.appendingPathComponent("Contents/Info.plist")
        let modified = (try? plist.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return [game.url.path, game.version ?? "", modified.map { String($0.timeIntervalSince1970) } ?? ""]
            .joined(separator: "|")
    }

    /// Measures one title again, e.g. after its save data was deleted.
    public func remeasure(_ game: Game) {
        software[game.id] = nil
        measure([game])
    }

    public func forget(_ game: Game) {
        software[game.id] = nil
        if appSizes.removeValue(forKey: game.id) != nil { saveAppSizes() }
    }

    /// The disk that holds `url`.
    public nonisolated static func volume(for url: URL) -> VolumeUsage? {
        let keys: Set<URLResourceKey> = [.volumeURLKey, .volumeLocalizedNameKey, .volumeTotalCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
                                         .volumeIsInternalKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else { return nil }
        // "Important usage" counts purgeable space as free, like Finder; network shares don't report it.
        let available = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
        return VolumeUsage(name: values.volumeLocalizedName ?? url.lastPathComponent,
                           url: values.volume ?? url,
                           total: Int64(total),
                           available: available,
                           isInternal: values.volumeIsInternal ?? true)
    }

    /// Drives software can live on: the Mac's disk and writable local drives (external SSDs,
    /// cards). Network shares and read-only disk images are left out.
    public nonisolated static func drives() -> [VolumeUsage] {
        let keys: [URLResourceKey] = [.volumeIsLocalKey, .volumeIsReadOnlyKey, .volumeIsBrowsableKey]
        let mounted = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                            options: [.skipHiddenVolumes]) ?? []
        var result: [VolumeUsage] = []
        for url in mounted {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsLocal == true, values.volumeIsReadOnly != true, values.volumeIsBrowsable != false,
                  let volume = volume(for: url), !result.contains(where: { $0.url == volume.url }) else { continue }
            result.append(volume)
        }
        // The Mac's disk first.
        return result.sorted { ($0.url.path == "/" ? 0 : 1, $0.name) < ($1.url.path == "/" ? 0 : 1, $1.name) }
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

    public enum MoveError: LocalizedError {
        case exists, incomplete
        public var errorDescription: String? {
            switch self {
            case .exists: "There's already software with that name there."
            case .incomplete: "The copy didn't match the original, so nothing was deleted."
            }
        }
    }

    /// Moves an app into `folder` (on another drive): copies it with its `.app.key`, checks the
    /// copy has every byte, then deletes the original. Returns the new location.
    public func move(_ game: Game, to folder: URL) async throws -> URL {
        let destination = folder.appendingPathComponent(game.url.lastPathComponent, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw MoveError.exists }
        moving[game.id] = 0
        defer { moving[game.id] = nil }
        let source = game.url
        let total = await Task.detached(priority: .utility) { Self.contentSize(of: source) }.value
        let watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let copied = await Task.detached(priority: .background) { Self.contentSize(of: destination) }.value
                if !Task.isCancelled, total > 0 { self?.moving[game.id] = min(Double(copied) / Double(total), 0.99) }
            }
        }
        defer { watcher.cancel() }
        try await Task.detached(priority: .utility) {
            let fm = FileManager.default
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            do {
                try fm.copyItem(at: source, to: destination)
                guard Self.contentSize(of: destination) == total else { throw MoveError.incomplete }
            } catch {
                try? fm.removeItem(at: destination)
                throw error
            }
            let key = Self.keyFile(for: source)
            if fm.fileExists(atPath: key.path) {
                try? fm.copyItem(at: key, to: Self.keyFile(for: destination))
                try? fm.removeItem(at: key)
            }
            try fm.removeItem(at: source)
        }.value
        forget(game)
        return destination
    }

    /// Bytes of file content in a file or folder (what a copy has to reproduce exactly).
    nonisolated static func contentSize(of url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else {
            return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
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
