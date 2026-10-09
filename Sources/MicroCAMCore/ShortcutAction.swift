/// Single-key shortcuts. Never fire while the user types into a text field
/// (a job code like `PR-2600` contains R and 0). Space previews the selected
/// files instead of taking a photo while the side panel has focus, as in
/// Finder; with nothing selected it still takes a photo, the app's main job.
/// D starts or stops drawing on the picture; Esc stops it, and only then, so
/// Esc keeps its usual meaning otherwise (and cancels a label being typed).
/// S starts a self-timer countdown; Esc cancels a running one first (Space
/// and S cancel it too, see `AppModel.handle`).
public enum ShortcutAction: Equatable, Sendable {
    case photo, selfTimer, cancelSelfTimer, toggleRecording, toggleGrid, resetZoom, quickLook, toggleDrawing, leaveDrawing

    public static func from(characters: String?, hasModifiers: Bool, isEditingText: Bool,
                            inSidePanel: Bool = false, hasSelection: Bool = false,
                            isDrawing: Bool = false, isCountingDown: Bool = false) -> ShortcutAction? {
        guard !hasModifiers, !isEditingText, let characters else { return nil }
        switch characters.lowercased() {
        case " ": return inSidePanel && hasSelection ? .quickLook : .photo
        case "s": return .selfTimer
        case "r": return .toggleRecording
        case "g": return .toggleGrid
        case "0": return .resetZoom
        case "d": return .toggleDrawing
        case "\u{1b}": return isCountingDown ? .cancelSelfTimer : isDrawing ? .leaveDrawing : nil
        default: return nil
        }
    }
}
