import AppKit
import ImageIO
import LauncherCore
import Observation
import SwiftUI

/// Game icons, decoded off the main thread and downsampled to 512 px.
/// Views read `icon(for:)`; it returns `nil` until the icon is ready and redraws when it is.
@MainActor @Observable
final class IconCache {
    static let shared = IconCache()

    private var images: [String: NSImage] = [:]
    private var resolved: Set<String> = []
    @ObservationIgnored private var requested: Set<String> = []

    /// `true` until the icon for this game has been decoded (or found missing).
    func isLoading(_ game: Game) -> Bool {
        !resolved.contains(game.id)
    }

    func icon(for game: Game) -> NSImage? {
        if let image = images[game.id] { return image }
        load([game])
        return nil
    }

    /// Starts decoding icons for these games (no-op for ones already requested).
    func load(_ games: [Game]) {
        let pending = games.filter { requested.insert($0.id).inserted }
        guard !pending.isEmpty else { return }
        Task {
            for game in pending {
                let image = await Task.detached(priority: .userInitiated) { Self.decode(game) }.value
                if let image { images[game.id] = image }
                resolved.insert(game.id)
            }
        }
    }

    /// Native ports without cover art get `nil`, so the tile shows the title instead of a generic
    /// app icon. Other apps use their Finder icon.
    nonisolated static func decode(_ game: Game) -> NSImage? {
        if let url = game.iconURL, let image = largestImage(at: url, maxPixel: 512) {
            return image
        }
        let isNative = GameScanner.isNativeBundleID(game.bundleIdentifier)
        if isNative { return nil }
        let icon = NSWorkspace.shared.icon(forFile: game.url.path)
        icon.size = NSSize(width: 512, height: 512)
        return icon
    }

    /// `.icns` files hold several sizes; thumbnail from the largest one.
    nonisolated static func largestImage(at url: URL, maxPixel: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        var bestIndex = 0
        var bestWidth = 0
        for index in 0..<CGImageSourceGetCount(source) {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
            if width > bestWidth {
                bestWidth = width
                bestIndex = index
            }
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, bestIndex, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

/// Downsampled image loaded off the main thread (for Album thumbnails).
struct AsyncThumbnail: View {
    let url: URL
    let maxPixel: CGFloat

    @State private var image: NSImage?
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.surfaceRaised
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .task(id: url) {
            let url = url
            let maxPixel = maxPixel
            image = await Task.detached(priority: .utility) {
                IconCache.largestImage(at: url, maxPixel: maxPixel)
            }.value
        }
    }
}
