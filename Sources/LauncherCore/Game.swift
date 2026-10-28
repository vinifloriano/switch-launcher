import Foundation

/// One installed piece of software: a native Mac `.app` built from a Switch title.
public struct Game: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let url: URL
    public let bundleIdentifier: String?
    public let titleID: String?
    public let version: String?
    public let iconURL: URL?
    public let category: String?
    public let addedDate: Date?

    public init(
        id: String,
        title: String,
        url: URL,
        bundleIdentifier: String? = nil,
        titleID: String? = nil,
        version: String? = nil,
        iconURL: URL? = nil,
        category: String? = nil,
        addedDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.bundleIdentifier = bundleIdentifier
        self.titleID = titleID
        self.version = version
        self.iconURL = iconURL
        self.category = category
        self.addedDate = addedDate
    }
}

public enum AppPaths {
    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("SwitchLauncher", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
