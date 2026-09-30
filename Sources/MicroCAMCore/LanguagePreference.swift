import Foundation

/// The app's own language setting (Settings → General → Language), stored
/// like macOS does it: `AppleLanguages` in the app's defaults; no value means
/// "follow the system". The choices are the bundle's localizations, so a new
/// `<lang>.lproj` shows up without code changes.
public enum LanguagePreference {
    public static let defaultsKey = "AppleLanguages"

    /// Language codes the user can pick, e.g. `["cs", "en"]`.
    public static func choices(bundleLocalizations: [String]) -> [String] {
        bundleLocalizations.filter { $0 != "Base" }.sorted()
    }

    /// The picked language for a stored `AppleLanguages` value, or nil for "system".
    public static func choice(appleLanguages: [String]?, available: [String]) -> String? {
        guard let first = appleLanguages?.first else { return nil }
        let code = first.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map { String($0).lowercased() }
        return code.flatMap { available.contains($0) ? $0 : nil }
    }

    /// Value to store for a choice; nil removes the key (follow the system).
    public static func appleLanguages(for choice: String?) -> [String]? {
        choice.map { [$0] }
    }
}
