import XCTest
@testable import MicroCAMCore

final class ImageAdjustmentsTests: XCTestCase {
    func testNeutral() {
        XCTAssertTrue(ImageAdjustments.neutral.isNeutral)
        var a = ImageAdjustments.neutral
        a.sharpness = 0.3
        XCTAssertFalse(a.isNeutral)
    }
    func testClamped() {
        var a = ImageAdjustments.neutral
        a.brightness = 5
        a.temperature = 100
        let c = a.clamped()
        XCTAssertEqual(c.brightness, ImageAdjustments.ranges[\.brightness]!.upperBound)
        XCTAssertEqual(c.temperature, ImageAdjustments.ranges[\.temperature]!.lowerBound)
    }
    func testDecodingMissingKeysUsesNeutralValues() throws {
        let a = try JSONDecoder().decode(ImageAdjustments.self, from: Data(#"{"contrast":1.5}"#.utf8))
        XCTAssertEqual(a.contrast, 1.5)
        XCTAssertEqual(a.temperature, 6500)
        XCTAssertEqual(a.gamma, 1)
    }
}
