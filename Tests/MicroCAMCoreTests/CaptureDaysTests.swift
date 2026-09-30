import XCTest
@testable import MicroCAMCore

final class CaptureDaysTests: XCTestCase {
    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/x/\(name)") }

    func testGroupsNewestFirstListByDayKeepingOrder() {
        let files = [url("PR-1_2026-09-30_10-00-00.jpg"), url("no-job_2026-09-30_09-00-00_2.mov"),
                     url("PR-1_2026-09-25_14-30-00.jpg"), url("PR-1_2026-09-25_14-01-00.jpg")]
        let days = CaptureDays.group(files)
        XCTAssertEqual(days.map(\.day), ["2026-09-30", "2026-09-25"])
        XCTAssertEqual(days[0].files, Array(files[0...1]))
        XCTAssertEqual(days[1].files, Array(files[2...3]))
    }

    func testUnparsableNamesGoToOneTrailingGroup() {
        let files = [url("PR-1_2026-09-30_10-00-00.jpg"), url("odd.jpg")]
        let days = CaptureDays.group(files)
        XCTAssertEqual(days.map(\.day), ["2026-09-30", ""])
        XCTAssertEqual(days[1].files, [files[1]])
    }

    func testTimeOfDay() {
        XCTAssertEqual(CaptureDays.timeOfDay(url("PR-1_2026-09-25_14-30-05.jpg")), "14:30:05")
        XCTAssertEqual(CaptureDays.timeOfDay(url("PR-1_2026-09-25_14-30-05_3.jpg")), "14:30:05 (3)")
        XCTAssertEqual(CaptureDays.timeOfDay(url("odd.jpg")), "odd.jpg")
    }

    func testDayDate() {
        let date = CaptureDays.date(ofDay: "2026-09-25", timeZone: TimeZone(identifier: "Europe/Prague")!)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Prague")!
        XCTAssertEqual(date.map { cal.dateComponents([.year, .month, .day], from: $0) },
                       DateComponents(year: 2026, month: 9, day: 25))
        XCTAssertNil(CaptureDays.date(ofDay: ""))
    }
}
