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

    func testSelfTimerKeys() {
        XCTAssertEqual(ShortcutAction.from(characters: "s", hasModifiers: false, isEditingText: false), .selfTimer)
        XCTAssertEqual(ShortcutAction.from(characters: "S", hasModifiers: false, isEditingText: false), .selfTimer)
        XCTAssertNil(ShortcutAction.from(characters: "s", hasModifiers: false, isEditingText: true))
        XCTAssertNil(ShortcutAction.from(characters: "s", hasModifiers: true, isEditingText: false))
        // Esc cancels the countdown first, even while drawing.
        XCTAssertEqual(ShortcutAction.from(characters: "\u{1b}", hasModifiers: false, isEditingText: false,
                                           isCountingDown: true), .cancelSelfTimer)
        XCTAssertEqual(ShortcutAction.from(characters: "\u{1b}", hasModifiers: false, isEditingText: false,
                                           isDrawing: true, isCountingDown: true), .cancelSelfTimer)
        // Space stays the photo key; AppModel cancels a running countdown with it.
        XCTAssertEqual(ShortcutAction.from(characters: " ", hasModifiers: false, isEditingText: false,
                                           isCountingDown: true), .photo)
    }

    func testCommandCCopiesTheSelection() {
        XCTAssertEqual(ShortcutAction.from(characters: "c", hasModifiers: true, isEditingText: false,
                                           hasSelection: true, isCommandOnly: true), .copySelection)
        // Text being edited, nothing selected or other modifiers: the Edit menu handles it.
        XCTAssertNil(ShortcutAction.from(characters: "c", hasModifiers: true, isEditingText: true,
                                         hasSelection: true, isCommandOnly: true))
        XCTAssertNil(ShortcutAction.from(characters: "c", hasModifiers: true, isEditingText: false,
                                         hasSelection: false, isCommandOnly: true))
        XCTAssertNil(ShortcutAction.from(characters: "c", hasModifiers: true, isEditingText: false,
                                         hasSelection: true, isCommandOnly: false))
        // A plain C is no shortcut.
        XCTAssertNil(ShortcutAction.from(characters: "c", hasModifiers: false, isEditingText: false,
                                         hasSelection: true))
    }

    func testCommandBackspaceMovesTheSelectionToTheTrash() {
        XCTAssertEqual(ShortcutAction.from(characters: "\u{7f}", hasModifiers: true, isEditingText: false,
                                           hasSelection: true, isCommandOnly: true), .trashSelection)
        XCTAssertNil(ShortcutAction.from(characters: "\u{7f}", hasModifiers: true, isEditingText: true,
                                         hasSelection: true, isCommandOnly: true))
        XCTAssertNil(ShortcutAction.from(characters: "\u{7f}", hasModifiers: true, isEditingText: false,
                                         hasSelection: false, isCommandOnly: true))
        // A plain ⌫ deletes nothing.
        XCTAssertNil(ShortcutAction.from(characters: "\u{7f}", hasModifiers: false, isEditingText: false,
                                         hasSelection: true))
    }
}
