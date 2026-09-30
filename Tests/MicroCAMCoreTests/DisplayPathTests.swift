import XCTest
@testable import MicroCAMCore

final class DisplayPathTests: XCTestCase {
    let home = "/Users/alex"

    func testICloudDrive() {
        XCTAssertEqual(DisplayPath.string(for: "/Users/alex/Library/Mobile Documents/com~apple~CloudDocs/Repairs/microCAM", home: home),
                       "iCloud Drive/Repairs/microCAM")
    }
    func testHomeBecomesTilde() {
        XCTAssertEqual(DisplayPath.string(for: "/Users/alex/Pictures/microCAM", home: home), "~/Pictures/microCAM")
    }
    func testOtherPathsUnchanged() {
        XCTAssertEqual(DisplayPath.string(for: "/Volumes/Data/microCAM", home: home), "/Volumes/Data/microCAM")
        XCTAssertEqual(DisplayPath.string(for: "/Users/alexa/x", home: home), "/Users/alexa/x")
    }
}
