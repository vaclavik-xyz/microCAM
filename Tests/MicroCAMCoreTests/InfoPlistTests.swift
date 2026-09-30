import XCTest

/// Keys in Resources/Info.plist that keep the preview cheap. Measured on an
/// M-series Mac with a 1080p60 HDMI capture card on macOS 26.5: with only
/// `NSCameraReactionEffectsEnabled` off, macOS still ran hand-gesture
/// detection for Reactions on every frame (~12 % CPU); turning
/// `NSCameraReactionEffectGesturesEnabledDefault` off as well brought it to
/// ~8 %. Both are read through LaunchServices, so after changing them the
/// installed app needs `lsregister -f` (scripts/deploy.sh does that).
final class InfoPlistTests: XCTestCase {
    let plistURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Info.plist")

    func testCameraEffectOptOutsAreOff() throws {
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        for key in ["NSCameraReactionEffectsEnabled", "NSCameraReactionEffectGesturesEnabledDefault"] {
            XCTAssertEqual(plist[key] as? Bool, false, "\(key) must be present and false in Resources/Info.plist")
        }
    }
}
