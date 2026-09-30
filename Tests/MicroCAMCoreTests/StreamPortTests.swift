import XCTest
@testable import MicroCAMCore

final class StreamPortTests: XCTestCase {
    func testParsesUsablePorts() {
        XCTAssertEqual(StreamPort.parse("8090"), 8090)
        XCTAssertEqual(StreamPort.parse(" 1024 "), 1024)
        XCTAssertEqual(StreamPort.parse("65535"), 65535)
    }
    func testRejectsPrivilegedOutOfRangeAndGarbage() {
        for text in ["", "80", "1023", "65536", "8o90", "-8090", "8090.5", "99999999999999999999"] {
            XCTAssertNil(StreamPort.parse(text), text)
        }
    }
    func testIsValid() {
        XCTAssertTrue(StreamPort.isValid(8090))
        XCTAssertFalse(StreamPort.isValid(0))
    }
}
