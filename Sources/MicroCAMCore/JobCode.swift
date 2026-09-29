import Foundation

/// A repair-order number as typed by the technician, e.g. `PR-260042` or `260042`.
/// Only `A–Z`, `0–9` and `-` are allowed: the code becomes a folder name and the
/// file-name prefix, and `_` is the separator inside capture file names.
public struct JobCode: Hashable, Sendable, CustomStringConvertible {
    public static let maxLength = 32
    private static let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")

    public let value: String

    public init?(_ raw: String) {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty,
              normalized.count <= Self.maxLength,
              normalized.first != "-",
              normalized.allSatisfy({ Self.allowed.contains($0) })
        else { return nil }
        value = normalized
    }

    public var description: String { value }
}

extension JobCode: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let code = JobCode(raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Invalid job code: \(raw)"))
        }
        self = code
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
