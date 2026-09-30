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

    /// Sparkle reads the appcast that scripts/release.sh attaches to every
    /// release; "latest/download" always resolves to the newest one.
    func testUpdateFeedPointsAtTheLatestRelease() throws {
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["SUFeedURL"] as? String,
                       "https://github.com/vaclavik-xyz/microCAM/releases/latest/download/appcast.xml")
        XCTAssertNotNil(plist["SUPublicEDKey"] as? String, "SUPublicEDKey must exist (empty turns updates off)")
    }

    /// Under the hardened runtime (Developer ID builds) the camera and the
    /// microphone need entitlements, or macOS silently denies them.
    func testEntitlementsAllowCameraAndMicrophone() throws {
        let url = plistURL.deletingLastPathComponent().appendingPathComponent("microCAM.entitlements")
        let data = try Data(contentsOf: url)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["com.apple.security.device.camera"] as? Bool, true)
        XCTAssertEqual(plist["com.apple.security.device.audio-input"] as? Bool, true)
    }
}
