import XCTest
@testable import MicroCAMCore

private final class FakeMCPBackend: MCPBackend {
    var statusValue = MCPStatus(cameraName: "Bench scope", format: FormatChoice(width: 1920, height: 1080, fps: 60),
                                recording: .idle, recordingStartedAt: nil, timelapse: nil,
                                folder: "/captures/PR-1", jobsEnabled: true, job: "PR-1")
    var folders: [URL] = []
    var frameResult: Result<MCPImage, MCPToolError> = .success(MCPImage(jpeg: Data([1, 2, 3]), width: 640, height: 360))
    var photoResult: Result<MCPSavedPhoto, MCPToolError> = .success(MCPSavedPhoto(
        file: URL(fileURLWithPath: "/captures/PR-1/PR-1_2026-09-21_10-00-00.jpg"),
        image: MCPImage(jpeg: Data([4, 5]), width: 320, height: 180)))
    var recordingError: MCPToolError?
    var jobSet: [JobCode?] = []
    var frames: [Int] = []
    var photos: [Int] = []
    var loaded: [(URL, Int)] = []
    var starts = 0, stops = 0

    func status() -> MCPStatus { statusValue }
    func captureFolders() -> [URL] { folders }
    func captureFrame(maxDimension: Int, completion: @escaping (Result<MCPImage, MCPToolError>) -> Void) {
        frames.append(maxDimension)
        completion(frameResult)
    }
    func takePhoto(maxDimension: Int, completion: @escaping (Result<MCPSavedPhoto, MCPToolError>) -> Void) {
        photos.append(maxDimension)
        completion(photoResult)
    }
    func loadPhoto(_ url: URL, maxDimension: Int, completion: @escaping (Result<MCPImage, MCPToolError>) -> Void) {
        loaded.append((url, maxDimension))
        completion(.success(MCPImage(jpeg: Data([9]), width: 10, height: 10)))
    }
    func startRecording(completion: @escaping (Result<Void, MCPToolError>) -> Void) {
        starts += 1
        completion(recordingError.map { .failure($0) } ?? .success(()))
    }
    func stopRecording(completion: @escaping (Result<URL, MCPToolError>) -> Void) {
        stops += 1
        completion(recordingError.map { .failure($0) }
                   ?? .success(URL(fileURLWithPath: "/captures/PR-1/PR-1_2026-09-21_10-05-00.mov")))
    }
    func setJob(_ job: JobCode?) -> Result<String?, MCPToolError> {
        jobSet.append(job)
        return .success("/captures/\(job?.value ?? "_Unsorted")")
    }
}

final class MCPRouterTests: XCTestCase {
    fileprivate var backend: FakeMCPBackend!
    var router: MCPRouter!
    var token: String? = String(repeating: "k", count: 43)
    var clock = Date(timeIntervalSince1970: 1_000_000)
    let modern = MCPRouter.modernVersion

    override func setUp() {
        backend = FakeMCPBackend()
        router = MCPRouter(backend: backend, authGuard: MCPAuthGuard(now: { [unowned self] in self.clock }),
                           token: { [unowned self] in self.token }, serverVersion: "9.9", now: { [unowned self] in self.clock })
    }

    // MARK: Helpers

    func http(_ method: String = "POST", _ path: String = "/mcp", headers: [String: String]? = nil,
              body: String = "") -> HTTPRequest {
        var raw = "\(method) \(path) HTTP/1.1\r\nHost: bench:8091\r\n"
        let all = headers ?? ["Authorization": "Bearer \(token ?? "")", "Content-Type": "application/json"]
        for (k, v) in all { raw += "\(k): \(v)\r\n" }
        raw += "Content-Length: \(body.utf8.count)\r\n\r\n\(body)"
        guard case .complete(let r) = HTTPRequestParser.parse(Data(raw.utf8)) else { fatalError() }
        return r
    }

    func send(_ request: HTTPRequest, peer: String = "10.0.0.5") -> HTTPResponse {
        var out: HTTPResponse?
        router.handle(request, peer: peer) { out = $0 }
        return out!
    }

    /// Legacy request (no `_meta`), as sent after `initialize`.
    func rpc(_ method: String, _ params: JSONValue? = nil, id: JSONValue = 1,
             extraHeaders: [String: String] = [:]) -> (HTTPResponse, JSONValue) {
        var message: [String: JSONValue] = ["jsonrpc": "2.0", "id": id, "method": .string(method)]
        if let params { message["params"] = params }
        var headers = ["Authorization": "Bearer \(token ?? "")", "Content-Type": "application/json"]
        headers.merge(extraHeaders) { $1 }
        let response = send(http(headers: headers, body: String(decoding: JSONValue.object(message).serialized(), as: UTF8.self)))
        return (response, (try? JSONValue.parse(response.body)) ?? .null)
    }

    /// Modern request: version and capabilities in `_meta`, mirrored into headers.
    func modernRPC(_ method: String, _ params: [String: JSONValue] = [:], headers: [String: String]? = nil,
                   meta: [String: JSONValue]? = nil) -> (HTTPResponse, JSONValue) {
        var p = params
        p["_meta"] = .object(meta ?? ["io.modelcontextprotocol/protocolVersion": .string(modern),
                                      "io.modelcontextprotocol/clientCapabilities": [:],
                                      "io.modelcontextprotocol/clientInfo": ["name": "test", "version": "1"]])
        var h = ["MCP-Protocol-Version": modern, "Mcp-Method": method]
        if method == "tools/call", let name = params["name"]?.string { h["Mcp-Name"] = name }
        return rpc(method, .object(p), extraHeaders: headers ?? h)
    }

    func call(_ name: String, _ args: JSONValue? = nil) -> JSONValue {
        var params: [String: JSONValue] = ["name": .string(name)]
        if let args { params["arguments"] = args }
        return rpc("tools/call", .object(params)).1
    }

    func text(_ result: JSONValue) -> String {
        guard case .array(let blocks)? = result["result"]?["content"] else { return "" }
        return blocks.compactMap { $0["type"] == "text" ? $0["text"]?.string : nil }.joined(separator: "\n")
    }

    // MARK: HTTP layer

    func testOnlyPostOnTheMCPPath() {
        XCTAssertEqual(send(http("GET")).status, 405)
        XCTAssertEqual(send(http("DELETE")).status, 405)
        XCTAssertTrue(send(http("GET")).headers.contains { $0.0 == "Allow" && $0.1 == "POST" })
        XCTAssertEqual(send(http("GET", "/")).status, 404)
        XCTAssertEqual(send(http("POST", "/other", body: "{}")).status, 404)
    }

    func testRequiresTheTokenAndLocksOutAfterRepeatedFailures() {
        let ping = #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#
        XCTAssertEqual(send(http(headers: [:], body: ping)).status, 401)
        let wrong = http(headers: ["Authorization": "Bearer nope"], body: ping)
        let unauthorized = send(wrong)
        XCTAssertEqual(unauthorized.status, 401)
        XCTAssertTrue(unauthorized.headers.contains { $0.0 == "WWW-Authenticate" })
        for _ in 0..<3 { XCTAssertEqual(send(wrong).status, 401) }
        let locked = send(http(body: ping))
        XCTAssertEqual(locked.status, 429)
        XCTAssertTrue(locked.headers.contains { $0.0 == "Retry-After" && $0.1 == "300" })
        XCTAssertEqual(send(http(body: ping), peer: "10.0.0.6").status, 200)   // another machine is fine
        clock = clock.addingTimeInterval(301)
        XCTAssertEqual(send(http(body: ping)).status, 200)
    }

    func testTheResponseNeverContainsTheToken() {
        let response = send(http(headers: ["Authorization": "Bearer nope"], body: "{}"))
        XCTAssertFalse(String(decoding: response.body, as: UTF8.self).contains(token!))
        XCTAssertFalse(String(decoding: response.body, as: UTF8.self).contains("nope"))
    }

    func testRefusesToRunWithoutAToken() {
        token = nil
        XCTAssertEqual(send(http(headers: ["Authorization": "Bearer "], body: "{}")).status, 503)
    }

    func testRejectsForeignBrowserOrigins() {
        let body = #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#
        let evil = http(headers: ["Authorization": "Bearer \(token!)", "Origin": "https://evil.example"], body: body)
        XCTAssertEqual(send(evil).status, 403)
        let same = http(headers: ["Authorization": "Bearer \(token!)", "Origin": "http://bench:8091"], body: body)
        XCTAssertEqual(send(same).status, 200)
    }

    // MARK: JSON-RPC

    func testParseErrorsAndInvalidRequests() throws {
        let bad = send(http(body: "{nope"))
        XCTAssertEqual(bad.status, 400)
        XCTAssertEqual(try JSONValue.parse(bad.body)["error"]?["code"], -32700)
        let batch = send(http(body: #"[{"jsonrpc":"2.0","id":1,"method":"ping"}]"#))
        XCTAssertEqual(try JSONValue.parse(batch.body)["error"]?["code"], -32600)
        let noVersion = send(http(body: #"{"id":1,"method":"ping"}"#))
        XCTAssertEqual(try JSONValue.parse(noVersion.body)["error"]?["code"], -32600)
        let nullID = send(http(body: #"{"jsonrpc":"2.0","id":null,"method":"ping"}"#))
        XCTAssertEqual(try JSONValue.parse(nullID.body)["error"]?["code"], -32600)
    }

    func testNotificationsAreAcceptedWithoutABody() {
        let response = send(http(body: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#))
        XCTAssertEqual(response.status, 202)
        XCTAssertTrue(response.body.isEmpty)
    }

    func testInitializeEchoesASupportedVersionOrOffersTheNewest() {
        let (response, known) = rpc("initialize", ["protocolVersion": "2025-06-18", "capabilities": [:],
                                                    "clientInfo": ["name": "c", "version": "1"]])
        XCTAssertEqual(response.status, 200)
        XCTAssertTrue(response.headers.contains { $0.0 == "Content-Type" && $0.1.hasPrefix("application/json") })
        XCTAssertEqual(known["id"], 1)
        XCTAssertEqual(known["result"]?["protocolVersion"], "2025-06-18")
        XCTAssertEqual(known["result"]?["capabilities"]?["tools"]?["listChanged"], false)
        XCTAssertEqual(known["result"]?["serverInfo"]?["name"], "microCAM")
        XCTAssertEqual(known["result"]?["serverInfo"]?["version"], "9.9")
        XCTAssertNotNil(known["result"]?["instructions"]?.string)
        let unknown = rpc("initialize", ["protocolVersion": "1999-01-01", "capabilities": [:]], id: "a").1
        XCTAssertEqual(unknown["id"], "a")
        XCTAssertEqual(unknown["result"]?["protocolVersion"], .string(MCPRouter.legacyVersions[0]))
    }

    func testPingAndUnknownMethod() {
        XCTAssertEqual(rpc("ping").1["result"], [:])
        let (response, unknown) = rpc("resources/list")
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(unknown["error"]?["code"], -32601)
    }

    func testLegacyHeaderWithAnUnsupportedVersionIsRejected() {
        let (response, body) = rpc("tools/list", extraHeaders: ["MCP-Protocol-Version": "1999-01-01"])
        XCTAssertEqual(response.status, 400)
        XCTAssertEqual(body["error"]?["code"], -32022)
    }

    // MARK: Modern (per-request metadata)

    func testModernDiscoverAndToolsList() {
        let (response, discover) = modernRPC("server/discover")
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(discover["result"]?["resultType"], "complete")
        guard case .array(let versions)? = discover["result"]?["supportedVersions"] else { return XCTFail() }
        XCTAssertEqual(versions.first, .string(modern))
        XCTAssertEqual(discover["result"]?["_meta"]?["io.modelcontextprotocol/serverInfo"]?["name"], "microCAM")
        let list = modernRPC("tools/list").1
        XCTAssertEqual(list["result"]?["resultType"], "complete")
        guard case .array(let tools)? = list["result"]?["tools"] else { return XCTFail() }
        XCTAssertEqual(tools.count, 8)
        // Caching hints are required on both (utilities/caching). The tool list
        // changes with the jobs setting, so it is never fresh for long.
        XCTAssertEqual(list["result"]?["ttlMs"], 0)
        XCTAssertEqual(list["result"]?["cacheScope"], "private")
        XCTAssertNotNil(discover["result"]?["ttlMs"]?.integer)
        XCTAssertEqual(discover["result"]?["cacheScope"], "private")
        // Legacy results stay as they were.
        XCTAssertNil(rpc("tools/list").1["result"]?["ttlMs"])
    }

    func testModernHeadersMustMatchTheBody() {
        XCTAssertEqual(modernRPC("tools/list", headers: ["Mcp-Method": "tools/list"]).1["error"]?["code"], -32020)
        let mismatch = modernRPC("tools/list", headers: ["MCP-Protocol-Version": "2025-06-18", "Mcp-Method": "tools/list"])
        XCTAssertEqual(mismatch.0.status, 400)
        XCTAssertEqual(mismatch.1["error"]?["code"], -32020)
        XCTAssertEqual(modernRPC("tools/list", headers: ["MCP-Protocol-Version": modern, "Mcp-Method": "ping"])
            .1["error"]?["code"], -32020)
        let wrongName = modernRPC("tools/call", ["name": "get_status"],
                                  headers: ["MCP-Protocol-Version": modern, "Mcp-Method": "tools/call", "Mcp-Name": "take_photo"])
        XCTAssertEqual(wrongName.1["error"]?["code"], -32020)
        XCTAssertEqual(backend.photos, [])
        // Base64 sentinel form of "get_status".
        let encoded = modernRPC("tools/call", ["name": "get_status"],
                                headers: ["MCP-Protocol-Version": modern, "Mcp-Method": "tools/call",
                                          "Mcp-Name": "=?base64?Z2V0X3N0YXR1cw==?="])
        XCTAssertEqual(encoded.1["result"]?["resultType"], "complete")
    }

    func testModernMetadataRules() {
        let noCaps = modernRPC("tools/list", meta: ["io.modelcontextprotocol/protocolVersion": .string(modern)])
        XCTAssertEqual(noCaps.0.status, 400)
        XCTAssertEqual(noCaps.1["error"]?["code"], -32602)
        let future = modernRPC("tools/list", headers: ["MCP-Protocol-Version": "2099-01-01", "Mcp-Method": "tools/list"],
                               meta: ["io.modelcontextprotocol/protocolVersion": "2099-01-01",
                                      "io.modelcontextprotocol/clientCapabilities": [:]])
        XCTAssertEqual(future.0.status, 400)
        XCTAssertEqual(future.1["error"]?["code"], -32022)
        XCTAssertEqual(future.1["error"]?["data"]?["requested"], "2099-01-01")
        let unknown = modernRPC("resources/list")
        XCTAssertEqual(unknown.0.status, 404)
        XCTAssertEqual(unknown.1["error"]?["code"], -32601)
        // The modern version without per-request metadata is malformed.
        let bare = rpc("tools/list", extraHeaders: ["MCP-Protocol-Version": modern])
        XCTAssertEqual(bare.0.status, 400)
        XCTAssertEqual(bare.1["error"]?["code"], -32602)
    }

    // MARK: Tools

    func testToolsListHidesSetJobWithoutJobs() {
        backend.statusValue.jobsEnabled = false
        guard case .array(let tools)? = rpc("tools/list").1["result"]?["tools"] else { return XCTFail() }
        XCTAssertFalse(tools.contains { $0["name"] == "set_job" })
        let result = call("set_job", ["job": "PR-2"])
        XCTAssertEqual(result["result"]?["isError"], true)
        XCTAssertTrue(text(result).contains("Jobs are turned off"))
        XCTAssertTrue(backend.jobSet.isEmpty)
    }

    func testUnknownToolAndMalformedCallAreProtocolErrors() {
        XCTAssertEqual(call("format_disk")["error"]?["code"], -32602)
        XCTAssertEqual(rpc("tools/call", ["arguments": [:]]).1["error"]?["code"], -32602)
        XCTAssertEqual(rpc("tools/call", ["name": "get_status", "arguments": "x"]).1["error"]?["code"], -32602)
    }

    func testBadArgumentsAreToolErrors() {
        let result = call("capture_frame", ["max_size": 5])
        XCTAssertEqual(result["result"]?["isError"], true)
        XCTAssertTrue(text(result).contains("max_size"))
        XCTAssertEqual(backend.frames, [])
    }

    func testGetStatus() {
        backend.statusValue.recording = .recording
        backend.statusValue.recordingStartedAt = clock.addingTimeInterval(-75)
        backend.statusValue.timelapse = MCPTimelapseStatus(shotsTaken: 3, shotCount: 10)
        let result = call("get_status")["result"]
        XCTAssertEqual(result?["isError"], false)
        let s = result?["structuredContent"]
        XCTAssertEqual(s?["camera"]?["name"], "Bench scope")
        XCTAssertEqual(s?["camera"]?["connected"], true)
        XCTAssertEqual(s?["format"]?["width"], 1920)
        XCTAssertEqual(s?["format"]?["label"], "1920×1080 @ 60 fps")
        XCTAssertEqual(s?["recording"]?["state"], "recording")
        XCTAssertEqual(s?["recording"]?["seconds"], 75)
        XCTAssertEqual(s?["timelapse"]?["running"], true)
        XCTAssertEqual(s?["timelapse"]?["shotsTaken"], 3)
        XCTAssertEqual(s?["folder"], "/captures/PR-1")
        XCTAssertEqual(s?["job"], "PR-1")
        // Structured content is repeated as text for clients that only read text.
        XCTAssertEqual(try? JSONValue.parse(Data(text(["result": result ?? .null]).utf8)), s)
    }

    func testGetStatusWithoutCamera() {
        backend.statusValue = MCPStatus(cameraName: nil, format: nil, recording: .idle, recordingStartedAt: nil,
                                        timelapse: nil, folder: nil, jobsEnabled: false, job: nil)
        let s = call("get_status")["result"]?["structuredContent"]
        XCTAssertEqual(s?["camera"]?["connected"], false)
        XCTAssertEqual(s?["camera"]?["name"], .null)
        XCTAssertEqual(s?["format"], .null)
        XCTAssertEqual(s?["timelapse"]?["running"], false)
    }

    func testCaptureFrameReturnsAnImageWithoutSaving() {
        let result = call("capture_frame", ["max_size": 800])["result"]
        XCTAssertEqual(backend.frames, [800])
        XCTAssertEqual(backend.photos, [])
        guard case .array(let blocks)? = result?["content"] else { return XCTFail() }
        XCTAssertEqual(blocks.first?["type"], "image")
        XCTAssertEqual(blocks.first?["mimeType"], "image/jpeg")
        XCTAssertEqual(blocks.first?["data"], .string(Data([1, 2, 3]).base64EncodedString()))
        XCTAssertEqual(result?["isError"], false)
    }

    func testCaptureFrameErrorIsAReadableToolError() {
        backend.frameResult = .failure(.noCamera)
        let result = call("capture_frame")
        XCTAssertEqual(result["result"]?["isError"], true)
        XCTAssertEqual(text(result), MCPToolError.noCamera.message)
    }

    func testTakePhotoReturnsImageAndFile() {
        let result = call("take_photo")["result"]
        XCTAssertEqual(backend.photos, [MCPTools.defaultMaxSize])
        XCTAssertEqual(result?["structuredContent"]?["name"], "PR-1_2026-09-21_10-00-00.jpg")
        XCTAssertEqual(result?["structuredContent"]?["path"], "/captures/PR-1/PR-1_2026-09-21_10-00-00.jpg")
        guard case .array(let blocks)? = result?["content"] else { return XCTFail() }
        XCTAssertEqual(blocks.first?["type"], "image")
    }

    func testListAndGetCaptures() {
        let tmp = TempDir()
        tmp.touch("PR-1/PR-1_2026-09-21_10-00-00.jpg")
        tmp.touch("PR-1/PR-1_2026-09-21_11-00-00.mov")
        backend.folders = [tmp.url.appendingPathComponent("PR-1")]
        let list = call("list_captures", ["limit": 5])["result"]?["structuredContent"]
        guard case .array(let files)? = list?["captures"] else { return XCTFail() }
        XCTAssertEqual(files.map { $0["name"] }, ["PR-1_2026-09-21_11-00-00.mov", "PR-1_2026-09-21_10-00-00.jpg"])
        XCTAssertEqual(files.map { $0["kind"] }, ["video", "photo"])
        XCTAssertNotNil(files.first?["capturedAt"]?.string)

        let photo = call("get_capture", ["name": "PR-1_2026-09-21_10-00-00.jpg", "max_size": 300])["result"]
        XCTAssertEqual(backend.loaded.last?.1, 300)
        guard case .array(let blocks)? = photo?["content"] else { return XCTFail() }
        XCTAssertEqual(blocks.first?["type"], "image")

        let video = call("get_capture", ["name": "PR-1_2026-09-21_11-00-00.mov"])["result"]
        XCTAssertEqual(video?["structuredContent"]?["kind"], "video")
        guard case .array(let videoBlocks)? = video?["content"] else { return XCTFail() }
        XCTAssertFalse(videoBlocks.contains { $0["type"] == "image" })
        XCTAssertEqual(backend.loaded.count, 1)

        let missing = call("get_capture", ["name": "../../etc/passwd"])
        XCTAssertEqual(missing["result"]?["isError"], true)
    }

    func testRecordingAndJob() {
        XCTAssertEqual(call("start_recording")["result"]?["isError"], false)
        let stop = call("stop_recording")["result"]
        XCTAssertEqual(stop?["structuredContent"]?["name"], "PR-1_2026-09-21_10-05-00.mov")
        backend.recordingError = .alreadyRecording
        XCTAssertEqual(text(call("start_recording")), MCPToolError.alreadyRecording.message)
        XCTAssertEqual(backend.starts, 2)

        let job = call("set_job", ["job": "pr-7"])["result"]
        XCTAssertEqual(backend.jobSet, [JobCode("PR-7")])
        XCTAssertEqual(job?["structuredContent"]?["job"], "PR-7")
        XCTAssertEqual(job?["structuredContent"]?["folder"], "/captures/PR-7")
        let bad = call("set_job", ["job": "../x"])
        XCTAssertEqual(bad["result"]?["isError"], true)
        XCTAssertEqual(backend.jobSet.count, 1)
    }
}
