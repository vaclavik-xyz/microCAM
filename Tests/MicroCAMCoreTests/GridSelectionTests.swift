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

    func testPreviewOfOneItemBrowsesTheWholeGrid() {
        let s = GridSelection<String>(selected: ["c"], anchor: "c")
        let preview = s.previewItems(in: order)
        XCTAssertEqual(preview?.items, order)
        XCTAssertEqual(preview?.start, 2)
    }

    func testPreviewOfSeveralItemsShowsOnlyThoseFromTheLastClicked() {
        let s = GridSelection<String>(selected: ["d", "b"], anchor: "d")
        let preview = s.previewItems(in: order)
        XCTAssertEqual(preview?.items, ["b", "d"])
        XCTAssertEqual(preview?.start, 1)
        // Anchor outside the selection (⌘-click removed it): start at the first one.
        XCTAssertEqual(GridSelection<String>(selected: ["b", "d"], anchor: "c").previewItems(in: order)?.start, 0)
    }

    func testNoPreviewWithoutSelection() {
        XCTAssertNil(GridSelection<String>().previewItems(in: order))
        XCTAssertNil(GridSelection<String>(selected: ["gone"]).previewItems(in: order))
    }
}
