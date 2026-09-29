import XCTest
@testable import MicroCAMCore

final class CameraReselectPolicyTests: XCTestCase {
    func testWaitsForRememberedCameraInsteadOfSwitching() {
        // Cam Link unplugged, only the FaceTime camera is left: do not switch.
        XCTAssertFalse(CameraReselectPolicy.shouldSelect(currentID: nil, rememberedID: "camlink", available: ["facetime"]))
    }
    func testReselectsWhenRememberedCameraReturns() {
        XCTAssertTrue(CameraReselectPolicy.shouldSelect(currentID: nil, rememberedID: "camlink", available: ["facetime", "camlink"]))
    }
    func testFirstLaunchPicksAnyCamera() {
        XCTAssertTrue(CameraReselectPolicy.shouldSelect(currentID: nil, rememberedID: nil, available: ["facetime"]))
        XCTAssertFalse(CameraReselectPolicy.shouldSelect(currentID: nil, rememberedID: nil, available: []))
    }
    func testKeepsRunningCamera() {
        XCTAssertFalse(CameraReselectPolicy.shouldSelect(currentID: "camlink", rememberedID: "camlink", available: ["camlink"]))
    }
}
