import AppKit
import CryptoKit
import Foundation
import Observation

/// Talks to the game store bucket: loads `catalog.json`, downloads archives with progress and
/// resume, checks their SHA-256, and installs them with Apple Archive (`aa extract`).
///
/// Downloads go into `<install folder>/.switch-store/<id>.aar.partial`. When the connection drops
/// or the server answers with an error (a 503 from the tunnel, a timeout), the download carries on
/// from the last byte received with a Range request, retrying until `retryWindow` passes without
/// progress. The partial file also survives quitting the launcher, so starting the download again
/// continues where it stopped.
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
        /// The connection dropped; waiting to continue from `received`.
        case reconnecting(received: Int64, total: Int64)
        case verifying
        case installing
        case installed
        case failed(String)

        public var isActive: Bool {
            switch self {
            case .downloading, .reconnecting, .verifying, .installing: true
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
    @ObservationIgnored private var tasks: [String: URLSessionDataTask] = [:]
    @ObservationIgnored private var pending: [String: (StoreGame, URL)] = [:]
    @ObservationIgnored private var attempts: [String: Int] = [:]
    /// When each download last received data.
    @ObservationIgnored private var lastProgress: [String: Date] = [:]
    /// A download gives up after this long without receiving anything, however many retries that takes.
    nonisolated static let retryWindow: TimeInterval = 10 * 60

    public init() {
        delegate = DownloadDelegate(owner: self)
        let configuration = URLSessionConfiguration.default
        // A stalled connection fails after a minute and is retried from where it stopped.
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60 * 24
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let queue = OperationQueue()
        queue.name = "SwitchLauncher.store-downloads"
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: queue)
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

    nonisolated static func partialURL(for game: StoreGame, in folder: URL) -> URL {
        folder.appendingPathComponent(".switch-store/\(safeName(game.id)).aar.partial")
    }

    /// Records which archive a partial file belongs to, so a new version starts afresh.
    nonisolated static func partialInfoURL(for game: StoreGame, in folder: URL) -> URL {
        partialURL(for: game, in: folder).appendingPathExtension("sha256")
    }

    nonisolated static func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    public func download(_ game: StoreGame, into folder: URL) {
        guard !(jobs[game.id]?.isActive ?? false) else { return }
        let partial = Self.partialURL(for: game, in: folder)
        let info = Self.partialInfoURL(for: game, in: folder)
        do {
            try FileManager.default.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Keep what an earlier attempt downloaded, if it was the same archive.
            let previous = try? String(contentsOf: info, encoding: .utf8)
            if previous != game.sha256 || Self.fileSize(partial) > game.archiveSize {
                try? FileManager.default.removeItem(at: partial)
            }
            try game.sha256.write(to: info, atomically: true, encoding: .utf8)
        } catch {
            jobs[game.id] = .failed("Couldn't save the download: \(error.localizedDescription)")
            return
        }
        let offset = Self.fileSize(partial)
        attempts[game.id] = 0
        lastProgress[game.id] = Date()
        pending[game.id] = (game, folder)
        jobs[game.id] = .downloading(received: offset, total: game.archiveSize)
        Log.store.info("Downloading \(game.title, privacy: .public)\(offset > 0 ? " from byte \(offset)" : "", privacy: .public)")
        startTask(game, into: folder)
    }

    private func startTask(_ game: StoreGame, into folder: URL) {
        let partial = Self.partialURL(for: game, in: folder)
        let offset = Self.fileSize(partial)
        if offset == game.archiveSize {
            completeDownload(game, folder: folder)
            return
        }
        guard let url = url(for: game.archive, expires: 24 * 3600) else {
            fail(game.id, "The store isn't set up.")
            return
        }
        var request = URLRequest(url: url)
        if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
        let task = session.dataTask(with: request)
        task.taskDescription = game.id
        delegate.register(task, file: partial, offset: offset)
        tasks[game.id] = task
        task.resume()
    }

    public func cancel(_ id: String) {
        let task = tasks.removeValue(forKey: id)
        task?.cancel()
        // A stopped download is thrown away; one that failed keeps its partial file to continue later.
        if let (game, folder) = pending[id] {
            try? FileManager.default.removeItem(at: Self.partialURL(for: game, in: folder))
            try? FileManager.default.removeItem(at: Self.partialInfoURL(for: game, in: folder))
        }
        pending[id] = nil
        attempts[id] = nil
        lastProgress[id] = nil
        jobs[id] = nil
    }

    public func clearFailure(_ id: String) {
        if case .failed? = jobs[id] { jobs[id] = nil }
    }

    fileprivate func progress(_ id: String, received: Int64) {
        guard let (game, _) = pending[id], tasks[id] != nil else { return }
        lastProgress[id] = Date()
        attempts[id] = 0
        jobs[id] = .downloading(received: received, total: game.archiveSize)
    }

    fileprivate enum TaskEnd {
        case finished
        case status(Int)
        case error(Error)
    }

    fileprivate func taskEnded(_ id: String, _ end: TaskEnd) {
        tasks[id] = nil
        // Stopped by the user.
        guard let (game, folder) = pending[id] else { return }
        let partial = Self.partialURL(for: game, in: folder)
        let size = Self.fileSize(partial)
        switch end {
        case .finished where size == game.archiveSize:
            completeDownload(game, folder: folder)
        case .finished where size > game.archiveSize:
            try? FileManager.default.removeItem(at: partial)
            retry(game, folder: folder, reason: "the download came out too long; starting over")
        case .finished:
            retry(game, folder: folder, reason: "the connection ended early")
        case .status(let status) where status == 416 && size == game.archiveSize:
            completeDownload(game, folder: folder)
        case .status(403):
            fail(id, "The download link was refused (403). Check the store password.")
        case .status(404):
            fail(id, "This game is no longer in the store (404).")
        case .status(let status):
            retry(game, folder: folder, reason: "the store answered \(status)")
        case .error(let error):
            retry(game, folder: folder, reason: error.localizedDescription)
        }
    }

    /// Tries again from the bytes already saved, after a short wait that grows to 30 seconds.
    private func retry(_ game: StoreGame, folder: URL, reason: String) {
        let id = game.id
        let received = Self.fileSize(Self.partialURL(for: game, in: folder))
        let quiet = Date().timeIntervalSince(lastProgress[id] ?? Date())
        guard quiet < Self.retryWindow else {
            fail(id, "The store stopped answering (\(reason)). Press A to continue the download.")
            return
        }
        let attempt = (attempts[id] ?? 0) + 1
        attempts[id] = attempt
        jobs[id] = .reconnecting(received: received, total: game.archiveSize)
        let delay = min(pow(2, Double(attempt)), 30)
        Log.store.info("\(game.title, privacy: .public): \(reason, privacy: .public); continuing from byte \(received) in \(Int(delay))s (attempt \(attempt))")
        Task {
            try? await Task.sleep(for: .seconds(delay))
            guard pending[id] != nil, tasks[id] == nil else { return }
            // Every few attempts look for the store again: away from home only the remote address works.
            if attempt % 3 == 0 { await refresh() }
            guard pending[id] != nil, tasks[id] == nil else { return }
            startTask(game, into: folder)
        }
    }

    private func completeDownload(_ game: StoreGame, folder: URL) {
        let staging = folder.appendingPathComponent(".switch-store", isDirectory: true)
        let archive = staging.appendingPathComponent("\(Self.safeName(game.id)).aar")
        do {
            try? FileManager.default.removeItem(at: archive)
            try FileManager.default.moveItem(at: Self.partialURL(for: game, in: folder), to: archive)
            try? FileManager.default.removeItem(at: Self.partialInfoURL(for: game, in: folder))
        } catch {
            fail(game.id, "Couldn't save the download: \(error.localizedDescription)")
            return
        }
        lastProgress[game.id] = nil
        jobs[game.id] = .verifying
        Task { await install(game, archive: archive, folder: folder, staging: staging) }
    }

    private func fail(_ id: String, _ message: String) {
        Log.store.error("\(id, privacy: .public): \(message, privacy: .public)")
        tasks.removeValue(forKey: id)?.cancel()
        jobs[id] = .failed(message)
        pending[id] = nil
        attempts[id] = nil
        lastProgress[id] = nil
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
        attempts[game.id] = nil
        jobs[game.id] = .installed
        Log.store.info("Installed \(game.title, privacy: .public) to \(destination.path, privacy: .public)")
        onInstalled?(game, destination)
    }

    nonisolated static func sha256(ofData data: Data) -> String {
        S3Signer.hex(SHA256.hash(data: data))
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

    nonisolated static func safeName(_ id: String) -> String {
        id.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" }.reduce(into: "") { $0.append($1) }
    }
}

/// Writes each download straight into its partial file. Callbacks arrive on the session's own
/// serial queue; state changes are handed to the store on the main actor.
private final class DownloadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct Transfer {
        let id: String
        let file: URL
        var offset: Int64
        var handle: FileHandle?
        var written: Int64 = 0
        var status = 0
        var lastReport = Date.distantPast
    }

    weak var owner: StoreService?
    private let lock = NSLock()
    private var transfers: [Int: Transfer] = [:]

    init(owner: StoreService) {
        self.owner = owner
    }

    /// Called before the task starts.
    func register(_ task: URLSessionDataTask, file: URL, offset: Int64) {
        guard let id = task.taskDescription else { return }
        lock.withLock { transfers[task.taskIdentifier] = Transfer(id: id, file: file, offset: offset) }
    }

    private func update(_ task: URLSessionTask, _ change: (inout Transfer) -> Void) -> Transfer? {
        lock.withLock {
            guard var transfer = transfers[task.taskIdentifier] else { return nil }
            change(&transfer)
            transfers[task.taskIdentifier] = transfer
            return transfer
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        var allow = false
        _ = update(dataTask) { transfer in
            transfer.status = status
            // 206 continues at the byte the server says; 200 means the whole file from the start.
            let start: Int64?
            switch status {
            case 206: start = Self.rangeStart(response) ?? transfer.offset
            case 200: start = 0
            default: start = nil
            }
            guard let start, start <= transfer.offset,
                  let handle = try? FileHandle(forWritingTo: Self.ensureFile(transfer.file)) else { return }
            try? handle.truncate(atOffset: UInt64(start))
            try? handle.seekToEnd()
            transfer.offset = start
            transfer.handle = handle
            allow = true
        }
        completionHandler(allow ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        var report: (String, Int64)?
        _ = update(dataTask) { transfer in
            guard let handle = transfer.handle else { return }
            do {
                try handle.write(contentsOf: data)
            } catch {
                dataTask.cancel()
                return
            }
            transfer.written += Int64(data.count)
            // Four updates a second is plenty for a progress bar.
            let now = Date()
            if now.timeIntervalSince(transfer.lastReport) >= 0.25 {
                transfer.lastReport = now
                report = (transfer.id, transfer.offset + transfer.written)
            }
        }
        if let (id, received) = report {
            DispatchQueue.main.async { [weak owner] in
                MainActor.assumeIsolated { owner?.progress(id, received: received) }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let transfer = lock.withLock { transfers.removeValue(forKey: task.taskIdentifier) }
        guard let transfer else { return }
        try? transfer.handle?.synchronize()
        try? transfer.handle?.close()
        let end: StoreService.TaskEnd
        if transfer.status != 0, transfer.status != 200, transfer.status != 206 {
            end = .status(transfer.status)
        } else if let error {
            end = .error(error)
        } else {
            end = .finished
        }
        DispatchQueue.main.async { [weak owner] in
            MainActor.assumeIsolated { owner?.taskEnded(transfer.id, end) }
        }
    }

    /// The first byte in `Content-Range: bytes 1000-1999/5000`.
    static func rangeStart(_ response: URLResponse) -> Int64? {
        guard let header = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Range"),
              let range = header.split(separator: " ").last?.split(separator: "-").first else { return nil }
        return Int64(range)
    }

    private static func ensureFile(_ url: URL) -> URL {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        return url
    }
}
