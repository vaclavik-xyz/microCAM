import XCTest
@testable import MicroCAMCore

final class GridSelectionTests: XCTestCase {
    let order = ["a", "b", "c", "d", "e"]

    func testPlainClickSelectsOnlyThatItem() {
        var s = GridSelection<String>(selected: ["a", "c"], anchor: "a")
        s.click("d", in: order, command: false, shift: false)
        XCTAssertEqual(s.selected, ["d"])
        XCTAssertEqual(s.anchor, "d")
    }

    func testCommandClickToggles() {
        var s = GridSelection<String>(selected: ["a"], anchor: "a")
        s.click("c", in: order, command: true, shift: false)
        XCTAssertEqual(s.selected, ["a", "c"])
        s.click("a", in: order, command: true, shift: false)
        XCTAssertEqual(s.selected, ["c"])
    }

    func testShiftClickSelectsRangeFromAnchorInEitherDirection() {
        var s = GridSelection<String>(selected: ["b"], anchor: "b")
        s.click("d", in: order, command: false, shift: true)
        XCTAssertEqual(s.selected, ["b", "c", "d"])
        s.click("a", in: order, command: false, shift: true)
        XCTAssertEqual(s.selected, ["a", "b"])
        XCTAssertEqual(s.anchor, "b")
    }

    func testShiftClickWithoutAnchorActsLikeClick() {
        var s = GridSelection<String>()
        s.click("c", in: order, command: false, shift: true)
        XCTAssertEqual(s.selected, ["c"])
    }

    func testTargetsOfContextClick() {
        let s = GridSelection<String>(selected: ["a", "b"], anchor: "a")
        XCTAssertEqual(s.targets(forContextClickOn: "b", in: order), ["a", "b"])
        XCTAssertEqual(s.targets(forContextClickOn: "d", in: order), ["d"])
    }
}
