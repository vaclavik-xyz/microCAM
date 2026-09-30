/// Single-key shortcuts. Never fire while the user types into a text field
/// (a job code like `PR-2600` contains R and 0). Space previews the selected
/// files instead of taking a photo while the side panel has focus, as in
/// Finder; with nothing selected it still takes a photo, the app's main job.
public enum ShortcutAction: Equatable, Sendable {
    case photo, toggleRecording, toggleGrid, resetZoom, quickLook

    public static func from(characters: String?, hasModifiers: Bool, isEditingText: Bool,
                            inSidePanel: Bool = false, hasSelection: Bool = false) -> ShortcutAction? {
        guard !hasModifiers, !isEditingText, let characters else { return nil }
        switch characters.lowercased() {
        case " ": return inSidePanel && hasSelection ? .quickLook : .photo
        case "r": return .toggleRecording
        case "g": return .toggleGrid
        case "0": return .resetZoom
        default: return nil
        }
    }
}
