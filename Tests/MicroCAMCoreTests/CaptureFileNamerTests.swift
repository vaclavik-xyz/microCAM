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

    func testEditedCopyTakesNextIndexOfTheSameTimestamp() {
        let existing: Set<String> = ["PR-1_2026-09-21_14-13-20.jpg", "PR-1_2026-09-21_14-13-20_2.jpg"]
        let namer = CaptureFileNamer(fileExists: { existing.contains($0.lastPathComponent) })
        let source = folder.appendingPathComponent("PR-1_2026-09-21_14-13-20.jpg")
        let copy = namer.editedCopyURL(of: source)
        XCTAssertEqual(copy.lastPathComponent, "PR-1_2026-09-21_14-13-20_3.jpg")
        XCTAssertEqual(copy.deletingLastPathComponent().path, folder.path)
        // A copy of a copy lands in the same series, not "…_2_2".
        XCTAssertEqual(namer.editedCopyURL(of: folder.appendingPathComponent("PR-1_2026-09-21_14-13-20_2.jpg")).lastPathComponent,
                       "PR-1_2026-09-21_14-13-20_3.jpg")
    }
    func testEditedCopyIsAlwaysJPEG() {
        let namer = CaptureFileNamer(fileExists: { $0.lastPathComponent == "PR-1_2026-09-21_14-13-20.JPG" })
        XCTAssertEqual(namer.editedCopyURL(of: folder.appendingPathComponent("PR-1_2026-09-21_14-13-20.JPG")).lastPathComponent,
                       "PR-1_2026-09-21_14-13-20.jpg")
    }
    func testEditedCopyOfAFileWithAnotherName() {
        let existing: Set<String> = ["board.jpeg", "board_2.jpg"]
        let namer = CaptureFileNamer(fileExists: { existing.contains($0.lastPathComponent) })
        XCTAssertEqual(namer.editedCopyURL(of: folder.appendingPathComponent("board.jpeg")).lastPathComponent, "board_3.jpg")
    }
}
