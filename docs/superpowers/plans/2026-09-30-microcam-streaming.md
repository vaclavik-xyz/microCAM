# microCAM Live Stream and Viewer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stream the live microscope image from microCAM on bench Mac to a browser or to microCAM in viewer mode on reception-mac. The host decides between an image-only page and a page with controls. With controls, the viewer can take photos (PIN-protected), annotate the live image, and save an annotated copy to the active job.

**Architecture:** A small HTTP server inside microCAM, built on `Network.framework`. Pure protocol and security logic lives in `MicroCAMCore` with unit tests: the request parser, response builder, MJPEG framing, the local-network access policy, the PIN guard with lockout, and annotation rendering. The app layer holds four pieces:
- `StreamServer`: listener, Bonjour advertising and routing.
- `StreamHub`: GPU JPEG encoding, only while at least one viewer is connected.
- One self-contained HTML/JS page, embedded as a Swift string.
- Viewer mode: Bonjour browser plus `WKWebView` showing the same page.

**Tech Stack:** Swift 5 mode, `Network.framework` (NWListener, NWConnection, NWBrowser), Core Image (Metal) JPEG encoding, CoreGraphics annotation rendering, WebKit (`WKWebView`), vanilla HTML/CSS/JS (no build step, no libraries), XCTest.

**Spec:** agreed in conversation on 2026-09-30. The design is summarized below. The v1 spec `docs/superpowers/specs/2026-09-29-microcam-design.md` still governs everything else (storage, naming, lifecycle, no third-party dependencies).

## Design summary (binding for this plan)

**Host (bench Mac), Settings → Přenos:**
- Toggle, off by default.
- Page mode, chosen only by the host:
  - *Jen obraz*: image only; photo, annotation and capture endpoints return 403.
  - *S ovládáním*: controls, the default.
- Port, default 8090.
- Photo PIN, 4–8 digits, stored in the Keychain. Without a PIN, remote photos are disabled.
- The addresses to open on the recepce Mac, with a copy button.

**Access and cost:**
- Connections are accepted only from loopback, private LAN, link-local and Tailscale ranges. Everything else is closed immediately.
- Nothing listens while the toggle is off. With no viewer connected, nothing is encoded.
- While a viewer is connected, the camera keeps running even if the bench window is hidden or the screen is locked (like a recording). System sleep still stops it.

**Stream:**
- MJPEG over `multipart/x-mixed-replace` at ≤ 15 fps, ≤ 1920 px wide, JPEG quality 0.7.
- The same image adjustments as the bench preview. No zoom.

**Page, S ovládáním:**
- Shows the active job.
- Full screen button.
- **Kreslit** (live pointer drawing that is never saved) and **Smazat**.
- **Vyfotit** (asks for the PIN once and keeps it in `localStorage`):
  - The photo is taken on bench Mac exactly like pressing Space: full frame, adjustments applied, saved to the active job.
  - The page switches to the frozen photo. There you can annotate (arrow, ellipse, pen), **Uložit k zakázce**, **Stáhnout** or go **Zpět na živý obraz**.
- **Uložit k zakázce** renders the shapes on bench Mac onto the original. The result is saved as a new capture with the same timestamp and the next index (`…_2.jpg`); the original stays untouched.

**Bench feedback:** the status bar shows "Sleduje N" while viewers are connected and "Vyfoceno z recepce: <file>" after a remote photo.

**Viewer mode (reception-mac):**
- Settings → Režim appky: *Kamera* / *Prohlížeč*. In viewer mode the camera, storage and shortcuts stay untouched.
- The window lists bench Mac instances found via Bonjour (`_microcam._tcp`), with a manual URL fallback for Tailscale, where Bonjour does not cross.
- It remembers the last source, auto-connects and retries after failures.
- It shows the stream page in `WKWebView`.
- Menu: show full screen on a chosen display.

**Out of scope:**
- recording from the viewer,
- choosing the job from the viewer,
- annotations shared back to the bench,
- a native video decoder (HEVC).

**Build:** universal binary (arm64 + x86_64), because reception-mac is an Intel Mac.

## Global Constraints

- No third-party dependencies. Code and comments in English; UI strings in Czech.
- Conventional commits, no `Co-Authored-By`; check Roborev after each commit; fix only verified High/Medium findings in scope.
- Streaming off by default. Toggle off means no listener; zero viewers means no JPEG encoding.
- Remote actions (`/photo`, `/annotated`, `/captures/*`) must meet all of the following:
  - mode *S ovládáním*;
  - a PIN configured;
  - `POST` for state changes;
  - header `X-MicroCAM-PIN` (a custom header blocks cross-site requests without CORS; the server never answers CORS preflight).
- PIN lockout: 5 wrong attempts → 60 s lock (global).
- File access over HTTP only for capture file names that parse (`CaptureFileName.parse`) and exist in the active job's listed folders; no path segments.
- Work on branch `streaming` (stacked on `integrations`), one PR.

## Review Focus

1. A web page on another site POSTing to `http://bench-mac:8090/photo` must not take a photo. Pinned by `StreamRouterTests.testPhotoRequiresPostPinAndSameOrigin` (Task 5) and the no-CORS rule.
2. `GET /captures/../../etc/passwd` or `/captures/%2e%2e%2f…` must never read outside the job folder. Pinned by `CaptureNameGuardTests` (Task 2).
3. A client on a public IP (port forwarded, VPN) must be refused before any HTTP is parsed. Pinned by `StreamAccessPolicyTests` (Task 1).
4. A slow viewer (weak Wi-Fi) must not delay other viewers or the bench preview. Frames for a busy connection are dropped, not queued; covered by manual check #4 in Task 9.
5. Brute-forcing the PIN must be impractical. Pinned by `PinGuardTests.testLocksAfterFiveFailures` (Task 1).

## File Structure

```
Sources/MicroCAMCore/Streaming/
  StreamAccessPolicy.swift    allowed remote addresses
  PinGuard.swift              PIN validation, constant-time compare, lockout
  HTTPMessage.swift           HTTPRequest/Parser, HTTPResponse
  MJPEG.swift                 multipart framing
  CaptureNameGuard.swift      safe capture lookup for /captures and /annotated
  Annotation.swift            shapes model + CoreGraphics renderer
  StreamRouter.swift          routes, PIN/method/origin checks, backend protocol
Sources/MicroCAMCore/AppSettings.swift        + streaming, appMode, viewer fields
Sources/MicroCAMCore/CaptureLifecyclePolicy.swift  + streamViewers
Sources/MicroCAMApp/Streaming/
  StreamServer.swift          NWListener, Bonjour, connections
  StreamHub.swift             viewer registry, throttled GPU JPEG encoding, broadcast
  StreamPage.swift            the HTML/CSS/JS page as a Swift string
  NetworkAddresses.swift      local IPv4 addresses for the settings tab
Sources/MicroCAMApp/Viewer/
  ViewerModel.swift           NWBrowser, resolve, remembered source, retry
  ViewerView.swift            source picker + WKWebView
Sources/MicroCAMApp/Views/SettingsView.swift  + Přenos tab, Režim appky
Tests/MicroCAMCoreTests/…     one test file per Core file
scripts/make-app.sh           universal build
scripts/deploy.sh             deploy to any host (bench-mac, reception-mac)
scripts/stream-smoke.sh       curl-based end-to-end check
```

---

Start: `git checkout integrations && git checkout -b streaming` (already created with this plan).

### Task 1: Access policy and PIN guard (Core)

**Files:**
- Create: `Sources/MicroCAMCore/Streaming/StreamAccessPolicy.swift`, `Sources/MicroCAMCore/Streaming/PinGuard.swift`
- Test: `Tests/MicroCAMCoreTests/StreamAccessPolicyTests.swift`, `Tests/MicroCAMCoreTests/PinGuardTests.swift`

**Interfaces:**
- Produces: `enum StreamAccessPolicy { static func isAllowed(_ host: String) -> Bool }`; `final class PinGuard { enum Outcome: Equatable { case ok, wrong, locked(until: Date), notConfigured }; init(maxFailures: Int = 5, lockout: TimeInterval = 60, now: @escaping () -> Date = Date.init); func check(_ candidate: String?, expected: String?) -> Outcome; static func isValidPIN(_: String) -> Bool }`

- [ ] **Step 1: Write failing tests**

`Tests/MicroCAMCoreTests/StreamAccessPolicyTests.swift`:
```swift
import XCTest
@testable import MicroCAMCore

final class StreamAccessPolicyTests: XCTestCase {
    func testAllowsLocalAndTailscale() {
        for host in ["127.0.0.1", "10.0.0.5", "172.16.0.1", "172.31.255.255", "192.168.1.140",
                     "169.254.10.1", "100.100.100.100", "100.64.0.1", "100.127.255.254",
                     "::1", "fe80::1%en0", "fd7a:115c:a1e0::1", "::ffff:192.168.1.5"] {
            XCTAssertTrue(StreamAccessPolicy.isAllowed(host), host)
        }
    }
    func testRejectsPublicAndGarbage() {
        for host in ["8.8.8.8", "172.32.0.1", "100.128.0.1", "100.63.255.255", "192.169.0.1",
                     "2001:4860:4860::8888", "::ffff:8.8.8.8", "example.com", "", "999.1.1.1"] {
            XCTAssertFalse(StreamAccessPolicy.isAllowed(host), host)
        }
    }
}
```

`Tests/MicroCAMCoreTests/PinGuardTests.swift`:
```swift
import XCTest
@testable import MicroCAMCore

final class PinGuardTests: XCTestCase {
    var clock = Date(timeIntervalSince1970: 1_000_000)

    func makeGuard() -> PinGuard { PinGuard(now: { [unowned self] in self.clock }) }

    func testValidPINFormat() {
        XCTAssertTrue(PinGuard.isValidPIN("1234"))
        XCTAssertTrue(PinGuard.isValidPIN("12345678"))
        XCTAssertFalse(PinGuard.isValidPIN("123"))
        XCTAssertFalse(PinGuard.isValidPIN("123456789"))
        XCTAssertFalse(PinGuard.isValidPIN("12a4"))
    }
    func testOkWrongAndNotConfigured() {
        let g = makeGuard()
        XCTAssertEqual(g.check("1234", expected: "1234"), .ok)
        XCTAssertEqual(g.check("9999", expected: "1234"), .wrong)
        XCTAssertEqual(g.check(nil, expected: "1234"), .wrong)
        XCTAssertEqual(g.check("1234", expected: nil), .notConfigured)
        XCTAssertEqual(g.check("1234", expected: ""), .notConfigured)
    }
    func testLocksAfterFiveFailures() {
        let g = makeGuard()
        for _ in 0..<5 { XCTAssertEqual(g.check("0000", expected: "1234"), .wrong) }
        let until = clock.addingTimeInterval(60)
        XCTAssertEqual(g.check("1234", expected: "1234"), .locked(until: until)) // even the right PIN
        clock = clock.addingTimeInterval(61)
        XCTAssertEqual(g.check("1234", expected: "1234"), .ok)
    }
    func testSuccessResetsFailures() {
        let g = makeGuard()
        for _ in 0..<4 { _ = g.check("0000", expected: "1234") }
        XCTAssertEqual(g.check("1234", expected: "1234"), .ok)
        for _ in 0..<4 { XCTAssertEqual(g.check("0000", expected: "1234"), .wrong) }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter "StreamAccessPolicyTests|PinGuardTests"`
Expected: build failure, `cannot find 'StreamAccessPolicy' in scope`.

- [ ] **Step 3: Implement**

`Sources/MicroCAMCore/Streaming/StreamAccessPolicy.swift`:
```swift
import Darwin

/// The stream is for the shop network only: loopback, private LAN,
/// link-local and Tailscale (CGNAT 100.64/10, ULA fd7a:115c:a1e0::/48 ⊂ fc00::/7).
/// Anything else is refused before any HTTP is read.
public enum StreamAccessPolicy {
    public static func isAllowed(_ host: String) -> Bool {
        let bare = host.split(separator: "%", maxSplits: 1).first.map(String.init) ?? host
        if let v4 = ipv4(bare) { return allowedV4(v4) }
        if let v6 = ipv6(bare) { return allowedV6(v6) }
        return false
    }

    private static func ipv4(_ s: String) -> UInt32? {
        var addr = in_addr()
        guard inet_pton(AF_INET, s, &addr) == 1 else { return nil }
        return UInt32(bigEndian: addr.s_addr)
    }

    private static func ipv6(_ s: String) -> [UInt8]? {
        var addr = in6_addr()
        guard inet_pton(AF_INET6, s, &addr) == 1 else { return nil }
        return withUnsafeBytes(of: &addr) { Array($0) }
    }

    private static func inRange(_ ip: UInt32, _ base: UInt32, _ prefix: UInt32) -> Bool {
        let mask: UInt32 = prefix == 0 ? 0 : ~UInt32(0) << (32 - prefix)
        return ip & mask == base & mask
    }

    private static func allowedV4(_ ip: UInt32) -> Bool {
        let ranges: [(UInt32, UInt32)] = [
            (0x7F00_0000, 8),   // 127.0.0.0/8
            (0x0A00_0000, 8),   // 10.0.0.0/8
            (0xAC10_0000, 12),  // 172.16.0.0/12
            (0xC0A8_0000, 16),  // 192.168.0.0/16
            (0xA9FE_0000, 16),  // 169.254.0.0/16
            (0x6440_0000, 10),  // 100.64.0.0/10 (Tailscale)
        ]
        return ranges.contains { inRange(ip, $0.0, $0.1) }
    }

    private static func allowedV6(_ b: [UInt8]) -> Bool {
        if b == [UInt8](repeating: 0, count: 15) + [1] { return true }                 // ::1
        if b[0] == 0xFE && (b[1] & 0xC0) == 0x80 { return true }                       // fe80::/10
        if (b[0] & 0xFE) == 0xFC { return true }                                        // fc00::/7
        if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xFF && b[11] == 0xFF {        // ::ffff:a.b.c.d
            let v4 = UInt32(b[12]) << 24 | UInt32(b[13]) << 16 | UInt32(b[14]) << 8 | UInt32(b[15])
            return allowedV4(v4)
        }
        return false
    }
}
```

`Sources/MicroCAMCore/Streaming/PinGuard.swift`:
```swift
import Foundation

/// Guards remote photo/annotation requests. Lockout is global (one shop, a
/// handful of viewers): after `maxFailures` wrong PINs every attempt is
/// refused for `lockout` seconds, even with the right PIN.
public final class PinGuard: @unchecked Sendable {
    public enum Outcome: Equatable {
        case ok, wrong, locked(until: Date), notConfigured
    }

    private let maxFailures: Int
    private let lockout: TimeInterval
    private let now: () -> Date
    private let lock = NSLock()
    private var failures = 0
    private var lockedUntil: Date?

    public init(maxFailures: Int = 5, lockout: TimeInterval = 60, now: @escaping () -> Date = Date.init) {
        self.maxFailures = maxFailures
        self.lockout = lockout
        self.now = now
    }

    public static func isValidPIN(_ pin: String) -> Bool {
        (4...8).contains(pin.count) && pin.allSatisfy(\.isASCII) && pin.allSatisfy(\.isNumber)
    }

    public func check(_ candidate: String?, expected: String?) -> Outcome {
        guard let expected, !expected.isEmpty else { return .notConfigured }
        lock.lock(); defer { lock.unlock() }
        let t = now()
        if let until = lockedUntil {
            if t < until { return .locked(until: until) }
            lockedUntil = nil
            failures = 0
        }
        if let candidate, Self.constantTimeEquals(candidate, expected) {
            failures = 0
            return .ok
        }
        failures += 1
        if failures >= maxFailures { lockedUntil = t.addingTimeInterval(lockout) }
        return .wrong
    }

    private static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        var diff = UInt8(x.count == y.count ? 0 : 1)
        for i in 0..<max(x.count, y.count) {
            diff |= (i < x.count ? x[i] : 0) ^ (i < y.count ? y[i] : 0)
        }
        return diff == 0
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(core): add stream access policy and PIN guard"
```
Check Roborev.

### Task 2: HTTP message, MJPEG framing and capture-name guard (Core)

**Files:**
- Create: `Sources/MicroCAMCore/Streaming/HTTPMessage.swift`, `Sources/MicroCAMCore/Streaming/MJPEG.swift`, `Sources/MicroCAMCore/Streaming/CaptureNameGuard.swift`
- Test: `Tests/MicroCAMCoreTests/HTTPMessageTests.swift`, `Tests/MicroCAMCoreTests/CaptureNameGuardTests.swift`

**Interfaces:**
- Consumes: `CaptureFileName`, `StorageLayout.listedFolders(for:)`, `JobContext` (v1 Core).
- Produces:
  - `struct HTTPRequest: Equatable { method: String; path: String; query: [String: String]; headers: [String: String] /* lowercased keys */; body: Data; func header(_ name: String) -> String? }`
  - `enum HTTPParseResult: Equatable { case incomplete, invalid, complete(HTTPRequest) }`; `enum HTTPRequestParser { static let maxHeaderBytes = 16_384; static let maxBodyBytes = 1_000_000; static func parse(_ data: Data) -> HTTPParseResult }`
  - `struct HTTPResponse { var status: Int; var headers: [(String, String)]; var body: Data; init(status:headers:body:); static func json<T: Encodable>(_ status: Int, _ value: T) -> HTTPResponse; static func text(_ status: Int, _ text: String) -> HTTPResponse; static func html(_ html: String) -> HTTPResponse; func serialized() -> Data }`
  - `enum MJPEG { static let boundary: String; static func responseHead() -> Data; static func part(jpeg: Data) -> Data }`
  - `enum CaptureNameGuard { static func resolve(_ rawName: String, in folders: [URL], fileManager: FileManager = .default) -> URL? }`

- [ ] **Step 1: Write failing tests**

`Tests/MicroCAMCoreTests/HTTPMessageTests.swift`:
```swift
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
```

`Tests/MicroCAMCoreTests/CaptureNameGuardTests.swift`:
```swift
import XCTest
@testable import MicroCAMCore

final class CaptureNameGuardTests: XCTestCase {
    func testResolvesExistingCaptureInListedFolders() {
        let tmp = TempDir()
        let file = tmp.touch("PR-1/Fotky/PR-1_2026-09-21_10-00-00.jpg")
        let folders = [tmp.url.appendingPathComponent("PR-1"), tmp.url.appendingPathComponent("PR-1/Fotky")]
        XCTAssertEqual(CaptureNameGuard.resolve("PR-1_2026-09-21_10-00-00.jpg", in: folders)?.standardizedFileURL,
                       file.standardizedFileURL)
    }
    func testRejectsTraversalAndForeignNames() {
        let tmp = TempDir()
        tmp.touch("PR-1/PR-1_2026-09-21_10-00-00.jpg")
        tmp.touch("secret.txt")
        let folders = [tmp.url.appendingPathComponent("PR-1")]
        for name in ["../secret.txt", "..%2Fsecret.txt", "%2e%2e/secret.txt", "PR-1/PR-1_2026-09-21_10-00-00.jpg",
                     "/etc/passwd", "secret.txt", "PR-1_2026-09-21_10-00-00.mov", ""] {
            XCTAssertNil(CaptureNameGuard.resolve(name, in: folders), name)
        }
    }
    func testPercentEncodedValidNameResolves() {
        let tmp = TempDir()
        tmp.touch("PR-1/PR-1_2026-09-21_10-00-00_2.jpg")
        XCTAssertNotNil(CaptureNameGuard.resolve("PR-1_2026-09-21_10-00-00_2.jpg",
                                                 in: [tmp.url.appendingPathComponent("PR-1")]))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter "HTTPMessageTests|CaptureNameGuardTests"`
Expected: build failure, `cannot find 'HTTPRequestParser' in scope`.

- [ ] **Step 3: Implement**

`Sources/MicroCAMCore/Streaming/HTTPMessage.swift`:
```swift
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
        guard end.lowerBound <= maxHeaderBytes,
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

    static let reasons: [Int: String] = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden",
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
```
`percentEncodedPath` keeps `%2F` encoded, so a percent-encoded slash can never become a path separator; route handlers decode only the final name segment and pass it through `CaptureNameGuard`.

`Sources/MicroCAMCore/Streaming/MJPEG.swift`:
```swift
import Foundation

/// Motion JPEG over `multipart/x-mixed-replace`, supported natively by
/// Safari/WebKit/Chrome `<img>`.
public enum MJPEG {
    public static let boundary = "microcamframe"

    public static func responseHead() -> Data {
        Data(("HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=\(boundary)\r\n"
              + "Cache-Control: no-store\r\nConnection: close\r\nPragma: no-cache\r\n\r\n").utf8)
    }

    public static func part(jpeg: Data) -> Data {
        Data("--\(boundary)\r\nContent-Type: image/jpeg\r\nContent-Length: \(jpeg.count)\r\n\r\n".utf8)
            + jpeg + Data("\r\n".utf8)
    }
}
```

`Sources/MicroCAMCore/Streaming/CaptureNameGuard.swift`:
```swift
import Foundation

/// Maps a name from a URL to a capture file, refusing anything that is not a
/// plain capture file name existing directly in one of `folders`.
public enum CaptureNameGuard {
    public static func resolve(_ rawName: String, in folders: [URL], fileManager: FileManager = .default) -> URL? {
        guard let name = rawName.removingPercentEncoding, !name.isEmpty,
              !name.contains("/"), !name.contains("\\"), !name.hasPrefix("."),
              let parsed = CaptureFileName.parse(name), parsed.ext.lowercased() == "jpg" else { return nil }
        for folder in folders {
            let candidate = folder.appendingPathComponent(name, isDirectory: false)
            guard candidate.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL else { continue }
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDir), !isDir.boolValue {
                return candidate
            }
        }
        return nil
    }
}
```
(Only JPEG photos are served; videos are never exposed over the stream.)

- [ ] **Step 4: Run to verify pass**

Run: `swift test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(core): add minimal HTTP messages, MJPEG framing and capture name guard"
```
Check Roborev.

### Task 3: Annotation model and renderer (Core)

**Files:**
- Create: `Sources/MicroCAMCore/Streaming/Annotation.swift`
- Test: `Tests/MicroCAMCoreTests/AnnotationTests.swift`

**Interfaces:**
- Produces: `struct AnnotationShape: Codable, Equatable { enum Kind: String, Codable { case arrow, ellipse, pen }; var kind: Kind; var points: [AnnotationPoint]; var color: String; var width: Double }`, `struct AnnotationPoint: Codable, Equatable { var x: Double; var y: Double }` (normalized 0…1, **origin top-left** as in the browser), `struct AnnotationRequest: Codable { var source: String; var shapes: [AnnotationShape]; func sanitized() -> AnnotationRequest }`, `enum AnnotationRenderer { static func render(_ shapes: [AnnotationShape], onto image: CGImage) -> CGImage? }`.

Sanitizing rules: at most 200 shapes and 5 000 points in total (extra ones dropped); coordinates clamped to 0…1; `width` clamped to 0.001…0.05 of the image width; `color` must match `#rrggbb`, otherwise `#ff3b30`; arrow/ellipse keep only the first and last point (need ≥ 2); pen needs ≥ 2 points.

- [ ] **Step 1: Write failing tests**

`Tests/MicroCAMCoreTests/AnnotationTests.swift`:
```swift
import CoreGraphics
import XCTest
@testable import MicroCAMCore

final class AnnotationTests: XCTestCase {
    func whiteImage(_ w: Int, _ h: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    /// RGBA at (x, y) with y measured from the top, like the browser.
    func pixel(_ image: CGImage, _ x: Int, _ yFromTop: Int) -> [UInt8] {
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let offset = (yFromTop * image.width + x) * 4 // bitmap memory is top-down
        return Array(UnsafeBufferPointer(start: data + offset, count: 4))
    }

    func testPenLineIsDrawnWithTopLeftOrigin() {
        let shape = AnnotationShape(kind: .pen, points: [.init(x: 0, y: 0.25), .init(x: 1, y: 0.25)],
                                    color: "#ff0000", width: 0.02)
        let out = AnnotationRenderer.render([shape], onto: whiteImage(200, 100))!
        let onLine = pixel(out, 100, 25)
        XCTAssertGreaterThan(onLine[0], 200); XCTAssertLessThan(onLine[1], 60)
        let below = pixel(out, 100, 75)
        XCTAssertGreaterThan(below[1], 240) // untouched white
    }
    func testEllipseOutlineNotFilled() {
        let shape = AnnotationShape(kind: .ellipse, points: [.init(x: 0.25, y: 0.25), .init(x: 0.75, y: 0.75)],
                                    color: "#00ff00", width: 0.02)
        let out = AnnotationRenderer.render([shape], onto: whiteImage(200, 100))!
        XCTAssertGreaterThan(pixel(out, 50, 50)[1], 200)   // left edge of the ellipse is green
        XCTAssertLessThan(pixel(out, 50, 50)[0], 60)
        XCTAssertGreaterThan(pixel(out, 100, 50)[0], 240)  // centre stays white
    }
    func testSanitizing() {
        var shapes = (0..<250).map { _ in
            AnnotationShape(kind: .arrow, points: [.init(x: -1, y: 0.5), .init(x: 0.3, y: 0.3), .init(x: 2, y: 0.5)],
                            color: "red; drop table", width: 9)
        }
        shapes.append(AnnotationShape(kind: .pen, points: [.init(x: 0.5, y: 0.5)], color: "#123456", width: 0.01))
        let clean = AnnotationRequest(source: "x", shapes: shapes).sanitized()
        XCTAssertEqual(clean.shapes.count, 200)
        XCTAssertEqual(clean.shapes[0].points, [.init(x: 0, y: 0.5), .init(x: 1, y: 0.5)])
        XCTAssertEqual(clean.shapes[0].color, "#ff3b30")
        XCTAssertEqual(clean.shapes[0].width, 0.05)
    }
    func testDropsDegenerateShapes() {
        let clean = AnnotationRequest(source: "x", shapes: [
            AnnotationShape(kind: .pen, points: [.init(x: 0.5, y: 0.5)], color: "#123456", width: 0.01),
            AnnotationShape(kind: .ellipse, points: [], color: "#123456", width: 0.01),
        ]).sanitized()
        XCTAssertTrue(clean.shapes.isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter AnnotationTests`
Expected: build failure, `cannot find 'AnnotationShape' in scope`.

- [ ] **Step 3: Implement**

`Sources/MicroCAMCore/Streaming/Annotation.swift`:
```swift
import CoreGraphics
import Foundation

public struct AnnotationPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// One shape drawn in the browser. Points are normalized to the image
/// (0…1) with the origin top-left; `width` is a fraction of the image width.
public struct AnnotationShape: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case arrow, ellipse, pen }
    public var kind: Kind
    public var points: [AnnotationPoint]
    public var color: String
    public var width: Double

    public init(kind: Kind, points: [AnnotationPoint], color: String, width: Double) {
        self.kind = kind; self.points = points; self.color = color; self.width = width
    }
}

public struct AnnotationRequest: Codable, Sendable {
    public static let maxShapes = 200
    public static let maxPoints = 5_000
    public static let defaultColor = "#ff3b30"

    public var source: String
    public var shapes: [AnnotationShape]

    public init(source: String, shapes: [AnnotationShape]) { self.source = source; self.shapes = shapes }

    public func sanitized() -> AnnotationRequest {
        var budget = Self.maxPoints
        var out: [AnnotationShape] = []
        for var shape in shapes where out.count < Self.maxShapes {
            var pts = shape.points.map { AnnotationPoint(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1)) }
            if shape.kind != .pen, let first = pts.first, let last = pts.last { pts = [first, last] }
            guard pts.count >= 2, pts.count <= budget else { continue }
            budget -= pts.count
            shape.points = pts
            shape.width = min(max(shape.width, 0.001), 0.05)
            if shape.color.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) == nil {
                shape.color = Self.defaultColor
            }
            out.append(shape)
        }
        return AnnotationRequest(source: source, shapes: out)
    }
}

public enum AnnotationRenderer {
    public static func render(_ shapes: [AnnotationShape], onto image: CGImage) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let point = { (p: AnnotationPoint) in CGPoint(x: p.x * w, y: (1 - p.y) * h) }   // flip to bottom-left
        for shape in shapes {
            ctx.setStrokeColor(color(shape.color))
            ctx.setLineWidth(shape.width * w)
            let pts = shape.points.map(point)
            guard pts.count >= 2 else { continue }
            switch shape.kind {
            case .pen:
                ctx.addLines(between: pts)
                ctx.strokePath()
            case .ellipse:
                ctx.strokeEllipse(in: CGRect(x: min(pts[0].x, pts[1].x), y: min(pts[0].y, pts[1].y),
                                             width: abs(pts[1].x - pts[0].x), height: abs(pts[1].y - pts[0].y)))
            case .arrow:
                let (a, b) = (pts[0], pts[1])
                ctx.move(to: a); ctx.addLine(to: b)
                let angle = atan2(b.y - a.y, b.x - a.x)
                let head = max(shape.width * w * 4, 12)
                for side in [CGFloat.pi * 0.85, -CGFloat.pi * 0.85] {
                    ctx.move(to: b)
                    ctx.addLine(to: CGPoint(x: b.x + head * cos(angle + side), y: b.y + head * sin(angle + side)))
                }
                ctx.strokePath()
            }
        }
        return ctx.makeImage()
    }

    private static func color(_ hex: String) -> CGColor {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0xFF3B30
        return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test`
Expected: all pass. If `pixel()` reads rows bottom-up on this platform, flip the helper (`yFromTop` → `image.height - 1 - yFromTop`), not the renderer; the renderer contract (top-left input) is what the page relies on.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(core): add annotation shapes, sanitizing and rendering"
```
Check Roborev.

### Task 4: Settings and lifecycle for streaming and viewer mode (Core)

**Files:**
- Modify: `Sources/MicroCAMCore/AppSettings.swift`, `Sources/MicroCAMCore/CaptureLifecyclePolicy.swift`
- Test: `Tests/MicroCAMCoreTests/SettingsStoreTests.swift`, `Tests/MicroCAMCoreTests/PolicyTests.swift`

**Interfaces:**
- Produces: `enum StreamMode: String, Codable, CaseIterable { case imageOnly, controls }`, `enum AppMode: String, Codable, CaseIterable { case camera, viewer }`; `AppSettings` fields `streamingEnabled = false`, `streamingPort = 8090`, `streamingMode = StreamMode.controls`, `appMode = AppMode.camera`, `viewerSourceName: String? = nil`, `viewerManualURL: String? = nil`; `CaptureLifecycleState.streamViewers = false`.

- [ ] **Step 1: Write failing tests**

Append to `SettingsStoreTests`:
```swift
    func testStreamingAndViewerDefaultsAndRoundTrip() {
        let store = SettingsStore(defaults: defaults)
        var s = store.load()
        XCTAssertFalse(s.streamingEnabled)
        XCTAssertEqual(s.streamingPort, 8090)
        XCTAssertEqual(s.streamingMode, .controls)
        XCTAssertEqual(s.appMode, .camera)
        s.streamingEnabled = true
        s.streamingMode = .imageOnly
        s.appMode = .viewer
        s.viewerSourceName = "bench Mac"
        store.save(s)
        XCTAssertEqual(SettingsStore(defaults: defaults).load(), s)
    }
```
Append to `PolicyTests`:
```swift
    func testStreamViewersKeepCameraRunningExceptSleep() {
        var s = CaptureLifecycleState()
        s.windowVisible = false
        s.screenLocked = true
        s.streamViewers = true
        XCTAssertTrue(CaptureLifecyclePolicy.shouldRun(s))
        s.systemSleeping = true
        XCTAssertFalse(CaptureLifecyclePolicy.shouldRun(s))
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter "SettingsStoreTests|PolicyTests"`
Expected: build failure, `value of type 'AppSettings' has no member 'streamingEnabled'`.

- [ ] **Step 3: Implement**

In `AppSettings.swift` add the enums next to the others:
```swift
public enum StreamMode: String, Codable, CaseIterable, Sendable { case imageOnly, controls }
public enum AppMode: String, Codable, CaseIterable, Sendable { case camera, viewer }
```
Add stored properties after `webhookSendVideos`:
```swift
    /// Live stream to other devices (off by default). The photo PIN lives in the Keychain.
    public var streamingEnabled = false
    public var streamingPort = 8090
    public var streamingMode = StreamMode.controls
    /// `viewer` turns this Mac into a screen for another microCAM's stream.
    public var appMode = AppMode.camera
    public var viewerSourceName: String? = nil
    public var viewerManualURL: String? = nil
```
Add the six keys to `CodingKeys` and to `init(from:)` using the existing `value(_:_:)` helper, e.g. `streamingPort = value(.streamingPort, d.streamingPort)`.

In `CaptureLifecyclePolicy.swift` add `public var streamViewers = false` to the state and change the keep-alive line to:
```swift
        if s.recording || s.timelapseRunning || s.streamViewers { return true }
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(core): add streaming and viewer-mode settings; keep camera running for viewers"
```
Check Roborev.

### Task 5: Stream router (Core)

The routing and every security check live in Core, behind a small backend protocol, so they can be unit-tested without sockets.

**Files:**
- Create: `Sources/MicroCAMCore/Streaming/StreamRouter.swift`
- Test: `Tests/MicroCAMCoreTests/StreamRouterTests.swift`

**Interfaces:**
- Consumes: `HTTPRequest`, `HTTPResponse`, `PinGuard`, `CaptureNameGuard`, `AnnotationRequest`, `StreamMode` (Tasks 1–4).
- Produces:
  - `struct StreamStatus: Codable, Equatable { var job: String?; var mode: StreamMode; var photoEnabled: Bool; var viewers: Int }`
  - `struct CaptureRef: Codable, Equatable { var name: String; var url: String }` (`url` = `/captures/<name>`)
  - `protocol StreamBackend: AnyObject { func status() -> StreamStatus; func page(mode: StreamMode, embedded: Bool) -> String; func captureFolders() -> [URL]; func takePhoto(completion: @escaping (Result<String, Error>) -> Void); func saveAnnotated(_ request: AnnotationRequest, source: URL, completion: @escaping (Result<String, Error>) -> Void) }` — completions may be called on any queue.
  - `enum StreamRoute { case response(HTTPResponse), stream }`
  - `final class StreamRouter { init(backend: StreamBackend, pinGuard: PinGuard = PinGuard(), mode: @escaping () -> StreamMode, pin: @escaping () -> String?); func handle(_ request: HTTPRequest, completion: @escaping (StreamRoute) -> Void) }`

Routes:

| Method + path | Mode | Result |
|---|---|---|
| `GET /` | any | page HTML (`?embedded=1` → viewer-mode variant) |
| `GET /status` | any | `StreamStatus` JSON |
| `GET /stream` | any | `.stream` (the server takes over the connection) |
| `GET /captures/<name>` | controls | JPEG via `CaptureNameGuard`, else 404 |
| `POST /photo` | controls | PIN checks → `takePhoto` → `CaptureRef` |
| `POST /annotated` | controls | PIN checks → JSON `AnnotationRequest` → `saveAnnotated` → `CaptureRef` |
| anything else | — | 405 for known paths with the wrong method, 404 otherwise; `OPTIONS` always 405 (no CORS) |

Remote-action checks run in this order: mode (`imageOnly` → 403 `{"error":"disabled"}`), method, same origin (`Origin` present and its host:port ≠ `Host` → 403 `{"error":"origin"}`), PIN (`notConfigured` → 403 `{"error":"pin-not-set"}`, `wrong` → 401 `{"error":"pin"}`, `locked` → 429 `{"error":"locked","retryAfter":<s>}`).

- [ ] **Step 1: Write failing tests**

`Tests/MicroCAMCoreTests/StreamRouterTests.swift`:
```swift
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
    var backend: FakeBackend!
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
        guard case .response(let ok) = route(request("GET", "/captures/PR-1_2026-09-21_10-00-00.jpg")) else { return XCTFail() }
        XCTAssertEqual(ok.status, 200)
        XCTAssertTrue(ok.headers.contains { $0 == ("Content-Type", "image/jpeg") })
        XCTAssertEqual(status(route(request("GET", "/captures/..%2F..%2Fsecret.txt"))), 404)
    }

    func testAnnotatedValidatesJSONAndSource() {
        let tmp = TempDir()
        tmp.touch("PR-1/PR-1_2026-09-21_10-00-00.jpg")
        backend.folders = [tmp.url.appendingPathComponent("PR-1")]
        let pinHeader = ["X-MicroCAM-PIN": "1234"]
        XCTAssertEqual(status(route(request("POST", "/annotated", headers: pinHeader, body: "not json"))), 400)
        XCTAssertEqual(status(route(request("POST", "/annotated", headers: pinHeader,
                                            body: #"{"source":"nope.jpg","shapes":[]}"#))), 404)
        let body = #"{"source":"PR-1_2026-09-21_10-00-00.jpg","shapes":[{"kind":"arrow","points":[{"x":0.1,"y":0.1},{"x":0.5,"y":0.5}],"color":"#ff0000","width":0.01}]}"#
        XCTAssertEqual(status(route(request("POST", "/annotated", headers: pinHeader, body: body))), 200)
        XCTAssertEqual(backend.annotated.first?.shapes.count, 1)
    }

    func testUnknownAndOptions() {
        XCTAssertEqual(status(route(request("GET", "/nope"))), 404)
        XCTAssertEqual(status(route(request("OPTIONS", "/photo"))), 405)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter StreamRouterTests`
Expected: build failure, `cannot find type 'StreamBackend' in scope`.

- [ ] **Step 3: Implement**

`Sources/MicroCAMCore/Streaming/StreamRouter.swift`:
```swift
import Foundation

public struct StreamStatus: Codable, Equatable, Sendable {
    public var job: String?
    public var mode: StreamMode
    public var photoEnabled: Bool
    public var viewers: Int
    public init(job: String?, mode: StreamMode, photoEnabled: Bool, viewers: Int) {
        self.job = job; self.mode = mode; self.photoEnabled = photoEnabled; self.viewers = viewers
    }
}

public struct CaptureRef: Codable, Equatable, Sendable {
    public var name: String
    public var url: String
    public init(name: String) {
        self.name = name
        url = "/captures/" + (name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name)
    }
}

public protocol StreamBackend: AnyObject {
    func status() -> StreamStatus
    func page(mode: StreamMode, embedded: Bool) -> String
    func captureFolders() -> [URL]
    func takePhoto(completion: @escaping (Result<String, Error>) -> Void)
    func saveAnnotated(_ request: AnnotationRequest, source: URL, completion: @escaping (Result<String, Error>) -> Void)
}

public enum StreamRoute {
    case response(HTTPResponse)
    case stream
}

public final class StreamRouter {
    private struct ErrorBody: Encodable { let error: String; var retryAfter: Int? = nil }

    private weak var backend: StreamBackend?
    private let pinGuard: PinGuard
    private let mode: () -> StreamMode
    private let pin: () -> String?

    public init(backend: StreamBackend, pinGuard: PinGuard = PinGuard(),
                mode: @escaping () -> StreamMode, pin: @escaping () -> String?) {
        self.backend = backend
        self.pinGuard = pinGuard
        self.mode = mode
        self.pin = pin
    }

    public func handle(_ request: HTTPRequest, completion: @escaping (StreamRoute) -> Void) {
        guard let backend else { return completion(.response(.text(503, "unavailable"))) }
        let path = request.path
        if request.method == "OPTIONS" { return completion(.response(.text(405, "no"))) }

        switch (request.method, path) {
        case ("GET", "/"):
            completion(.response(.html(backend.page(mode: mode(), embedded: request.query["embedded"] == "1"))))
        case ("GET", "/status"):
            completion(.response(.json(200, backend.status())))
        case ("GET", "/stream"):
            completion(.stream)
        case ("GET", _) where path.hasPrefix("/captures/"):
            guard mode() == .controls else { return completion(.response(.json(403, ErrorBody(error: "disabled")))) }
            let name = String(path.dropFirst("/captures/".count))
            guard let file = CaptureNameGuard.resolve(name, in: backend.captureFolders()),
                  let data = try? Data(contentsOf: file) else { return completion(.response(.text(404, "not found"))) }
            completion(.response(HTTPResponse(status: 200, headers: [("Content-Type", "image/jpeg")], body: data)))
        case (_, "/photo"), (_, "/annotated"):
            if let denied = remoteActionDenied(request) { return completion(.response(denied)) }
            path == "/photo" ? photo(backend, completion) : annotated(request, backend, completion)
        case (_, "/"), (_, "/status"), (_, "/stream"):
            completion(.response(.text(405, "method not allowed")))
        default:
            completion(.response(.text(404, "not found")))
        }
    }

    private func remoteActionDenied(_ request: HTTPRequest) -> HTTPResponse? {
        guard mode() == .controls else { return .json(403, ErrorBody(error: "disabled")) }
        guard request.method == "POST" else { return .text(405, "method not allowed") }
        if let origin = request.header("origin") {
            let originHost = URLComponents(string: origin).map { c in
                c.port.map { "\(c.host ?? ""):\($0)" } ?? (c.host ?? "")
            }
            guard originHost == request.header("host") else { return .json(403, ErrorBody(error: "origin")) }
        }
        switch pinGuard.check(request.header("x-microcam-pin"), expected: pin()) {
        case .ok: return nil
        case .notConfigured: return .json(403, ErrorBody(error: "pin-not-set"))
        case .wrong: return .json(401, ErrorBody(error: "pin"))
        case .locked(let until):
            return .json(429, ErrorBody(error: "locked", retryAfter: max(1, Int(until.timeIntervalSinceNow.rounded(.up)))))
        }
    }

    private func photo(_ backend: StreamBackend, _ completion: @escaping (StreamRoute) -> Void) {
        backend.takePhoto { result in
            switch result {
            case .success(let name): completion(.response(.json(200, CaptureRef(name: name))))
            case .failure(let error): completion(.response(.json(500, ErrorBody(error: error.localizedDescription))))
            }
        }
    }

    private func annotated(_ request: HTTPRequest, _ backend: StreamBackend, _ completion: @escaping (StreamRoute) -> Void) {
        guard let decoded = try? JSONDecoder().decode(AnnotationRequest.self, from: request.body) else {
            return completion(.response(.json(400, ErrorBody(error: "json"))))
        }
        let clean = decoded.sanitized()
        guard let source = CaptureNameGuard.resolve(clean.source, in: backend.captureFolders()) else {
            return completion(.response(.json(404, ErrorBody(error: "source"))))
        }
        backend.saveAnnotated(clean, source: source) { result in
            switch result {
            case .success(let name): completion(.response(.json(200, CaptureRef(name: name))))
            case .failure(let error): completion(.response(.json(500, ErrorBody(error: error.localizedDescription))))
            }
        }
    }
}
```
Note: the lockout `retryAfter` uses the wall clock; tests only check the status code.

- [ ] **Step 4: Run to verify pass**

Run: `swift test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(core): add stream router with PIN, method and origin checks"
```
Check Roborev.

### Task 6: Stream server, hub and bench wiring (App)

**Files:**
- Create: `Sources/MicroCAMApp/Streaming/StreamServer.swift`, `Sources/MicroCAMApp/Streaming/StreamHub.swift`, `Sources/MicroCAMApp/Streaming/StreamBackendAdapter.swift`, `Sources/MicroCAMApp/Streaming/NetworkAddresses.swift`, `Sources/MicroCAMApp/Streaming/StreamPage.swift` (placeholder page, replaced in Task 7)
- Modify: `Sources/MicroCAMApp/Integrations/KeychainToken.swift` (account parameter), `Sources/MicroCAMApp/AppModel.swift`, `Sources/MicroCAMApp/Views/SettingsView.swift`, `Sources/MicroCAMApp/Views/StatusBar.swift`, `Resources/Info.plist`

**Interfaces:**
- Consumes: everything from Tasks 1–5; `AppModel.takePhoto`, `reserveURL`, `releaseURL`, `capturesChanged`, `adjustmentsBox`, `lifecycle`, `settings` (v1).
- Produces:
  - `KeychainToken.read(account: String = "token")`, `KeychainToken.write(_:account:)`
  - `final class StreamHub { let hasViewers: LockedValue<Bool>; var onViewersChanged: ((Int) -> Void)?; init(queue: DispatchQueue); func add(_ connection: NWConnection); func offer(_ pixelBuffer: CVPixelBuffer, adjustments: ImageAdjustments); func closeAll() }`
  - `final class StreamServer { init(router: StreamRouter, hub: StreamHub, queue: DispatchQueue); var onError: ((String?) -> Void)?; func start(port: UInt16, serviceName: String); func stop() }`
  - `final class StreamBackendAdapter: StreamBackend { init(model: AppModel) }`
  - `enum NetworkAddresses { static func streamIPv4() -> [String] }`
  - `AppModel`: `let streamHub: StreamHub`, `@Published private(set) var streamViewers: Int`, `@Published private(set) var streamError: String?`, `var streamPIN: String?`, `func setStreamPIN(_ pin: String?)`, `func applyStreaming()`, `func takePhoto(kind:remote:completion:)`, `func saveAnnotatedCopy(of:shapes:completion:)`

- [ ] **Step 1: Keychain account parameter**

In `KeychainToken.swift` replace the fixed `account` with a parameter (default `"token"`, so webhook call sites stay unchanged):
```swift
enum KeychainToken {
    private static let service = "xyz.vaclavik.microcam.webhook"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read(account: String = "token") -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Empty or nil removes the secret.
    static func write(_ value: String?, account: String = "token") {
        SecItemDelete(query(account) as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var q = query(account)
        q[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }
}
```

- [ ] **Step 2: StreamHub**

`Sources/MicroCAMApp/Streaming/StreamHub.swift`:
```swift
import CoreImage
import Metal
import MicroCAMCore
import Network

/// Viewer registry and MJPEG broadcaster. Encodes only while someone is
/// watching, at most 15 fps, one frame at a time; a viewer whose previous
/// frame is still being sent simply skips frames (never queues them), so a
/// slow Wi-Fi client cannot slow down anyone else or the bench.
final class StreamHub {
    private final class Client {
        let connection: NWConnection
        var busy = false
        init(_ connection: NWConnection) { self.connection = connection }
    }

    static let maxFPS = 15.0
    static let maxWidth: CGFloat = 1920

    let hasViewers = LockedValue(false)
    /// Called on the main queue with the new viewer count.
    var onViewersChanged: ((Int) -> Void)?

    private let queue: DispatchQueue            // owns `clients`
    private let encodeQueue = DispatchQueue(label: "microcam.stream.encode", qos: .utility)
    private var clients: [ObjectIdentifier: Client] = [:]
    private let encoding = LockedValue(false)
    private var lastOffer: CFAbsoluteTime = 0   // video queue only
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let context: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() { return CIContext(mtlDevice: device, options: [.cacheIntermediates: false]) }
        return CIContext(options: [.cacheIntermediates: false])
    }()

    init(queue: DispatchQueue) { self.queue = queue }

    /// Server queue. Takes over a connection that asked for `/stream`.
    func add(_ connection: NWConnection) {
        let client = Client(connection)
        let id = ObjectIdentifier(connection)
        clients[id] = client
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.queue.async { self?.remove(id) }
            default: break
            }
        }
        // A read that completes means the viewer closed the page.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] _, _, _, _ in
            self?.queue.async { self?.remove(id) }
        }
        connection.send(content: MJPEG.responseHead(), completion: .contentProcessed { _ in })
        publishCount()
    }

    /// Video queue, every camera frame. Cheap unless someone is watching.
    func offer(_ pixelBuffer: CVPixelBuffer, adjustments: ImageAdjustments) {
        guard hasViewers.value else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastOffer >= 1 / Self.maxFPS, !encoding.value else { return }
        lastOffer = now
        encoding.value = true
        encodeQueue.async { [weak self] in
            guard let self else { return }
            defer { self.encoding.value = false }
            var image = AdjustmentPipeline.apply(adjustments, to: CIImage(cvPixelBuffer: pixelBuffer))
            if image.extent.width > Self.maxWidth {
                let s = Self.maxWidth / image.extent.width
                image = image.transformed(by: CGAffineTransform(scaleX: s, y: s))
            }
            guard let jpeg = self.context.jpegRepresentation(
                of: image, colorSpace: self.colorSpace,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.7]) else { return }
            let part = MJPEG.part(jpeg: jpeg)
            self.queue.async { self.broadcast(part) }
        }
    }

    func closeAll() {
        queue.async {
            self.clients.values.forEach { $0.connection.cancel() }
            self.clients.removeAll()
            self.publishCount()
        }
    }

    private func broadcast(_ part: Data) {
        for client in clients.values where !client.busy {
            client.busy = true
            client.connection.send(content: part, completion: .contentProcessed { [weak self] error in
                self?.queue.async {
                    client.busy = false
                    if error != nil { self?.remove(ObjectIdentifier(client.connection)) }
                }
            })
        }
    }

    private func remove(_ id: ObjectIdentifier) {
        guard let client = clients.removeValue(forKey: id) else { return }
        client.connection.cancel()
        publishCount()
    }

    private func publishCount() {
        let count = clients.count
        hasViewers.value = count > 0
        DispatchQueue.main.async { self.onViewersChanged?(count) }
    }
}
```

- [ ] **Step 3: StreamServer**

`Sources/MicroCAMApp/Streaming/StreamServer.swift`:
```swift
import Foundation
import MicroCAMCore
import Network

/// HTTP/1.1, one request per connection. Refuses non-local peers before
/// reading anything, gives slow clients 10 s to send their request, and
/// advertises itself over Bonjour for viewer mode.
final class StreamServer {
    static let serviceType = "_microcam._tcp"

    var onError: ((String?) -> Void)?   // main queue; nil = running fine

    private let router: StreamRouter
    private let hub: StreamHub
    private let queue: DispatchQueue
    private var listener: NWListener?

    init(router: StreamRouter, hub: StreamHub, queue: DispatchQueue) {
        self.router = router
        self.hub = hub
        self.queue = queue
    }

    func start(port: UInt16, serviceName: String) {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return report("Neplatný port \(port).") }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: nwPort)
            listener.service = NWListener.Service(name: serviceName, type: Self.serviceType)
            listener.newConnectionHandler = { [weak self] in self?.accept($0) }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready: self?.report(nil)
                case .failed(let error): self?.report("Přenos nelze spustit na portu \(port): \(error.localizedDescription)")
                default: break
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            report("Přenos nelze spustit na portu \(port): \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        hub.closeAll()
    }

    private func report(_ text: String?) {
        DispatchQueue.main.async { self.onError?(text) }
    }

    private func accept(_ connection: NWConnection) {
        guard case .hostPort(let host, _) = connection.endpoint, StreamAccessPolicy.isAllowed(Self.string(host)) else {
            connection.cancel()
            return
        }
        connection.start(queue: queue)
        let handled = LockedValue(false)
        queue.asyncAfter(deadline: .now() + 10) {
            if !handled.value { connection.cancel() }
        }
        receive(connection, buffer: Data(), handled: handled)
    }

    private func receive(_ connection: NWConnection, buffer: Data, handled: LockedValue<Bool>) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            switch HTTPRequestParser.parse(buffer) {
            case .incomplete:
                if isComplete || error != nil { connection.cancel() } else { self.receive(connection, buffer: buffer, handled: handled) }
            case .invalid:
                handled.value = true
                self.send(.text(400, "bad request"), on: connection)
            case .complete(let request):
                handled.value = true
                // The backend lives on the main actor.
                DispatchQueue.main.async {
                    self.router.handle(request) { route in
                        self.queue.async {
                            switch route {
                            case .response(let response): self.send(response, on: connection)
                            case .stream: self.hub.add(connection)
                            }
                        }
                    }
                }
            }
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.serialized(), completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func string(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let address): "\(address)"
        case .ipv6(let address): "\(address)"
        case .name(let name, _): name
        @unknown default: ""
        }
    }
}
```

- [ ] **Step 4: Backend adapter, addresses, placeholder page**

`Sources/MicroCAMApp/Streaming/StreamBackendAdapter.swift`:
```swift
import Foundation
import MicroCAMCore

/// Bridges the router (called on the main queue by `StreamServer`) to the
/// main-actor `AppModel`.
final class StreamBackendAdapter: StreamBackend {
    private unowned let model: AppModel

    init(model: AppModel) { self.model = model }

    func status() -> StreamStatus {
        MainActor.assumeIsolated {
            let s = model.settings
            return StreamStatus(job: s.jobsEnabled ? s.activeJob?.value : nil, mode: s.streamingMode,
                                photoEnabled: s.streamingMode == .controls && model.streamPIN != nil,
                                viewers: model.streamViewers)
        }
    }

    func page(mode: StreamMode, embedded: Bool) -> String { StreamPage.html(mode: mode, embedded: embedded) }

    func captureFolders() -> [URL] {
        MainActor.assumeIsolated { model.settings.layout?.listedFolders(for: model.settings.jobContext) ?? [] }
    }

    func takePhoto(completion: @escaping (Result<String, Error>) -> Void) {
        MainActor.assumeIsolated {
            model.takePhoto(remote: true) { completion($0.map(\.lastPathComponent)) }
        }
    }

    func saveAnnotated(_ request: AnnotationRequest, source: URL, completion: @escaping (Result<String, Error>) -> Void) {
        MainActor.assumeIsolated {
            model.saveAnnotatedCopy(of: source, shapes: request.shapes) { completion($0.map(\.lastPathComponent)) }
        }
    }
}
```

`Sources/MicroCAMApp/Streaming/NetworkAddresses.swift`:
```swift
import Darwin
import MicroCAMCore

enum NetworkAddresses {
    /// IPv4 addresses a viewer can use (LAN, Tailscale), loopback excluded.
    static func streamIPv4() -> [String] {
        var result: [String] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let sa = ptr.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let address = String(cString: host)
            if !address.hasPrefix("127."), StreamAccessPolicy.isAllowed(address), !result.contains(address) {
                result.append(address)
            }
        }
        return result
    }
}
```

`Sources/MicroCAMApp/Streaming/StreamPage.swift` (placeholder; Task 7 replaces the template):
```swift
import MicroCAMCore

enum StreamPage {
    static func html(mode: StreamMode, embedded: Bool) -> String {
        #"<!doctype html><meta charset="utf-8"><title>microCAM</title><body style="margin:0;background:#000"><img src="/stream" style="width:100vw;height:100vh;object-fit:contain">"#
    }
}
```

- [ ] **Step 5: AppModel wiring**

Add to `AppModel` (new `// MARK: Streaming` section):
```swift
    let streamHub = StreamHub(queue: DispatchQueue(label: "microcam.stream"))
    private var streamServer: StreamServer?
    @Published private(set) var streamViewers = 0
    @Published private(set) var streamError: String?
    private var cachedStreamPIN: String?? = nil

    var streamPIN: String? {
        if case .some(let value) = cachedStreamPIN { return value }
        let value = KeychainToken.read(account: "stream-pin")
        cachedStreamPIN = .some(value)
        return value
    }

    func setStreamPIN(_ pin: String?) {
        let value = pin.flatMap { PinGuard.isValidPIN($0) ? $0 : nil }
        KeychainToken.write(value, account: "stream-pin")
        cachedStreamPIN = .some(value)
    }

    /// Starts, restarts or stops the server to match settings (camera mode only).
    func applyStreaming() {
        guard demo == nil, settings.appMode == .camera, settings.streamingEnabled else {
            streamServer?.stop()
            streamServer = nil
            streamError = nil
            return
        }
        if streamServer == nil {
            let queue = DispatchQueue(label: "microcam.stream.server")
            let router = StreamRouter(backend: streamBackend, mode: { [weak self] in
                MainActor.assumeIsolated { self?.settings.streamingMode ?? .imageOnly }
            }, pin: { [weak self] in
                MainActor.assumeIsolated { self?.streamPIN }
            })
            let server = StreamServer(router: router, hub: streamHub, queue: queue)
            server.onError = { [weak self] in self?.streamError = $0 }
            streamServer = server
        }
        guard (1024...65535).contains(settings.streamingPort) else {
            streamServer?.stop()
            streamError = "Port musí být 1024–65535."
            return
        }
        streamServer?.start(port: UInt16(settings.streamingPort),
                            serviceName: Host.current().localizedName ?? "microCAM")
    }

    private lazy var streamBackend = StreamBackendAdapter(model: self)
```
Note: the router's `mode`/`pin` closures run on the main queue (the server calls `router.handle` on main), so `MainActor.assumeIsolated` holds.

In `init()`:
- extend the frame closure: after the renderer/recorder lines add `hub.offer(pixelBuffer, adjustments: adjustments.value)` inside an `if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)` (capture `let hub = streamHub` before the closure);
- add
```swift
        streamHub.onViewersChanged = { [weak self] count in
            guard let self else { return }
            self.streamViewers = count
            self.lifecycle.update { $0.streamViewers = count > 0 }
        }
```
- call `applyStreaming()` at the end of `start()` (after the camera is selected).

In the `settings` `didSet`, add:
```swift
            if settings.streamingEnabled != oldValue.streamingEnabled || settings.streamingPort != oldValue.streamingPort
                || settings.appMode != oldValue.appMode { applyStreaming() }
```

Change `takePhoto` to report its result (existing callers keep working):
```swift
    func takePhoto(kind: CaptureKind = .photo, remote: Bool = false,
                   completion: ((Result<URL, Error>) -> Void)? = nil) {
```
In its body: on the `noFrame` and `reserveURL` failures call `completion?(.failure(error))` after `report`; on success set the message to `remote ? "Vyfoceno z recepce: \(name)" : "Uloženo: \(name)"` and call `completion?(.success(url))`; on write failure `completion?(.failure(error))`.

Add the annotated copy:
```swift
    /// Renders shapes onto a saved capture and stores the result as the next
    /// index of the same timestamp (`…_2.jpg`); the original stays untouched.
    func saveAnnotatedCopy(of source: URL, shapes: [AnnotationShape],
                           completion: @escaping (Result<URL, Error>) -> Void) {
        guard let name = CaptureFileName.parse(source.lastPathComponent) else {
            return completion(.failure(CocoaError(.fileReadInvalidFileName)))
        }
        let pending = pendingURLs
        let destination = CaptureFileNamer(fileExists: {
            pending.contains($0) || FileManager.default.fileExists(atPath: $0.path)
        }).availableURL(in: source.deletingLastPathComponent(), prefix: name.prefix, timestamp: name.timestamp, ext: "jpg")
        pendingURLs.insert(destination)
        let quality = settings.jpegQuality
        Task.detached(priority: .userInitiated) {
            let result: Result<URL, Error> = Result {
                guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(src, 0, nil),
                      let rendered = AnnotationRenderer.render(shapes, onto: image),
                      let dest = CGImageDestinationCreateWithURL(destination as CFURL, "public.jpeg" as CFString, 1, nil)
                else { throw CocoaError(.fileWriteUnknown) }
                CGImageDestinationAddImage(dest, rendered, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
                guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
                return destination
            }
            await MainActor.run {
                self.releaseURL(destination)
                if case .success(let url) = result {
                    self.message = StatusMessage(text: "Anotace z recepce: \(url.lastPathComponent)", isError: false)
                    self.capturesChanged()
                }
                completion(result)
            }
        }
    }
```
(`pendingURLs` is currently `private`; keep it private — this method lives in the same class. Add `import ImageIO` at the top of `AppModel.swift`.)

- [ ] **Step 6: Settings tab, status bar, Info.plist**

In `SettingsView`, add a tab before "Chování": `StreamSettingsTab().tabItem { Label("Přenos", systemImage: "dot.radiowaves.left.and.right") }.tag("stream")`, and:
```swift
struct StreamSettingsTab: View {
    @EnvironmentObject private var model: AppModel
    @State private var pin = ""
    @State private var pinInvalid = false

    var body: some View {
        Form {
            Toggle("Živý přenos obrazu do sítě", isOn: $model.settings.streamingEnabled)
            if model.settings.streamingEnabled {
                Picker("Stránka", selection: $model.settings.streamingMode) {
                    Text("S ovládáním (focení, kreslení)").tag(StreamMode.controls)
                    Text("Jen obraz").tag(StreamMode.imageOnly)
                }
                TextField("Port", value: $model.settings.streamingPort, format: .number.grouping(.never))
                SecureField("PIN pro focení (4–8 číslic)", text: $pin)
                    .onSubmit(savePIN)
                    .onDisappear(savePIN)
                if pinInvalid { Text("PIN musí mít 4–8 číslic.").font(.caption).foregroundStyle(.red) }
                if model.streamPIN == nil, model.settings.streamingMode == .controls {
                    Text("Bez PINu je focení z jiného zařízení vypnuté.").font(.caption).foregroundStyle(.secondary)
                }
                if let error = model.streamError { Text(error).font(.caption).foregroundStyle(.red) }
                LabeledContent("Otevřít na jiném zařízení") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(NetworkAddresses.streamIPv4(), id: \.self) { address in
                            let url = "http://\(address):\(model.settings.streamingPort)/"
                            HStack {
                                Text(url).textSelection(.enabled).monospaced()
                                Button("Kopírovat") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(url, forType: .string)
                                }
                            }
                        }
                    }
                }
                Text("Sleduje: \(model.streamViewers)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { pin = model.streamPIN ?? "" }
    }

    private func savePIN() {
        pinInvalid = !pin.isEmpty && !PinGuard.isValidPIN(pin)
        if !pinInvalid { model.setStreamPIN(pin.isEmpty ? nil : pin) }
    }
}
```
(`import AppKit` for `NSPasteboard` if not already imported.)

In `StatusBar`, before `Spacer()`:
```swift
            if model.streamViewers > 0 {
                Label("Sleduje \(model.streamViewers)", systemImage: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
            }
```

In `Resources/Info.plist` add (Bonjour and local-network privacy):
```xml
    <key>NSLocalNetworkUsageDescription</key><string>microCAM posílá živý obraz mikroskopu do zařízení v místní síti.</string>
    <key>NSBonjourServices</key><array><string>_microcam._tcp</string></array>
```

- [ ] **Step 7: Build and smoke-test locally**

Run: `swift build && swift test && scripts/make-app.sh`. On a Mac with a camera and the user present (test-mac, via `scripts/deploy.sh test-mac` from Task 9, or copy manually): enable Přenos, set PIN `1234`, allow the incoming-connection and local-network prompts, then from the dev Mac:
```bash
curl -s http://<ip>:8090/status                         # JSON with job/mode
curl -s --max-time 3 http://<ip>:8090/stream | grep -c "Content-Type: image/jpeg"   # ≥ 20
curl -s -o /dev/null -w "%{http_code}\n" -X POST http://<ip>:8090/photo              # 401
```
While `curl … /stream` runs, the bench status bar shows "Sleduje 1"; afterwards it disappears. Note CPU with and without a viewer.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat(app): add local-network MJPEG stream server with remote photo and annotations API"
```
Check Roborev.

### Task 7: The stream page (HTML/CSS/JS)

**Files:**
- Replace: `Sources/MicroCAMApp/Streaming/StreamPage.swift`

**Interfaces:**
- Consumes: routes from Task 5 (`/stream`, `/status`, `/photo`, `/annotated`, `/captures/<name>`), `CaptureRef` JSON `{name, url}`, `StreamStatus` JSON `{job, mode, photoEnabled, viewers}`, error JSON `{error, retryAfter?}`.
- Produces: `StreamPage.html(mode:embedded:) -> String`.

Behaviour:
- **Jen obraz:** only the image, black background, no UI. It still reconnects automatically.
- **S ovládáním:**
  - top pill with the job;
  - bottom toolbar: Kreslit (tool picker: šipka / kruh / pero; colors red / yellow / green / blue), Smazat, Vyfotit, Celá obrazovka;
  - both bars fade out after 3 s without pointer movement.
- **Frozen photo mode** (after Vyfotit): the live stream is closed, which frees the server; drawing is on. Buttons: Uložit k zakázce, Stáhnout, Zpět na živý obraz.
- **`embedded`** (viewer app): hides the full-screen button, because the app window handles full screen.
- The PIN is asked on the first Vyfotit and kept in `localStorage`; a 401 clears it and asks again.
- Pointer events work with mouse, trackpad and touch (iPad).

- [ ] **Step 1: Write the page**

`Sources/MicroCAMApp/Streaming/StreamPage.swift`:
```swift
import MicroCAMCore

/// The whole viewer page: no external assets, no build step.
enum StreamPage {
    static func html(mode: StreamMode, embedded: Bool) -> String {
        template
            .replacingOccurrences(of: "__MODE__", with: mode.rawValue)
            .replacingOccurrences(of: "__EMBEDDED__", with: embedded ? "true" : "false")
    }

    private static let template = #"""
<!doctype html>
<html lang="cs">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>microCAM – živě</title>
<style>
:root{--bg:#07080a;--panel:rgba(24,27,33,.78);--line:rgba(255,255,255,.08);--text:#eef0f4;--muted:#9aa3b2;--accent:#ff3b30}
*{box-sizing:border-box}
html,body{margin:0;height:100%;background:var(--bg);color:var(--text);font:15px/1.3 -apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif;overflow:hidden;-webkit-user-select:none;user-select:none}
#stage{position:fixed;inset:0;display:flex;align-items:center;justify-content:center}
#stage img{max-width:100vw;max-height:100vh;display:block}
#ink{position:fixed;touch-action:none;pointer-events:none}
body.drawing #ink{pointer-events:auto;cursor:crosshair}
.bar{position:fixed;left:50%;transform:translateX(-50%);display:flex;align-items:center;gap:6px;padding:6px;border-radius:16px;background:var(--panel);border:1px solid var(--line);-webkit-backdrop-filter:blur(18px);backdrop-filter:blur(18px);box-shadow:0 10px 30px rgba(0,0,0,.35);transition:opacity .35s}
#top{top:14px;padding:8px 14px;font-weight:600;letter-spacing:.2px}
#top small{color:var(--muted);font-weight:500;margin-left:8px}
#bottom{bottom:18px}
button,.btn{appearance:none;border:0;border-radius:11px;padding:9px 13px;background:rgba(255,255,255,.07);color:var(--text);font:inherit;font-weight:560;cursor:pointer;text-decoration:none;display:inline-flex;align-items:center;gap:6px;white-space:nowrap}
button:hover,.btn:hover{background:rgba(255,255,255,.13)}
button:disabled{opacity:.4;cursor:default}
button.on{background:rgba(255,255,255,.22)}
button.primary{background:var(--accent);color:#fff}
.sep{width:1px;height:24px;background:var(--line);margin:0 4px}
.swatch{width:22px;height:22px;padding:0;border-radius:50%;border:2px solid transparent}
.swatch.on{border-color:#fff}
.group{display:flex;gap:6px;align-items:center}
.hidden{display:none!important}
body.idle .bar{opacity:0;pointer-events:none}
body.image-only .bar,body.image-only #ink{display:none!important}
#offline{position:fixed;inset:0;display:flex;align-items:center;justify-content:center;color:var(--muted);font-size:17px;background:rgba(0,0,0,.55)}
#toast{position:fixed;left:50%;bottom:86px;transform:translateX(-50%);padding:9px 14px;border-radius:12px;background:var(--panel);border:1px solid var(--line);opacity:0;transition:opacity .25s;pointer-events:none}
#toast.show{opacity:1}
</style>
</head>
<body>
<div id="stage"><img id="live" alt=""><img id="shot" class="hidden" alt=""></div>
<canvas id="ink"></canvas>
<div id="offline" class="hidden">Připojuji se k mikroskopu…</div>
<div id="top" class="bar"><span id="job">microCAM</span><small id="state">živě</small></div>
<div id="bottom" class="bar">
  <button id="draw" title="Kreslit do obrazu">✏️ Kreslit</button>
  <span id="tools" class="group hidden">
    <button data-tool="arrow" class="on" title="Šipka">➚</button>
    <button data-tool="ellipse" title="Kruh">◯</button>
    <button data-tool="pen" title="Pero">〰︎</button>
    <span class="sep"></span>
    <button class="swatch on" data-color="#ff3b30" style="background:#ff3b30" title="Červená"></button>
    <button class="swatch" data-color="#ffd60a" style="background:#ffd60a" title="Žlutá"></button>
    <button class="swatch" data-color="#30d158" style="background:#30d158" title="Zelená"></button>
    <button class="swatch" data-color="#0a84ff" style="background:#0a84ff" title="Modrá"></button>
    <span class="sep"></span>
    <button id="clear" title="Smazat kresbu">Smazat</button>
  </span>
  <span class="sep"></span>
  <span id="liveTools" class="group"><button id="photo" class="primary" title="Vyfotit na bench Macu">📷 Vyfotit</button></span>
  <span id="shotTools" class="group hidden">
    <button id="save" class="primary">Uložit k zakázce</button>
    <a id="download" class="btn" download>Stáhnout</a>
    <button id="back">Zpět na živý obraz</button>
  </span>
  <button id="fs" title="Celá obrazovka">⛶</button>
</div>
<div id="toast"></div>
<script>
const MODE = "__MODE__", EMBEDDED = __EMBEDDED__;
const $ = id => document.getElementById(id);
const live = $("live"), shot = $("shot"), ink = $("ink"), ctx = ink.getContext("2d");
let tool = "arrow", color = "#ff3b30", drawing = false, shapes = [], current = null, frozen = null, offline = false;

if (MODE === "imageOnly") document.body.classList.add("image-only");
if (EMBEDDED) $("fs").classList.add("hidden");

// ---- live stream with automatic reconnect ----
function startStream() { live.src = "/stream?t=" + Date.now(); }
function stopStream() { live.removeAttribute("src"); }
live.addEventListener("load", () => { setOffline(false); layout(); });
live.addEventListener("error", () => { if (!frozen) { setOffline(true); setTimeout(startStream, 1500); } });
function setOffline(v) { offline = v; $("offline").classList.toggle("hidden", !v); }

async function poll() {
  try {
    const r = await fetch("/status", { cache: "no-store" });
    const s = await r.json();
    $("job").textContent = s.job ? "Zakázka " + s.job : "Bez zakázky";
    $("photo").disabled = !s.photoEnabled;
    $("photo").title = s.photoEnabled ? "Vyfotit na bench Macu" : "Focení je na bench Macu vypnuté (chybí PIN)";
    if (offline && !frozen) startStream();
  } catch (e) { if (!frozen) setOffline(true); }
  setTimeout(poll, 3000);
}

// ---- canvas over the visible image ----
function target() { return frozen ? shot : live; }
function layout() {
  const r = target().getBoundingClientRect(), dpr = window.devicePixelRatio || 1;
  Object.assign(ink.style, { left: r.left + "px", top: r.top + "px", width: r.width + "px", height: r.height + "px" });
  ink.width = Math.max(1, Math.round(r.width * dpr));
  ink.height = Math.max(1, Math.round(r.height * dpr));
  redraw();
}
window.addEventListener("resize", layout);
shot.addEventListener("load", layout);

function norm(e) {
  const r = ink.getBoundingClientRect();
  return { x: Math.min(Math.max((e.clientX - r.left) / r.width, 0), 1),
           y: Math.min(Math.max((e.clientY - r.top) / r.height, 0), 1) };
}
ink.addEventListener("pointerdown", e => {
  if (!drawing) return;
  ink.setPointerCapture(e.pointerId);
  const p = norm(e);
  current = { kind: tool, points: tool === "pen" ? [p] : [p, p], color, width: 0.006 };
});
ink.addEventListener("pointermove", e => {
  if (!current) return;
  const p = norm(e);
  if (current.kind === "pen") current.points.push(p); else current.points[1] = p;
  redraw();
});
function finish() {
  if (!current) return;
  const [a, b] = [current.points[0], current.points[current.points.length - 1]];
  if (current.points.length > 1 && (Math.abs(a.x - b.x) + Math.abs(a.y - b.y) > 0.005 || current.kind === "pen")) shapes.push(current);
  current = null; redraw();
}
ink.addEventListener("pointerup", finish);
ink.addEventListener("pointercancel", finish);

function redraw() {
  ctx.clearRect(0, 0, ink.width, ink.height);
  for (const s of current ? [...shapes, current] : shapes) drawShape(s, ink.width, ink.height);
}
function drawShape(s, W, H) {
  const P = s.points.map(p => [p.x * W, p.y * H]);
  ctx.strokeStyle = s.color; ctx.lineWidth = Math.max(2, s.width * W); ctx.lineCap = "round"; ctx.lineJoin = "round";
  ctx.beginPath();
  if (s.kind === "pen") {
    P.forEach(([x, y], i) => i ? ctx.lineTo(x, y) : ctx.moveTo(x, y));
  } else {
    const a = P[0], b = P[P.length - 1];
    if (s.kind === "ellipse") {
      ctx.ellipse((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, Math.abs(b[0] - a[0]) / 2, Math.abs(b[1] - a[1]) / 2, 0, 0, Math.PI * 2);
    } else {
      ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]);
      const ang = Math.atan2(b[1] - a[1], b[0] - a[0]), h = Math.max(s.width * W * 4, 12);
      for (const side of [Math.PI * 0.85, -Math.PI * 0.85]) {
        ctx.moveTo(b[0], b[1]); ctx.lineTo(b[0] + h * Math.cos(ang + side), b[1] + h * Math.sin(ang + side));
      }
    }
  }
  ctx.stroke();
}

// ---- toolbar ----
function setDrawing(v) {
  drawing = v;
  document.body.classList.toggle("drawing", v);
  $("draw").classList.toggle("on", v);
  $("tools").classList.toggle("hidden", !v);
}
$("draw").onclick = () => setDrawing(!drawing);
$("clear").onclick = () => { shapes = []; redraw(); };
document.querySelectorAll("[data-tool]").forEach(b => b.onclick = () => {
  tool = b.dataset.tool;
  document.querySelectorAll("[data-tool]").forEach(x => x.classList.toggle("on", x === b));
});
document.querySelectorAll("[data-color]").forEach(b => b.onclick = () => {
  color = b.dataset.color;
  document.querySelectorAll("[data-color]").forEach(x => x.classList.toggle("on", x === b));
});
$("fs").onclick = () => {
  const el = document.documentElement;
  if (document.fullscreenElement || document.webkitFullscreenElement) (document.exitFullscreen || document.webkitExitFullscreen).call(document);
  else (el.requestFullscreen || el.webkitRequestFullscreen).call(el);
};

// ---- photo, annotated copy ----
function toast(text) {
  const t = $("toast"); t.textContent = text; t.classList.add("show");
  clearTimeout(toast.timer); toast.timer = setTimeout(() => t.classList.remove("show"), 2600);
}
function pin() {
  let p = localStorage.getItem("microcamPin");
  if (!p) { p = prompt("PIN pro focení (nastavený na bench Macu)"); if (p) localStorage.setItem("microcamPin", p.trim()); }
  return p && p.trim();
}
async function post(path, body) {
  const p = pin(); if (!p) return null;
  let r;
  try {
    r = await fetch(path, { method: "POST", headers: { "X-MicroCAM-PIN": p, "Content-Type": "application/json" },
                            body: JSON.stringify(body || {}) });
  } catch (e) { toast("bench Mac není dostupný"); return null; }
  if (r.status === 401) { localStorage.removeItem("microcamPin"); toast("Špatný PIN"); return null; }
  if (r.status === 429) { const j = await r.json(); toast("Příliš mnoho pokusů – zkus to za " + j.retryAfter + " s"); return null; }
  if (r.status === 403) { toast("Tahle akce je na bench Macu vypnutá"); return null; }
  if (!r.ok) { toast("Chyba " + r.status); return null; }
  return r.json();
}
function setDownload(ref) { $("download").href = ref.url; $("download").download = ref.name; }
$("photo").onclick = async () => {
  $("photo").disabled = true;
  const ref = await post("/photo");
  $("photo").disabled = false;
  if (!ref) return;
  frozen = ref; shapes = [];
  shot.src = ref.url + "?t=" + Date.now();
  shot.classList.remove("hidden"); live.classList.add("hidden"); stopStream();
  $("liveTools").classList.add("hidden"); $("shotTools").classList.remove("hidden");
  $("state").textContent = "fotka " + ref.name;
  setDownload(ref); setDrawing(true);
  toast("Uloženo k zakázce: " + ref.name);
};
$("save").onclick = async () => {
  if (!shapes.length) { toast("Nejdřív něco nakresli"); return; }
  const ref = await post("/annotated", { source: frozen.name, shapes });
  if (!ref) return;
  setDownload(ref);
  toast("Uloženo s anotací: " + ref.name);
};
$("back").onclick = () => {
  frozen = null; shapes = []; redraw();
  shot.classList.add("hidden"); live.classList.remove("hidden");
  $("shotTools").classList.add("hidden"); $("liveTools").classList.remove("hidden");
  $("state").textContent = "živě"; setDrawing(false); startStream();
};

// ---- hide bars when idle ----
let idleTimer;
function wake() {
  document.body.classList.remove("idle");
  clearTimeout(idleTimer);
  idleTimer = setTimeout(() => { if (!drawing && !frozen) document.body.classList.add("idle"); }, 3000);
}
["pointermove", "pointerdown", "keydown"].forEach(ev => window.addEventListener(ev, wake));

startStream(); poll(); wake();
</script>
</body>
</html>
"""#
}
```

- [ ] **Step 2: Build and check in browsers**

Run: `swift build && scripts/make-app.sh`, deploy to a Mac with a camera, enable Přenos with PIN, and verify in Safari (Mac) and Safari (iPad or phone in the tailnet):
1. *S ovládáním:* live image fills the window, job pill shows the active job, the bars fade after 3 s and return on mouse move or touch.
2. Kreslit → arrow, circle and pen in all four colors; Smazat clears them. Nothing is saved.
3. Vyfotit → PIN prompt → frozen photo; the bench shows "Vyfoceno z recepce: …" and the file is in the job folder. Draw, then Uložit k zakázce → `…_2.jpg` exists next to the original, with the drawing in the same place. Stáhnout downloads the latest version. Zpět na živý obraz resumes the live image.
4. Wrong PIN → "Špatný PIN" and a new prompt next time; 5× wrong → the lock message.
5. Switch the bench to *Jen obraz* and reload → only the image; `curl -X POST …/photo -H 'X-MicroCAM-PIN: <pin>'` → 403.
6. Quit microCAM on the bench → the page shows "Připojuji se k mikroskopu…"; relaunch → the image returns without reloading the page.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat(app): add stream page with drawing, remote photo and annotated copies"
```
Check Roborev.

### Task 8: Viewer mode (Prohlížeč)

**Files:**
- Create: `Sources/MicroCAMApp/Viewer/ViewerModel.swift`, `Sources/MicroCAMApp/Viewer/ViewerView.swift`
- Modify: `Sources/MicroCAMApp/AppModel.swift`, `Sources/MicroCAMApp/Views/ContentView.swift`, `Sources/MicroCAMApp/Views/SettingsView.swift`, `Sources/MicroCAMApp/MicroCAMApp.swift`

**Interfaces:**
- Consumes: `AppSettings.appMode`, `viewerSourceName`, `viewerManualURL` (Task 4); `StreamServer.serviceType` (Task 6); the page with `?embedded=1` (Task 7).
- Produces:
  - `@MainActor final class ViewerModel: ObservableObject { struct Source: Identifiable, Hashable { name: String; endpoint: NWEndpoint }; @Published private(set) var sources: [Source]; @Published private(set) var url: URL?; @Published private(set) var status: String; init(settings: @escaping () -> AppSettings, update: @escaping ((inout AppSettings) -> Void) -> Void); func start(); func connect(_ source: Source); func connect(manual: String) -> Bool; func disconnect() }`
  - `AppModel`: `let launchMode: AppMode` (fixed at launch), `lazy var viewer: ViewerModel`, `func relaunch()`, `func showFullScreen(on screen: NSScreen)`.

Mode switching is applied by restarting the app, so a single process never runs the camera and the viewer at once.

- [ ] **Step 1: ViewerModel**

`Sources/MicroCAMApp/Viewer/ViewerModel.swift`:
```swift
import Foundation
import MicroCAMCore
import Network

/// Finds microCAM hosts via Bonjour, resolves one to an IPv4 URL and keeps
/// the chosen source for the next launch. Tailscale does not carry Bonjour,
/// so a manual URL is the fallback.
@MainActor
final class ViewerModel: ObservableObject {
    struct Source: Identifiable, Hashable {
        let name: String
        let endpoint: NWEndpoint
        var id: String { name }
    }

    @Published private(set) var sources: [Source] = []
    @Published private(set) var url: URL?
    @Published private(set) var status = "Hledám mikroskop v síti…"

    private let settings: () -> AppSettings
    private let update: ((inout AppSettings) -> Void) -> Void
    private var browser: NWBrowser?
    private var resolving: NWConnection?

    init(settings: @escaping () -> AppSettings, update: @escaping ((inout AppSettings) -> Void) -> Void) {
        self.settings = settings
        self.update = update
    }

    func start() {
        if let manual = settings().viewerManualURL, connect(manual: manual) { /* remembered manual URL */ }
        let browser = NWBrowser(for: .bonjour(type: StreamServer.serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sources = results.compactMap { result in
                    if case .service(let name, _, _, _) = result.endpoint { return Source(name: name, endpoint: result.endpoint) }
                    return nil
                }.sorted { $0.name < $1.name }
                self.autoConnect()
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private func autoConnect() {
        guard url == nil, resolving == nil else { return }
        if let name = settings().viewerSourceName, let source = sources.first(where: { $0.name == name }) {
            connect(source)
        } else if settings().viewerSourceName == nil, sources.count == 1 {
            connect(sources[0])
        } else if sources.isEmpty {
            status = "Hledám mikroskop v síti…"
        } else {
            status = "Vyber mikroskop"
        }
    }

    func connect(_ source: Source) {
        resolving?.cancel()
        status = "Připojuji k \(source.name)…"
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let connection = NWConnection(to: source.endpoint, using: parameters)
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch state {
                case .ready:
                    if case .hostPort(let host, let port)? = connection.currentPath?.remoteEndpoint,
                       case .ipv4(let address) = host {
                        self.url = URL(string: "http://\(address):\(port.rawValue)/?embedded=1")
                        self.status = source.name
                        self.update { $0.viewerSourceName = source.name; $0.viewerManualURL = nil }
                    }
                    connection.cancel()
                    self.resolving = nil
                case .failed, .waiting:
                    self.status = "\(source.name) není dostupný, zkouším znovu…"
                    connection.cancel()
                    self.resolving = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.autoConnect() }
                default:
                    break
                }
            }
        }
        resolving = connection
        connection.start(queue: .main)
    }

    /// `host:port`, `http://host:port` or a full URL. Returns false if unusable.
    @discardableResult
    func connect(manual: String) -> Bool {
        var text = manual.trimmingCharacters(in: .whitespaces)
        if !text.contains("://") { text = "http://" + text }
        guard var components = URLComponents(string: text), components.host != nil,
              ["http", "https"].contains(components.scheme ?? "") else { return false }
        if components.port == nil { components.port = 8090 }
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "embedded", value: "1")]
        guard let url = components.url else { return false }
        self.url = url
        status = components.host ?? ""
        update { $0.viewerManualURL = manual; $0.viewerSourceName = nil }
        return true
    }

    func disconnect() {
        url = nil
        update { $0.viewerSourceName = nil; $0.viewerManualURL = nil }
        autoConnect()
    }
}
```

- [ ] **Step 2: ViewerView**

`Sources/MicroCAMApp/Viewer/ViewerView.swift`:
```swift
import SwiftUI
import WebKit

struct ViewerView: View {
    @ObservedObject var viewer: ViewerModel
    @State private var manual = ""
    @State private var manualInvalid = false

    var body: some View {
        ZStack {
            Color.black
            if let url = viewer.url {
                StreamWebView(url: url)
            } else {
                VStack(spacing: 14) {
                    Text(viewer.status).font(.title3)
                    ForEach(viewer.sources) { source in
                        Button("Připojit k \(source.name)") { viewer.connect(source) }
                    }
                    HStack {
                        TextField("nebo adresa, např. 100.64.0.1:8090", text: $manual)
                            .textFieldStyle(.roundedBorder).frame(width: 300)
                            .onSubmit { manualInvalid = !viewer.connect(manual: manual) }
                        Button("Připojit") { manualInvalid = !viewer.connect(manual: manual) }
                    }
                    if manualInvalid { Text("Neplatná adresa").font(.caption).foregroundStyle(.red) }
                }
                .padding(28)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .toolbar {
            if viewer.url != nil {
                ToolbarItem {
                    Menu(viewer.status) {
                        ForEach(viewer.sources) { source in Button(source.name) { viewer.connect(source) } }
                        Divider()
                        Button("Odpojit a vybrat jiný") { viewer.disconnect() }
                    }
                }
            }
        }
    }
}

/// The stream page in WebKit. The page reconnects the stream by itself; this
/// only retries when the page itself cannot be loaded.
struct StreamWebView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()   // keeps the PIN in localStorage between launches
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        if view.url?.host != url.host || view.url?.port != url.port { view.load(URLRequest(url: url)) }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { retry(webView) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { retry(webView) }
        private func retry(_ webView: WKWebView) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { webView.reload() }
        }
    }
}
```
If `reload()` does nothing after a failed first load, use `webView.load(URLRequest(url: url))` with the URL stored in the coordinator.

- [ ] **Step 3: AppModel, ContentView, Settings, menu**

In `AppModel`:
```swift
    let launchMode: AppMode
    lazy var viewer = ViewerModel(settings: { [unowned self] in self.settings },
                                  update: { [unowned self] body in body(&self.settings) })

    /// Mode changes take effect on a fresh process.
    func relaunch() {
        flushSettings()
        let path = Bundle.main.bundlePath
        Process.launchedProcess(launchPath: "/bin/sh", arguments: ["-c", "sleep 1; /usr/bin/open -n \"\(path)\""])
        NSApp.terminate(nil)
    }

    func showFullScreen(on screen: NSScreen) {
        guard let window = mainWindow else { return }
        if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        window.setFrame(screen.visibleFrame, display: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { window.toggleFullScreen(nil) }
    }
```
In `init()`, right after `settings = store.load()`: `launchMode = settings.appMode`. Guard the camera: at the top of `start()` add `guard launchMode == .camera else { return }`; set `showFirstRun = settings.storageRoot == nil && launchMode == .camera`; in `handle(_:)` return early when `launchMode == .viewer`. At the end of `init()`: `if launchMode == .viewer { viewer.start() }` (instead of `Task { await start() }` in that case).

In `ContentView.body`, wrap the existing content:
```swift
    var body: some View {
        if model.launchMode == .viewer {
            ViewerView(viewer: model.viewer)
                .background(WindowAccessor { model.attachMainWindow($0) })
        } else {
            cameraBody   // the existing VStack with toolbar and sheets, moved into a computed property
        }
    }
```

In `SettingsView`, add a mode picker as the first tab, shown in both modes:
```swift
struct ModeSettingsTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Picker("Režim appky", selection: $model.settings.appMode) {
                Text("Kamera – mikroskop je připojený k tomuto Macu").tag(AppMode.camera)
                Text("Prohlížeč – zobrazuje přenos z jiného Macu").tag(AppMode.viewer)
            }
            .pickerStyle(.radioGroup)
            if model.settings.appMode != model.launchMode {
                HStack {
                    Text("Změna se projeví po restartu.").foregroundStyle(.secondary)
                    Button("Restartovat") { model.relaunch() }
                }
            }
        }
    }
}
```
and in `SettingsView.body` show only `ModeSettingsTab` (tag `"mode"`) when `model.launchMode == .viewer`; in camera mode put it first before "Zařízení".

In `MicroCAMApp` commands, add:
```swift
            CommandMenu("Zobrazení") {
                ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { _, screen in
                    Button("Na celou obrazovku: \(screen.localizedName)") { model.showFullScreen(on: screen) }
                }
            }
```

- [ ] **Step 4: Build and verify**

Run: `swift build && swift test && scripts/make-app.sh`. On test-mac (camera mode, Přenos on) and this dev Mac (switch to Prohlížeč → Restartovat):
1. The viewer lists the test-mac name within a few seconds and connects automatically when it is the only source; the live page appears without the full-screen button.
2. Quit and relaunch the viewer → it reconnects to the same source without asking.
3. Quit microCAM on the host → the page shows "Připojuji se…"; restart it → the image returns.
4. Manual URL `100.x.y.z:8090` works where Bonjour does not.
5. "Zobrazení → Na celou obrazovku: <display>" moves the viewer to that display in full screen.
6. Switch back to Kamera → Restartovat → the normal camera window returns.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(app): add viewer mode that finds and shows another microCAM's stream"
```
Check Roborev.

### Task 9: Universal build, deploy, smoke test, docs and acceptance

**Files:**
- Modify: `scripts/make-app.sh`, `scripts/deploy-bench.sh`, `README.md`, `docs/acceptance.md`
- Create: `scripts/deploy.sh`, `scripts/stream-smoke.sh`

- [ ] **Step 1: Universal build**

In `scripts/make-app.sh` replace the two build lines:
```bash
# Universal: bench Mac and test-mac are Apple Silicon, reception-mac is Intel.
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/MicroCAMApp"
```
Verify: `lipo -archs build/microCAM.app/Contents/MacOS/MicroCAMApp` → `x86_64 arm64`.

- [ ] **Step 2: Generic deploy**

`scripts/deploy.sh`:
```bash
#!/usr/bin/env bash
# Copy build/microCAM.app to <host>:<dir> (default ~/Applications), quitting a
# running copy first and re-registering it so Info.plist changes apply.
# Usage: scripts/deploy.sh <ssh-host> [/Applications]
set -euo pipefail
cd "$(dirname "$0")/.."
HOST="${1:?usage: scripts/deploy.sh <ssh-host> [dir]}"
DIR="${2:-Applications}"
test -d build/microCAM.app || { echo "run scripts/make-app.sh first" >&2; exit 1; }
ssh "$HOST" 'osascript -e "tell application \"microCAM\" to quit" >/dev/null 2>&1 || true; sleep 1'
ssh "$HOST" "mkdir -p \"$DIR\""
rsync -a --delete build/microCAM.app "$HOST:$DIR/"
ssh "$HOST" "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f \"$DIR/microCAM.app\""
echo "Deployed to $HOST:$DIR/microCAM.app — launch: ssh $HOST 'open \"$DIR/microCAM.app\"'"
```
Replace the body of `scripts/deploy-bench.sh` with `exec "$(dirname "$0")/deploy.sh" bench-mac /Applications`. `chmod +x scripts/deploy.sh`.

- [ ] **Step 3: Smoke test script**

`scripts/stream-smoke.sh`:
```bash
#!/usr/bin/env bash
# End-to-end check of a running stream. Usage: scripts/stream-smoke.sh <host> [port] [pin]
# With a PIN it also takes one real photo on the host.
set -uo pipefail
HOST="${1:?usage: scripts/stream-smoke.sh <host> [port] [pin]}"; PORT="${2:-8090}"; PIN="${3:-}"
BASE="http://$HOST:$PORT"
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (expected $3, got $2)"; fail=1; fi; }

check "status 200" "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/status")" 200
frames=$(curl -s --max-time 3 "$BASE/stream" | grep -ac "Content-Type: image/jpeg")
[ "$frames" -ge 10 ] && echo "ok   stream ($frames frames in 3 s)" || { echo "FAIL stream ($frames frames in 3 s)"; fail=1; }
check "photo without PIN" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/photo")" 401
check "photo cross-origin" "$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'X-MicroCAM-PIN: 0' -H 'Origin: https://evil.example' "$BASE/photo")" 403
check "GET photo" "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/photo")" 405
check "traversal" "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/captures/..%2F..%2Fetc%2Fpasswd")" 404
check "OPTIONS" "$(curl -s -o /dev/null -w '%{http_code}' -X OPTIONS "$BASE/photo")" 405
if [ -n "$PIN" ]; then
    body=$(curl -s -X POST -H "X-MicroCAM-PIN: $PIN" -H 'Content-Type: application/json' -d '{}' "$BASE/photo")
    echo "$body" | grep -q '"name"' && echo "ok   remote photo: $body" || { echo "FAIL remote photo: $body"; fail=1; }
fi
exit $fail
```
(The wrong-PIN checks count towards the lockout; the script uses at most 2 wrong attempts.)

- [ ] **Step 4: Docs**

README — add after "Integrations":
```markdown
## Live stream and viewer

Settings → Přenos: stream the live image to other devices on the shop
network or tailnet (off by default). Open `http://<bench-ip>:8090/` in any
browser, or run microCAM in **Prohlížeč** mode on another Mac (Settings →
Režim appky) — it finds the bench via Bonjour.

- *Jen obraz* — just the picture (for a customer-facing screen).
- *S ovládáním* — job, full screen, drawing over the live image, and
  **Vyfotit**: the photo is taken on the bench into the active job; draw on
  it and **Uložit k zakázce** saves an annotated copy (`…_2.jpg`), the
  original stays untouched. Remote photos need the PIN set on the bench.

Only local-network and Tailscale clients are accepted. Nothing listens while
the toggle is off, and nothing is encoded while nobody watches.
`scripts/stream-smoke.sh <host> [port] [pin]` checks a running stream.
```
`docs/acceptance.md` — append rows:
```markdown
| 13 | Stream on, no viewer | CPU same as #2 | | |
| 14 | Stream, 1 viewer in Safari (reception-mac) | + a few % CPU on bench, smooth image | | |
| 15 | Viewer mode on reception-mac (Intel) | auto-connects, CPU on recepce noted | | |
| 16 | Remote photo + annotated copy | files in job folder, original untouched | | |
| 17 | `stream-smoke.sh bench-mac 8090` | all ok | | |
| 18 | Slow viewer (iPhone on weak Wi-Fi) + second viewer | second viewer and bench preview stay smooth | | |
```

- [ ] **Step 5: Commit, push, PR**

```bash
git add -A && git commit -m "build: universal app, generic deploy and stream smoke test; document streaming"
git push -u origin streaming
gh pr create --base integrations --head streaming --title "feat: live stream, remote photo with annotations and viewer mode" \
  --body "Implements docs/superpowers/plans/2026-09-30-microcam-streaming.md. bench Mac/reception-mac acceptance rows 13–18 pending."
```
Check Roborev (per commit, then one whole-branch review before merge).
