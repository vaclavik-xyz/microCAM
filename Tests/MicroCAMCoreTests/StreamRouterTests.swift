import XCTest
@testable import MicroCAMCore

private final class FakeBackend: StreamBackend {
    var photos = 0
    var annotated: [AnnotationRequest] = []
    var folders: [URL] = []
    func status() -> StreamStatus { StreamStatus(job: "PR-1", mode: .controls, photoEnabled: true, viewers: 1) }
    func page(mode: StreamMode, embedded: Bool) -> String { "page-\(mode.rawValue)-\(embedded)" }
    func captureFolders() -> [URL] { folders }
    func takePhoto(completion: @escaping (Result<String, Error>) -> Void) {
        photos += 1
        completion(.success("PR-1_2026-09-21_10-00-00.jpg"))
    }
    func saveAnnotated(_ request: AnnotationRequest, source: URL, completion: @escaping (Result<String, Error>) -> Void) {
        annotated.append(request)
        completion(.success("PR-1_2026-09-21_10-00-00_2.jpg"))
    }
}

final class StreamRouterTests: XCTestCase {
    fileprivate var backend: FakeBackend!
    var mode = StreamMode.controls
    var pin: String? = "1234"
    var clock = Date(timeIntervalSince1970: 1_000_000)
    var router: StreamRouter!

    override func setUp() {
        backend = FakeBackend()
        router = StreamRouter(backend: backend, pinGuard: PinGuard(now: { [unowned self] in self.clock }),
                              mode: { [unowned self] in self.mode }, pin: { [unowned self] in self.pin })
    }

    func request(_ method: String, _ target: String, headers: [String: String] = [:], body: String = "") -> HTTPRequest {
        var raw = "\(method) \(target) HTTP/1.1\r\nHost: bench:8090\r\n"
        for (k, v) in headers { raw += "\(k): \(v)\r\n" }
        raw += "Content-Length: \(body.utf8.count)\r\n\r\n\(body)"
        guard case .complete(let r) = HTTPRequestParser.parse(Data(raw.utf8)) else { fatalError() }
        return r
    }

    func route(_ r: HTTPRequest) -> StreamRoute {
        var out: StreamRoute?
        router.handle(r) { out = $0 }
        return out!
    }

    func status(_ route: StreamRoute) -> Int {
        if case .response(let r) = route { return r.status }
        return -1
    }

    func testPageStatusAndStream() {
        guard case .response(let page) = route(request("GET", "/?embedded=1")) else { return XCTFail() }
        XCTAssertEqual(String(decoding: page.body, as: UTF8.self), "page-controls-true")
        XCTAssertEqual(status(route(request("GET", "/status"))), 200)
        guard case .stream = route(request("GET", "/stream")) else { return XCTFail("expected stream") }
    }

    func testPhotoRequiresPostPinAndSameOrigin() {
        XCTAssertEqual(status(route(request("GET", "/photo"))), 405)
        XCTAssertEqual(status(route(request("POST", "/photo"))), 401)
        XCTAssertEqual(status(route(request("POST", "/photo", headers: ["X-MicroCAM-PIN": "9999"]))), 401)
        XCTAssertEqual(status(route(request("POST", "/photo", headers: ["X-MicroCAM-PIN": "1234",
                                                                        "Origin": "https://evil.example"]))), 403)
        XCTAssertEqual(backend.photos, 0)
        XCTAssertEqual(status(route(request("POST", "/photo", headers: ["X-MicroCAM-PIN": "1234",
                                                                        "Origin": "http://bench:8090"]))), 200)
        XCTAssertEqual(backend.photos, 1)
    }

    func testImageOnlyModeDisablesRemoteActions() {
        mode = .imageOnly
        XCTAssertEqual(status(route(request("POST", "/photo", headers: ["X-MicroCAM-PIN": "1234"]))), 403)
        XCTAssertEqual(status(route(request("GET", "/captures/PR-1_2026-09-21_10-00-00.jpg"))), 403)
        XCTAssertEqual(backend.photos, 0)
    }

    func testMissingPinDisablesPhotos() {
        pin = nil
        XCTAssertEqual(status(route(request("POST", "/photo", headers: ["X-MicroCAM-PIN": "1234"]))), 403)
    }

    func testLockoutReturns429() {
        for _ in 0..<5 { _ = route(request("POST", "/photo", headers: ["X-MicroCAM-PIN": "0000"])) }
        XCTAssertEqual(status(route(request("POST", "/photo", headers: ["X-MicroCAM-PIN": "1234"]))), 429)
    }

    func testCapturesAreGuarded() throws {
        let tmp = TempDir()
        tmp.touch("PR-1/PR-1_2026-09-21_10-00-00.jpg")
        backend.folders = [tmp.url.appendingPathComponent("PR-1")]
        let pinHeader = ["X-MicroCAM-PIN": "1234"]
        guard case .response(let ok) = route(request("GET", "/captures/PR-1_2026-09-21_10-00-00.jpg",
                                                     headers: pinHeader)) else { return XCTFail() }
        XCTAssertEqual(ok.status, 200)
        XCTAssertTrue(ok.headers.contains { $0 == ("Content-Type", "image/jpeg") })
        XCTAssertEqual(status(route(request("GET", "/captures/..%2F..%2Fsecret.txt", headers: pinHeader))), 404)
    }

    /// Job photos are customer data: reading them needs the PIN like the other remote actions.
    func testCapturesRequirePin() {
        let tmp = TempDir()
        tmp.touch("PR-1/PR-1_2026-09-21_10-00-00.jpg")
        backend.folders = [tmp.url.appendingPathComponent("PR-1")]
        XCTAssertEqual(status(route(request("GET", "/captures/PR-1_2026-09-21_10-00-00.jpg"))), 401)
        XCTAssertEqual(status(route(request("GET", "/captures/PR-1_2026-09-21_10-00-00.jpg",
                                            headers: ["X-MicroCAM-PIN": "9999"]))), 401)
        pin = nil
        XCTAssertEqual(status(route(request("GET", "/captures/PR-1_2026-09-21_10-00-00.jpg",
                                            headers: ["X-MicroCAM-PIN": "1234"]))), 403)
        XCTAssertEqual(status(route(request("POST", "/captures/PR-1_2026-09-21_10-00-00.jpg"))), 405)
    }

    func testAnnotatedValidatesJSONAndSource() {
        let tmp = TempDir()
        tmp.touch("PR-1/PR-1_2026-09-21_10-00-00.jpg")
        backend.folders = [tmp.url.appendingPathComponent("PR-1")]
        let pinHeader = ["X-MicroCAM-PIN": "1234"]
        XCTAssertEqual(status(route(request("POST", "/annotated", headers: pinHeader, body: "not json"))), 400)
        XCTAssertEqual(status(route(request("POST", "/annotated", headers: pinHeader,
                                            body: #"{"source":"nope.jpg","shapes":[]}"#))), 404)
        let body = ##"{"source":"PR-1_2026-09-21_10-00-00.jpg","shapes":[{"kind":"arrow","points":[{"x":0.1,"y":0.1},{"x":0.5,"y":0.5}],"color":"#ff0000","width":0.01}]}"##
        XCTAssertEqual(status(route(request("POST", "/annotated", headers: pinHeader, body: body))), 200)
        XCTAssertEqual(backend.annotated.first?.shapes.count, 1)
    }

    func testUnknownAndOptions() {
        XCTAssertEqual(status(route(request("GET", "/nope"))), 404)
        XCTAssertEqual(status(route(request("OPTIONS", "/photo"))), 405)
    }
}
