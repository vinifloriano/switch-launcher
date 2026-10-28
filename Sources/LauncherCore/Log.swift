import os

/// Unified logging. Read with:
/// `log stream --predicate 'subsystem == "dev.vinicius.switchlauncher"'`
public enum Log {
    static let subsystem = "dev.vinicius.switchlauncher"

    public static let library = Logger(subsystem: subsystem, category: "library")
    public static let launcher = Logger(subsystem: subsystem, category: "launcher")
    public static let focus = Logger(subsystem: subsystem, category: "focus")
    public static let input = Logger(subsystem: subsystem, category: "input")
}
