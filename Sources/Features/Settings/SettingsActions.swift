import AppKit
import CryptoKit
import DesignSystem
import LauncherCore
import SwiftUI

/// What System Settings' pages do: Parental Controls, Airplane Mode, moving software, sleep.
extension AppModel {
    // MARK: Parental Controls

    var hasParentalPIN: Bool { !settings.value.parentalPINHash.isEmpty }

    static func hashPIN(_ pin: String) -> String {
        SHA256.hash(data: Data(pin.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// `true` when there's no PIN, or the right one is entered.
    func checkPIN(_ reason: String) -> Bool {
        guard hasParentalPIN else { return true }
        guard let pin = promptText("Parental Controls", message: "Enter the PIN to \(reason).", secure: true) else { return false }
        if Self.hashPIN(pin) == settings.value.parentalPINHash { return true }
        sound.play(.error)
        showToast("Incorrect PIN.", symbol: "lock.fill")
        return false
    }

    /// Asks for a new 4-digit PIN twice. `false` when cancelled or they don't match.
    @discardableResult
    func chooseParentalPIN() -> Bool {
        guard let pin = promptText("Set PIN", message: "Enter a 4-digit PIN.", secure: true) else { return false }
        guard pin.count == 4, pin.allSatisfy(\.isNumber) else {
            sound.play(.error)
            showToast("The PIN must be 4 digits.", symbol: "lock.fill")
            return false
        }
        guard let again = promptText("Set PIN", message: "Enter the same PIN again.", secure: true), again == pin else {
            sound.play(.error)
            showToast("The PINs didn't match.", symbol: "lock.fill")
            return false
        }
        settings.value.parentalPINHash = Self.hashPIN(pin)
        showToast("Parental Controls PIN set.", symbol: "lock.fill")
        return true
    }

    /// Play time today, including the software running now.
    var playedToday: TimeInterval {
        let running = launcher.session.map { Date().timeIntervalSince($0.started) } ?? 0
        return history.seconds() + running
    }

    /// With a daily limit reached, starting software takes the PIN.
    func launchAllowedByParentalControls(_ game: Game) -> Bool {
        let limit = TimeInterval(settings.value.dailyLimitMinutes * 60)
        guard limit > 0, playedToday >= limit, launcher.runningGameID != game.id else { return true }
        if settings.value.notifyPlayTime {
            showToast("Today's play time limit has been reached.", symbol: "hourglass")
        }
        return checkPIN("play past today's limit")
    }

    // MARK: Airplane Mode

    func setAirplaneMode(_ on: Bool) {
        controls.refresh()
        if on {
            settings.value.wifiBeforeAirplane = controls.wifiOn ?? true
            settings.value.bluetoothBeforeAirplane = controls.bluetoothOn ?? true
            controls.setWiFi(false)
            controls.setBluetooth(false)
        } else {
            if settings.value.wifiBeforeAirplane { controls.setWiFi(true) }
            if settings.value.bluetoothBeforeAirplane { controls.setBluetooth(true) }
        }
        settings.value.airplaneMode = on
        refreshControlsSoon()
    }

    /// Bluetooth and Wi-Fi take a moment to switch; read them again shortly after.
    func refreshControlsSoon() {
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            controls.refresh()
        }
    }

    // MARK: Sleep

    func runPowerCommand(_ argument: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = [argument]
        try? process.run()
    }

    // MARK: Moving software

    /// Where software goes on a drive: a library folder already on it, or a "Switch Games" folder.
    func destinationFolder(on drive: VolumeUsage) -> URL {
        let existing = settings.libraryFolderURLs.first { StorageUsage.volume(for: $0)?.url == drive.url }
        if let existing { return existing }
        if drive.url.path == "/" {
            return StorageUsage.volume(for: storeInstallFolder)?.url.path == "/"
                ? storeInstallFolder
                : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Switch/apps")
        }
        return drive.url.appendingPathComponent("Switch Games", isDirectory: true)
    }

    /// Offers the other drives to move software to.
    func confirmMove(_ game: Game) {
        guard launcher.runningGameID != game.id else {
            sound.play(.error)
            showToast("Close \(game.title) first.", symbol: "exclamationmark.triangle.fill")
            return
        }
        guard storage.moving[game.id] == nil else { return }
        guard !isAddedApp(game) else {
            showToast("Software added on its own stays where it is. Move it in Finder.", symbol: "info.circle.fill")
            return
        }
        let current = StorageUsage.volume(for: game.url)
        let targets = Array(StorageUsage.drives().filter { $0.url != current?.url }.prefix(3))
        guard !targets.isEmpty else {
            showToast("Connect an external drive to move software to it.", symbol: "externaldrive.badge.plus")
            return
        }
        let size = storage.software[game.id]?.app
        sound.play(.select)
        dialog = DialogModel(
            app: self,
            message: "Move \(game.title)?",
            detail: [size.map(ByteFormatter.string), current.map { "on \($0.name)" }].compactMap { $0 }.joined(separator: " ")
                + ". It's copied, checked, then deleted from where it is now. Save data stays on this Mac.",
            buttons: ["Cancel"] + targets.map { "Move to \($0.name)" },
            destructiveIndex: nil
        ) { [unowned self] index in
            guard index > 0 else { return }
            let drive = targets[index - 1]
            if let size, drive.available < size + 1_000_000_000 {
                sound.play(.error)
                showToast("Not enough space on \(drive.name).", symbol: "externaldrive.badge.exclamationmark")
                return
            }
            performMove(game, to: destinationFolder(on: drive), driveName: drive.name)
        }
    }

    private func performMove(_ game: Game, to folder: URL, driveName: String) {
        showToast("Moving \(game.title) to \(driveName)…", symbol: "arrow.right.circle.fill")
        Task {
            do {
                _ = try await storage.move(game, to: folder)
                if !settings.value.libraryFolders.contains(folder.path) {
                    settings.value.libraryFolders.append(folder.path)
                }
                await reloadLibrary()
                showToast("\(game.title) was moved to \(driveName).", symbol: "checkmark.circle.fill")
            } catch {
                sound.play(.error)
                showToast("Couldn't move \(game.title). \(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    // MARK: Profile icon

    /// The profile icon as an image, for menu rows.
    func avatarImage(diameter: CGFloat = 44) -> NSImage? {
        let renderer = ImageRenderer(content: UserAvatar(
            symbol: settings.value.avatarSymbol,
            color: AvatarPalette.color(at: settings.value.avatarColorIndex),
            diameter: diameter
        ).padding(2))
        renderer.scale = 2
        return renderer.nsImage
    }

    /// Initials on a coloured circle, for Mac accounts without a picture.
    func initialsImage(_ name: String, diameter: CGFloat = 44) -> NSImage? {
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        let renderer = ImageRenderer(content: ZStack {
            Circle().fill(LinearGradient(colors: [Color(hex: 0x8E8E93), Color(hex: 0x636366)],
                                         startPoint: .top, endPoint: .bottom))
            Text(initials.uppercased())
                .font(.system(size: diameter * 0.4, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }.frame(width: diameter, height: diameter))
        renderer.scale = 2
        return renderer.nsImage
    }
}
