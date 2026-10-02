import XCTest
@testable import MicroCAMCore

final class VideoFeedGateTests: XCTestCase {
    func testStartsAtAKeyframe() {
        var gate = VideoFeedGate()
        XCTAssertEqual(gate.admit(isKeyframe: false), .skip)
        XCTAssertEqual(gate.admit(isKeyframe: true), .send)
        XCTAssertEqual(gate.admit(isKeyframe: false), .send)
        XCTAssertTrue(gate.synced)
    }

    /// A slow viewer drops to the next keyframe instead of lagging further behind.
    func testFallingBehindWaitsForTheNextKeyframe() {
        var gate = VideoFeedGate()
        XCTAssertEqual(gate.admit(isKeyframe: true), .send)
        for _ in 1..<VideoFeedGate.maxInFlight { XCTAssertEqual(gate.admit(isKeyframe: false), .send) }
        XCTAssertEqual(gate.admit(isKeyframe: false), .skipAndRequestKeyframe)
        XCTAssertFalse(gate.synced)
        XCTAssertEqual(gate.admit(isKeyframe: false), .skip)
        // A keyframe while old frames are still queued would only queue behind them.
        XCTAssertEqual(gate.admit(isKeyframe: true), .skipAndRequestKeyframe)
        for _ in 0..<VideoFeedGate.maxInFlight { gate.sent() }
        XCTAssertEqual(gate.admit(isKeyframe: false), .skip)
        XCTAssertEqual(gate.admit(isKeyframe: true), .send)
        XCTAssertEqual(gate.inFlight, 1)
    }

    func testKeepsUpWhenFramesLeave() {
        var gate = VideoFeedGate()
        XCTAssertEqual(gate.admit(isKeyframe: true), .send)
        for _ in 0..<100 {
            gate.sent()
            XCTAssertEqual(gate.admit(isKeyframe: false), .send)
        }
        gate.sent(); gate.sent()
        XCTAssertEqual(gate.inFlight, 0)
    }
}
