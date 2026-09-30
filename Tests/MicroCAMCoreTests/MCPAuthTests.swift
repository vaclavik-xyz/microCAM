import XCTest
@testable import MicroCAMCore

final class JSONValueTests: XCTestCase {
    func testParsesTypesWithoutConfusingBoolsAndNumbers() throws {
        let value = try JSONValue.parse(Data(#"{"a":1,"b":true,"c":1.5,"d":"x","e":null,"f":[0,false]}"#.utf8))
        XCTAssertEqual(value, .object(["a": .int(1), "b": .bool(true), "c": .double(1.5), "d": .string("x"),
                                       "e": .null, "f": .array([.int(0), .bool(false)])]))
    }

    func testSerializesWithSortedKeysAndRoundTrips() throws {
        let value = JSONValue.object(["b": .int(2), "a": .string("x/y"), "c": .bool(false), "d": .double(0.5)])
        let text = String(decoding: value.serialized(), as: UTF8.self)
        XCTAssertEqual(text, #"{"a":"x/y","b":2,"c":false,"d":0.5}"#)
        XCTAssertEqual(try JSONValue.parse(value.serialized()), value)
    }

    func testRejectsInvalidJSON() {
        XCTAssertThrowsError(try JSONValue.parse(Data("{nope".utf8)))
    }

    func testIntegerAcceptsWholeDoubles() {
        XCTAssertEqual(JSONValue.int(5).integer, 5)
        XCTAssertEqual(JSONValue.double(5.0).integer, 5)
        XCTAssertNil(JSONValue.double(5.5).integer)
        XCTAssertNil(JSONValue.string("5").integer)
        XCTAssertNil(JSONValue.bool(true).integer)
    }
}

final class MCPTokenTests: XCTestCase {
    func testGeneratedTokensAreLongURLSafeAndDifferent() {
        let a = MCPToken.generate(), b = MCPToken.generate()
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a.count, 43)   // 32 random bytes, base64url without padding
        XCTAssertTrue(a.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        XCTAssertTrue(MCPToken.isValid(a))
    }

    func testValidTokenFormat() {
        XCTAssertFalse(MCPToken.isValid(""))
        XCTAssertFalse(MCPToken.isValid("short"))
        XCTAssertFalse(MCPToken.isValid(String(repeating: "a", count: 40) + " b"))
        XCTAssertTrue(MCPToken.isValid(String(repeating: "a", count: 32)))
    }

    func testBearerParsing() {
        XCTAssertEqual(MCPToken.bearer(from: "Bearer abc"), "abc")
        XCTAssertEqual(MCPToken.bearer(from: "bearer   abc "), "abc")
        XCTAssertNil(MCPToken.bearer(from: "Basic abc"))
        XCTAssertNil(MCPToken.bearer(from: "Bearer"))
        XCTAssertNil(MCPToken.bearer(from: nil))
    }

    func testConstantTimeEquals() {
        XCTAssertTrue(ConstantTime.equals("abc", "abc"))
        XCTAssertFalse(ConstantTime.equals("abc", "abd"))
        XCTAssertFalse(ConstantTime.equals("abc", "abcd"))
        XCTAssertFalse(ConstantTime.equals("", "a"))
    }
}

final class MCPAuthGuardTests: XCTestCase {
    var clock = Date(timeIntervalSince1970: 1_000_000)
    let token = String(repeating: "t", count: 43)

    func makeGuard() -> MCPAuthGuard { MCPAuthGuard(maxFailures: 5, lockout: 300, now: { [unowned self] in self.clock }) }

    func testOkWrongAndNotConfigured() {
        let g = makeGuard()
        XCTAssertEqual(g.check("Bearer \(token)", expected: token, peer: "10.0.0.2"), .ok)
        XCTAssertEqual(g.check("Bearer nope", expected: token, peer: "10.0.0.2"), .unauthorized)
        XCTAssertEqual(g.check(nil, expected: token, peer: "10.0.0.2"), .unauthorized)
        XCTAssertEqual(g.check("Bearer \(token)", expected: nil, peer: "10.0.0.2"), .notConfigured)
        XCTAssertEqual(g.check("Bearer \(token)", expected: "", peer: "10.0.0.2"), .notConfigured)
    }

    func testLocksOnlyTheOffendingAddress() {
        let g = makeGuard()
        for _ in 0..<5 { XCTAssertEqual(g.check("Bearer bad", expected: token, peer: "10.0.0.9"), .unauthorized) }
        let until = clock.addingTimeInterval(300)
        // Even the right token is refused from the locked address…
        XCTAssertEqual(g.check("Bearer \(token)", expected: token, peer: "10.0.0.9"), .locked(until: until))
        // …while another machine still gets in.
        XCTAssertEqual(g.check("Bearer \(token)", expected: token, peer: "10.0.0.2"), .ok)
        clock = clock.addingTimeInterval(301)
        XCTAssertEqual(g.check("Bearer \(token)", expected: token, peer: "10.0.0.9"), .ok)
    }

    func testSuccessResetsFailures() {
        let g = makeGuard()
        for _ in 0..<4 { _ = g.check("Bearer bad", expected: token, peer: "10.0.0.9") }
        XCTAssertEqual(g.check("Bearer \(token)", expected: token, peer: "10.0.0.9"), .ok)
        for _ in 0..<4 { XCTAssertEqual(g.check("Bearer bad", expected: token, peer: "10.0.0.9"), .unauthorized) }
    }

    func testForgetsOldEntriesSoTheTableStaysSmall() {
        let g = MCPAuthGuard(maxFailures: 5, lockout: 300, maxTracked: 3, now: { [unowned self] in self.clock })
        for i in 0..<10 { _ = g.check("Bearer bad", expected: token, peer: "10.0.0.\(i)") }
        XCTAssertLessThanOrEqual(g.trackedCount, 3)
    }
}

final class MCPClientConfigTests: XCTestCase {
    func testURL() {
        XCTAssertEqual(MCPClientConfig.url(address: "192.0.2.10", port: 8091), "http://192.0.2.10:8091/mcp")
        XCTAssertEqual(MCPClientConfig.url(address: "fd7a::1", port: 8091), "http://[fd7a::1]:8091/mcp")
    }

    /// The common `mcpServers` shape most MCP clients read: URL plus the Authorization header.
    func testGenericClientConfiguration() throws {
        let text = MCPClientConfig.json(address: "192.0.2.10", port: 8091, token: "abc_DEF-123")
        let value = try JSONValue.parse(Data(text.utf8))
        let server = value["mcpServers"]?["microcam"]
        XCTAssertEqual(server?["type"], "http")
        XCTAssertEqual(server?["url"], "http://192.0.2.10:8091/mcp")
        XCTAssertEqual(server?["headers"]?["Authorization"], "Bearer abc_DEF-123")
        XCTAssertTrue(text.contains("\n"), "pretty-printed for pasting")
    }
}
