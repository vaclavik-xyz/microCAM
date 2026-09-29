import XCTest
@testable import MicroCAMCore

final class CaptureFileNameTests: XCTestCase {
    let utc = TimeZone(identifier: "UTC")!

    func testTimestampFormat() {
        let date = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21 14:13:20 UTC
        XCTAssertEqual(CaptureFileName.timestampString(date, timeZone: utc), "2026-09-21_14-13-20")
    }
    func testFileNameWithAndWithoutIndex() {
        XCTAssertEqual(CaptureFileName(prefix: "PR-1", timestamp: "2026-09-21_14-13-20", index: nil, ext: "jpg").fileName,
                       "PR-1_2026-09-21_14-13-20.jpg")
        XCTAssertEqual(CaptureFileName(prefix: "PR-1", timestamp: "2026-09-21_14-13-20", index: 2, ext: "mov").fileName,
                       "PR-1_2026-09-21_14-13-20_2.mov")
    }
    func testParseRoundTrip() {
        for name in ["PR-260042_2026-09-21_14-13-20.jpg",
                     "bez-zakazky_2026-09-21_14-13-20_3.mov",
                     "microcam_2026-01-01_00-00-00.jpg"] {
            XCTAssertEqual(CaptureFileName.parse(name)?.fileName, name)
        }
        let parsed = CaptureFileName.parse("PR-1_2026-09-21_14-13-20_3.mov")
        XCTAssertEqual(parsed?.prefix, "PR-1")
        XCTAssertEqual(parsed?.index, 3)
        XCTAssertEqual(parsed?.ext, "mov")
    }
    func testParseRejectsForeignNames() {
        for name in ["IMG_0001.jpg", "Single Shots", "PR-1_2026-09-21.jpg", ".DS_Store", "PR-1_2026-09-21_14-13-20"] {
            XCTAssertNil(CaptureFileName.parse(name), name)
        }
    }
    func testKindExtensionsAndFolders() {
        XCTAssertEqual(CaptureKind.photo.fileExtension, "jpg")
        XCTAssertEqual(CaptureKind.timelapse.fileExtension, "jpg")
        XCTAssertEqual(CaptureKind.video.fileExtension, "mov")
        XCTAssertEqual(CaptureKind.photo.typeFolderName, "Fotky")
        XCTAssertEqual(CaptureKind.video.typeFolderName, "Videa")
        XCTAssertEqual(CaptureKind.timelapse.typeFolderName, "Časosběr")
        XCTAssertEqual(CaptureKind.fromTypeFolder("Časosběr"), .timelapse)
        XCTAssertNil(CaptureKind.fromTypeFolder("PR-1"))
    }
}
