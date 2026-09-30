import Foundation
/// Ports the stream may listen on: unprivileged, so no root is needed.
public enum StreamPort {
    public static let range = 1024...65535

    public static func isValid(_ port: Int) -> Bool { range.contains(port) }

    /// Text from the settings field → port, or nil while it is not usable.
    public static func parse(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isASCII), trimmed.allSatisfy(\.isNumber),
              let port = Int(trimmed), isValid(port) else { return nil }
        return port
    }
}
