import AVFoundation
import XCTest
@testable import MicroCAMCore

final class PolicyTests: XCTestCase {
    // MARK: lifecycle
    func testRunsByDefault() {
        XCTAssertTrue(CaptureLifecyclePolicy.shouldRun(CaptureLifecycleState()))
    }
    func testStopsWhenHiddenLockedOrDisplayOff() {
        var s = CaptureLifecycleState()
        s.windowVisible = false
        XCTAssertFalse(CaptureLifecyclePolicy.shouldRun(s))
        s = CaptureLifecycleState(); s.screenLocked = true
        XCTAssertFalse(CaptureLifecyclePolicy.shouldRun(s))
        s = CaptureLifecycleState(); s.displayAsleep = true
        XCTAssertFalse(CaptureLifecyclePolicy.shouldRun(s))
    }
    func testHiddenKeepsRunningWhenPauseDisabled() {
        var s = CaptureLifecycleState()
        s.windowVisible = false
        s.pauseWhenHidden = false
        XCTAssertTrue(CaptureLifecyclePolicy.shouldRun(s))
    }
    func testRecordingAndTimelapseKeepRunningWhenHiddenOrLocked() {
        var s = CaptureLifecycleState()
        s.windowVisible = false
        s.screenLocked = true
        s.recording = true
        XCTAssertTrue(CaptureLifecyclePolicy.shouldRun(s))
        s.recording = false
        s.timelapseRunning = true
        XCTAssertTrue(CaptureLifecyclePolicy.shouldRun(s))
    }
    func testSystemSleepAlwaysStops() {
        var s = CaptureLifecycleState()
        s.recording = true
        s.systemSleeping = true
        XCTAssertFalse(CaptureLifecyclePolicy.shouldRun(s))
    }

    // MARK: disk space
    func testDiskSpace() {
        XCTAssertEqual(DiskSpacePolicy.status(availableBytes: 50_000_000_000), .ok)
        XCTAssertEqual(DiskSpacePolicy.status(availableBytes: 4_000_000_000), .low)
        XCTAssertEqual(DiskSpacePolicy.status(availableBytes: 100_000_000), .critical)
    }

    // MARK: timelapse
    func testTimelapseValidation() {
        XCTAssertNil(TimelapseSchedule(interval: 0.5, duration: 60))
        XCTAssertNil(TimelapseSchedule(interval: 60, duration: 30))
        XCTAssertNil(TimelapseSchedule(interval: 60, duration: 8 * 24 * 3600))
        XCTAssertNotNil(TimelapseSchedule(interval: 1, duration: 1))
    }
    func testTimelapseShotCount() {
        let s = TimelapseSchedule(interval: 60, duration: 3600)!
        XCTAssertEqual(s.shotCount, 61) // t = 0, 60, …, 3600
        XCTAssertFalse(s.isFinished(shotsTaken: 60))
        XCTAssertTrue(s.isFinished(shotsTaken: 61))
    }

    // MARK: encoding
    func testBitrates() {
        XCTAssertEqual(VideoEncoding.bitrate(codec: .hevc, quality: .standard, width: 1920, height: 1080, fps: 60), 6_220_800)
        XCTAssertEqual(VideoEncoding.bitrate(codec: .h264, quality: .high, width: 1920, height: 1080, fps: 60), 19_906_560)
        XCTAssertEqual(VideoEncoding.bitrate(codec: .hevc, quality: .standard, width: 640, height: 480, fps: 25), 2_000_000)
    }
    func testVideoSettings() {
        let s = VideoEncoding.videoSettings(codec: .hevc, quality: .standard, width: 1920, height: 1080, fps: 60)
        XCTAssertEqual(s[AVVideoCodecKey] as? AVVideoCodecType, .hevc)
        XCTAssertEqual(s[AVVideoWidthKey] as? Int, 1920)
        let props = s[AVVideoCompressionPropertiesKey] as? [String: Any]
        XCTAssertEqual(props?[AVVideoAverageBitRateKey] as? Int, 6_220_800)
        XCTAssertEqual(props?[AVVideoExpectedSourceFrameRateKey] as? Int, 60)
    }

    // MARK: LockedValue
    func testLockedValueConcurrentUpdates() {
        let counter = LockedValue(0)
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in counter.update { $0 += 1 } }
        XCTAssertEqual(counter.value, 1000)
    }
    func testStreamViewersKeepCameraRunningExceptSleep() {
        var s = CaptureLifecycleState()
        s.windowVisible = false
        s.screenLocked = true
        s.streamViewers = true
        XCTAssertTrue(CaptureLifecyclePolicy.shouldRun(s))
        s.systemSleeping = true
        XCTAssertFalse(CaptureLifecyclePolicy.shouldRun(s))
    }
}
