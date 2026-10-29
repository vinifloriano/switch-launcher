import Foundation
@testable import LauncherCore
import XCTest

final class GameScannerTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeApp(_ name: String, info: [String: Any]) throws -> URL {
        let app = folder.appendingPathComponent(name + ".app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        (info as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"), atomically: true)
        return app
    }

    func testFindsOnlyNativePorts() throws {
        _ = try makeApp("Metroid Dread", info: [
            "CFBundleIdentifier": "org.nxnative.010093801237c000",
            "CFBundleDisplayName": "Metroid Dread",
            "DMTitleID": "010093801237C000",
            "CFBundleShortVersionString": "2.1.0",
            "LSApplicationCategoryType": "public.app-category.action-games",
        ])
        _ = try makeApp("Jamboree", info: ["CFBundleIdentifier": "org.macnativegames.jamboree"])
        _ = try makeApp("Safari", info: ["CFBundleIdentifier": "com.apple.Safari"])

        let games = GameScanner().scan(folders: [folder], extraApps: [])

        XCTAssertEqual(Set(games.map(\.title)), ["Metroid Dread", "Jamboree"])
        let dread = try XCTUnwrap(games.first { $0.title == "Metroid Dread" })
        XCTAssertEqual(dread.titleID, "010093801237C000")
        XCTAssertEqual(dread.version, "2.1.0")
        XCTAssertEqual(dread.category, "Action")
    }

    func testRecognisesPortsByIDSuffixOrRuntimeFiles() throws {
        _ = try makeApp("Kirby", info: ["CFBundleIdentifier": "local.kirby.native", "CFBundleName": "Kirby"])
        let acnh = try makeApp("ACNH", info: ["CFBundleIdentifier": "com.example.acnh", "CFBundleName": "ACNH"])
        try FileManager.default.createDirectory(at: acnh.appendingPathComponent("Contents/Resources/game"), withIntermediateDirectories: true)
        let games = GameScanner().scan(folders: [folder], extraApps: [])
        XCTAssertEqual(Set(games.map(\.title)), ["Kirby", "ACNH"])
    }

    func testExtraAppsSkipMarkerAndDeduplicate() throws {
        let safari = try makeApp("Safari", info: ["CFBundleIdentifier": "com.apple.Safari", "CFBundleName": "Safari"])
        let games = GameScanner().scan(folders: [folder], extraApps: [safari, safari])
        XCTAssertEqual(games.map(\.title), ["Safari"])
    }
}

final class LibraryOrderingTests: XCTestCase {
    func testRecentlyPlayedPutsPlayedFirstNewestFirst() {
        let a = Game(id: "a", title: "Alpha", url: URL(fileURLWithPath: "/a"), addedDate: Date(timeIntervalSince1970: 300))
        let b = Game(id: "b", title: "Bravo", url: URL(fileURLWithPath: "/b"), addedDate: Date(timeIntervalSince1970: 100))
        let c = Game(id: "c", title: "Charlie", url: URL(fileURLWithPath: "/c"), addedDate: Date(timeIntervalSince1970: 100))
        let history = [
            "b": PlayRecord(lastPlayed: Date(timeIntervalSince1970: 1_000)),
            "c": PlayRecord(lastPlayed: Date(timeIntervalSince1970: 2_000)),
        ]
        let sorted = LibraryOrdering.sort([a, b, c], by: .recentlyPlayed, history: history)
        XCTAssertEqual(sorted.map(\.id), ["c", "b", "a"])
    }

    func testPlayTimeAndTitle() {
        let a = Game(id: "a", title: "zeta", url: URL(fileURLWithPath: "/a"))
        let b = Game(id: "b", title: "Alpha", url: URL(fileURLWithPath: "/b"))
        let history = ["a": PlayRecord(totalSeconds: 50)]
        XCTAssertEqual(LibraryOrdering.sort([b, a], by: .playTime, history: history).map(\.id), ["a", "b"])
        XCTAssertEqual(LibraryOrdering.sort([a, b], by: .title, history: [:]).map(\.id), ["b", "a"])
    }

    func testSettingsDecodeToleratesMissingKeys() throws {
        let data = Data(#"{"theme":"basicBlack","userName":"Vini"}"#.utf8)
        let settings = try JSONDecoder().decode(LauncherSettings.self, from: data)
        XCTAssertEqual(settings.theme, .basicBlack)
        XCTAssertEqual(settings.userName, "Vini")
        XCTAssertTrue(settings.soundsEnabled)
    }
}

final class S3SignerTests: XCTestCase {
    /// AWS's published example for query-string (presigned) authentication.
    func testMatchesAWSPresignExample() throws {
        let signer = S3Signer(accessKey: "AKIAIOSFODNN7EXAMPLE", secretKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2013-05-24T00:00:00Z"))
        let url = try XCTUnwrap(signer.presignedURL(
            endpoint: URL(string: "https://examplebucket.s3.amazonaws.com")!,
            path: "/test.txt", expires: 86400, date: date
        ))
        XCTAssertTrue(url.absoluteString.hasSuffix(
            "X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404"
        ), url.absoluteString)
    }

    func testPathStyleKeepsPortAndEncodesKey() throws {
        let signer = S3Signer(accessKey: "k", secretKey: "s")
        let url = try XCTUnwrap(signer.presignedURL(
            endpoint: URL(string: "http://192.168.1.10:30900")!, bucket: "switch-games", key: "games/Metroid Dread/icon.png"
        ))
        XCTAssertTrue(url.absoluteString.hasPrefix("http://192.168.1.10:30900/switch-games/games/Metroid%20Dread/icon.png?"))
    }

    func testStoreConfigEndpointsAndDecoding() throws {
        var config = StoreConfig()
        XCTAssertFalse(config.isConfigured)
        config.localEndpoint = "http://192.168.1.10:30900"
        config.username = "launcher"
        XCTAssertFalse(config.isConfigured)
        config.password = "secret"
        XCTAssertTrue(config.isConfigured)
        let decoded = try JSONDecoder().decode(StoreConfig.self, from: Data(#"{"bucket":"b"}"#.utf8))
        XCTAssertEqual(decoded.bucket, "b")
        XCTAssertEqual(decoded.region, "us-east-1")
    }
}

/// Runs only against a real or emulated S3 store:
/// `STORE_TEST_ENDPOINT=http://127.0.0.1:9100 STORE_TEST_GAME=<bundle id> swift test --filter StoreServiceIntegrationTests`
final class StoreServiceIntegrationTests: XCTestCase {
    @MainActor
    func testDownloadsVerifiesAndInstallsAGame() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let endpoint = env["STORE_TEST_ENDPOINT"], let gameID = env["STORE_TEST_GAME"] else {
            throw XCTSkip("Set STORE_TEST_ENDPOINT and STORE_TEST_GAME to run against a store.")
        }
        var config = StoreConfig()
        config.localEndpoint = endpoint
        config.username = env["STORE_TEST_USER"] ?? "test"
        config.password = env["STORE_TEST_PASSWORD"] ?? "test"
        config.bucket = env["STORE_TEST_BUCKET"] ?? "switch-games"
        let service = StoreService()
        service.configure(config)
        await service.refresh()
        XCTAssertEqual(service.state, .ready)
        let game = try XCTUnwrap(service.catalog.games.first { $0.id == gameID })

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        var installedURL: URL?
        service.onInstalled = { _, url in installedURL = url }
        service.download(game, into: folder)
        // Finish as soon as the job installs or fails, instead of waiting for a timeout.
        let deadline = Date().addingTimeInterval(Double(env["STORE_TEST_TIMEOUT"] ?? "") ?? 300)
        while Date() < deadline {
            switch service.jobs[game.id] {
            case .installed?, .failed?: break
            default:
                try await Task.sleep(for: .milliseconds(250))
                continue
            }
            break
        }
        if case .failed(let message)? = service.jobs[game.id] {
            XCTFail("Download failed: \(message)")
            return
        }
        XCTAssertEqual(service.jobs[game.id], .installed)
        let app = try XCTUnwrap(installedURL)
        XCTAssertEqual(app.lastPathComponent, game.appName)
        let scanned = try XCTUnwrap(GameScanner().game(at: app, requireNativeMarker: true))
        XCTAssertEqual(scanned.id, game.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(".switch-store").path))
        if let expected = env["STORE_TEST_SOURCE"] {
            let diff = Process()
            diff.executableURL = URL(fileURLWithPath: "/usr/bin/diff")
            diff.arguments = ["-r", expected, app.path]
            try diff.run()
            diff.waitUntilExit()
            XCTAssertEqual(diff.terminationStatus, 0, "installed app differs from the source")
        }
    }
}

final class StorageUsageTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testMeasuresBundleSizeOnDisk() throws {
        let app = folder.appendingPathComponent("Game.app/Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data(count: 300_000).write(to: app.appendingPathComponent("romfs.bin"))
        try Data(count: 10).write(to: app.appendingPathComponent("small"))
        let size = StorageUsage.size(of: folder.appendingPathComponent("Game.app"))
        XCTAssertGreaterThanOrEqual(size, 300_010)
        XCTAssertLessThan(size, 400_000)
        XCTAssertEqual(StorageUsage.size(of: app.appendingPathComponent("missing")), 0)
    }

    func testKeyFileSitsBesideTheApp() {
        let app = URL(fileURLWithPath: "/Games/Mario Kart 8.app")
        XCTAssertEqual(StorageUsage.keyFile(for: app).path, "/Games/Mario Kart 8.app.key")
    }

    @MainActor
    func testReusesCachedAppSizeUntilTheAppChanges() async throws {
        let app = folder.appendingPathComponent("Game.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try Data("plist".utf8).write(to: contents.appendingPathComponent("Info.plist"))
        try Data(count: 200_000).write(to: contents.appendingPathComponent("game.bin"))
        let game = Game(id: "g", title: "Game", url: app, version: "1.0")
        let cache = folder.appendingPathComponent("sizes.json")

        func measured(_ storage: StorageUsage) async -> Int64? {
            storage.measure([game])
            while storage.isMeasuring { await Task.yield() }
            return storage.software[game.id]?.app
        }
        let measuredFirst = await measured(StorageUsage(sizesFile: cache))
        let first = try XCTUnwrap(measuredFirst)
        XCTAssertGreaterThanOrEqual(first, 200_000)

        // Content changed but the app wasn't updated: a new session uses the cached size.
        try Data(count: 900_000).write(to: contents.appendingPathComponent("game.bin"))
        let cached = await measured(StorageUsage(sizesFile: cache))
        XCTAssertEqual(cached, first)

        // A new version is measured again.
        let updated = Game(id: "g", title: "Game", url: app, version: "1.1")
        let storage = StorageUsage(sizesFile: cache)
        storage.measure([updated])
        while storage.isMeasuring { await Task.yield() }
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(storage.software["g"]?.app), 900_000)
    }

    func testReportsTheVolume() throws {
        let volume = try XCTUnwrap(StorageUsage.volume(for: folder))
        XCTAssertGreaterThan(volume.total, 0)
        XCTAssertLessThanOrEqual(volume.available, volume.total)
    }
}

final class UpdateCheckerTests: XCTestCase {
    func testComparesVersionsNumerically() {
        XCTAssertTrue(UpdateChecker.isNewer("1.4.0", than: "1.3.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.10.0", than: "1.9.2"))
        XCTAssertTrue(UpdateChecker.isNewer("2.0", than: "1.99.99"))
        XCTAssertTrue(UpdateChecker.isNewer("1.3.1", than: "1.3"))
        XCTAssertFalse(UpdateChecker.isNewer("1.3.0", than: "1.3.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.3", than: "1.3.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.2.9", than: "1.3.0"))
    }

    func testReadsGitHubRelease() throws {
        let json = """
        {"tag_name": "v1.4.0", "html_url": "https://github.com/o/r/releases/tag/v1.4.0",
         "published_at": "2026-10-29T15:51:49Z",
         "assets": [{"name": "Switch-Launcher-1.4.0.zip.sha256", "browser_download_url": "https://x/a.sha256"},
                    {"name": "Switch-Launcher-1.4.0.zip", "browser_download_url": "https://x/a.zip"}]}
        """
        let release = try UpdateChecker.parse(Data(json.utf8))
        XCTAssertEqual(release.version, "1.4.0")
        XCTAssertEqual(release.downloadURL?.absoluteString, "https://x/a.zip")
        XCTAssertEqual(release.pageURL.absoluteString, "https://github.com/o/r/releases/tag/v1.4.0")
        XCTAssertNotNil(release.published)
    }
}
