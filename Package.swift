// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwitchLauncher",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "SwitchLauncher", targets: ["SwitchLauncher"]),
        .executable(name: "store-publish", targets: ["store-publish"]),
    ],
    targets: [
        // Visual language: theme tokens, scaling, and reusable console-style components.
        .target(name: "DesignSystem"),
        // Game discovery, launching, play history, settings and system status. No UI.
        .target(name: "LauncherCore"),
        // Keyboard + game controller input mapped to Nintendo buttons.
        .target(name: "InputKit"),
        // Synthesized HOME Menu sound effects.
        .target(name: "SoundKit"),
        // Screens (HOME Menu, All Software, System Settings, ...) and navigation.
        .target(
            name: "Features",
            dependencies: ["DesignSystem", "LauncherCore", "InputKit", "SoundKit"]
        ),
        .executableTarget(name: "SwitchLauncher", dependencies: ["Features"]),
        // Packages game apps and uploads them with a catalog to the store bucket.
        .executableTarget(name: "store-publish", dependencies: ["LauncherCore"], path: "Sources/StorePublish"),
        .testTarget(name: "LauncherCoreTests", dependencies: ["LauncherCore"]),
    ],
    swiftLanguageModes: [.v5]
)
