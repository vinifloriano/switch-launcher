import AppKit
import CryptoKit
import Foundation
import Observation

/// Talks to the game store bucket: loads `catalog.json`, downloads archives with progress and
/// resume, checks their SHA-256, and installs them with Apple Archive (`aa extract`).
@MainActor @Observable
public final class StoreService {
    public enum State: Equatable {
        case notConfigured
        case loading
        case ready
        case failed(String)
    }

    public enum Phase: Equatable {
        case downloading(received: Int64, total: Int64)
        case verifying
        case installing
        case installed
        case failed(String)

        public var isActive: Bool {
            switch self {
            case .downloading, .verifying, .installing: true
            default: false
            }
        }
    }

    public private(set) var state: State = .notConfigured
    public private(set) var catalog = StoreCatalog()
    /// The endpoint that answered last (LAN or remote).
    public private(set) var activeEndpoint: URL?
    public private(set) var jobs: [String: Phase] = [:]

    /// Called after a game was installed, with the folder it went into.
    @ObservationIgnored public var onInstalled: ((StoreGame, URL) -> Void)?
    @ObservationIgnored private var config = StoreConfig()
    @ObservationIgnored private var delegate: DownloadDelegate!
    @ObservationIgnored private var session: URLSession!
    @ObservationIgnored private var tasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var resumeData: [String: Data] = [:]
    @ObservationIgnored private var pending: [String: (StoreGame, URL)] = [:]

    public init() {
        delegate = DownloadDelegate(owner: self)
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60 * 24
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: .main)
    }

    // MARK: Configuration

    public func configure(_ config: StoreConfig, force: Bool = false) {
        guard force || config != self.config else { return }
        self.config = config
        activeEndpoint = nil
        state = config.isConfigured ? (catalog.games.isEmpty ? .loading : .ready) : .notConfigured
    }

    private var signer: S3Signer? {
        guard config.isConfigured else { return nil }
        return S3Signer(accessKey: config.username, secretKey: config.password, region: config.region)
    }

    /// Signed URL for an object on the endpoint that answered last.
    public func url(for key: String, expires: Int = 6 * 3600) -> URL? {
        guard let signer, let endpoint = activeEndpoint ?? config.endpoints.first else { return nil }
        return signer.presignedURL(endpoint: endpoint, bucket: config.bucket, key: key, expires: expires)
    }

    // MARK: Catalog

    /// Fetches `catalog.json`, trying the home-network address before the remote one.
    public func refresh() async {
        guard config.isConfigured, let signer else {
            state = .notConfigured
            return
        }
        state = .loading
        var lastError = "The store didn't answer."
        for (index, endpoint) in config.endpoints.enumerated() {
            guard let url = signer.presignedURL(endpoint: endpoint, bucket: config.bucket, key: "catalog.json") else { continue }
            var request = URLRequest(url: url)
            // A LAN address that isn't reachable (away from home) should fail fast.
            request.timeoutInterval = index == 0 && config.endpoints.count > 1 ? 4 : 20
            request.cachePolicy = .reloadIgnoringLocalCacheData
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200 else {
                    lastError = status == 403 ? "Wrong username or password." : "The store answered \(status)."
                    if status == 403 { break }
                    continue
                }
                catalog = try JSONDecoder().decode(StoreCatalog.self, from: data)
                catalog.games.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                activeEndpoint = endpoint
                state = .ready
                Log.store.info("Catalog: \(self.catalog.games.count) games from \(endpoint.absoluteString, privacy: .public)")
                return
            } catch is DecodingError {
                lastError = "catalog.json couldn't be read."
            } catch {
                lastError = error.localizedDescription
            }
        }
        Log.store.error("Catalog failed: \(lastError, privacy: .public)")
        state = .failed(lastError)
    }

    // MARK: Downloads

    public func download(_ game: StoreGame, into folder: URL) {
        guard !(jobs[game.id]?.isActive ?? false) else { return }
        let task: URLSessionDownloadTask
        if let data = resumeData.removeValue(forKey: game.id) {
            task = session.downloadTask(withResumeData: data)
        } else {
            guard let url = url(for: game.archive, expires: 24 * 3600) else {
                jobs[game.id] = .failed("The store isn't set up.")
                return
            }
            task = session.downloadTask(with: url)
        }
        task.taskDescription = game.id
        tasks[game.id] = task
        pending[game.id] = (game, folder)
        jobs[game.id] = .downloading(received: 0, total: game.archiveSize)
        Log.store.info("Downloading \(game.title, privacy: .public)")
        task.resume()
    }

    public func cancel(_ id: String) {
        guard let task = tasks.removeValue(forKey: id) else { return }
        task.cancel { _ in }
        pending[id] = nil
        resumeData[id] = nil
        jobs[id] = nil
    }

    public func clearFailure(_ id: String) {
        if case .failed? = jobs[id] { jobs[id] = nil }
    }

    fileprivate func progress(_ id: String, received: Int64, expected: Int64) {
        guard case .downloading? = jobs[id] else { return }
        let total = expected > 0 ? expected : (pending[id]?.0.archiveSize ?? 0)
        jobs[id] = .downloading(received: received, total: total)
    }

    fileprivate func finished(_ id: String, file: URL) {
        tasks[id] = nil
        guard let (game, folder) = pending[id] else { return }
        // The temporary file is deleted when this callback returns, so move it first,
        // next to the install folder (same volume, so the later move is instant).
        let staging = folder.appendingPathComponent(".switch-store", isDirectory: true)
        let archive = staging.appendingPathComponent("\(Self.safeName(game.id)).aar")
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: archive)
            try FileManager.default.moveItem(at: file, to: archive)
        } catch {
            fail(id, "Couldn't save the download: \(error.localizedDescription)")
            return
        }
        jobs[id] = .verifying
        Task { await install(game, archive: archive, folder: folder, staging: staging) }
    }

    fileprivate func failed(_ id: String, error: Error, resumeData data: Data?) {
        tasks[id] = nil
        if let data { resumeData[id] = data }
        if (error as NSError).code == NSURLErrorCancelled, jobs[id] == nil { return }
        fail(id, error.localizedDescription)
    }

    fileprivate func httpFailure(_ id: String, status: Int) {
        tasks[id]?.cancel()
        tasks[id] = nil
        fail(id, status == 403 ? "The download link was refused (403)." : "The store answered \(status).")
    }

    private func fail(_ id: String, _ message: String) {
        Log.store.error("\(id, privacy: .public): \(message, privacy: .public)")
        jobs[id] = .failed(message)
        pending[id] = nil
    }

    private func install(_ game: StoreGame, archive: URL, folder: URL, staging: URL) async {
        let expected = game.sha256.lowercased()
        let actual = await Task.detached(priority: .utility) { Self.sha256(of: archive) }.value
        guard actual == expected else {
            try? FileManager.default.removeItem(at: archive)
            fail(game.id, "The download is damaged (checksum mismatch). Try again.")
            return
        }

        jobs[game.id] = .installing
        let work = staging.appendingPathComponent(Self.safeName(game.id), isDirectory: true)
        let extracted = work.appendingPathComponent(game.appName, isDirectory: true)
        let destination = folder.appendingPathComponent(game.appName, isDirectory: true)
        let result: String? = await Task.detached(priority: .utility) {
            let fm = FileManager.default
            try? fm.removeItem(at: work)
            do {
                try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
            } catch {
                return error.localizedDescription
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/aa")
            process.arguments = ["extract", "-i", archive.path, "-d", extracted.path]
            let errors = Pipe()
            process.standardError = errors
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return error.localizedDescription
            }
            guard process.terminationStatus == 0 else {
                let text = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                return "Extracting failed: \(text.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
            return nil
        }.value
        if let result {
            try? FileManager.default.removeItem(at: work)
            fail(game.id, result)
            return
        }

        // An existing copy goes to the Trash, so nothing is lost if the new one misbehaves.
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try? await NSWorkspace.shared.recycle([destination])
        }
        do {
            try FileManager.default.moveItem(at: extracted, to: destination)
        } catch {
            fail(game.id, "Couldn't install: \(error.localizedDescription)")
            return
        }
        try? FileManager.default.removeItem(at: work)
        try? FileManager.default.removeItem(at: archive)
        try? FileManager.default.removeItem(at: staging)   // only succeeds once it's empty
        pending[game.id] = nil
        jobs[game.id] = .installed
        Log.store.info("Installed \(game.title, privacy: .public) to \(destination.path, privacy: .public)")
        onInstalled?(game, destination)
    }

    nonisolated static func sha256(of url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 8 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return S3Signer.hex(hasher.finalize())
    }

    static func safeName(_ id: String) -> String {
        id.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" }.reduce(into: "") { $0.append($1) }
    }
}

/// URLSession callbacks arrive on the main queue (see `delegateQueue`).
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    weak var owner: StoreService?
    private var lastReport: [Int: Date] = [:]

    init(owner: StoreService) {
        self.owner = owner
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // Four updates a second is plenty for a progress bar.
        let now = Date()
        if let last = lastReport[downloadTask.taskIdentifier], now.timeIntervalSince(last) < 0.25 { return }
        lastReport[downloadTask.taskIdentifier] = now
        guard let id = downloadTask.taskDescription else { return }
        MainActor.assumeIsolated {
            owner?.progress(id, received: totalBytesWritten, expected: totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
        MainActor.assumeIsolated {
            if status == 200 || status == 206 {
                owner?.finished(id, file: location)
            } else {
                owner?.httpFailure(id, status: status)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lastReport[task.taskIdentifier] = nil
        guard let error, let id = task.taskDescription else { return }
        let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        MainActor.assumeIsolated {
            owner?.failed(id, error: error, resumeData: data)
        }
    }
}
