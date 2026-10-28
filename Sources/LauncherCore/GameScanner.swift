import Foundation

/// Finds native Switch ports in folders. A bundle counts as one when its Info.plist has a
/// `DMTitleID`, its bundle identifier comes from nxnative / MacNativeGames (or ends in `.native`),
/// or it carries a port's runtime files (`dmhost`, `romfs`, `game`).
public struct GameScanner: Sendable {
    public static let nativeBundlePrefixes = ["org.nxnative.", "org.macnativegames."]
    static let nativeBundleSuffixes = [".native"]
    static let nativeBundleContents = ["Contents/MacOS/dmhost", "Contents/Resources/romfs", "Contents/Resources/game"]

    public static func isNativeBundleID(_ id: String?) -> Bool {
        guard let id else { return false }
        return nativeBundlePrefixes.contains { id.hasPrefix($0) } || nativeBundleSuffixes.contains { id.hasSuffix($0) }
    }

    public init() {}

    /// Folders are scanned one level deep; `extraApps` are added even without the native marker.
    public func scan(folders: [URL], extraApps: [URL]) -> [Game] {
        var seen = Set<String>()
        var result: [Game] = []
        let fm = FileManager.default

        for folder in folders {
            guard let items = try? fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where url.pathExtension == "app" {
                if let game = game(at: url, requireNativeMarker: true), seen.insert(game.id).inserted {
                    result.append(game)
                }
            }
        }
        for url in extraApps {
            if let game = game(at: url, requireNativeMarker: false), seen.insert(game.id).inserted {
                result.append(game)
            }
        }
        return result
    }

    public func game(at url: URL, requireNativeMarker: Bool) -> Game? {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plistURL) as? [String: Any] else { return nil }

        let bundleID = info["CFBundleIdentifier"] as? String
        let titleID = info["DMTitleID"] as? String
        let isNative = titleID != nil
            || Self.isNativeBundleID(bundleID)
            || Self.nativeBundleContents.contains { FileManager.default.fileExists(atPath: url.appendingPathComponent($0).path) }
        if requireNativeMarker && !isNative { return nil }

        let title = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent

        var iconURL: URL?
        if var iconName = info["CFBundleIconFile"] as? String {
            if (iconName as NSString).pathExtension.isEmpty { iconName += ".icns" }
            let candidate = url.appendingPathComponent("Contents/Resources").appendingPathComponent(iconName)
            if FileManager.default.fileExists(atPath: candidate.path) { iconURL = candidate }
        }

        return Game(
            id: bundleID ?? url.path,
            title: title,
            url: url,
            bundleIdentifier: bundleID,
            titleID: titleID,
            version: info["CFBundleShortVersionString"] as? String,
            iconURL: iconURL,
            category: (info["LSApplicationCategoryType"] as? String).map(Self.categoryName),
            addedDate: try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
        )
    }

    /// `public.app-category.action-games` → `Action`
    static func categoryName(_ uti: String) -> String {
        let last = uti.components(separatedBy: ".").last ?? uti
        let words = last.replacingOccurrences(of: "-games", with: "").split(separator: "-")
        return words.map { $0.capitalized }.joined(separator: " ")
    }
}
