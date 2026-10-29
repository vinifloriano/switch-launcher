import Foundation
import Observation

public enum ThemeChoice: String, Codable, CaseIterable, Sendable {
    case basicWhite, basicBlack, matchSystem

    public var displayName: String {
        switch self {
        case .basicWhite: "Basic White"
        case .basicBlack: "Basic Black"
        case .matchSystem: "Match macOS"
        }
    }
}

public struct LauncherSettings: Codable, Equatable, Sendable {
    public var theme: ThemeChoice = .basicWhite
    public var soundsEnabled = true
    public var soundVolume: Double = 0.7
    public var libraryFolders: [String] = LauncherSettings.defaultFolders
    public var extraApps: [String] = []
    /// Virtual game cards that are "ejected": hidden from the HOME Menu, still in All Software.
    public var ejectedGameIDs: Set<String> = []
    public var userName: String = LauncherSettings.defaultUserName
    public var avatarSymbol = "star.fill"
    public var avatarColorIndex = 0
    public var startFullScreen = false
    public var showBootAnimation = true
    public var hideWhilePlaying = false
    /// Starts native ports in full screen (`DM_FULLSCREEN=1`), on top of the launcher.
    public var playInFullScreen = true
    /// Gives focus back to the game when a background app takes it.
    public var keepGameInFront = true
    /// The game store bucket and sign-in.
    public var store = StoreConfig()
    public var homeButtonReturnsToLauncher = true
    public var nintendoButtonLayout = true
    /// Look for a newer launcher release on GitHub at startup and every few hours.
    public var checkForUpdates = true

    public init() {}

    public static var defaultFolders: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Documents/Switch/apps").path,
            "/Applications",
            home.appendingPathComponent("Applications").path,
        ]
    }

    public static var defaultUserName: String {
        NSFullUserName().split(separator: " ").first.map(String.init) ?? "Player"
    }

    // Decoded field by field so settings saved by older versions keep working.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LauncherSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        theme = value(.theme, d.theme)
        soundsEnabled = value(.soundsEnabled, d.soundsEnabled)
        soundVolume = value(.soundVolume, d.soundVolume)
        libraryFolders = value(.libraryFolders, d.libraryFolders)
        extraApps = value(.extraApps, d.extraApps)
        ejectedGameIDs = value(.ejectedGameIDs, d.ejectedGameIDs)
        userName = value(.userName, d.userName)
        avatarSymbol = value(.avatarSymbol, d.avatarSymbol)
        avatarColorIndex = value(.avatarColorIndex, d.avatarColorIndex)
        startFullScreen = value(.startFullScreen, d.startFullScreen)
        showBootAnimation = value(.showBootAnimation, d.showBootAnimation)
        hideWhilePlaying = value(.hideWhilePlaying, d.hideWhilePlaying)
        playInFullScreen = value(.playInFullScreen, d.playInFullScreen)
        keepGameInFront = value(.keepGameInFront, d.keepGameInFront)
        store = value(.store, d.store)
        homeButtonReturnsToLauncher = value(.homeButtonReturnsToLauncher, d.homeButtonReturnsToLauncher)
        nintendoButtonLayout = value(.nintendoButtonLayout, d.nintendoButtonLayout)
        checkForUpdates = value(.checkForUpdates, d.checkForUpdates)
    }
}

@MainActor @Observable
public final class SettingsStore {
    public var value: LauncherSettings {
        didSet {
            guard value != oldValue else { return }
            save()
            onChange?(value)
        }
    }

    @ObservationIgnored public var onChange: ((LauncherSettings) -> Void)?
    @ObservationIgnored private let fileURL: URL

    public init(fileURL: URL = AppPaths.supportDirectory.appendingPathComponent("settings.json")) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(LauncherSettings.self, from: data) {
            value = decoded
        } else {
            value = LauncherSettings()
        }
    }

    public var libraryFolderURLs: [URL] {
        value.libraryFolders.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    public var extraAppURLs: [URL] {
        value.extraApps.map { URL(fileURLWithPath: $0) }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: fileURL, options: .atomic)
        // Holds the store password: readable by this user only.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

}
