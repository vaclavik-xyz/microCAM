import CoreGraphics
import XCTest
@testable import MicroCAMCore

final class GridNavigationTests: XCTestCase {
    /// Two columns; day 1 has a, b, c (c alone in its row), day 2 has d, e under a header.
    let order = ["a", "b", "c", "d", "e"]
    let frames: [String: CGRect] = [
        "a": CGRect(x: 0, y: 0, width: 100, height: 70), "b": CGRect(x: 110, y: 0, width: 100, height: 70),
        "c": CGRect(x: 0, y: 80, width: 100, height: 70),
        "d": CGRect(x: 0, y: 190, width: 100, height: 70), "e": CGRect(x: 110, y: 190, width: 100, height: 70),
    ]

    func target(_ from: String?, _ move: GridMove, frames: [String: CGRect]? = nil) -> String? {
        GridNavigation.target(from: from, move: move, order: order, frames: frames ?? self.frames)
    }

    func testLeftAndRightFollowTheOrderAcrossRowsAndDays() {
        XCTAssertEqual(target("b", .right), "c")
        XCTAssertEqual(target("c", .right), "d")
        XCTAssertEqual(target("d", .left), "c")
        XCTAssertNil(target("a", .left))
        XCTAssertNil(target("e", .right))
    }

    func testUpAndDownGoToTheNearestTileOfTheNextRow() {
        XCTAssertEqual(target("a", .down), "c")
        XCTAssertEqual(target("b", .down), "c")   // the row below has only c
        XCTAssertEqual(target("c", .down), "d")   // across the day header
        XCTAssertEqual(target("e", .up), "c")
        XCTAssertEqual(target("c", .up), "a")
        XCTAssertNil(target("a", .up))
        XCTAssertNil(target("e", .down))
    }

    /// Rows off screen aren't laid out: as many captures on as the row is wide.
    func testFallsBackToTheRowWidthWithoutFrames() {
        let onScreen = ["a": frames["a"]!, "b": frames["b"]!]
        XCTAssertEqual(target("a", .down, frames: onScreen), "c")
        XCTAssertEqual(target("b", .down, frames: onScreen), "d")
        XCTAssertEqual(target("c", .down, frames: [:]), "d")
    }

    func testNothingSelectedStartsAtTheFirst() {
        XCTAssertEqual(target(nil, .down), "a")
        XCTAssertEqual(target("gone", .right), "a")
        XCTAssertNil(GridNavigation.target(from: nil, move: .down, order: [String](), frames: [:]))
    }
}
