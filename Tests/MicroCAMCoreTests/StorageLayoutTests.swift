import XCTest
@testable import MicroCAMCore

final class StorageLayoutTests: XCTestCase {
    let root = URL(fileURLWithPath: "/tmp/root", isDirectory: true)
    let job = JobContext.job(JobCode("PR-1")!)

    func testFlatFolders() {
        let layout = StorageLayout(root: root, language: .czech)
        XCTAssertEqual(layout.folder(for: job, kind: .video).path, "/tmp/root/PR-1")
        XCTAssertEqual(layout.folder(for: .unassigned, kind: .photo).path, "/tmp/root/_Nezařazeno")
        XCTAssertEqual(layout.folder(for: .jobsDisabled, kind: .timelapse).path, "/tmp/root")
        XCTAssertEqual(layout.listedFolders(for: job).map(\.path), ["/tmp/root/PR-1"])
    }
    func testSortByTypeFolders() {
        let layout = StorageLayout(root: root, sortByType: true, language: .czech)
        XCTAssertEqual(layout.folder(for: job, kind: .photo).path, "/tmp/root/PR-1/Fotky")
        XCTAssertEqual(layout.folder(for: job, kind: .video).path, "/tmp/root/PR-1/Videa")
        XCTAssertEqual(layout.folder(for: .jobsDisabled, kind: .timelapse).path, "/tmp/root/Časosběr")
        // the base folder is listed too, so files saved before the mode was switched stay visible
        XCTAssertEqual(layout.listedFolders(for: job).map(\.lastPathComponent).prefix(4), ["PR-1", "Fotky", "Videa", "Časosběr"])
    }
    func testPrefixes() {
        let layout = StorageLayout(root: root, language: .czech)
        XCTAssertEqual(layout.prefix(for: job), "PR-1")
        XCTAssertEqual(layout.prefix(for: .unassigned), "bez-zakazky")
        XCTAssertEqual(layout.prefix(for: .jobsDisabled), "microcam")
    }
    func testPrepareFolderCreatesJobFolderOnly() throws {
        let tmp = TempDir()
        _ = try StorageLayout(root: tmp.url, language: .czech).prepareFolder(for: job, kind: .photo)
        _ = try StorageLayout(root: tmp.url, language: .czech).prepareFolder(for: job, kind: .photo) // idempotent
        XCTAssertEqual(tmp.contents(), ["PR-1"])
        XCTAssertEqual(tmp.contents("PR-1"), [])
    }
    func testPrepareFolderSortByTypeCreatesOnlyNeededTypeFolder() throws {
        let tmp = TempDir()
        _ = try StorageLayout(root: tmp.url, sortByType: true, language: .czech).prepareFolder(for: job, kind: .video)
        XCTAssertEqual(tmp.contents("PR-1"), ["Videa"])
    }
    func testPrepareFolderJobsDisabledCreatesNothing() throws {
        let tmp = TempDir()
        let folder = try StorageLayout(root: tmp.url, language: .czech).prepareFolder(for: .jobsDisabled, kind: .photo)
        XCTAssertEqual(folder.standardizedFileURL, tmp.url.standardizedFileURL)
        XCTAssertEqual(tmp.contents(), [])
    }
    func testPrepareFolderFailsWhenRootMissing() {
        let missing = TempDir().url.appendingPathComponent("gone", isDirectory: true)
        XCTAssertThrowsError(try StorageLayout(root: missing, language: .czech).prepareFolder(for: job, kind: .photo)) { error in
            XCTAssertEqual(error as? StorageError, .rootUnavailable(missing))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }
    func testPrepareFolderFailsWhenRootIsAFile() {
        let tmp = TempDir()
        let file = tmp.touch("root-file")
        XCTAssertThrowsError(try StorageLayout(root: file, language: .czech).prepareFolder(for: .unassigned, kind: .photo)) { error in
            XCTAssertEqual(error as? StorageError, .rootUnavailable(file))
        }
    }
}
