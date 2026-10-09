/// Single-key shortcuts. Never fire while the user types into a text field
/// (a job code like `PR-2600` contains R and 0). Space previews the selected
/// files instead of taking a photo while the side panel has focus, as in
/// Finder; with nothing selected it still takes a photo, the app's main job.
/// D starts or stops drawing on the picture; Esc stops it, and only then, so
/// Esc keeps its usual meaning otherwise (and cancels a label being typed).
/// ⌘C copies the selected files and ⌘⌫ moves them to the Trash, as in
/// Finder, while no text is being edited (there the keys keep their text
/// meaning).
/// S starts a self-timer countdown; Esc cancels a running one first (Space
/// and S cancel it too, see `AppModel.handle`).
public enum ShortcutAction: Equatable, Sendable {
    case photo, selfTimer, cancelSelfTimer, copySelection, trashSelection, toggleRecording, toggleGrid, resetZoom, quickLook, toggleDrawing, leaveDrawing

    public static func from(characters: String?, hasModifiers: Bool, isEditingText: Bool,
                            inSidePanel: Bool = false, hasSelection: Bool = false,
                            isDrawing: Bool = false, isCountingDown: Bool = false,
                            isCommandOnly: Bool = false) -> ShortcutAction? {
        if isCommandOnly, !isEditingText, hasSelection {
            switch characters?.lowercased() {
            case "c": return .copySelection
            case "\u{7f}": return .trashSelection   // ⌫
            default: break
            }
        }
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
