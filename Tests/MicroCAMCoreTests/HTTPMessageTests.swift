import XCTest
@testable import MicroCAMCore

final class HTTPMessageTests: XCTestCase {
    func raw(_ s: String) -> Data { Data(s.replacingOccurrences(of: "\n", with: "\r\n").utf8) }

    func testParsesGetWithQueryAndHeaders() {
        let r = HTTPRequestParser.parse(raw("GET /stream?viewer=1&x=a%20b HTTP/1.1\nHost: m:8090\nX-MicroCAM-PIN: 1234\n\n"))
        guard case .complete(let req) = r else { return XCTFail("\(r)") }
        XCTAssertEqual(req.method, "GET")
        XCTAssertEqual(req.path, "/stream")
        XCTAssertEqual(req.query, ["viewer": "1", "x": "a b"])
        XCTAssertEqual(req.header("x-microcam-pin"), "1234")
        XCTAssertEqual(req.header("Host"), "m:8090")
    }
    func testIncompleteUntilBodyArrives() {
        XCTAssertEqual(HTTPRequestParser.parse(raw("GET / HTTP/1.1\nHost: x\n")), .incomplete)
        XCTAssertEqual(HTTPRequestParser.parse(raw("POST /photo HTTP/1.1\nContent-Length: 5\n\nab")), .incomplete)
        guard case .complete(let req) = HTTPRequestParser.parse(raw("POST /photo HTTP/1.1\nContent-Length: 2\n\n{}"))
        else { return XCTFail() }
        XCTAssertEqual(req.body, Data("{}".utf8))
    }
    func testRejectsOversizeAndGarbage() {
        XCTAssertEqual(HTTPRequestParser.parse(Data(repeating: 65, count: 20_000)), .invalid)
        XCTAssertEqual(HTTPRequestParser.parse(raw("POST / HTTP/1.1\nContent-Length: 5000000\n\n")), .invalid)
        XCTAssertEqual(HTTPRequestParser.parse(raw("NONSENSE\n\n")), .invalid)
    }
    /// Receive buffers may be slices whose indices do not start at 0; the
    /// header limit must count bytes, not indices.
    func testParsesSliceWithNonZeroStartIndex() {
        let padded = Data(repeating: 0x20, count: 20_000) + raw("GET /status HTTP/1.1\nHost: m\n\n")
        let slice = padded[20_000...]
        guard case .complete(let req) = HTTPRequestParser.parse(slice) else { return XCTFail() }
        XCTAssertEqual(req.path, "/status")
    }
    func testResponseSerialization() {
        let text = String(decoding: HTTPResponse.text(404, "nope").serialized(), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 404 Not Found\r\n"))
        XCTAssertTrue(text.contains("Content-Length: 4\r\n"))
        XCTAssertTrue(text.contains("Connection: close\r\n"))
        XCTAssertTrue(text.contains("Cache-Control: no-store\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n\r\nnope"))
    }
    func testJSONResponse() {
        struct S: Encodable { let a: Int }
        let text = String(decoding: HTTPResponse.json(200, S(a: 1)).serialized(), as: UTF8.self)
        XCTAssertTrue(text.contains("Content-Type: application/json; charset=utf-8"))
        XCTAssertTrue(text.hasSuffix("{\"a\":1}"))
    }
    func testMJPEGFraming() {
        let head = String(decoding: MJPEG.responseHead(), as: UTF8.self)
        XCTAssertTrue(head.contains("Content-Type: multipart/x-mixed-replace; boundary=\(MJPEG.boundary)"))
        let part = MJPEG.part(jpeg: Data([0xFF, 0xD8]))
        XCTAssertTrue(String(decoding: part.prefix(80), as: UTF8.self)
            .hasPrefix("--\(MJPEG.boundary)\r\nContent-Type: image/jpeg\r\nContent-Length: 2\r\n\r\n"))
        XCTAssertEqual(Array(part.suffix(4)), [0xFF, 0xD8, 0x0D, 0x0A])
    }
}
