import CoreImage
import XCTest
@testable import MicroCAMCore

final class AdjustmentPipelineTests: XCTestCase {
    let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
    let gray = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
        .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))

    func pixel(_ image: CIImage) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: 4)
        context.render(image, toBitmap: &p, rowBytes: 4, bounds: CGRect(x: 1, y: 1, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
        return p
    }

    func testNeutralReturnsSameImage() {
        XCTAssertTrue(AdjustmentPipeline.apply(.neutral, to: gray) === gray)
    }
    func testBrightnessRaisesLuma() {
        var a = ImageAdjustments.neutral
        a.brightness = 0.2
        XCTAssertGreaterThan(pixel(AdjustmentPipeline.apply(a, to: gray))[0], 150)
    }
    func testWarmerTemperatureRaisesRedLowersBlue() {
        var a = ImageAdjustments.neutral
        a.temperature = 8000
        let p = pixel(AdjustmentPipeline.apply(a, to: gray))
        XCTAssertGreaterThan(p[0], 128)
        XCTAssertLessThan(p[2], 128)
    }
    func testGammaAboveOneBrightens() {
        var a = ImageAdjustments.neutral
        a.gamma = 2
        XCTAssertGreaterThan(pixel(AdjustmentPipeline.apply(a, to: gray))[0], 160)
    }
    func testExtentIsPreserved() {
        var a = ImageAdjustments.neutral
        a.sharpness = 1
        a.contrast = 1.3
        XCTAssertEqual(AdjustmentPipeline.apply(a, to: gray).extent, gray.extent)
    }
}
