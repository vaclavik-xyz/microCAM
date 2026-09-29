import XCTest
@testable import MicroCAMCore

final class CaptureLibraryTests: XCTestCase {
    func testListsCapturesNewestFirstAndSkipsOthers() {
        let tmp = TempDir()
        tmp.touch("PR-1_2026-09-21_10-00-00.jpg")
        tmp.touch("PR-1_2026-09-21_12-00-00.mov")
        tmp.touch("PR-1_2026-09-21_12-00-00_2.jpg")
        tmp.touch("notes.txt")
        tmp.touch("IMG_0001.jpg")
        tmp.touch("PR-2/PR-2_2026-09-21_13-00-00.jpg") // subfolder: not listed
        let names = CaptureLibrary.captureFiles(in: [tmp.url]).map(\.lastPathComponent)
        XCTAssertEqual(names, ["PR-1_2026-09-21_12-00-00_2.jpg",
                               "PR-1_2026-09-21_12-00-00.mov",
                               "PR-1_2026-09-21_10-00-00.jpg"])
    }
    func testMergesTypeFolders() {
        let tmp = TempDir()
        tmp.touch("Fotky/PR-1_2026-09-21_10-00-00.jpg")
        tmp.touch("Videa/PR-1_2026-09-21_11-00-00.mov")
        let folders = ["Fotky", "Videa", "Časosběr"].map { tmp.url.appendingPathComponent($0) }
        XCTAssertEqual(CaptureLibrary.captureFiles(in: folders).map(\.lastPathComponent),
                       ["PR-1_2026-09-21_11-00-00.mov", "PR-1_2026-09-21_10-00-00.jpg"])
    }
    func testMissingFolderIsEmpty() {
        XCTAssertEqual(CaptureLibrary.captureFiles(in: [URL(fileURLWithPath: "/nonexistent/microcam")]), [])
    }
}
