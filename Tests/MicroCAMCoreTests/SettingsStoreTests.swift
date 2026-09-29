import XCTest
@testable import MicroCAMCore

final class SettingsStoreTests: XCTestCase {
    var defaults: UserDefaults!
    let suite = "microcam-tests-\(UUID().uuidString)"

    override func setUp() { defaults = UserDefaults(suiteName: suite) }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    func testDefaultsWhenEmpty() {
        let s = SettingsStore(defaults: defaults).load()
        XCTAssertEqual(s, AppSettings())
        XCTAssertNil(s.storageRoot)
        XCTAssertTrue(s.jobsEnabled)
        XCTAssertFalse(s.sortByType)
    }
    func testRoundTrip() {
        let store = SettingsStore(defaults: defaults)
        var s = AppSettings()
        s.storageRootPath = "/tmp/x"
        s.activeJob = JobCode("PR-5")
        s.videoCodec = .h264
        s.lastFormatByDevice["cam"] = FormatChoice(width: 1920, height: 1080, fps: 60)
        var adj = ImageAdjustments.neutral
        adj.gamma = 1.4
        s.adjustmentsByDevice["cam"] = adj
        store.save(s)
        XCTAssertEqual(SettingsStore(defaults: defaults).load(), s)
    }
    func testMissingKeysUseDefaults() {
        defaults.set(Data(#"{"jobsEnabled":false,"jpegQuality":0.7}"#.utf8), forKey: "microcam.settings.v1")
        let s = SettingsStore(defaults: defaults).load()
        XCTAssertFalse(s.jobsEnabled)
        XCTAssertEqual(s.jpegQuality, 0.7)
        XCTAssertEqual(s.videoCodec, .hevc)
        XCTAssertTrue(s.pauseWhenHidden)
    }
    func testCorruptDataReturnsDefaults() {
        defaults.set(Data("not json".utf8), forKey: "microcam.settings.v1")
        XCTAssertEqual(SettingsStore(defaults: defaults).load(), AppSettings())
    }
    func testInvalidStoredJobIsDropped() {
        defaults.set(Data(#"{"activeJob":"a/b","jobsEnabled":true}"#.utf8), forKey: "microcam.settings.v1")
        let s = SettingsStore(defaults: defaults).load()
        XCTAssertNil(s.activeJob)
        XCTAssertTrue(s.jobsEnabled)
    }
    func testJobContext() {
        var s = AppSettings()
        XCTAssertEqual(s.jobContext, .unassigned)
        s.activeJob = JobCode("PR-1")
        XCTAssertEqual(s.jobContext, .job(JobCode("PR-1")!))
        s.jobsEnabled = false
        XCTAssertEqual(s.jobContext, .jobsDisabled)
    }
    func testLayoutFollowsSettings() {
        var s = AppSettings()
        XCTAssertNil(s.layout)
        s.storageRootPath = "/tmp/root"
        s.sortByType = true
        XCTAssertEqual(s.layout?.root.path, "/tmp/root")
        XCTAssertEqual(s.layout?.sortByType, true)
    }
    func testFormatLabel() {
        XCTAssertEqual(FormatChoice(width: 1920, height: 1080, fps: 59.94).label, "1920×1080 @ 60 fps")
    }
}
