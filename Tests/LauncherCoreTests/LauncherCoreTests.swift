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
