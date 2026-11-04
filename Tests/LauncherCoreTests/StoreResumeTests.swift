import Foundation
@testable import LauncherCore
import Network
import XCTest

/// A store that misbehaves like a flaky tunnel: the first download is cut part way, the next
/// request gets a 503, and later requests are served from the byte asked for.
private final class FlakyStore: @unchecked Sendable {
    let archive: Data
    private(set) var ranges: [String?] = []
    private let listener: NWListener
    private let queue = DispatchQueue(label: "FlakyStore")
    private let lock = NSLock()

    init(archive: Data) throws {
        self.archive = archive
        listener = try NWListener(using: .tcp, on: .any)
    }

    var port: UInt16 { listener.port?.rawValue ?? 0 }

    func start() async throws {
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: self?.queue ?? .main)
            self?.read(connection, buffer: Data())
        }
        listener.start(queue: queue)
        for _ in 0..<100 where listener.port == nil || listener.state != .ready {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func stop() { listener.cancel() }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, _ in
            guard let self else { return }
            let buffer = buffer + (data ?? Data())
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                self.respond(connection, head: String(decoding: buffer[..<end.lowerBound], as: UTF8.self))
            } else if !done {
                self.read(connection, buffer: buffer)
            }
        }
    }

    private func respond(_ connection: NWConnection, head: String) {
        let range = head.split(separator: "\r\n")
            .first { $0.lowercased().hasPrefix("range:") }
            .map { String($0.dropFirst("range:".count)).trimmingCharacters(in: .whitespaces) }
        let request = lock.withLock { () -> Int in
            ranges.append(range)
            return ranges.count
        }
        let total = archive.count
        switch request {
        case 1:
            // Promise everything, send 40 %, then drop the connection.
            let cut = total * 4 / 10
            let header = "HTTP/1.1 200 OK\r\nContent-Length: \(total)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(header.utf8) + archive.prefix(cut), completion: .contentProcessed { _ in
                connection.cancel()
            })
        case 2:
            let body = "Service Unavailable"
            let header = "HTTP/1.1 503 Service Unavailable\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data((header + body).utf8), completion: .contentProcessed { _ in connection.cancel() })
        default:
            let start = range.flatMap { Int($0.dropFirst("bytes=".count).split(separator: "-").first ?? "") } ?? 0
            let header = "HTTP/1.1 206 Partial Content\r\nContent-Length: \(total - start)\r\n"
                + "Content-Range: bytes \(start)-\(total - 1)/\(total)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(header.utf8) + archive.suffix(from: start), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}

final class StoreResumeTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A small game app packed the way store-publish packs it.
    private func makeArchive() throws -> Data {
        let app = folder.appendingPathComponent("src/Test Game.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "org.nxnative.test", "CFBundleName": "Test Game", "DMTitleID": "0100000000000001"]
        (info as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"), atomically: true)
        var bytes = [UInt8](repeating: 0, count: 3_000_000)
        for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255) }
        try Data(bytes).write(to: contents.appendingPathComponent("Resources/romfs.bin"))
        let archive = folder.appendingPathComponent("game.aar")
        let aa = Process()
        aa.executableURL = URL(fileURLWithPath: "/usr/bin/aa")
        aa.arguments = ["archive", "-d", app.path, "-o", archive.path, "-a", "raw"]
        try aa.run()
        aa.waitUntilExit()
        XCTAssertEqual(aa.terminationStatus, 0)
        return try Data(contentsOf: archive)
    }

    @MainActor
    func testContinuesFromWhereItStoppedAfterADropAndA503() async throws {
        let data = try makeArchive()
        let server = try FlakyStore(archive: data)
        try await server.start()
        defer { server.stop() }

        var config = StoreConfig()
        config.localEndpoint = "http://127.0.0.1:\(server.port)"
        config.username = "test"
        config.password = "test"
        let service = StoreService()
        service.configure(config)
        let game = StoreGame(id: "org.nxnative.test", title: "Test Game", appName: "Test Game.app",
                             archive: "games/test/test-1.aar", archiveSize: Int64(data.count),
                             sha256: StoreService.sha256(ofData: data))
        let install = folder.appendingPathComponent("apps", isDirectory: true)
        try FileManager.default.createDirectory(at: install, withIntermediateDirectories: true)

        var sawReconnecting = false
        service.download(game, into: install)
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            if case .reconnecting? = service.jobs[game.id] { sawReconnecting = true }
            if case .installed? = service.jobs[game.id] { break }
            if case .failed(let message)? = service.jobs[game.id] { return XCTFail("Download failed: \(message)") }
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertEqual(service.jobs[game.id], .installed)
        XCTAssertTrue(sawReconnecting)
        // First a full request, then two that continue from where the cut left off.
        XCTAssertEqual(server.ranges.count, 3)
        XCTAssertNil(server.ranges[0])
        let resumed = "bytes=\(data.count * 4 / 10)-"
        XCTAssertEqual(server.ranges[1], resumed)
        XCTAssertEqual(server.ranges[2], resumed)
        let installed = install.appendingPathComponent("Test Game.app/Contents/Resources/romfs.bin")
        XCTAssertEqual(try Data(contentsOf: installed).count, 3_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: install.appendingPathComponent(".switch-store").path))
    }

    @MainActor
    func testPartialFileSitsInTheStagingFolder() throws {
        let game = StoreGame(id: "g", title: "G", appName: "G.app", archive: "a", archiveSize: 10, sha256: "abc")
        let partial = StoreService.partialURL(for: game, in: folder)
        XCTAssertEqual(partial.lastPathComponent, "g.aar.partial")
        XCTAssertEqual(StoreService.partialInfoURL(for: game, in: folder).lastPathComponent, "g.aar.partial.sha256")
    }
}
