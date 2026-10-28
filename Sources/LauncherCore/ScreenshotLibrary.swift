import Foundation

/// Screenshots for the Album: macOS's screenshot folder, the Desktop and ~/Pictures/Screenshots.
public enum ScreenshotLibrary {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic"]

    public static var locations: [URL] {
        let fm = FileManager.default
        var urls: [URL] = []
        if let custom = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            urls.append(URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true))
        }
        urls.append(fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true))
        urls.append(fm.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Screenshots", isDirectory: true))
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    /// Newest first.
    public static func load(limit: Int = 300) -> [URL] {
        let fm = FileManager.default
        var found: [(URL, Date)] = []
        for folder in locations {
            guard let items = try? fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in items where imageExtensions.contains(url.pathExtension.lowercased()) {
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                found.append((url, date))
            }
        }
        return found.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }
}
