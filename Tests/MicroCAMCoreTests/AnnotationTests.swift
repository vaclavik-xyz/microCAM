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
    func testPointBudgetDropsShapesThatDoNotFit() {
        let many = (0..<4_999).map { AnnotationPoint(x: Double($0) / 5_000, y: 0.5) }
        let clean = AnnotationRequest(source: "x", shapes: [
            AnnotationShape(kind: .pen, points: many, color: "#123456", width: 0.01),
            AnnotationShape(kind: .pen, points: [.init(x: 0, y: 0), .init(x: 1, y: 1)], color: "#123456", width: 0.01),
            AnnotationShape(kind: .pen, points: Array(repeating: .init(x: 0.5, y: 0.5), count: 6_000),
                            color: "#123456", width: 0.01),
        ]).sanitized()
        XCTAssertEqual(clean.shapes.map(\.points.count), [4_999])
        let total = clean.shapes.reduce(0) { $0 + $1.points.count }
        XCTAssertLessThanOrEqual(total, AnnotationRequest.maxPoints)
    }
    func testDropsDegenerateShapes() {
        let clean = AnnotationRequest(source: "x", shapes: [
            AnnotationShape(kind: .pen, points: [.init(x: 0.5, y: 0.5)], color: "#123456", width: 0.01),
            AnnotationShape(kind: .ellipse, points: [], color: "#123456", width: 0.01),
        ]).sanitized()
        XCTAssertTrue(clean.shapes.isEmpty)
    }

    func testOldJSONWithoutNewFieldsDecodes() throws {
        let json = ##"{"source":"a.jpg","shapes":[{"kind":"arrow","points":[{"x":0,"y":0},{"x":1,"y":1}],"color":"#ff0000","width":0.01}]}"##
        let r = try JSONDecoder().decode(AnnotationRequest.self, from: Data(json.utf8)).sanitized()
        XCTAssertEqual(r.shapes.count, 1)
        XCTAssertNil(r.shapes[0].id)
        XCTAssertNil(r.shapes[0].text)
    }
    func testTextShapeSanitizing() {
        let s = AnnotationShape(kind: .text, points: [.init(x: 1.4, y: -0.2), .init(x: 0.5, y: 0.5)], color: "#ffd60a",
                                width: 0.006, text: "  C12\tshort\n\u{0007}ed  ", fontSize: 0.5)
        let clean = s.sanitized(pointBudget: 10)!
        XCTAssertEqual(clean.points, [.init(x: 1, y: 0)])
        XCTAssertEqual(clean.text, "C12 short ed")
        XCTAssertEqual(clean.fontSize, 0.12)
        XCTAssertEqual(AnnotationShape.cleanText(String(repeating: "é", count: 250))?.count, 200)
        XCTAssertNil(AnnotationShape(kind: .text, points: [.init(x: 0, y: 0)], color: "#fff000", width: 0.01,
                                     text: " \n\u{0007} ").sanitized(pointBudget: 10))
        XCTAssertNil(AnnotationShape(kind: .text, points: [.init(x: 0, y: 0)], color: "#fff000", width: 0.01)
            .sanitized(pointBudget: 10))
        XCTAssertEqual(AnnotationShape(kind: .text, points: [.init(x: 0, y: 0)], color: "#fff000", width: 0.01,
                                       text: "x").sanitized(pointBudget: 10)?.fontSize, AnnotationTextSize.medium.fontSize)
        XCTAssertEqual(AnnotationShape(kind: .text, points: [.init(x: 0, y: 0)], color: "#fff000", width: 0.01,
                                       text: "x", fontSize: 0.001).sanitized(pointBudget: 10)?.fontSize, 0.015)
    }
    func testTextKeepsJoinersButDropsFormatCharacters() {
        XCTAssertEqual(AnnotationShape.cleanText("a\u{200B}b\u{202E}c"), "abc")
        XCTAssertEqual(AnnotationShape.cleanText("👩\u{200D}🔧"), "👩\u{200D}🔧")
    }
    func testTextOnNonTextShapeIsDroppedAndIDsAreChecked() {
        let s = AnnotationShape(kind: .pen, points: [.init(x: 0, y: 0), .init(x: 1, y: 1)], color: "#123456", width: 0.01,
                                id: "abc-1_2", author: "bad id!", text: "x", fontSize: 0.05).sanitized(pointBudget: 10)!
        XCTAssertEqual(s.id, "abc-1_2")
        XCTAssertNil(s.author)
        XCTAssertNil(s.text)
        XCTAssertNil(s.fontSize)
        XCTAssertNil(AnnotationShape.cleanID(String(repeating: "a", count: 65)))
        XCTAssertEqual(AnnotationShape.cleanID("bench"), "bench")
    }
    func testPointerKeepsItsLatestPoints() {
        let pts = (0..<300).map { AnnotationPoint(x: Double($0) / 300, y: 0.5) }
        let s = AnnotationShape(kind: .pointer, points: pts, color: "#ff3b30", width: 0.006).sanitized(pointBudget: 5_000)!
        XCTAssertEqual(s.points.count, 200)
        XCTAssertEqual(s.points.last, pts.last)
    }

    func testTextOriginStaysInsideTheImageWithItsOutline() {
        let size = CGSize(width: 200, height: 100)
        // The outline and accents (Č, Ž) reach 0.15 × the font size past the box.
        let o = AnnotationTextLayout.origin(.init(x: 0.95, y: 0.98), textWidth: 60, fontPixels: 10, in: size)
        XCTAssertEqual(o.x, 138.5, accuracy: 0.001)
        XCTAssertEqual(o.y, 86.5, accuracy: 0.001)
        XCTAssertEqual(AnnotationTextLayout.origin(.init(x: 0.1, y: 0.2), textWidth: 60, fontPixels: 10, in: size),
                       CGPoint(x: 20, y: 20))
        XCTAssertEqual(AnnotationTextLayout.origin(.init(x: 0, y: 0), textWidth: 60, fontPixels: 10, in: size),
                       CGPoint(x: 1.5, y: 1.5))
    }
    func testALongLabelShrinksToFitTheWidth() {
        let size = CGSize(width: 400, height: 200)
        let px = AnnotationTextLayout.fittedFontPixels(14, textWidth: 800, in: size)
        XCTAssertEqual(px, 14 * (400 - 2 * 0.15 * px) / 800, accuracy: 0.01)
        XCTAssertEqual(AnnotationTextLayout.fittedFontPixels(14, textWidth: 100, in: size), 14)
        let label = AnnotationShape(kind: .text, points: [.init(x: 0.5, y: 0.5)], color: "#00ff00", width: 0.006,
                                    text: String(repeating: "W", count: 200), fontSize: 0.07)
        let frame = AnnotationTextLayout.frame(of: label, in: size)!
        XCTAssertGreaterThanOrEqual(frame.minX, 0)
        XCTAssertLessThanOrEqual(frame.maxX, 400)
    }
    func testTextIsRenderedInItsColourWithinItsFrame() {
        let shape = AnnotationShape(kind: .text, points: [.init(x: 0.9, y: 0.9)], color: "#00ff00", width: 0.006,
                                    text: "HHHH", fontSize: 0.3)
        let out = AnnotationRenderer.render([shape], onto: whiteImage(400, 200))!
        XCTAssertEqual(out.width, 400)
        XCTAssertEqual(out.height, 200)
        let frame = AnnotationTextLayout.frame(of: shape, in: CGSize(width: 400, height: 200))!
        XCTAssertGreaterThan(frame.width, 50)
        XCTAssertLessThanOrEqual(frame.maxX, 400)
        XCTAssertLessThanOrEqual(frame.maxY, 200)
        var green = 0, dark = 0
        for x in stride(from: Int(frame.minX), to: Int(frame.maxX), by: 2) {
            for y in stride(from: Int(frame.minY), to: Int(frame.maxY), by: 2) {
                let p = pixel(out, x, y)
                if p[1] > 200 && p[0] < 80 && p[2] < 80 { green += 1 }
                if p[0] < 90 && p[1] < 90 && p[2] < 90 { dark += 1 }
            }
        }
        XCTAssertGreaterThan(green, 20)
        XCTAssertGreaterThan(dark, 5)                        // the outline
        XCTAssertGreaterThan(pixel(out, 10, 10)[0], 240)     // far from the text: untouched
    }
    func testPointersAreNeverRenderedIntoFiles() {
        let p = AnnotationShape(kind: .pointer, points: [.init(x: 0, y: 0.5), .init(x: 1, y: 0.5)],
                                color: "#ff0000", width: 0.05)
        let out = AnnotationRenderer.render([p], onto: whiteImage(100, 100))!
        XCTAssertGreaterThan(pixel(out, 50, 50)[1], 240)
    }
    func testPointerIsDrawnWhenAnOpacityIsGiven() {
        let p = AnnotationShape(kind: .pointer, points: [.init(x: 0, y: 0.5), .init(x: 1, y: 0.5)],
                                color: "#ff0000", width: 0.05)
        let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(whiteImage(100, 100), in: CGRect(x: 0, y: 0, width: 100, height: 100))
        AnnotationRenderer.draw([p], in: ctx, size: CGSize(width: 100, height: 100), pointerOpacity: { _ in 1 })
        XCTAssertLessThan(pixel(ctx.makeImage()!, 50, 50)[1], 60)
    }
}
