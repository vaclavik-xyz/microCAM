import XCTest
@testable import MicroCAMCore

final class CaptureFileNamerTests: XCTestCase {
    let utc = TimeZone(identifier: "UTC")!
    let date = Date(timeIntervalSince1970: 1_790_000_000)
    let folder = URL(fileURLWithPath: "/tmp/root/PR-1", isDirectory: true)

    func testFirstName() {
        let namer = CaptureFileNamer(fileExists: { _ in false })
        let url = namer.nextURL(in: folder, prefix: "PR-1", kind: .photo, date: date, timeZone: utc)
        XCTAssertEqual(url.lastPathComponent, "PR-1_2026-09-21_14-13-20.jpg")
        XCTAssertEqual(url.deletingLastPathComponent().path, folder.path)
    }
    func testCollisionAddsSuffix() {
        let existing: Set<String> = ["PR-1_2026-09-21_14-13-20.jpg", "PR-1_2026-09-21_14-13-20_2.jpg"]
        let namer = CaptureFileNamer(fileExists: { existing.contains($0.lastPathComponent) })
        let url = namer.nextURL(in: folder, prefix: "PR-1", kind: .timelapse, date: date, timeZone: utc)
        XCTAssertEqual(url.lastPathComponent, "PR-1_2026-09-21_14-13-20_3.jpg")
    }
    func testVideoAndPrefixes() {
        let namer = CaptureFileNamer(fileExists: { _ in false })
        XCTAssertEqual(namer.nextURL(in: folder, prefix: "bez-zakazky", kind: .video, date: date, timeZone: utc).lastPathComponent,
                       "bez-zakazky_2026-09-21_14-13-20.mov")
        XCTAssertEqual(namer.nextURL(in: folder, prefix: "microcam", kind: .photo, date: date, timeZone: utc).lastPathComponent,
                       "microcam_2026-09-21_14-13-20.jpg")
    }
}
