import Foundation

/// Runtime localization for model-driven labels. SwiftUI localizes string literals by default,
/// but menu models carry ordinary `String` values, so their rendering passes through here.
public enum L10n {
    public static func text(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }
}
