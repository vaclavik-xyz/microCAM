import Foundation

public struct HTTPRequest: Equatable {
    public let method: String
    public let path: String
    public let query: [String: String]
    public let headers: [String: String]
    public let body: Data

    public func header(_ name: String) -> String? { headers[name.lowercased()] }
}

public enum HTTPParseResult: Equatable {
    case incomplete, invalid, complete(HTTPRequest)
}

/// Minimal HTTP/1.1 request parser for the stream server (one request per
/// connection, `Connection: close`).
public enum HTTPRequestParser {
    public static let maxHeaderBytes = 16_384
    public static let maxBodyBytes = 1_000_000

    public static func parse(_ data: Data) -> HTTPParseResult {
        let separator = Data("\r\n\r\n".utf8)
        guard let end = data.range(of: separator) else {
            return data.count > maxHeaderBytes ? .invalid : .incomplete
        }
        guard end.lowerBound - data.startIndex <= maxHeaderBytes,
              let head = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8) else { return .invalid }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { return .invalid }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0, length <= maxBodyBytes else { return .invalid }
        let bodyStart = end.upperBound
        guard data.count - (bodyStart - data.startIndex) >= length else { return .incomplete }
        let body = data[bodyStart..<(bodyStart + length)]

        let target = String(requestLine[1])
        let components = URLComponents(string: target)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        return .complete(HTTPRequest(method: String(requestLine[0]), path: components?.percentEncodedPath ?? target,
                                     query: query, headers: headers, body: Data(body)))
    }
}

public struct HTTPResponse {
    public var status: Int
    public var headers: [(String, String)]
    public var body: Data

    public init(status: Int, headers: [(String, String)] = [], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public static func text(_ status: Int, _ text: String) -> HTTPResponse {
        HTTPResponse(status: status, headers: [("Content-Type", "text/plain; charset=utf-8")], body: Data(text.utf8))
    }

    public static func html(_ html: String) -> HTTPResponse {
        HTTPResponse(status: 200, headers: [("Content-Type", "text/html; charset=utf-8")], body: Data(html.utf8))
    }

    public static func json<T: Encodable>(_ status: Int, _ value: T) -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return HTTPResponse(status: status, headers: [("Content-Type", "application/json; charset=utf-8")],
                            body: (try? encoder.encode(value)) ?? Data("{}".utf8))
    }

    static let reasons: [Int: String] = [200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden",
                                         404: "Not Found", 405: "Method Not Allowed", 409: "Conflict",
                                         413: "Payload Too Large", 429: "Too Many Requests",
                                         500: "Internal Server Error", 503: "Service Unavailable"]

    public func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reasons[status] ?? "Status")\r\n"
        for (k, v) in headers { head += "\(k): \(v)\r\n" }
        head += "Content-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}
