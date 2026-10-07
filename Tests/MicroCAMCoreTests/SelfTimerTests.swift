import XCTest
@testable import MicroCAMCore

final class SelfTimerTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 1000)

    func testCountsDownWholeSeconds() {
        let countdown = SelfTimerCountdown(seconds: 5, startedAt: start)
        XCTAssertEqual(countdown.remaining(at: start), 5)
        XCTAssertEqual(countdown.remaining(at: start.addingTimeInterval(0.2)), 5)
        XCTAssertEqual(countdown.remaining(at: start.addingTimeInterval(1)), 4)
        // A timer fires a little late, never early: still the right number.
        XCTAssertEqual(countdown.remaining(at: start.addingTimeInterval(1.01)), 4)
        XCTAssertEqual(countdown.remaining(at: start.addingTimeInterval(4.01)), 1)
        XCTAssertFalse(countdown.isDue(at: start.addingTimeInterval(4.99)))
        XCTAssertTrue(countdown.isDue(at: start.addingTimeInterval(5)))
        XCTAssertEqual(countdown.remaining(at: start.addingTimeInterval(60)), 0)
    }

    func testDefaultDelayIsOneOfTheChoices() {
        XCTAssertTrue(SelfTimer.delays.contains(SelfTimer.defaultDelay))
        XCTAssertEqual(AppSettings().selfTimerDelay, SelfTimer.defaultDelay)
        for delay in SelfTimer.delays { XCTAssertTrue(SelfTimer.isValid(remoteDelay: delay)) }
    }

    func testRemoteDelayFromQuery() {
        XCTAssertEqual(SelfTimer.remoteDelay(query: nil), 0)
        XCTAssertEqual(SelfTimer.remoteDelay(query: "0"), 0)
        XCTAssertEqual(SelfTimer.remoteDelay(query: "5"), 5)
        XCTAssertEqual(SelfTimer.remoteDelay(query: "30"), 30)
        for bad in ["31", "-1", "", "abc", "2.5", "1e3"] {
            XCTAssertNil(SelfTimer.remoteDelay(query: bad), bad)
        }
    }

    func testDelayRoundTripsInSettings() throws {
        var settings = AppSettings()
        settings.selfTimerDelay = 10
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.selfTimerDelay, 10)
    }
}
