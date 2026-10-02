import Foundation

/// A recording left in the staging folder by a crash, a power cut or an error
/// right after it started. It is written in 10-second fragments, so it plays
/// unless it ended before the first one.
public enum LeftoverRecordingAction: Equatable, Sendable {
    /// Move it to the captures, named by when it was recorded.
    case recover
    /// Nothing can be played back: into the Trash.
    case trash
    /// Playable, but there is no storage folder yet; try again next launch.
    case keep
}

public enum LeftoverRecordingPolicy {
    /// `playableSeconds` is nil when the file can't be played.
    public static func action(playableSeconds: Double?, hasStorage: Bool) -> LeftoverRecordingAction {
        guard let seconds = playableSeconds, seconds > 0 else { return .trash }
        return hasStorage ? .recover : .keep
    }
}
