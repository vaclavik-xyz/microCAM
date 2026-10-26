import XCTest
@testable import MicroCAMCore

final class StreamGalleryTests: XCTestCase {
    func testFolderQuery() {
        XCTAssertEqual(GalleryFolder(query: nil), .current)
        XCTAssertEqual(GalleryFolder(query: ""), .current)
        XCTAssertEqual(GalleryFolder(query: "_unassigned"), .unassigned)
        XCTAssertEqual(GalleryFolder(query: "PR-260412"), .job(JobCode("PR-260412")!))
        // Only a code exactly as microCAM writes it: no other spelling, no path.
        for bad in ["pr-1", " PR-1", "PR-1/..", "..", "_Unsorted", "Nezařazené", "-1"] {
            XCTAssertNil(GalleryFolder(query: bad), bad)
        }
        for folder in [GalleryFolder.current, .unassigned, .job(JobCode("PR-1")!)] {
            XCTAssertEqual(GalleryFolder(query: folder.token), folder)
        }
    }

    func testListingKeepsTheNewestPhotosUpToTheLimit() {
        let tmp = TempDir()
        for minute in 0..<5 { tmp.touch("_Unsorted/no-job_2026-09-21_10-0\(minute)-00.jpg") }
        let storage = StreamStorage(layout: StorageLayout(root: tmp.url, language: .english), context: .unassigned)
        let listing = StreamGallery.listing(.current, storage: storage, limit: 3)
        XCTAssertEqual(listing?.days.flatMap(\.photos).map(\.name),
                       ["no-job_2026-09-21_10-04-00.jpg", "no-job_2026-09-21_10-03-00.jpg", "no-job_2026-09-21_10-02-00.jpg"])
        XCTAssertEqual(listing?.more, true)
        XCTAssertNil(listing?.job)
        XCTAssertEqual(StreamGallery.listing(.current, storage: storage, limit: 5)?.more, false)
    }

    /// Like the side panel: Czech folder names and type folders are listed too.
    func testListingCoversEveryLanguageAndTypeFolder() {
        let tmp = TempDir()
        tmp.touch("_Nezařazeno/bez-zakazky_2026-09-21_10-00-00.jpg")
        tmp.touch("_Unsorted/Photos/no-job_2026-09-22_10-00-00.jpg")
        let storage = StreamStorage(layout: StorageLayout(root: tmp.url, sortByType: true, language: .english), context: .job(JobCode("PR-1")!))
        let names = StreamGallery.listing(.unassigned, storage: storage)?.days.flatMap(\.photos).map(\.name)
        XCTAssertEqual(names, ["no-job_2026-09-22_10-00-00.jpg", "bez-zakazky_2026-09-21_10-00-00.jpg"])
    }
}
