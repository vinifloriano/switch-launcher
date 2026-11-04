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
    /// Seconds played per day ("yyyy-MM-dd"), for the daily play time limit.
    public private(set) var days: [String: TimeInterval] = [:]
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let daysURL: URL

    public init(fileURL: URL = AppPaths.supportDirectory.appendingPathComponent("play-history.json")) {
        self.fileURL = fileURL
        self.daysURL = fileURL.deletingLastPathComponent().appendingPathComponent("play-days.json")
        records = JSONFileStore.load([String: PlayRecord].self, from: fileURL, label: "play history") ?? [:]
        days = JSONFileStore.load([String: TimeInterval].self, from: daysURL, label: "daily play history") ?? [:]
    }

    public static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Seconds played on `date`'s day, not counting a session still running.
    public func seconds(on date: Date = Date()) -> TimeInterval {
        days[Self.dayKey(date)] ?? 0
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
        // A session over midnight counts toward the day it ended; close enough for a daily limit.
        days[Self.dayKey(date), default: 0] += seconds
        save()
        do {
            try JSONFileStore.save(days, to: daysURL, permissions: 0o600)
        } catch {
            Log.persistence.error("Couldn't save daily play history: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        do {
            try JSONFileStore.save(records, to: fileURL, permissions: 0o600)
        } catch {
            Log.persistence.error("Couldn't save play history: \(error.localizedDescription, privacy: .public)")
        }
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
