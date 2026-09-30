import Foundation

/// Any JSON value, for JSON-RPC messages whose shape depends on the method.
/// Parsed with `JSONSerialization`, which tells `true` from `1` (a
/// `Codable` decoder may not).
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public struct ParseError: Error {}

    public static func parse(_ data: Data) throws -> JSONValue {
        let any = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let value = JSONValue(any: any) else { throw ParseError() }
        return value
    }

    init?(any: Any) {
        switch any {
        case is NSNull: self = .null
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if CFNumberIsFloatType(number) {
                self = .double(number.doubleValue)
            } else {
                self = .int(number.intValue)
            }
        case let string as String: self = .string(string)
        case let array as [Any]:
            var out: [JSONValue] = []
            for item in array {
                guard let value = JSONValue(any: item) else { return nil }
                out.append(value)
            }
            self = .array(out)
        case let dict as [String: Any]:
            var out: [String: JSONValue] = [:]
            for (key, item) in dict {
                guard let value = JSONValue(any: item) else { return nil }
                out[key] = value
            }
            self = .object(out)
        default: return nil
        }
    }

    var any: Any {
        switch self {
        case .null: NSNull()
        case .bool(let b): NSNumber(value: b)
        case .int(let i): NSNumber(value: i)
        case .double(let d): NSNumber(value: d)
        case .string(let s): s
        case .array(let a): a.map(\.any)
        case .object(let o): o.mapValues(\.any)
        }
    }

    /// Compact JSON with sorted keys.
    public func serialized() -> Data {
        (try? JSONSerialization.data(withJSONObject: any, options: [.sortedKeys, .withoutEscapingSlashes,
                                                                    .fragmentsAllowed])) ?? Data("null".utf8)
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var object: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    /// A whole number, also when a client sent it as `5.0`.
    public var integer: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d) where d.rounded() == d && abs(d) < 1e15: return Int(d)
        default: return nil
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { $1 }))
    }
}
