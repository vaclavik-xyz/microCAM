public struct CaptureLifecycleState: Equatable, Sendable {
    public var windowVisible = true
    public var screenLocked = false
    public var displayAsleep = false
    public var systemSleeping = false
    public var recording = false
    public var timelapseRunning = false
    /// Someone is watching the live stream; keeps the camera on like a recording.
    public var streamViewers = false
    public var pauseWhenHidden = true

    public init() {}
}

public enum CaptureLifecyclePolicy {
    /// The camera runs only while someone can see it, unless a recording,
    /// timelapse or stream viewer needs frames. System sleep always stops it (the recorder is
    /// finalized before that).
    public static func shouldRun(_ s: CaptureLifecycleState) -> Bool {
        if s.systemSleeping { return false }
        if s.recording || s.timelapseRunning || s.streamViewers { return true }
        if s.screenLocked || s.displayAsleep { return false }
        if s.pauseWhenHidden && !s.windowVisible { return false }
        return true
    }
}
