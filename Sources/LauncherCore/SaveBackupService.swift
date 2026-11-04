import Foundation

public struct SaveBackup: Identifiable, Hashable, Sendable {
    public let titleID: String
    public let url: URL
    public let createdAt: Date
    public let size: Int64

    public var id: String { url.path }
}

public enum SaveBackupError: LocalizedError, Equatable {
    case sourceMissing
    case backupMissing
    case invalidBackup
    case invalidTitleID

    public var errorDescription: String? {
        switch self {
        case .sourceMissing: "The save data no longer exists."
        case .backupMissing: "The backup no longer exists."
        case .invalidBackup: "This backup does not belong to the selected game."
        case .invalidTitleID: "The save data has an invalid title ID."
        }
    }
}

/// Timestamped local save snapshots with rollback-safe restore.
public struct SaveBackupService: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    public func backups(for titleID: String) -> [SaveBackup] {
        guard let titleID = Self.safeTitleID(titleID) else { return [] }
        let folder = root.appendingPathComponent(titleID, isDirectory: true)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .creationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.compactMap { url in
            guard (try? url.resourceValues(forKeys: keys).isDirectory) == true else { return nil }
            let created = (try? url.resourceValues(forKeys: keys).creationDate) ?? .distantPast
            return SaveBackup(titleID: titleID, url: url, createdAt: created, size: StorageUsage.size(of: url))
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    public func backup(_ save: SaveData, at date: Date = Date()) throws -> SaveBackup {
        let fm = FileManager.default
        guard fm.fileExists(atPath: save.url.path) else { throw SaveBackupError.sourceMissing }
        guard let titleID = Self.safeTitleID(save.titleID) else { throw SaveBackupError.invalidTitleID }
        let titleFolder = root.appendingPathComponent(titleID, isDirectory: true)
        try fm.createDirectory(at: titleFolder, withIntermediateDirectories: true)
        let destination = titleFolder.appendingPathComponent(Self.backupName(date), isDirectory: true)
        try fm.copyItem(at: save.url, to: destination)
        return SaveBackup(titleID: titleID, url: destination, createdAt: date, size: StorageUsage.size(of: destination))
    }

    /// Restores a snapshot. The current save is backed up first, and remains available if any
    /// copy or replacement step fails.
    public func restore(_ backup: SaveBackup, to destination: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: backup.url.path) else { throw SaveBackupError.backupMissing }
        guard let titleID = Self.safeTitleID(backup.titleID) else { throw SaveBackupError.invalidTitleID }
        let expectedRoot = root.appendingPathComponent(titleID, isDirectory: true).standardizedFileURL.path + "/"
        guard backup.url.standardizedFileURL.path.hasPrefix(expectedRoot),
              destination.lastPathComponent.uppercased() == titleID else {
            throw SaveBackupError.invalidBackup
        }

        if fm.fileExists(atPath: destination.path) {
            let current = SaveData(titleID: titleID, url: destination, size: StorageUsage.size(of: destination))
            try self.backup(current)
        }

        let parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let token = UUID().uuidString
        let staging = parent.appendingPathComponent(".\(titleID).restore-\(token)", isDirectory: true)
        let previous = parent.appendingPathComponent(".\(titleID).previous-\(token)", isDirectory: true)
        try fm.copyItem(at: backup.url, to: staging)
        var movedCurrent = false
        do {
            if fm.fileExists(atPath: destination.path) {
                try fm.moveItem(at: destination, to: previous)
                movedCurrent = true
            }
            try fm.moveItem(at: staging, to: destination)
            if movedCurrent { try fm.removeItem(at: previous) }
        } catch {
            try? fm.removeItem(at: staging)
            if movedCurrent, !fm.fileExists(atPath: destination.path) {
                try? fm.moveItem(at: previous, to: destination)
            }
            throw error
        }
    }

    private static func backupName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: date) + "_" + UUID().uuidString.prefix(8)
    }

    /// Title IDs normally contain only hexadecimal characters, but third-party bundle metadata is
    /// not trusted. Reject path syntax while still supporting nonstandard IDs already in use.
    private static func safeTitleID(_ raw: String) -> String? {
        let value = raw.uppercased()
        guard !value.isEmpty, value.count <= 128, value != ".", value != "..",
              !value.contains("/"), !value.contains("\\"), !value.contains("\0") else { return nil }
        return value
    }
}
