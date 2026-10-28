import Foundation
import Observation

public struct PlayRecord: Codable, Equatable, Sendable {
    public var firstPlayed: Date?
    public var lastPlayed: Date?
    public var totalSeconds: TimeInterval = 0
    public var launches: Int = 0

    public init(firstPlayed: Date? = nil, lastPlayed: Date? = nil, totalSeconds: TimeInterval = 0, launches: Int = 0) {
        self.firstPlayed = firstPlayed
        self.lastPlayed = lastPlayed
        self.totalSeconds = totalSeconds
        self.launches = launches
    }
}

/// Play activity per game, persisted as JSON in Application Support.
@MainActor @Observable
public final class PlayHistory {
    public private(set) var records: [String: PlayRecord] = [:]
    @ObservationIgnored private let fileURL: URL

    public init(fileURL: URL = AppPaths.supportDirectory.appendingPathComponent("play-history.json")) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: PlayRecord].self, from: data) {
            records = decoded
        }
    }

    public func record(for id: String) -> PlayRecord {
        records[id] ?? PlayRecord()
    }

    public func markLaunched(_ id: String, at date: Date = Date()) {
        var record = record(for: id)
        record.firstPlayed = record.firstPlayed ?? date
        record.lastPlayed = date
        record.launches += 1
        records[id] = record
        save()
    }

    public func addPlaytime(_ id: String, seconds: TimeInterval, endedAt date: Date = Date()) {
        guard seconds > 0 else { return }
        var record = record(for: id)
        record.totalSeconds += seconds
        record.lastPlayed = date
        records[id] = record
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

public enum PlayTimeFormatter {
    /// "2 hr 15 min", "Less than 1 min", ...
    public static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "Less than 1 min" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .short
        return formatter.string(from: seconds) ?? "\(Int(seconds / 60)) min"
    }

    public static func relative(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
