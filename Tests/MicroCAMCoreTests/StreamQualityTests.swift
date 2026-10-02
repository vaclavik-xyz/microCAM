import XCTest
@testable import MicroCAMCore

final class StreamQualityTests: XCTestCase {
    /// Measured on a 1920×1080 board picture: 1920 at 0.7 was ~480 KB a frame
    /// (58 Mbit/s at 15 fps), and a Wi-Fi viewer got 4 fps. Smooth must fit
    /// about 20 Mbit/s.
    func testSmoothIsTheDefaultAndSmaller() {
        XCTAssertEqual(AppSettings().streamQuality, .smooth)
        XCTAssertEqual(StreamQuality.smooth.maxWidth, 1280)
        XCTAssertEqual(StreamQuality.sharp.maxWidth, 1920)
        XCTAssertLessThan(StreamQuality.smooth.jpegQuality, StreamQuality.sharp.jpegQuality)
    }

    /// The video stream measured on Wi-Fi at about 18 Mbit/s: both bit rates must fit with room to spare.
    func testVideoBitRatesFitWiFi() {
        XCTAssertEqual(StreamQuality.videoMaxWidth, 1920)
        XCTAssertLessThan(StreamQuality.smooth.videoBitsPerSecond, StreamQuality.sharp.videoBitsPerSecond)
        XCTAssertLessThanOrEqual(StreamQuality.sharp.videoBitsPerSecond, 10_000_000)
    }

    func testRoundTripAndOlderSettings() throws {
        var s = AppSettings()
        s.streamQuality = .sharp
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data).streamQuality, .sharp)
        let old = Data(#"{"streamingEnabled":true}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: old).streamQuality, .smooth)
    }
}
