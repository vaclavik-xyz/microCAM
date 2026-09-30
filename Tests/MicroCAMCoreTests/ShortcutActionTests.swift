import XCTest
@testable import MicroCAMCore

final class ShortcutActionTests: XCTestCase {
    func testMapping() {
        XCTAssertEqual(ShortcutAction.from(characters: " ", hasModifiers: false, isEditingText: false), .photo)
        XCTAssertEqual(ShortcutAction.from(characters: "r", hasModifiers: false, isEditingText: false), .toggleRecording)
        XCTAssertEqual(ShortcutAction.from(characters: "R", hasModifiers: false, isEditingText: false), .toggleRecording)
        XCTAssertEqual(ShortcutAction.from(characters: "g", hasModifiers: false, isEditingText: false), .toggleGrid)
        XCTAssertEqual(ShortcutAction.from(characters: "0", hasModifiers: false, isEditingText: false), .resetZoom)
    }
    func testTypingInJobFieldNeverTriggers() {
        for ch in ["P", "R", "-", "2", "6", "0", "g", " "] {
            XCTAssertNil(ShortcutAction.from(characters: ch, hasModifiers: false, isEditingText: true), ch)
        }
    }
    func testModifiersAndUnknownKeysIgnored() {
        XCTAssertNil(ShortcutAction.from(characters: "r", hasModifiers: true, isEditingText: false))
        XCTAssertNil(ShortcutAction.from(characters: "x", hasModifiers: false, isEditingText: false))
        XCTAssertNil(ShortcutAction.from(characters: nil, hasModifiers: false, isEditingText: false))
    }

    func testSpaceInSidePanelPreviewsTheSelectionInsteadOfTakingAPhoto() {
        XCTAssertEqual(ShortcutAction.from(characters: " ", hasModifiers: false, isEditingText: false,
                                           inSidePanel: true, hasSelection: true), .quickLook)
        XCTAssertEqual(ShortcutAction.from(characters: " ", hasModifiers: false, isEditingText: false,
                                           inSidePanel: false, hasSelection: true), .photo)
        // Other single keys keep working while the panel has focus.
        XCTAssertEqual(ShortcutAction.from(characters: "r", hasModifiers: false, isEditingText: false,
                                           inSidePanel: true, hasSelection: true), .toggleRecording)
    }
    func testSpaceInSidePanelWithoutSelectionTakesAPhoto() {
        XCTAssertEqual(ShortcutAction.from(characters: " ", hasModifiers: false, isEditingText: false,
                                           inSidePanel: true, hasSelection: false), .photo)
    }

    func testDrawingKeys() {
        XCTAssertEqual(ShortcutAction.from(characters: "d", hasModifiers: false, isEditingText: false), .toggleDrawing)
        XCTAssertEqual(ShortcutAction.from(characters: "D", hasModifiers: false, isEditingText: false), .toggleDrawing)
        XCTAssertNil(ShortcutAction.from(characters: "d", hasModifiers: false, isEditingText: true))
        XCTAssertEqual(ShortcutAction.from(characters: "\u{1b}", hasModifiers: false, isEditingText: false,
                                           isDrawing: true), .leaveDrawing)
        // Esc keeps its usual meaning (leave full screen, close a sheet) when not drawing,
        // and cancels the label being typed while drawing.
        XCTAssertNil(ShortcutAction.from(characters: "\u{1b}", hasModifiers: false, isEditingText: false))
        XCTAssertNil(ShortcutAction.from(characters: "\u{1b}", hasModifiers: false, isEditingText: true,
                                         isDrawing: true))
    }
}
