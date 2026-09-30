import XCTest
@testable import MicroCAMCore

final class PinGuardTests: XCTestCase {
    var clock = Date(timeIntervalSince1970: 1_000_000)

    func makeGuard() -> PinGuard { PinGuard(now: { [unowned self] in self.clock }) }

    func testValidPINFormat() {
        XCTAssertTrue(PinGuard.isValidPIN("1234"))
        XCTAssertTrue(PinGuard.isValidPIN("12345678"))
        XCTAssertFalse(PinGuard.isValidPIN("123"))
        XCTAssertFalse(PinGuard.isValidPIN("123456789"))
        XCTAssertFalse(PinGuard.isValidPIN("12a4"))
    }
    func testOkWrongAndNotConfigured() {
        let g = makeGuard()
        XCTAssertEqual(g.check("1234", expected: "1234"), .ok)
        XCTAssertEqual(g.check("9999", expected: "1234"), .wrong)
        XCTAssertEqual(g.check(nil, expected: "1234"), .wrong)
        XCTAssertEqual(g.check("1234", expected: nil), .notConfigured)
        XCTAssertEqual(g.check("1234", expected: ""), .notConfigured)
    }
    func testLocksAfterFiveFailures() {
        let g = makeGuard()
        for _ in 0..<5 { XCTAssertEqual(g.check("0000", expected: "1234"), .wrong) }
        let until = clock.addingTimeInterval(60)
        XCTAssertEqual(g.check("1234", expected: "1234"), .locked(until: until)) // even the right PIN
        clock = clock.addingTimeInterval(61)
        XCTAssertEqual(g.check("1234", expected: "1234"), .ok)
    }
    func testSuccessResetsFailures() {
        let g = makeGuard()
        for _ in 0..<4 { _ = g.check("0000", expected: "1234") }
        XCTAssertEqual(g.check("1234", expected: "1234"), .ok)
        for _ in 0..<4 { XCTAssertEqual(g.check("0000", expected: "1234"), .wrong) }
    }
}
