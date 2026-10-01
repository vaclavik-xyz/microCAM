import CoreGraphics
import XCTest
@testable import MicroCAMCore

final class PreviewGeometryTests: XCTestCase {
    let view = CGSize(width: 1000, height: 1000)
    let hd = CGSize(width: 1920, height: 1080)

    func testPictureIsFittedWithLetterboxes() {
        let rect = PreviewGeometry(viewSize: view, contentSize: hd, zoom: ZoomState()).imageRect
        XCTAssertEqual(rect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(rect.width, 1000, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 218.75, accuracy: 0.001)
        XCTAssertEqual(rect.maxY, 781.25, accuracy: 0.001)
        XCTAssertEqual(PreviewGeometry(viewSize: view, contentSize: nil, zoom: ZoomState()).imageRect,
                       CGRect(origin: .zero, size: view))
    }

    func testTopLeftOfTheImageIsTopLeftOfThePicture() {
        let g = PreviewGeometry(viewSize: view, contentSize: hd, zoom: ZoomState())
        let p = g.viewPoint(AnnotationPoint(x: 0, y: 0))
        XCTAssertEqual(p.x, 0, accuracy: 0.001)
        XCTAssertEqual(p.y, 781.25, accuracy: 0.001)   // view origin is bottom-left
    }

    func testRoundTripAtAnyZoom() {
        var zoom = ZoomState()
        for z in [nil, (3.0, CGPoint(x: 0.8, y: 0.3))] as [(CGFloat, CGPoint)?] {
            if let z { zoom.zoom(by: z.0, anchor: z.1) }
            let g = PreviewGeometry(viewSize: CGSize(width: 1200, height: 700), contentSize: hd, zoom: zoom)
            for p in [AnnotationPoint(x: 0.7, y: 0.4), AnnotationPoint(x: 0.75, y: 0.66)] {
                let back = g.imagePoint(g.viewPoint(p))
                XCTAssertEqual(back.x, p.x, accuracy: 1e-9)
                XCTAssertEqual(back.y, p.y, accuracy: 1e-9)
            }
        }
    }

    func testZoomScalesThePictureAroundTheCentre() {
        var zoom = ZoomState()
        zoom.zoom(by: 2, anchor: CGPoint(x: 0.5, y: 0.5))
        let g = PreviewGeometry(viewSize: view, contentSize: hd, zoom: zoom)
        XCTAssertEqual(g.imageRect.width, 2000, accuracy: 0.001)
        let centre = g.viewPoint(AnnotationPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(centre.x, 500, accuracy: 0.001)
        XCTAssertEqual(centre.y, 500, accuracy: 0.001)
    }

    func testPointsOutsideThePictureAreClampedAndReported() {
        let g = PreviewGeometry(viewSize: view, contentSize: hd, zoom: ZoomState())
        XCTAssertEqual(g.imagePoint(CGPoint(x: -50, y: 900)), AnnotationPoint(x: 0, y: 0))
        XCTAssertFalse(g.containsImage(CGPoint(x: 500, y: 100)))
        XCTAssertTrue(g.containsImage(CGPoint(x: 500, y: 500)))
    }
}
