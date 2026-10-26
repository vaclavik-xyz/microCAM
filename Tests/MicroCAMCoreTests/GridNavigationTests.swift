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

    /// Rows off screen aren't laid out: rows of the current row's width, each day starting a new row.
    func testFallsBackToRowsWithinEachDayWithoutFrames() {
        let days = [["a", "b", "c"], ["d", "e"]]
        let onScreen = ["a": frames["a"]!, "b": frames["b"]!]
        func target(_ from: String, _ move: GridMove, _ frames: [String: CGRect]) -> String? {
            GridNavigation.target(from: from, move: move, order: order, frames: frames, sections: days)
        }
        XCTAssertEqual(target("a", .down, onScreen), "c")
        XCTAssertEqual(target("b", .down, onScreen), "c")   // the shorter row below: its last tile, not d
        let lastRow = ["c": frames["c"]!, "x": CGRect(x: 110, y: 80, width: 100, height: 70)]
        XCTAssertEqual(target("c", .down, lastRow), "d")    // into the next day's first row
        let nextDay = ["d": frames["d"]!, "e": frames["e"]!]
        XCTAssertEqual(target("e", .up, nextDay), "c")      // the previous day's last row, clamped
        XCTAssertEqual(target("d", .up, nextDay), "c")
        XCTAssertNil(target("a", .up, onScreen))
        XCTAssertNil(target("e", .down, nextDay))
    }

    /// From a day's shorter last row the grid is still as wide as its widest row on screen.
    func testColumnsComeFromTheWidestRow() {
        let days = [["a", "b", "c", "d", "e"], ["f", "g", "h"]]   // three columns: a b c / d e, then f g h
        let order = days.flatMap { $0 }
        let frames: [String: CGRect] = [   // only day 1 on screen, d and e in its short last row
            "a": CGRect(x: 0, y: 0, width: 60, height: 40), "b": CGRect(x: 70, y: 0, width: 60, height: 40),
            "c": CGRect(x: 140, y: 0, width: 60, height: 40),
            "d": CGRect(x: 0, y: 50, width: 60, height: 40), "e": CGRect(x: 70, y: 50, width: 60, height: 40),
        ]
        XCTAssertEqual(GridNavigation.target(from: "e", move: .down, order: order, frames: frames, sections: days), "g")
    }

    func testNothingSelectedStartsAtTheFirst() {
        XCTAssertEqual(target(nil, .down), "a")
        XCTAssertEqual(target("gone", .right), "a")
        XCTAssertNil(GridNavigation.target(from: nil, move: .down, order: [String](), frames: [:]))
    }
}
