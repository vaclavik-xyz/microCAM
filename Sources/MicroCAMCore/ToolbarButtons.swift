import Foundation

/// Toolbar buttons the user can hide in Settings → Preview. Every action stays
/// in the Camera menu with its shortcut. Settings and the job are always there.
public enum ToolbarButton: String, Codable, CaseIterable, Sendable {
    case photo, record, timelapse, draw, adjustments
}

/// What the button would show right now; a hidden button still appears while
/// it shows something the person needs (a stop button, a running timelapse)
/// or anchors a popover opened from the menu.
public struct ToolbarButtonState: Equatable, Sendable {
    public var recording = false
    /// The self-timer is on or counting down.
    public var selfTimerActive = false
    public var timelapseRunning = false
    public var timelapseOpen = false
    public var adjustmentsOpen = false

    public init(recording: Bool = false, selfTimerActive: Bool = false, timelapseRunning: Bool = false,
                timelapseOpen: Bool = false, adjustmentsOpen: Bool = false) {
        self.recording = recording
        self.selfTimerActive = selfTimerActive
        self.timelapseRunning = timelapseRunning
        self.timelapseOpen = timelapseOpen
        self.adjustmentsOpen = adjustmentsOpen
    }
}

public enum ToolbarButtons {
    public static func isVisible(_ button: ToolbarButton, hidden: Set<ToolbarButton>,
                                 state: ToolbarButtonState) -> Bool {
        guard hidden.contains(button) else { return true }
        switch button {
        case .record: return state.recording
        case .timelapse: return state.timelapseRunning || state.timelapseOpen
        case .adjustments: return state.adjustmentsOpen
        // The self-timer lives in the photo button: on or counting down, it shows.
        case .photo: return state.selfTimerActive
        case .draw: return false
        }
    }
}
