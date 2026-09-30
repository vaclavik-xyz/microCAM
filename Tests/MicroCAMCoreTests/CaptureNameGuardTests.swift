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
    /// A name whose encoded and decoded forms differ exercises the decode path.
    func testPercentEncodedValidNameResolves() {
        let tmp = TempDir()
        tmp.touch("PR-1/PR-1_2026-09-21_10-00-00_2.jpg")
        XCTAssertNotNil(CaptureNameGuard.resolve("PR%2D1_2026-09-21_10-00-00%5F2.jpg",
                                                 in: [tmp.url.appendingPathComponent("PR-1")]))
    }
}
