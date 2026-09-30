import XCTest
@testable import MicroCAMCore

final class JobFileMoverTests: XCTestCase {
    let pr7 = JobContext.job(JobCode("PR-7")!)

    func testMovesAndRenamesKeepingTimestamp() throws {
        let tmp = TempDir()
        let src = tmp.touch("_Nezařazeno/bez-zakazky_2026-09-21_10-00-00.jpg")
        let dest = try JobFileMover(layout: StorageLayout(root: tmp.url, language: .czech)).move([src], to: pr7)[0].result.get()
        XCTAssertEqual(dest.lastPathComponent, "PR-7_2026-09-21_10-00-00.jpg")
        XCTAssertEqual(dest.deletingLastPathComponent().lastPathComponent, "PR-7")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path))
    }
    func testMoveResolvesCollision() throws {
        let tmp = TempDir()
        tmp.touch("PR-7/PR-7_2026-09-21_10-00-00.jpg")
        let src = tmp.touch("PR-1/PR-1_2026-09-21_10-00-00.jpg")
        let dest = try JobFileMover(layout: StorageLayout(root: tmp.url, language: .czech)).move([src], to: pr7)[0].result.get()
        XCTAssertEqual(dest.lastPathComponent, "PR-7_2026-09-21_10-00-00_2.jpg")
        XCTAssertEqual(tmp.contents("PR-7").count, 2)
    }
    func testSortByTypeKeepsTypeFolder() throws {
        let tmp = TempDir()
        let layout = StorageLayout(root: tmp.url, sortByType: true, language: .czech)
        let shot = tmp.touch("PR-1/Časosběr/PR-1_2026-09-21_10-00-00.jpg")
        let movie = tmp.touch("PR-1/Videa/PR-1_2026-09-21_11-00-00.mov")
        let outcomes = JobFileMover(layout: layout).move([shot, movie], to: pr7)
        XCTAssertEqual(try outcomes[0].result.get().deletingLastPathComponent().lastPathComponent, "Časosběr")
        XCTAssertEqual(try outcomes[1].result.get().deletingLastPathComponent().lastPathComponent, "Videa")
    }
    func testForeignFileIsRejectedAndLeftAlone() {
        let tmp = TempDir()
        let src = tmp.touch("PR-1/IMG_0001.jpg")
        let outcome = JobFileMover(layout: StorageLayout(root: tmp.url, language: .czech)).move([src], to: .unassigned)
        XCTAssertEqual(outcome[0].result, .failure(.notACaptureFile))
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path))
    }
    func testSameJobIsNoOp() {
        let tmp = TempDir()
        let src = tmp.touch("PR-1/PR-1_2026-09-21_10-00-00.jpg")
        let outcome = JobFileMover(layout: StorageLayout(root: tmp.url, language: .czech)).move([src], to: .job(JobCode("PR-1")!))
        XCTAssertEqual(outcome[0].result, .failure(.alreadyThere))
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path))
    }
    func testMissingSourceReportsFailureAndContinues() throws {
        let tmp = TempDir()
        let ghost = tmp.url.appendingPathComponent("PR-1/PR-1_2026-09-21_09-00-00.jpg")
        let real = tmp.touch("PR-1/PR-1_2026-09-21_10-00-00.jpg")
        let outcomes = JobFileMover(layout: StorageLayout(root: tmp.url, language: .czech)).move([ghost, real], to: .unassigned)
        guard case .failure(.fileSystem) = outcomes[0].result else { return XCTFail("expected fileSystem failure") }
        XCTAssertEqual(try outcomes[1].result.get().lastPathComponent, "bez-zakazky_2026-09-21_10-00-00.jpg")
    }
    func testMissingRootFailsWithStorageError() {
        let tmp = TempDir()
        let src = tmp.touch("x/PR-1_2026-09-21_10-00-00.jpg")
        let missingRoot = tmp.url.appendingPathComponent("gone", isDirectory: true)
        let outcome = JobFileMover(layout: StorageLayout(root: missingRoot, language: .czech)).move([src], to: .unassigned)
        XCTAssertEqual(outcome[0].result, .failure(.storage(.rootUnavailable(missingRoot))))
    }
}
