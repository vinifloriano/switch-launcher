import Foundation

/// `catalog.json` at the root of the store bucket, written by `scripts/store-publish.sh`.
public struct StoreCatalog: Codable, Equatable, Sendable {
    public var version: Int
    public var updated: String?
    public var games: [StoreGame]

    public init(version: Int = 1, updated: String? = nil, games: [StoreGame] = []) {
        self.version = version
        self.updated = updated
        self.games = games
    }
}

public struct StoreGame: Codable, Equatable, Identifiable, Sendable {
    /// The app's bundle identifier, so it matches `Game.id` once installed.
    public var id: String
    public var title: String
    public var version: String?
    public var titleID: String?
    public var category: String?
    /// Folder name of the app once installed, e.g. `Metroid Dread.app`.
    public var appName: String
    /// Object key of the Apple Archive (`.aar`) holding the app's contents.
    public var archive: String
    public var archiveSize: Int64
    public var installedSize: Int64?
    /// SHA-256 of the archive, hex.
    public var sha256: String
    /// Object key of a PNG cover icon.
    public var icon: String?

    public init(
        id: String, title: String, version: String? = nil, titleID: String? = nil, category: String? = nil,
        appName: String, archive: String, archiveSize: Int64, installedSize: Int64? = nil,
        sha256: String, icon: String? = nil
    ) {
        self.id = id
        self.title = title
        self.version = version
        self.titleID = titleID
        self.category = category
        self.appName = appName
        self.archive = archive
        self.archiveSize = archiveSize
        self.installedSize = installedSize
        self.sha256 = sha256
        self.icon = icon
    }
}

/// Where the store lives and how to sign in. For MinIO the username and password are the user's
/// access key and secret key.
public struct StoreConfig: Codable, Equatable, Sendable {
    /// Home-network address, tried first (e.g. `http://192.168.1.10:30900`).
    public var localEndpoint: String = ""
    /// Address from anywhere, e.g. through a Cloudflare tunnel (`https://games.example.net`).
    public var remoteEndpoint: String = ""
    public var bucket: String = "switch-games"
    public var region: String = "us-east-1"
    public var username: String = ""
    public var password: String = ""
    /// Where downloaded games are installed; empty means the first library folder.
    public var installFolder: String = ""

    public init() {}

    public var endpoints: [URL] {
        [localEndpoint, remoteEndpoint]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap(URL.init(string:))
    }

    public var isConfigured: Bool {
        !endpoints.isEmpty && !bucket.isEmpty && !username.isEmpty && !password.isEmpty
    }

    // Decoded field by field so configs saved by older versions keep working.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StoreConfig()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        localEndpoint = value(.localEndpoint, d.localEndpoint)
        remoteEndpoint = value(.remoteEndpoint, d.remoteEndpoint)
        bucket = value(.bucket, d.bucket)
        region = value(.region, d.region)
        username = value(.username, d.username)
        password = value(.password, d.password)
        installFolder = value(.installFolder, d.installFolder)
    }
}

public enum ByteFormatter {
    public static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
