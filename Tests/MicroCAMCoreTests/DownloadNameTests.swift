import XCTest
@testable import MicroCAMCore

final class DownloadNameTests: XCTestCase {
    let folder = URL(fileURLWithPath: "/Users/x/Downloads", isDirectory: true)

    func testKeepsTheNameAndNeverOverwrites() {
        var taken: Set<String> = []
        let next = { DownloadName.freeURL(for: "PR-1_2026-09-21_10-00-00.jpg", in: self.folder) { taken.contains($0.lastPathComponent) } }
        XCTAssertEqual(next()?.lastPathComponent, "PR-1_2026-09-21_10-00-00.jpg")
        taken.insert("PR-1_2026-09-21_10-00-00.jpg")
        XCTAssertEqual(next()?.lastPathComponent, "PR-1_2026-09-21_10-00-00 2.jpg")
        taken.insert("PR-1_2026-09-21_10-00-00 2.jpg")
        XCTAssertEqual(next()?.lastPathComponent, "PR-1_2026-09-21_10-00-00 3.jpg")
        XCTAssertEqual(next()?.deletingLastPathComponent().path, folder.path)
    }

    /// The name comes from the camera Mac's page: only a file name, never a path.
    func testRefusesPathsAndHiddenNames() {
        XCTAssertEqual(DownloadName.freeURL(for: "../../etc/x.jpg", in: folder) { _ in false }?.path, "/Users/x/Downloads/x.jpg")
        for bad in ["", ".", "..", ".hidden.jpg", "../"] {
            XCTAssertNil(DownloadName.freeURL(for: bad, in: folder) { _ in false }, bad)
        }
    }
}
