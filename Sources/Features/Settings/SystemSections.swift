import AppKit
import DesignSystem
import LauncherCore

/// System Settings pages modelled on the Switch 2's list.
extension AppModel {
    var airplaneSection: MenuSection {
        let c = controls
        let on = settings.value.airplaneMode
        return MenuSection(
            id: "airplane", title: "Airplane Mode", symbol: "airplane",
            footnote: "Turns off Wi-Fi and Bluetooth together. Turning it off again restores them as they were. Wireless controllers stop working while it's on.",
            items: [
                MenuItem(id: "airplaneMode", title: "Airplane Mode",
                         kind: .toggle(on) { [unowned self] in setAirplaneMode($0) }),
                MenuItem(id: "airWifi", title: "Wi-Fi", symbol: "wifi",
                         kind: .info(c.wifiOn.map { $0 ? "On" : "Off" } ?? "Not available")),
                MenuItem(id: "airBluetooth", title: "Bluetooth", symbol: "antenna.radiowaves.left.and.right",
                         kind: .info(c.bluetoothOn.map { $0 ? "On" : "Off" } ?? "Not available")),
            ]
        )
    }

    var brightnessSection: MenuSection {
        var items: [MenuItem] = []
        if let level = controls.brightness {
            items.append(MenuItem(id: "brightness", title: "Screen Brightness", symbol: "sun.max.fill",
                                  kind: .slider(level) { [unowned self] in controls.setBrightness($0) }))
        } else {
            items.append(MenuItem(id: "brightness", title: "Screen Brightness", subtitle: "This display's brightness is set on the display itself.",
                                  symbol: "sun.max.fill", kind: .info("Not available")))
        }
        items.append(MenuItem(id: "displays", title: "Display Settings on Mac", symbol: "arrow.up.forward.app",
                              kind: .action { [unowned self] in openMacSettings("com.apple.Displays-Settings.extension") }))
        return MenuSection(id: "brightness", title: "Screen Brightness", symbol: "sun.max.fill",
                           footnote: "Use left and right to change the brightness of this Mac's display.", items: items)
    }

    var bluetoothSection: MenuSection {
        let c = controls
        var items = [
            MenuItem(id: "bluetoothPower", title: "Bluetooth", symbol: "antenna.radiowaves.left.and.right",
                     kind: c.bluetoothOn.map { isOn in
                         .toggle(isOn) { [unowned self] in
                             controls.setBluetooth($0)
                             refreshControlsSoon()
                         }
                     } ?? .info("Not available")),
        ]
        if !c.bluetoothDevices.isEmpty {
            items.append(.header("Paired Devices"))
            items += c.bluetoothDevices.map { device in
                MenuItem(id: "bt:" + device.id, title: device.name,
                         symbol: symbol(for: device.kind),
                         kind: .info(device.isConnected ? "Connected" : "Not connected"))
            }
        }
        items.append(MenuItem(id: "pairController", title: "Pair a Controller", symbol: "plus.circle.fill",
                              kind: .link { [unowned self] in openDock(.controllers) }))
        items.append(MenuItem(id: "btSettings", title: "Bluetooth Settings on Mac", symbol: "arrow.up.forward.app",
                              kind: .action { [unowned self] in openMacSettings("com.apple.BluetoothSettings") }))
        return MenuSection(id: "bluetooth", title: "Bluetooth", symbol: "antenna.radiowaves.left.and.right", items: items)
    }

    private func symbol(for kind: BluetoothDevice.Kind) -> String {
        switch kind {
        case .controller: "gamecontroller.fill"
        case .audio: "headphones"
        case .keyboard: "keyboard.fill"
        case .mouse: "computermouse.fill"
        case .other: "dot.radiowaves.right"
        }
    }

    var internetSection: MenuSection {
        let c = controls
        let connection: String
        switch status.network {
        case .wifi: connection = c.wifiNetwork.map { "Wi-Fi · \($0)" } ?? "Wi-Fi"
        case .wired: connection = "Wired"
        case .offline: connection = "Not connected"
        }
        var items: [MenuItem] = [
            .header("Connection"),
            MenuItem(id: "connection", title: "Status", subtitle: c.ipAddress.map { "IP address \($0)" },
                     symbol: status.network == .offline ? "wifi.slash" : "wifi", kind: .info(connection)),
        ]
        if let wifiOn = c.wifiOn {
            items.append(MenuItem(id: "wifiPower", title: "Wi-Fi", kind: .toggle(wifiOn) { [unowned self] in
                controls.setWiFi($0)
                refreshControlsSoon()
            }))
        }
        items += [
            MenuItem(id: "testConnection", title: "Test Connection", symbol: "bolt.horizontal.circle.fill",
                     kind: .action { [unowned self] in testConnection() }),
            MenuItem(id: "netSettings", title: "Network Settings on Mac", symbol: "arrow.up.forward.app",
                     kind: .action { [unowned self] in openMacSettings("com.apple.Network-Settings.extension") }),
            .header("Game Store Server"),
        ]
        items += storeItems
        return MenuSection(id: "internet", title: "Internet", symbol: "wifi", items: items)
    }

    private func testConnection() {
        showToast("Testing the connection…", symbol: "bolt.horizontal.circle.fill")
        Task {
            let start = Date()
            var request = URLRequest(url: URL(string: "https://www.apple.com/library/test/success.html")!, timeoutInterval: 10)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            do {
                _ = try await URLSession.shared.data(for: request)
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                showToast("Connected to the internet (\(ms) ms).", symbol: "checkmark.circle.fill")
            } catch {
                sound.play(.error)
                showToast("Couldn't reach the internet.", symbol: "wifi.exclamationmark")
            }
        }
    }

    var parentalSection: MenuSection {
        let s = settings.value
        let limits = [0, 30, 60, 90, 120, 180, 240]
        let names = limits.map { $0 == 0 ? "No Limit" : PlayTimeFormatter.duration(TimeInterval($0 * 60)) }
        var items: [MenuItem] = [
            MenuItem(id: "pin", title: hasParentalPIN ? "Change PIN" : "Set PIN",
                     subtitle: hasParentalPIN ? "Parental Controls are on." : "Set a PIN to turn on Parental Controls.",
                     symbol: "lock.fill", kind: .action { [unowned self] in
                         guard checkPIN("change the PIN") else { return }
                         chooseParentalPIN()
                     }),
        ]
        if hasParentalPIN {
            items += [
                MenuItem(id: "limit", title: "Daily Play Time Limit",
                         subtitle: "When reached, starting software takes the PIN.",
                         kind: .choice(names, limits.firstIndex(of: s.dailyLimitMinutes) ?? 0) { [unowned self] index in
                             guard checkPIN("change the play time limit") else { return }
                             settings.value.dailyLimitMinutes = limits[index]
                         }),
                MenuItem(id: "today", title: "Played Today", kind: .info(PlayTimeFormatter.duration(playedToday))),
                MenuItem(id: "removePIN", title: "Turn Off Parental Controls", symbol: "lock.open.fill", isDestructive: true,
                         kind: .action { [unowned self] in
                             guard checkPIN("turn off Parental Controls") else { return }
                             settings.value.parentalPINHash = ""
                             settings.value.dailyLimitMinutes = 0
                             showToast("Parental Controls are off.", symbol: "lock.open.fill")
                         }),
            ]
        }
        return MenuSection(
            id: "parental", title: "Parental Controls", symbol: "figure.and.child.holdinghands",
            footnote: "With a PIN set, deleting software or save data and changing these settings also take the PIN.",
            items: items
        )
    }

    var accessibilitySection: MenuSection {
        MenuSection(
            id: "accessibility", title: "Accessibility", symbol: "accessibility",
            items: [
                toggleItem("reduceMotion", "Reduce Motion", \.reduceMotion,
                           subtitle: "Skip the startup and software launch animations."),
                toggleItem("layout", "Nintendo Button Layout", \.nintendoButtonLayout,
                           subtitle: "Use A/B/X/Y as printed on Nintendo controllers."),
                MenuItem(id: "macAccessibility", title: "Accessibility Settings on Mac", symbol: "arrow.up.forward.app",
                         kind: .action { [unowned self] in openMacSettings("com.apple.Accessibility-Settings.extension") }),
            ]
        )
    }

    var audioSection: MenuSection {
        let c = controls
        let levels: [(String, Double)] = [("Low", 0.35), ("Medium", 0.7), ("High", 1.0)]
        let current = levels.indices.min {
            abs(levels[$0].1 - settings.value.soundVolume) < abs(levels[$1].1 - settings.value.soundVolume)
        } ?? 1
        var items: [MenuItem] = [.header(c.outputDevice ?? "Mac Output")]
        if let volume = c.volume {
            items.append(MenuItem(id: "macVolume", title: "Volume", symbol: "speaker.wave.3.fill",
                                  kind: .slider(c.isMuted ? 0 : volume) { [unowned self] in controls.setVolume($0) }))
            items.append(MenuItem(id: "mute", title: "Mute", kind: .toggle(c.isMuted) { [unowned self] in controls.setMuted($0) }))
        } else {
            items.append(MenuItem(id: "macVolume", title: "Volume", subtitle: "This output's volume is set on the device.",
                                  kind: .info("Not available")))
        }
        items += [
            .header("HOME Menu"),
            toggleItem("sounds", "HOME Menu Sounds", \.soundsEnabled),
            MenuItem(id: "volume", title: "Sound Volume", kind: .choice(levels.map(\.0), current) { [unowned self] in
                settings.value.soundVolume = levels[$0].1
                sound.play(.select)
            }),
            MenuItem(id: "soundSettings", title: "Sound Settings on Mac", symbol: "arrow.up.forward.app",
                     kind: .action { [unowned self] in openMacSettings("com.apple.Sound-Settings.extension") }),
        ]
        return MenuSection(id: "audio", title: "Audio", symbol: "speaker.wave.2.fill", items: items)
    }

    var displaySection: MenuSection {
        MenuSection(
            id: "display", title: "Display", symbol: "display",
            items: [
                toggleItem("fullscreen", "Start in Full Screen", \.startFullScreen),
                MenuItem(id: "fs", title: "Toggle Full Screen", symbol: "arrow.up.left.and.arrow.down.right",
                         kind: .action { [unowned self] in toggleFullScreen() }),
                toggleItem("gameFullScreen", "Play Software in Full Screen", \.playInFullScreen,
                           subtitle: "Games open full screen on top of the launcher."),
                toggleItem("keepFront", "Keep Software in Front", \.keepGameInFront,
                           subtitle: "Take focus back when a background app steals it during play."),
                toggleItem("hide", "Hide Launcher While Playing", \.hideWhilePlaying),
                toggleItem("homeReturn", "HOME Button Returns to Launcher", \.homeButtonReturnsToLauncher,
                           subtitle: "Press HOME on a controller during a game to come back here."),
                toggleItem("boot", "Startup Animation", \.showBootAnimation),
            ]
        )
    }

    var notificationsSection: MenuSection {
        MenuSection(
            id: "notifications", title: "Notifications", symbol: "bell.badge.fill",
            footnote: "Messages shown at the top of the screen.",
            items: [
                toggleItem("notifyUpdates", "Launcher Updates", \.notifyUpdates,
                           subtitle: "When a new version of Switch Launcher is available."),
                toggleItem("notifyDownloads", "Downloads", \.notifyDownloads,
                           subtitle: "When software from the Game Store is ready to play."),
                toggleItem("notifyPlayTime", "Play Time", \.notifyPlayTime,
                           subtitle: "When today's play time limit is reached."),
            ]
        )
    }

    var sleepSection: MenuSection {
        let minutes = [0, 5, 10, 15, 30, 60]
        let names = minutes.map { $0 == 0 ? "Never" : "After \($0) min" }
        return MenuSection(
            id: "sleepMode", title: "Sleep Mode", symbol: "moon.fill",
            items: [
                MenuItem(id: "sleepNow", title: "Enter Sleep Mode", symbol: "power",
                         kind: .link { [unowned self] in openDock(.sleep) }),
                MenuItem(id: "autoSleep", title: "Auto-Sleep",
                         subtitle: "On the HOME Menu with nothing pressed. Never during play.",
                         kind: .choice(names, minutes.firstIndex(of: settings.value.autoSleepMinutes) ?? 0) { [unowned self] in
                             settings.value.autoSleepMinutes = minutes[$0]
                         }),
                MenuItem(id: "displaySleep", title: "Turn Off Display", symbol: "display",
                         kind: .action { [unowned self] in runPowerCommand("displaysleepnow") }),
                MenuItem(id: "macSleep", title: "Put Mac to Sleep", symbol: "moon.zzz.fill",
                         kind: .action { [unowned self] in
                             confirm(message: "Put the Mac to sleep?", detail: launcher.session == nil ? nil : "The software keeps running and resumes when the Mac wakes.",
                                     confirmTitle: "Sleep") { [unowned self] in runPowerCommand("sleepnow") }
                         }),
            ]
        )
    }

    func toggleItem(
        _ id: String,
        _ title: String,
        _ keyPath: WritableKeyPath<LauncherSettings, Bool>,
        subtitle: String? = nil
    ) -> MenuItem {
        MenuItem(id: id, title: title, subtitle: subtitle, kind: .toggle(settings.value[keyPath: keyPath]) { [unowned self] in
            settings.value[keyPath: keyPath] = $0
        })
    }

    /// Opens a pane of macOS System Settings.
    func openMacSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:\(pane)") { NSWorkspace.shared.open(url) }
    }
}
