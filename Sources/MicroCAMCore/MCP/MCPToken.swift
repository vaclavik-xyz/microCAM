import Foundation

/// Comparison whose duration does not depend on where two secrets differ.
public enum ConstantTime {
    public static func equals(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        var diff = UInt8(x.count == y.count ? 0 : 1)
        for i in 0..<max(x.count, y.count) {
            diff |= (i < x.count ? x[i] : 0) ^ (i < y.count ? y[i] : 0)
        }
        return diff == 0
    }
}

/// The bearer token agents send to the MCP server.
public enum MCPToken {
    /// 32 random bytes as base64url without padding (43 characters).
    /// `SystemRandomNumberGenerator` is the system CSPRNG (arc4random) on Apple platforms.
    public static func generate() -> String {
        var rng = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &rng) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// At least 32 URL-safe characters: nothing guessable, nothing that breaks the copied command.
    public static func isValid(_ token: String) -> Bool {
        token.count >= 32 && token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    /// The token from an `Authorization: Bearer …` header.
    public static func bearer(from header: String?) -> String? {
        guard let header else { return nil }
        let parts = header.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else { return nil }
        let token = parts[1].trimmingCharacters(in: .whitespaces)
        return token.isEmpty ? nil : token
    }
}
