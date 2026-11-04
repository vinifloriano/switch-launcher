import Foundation

/// Small, resilient JSON persistence used by user-facing state.
///
/// A malformed file is preserved beside the original before defaults are used, which makes a
/// support report actionable without letting one damaged preference prevent the app from opening.
enum JSONFileStore {
    static func load<Value: Decodable>(_ type: Value.Type, from url: URL, label: String) -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: Data(contentsOf: url))
        } catch {
            preserveCorruptFile(at: url)
            Log.persistence.error("Couldn't read \(label, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func save<Value: Encodable>(
        _ value: Value,
        to url: URL,
        permissions: Int? = nil
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        if let permissions {
            try FileManager.default.setAttributes(
                [.posixPermissions: permissions],
                ofItemAtPath: url.path
            )
        }
    }

    static func corruptBackupURL(for url: URL) -> URL {
        url.appendingPathExtension("corrupt")
    }

    private static func preserveCorruptFile(at url: URL) {
        let backup = corruptBackupURL(for: url)
        guard !FileManager.default.fileExists(atPath: backup.path) else { return }
        do {
            try FileManager.default.copyItem(at: url, to: backup)
            Log.persistence.notice("Preserved damaged file at \(backup.path, privacy: .public)")
        } catch {
            Log.persistence.error("Couldn't preserve damaged file \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
