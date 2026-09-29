import XCTest
@testable import MicroCAMCore

final class JobCodeTests: XCTestCase {
    func testNormalizesWhitespaceAndCase() {
        XCTAssertEqual(JobCode("  pr-260042 \n")?.value, "PR-260042")
    }
    func testAcceptsPlainNumber() {
        XCTAssertEqual(JobCode("260042")?.value, "260042")
    }
    func testRejectsEmpty() {
        XCTAssertNil(JobCode("   "))
    }
    func testRejectsPathAndSeparatorCharacters() {
        for raw in ["PR/1", "..", "PR_1", "PR 1", "a:b", "-PR1", "Ž1"] {
            XCTAssertNil(JobCode(raw), raw)
        }
    }
    func testRejectsTooLong() {
        XCTAssertNil(JobCode(String(repeating: "A", count: 33)))
        XCTAssertNotNil(JobCode(String(repeating: "A", count: 32)))
    }
    func testCodableRoundTripAndValidation() throws {
        let data = try JSONEncoder().encode(JobCode("PR-1")!)
        XCTAssertEqual(try JSONDecoder().decode(JobCode.self, from: data).value, "PR-1")
        XCTAssertThrowsError(try JSONDecoder().decode(JobCode.self, from: Data("\"a/b\"".utf8)))
    }
}
