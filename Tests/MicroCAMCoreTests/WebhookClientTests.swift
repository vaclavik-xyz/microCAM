import XCTest
@testable import MicroCAMCore

/// Captures requests instead of hitting the network.
final class StubProtocol: URLProtocol {
    static var status = 200
    static var captured: [URLRequest] = []
    static var bodies: [Data] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.captured.append(request)
        Self.bodies.append(request.httpBody ?? Self.read(request.httpBodyStream))
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func read(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

final class WebhookClientTests: XCTestCase {
    var session: URLSession!

    override func setUp() {
        StubProtocol.status = 200
        StubProtocol.captured = []
        StubProtocol.bodies = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
    }

    func testMultipartContainsFieldsAndFile() {
        let body = MultipartBody(boundary: "B")
            .field("job", "PR-1")
            .file("file", filename: "a.jpg", mimeType: "image/jpeg", data: Data("JPEG".utf8))
            .finalized()
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("--B\r\nContent-Disposition: form-data; name=\"job\"\r\n\r\nPR-1\r\n"))
        XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"file\"; filename=\"a.jpg\"\r\nContent-Type: image/jpeg\r\n\r\nJPEG\r\n"))
        XCTAssertTrue(text.hasSuffix("--B--\r\n"))
    }

    func testUploadSendsAuthorizedMultipartPost() async throws {
        let tmp = TempDir()
        let file = tmp.touch("PR-7/PR-7_2026-09-21_10-00-00.jpg")
        let client = WebhookClient(endpoint: URL(string: "https://example.test/hook")!, token: "secret", session: session)
        try await client.upload(file: file)

        let request = try XCTUnwrap(StubProtocol.captured.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") ?? false)
        let key = try XCTUnwrap(request.value(forHTTPHeaderField: "Idempotency-Key"))
        XCTAssertEqual(key.count, 64) // SHA-256 hex of the content
        let text = String(decoding: StubProtocol.bodies[0], as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"job\"\r\n\r\nPR-7\r\n"))
        XCTAssertTrue(text.contains("name=\"kind\"\r\n\r\nphoto\r\n"))
        XCTAssertTrue(text.contains("name=\"capturedAt\"\r\n\r\n2026-09-21T10:00:00"))
        XCTAssertTrue(text.contains("name=\"idempotencyKey\"\r\n\r\n\(key)\r\n"))
        XCTAssertTrue(text.contains("filename=\"PR-7_2026-09-21_10-00-00.jpg\""))
    }

    func testFilesWithoutJobOmitJobField() async throws {
        let tmp = TempDir()
        let file = tmp.touch("_Nezařazeno/bez-zakazky_2026-09-21_10-00-00.mov")
        try await WebhookClient(endpoint: URL(string: "https://example.test/hook")!, token: nil, session: session)
            .upload(file: file)
        let request = try XCTUnwrap(StubProtocol.captured.first)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let text = String(decoding: StubProtocol.bodies[0], as: UTF8.self)
        XCTAssertFalse(text.contains("name=\"job\""))
        XCTAssertTrue(text.contains("name=\"kind\"\r\n\r\nvideo\r\n"))
        XCTAssertTrue(text.contains("Content-Type: video/quicktime"))
    }

    func testNon2xxThrowsWithStatus() async {
        StubProtocol.status = 401
        let tmp = TempDir()
        let file = tmp.touch("PR-7/PR-7_2026-09-21_10-00-00.jpg")
        do {
            try await WebhookClient(endpoint: URL(string: "https://example.test/hook")!, token: "x", session: session)
                .upload(file: file)
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? WebhookError, .httpStatus(401))
        }
    }

    func testJobCodeFromFileName() {
        XCTAssertEqual(WebhookClient.jobCode(for: URL(fileURLWithPath: "/r/PR-7/Fotky/PR-7_2026-09-21_10-00-00.jpg")), "PR-7")
        XCTAssertNil(WebhookClient.jobCode(for: URL(fileURLWithPath: "/r/microcam_2026-09-21_10-00-00.jpg")))
        XCTAssertNil(WebhookClient.jobCode(for: URL(fileURLWithPath: "/r/_Nezařazeno/bez-zakazky_2026-09-21_10-00-00.jpg")))
    }
}
