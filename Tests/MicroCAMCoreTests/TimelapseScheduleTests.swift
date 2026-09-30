import XCTest
@testable import MicroCAMCore

final class TimelapseScheduleTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_000_000)

    func testLastShotIsAtTheLastFullInterval() {
        // 1 min for 1 h: 61 shots, the last one exactly an hour after the first.
        let s = TimelapseSchedule(interval: 60, duration: 3600)!
        XCTAssertEqual(s.shotCount, 61)
        XCTAssertEqual(s.lastShot(startedAt: start), start.addingTimeInterval(3600))
        // 7 min for 1 h: 9 shots, the last at 56 min, not at 60.
        let odd = TimelapseSchedule(interval: 420, duration: 3600)!
        XCTAssertEqual(odd.lastShot(startedAt: start), start.addingTimeInterval(8 * 420))
    }

    func testNextShotFollowsShotsTaken() {
        let s = TimelapseSchedule(interval: 30, duration: 300)!
        XCTAssertEqual(s.nextShot(startedAt: start, shotsTaken: 1), start.addingTimeInterval(30))
        XCTAssertEqual(s.nextShot(startedAt: start, shotsTaken: 4), start.addingTimeInterval(120))
        XCTAssertNil(s.nextShot(startedAt: start, shotsTaken: s.shotCount))
    }
}
