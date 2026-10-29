// store-publish: packages game apps and uploads them, with their icons and catalog.json, to the
// S3 bucket the launcher's Game Store reads.
//
//   swift run -c release store-publish \
//       --endpoint http://192.168.1.10:30900 --user switchadmin [--bucket switch-games] \
//       "/path/Game One.app" "/path/Game Two.app"
//
//   swift run -c release store-publish --to "/Volumes/games/Switch Store/switch-games" --scan DIR
//
// Each app is archived with Apple Archive (LZFSE) and streamed straight into a multipart upload,
// so no local copy is written (games are often bigger than the free space). The password comes
// from STORE_PASSWORD or is asked for. With --to the same files are written into the bucket's
// folder instead (e.g. a NAS share the store's S3 gateway serves), and no login is needed.

import CryptoKit
import Foundation
import ImageIO
import LauncherCore
import UniformTypeIdentifiers

struct Options {
    enum Target { case s3(endpoint: URL, user: String, password: String), folder(URL) }
    var target: Target
    var bucket = "switch-games"
    var region = "us-east-1"
    var apps: [URL]
    var scanFolders: [URL] = []
    var jobs = 1
    var force = false
    /// Upload speed limit in bytes per second (all jobs together), nil for none.
    var maxRate: Double?

    static let usage = """
    usage: store-publish (--endpoint URL --user NAME | --to DIR) [options] [APP...]
      --to DIR        write into the bucket's folder (e.g. a mounted NAS share) instead of S3
      --scan DIR      also publish every game found in DIR (repeatable)
      --jobs N        upload N games at once (default 1)
      --force         re-upload games already in the store at the same version
      --max-rate MB   limit the upload speed to MB megabytes per second (all jobs together)
      --bucket NAME   default switch-games
      --region NAME   default us-east-1
      The password is read from STORE_PASSWORD, or asked for.
    """

    static func parse(_ arguments: [String]) -> Options? {
        var endpoint: URL?
        var bucket = "switch-games"
        var region = "us-east-1"
        var user = ProcessInfo.processInfo.environment["STORE_USER"]
        var apps: [URL] = []
        var scanFolders: [URL] = []
        var jobs = 1
        var force = false
        var maxRate: Double?
        var folder: URL?
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--to": folder = iterator.next().map { URL(fileURLWithPath: $0, isDirectory: true) }
            case "--endpoint": endpoint = iterator.next().flatMap(URL.init(string:))
            case "--bucket": bucket = iterator.next() ?? bucket
            case "--region": region = iterator.next() ?? region
            case "--user": user = iterator.next()
            case "--scan": iterator.next().map { scanFolders.append(URL(fileURLWithPath: $0, isDirectory: true)) }
            case "--jobs": jobs = max(1, Int(iterator.next() ?? "") ?? 1)
            case "--force": force = true
            case "--max-rate": maxRate = iterator.next().flatMap(Double.init).map { $0 * 1_000_000 }
            case "-h", "--help": return nil
            default: apps.append(URL(fileURLWithPath: argument))
            }
        }
        guard !(apps.isEmpty && scanFolders.isEmpty) else { return nil }
        let target: Target
        if let folder {
            target = .folder(folder)
        } else {
            guard let endpoint, let user else { return nil }
            var password = ProcessInfo.processInfo.environment["STORE_PASSWORD"]
            if password == nil, let typed = getpass("Password for \(user): ") {
                password = String(cString: typed)
            }
            guard let password, !password.isEmpty else { return nil }
            target = .s3(endpoint: endpoint, user: user, password: password)
        }
        return Options(target: target, bucket: bucket, region: region, apps: apps, scanFolders: scanFolders,
                       jobs: jobs, force: force, maxRate: maxRate)
    }
}

struct S3Error: Error, CustomStringConvertible {
    let status: Int
    let body: String
    var description: String { "S3 error \(status): \(body.prefix(300))" }
}

/// Where the publisher writes: the store's S3 bucket, or the folder that holds the bucket's files.
protocol Store: Sendable {
    func read(_ key: String) async throws -> Data?
    func write(_ key: String, _ data: Data, contentType: String) async throws
    func delete(_ key: String) async throws
    /// Writes `chunks` to `key`. Returns total size and SHA-256.
    func writeArchive(_ key: String, chunks: AsyncThrowingStream<Data, Error>, maxRate: Double?,
                      progress: @escaping (Int64) -> Void) async throws -> (Int64, String)
}

/// Sleeps as long as needed to keep `total` bytes since `start` under `maxRate` bytes per second.
func throttle(_ total: Int64, since start: Date, maxRate: Double?) async throws {
    guard let maxRate else { return }
    let due = Double(total) / maxRate - Date().timeIntervalSince(start)
    if due > 0 { try await Task.sleep(for: .seconds(due)) }
}

/// The bucket's folder, e.g. a NAS share mounted over SMB that the store's S3 gateway serves.
/// Files are written under a temporary name and renamed when complete, so the store never serves
/// half-written archives.
struct FolderStore: Store {
    let root: URL

    private func url(_ key: String) -> URL { root.appendingPathComponent(key) }

    func read(_ key: String) async throws -> Data? {
        let file = url(key)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try Data(contentsOf: file)
    }

    func write(_ key: String, _ data: Data, contentType: String) async throws {
        let file = url(key)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }

    func delete(_ key: String) async throws {
        try? FileManager.default.removeItem(at: url(key))
    }

    func writeArchive(_ key: String, chunks: AsyncThrowingStream<Data, Error>, maxRate: Double?,
                      progress: @escaping (Int64) -> Void) async throws -> (Int64, String) {
        let file = url(key)
        let partial = file.appendingPathExtension("partial")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: partial.path, contents: nil)
        let start = Date()
        var hasher = SHA256()
        var total: Int64 = 0
        do {
            let handle = try FileHandle(forWritingTo: partial)
            defer { try? handle.close() }
            for try await chunk in chunks {
                hasher.update(data: chunk)
                try handle.write(contentsOf: chunk)
                total += Int64(chunk.count)
                progress(total)
                try await throttle(total, since: start, maxRate: maxRate)
            }
            try handle.synchronize()
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: partial, to: file)
        return (total, S3Signer.hex(hasher.finalize()))
    }
}

/// The few S3 calls the publisher needs, all through presigned URLs.
struct S3: Store {
    let signer: S3Signer
    let endpoint: URL
    let bucket: String

    @discardableResult
    func send(_ method: String, _ key: String, query: [(String, String)] = [], body: Data? = nil,
              contentType: String? = nil, allow404: Bool = false) async throws -> (Data, HTTPURLResponse)? {
        guard let url = signer.presignedURL(endpoint: endpoint, bucket: bucket, key: key, method: method, query: query) else {
            throw S3Error(status: 0, body: "bad URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 600
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        let (data, response): (Data, URLResponse)
        if let body {
            (data, response) = try await URLSession.shared.upload(for: request, from: body)
        } else {
            (data, response) = try await URLSession.shared.data(for: request)
        }
        let http = response as! HTTPURLResponse
        if allow404 && http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else {
            throw S3Error(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return (data, http)
    }

    /// Streams `chunks` into a multipart upload. Returns total size and SHA-256.
    func multipartUpload(_ key: String, contentType: String, chunks: AsyncThrowingStream<Data, Error>,
                         maxRate: Double? = nil, progress: (Int64) -> Void) async throws -> (Int64, String) {
        let start = Date()
        guard let (data, _) = try await send("POST", key, query: [("uploads", "")], contentType: contentType),
              let uploadID = Self.tag("UploadId", in: data) else { throw S3Error(status: 0, body: "no UploadId") }
        var parts: [(Int, String)] = []
        var hasher = SHA256()
        var total: Int64 = 0
        do {
            for try await chunk in chunks {
                hasher.update(data: chunk)
                let number = parts.count + 1
                let result = try await send("PUT", key, query: [("partNumber", String(number)), ("uploadId", uploadID)], body: chunk)
                guard let etag = result?.1.value(forHTTPHeaderField: "ETag") else { throw S3Error(status: 0, body: "no ETag") }
                parts.append((number, etag))
                total += Int64(chunk.count)
                progress(total)
                try await throttle(total, since: start, maxRate: maxRate)
            }
            let xml = "<CompleteMultipartUpload>" + parts.map {
                "<Part><PartNumber>\($0.0)</PartNumber><ETag>\($0.1)</ETag></Part>"
            }.joined() + "</CompleteMultipartUpload>"
            try await send("POST", key, query: [("uploadId", uploadID)], body: Data(xml.utf8), contentType: "application/xml")
        } catch {
            _ = try? await send("DELETE", key, query: [("uploadId", uploadID)])
            throw error
        }
        return (total, S3Signer.hex(hasher.finalize()))
    }

    func read(_ key: String) async throws -> Data? {
        try await send("GET", key, allow404: true)?.0
    }

    func write(_ key: String, _ data: Data, contentType: String) async throws {
        try await send("PUT", key, body: data, contentType: contentType)
    }

    func delete(_ key: String) async throws {
        try await send("DELETE", key)
    }

    func writeArchive(_ key: String, chunks: AsyncThrowingStream<Data, Error>, maxRate: Double?,
                      progress: @escaping (Int64) -> Void) async throws -> (Int64, String) {
        try await multipartUpload(key, contentType: "application/octet-stream", chunks: chunks, maxRate: maxRate, progress: progress)
    }

    static func tag(_ name: String, in data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8),
              let start = text.range(of: "<\(name)>"),
              let end = text.range(of: "</\(name)>", range: start.upperBound..<text.endIndex) else { return nil }
        return String(text[start.upperBound..<end.lowerBound])
    }
}

/// Runs `aa archive` on the app's contents and yields its output in 64 MB parts.
func archiveChunks(of app: URL, partSize: Int = 64 << 20) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/aa")
        process.arguments = ["archive", "-a", "lzfse", "-d", app.path]
        let output = Pipe()
        process.standardOutput = output
        do {
            try process.run()
        } catch {
            continuation.finish(throwing: error)
            return
        }
        Thread.detachNewThread {
            let handle = output.fileHandleForReading
            var buffer = Data()
            buffer.reserveCapacity(partSize)
            while true {
                let data = handle.readData(ofLength: partSize - buffer.count)
                if data.isEmpty { break }
                buffer.append(data)
                if buffer.count >= partSize {
                    continuation.yield(buffer)
                    buffer = Data()
                    buffer.reserveCapacity(partSize)
                }
            }
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                continuation.finish(throwing: S3Error(status: Int(process.terminationStatus), body: "aa archive failed"))
                return
            }
            if !buffer.isEmpty { continuation.yield(buffer) }
            continuation.finish()
        }
    }
}

func pngIcon(for game: Game) -> Data? {
    guard let url = game.iconURL, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    var best = 0
    var bestWidth = 0
    for index in 0..<CGImageSourceGetCount(source) {
        let width = (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any])?[kCGImagePropertyPixelWidth] as? Int ?? 0
        if width > bestWidth { bestWidth = width; best = index }
    }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: 512,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, best, options as CFDictionary) else { return nil }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
}

func installedSize(of app: URL) -> Int64 {
    guard let enumerator = FileManager.default.enumerator(at: app, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
    var total: Int64 = 0
    for case let url as URL in enumerator {
        total += Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
    }
    return total
}

func slug(_ title: String) -> String {
    let lowered = title.lowercased().folding(options: .diacriticInsensitive, locale: nil)
    let mapped = lowered.map { $0.isLetter || $0.isNumber ? $0 : "-" }
    return String(mapped).split(separator: "-").joined(separator: "-")
}

func line(_ text: String) {
    FileHandle.standardOutput.write(Data((text + "\n").utf8))
}

// MARK: Main

guard let options = Options.parse(Array(CommandLine.arguments.dropFirst())) else {
    FileHandle.standardError.write(Data((Options.usage + "\n").utf8))
    exit(2)
}
let store: any Store
switch options.target {
case let .s3(endpoint, user, password):
    store = S3(signer: S3Signer(accessKey: user, secretKey: password, region: options.region), endpoint: endpoint, bucket: options.bucket)
case let .folder(root):
    guard FileManager.default.fileExists(atPath: root.path) else {
        FileHandle.standardError.write(Data("No such folder: \(root.path)\n".utf8))
        exit(2)
    }
    store = FolderStore(root: root)
}

/// Keeps catalog.json in step with finished uploads. Writes go out one at a time and each carries
/// every entry finished so far, so parallel uploads can't overwrite each other's entries.
actor CatalogWriter {
    private(set) var catalog: StoreCatalog
    private let store: any Store
    private var lastWrite: Task<Void, Error>?

    init(catalog: StoreCatalog, store: any Store) {
        self.catalog = catalog
        self.store = store
    }

    func entry(for id: String) -> StoreGame? {
        catalog.games.first { $0.id == id }
    }

    /// Adds or replaces the entry and uploads the catalog. Returns the replaced entry.
    func upsert(_ entry: StoreGame) async throws -> StoreGame? {
        let previous = catalog.games.first { $0.id == entry.id }
        catalog.games.removeAll { $0.id == entry.id }
        catalog.games.append(entry)
        catalog.games.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let before = lastWrite
        let write = Task {
            _ = try? await before?.value
            try await self.put()
        }
        lastWrite = write
        try await write.value
        return previous
    }

    private func put() async throws {
        catalog.updated = ISO8601DateFormatter().string(from: Date())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try await store.write("catalog.json", try encoder.encode(catalog), contentType: "application/json")
    }
}

enum Outcome { case published, skipped, failed }

func publish(_ app: URL, _ game: Game, writer: CatalogWriter, force: Bool) async -> Outcome {
    let name = slug(game.title)
    let version = game.version ?? "1"
    let archiveKey = "games/\(name)/\(name)-\(version).aar"
    if !force, let existing = await writer.entry(for: game.id), existing.version == game.version {
        line("= \(game.title) \(version) is already in the store")
        return .skipped
    }
    line("▸ \(game.title) \(version) → \(archiveKey)")
    do {
        let start = Date()
        var lastPrint = Date()
        let (size, sha) = try await store.writeArchive(
            archiveKey, chunks: archiveChunks(of: app),
            maxRate: options.maxRate.map { $0 / Double(options.jobs) }
        ) { uploaded in
            if Date().timeIntervalSince(lastPrint) > 30 {
                lastPrint = Date()
                let rate = Double(uploaded) / max(Date().timeIntervalSince(start), 1)
                line("    \(game.title): \(ByteFormatter.string(uploaded)) · \(ByteFormatter.string(Int64(rate)))/s")
            }
        }
        var iconKey: String?
        if let png = pngIcon(for: game) {
            iconKey = "games/\(name)/icon.png"
            try await store.write(iconKey!, png, contentType: "image/png")
        }
        let entry = StoreGame(
            id: game.id, title: game.title, version: game.version, titleID: game.titleID, category: game.category,
            appName: app.lastPathComponent, archive: archiveKey, archiveSize: size,
            installedSize: installedSize(of: app), sha256: sha, icon: iconKey
        )
        if let previous = try await writer.upsert(entry), previous.archive != archiveKey {
            try? await store.delete(previous.archive)
        }
        line("✓ \(game.title): \(ByteFormatter.string(size)) in \(Int(Date().timeIntervalSince(start)))s, sha256 \(sha.prefix(12))…")
        return .published
    } catch {
        line("✗ \(game.title): \(error)")
        return .failed
    }
}

var catalog = StoreCatalog()
do {
    if let data = try await store.read("catalog.json") {
        catalog = try JSONDecoder().decode(StoreCatalog.self, from: data)
    }
} catch {
    line("Couldn't read catalog.json: \(error)")
    exit(1)
}
line("Catalog has \(catalog.games.count) games.")
let writer = CatalogWriter(catalog: catalog, store: store)

// Explicit apps, then everything the launcher would recognise in the scanned folders.
var work: [(URL, Game)] = []
var seen = Set<String>()
var failures = 0
for app in options.apps {
    guard let game = GameScanner().game(at: app, requireNativeMarker: false) else {
        line("✗ \(app.lastPathComponent): not an app bundle")
        failures += 1
        continue
    }
    if seen.insert(game.id).inserted { work.append((app, game)) }
}
for game in GameScanner().scan(folders: options.scanFolders, extraApps: []) where seen.insert(game.id).inserted {
    work.append((game.url, game))
}
line("\(work.count) apps to check, \(options.jobs) at a time.")

var counts: [Outcome: Int] = [:]
await withTaskGroup(of: Outcome.self) { group in
    var queue = work[...]
    func startNext() {
        guard let (app, game) = queue.popFirst() else { return }
        group.addTask { await publish(app, game, writer: writer, force: options.force) }
    }
    for _ in 0..<options.jobs { startNext() }
    while let outcome = await group.next() {
        counts[outcome, default: 0] += 1
        startNext()
    }
}
failures += counts[.failed, default: 0]
line("Done: \(counts[.published, default: 0]) published, \(counts[.skipped, default: 0]) already there, \(failures) failed. Catalog has \(await writer.catalog.games.count) games.")
exit(failures == 0 ? 0 : 1)
