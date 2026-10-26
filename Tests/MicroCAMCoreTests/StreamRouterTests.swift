import ImageIO
import XCTest
@testable import MicroCAMCore

private final class FakeBackend: StreamBackend {
    var photos = 0
    var delays: [Int] = []
    var photoResult: Result<String, Error> = .success("PR-1_2026-09-21_10-00-00.jpg")
    var annotated: [AnnotationRequest] = []
    var annotatedSources: [URL] = []
    var storageValue: StreamStorage?
    func status() -> StreamStatus { StreamStatus(job: "PR-1", mode: .controls, photoEnabled: true, viewers: 1) }
    func page(mode: StreamMode, embedded: Bool) -> String { "page-\(mode.rawValue)-\(embedded)" }
    func storage() -> StreamStorage? { storageValue }
    func takePhoto(delay: Int, completion: @escaping (Result<String, Error>) -> Void) {
        photos += 1
        delays.append(delay)
        completion(photoResult)
    }
    func saveAnnotated(_ request: AnnotationRequest, source: URL, completion: @escaping (Result<String, Error>) -> Void) {
        annotated.append(request)
        annotatedSources.append(source)
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
                              mode: { [unowned self] in self.mode }, pin: { [unowned self] in self.pin },
                              work: { $0() })
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

    /// Storage under `dir` with jobs on and PR-1 as the current job.
    func useStorage(_ dir: TempDir, context: JobContext = .job(JobCode("PR-1")!)) {
        backend.storageValue = StreamStorage(layout: StorageLayout(root: dir.url, language: .english), context: context)
    }

    func testPageStatusAndStream() {
        guard case .response(let page) = route(request("GET", "/?embedded=1")) else { return XCTFail() }
        XCTAssertEqual(String(decoding: page.body, as: UTF8.self), "page-controls-true")
        XCTAssertEqual(status(route(request("GET", "/status"))), 200)
        guard case .stream(.mjpeg) = route(request("GET", "/stream")) else { return XCTFail("expected JPEG stream") }
        guard case .stream(.video) = route(request("GET", "/video")) else { return XCTFail("expected video stream") }
        XCTAssertEqual(status(route(request("POST", "/video"))), 405)
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

    func body(_ route: StreamRoute) -> String {
        if case .response(let r) = route { return String(decoding: r.body, as: UTF8.self) }
        return ""
    }

    func testPhotoPassesTheSelfTimerDelay() {
        let pinHeader = ["X-MicroCAM-PIN": "1234"]
        XCTAssertEqual(status(route(request("POST", "/photo", headers: pinHeader))), 200)
        XCTAssertEqual(status(route(request("POST", "/photo?delay=5", headers: pinHeader))), 200)
        XCTAssertEqual(status(route(request("POST", "/photo?delay=0", headers: pinHeader))), 200)
        XCTAssertEqual(status(route(request("POST", "/photo?delay=\(SelfTimer.maxDelay)", headers: pinHeader))), 200)
        XCTAssertEqual(backend.delays, [0, 5, 0, SelfTimer.maxDelay])
    }

    func testInvalidDelayIsABadRequest() {
        let pinHeader = ["X-MicroCAM-PIN": "1234"]
        for bad in ["-1", "\(SelfTimer.maxDelay + 1)", "abc", "2.5", ""] {
            let r = route(request("POST", "/photo?delay=\(bad)", headers: pinHeader))
            XCTAssertEqual(status(r), 400, "delay=\(bad)")
            XCTAssertEqual(body(r), #"{"error":"delay"}"#)
        }
        XCTAssertEqual(backend.photos, 0)
    }

    /// The mode and PIN are checked before the delay, so a bad delay reveals nothing.
    func testDelayIsCheckedAfterModeAndPin() {
        XCTAssertEqual(status(route(request("POST", "/photo?delay=abc"))), 401)
        XCTAssertEqual(status(route(request("GET", "/photo?delay=5", headers: ["X-MicroCAM-PIN": "1234"]))), 405)
        mode = .imageOnly
        XCTAssertEqual(status(route(request("POST", "/photo?delay=abc", headers: ["X-MicroCAM-PIN": "1234"]))), 403)
        mode = .controls
        pin = nil
        XCTAssertEqual(status(route(request("POST", "/photo?delay=5", headers: ["X-MicroCAM-PIN": "1234"]))), 403)
        XCTAssertEqual(backend.photos, 0)
    }

    func testBusyOrCancelledSelfTimerIsAConflict() {
        let pinHeader = ["X-MicroCAM-PIN": "1234"]
        backend.photoResult = .failure(StreamPhotoError.selfTimerBusy)
        var r = route(request("POST", "/photo?delay=5", headers: pinHeader))
        XCTAssertEqual(status(r), 409)
        XCTAssertEqual(body(r), #"{"error":"busy"}"#)
        backend.photoResult = .failure(StreamPhotoError.selfTimerCancelled)
        r = route(request("POST", "/photo?delay=5", headers: pinHeader))
        XCTAssertEqual(status(r), 409)
        XCTAssertEqual(body(r), #"{"error":"cancelled"}"#)
        backend.photoResult = .failure(CocoaError(.fileWriteNoPermission))
        XCTAssertEqual(status(route(request("POST", "/photo", headers: pinHeader))), 500)
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
        useStorage(tmp)
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
        useStorage(tmp)
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
        useStorage(tmp)
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

    // MARK: Photo browser

    let pinHeader = ["X-MicroCAM-PIN": "1234"]

    func json(_ route: StreamRoute) -> [String: Any] {
        guard case .response(let r) = route else { return [:] }
        return (try? JSONSerialization.jsonObject(with: r.body)) as? [String: Any] ?? [:]
    }

    /// The gallery shows customer photos: the same mode, PIN and origin checks as taking a photo.
    func testGalleryJobsAndThumbsAreGuarded() {
        let tmp = TempDir()
        tmp.touch("PR-1/PR-1_2026-09-21_10-00-00.jpg")
        useStorage(tmp)
        for path in ["/gallery", "/jobs", "/thumbs/PR-1_2026-09-21_10-00-00.jpg"] {
            XCTAssertEqual(status(route(request("GET", path))), 401, path)
            XCTAssertEqual(status(route(request("POST", path, headers: pinHeader))), 405, path)
            XCTAssertEqual(status(route(request("GET", path, headers: pinHeader.merging(["Origin": "https://evil.example"]) { $1 }))),
                           403, path)
        }
        mode = .imageOnly
        for path in ["/gallery", "/jobs", "/thumbs/PR-1_2026-09-21_10-00-00.jpg"] {
            XCTAssertEqual(status(route(request("GET", path, headers: pinHeader))), 403, path)
        }
        mode = .controls
        pin = nil
        XCTAssertEqual(status(route(request("GET", "/gallery", headers: pinHeader))), 403)
    }

    func testGalleryListsTheCurrentFolderNewestFirstByDay() throws {
        let tmp = TempDir()
        tmp.touch("PR-1/PR-1_2026-09-20_09-00-00.jpg")
        tmp.touch("PR-1/PR-1_2026-09-21_10-00-00.jpg")
        tmp.touch("PR-1/PR-1_2026-09-21_10-00-00_2.jpg")
        tmp.touch("PR-1/PR-1_2026-09-21_11-00-00.mov")   // videos are not shown
        tmp.touch("PR-2/PR-2_2026-09-22_10-00-00.jpg")
        useStorage(tmp)
        let r = route(request("GET", "/gallery", headers: pinHeader))
        XCTAssertEqual(status(r), 200)
        let listing = json(r)
        XCTAssertEqual(listing["folder"] as? String, "")
        XCTAssertEqual(listing["job"] as? String, "PR-1")
        XCTAssertEqual(listing["current"] as? Bool, true)
        XCTAssertEqual(listing["jobs"] as? Bool, true)
        XCTAssertEqual(listing["more"] as? Bool, false)
        let days = try XCTUnwrap(listing["days"] as? [[String: Any]])
        XCTAssertEqual(days.map { $0["day"] as? String }, ["2026-09-21", "2026-09-20"])
        let first = try XCTUnwrap((days[0]["photos"] as? [[String: Any]])?.first)
        XCTAssertEqual(first["name"] as? String, "PR-1_2026-09-21_10-00-00_2.jpg")
        XCTAssertEqual(first["url"] as? String, "/captures/PR-1_2026-09-21_10-00-00_2.jpg")
        XCTAssertEqual(first["thumb"] as? String, "/thumbs/PR-1_2026-09-21_10-00-00_2.jpg")
    }

    /// Another job is only read: its photos come with `?folder=`, and the current job stays.
    func testGalleryShowsAnotherJobAndThePhotosWithoutAJob() throws {
        let tmp = TempDir()
        tmp.touch("PR-1/PR-1_2026-09-21_10-00-00.jpg")
        tmp.touch("PR-2/PR-2_2026-09-22_10-00-00.jpg")
        tmp.touch("_Unsorted/no-job_2026-09-23_10-00-00.jpg")
        useStorage(tmp)
        var listing = json(route(request("GET", "/gallery?folder=PR-2", headers: pinHeader)))
        XCTAssertEqual(listing["folder"] as? String, "PR-2")
        XCTAssertEqual(listing["job"] as? String, "PR-2")
        XCTAssertEqual(listing["current"] as? Bool, false)
        let photo = try XCTUnwrap(((listing["days"] as? [[String: Any]])?.first?["photos"] as? [[String: Any]])?.first)
        XCTAssertEqual(photo["url"] as? String, "/captures/PR-2_2026-09-22_10-00-00.jpg?folder=PR-2")
        XCTAssertEqual(status(route(request("GET", "/captures/PR-2_2026-09-22_10-00-00.jpg?folder=PR-2", headers: pinHeader))), 200)
        // Not without the folder: the current folder is PR-1.
        XCTAssertEqual(status(route(request("GET", "/captures/PR-2_2026-09-22_10-00-00.jpg", headers: pinHeader))), 404)

        listing = json(route(request("GET", "/gallery?folder=_unassigned", headers: pinHeader)))
        XCTAssertNil(listing["job"] as? String)
        XCTAssertEqual(listing["current"] as? Bool, false)
        XCTAssertEqual((listing["days"] as? [[String: Any]])?.count, 1)

        // Picking the current job from the list is the current folder, so it updates too.
        XCTAssertEqual(json(route(request("GET", "/gallery?folder=PR-1", headers: pinHeader)))["current"] as? Bool, true)
    }

    func testGalleryRefusesFoldersOutsideTheJobs() {
        let tmp = TempDir()
        tmp.touch("PR-1/PR-1_2026-09-21_10-00-00.jpg")
        useStorage(tmp)
        for bad in ["..", "..%2F..", "pr-1", "PR-1%2F..", "_Unsorted", "%2Fetc"] {
            XCTAssertEqual(status(route(request("GET", "/gallery?folder=\(bad)", headers: pinHeader))), 400, bad)
            XCTAssertEqual(status(route(request("GET", "/captures/PR-1_2026-09-21_10-00-00.jpg?folder=\(bad)",
                                                headers: pinHeader))), 404, bad)
        }
        // With jobs off there are no job folders to show.
        useStorage(tmp, context: .jobsDisabled)
        XCTAssertEqual(status(route(request("GET", "/gallery?folder=PR-1", headers: pinHeader))), 404)
        XCTAssertEqual(status(route(request("GET", "/gallery?folder=_unassigned", headers: pinHeader))), 404)
        XCTAssertEqual(status(route(request("GET", "/captures/PR-1_2026-09-21_10-00-00.jpg?folder=PR-1",
                                            headers: pinHeader))), 404)
        let listing = json(route(request("GET", "/gallery", headers: pinHeader)))
        XCTAssertEqual(listing["jobs"] as? Bool, false)
        XCTAssertNil(listing["job"] as? String)
        backend.storageValue = nil
        XCTAssertEqual(status(route(request("GET", "/gallery", headers: pinHeader))), 404)
    }

    func testJobsListsTheJobFoldersOnlyWhileJobsAreOn() throws {
        let tmp = TempDir()
        tmp.touch("PR-1/PR-1_2026-09-21_10-00-00.jpg")
        tmp.touch("PR-2/PR-2_2026-09-22_10-00-00.jpg")
        tmp.touch("PR-2/PR-2_2026-09-22_11-00-00.jpg")
        useStorage(tmp)
        let jobs = try XCTUnwrap(json(route(request("GET", "/jobs", headers: pinHeader)))["jobs"] as? [[String: Any]])
        XCTAssertEqual(jobs.map { $0["code"] as? String }, ["PR-2", "PR-1"])
        XCTAssertEqual(jobs.map { $0["files"] as? Int }, [2, 1])
        XCTAssertEqual(jobs.first?["lastDay"] as? String, "2026-09-22")
        useStorage(tmp, context: .jobsDisabled)
        XCTAssertEqual((json(route(request("GET", "/jobs", headers: pinHeader)))["jobs"] as? [Any])?.count, 0)
    }

    func testThumbsAreSmallJPEGs() throws {
        let tmp = TempDir()
        let file = tmp.url.appendingPathComponent("PR-1/PR-1_2026-09-21_10-00-00.jpg")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JPEGScalerTests().makeJPEG(width: 1920, height: 1080).write(to: file)
        useStorage(tmp)
        guard case .response(let r) = route(request("GET", "/thumbs/PR-1_2026-09-21_10-00-00.jpg", headers: pinHeader)) else {
            return XCTFail()
        }
        XCTAssertEqual(r.status, 200)
        XCTAssertTrue(r.headers.contains { $0 == ("Content-Type", "image/jpeg") })
        let source = try XCTUnwrap(CGImageSourceCreateWithData(r.body as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, ThumbnailCache.maxDimension)
        // A file that is no picture has no thumbnail.
        tmp.touch("PR-1/PR-1_2026-09-21_11-00-00.jpg")
        XCTAssertEqual(status(route(request("GET", "/thumbs/PR-1_2026-09-21_11-00-00.jpg", headers: pinHeader))), 404)
    }

    /// A drawing on a photo from another job is saved next to that photo.
    func testAnnotatedReadsTheSourceFromTheGalleryFolder() {
        let tmp = TempDir()
        let source = tmp.touch("PR-2/PR-2_2026-09-22_10-00-00.jpg")
        useStorage(tmp)
        let shapes = ##""shapes":[{"kind":"arrow","points":[{"x":0.1,"y":0.1},{"x":0.5,"y":0.5}],"color":"#ff0000","width":0.01}]"##
        XCTAssertEqual(status(route(request("POST", "/annotated", headers: pinHeader,
                                            body: #"{"source":"PR-2_2026-09-22_10-00-00.jpg","#+shapes+"}"))), 404)
        let r = route(request("POST", "/annotated", headers: pinHeader,
                              body: #"{"source":"PR-2_2026-09-22_10-00-00.jpg","folder":"PR-2","#+shapes+"}"))
        XCTAssertEqual(status(r), 200)
        XCTAssertEqual(backend.annotatedSources.map(\.standardizedFileURL), [source.standardizedFileURL])
        XCTAssertEqual(json(r)["url"] as? String, "/captures/PR-1_2026-09-21_10-00-00_2.jpg?folder=PR-2")
        XCTAssertEqual(status(route(request("POST", "/annotated", headers: pinHeader,
                                            body: #"{"source":"PR-2_2026-09-22_10-00-00.jpg","folder":"..","#+shapes+"}"))), 404)
    }
}
