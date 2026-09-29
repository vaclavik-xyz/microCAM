import CoreGraphics
import XCTest
@testable import MicroCAMCore

final class AnnotationTests: XCTestCase {
    func whiteImage(_ w: Int, _ h: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    /// RGBA at (x, y) with y measured from the top, like the browser.
    func pixel(_ image: CGImage, _ x: Int, _ yFromTop: Int) -> [UInt8] {
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let offset = (yFromTop * image.width + x) * 4 // bitmap memory is top-down
        return Array(UnsafeBufferPointer(start: data + offset, count: 4))
    }

    func testPenLineIsDrawnWithTopLeftOrigin() {
        let shape = AnnotationShape(kind: .pen, points: [.init(x: 0, y: 0.25), .init(x: 1, y: 0.25)],
                                    color: "#ff0000", width: 0.02)
        let out = AnnotationRenderer.render([shape], onto: whiteImage(200, 100))!
        let onLine = pixel(out, 100, 25)
        XCTAssertGreaterThan(onLine[0], 200); XCTAssertLessThan(onLine[1], 60)
        let below = pixel(out, 100, 75)
        XCTAssertGreaterThan(below[1], 240) // untouched white
    }
    func testEllipseOutlineNotFilled() {
        let shape = AnnotationShape(kind: .ellipse, points: [.init(x: 0.25, y: 0.25), .init(x: 0.75, y: 0.75)],
                                    color: "#00ff00", width: 0.02)
        let out = AnnotationRenderer.render([shape], onto: whiteImage(200, 100))!
        XCTAssertGreaterThan(pixel(out, 50, 50)[1], 200)   // left edge of the ellipse is green
        XCTAssertLessThan(pixel(out, 50, 50)[0], 60)
        XCTAssertGreaterThan(pixel(out, 100, 50)[0], 240)  // centre stays white
    }
    func testSanitizing() {
        var shapes = (0..<250).map { _ in
            AnnotationShape(kind: .arrow, points: [.init(x: -1, y: 0.5), .init(x: 0.3, y: 0.3), .init(x: 2, y: 0.5)],
                            color: "red; drop table", width: 9)
        }
        shapes.append(AnnotationShape(kind: .pen, points: [.init(x: 0.5, y: 0.5)], color: "#123456", width: 0.01))
        let clean = AnnotationRequest(source: "x", shapes: shapes).sanitized()
        XCTAssertEqual(clean.shapes.count, 200)
        XCTAssertEqual(clean.shapes[0].points, [.init(x: 0, y: 0.5), .init(x: 1, y: 0.5)])
        XCTAssertEqual(clean.shapes[0].color, "#ff3b30")
        XCTAssertEqual(clean.shapes[0].width, 0.05)
    }
    func testDropsDegenerateShapes() {
        let clean = AnnotationRequest(source: "x", shapes: [
            AnnotationShape(kind: .pen, points: [.init(x: 0.5, y: 0.5)], color: "#123456", width: 0.01),
            AnnotationShape(kind: .ellipse, points: [], color: "#123456", width: 0.01),
        ]).sanitized()
        XCTAssertTrue(clean.shapes.isEmpty)
    }
}
