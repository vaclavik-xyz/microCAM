import XCTest
@testable import MicroCAMCore

final class ZoomStateTests: XCTestCase {
    let size = CGSize(width: 100, height: 100)

    func testInitialIsIdentity() {
        let z = ZoomState()
        XCTAssertEqual(z.layerTransform(viewSize: size), .identity)
        XCTAssertEqual(z.absoluteTransform(viewSize: size), .identity)
    }
    func testZoomAtCenter() {
        var z = ZoomState()
        z.zoom(by: 2, anchor: CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(z.scale, 2)
        XCTAssertEqual(z.center, CGPoint(x: 0.5, y: 0.5))
    }
    func testZoomAtCornerKeepsAnchorAndClamps() {
        var z = ZoomState()
        z.zoom(by: 2, anchor: CGPoint(x: 1, y: 1))
        XCTAssertEqual(z.center.x, 0.75, accuracy: 1e-9)
        XCTAssertEqual(z.center.y, 0.75, accuracy: 1e-9)
        // image point (75,75) (the new center) lands in the view center
        let p = CGPoint(x: 75, y: 75).applying(z.absoluteTransform(viewSize: size))
        XCTAssertEqual(p.x, 50, accuracy: 1e-9)
        XCTAssertEqual(p.y, 50, accuracy: 1e-9)
        // same mapping expressed relative to the layer's center anchor
        let q = CGPoint(x: 25, y: 25).applying(z.layerTransform(viewSize: size))
        XCTAssertEqual(q.x, 0, accuracy: 1e-9)
        XCTAssertEqual(q.y, 0, accuracy: 1e-9)
    }
    func testScaleLimits() {
        var z = ZoomState()
        z.zoom(by: 100, anchor: CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(z.scale, ZoomState.maxScale)
        z.zoom(by: 0.001, anchor: CGPoint(x: 0.9, y: 0.1))
        XCTAssertEqual(z, ZoomState())
    }
    func testPanMovesOppositeAndClamps() {
        var z = ZoomState()
        z.zoom(by: 2, anchor: CGPoint(x: 0.5, y: 0.5))
        z.pan(byNormalized: CGPoint(x: 0.1, y: 0))
        XCTAssertEqual(z.center.x, 0.45, accuracy: 1e-9)
        z.pan(byNormalized: CGPoint(x: 10, y: -10))
        XCTAssertEqual(z.center, CGPoint(x: 0.25, y: 0.75))
    }
    func testPanAtScaleOneDoesNothing() {
        var z = ZoomState()
        z.pan(byNormalized: CGPoint(x: 0.3, y: 0.3))
        XCTAssertEqual(z, ZoomState())
    }
    func testReset() {
        var z = ZoomState()
        z.zoom(by: 3, anchor: CGPoint(x: 0.2, y: 0.2))
        z.reset()
        XCTAssertEqual(z, ZoomState())
    }
}
