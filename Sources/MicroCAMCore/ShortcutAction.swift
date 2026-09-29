/// Single-key shortcuts. Never fire while the user types into a text field
/// (a job code like `PR-2600` contains R and 0).
public enum ShortcutAction: Equatable, Sendable {
    case photo, toggleRecording, toggleGrid, resetZoom

    public static func from(characters: String?, hasModifiers: Bool, isEditingText: Bool) -> ShortcutAction? {
        guard !hasModifiers, !isEditingText, let characters else { return nil }
        switch characters.lowercased() {
        case " ": return .photo
        case "r": return .toggleRecording
        case "g": return .toggleGrid
        case "0": return .resetZoom
        default: return nil
        }
    }
}
