import CoreAudio
import CoreGraphics
import CoreWLAN
import Foundation
import IOBluetooth
import Observation

/// A Bluetooth device paired with this Mac.
public struct BluetoothDevice: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable { case controller, audio, keyboard, mouse, other }

    public let id: String
    public let name: String
    public let isConnected: Bool
    public let kind: Kind

    /// From the Bluetooth device class; controllers that report themselves vaguely go by name.
    static func kind(major: UInt32, minor: UInt32, name: String) -> Kind {
        let controllerNames = ["controller", "8bitdo", "joy-con", "dualsense", "dualshock", "xbox", "gamepad"]
        if controllerNames.contains(where: name.lowercased().contains) { return .controller }
        switch major {
        case 0x04: return .audio
        case 0x05:
            // Peripheral: low bits say gamepad/joystick, high bits keyboard/pointer.
            if minor & 0x0F == 0x01 || minor & 0x0F == 0x02 { return .controller }
            if minor & 0x30 == 0x10 { return .keyboard }
            if minor & 0x30 == 0x20 { return .mouse }
            return .other
        default: return .other
        }
    }
}

/// The Mac's own switches, controlled from System Settings: display brightness, output volume,
/// Wi-Fi, Bluetooth and Airplane Mode (Wi-Fi and Bluetooth off together).
/// Values are read on `refresh()`; a control that this Mac can't change reads as `nil`.
@MainActor @Observable
public final class MacControls {
    public private(set) var brightness: Double?
    public private(set) var volume: Double?
    public private(set) var isMuted = false
    public private(set) var outputDevice: String?
    public private(set) var wifiOn: Bool?
    public private(set) var wifiNetwork: String?
    public private(set) var bluetoothOn: Bool?
    public private(set) var bluetoothDevices: [BluetoothDevice] = []
    public private(set) var ipAddress: String?

    public init() {}

    public func refresh() {
        brightness = Display.brightness()
        volume = Audio.volume()
        isMuted = Audio.isMuted()
        outputDevice = Audio.outputName()
        let wifi = CWWiFiClient.shared().interface()
        wifiOn = wifi?.powerOn()
        // The network name needs Location Services; without it macOS returns nil.
        wifiNetwork = wifi?.ssid()
        bluetoothOn = Bluetooth.powerOn()
        bluetoothDevices = Bluetooth.pairedDevices()
        ipAddress = Network.primaryAddress()
    }

    public func setBrightness(_ value: Double) {
        guard Display.setBrightness(value) else { return }
        brightness = value
    }

    public func setVolume(_ value: Double) {
        guard Audio.setVolume(value) else { return }
        volume = value
        if value > 0, isMuted, Audio.setMuted(false) { isMuted = false }
    }

    public func setMuted(_ muted: Bool) {
        guard Audio.setMuted(muted) else { return }
        isMuted = muted
    }

    @discardableResult
    public func setWiFi(_ on: Bool) -> Bool {
        guard let wifi = CWWiFiClient.shared().interface() else { return false }
        do {
            try wifi.setPower(on)
            wifiOn = on
            return true
        } catch {
            Log.launcher.error("Wi-Fi power change failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    @discardableResult
    public func setBluetooth(_ on: Bool) -> Bool {
        guard Bluetooth.setPower(on) else { return false }
        bluetoothOn = on
        return true
    }

    // MARK: Display

    private enum Display {
        private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        private typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32
        // DisplayServices is what the brightness keys use; it only drives Apple displays.
        private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        private static let get = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: Get.self) }
        private static let set = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: Set.self) }

        static func brightness() -> Double? {
            var value: Float = 0
            guard let get, get(CGMainDisplayID(), &value) == 0 else { return nil }
            return Double(value)
        }

        static func setBrightness(_ value: Double) -> Bool {
            guard let set else { return false }
            return set(CGMainDisplayID(), Float(min(max(value, 0), 1))) == 0
        }
    }

    // MARK: Audio

    private enum Audio {
        static func outputDevice() -> AudioObjectID? {
            var device = AudioObjectID(0)
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
            return status == noErr && device != 0 ? device : nil
        }

        /// The device's main volume, or the first channel's on devices without one.
        private static func volumeAddress(_ device: AudioObjectID) -> AudioObjectPropertyAddress? {
            for element in [kAudioObjectPropertyElementMain, 1] {
                var address = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyVolumeScalar,
                    mScope: kAudioDevicePropertyScopeOutput,
                    mElement: element)
                if AudioObjectHasProperty(device, &address) { return address }
            }
            return nil
        }

        static func volume() -> Double? {
            guard let device = outputDevice(), var address = volumeAddress(device) else { return nil }
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
            return Double(value)
        }

        static func setVolume(_ value: Double) -> Bool {
            guard let device = outputDevice(), var main = volumeAddress(device) else { return false }
            var level = Float32(min(max(value, 0), 1))
            let size = UInt32(MemoryLayout<Float32>.size)
            if main.mElement == kAudioObjectPropertyElementMain {
                return AudioObjectSetPropertyData(device, &main, 0, nil, size, &level) == noErr
            }
            // No main volume: set left and right.
            var ok = false
            for channel: UInt32 in [1, 2] {
                main.mElement = channel
                if AudioObjectHasProperty(device, &main) {
                    ok = AudioObjectSetPropertyData(device, &main, 0, nil, size, &level) == noErr || ok
                }
            }
            return ok
        }

        private static func muteAddress() -> AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain)
        }

        static func isMuted() -> Bool {
            guard let device = outputDevice() else { return false }
            var address = muteAddress()
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectHasProperty(device, &address),
                  AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return false }
            return value != 0
        }

        static func setMuted(_ muted: Bool) -> Bool {
            guard let device = outputDevice() else { return false }
            var address = muteAddress()
            var value: UInt32 = muted ? 1 : 0
            guard AudioObjectHasProperty(device, &address) else { return false }
            return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
        }

        static func outputName() -> String? {
            guard let device = outputDevice() else { return nil }
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var name: Unmanaged<CFString>?
            var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else { return nil }
            return name?.takeRetainedValue() as String?
        }
    }

    // MARK: Bluetooth

    private enum Bluetooth {
        private typealias Get = @convention(c) () -> Int32
        private typealias Set = @convention(c) (Int32) -> Void
        // The same calls the Bluetooth menu uses; IOBluetooth exports them without a header.
        private static let handle = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY)
        private static let get = handle.flatMap { dlsym($0, "IOBluetoothPreferenceGetControllerPowerState") }.map { unsafeBitCast($0, to: Get.self) }
        private static let set = handle.flatMap { dlsym($0, "IOBluetoothPreferenceSetControllerPowerState") }.map { unsafeBitCast($0, to: Set.self) }

        static func powerOn() -> Bool? {
            get.map { $0() != 0 }
        }

        static func setPower(_ on: Bool) -> Bool {
            guard let set else { return false }
            set(on ? 1 : 0)
            // The controller takes a moment to change; report what was asked for.
            return true
        }

        static func pairedDevices() -> [BluetoothDevice] {
            let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
            return devices.map {
                BluetoothDevice(id: $0.addressString ?? UUID().uuidString,
                                name: $0.name ?? $0.addressString ?? "Device",
                                isConnected: $0.isConnected(),
                                kind: BluetoothDevice.kind(major: $0.deviceClassMajor, minor: $0.deviceClassMinor,
                                                           name: $0.name ?? ""))
            }
            .sorted { ($0.isConnected ? 0 : 1, $0.name) < ($1.isConnected ? 0 : 1, $1.name) }
        }
    }

    // MARK: Network

    private enum Network {
        /// IPv4 address of the first active Ethernet or Wi-Fi interface.
        static func primaryAddress() -> String? {
            var list: UnsafeMutablePointer<ifaddrs>?
            guard getifaddrs(&list) == 0, let first = list else { return nil }
            defer { freeifaddrs(list) }
            for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
                let entry = pointer.pointee
                let name = String(cString: entry.ifa_name)
                guard name.hasPrefix("en"), let address = entry.ifa_addr,
                      address.pointee.sa_family == UInt8(AF_INET),
                      entry.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: host)
                }
            }
            return nil
        }
    }
}
