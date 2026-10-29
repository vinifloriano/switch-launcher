import Foundation
import Observation

/// A published release of the launcher.
public struct AppRelease: Equatable, Sendable {
    public let version: String
    /// The release page, with its notes.
    public let pageURL: URL
    /// The zip to download, or `nil` when the release has none attached yet.
    public let downloadURL: URL?
    public let published: Date?
}

/// Looks for a newer release of the launcher on GitHub. It only points to the download;
/// installing stays in the user's hands.
@MainActor @Observable
public final class UpdateChecker {
    public enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(AppRelease)
        case failed(String)
    }

    public private(set) var state: State = .idle
    public private(set) var lastChecked: Date?
    /// The running version, e.g. "1.3.0". `nil` in development builds, which never report updates.
    public let currentVersion: String?
    @ObservationIgnored private let latestURL: URL
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var timer: Task<Void, Never>?

    public init(
        repository: String = "vinifloriano/switch-launcher",
        currentVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
        session: URLSession = .shared
    ) {
        self.latestURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
        self.currentVersion = currentVersion
        self.session = session
    }

    public var availableRelease: AppRelease? {
        if case .available(let release) = state { return release }
        return nil
    }

    /// Checks now and then every `interval`. `onFound` runs once per newly found version.
    public func startChecking(every interval: Duration = .seconds(6 * 3600), onFound: @escaping (AppRelease) -> Void) {
        timer?.cancel()
        timer = Task { [weak self] in
            var announced: String?
            while !Task.isCancelled {
                await self?.check()
                if let release = self?.availableRelease, release.version != announced {
                    announced = release.version
                    onFound(release)
                }
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stopChecking() {
        timer?.cancel()
        timer = nil
    }

    public func check() async {
        guard state != .checking else { return }
        state = .checking
        var request = URLRequest(url: latestURL, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SwitchLauncher/\(currentVersion ?? "dev")", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let release = try Self.parse(data)
            lastChecked = Date()
            if let current = currentVersion, Self.isNewer(release.version, than: current) {
                state = .available(release)
                Log.updates.info("Update available: \(release.version, privacy: .public)")
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed("Couldn't check for updates.")
            Log.updates.error("Update check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Reads GitHub's "latest release" response.
    nonisolated static func parse(_ data: Data) throws -> AppRelease {
        struct Response: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
            }
            let tag_name: String
            let html_url: URL
            let published_at: String?
            let assets: [Asset]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        let version = response.tag_name.hasPrefix("v") ? String(response.tag_name.dropFirst()) : response.tag_name
        let zip = response.assets.first { $0.name.hasSuffix(".zip") }
        return AppRelease(
            version: version,
            pageURL: response.html_url,
            downloadURL: zip?.browser_download_url,
            published: response.published_at.flatMap { ISO8601DateFormatter().date(from: $0) }
        )
    }

    /// Compares dotted versions numerically: 1.10.0 is newer than 1.9.2.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ version: String) -> [Int] {
            version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}
