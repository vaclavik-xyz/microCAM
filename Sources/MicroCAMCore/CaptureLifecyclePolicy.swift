public struct CaptureLifecycleState: Equatable, Sendable {
    public var windowVisible = true
    public var screenLocked = false
    public var displayAsleep = false
    public var systemSleeping = false
    public var recording = false
    public var timelapseRunning = false
    /// Someone is watching the live stream; keeps the camera on like a recording.
    public var streamViewers = false
    /// An AI agent pulled a frame over MCP in the last few seconds; like a stream viewer.
    public var agentWatching = false
    public var pauseWhenHidden = true

    public init() {}
}

public enum CaptureLifecyclePolicy {
    /// The camera runs only while someone can see it, unless a recording,
    /// timelapse, stream viewer or agent needs frames. System sleep always stops it (the recorder is
    /// finalized before that).
    public static func shouldRun(_ s: CaptureLifecycleState) -> Bool {
        if s.systemSleeping { return false }
        if s.recording || s.timelapseRunning || s.streamViewers || s.agentWatching { return true }
        if s.screenLocked || s.displayAsleep { return false }
        if s.pauseWhenHidden && !s.windowVisible { return false }
        return true
    }

    /// Work that must keep going while the window is hidden. macOS App Naps
    /// a minimized app: during a bench recording its frames reached the
    /// encoder late and ~1 500 were dropped in a few minutes. While this is
    /// true the app holds a `ProcessInfo` activity that opts out of App Nap.
    public static func needsAppAwake(_ s: CaptureLifecycleState) -> Bool {
        !s.systemSleeping && (s.recording || s.timelapseRunning || s.streamViewers || s.agentWatching)
    }
}
