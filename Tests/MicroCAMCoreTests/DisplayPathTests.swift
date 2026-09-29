import XCTest
@testable import MicroCAMCore

final class DisplayPathTests: XCTestCase {
    let home = "/Users/user"

    func testICloudDrive() {
        XCTAssertEqual(DisplayPath.string(for: "/Users/user/Library/Mobile Documents/com~apple~CloudDocs/Repairs/microCAM", home: home),
                       "iCloud Drive/Repairs/microCAM")
    }
    func testHomeBecomesTilde() {
        XCTAssertEqual(DisplayPath.string(for: "/Users/user/Pictures/microCAM", home: home), "~/Pictures/microCAM")
    }
    func testOtherPathsUnchanged() {
        XCTAssertEqual(DisplayPath.string(for: "/Volumes/Data/microCAM", home: home), "/Volumes/Data/microCAM")
        XCTAssertEqual(DisplayPath.string(for: "/Users/usera/x", home: home), "/Users/usera/x")
    }
}
