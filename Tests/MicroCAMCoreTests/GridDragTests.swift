import CoreGraphics
import XCTest
@testable import MicroCAMCore

final class GridDragTests: XCTestCase {
    private let order = ["a", "b", "c", "d", "e"]

    func testDragFromAnUnselectedItemSelectsTheRangeToThePointer() {
        var grid = GridSelection<String>(selected: ["e"], anchor: "e")
        XCTAssertTrue(grid.dragSelects(from: "b"))
        grid.drag(from: "b", to: "d", in: order)
        XCTAssertEqual(grid.selected, ["b", "c", "d"])
        XCTAssertEqual(grid.anchor, "b")
        // Back over the start and beyond it, upwards.
        grid.drag(from: "b", to: "a", in: order)
        XCTAssertEqual(grid.selected, ["a", "b"])
        grid.drag(from: "b", to: "b", in: order)
        XCTAssertEqual(grid.selected, ["b"])
        // ⇧-click then extends from where the drag started.
        grid.click("e", in: order, command: false, shift: true)
        XCTAssertEqual(grid.selected, ["b", "c", "d", "e"])
    }

    func testDragFromASelectedItemCarriesTheSelectionOut() {
        let grid = GridSelection<String>(selected: ["b", "c"], anchor: "b")
        XCTAssertFalse(grid.dragSelects(from: "c"))
        XCTAssertTrue(grid.dragSelects(from: "a"))
    }

    func testDragToAnItemNoLongerListedChangesNothing() {
        var grid = GridSelection<String>(selected: ["a"], anchor: "a")
        grid.drag(from: "b", to: "x", in: order)
        XCTAssertEqual(grid.selected, ["a"])
    }

    /// Two rows of two 80×60 tiles, 8 pt apart; a header-sized gap between rows.
    private let frames: [String: CGRect] = [
        "a": CGRect(x: 0, y: 0, width: 80, height: 60), "b": CGRect(x: 88, y: 0, width: 80, height: 60),
        "c": CGRect(x: 0, y: 90, width: 80, height: 60),
    ]

    func testHitTest() {
        XCTAssertEqual(GridHitTest.item(at: CGPoint(x: 10, y: 10), frames: frames), "a")
        XCTAssertEqual(GridHitTest.item(at: CGPoint(x: 100, y: 59), frames: frames), "b")
        // In the gap between a and b: the nearer one.
        XCTAssertEqual(GridHitTest.item(at: CGPoint(x: 82, y: 30), frames: frames), "a")
        XCTAssertEqual(GridHitTest.item(at: CGPoint(x: 86, y: 30), frames: frames), "b")
        // Past the last tile of a row.
        XCTAssertEqual(GridHitTest.item(at: CGPoint(x: 150, y: 120), frames: frames), "c")
        // Between the rows: none.
        XCTAssertNil(GridHitTest.item(at: CGPoint(x: 10, y: 75), frames: frames))
        XCTAssertNil(GridHitTest.item(at: CGPoint(x: 10, y: 10), frames: [String: CGRect]()))
    }
}
