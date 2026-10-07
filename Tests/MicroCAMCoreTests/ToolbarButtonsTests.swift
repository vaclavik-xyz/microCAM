import XCTest
@testable import MicroCAMCore

final class ToolbarButtonsTests: XCTestCase {
    func testAllShownByDefault() {
        XCTAssertEqual(AppSettings().hiddenToolbarButtons, [])
        for button in ToolbarButton.allCases {
            XCTAssertTrue(ToolbarButtons.isVisible(button, hidden: [], state: .init()))
        }
    }

    func testHiddenButtonsStayHiddenWhenIdle() {
        let hidden = Set(ToolbarButton.allCases)
        for button in ToolbarButton.allCases {
            XCTAssertFalse(ToolbarButtons.isVisible(button, hidden: hidden, state: .init()), "\(button)")
        }
    }

    /// The stop button and a running timelapse must stay reachable, and a
    /// popover opened from the menu needs its button to point at.
    func testHiddenButtonsComeBackWhileNeeded() {
        let hidden = Set(ToolbarButton.allCases)
        XCTAssertTrue(ToolbarButtons.isVisible(.record, hidden: hidden, state: .init(recording: true)))
        XCTAssertTrue(ToolbarButtons.isVisible(.timelapse, hidden: hidden, state: .init(timelapseRunning: true)))
        XCTAssertTrue(ToolbarButtons.isVisible(.timelapse, hidden: hidden, state: .init(timelapseOpen: true)))
        XCTAssertTrue(ToolbarButtons.isVisible(.adjustments, hidden: hidden, state: .init(adjustmentsOpen: true)))
        XCTAssertTrue(ToolbarButtons.isVisible(.selfTimer, hidden: hidden, state: .init(selfTimerActive: true)))
        XCTAssertFalse(ToolbarButtons.isVisible(.photo, hidden: hidden, state: .init(recording: true)))
    }

    func testHiddenButtonsRoundTripAndSurviveUnknownValues() throws {
        var s = AppSettings()
        s.hiddenToolbarButtons = [.timelapse, .draw]
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data).hiddenToolbarButtons, [.timelapse, .draw])
        // A button a newer version added falls back to all shown, not to lost settings.
        let future = Data(#"{"hiddenToolbarButtons":["draw","laser"],"jpegQuality":0.7}"#.utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: future)
        XCTAssertEqual(decoded.jpegQuality, 0.7)
        XCTAssertEqual(decoded.hiddenToolbarButtons, [])
    }
}
