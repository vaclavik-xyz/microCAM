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
        // Jobs are opt-in (Settings → Storage); a new user just captures.
        XCTAssertFalse(s.jobsEnabled)
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
    func testCameraNameFallsBackToTheSystemName() {
        var s = AppSettings()
        XCTAssertEqual(s.cameraName(for: "cam", systemName: "Cam Link 4K"), "Cam Link 4K")
        s.cameraNames["cam"] = "  Mikroskop  "
        XCTAssertEqual(s.cameraName(for: "cam", systemName: "Cam Link 4K"), "Mikroskop")
        XCTAssertEqual(s.cameraName(for: "other", systemName: "FaceTime HD"), "FaceTime HD")
        s.cameraNames["cam"] = "   "
        XCTAssertEqual(s.cameraName(for: "cam", systemName: "Cam Link 4K"), "Cam Link 4K")
    }
    func testCameraNamesRoundTrip() {
        let store = SettingsStore(defaults: defaults)
        var s = AppSettings()
        s.cameraNames["cam"] = "Mikroskop"
        store.save(s)
        XCTAssertEqual(SettingsStore(defaults: defaults).load().cameraNames, ["cam": "Mikroskop"])
    }
    func testJobContext() {
        var s = AppSettings()
        XCTAssertEqual(s.jobContext, .jobsDisabled)
        s.jobsEnabled = true
        XCTAssertEqual(s.jobContext, .unassigned)
        s.activeJob = JobCode("PR-1")
        XCTAssertEqual(s.jobContext, .job(JobCode("PR-1")!))
        s.jobsEnabled = false
        XCTAssertEqual(s.jobContext, .jobsDisabled)
    }
    func testLayoutFollowsSettings() {
        var s = AppSettings()
        XCTAssertNil(s.layout(language: .english))
        s.storageRootPath = "/tmp/root"
        s.sortByType = true
        XCTAssertEqual(s.layout(language: .english)?.root.path, "/tmp/root")
        XCTAssertEqual(s.layout(language: .english)?.sortByType, true)
    }
    func testFormatLabel() {
        XCTAssertEqual(FormatChoice(width: 1920, height: 1080, fps: 59.94).label, "1920×1080 @ 60 fps")
    }

    func testWebhookDefaultsOff() {
        let s = SettingsStore(defaults: defaults).load()
        XCTAssertFalse(s.webhookEnabled)
        XCTAssertNil(s.webhookURL)
        XCTAssertFalse(s.webhookSendVideos)
    }
    func testStreamingAndViewerDefaultsAndRoundTrip() {
        let store = SettingsStore(defaults: defaults)
        var s = store.load()
        XCTAssertFalse(s.streamingEnabled)
        XCTAssertEqual(s.streamingPort, 8090)
        XCTAssertEqual(s.streamingMode, .controls)
        XCTAssertEqual(s.appMode, .camera)
        s.streamingEnabled = true
        s.streamingMode = .imageOnly
        s.appMode = .viewer
        s.viewerSourceName = "Workbench"
        store.save(s)
        XCTAssertEqual(SettingsStore(defaults: defaults).load(), s)
    }
    /// The MCP server is off until turned on; the token lives in the Keychain, not here.
    func testMCPDefaultsOffAndRoundTrips() {
        let store = SettingsStore(defaults: defaults)
        var s = store.load()
        XCTAssertFalse(s.mcpEnabled)
        XCTAssertEqual(s.mcpPort, 8091)
        s.mcpEnabled = true
        s.mcpPort = 9001
        store.save(s)
        XCTAssertEqual(SettingsStore(defaults: defaults).load(), s)
    }
    /// Older settings have no key: the format stays in the title as before.
    func testFormatInTitleDefaultsOnAndRoundTrips() {
        let store = SettingsStore(defaults: defaults)
        var s = store.load()
        XCTAssertTrue(s.showFormatInTitle)
        s.showFormatInTitle = false
        store.save(s)
        XCTAssertFalse(SettingsStore(defaults: defaults).load().showFormatInTitle)
    }
}
