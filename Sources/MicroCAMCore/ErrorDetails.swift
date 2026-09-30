import Foundation

/// AVFoundation errors often localize to a bare "The operation could not be
/// completed"; the domain, code and underlying error chain are what tells
/// the cause apart (e.g. -11800 ← -12780). Shown in messages and logged.
public enum ErrorDetails {
    public static func describe(_ error: Error?, fallback: String = "?") -> String {
        guard let error else { return fallback }
        var chain: [String] = []
        var current: NSError? = error as NSError
        while let e = current, chain.count < 5 {
            chain.append("\(e.domain) \(e.code)")
            current = e.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return "\((error as NSError).localizedDescription) (\(chain.joined(separator: " ← ")))"
    }
}
