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
    /// Airplane Mode: Wi-Fi and Bluetooth were turned off by the launcher, and what to restore.
    public var airplaneMode = false
    public var wifiBeforeAirplane = true
    public var bluetoothBeforeAirplane = true
    /// Messages the launcher shows.
    public var notifyUpdates = true
    /// SHA-256 receipt of the store archive currently installed for each game.
    public var installedStoreArchives: [String: String] = [:]
    /// Last catalog release announced for each game. This prevents the same update notification
    /// on every launch while allowing a newer release to be announced normally.
    public var announcedGameUpdates: [String: String] = [:]
    public var notifyDownloads = true
    public var notifyPlayTime = true
    /// Minutes without input on the HOME Menu before Sleep Mode; 0 never.
    public var autoSleepMinutes = 0
    /// Skip the startup and software launch animations.
    public var reduceMotion = false
    /// Parental Controls: SHA-256 of the PIN (empty when off) and a daily play time limit in minutes (0 none).
    public var parentalPINHash = ""
    public var dailyLimitMinutes = 0
    /// Groups of software, shown under All Software › Groups.
    public var groups: [SoftwareGroup] = []
    /// Timestamped save snapshots. May point to an external drive.
    public var saveBackupFolder: String = LauncherSettings.defaultSaveBackupFolder

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

    public static var defaultSaveBackupFolder: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Switch/Save Backups", isDirectory: true).path
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
        airplaneMode = value(.airplaneMode, d.airplaneMode)
        wifiBeforeAirplane = value(.wifiBeforeAirplane, d.wifiBeforeAirplane)
        bluetoothBeforeAirplane = value(.bluetoothBeforeAirplane, d.bluetoothBeforeAirplane)
        notifyUpdates = value(.notifyUpdates, d.notifyUpdates)
        installedStoreArchives = value(.installedStoreArchives, d.installedStoreArchives)
        announcedGameUpdates = value(.announcedGameUpdates, d.announcedGameUpdates)
        notifyDownloads = value(.notifyDownloads, d.notifyDownloads)
        notifyPlayTime = value(.notifyPlayTime, d.notifyPlayTime)
        autoSleepMinutes = value(.autoSleepMinutes, d.autoSleepMinutes)
        reduceMotion = value(.reduceMotion, d.reduceMotion)
        parentalPINHash = value(.parentalPINHash, d.parentalPINHash)
        dailyLimitMinutes = value(.dailyLimitMinutes, d.dailyLimitMinutes)
        groups = value(.groups, d.groups)
        saveBackupFolder = value(.saveBackupFolder, d.saveBackupFolder)
    }
}

/// A named set of software, like the console's groups.
public struct SoftwareGroup: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var gameIDs: [String]

    public init(id: String = UUID().uuidString, name: String, gameIDs: [String] = []) {
        self.id = id
        self.name = name
        self.gameIDs = gameIDs
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
        value = JSONFileStore.load(LauncherSettings.self, from: fileURL, label: "settings")
            ?? LauncherSettings()
    }

    public var libraryFolderURLs: [URL] {
        value.libraryFolders.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    public var extraAppURLs: [URL] {
        value.extraApps.map { URL(fileURLWithPath: $0) }
    }

    private func save() {
        do {
            // Holds the store password: readable by this user only.
            try JSONFileStore.save(value, to: fileURL, permissions: 0o600)
        } catch {
            Log.persistence.error("Couldn't save settings: \(error.localizedDescription, privacy: .public)")
        }
    }

}
