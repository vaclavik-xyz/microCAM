import XCTest
@testable import MicroCAMCore

/// New captures are named in the app's language; captures named in any other
/// supported language must stay visible and movable after a language switch.
final class FolderLanguageTests: XCTestCase {
    let root = URL(fileURLWithPath: "/tmp/root", isDirectory: true)
    let job = JobContext.job(JobCode("PR-1")!)

    func testLanguageFromLocalization() {
        XCTAssertEqual(FolderLanguage(localization: "cs"), .czech)
        XCTAssertEqual(FolderLanguage(localization: "cs-CZ"), .czech)
        XCTAssertEqual(FolderLanguage(localization: "en"), .english)
        XCTAssertEqual(FolderLanguage(localization: "de"), .english)
        XCTAssertEqual(FolderLanguage(localization: nil), .english)
    }

    func testEnglishNames() {
        let layout = StorageLayout(root: root, sortByType: true, language: .english)
        XCTAssertEqual(layout.baseFolder(for: .unassigned).lastPathComponent, "_Unsorted")
        XCTAssertEqual(layout.folder(for: job, kind: .photo).path, "/tmp/root/PR-1/Photos")
        XCTAssertEqual(layout.folder(for: job, kind: .video).path, "/tmp/root/PR-1/Videos")
        XCTAssertEqual(layout.folder(for: job, kind: .timelapse).path, "/tmp/root/PR-1/Timelapse")
        XCTAssertEqual(layout.prefix(for: .unassigned), "no-job")
        XCTAssertEqual(layout.prefix(for: .jobsDisabled), "microcam")
        XCTAssertEqual(layout.prefix(for: job), "PR-1")
    }

    func testCzechNames() {
        let layout = StorageLayout(root: root, sortByType: true, language: .czech)
        XCTAssertEqual(layout.baseFolder(for: .unassigned).lastPathComponent, "_Nezařazeno")
        XCTAssertEqual(layout.folder(for: job, kind: .photo).lastPathComponent, "Fotky")
        XCTAssertEqual(layout.folder(for: job, kind: .video).lastPathComponent, "Videa")
        XCTAssertEqual(layout.folder(for: job, kind: .timelapse).lastPathComponent, "Časosběr")
        XCTAssertEqual(layout.prefix(for: .unassigned), "bez-zakazky")
        XCTAssertEqual(layout.prefix(for: .jobsDisabled), "microcam")
    }

    func testTypeFolderIsRecognisedInEveryLanguage() {
        XCTAssertEqual(CaptureKind.fromTypeFolder("Photos"), .photo)
        XCTAssertEqual(CaptureKind.fromTypeFolder("Fotky"), .photo)
        XCTAssertEqual(CaptureKind.fromTypeFolder("Videos"), .video)
        XCTAssertEqual(CaptureKind.fromTypeFolder("Videa"), .video)
        XCTAssertEqual(CaptureKind.fromTypeFolder("Timelapse"), .timelapse)
        XCTAssertEqual(CaptureKind.fromTypeFolder("Časosběr"), .timelapse)
        XCTAssertNil(CaptureKind.fromTypeFolder("PR-1"))
    }

    func testListedFoldersCoverBothLanguages() {
        let flat = StorageLayout(root: root, language: .english)
        XCTAssertEqual(flat.listedFolders(for: .unassigned).map(\.lastPathComponent), ["_Unsorted", "_Nezařazeno"])
        XCTAssertEqual(flat.listedFolders(for: job).map(\.lastPathComponent), ["PR-1"])
        let sorted = StorageLayout(root: root, sortByType: true, language: .czech)
        XCTAssertEqual(sorted.listedFolders(for: job).map(\.lastPathComponent),
                       ["PR-1", "Fotky", "Videa", "Časosběr", "Photos", "Videos", "Timelapse"])
        XCTAssertEqual(sorted.listedFolders(for: .unassigned).map { $0.path.replacingOccurrences(of: "/tmp/root/", with: "") },
                       ["_Nezařazeno", "_Nezařazeno/Fotky", "_Nezařazeno/Videa", "_Nezařazeno/Časosběr",
                        "_Nezařazeno/Photos", "_Nezařazeno/Videos", "_Nezařazeno/Timelapse",
                        "_Unsorted", "_Unsorted/Fotky", "_Unsorted/Videa", "_Unsorted/Časosběr",
                        "_Unsorted/Photos", "_Unsorted/Videos", "_Unsorted/Timelapse"])
    }

    func testLibraryShowsCapturesNamedInEitherLanguage() {
        let tmp = TempDir()
        tmp.touch("_Nezařazeno/bez-zakazky_2026-09-21_10-00-00.jpg")
        tmp.touch("_Unsorted/no-job_2026-09-21_11-00-00.jpg")
        let layout = StorageLayout(root: tmp.url, language: .english)
        let names = CaptureLibrary.captureFiles(in: layout.listedFolders(for: .unassigned)).map(\.lastPathComponent)
        XCTAssertEqual(names, ["no-job_2026-09-21_11-00-00.jpg", "bez-zakazky_2026-09-21_10-00-00.jpg"])
    }

    func testMoveToJobRenamesACaptureNamedInTheOtherLanguage() throws {
        let tmp = TempDir()
        let src = tmp.touch("_Nezařazeno/bez-zakazky_2026-09-21_10-00-00.jpg")
        let layout = StorageLayout(root: tmp.url, language: .english)
        let dest = try JobFileMover(layout: layout).move([src], to: job)[0].result.get()
        XCTAssertEqual(dest.lastPathComponent, "PR-1_2026-09-21_10-00-00.jpg")
    }

    func testMoveKeepsTheTypeOfACzechTypeFolder() throws {
        let tmp = TempDir()
        let shot = tmp.touch("PR-2/Časosběr/PR-2_2026-09-21_10-00-00.jpg")
        let layout = StorageLayout(root: tmp.url, sortByType: true, language: .english)
        let dest = try JobFileMover(layout: layout).move([shot], to: job)[0].result.get()
        XCTAssertEqual(dest.deletingLastPathComponent().lastPathComponent, "Timelapse")
    }

    /// A language switch alone never renames or relocates files.
    func testCaptureAlreadyInTheTargetInTheOtherLanguageStays() {
        let tmp = TempDir()
        let unsorted = tmp.touch("_Nezařazeno/bez-zakazky_2026-09-21_10-00-00.jpg")
        let typed = tmp.touch("PR-1/Fotky/PR-1_2026-09-21_10-00-00.jpg")
        let english = StorageLayout(root: tmp.url, sortByType: true, language: .english)
        XCTAssertEqual(JobFileMover(layout: english).move([typed], to: job)[0].result, .failure(.alreadyThere))
        let flat = StorageLayout(root: tmp.url, language: .english)
        XCTAssertEqual(JobFileMover(layout: flat).move([unsorted], to: .unassigned)[0].result, .failure(.alreadyThere))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unsorted.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: typed.path))
    }

    func testWebhookTreatsJoblessPrefixesOfEveryLanguageAsNoJob() {
        XCTAssertNil(WebhookClient.jobCode(for: URL(fileURLWithPath: "/r/_Unsorted/no-job_2026-09-21_10-00-00.jpg")))
        XCTAssertNil(WebhookClient.jobCode(for: URL(fileURLWithPath: "/r/_Nezařazeno/bez-zakazky_2026-09-21_10-00-00.jpg")))
        XCTAssertEqual(WebhookClient.jobCode(for: URL(fileURLWithPath: "/r/PR-7/Photos/PR-7_2026-09-21_10-00-00.jpg")), "PR-7")
    }

    func testSettingsBuildTheLayoutInTheGivenLanguage() {
        var s = AppSettings()
        XCTAssertNil(s.layout(language: .english))
        s.storageRootPath = "/tmp/root"
        XCTAssertEqual(s.layout(language: .czech)?.language, .czech)
        XCTAssertEqual(s.layout(language: .english)?.baseFolder(for: .unassigned).lastPathComponent, "_Unsorted")
    }
}
