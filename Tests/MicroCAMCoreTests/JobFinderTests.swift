import XCTest
@testable import MicroCAMCore

final class JobFinderTests: XCTestCase {
    func testListsJobFoldersNewestFirstWithCounts() {
        let dir = TempDir()
        dir.touch("PR-1/PR-1_2026-09-01_10-00-00.jpg")
        dir.touch("PR-2/PR-2_2026-09-20_10-00-00.jpg")
        dir.touch("PR-2/PR-2_2026-09-21_08-00-00.mov")
        dir.touch("PR-3/notes.txt")                      // no captures: still a job
        dir.touch("_Unsorted/x_2026-09-30_10-00-00.jpg") // not a job
        dir.touch("lower-case/a.jpg")                    // not how microCAM names a job folder
        dir.touch("PR-4.jpg")                            // a file, not a folder
        let layout = StorageLayout(root: dir.url, language: .english)
        let jobs = JobFinder.jobs(in: layout)
        XCTAssertEqual(jobs.map(\.code.value), ["PR-2", "PR-1", "PR-3"])
        XCTAssertEqual(jobs.map(\.files), [2, 1, 0])
        XCTAssertEqual(jobs.map(\.lastDay), ["2026-09-21", "2026-09-01", nil])
    }

    /// With captures sorted by type, they sit one level deeper.
    func testCountsTypeFolders() {
        let dir = TempDir()
        dir.touch("PR-1/Photos/PR-1_2026-09-01_10-00-00.jpg")
        dir.touch("PR-1/Videos/PR-1_2026-09-02_10-00-00.mov")
        let jobs = JobFinder.jobs(in: StorageLayout(root: dir.url, sortByType: true, language: .english))
        XCTAssertEqual(jobs.first?.files, 2)
        XCTAssertEqual(jobs.first?.lastDay, "2026-09-02")
    }

    func testFilterIgnoresCaseAndKeepsOrder() {
        let jobs = ["PR-260412", "XY-1", "PR-260042"].map { JobSummary(code: JobCode($0)!, files: 0, lastDay: nil) }
        XCTAssertEqual(JobFinder.filter(jobs, query: " pr-2600 ").map(\.code.value), ["PR-260042"])
        XCTAssertEqual(JobFinder.filter(jobs, query: "pr").map(\.code.value), ["PR-260412", "PR-260042"])
        XCTAssertEqual(JobFinder.filter(jobs, query: "").count, 3)
    }

    func testMissingRootIsEmpty() {
        let layout = StorageLayout(root: URL(fileURLWithPath: "/nonexistent-\(UUID())"), language: .english)
        XCTAssertEqual(JobFinder.jobs(in: layout), [])
    }
}
