import Foundation

/// A JPEG handed to an agent.
public struct MCPImage: Equatable, Sendable {
    public var jpeg: Data
    public var width: Int
    public var height: Int
    public init(jpeg: Data, width: Int, height: Int) { self.jpeg = jpeg; self.width = width; self.height = height }
}

public struct MCPSavedPhoto: Equatable, Sendable {
    public var file: URL
    public var image: MCPImage
    public init(file: URL, image: MCPImage) { self.file = file; self.image = image }
}

public struct MCPTimelapseStatus: Equatable, Sendable {
    public var shotsTaken: Int
    public var shotCount: Int
    public init(shotsTaken: Int, shotCount: Int) { self.shotsTaken = shotsTaken; self.shotCount = shotCount }
}

public enum MCPRecordingState: String, Sendable {
    /// `starting`: waiting for the microphone; `saving`: the previous file is being finished.
    case idle, starting, recording, saving
}

public struct MCPStatus: Equatable, Sendable {
    /// The user's name for the camera; nil when no camera is connected.
    public var cameraName: String?
    public var format: FormatChoice?
    public var recording: MCPRecordingState
    public var recordingStartedAt: Date?
    /// nil when no timelapse runs.
    public var timelapse: MCPTimelapseStatus?
    /// Where new captures go (full path).
    public var folder: String?
    public var jobsEnabled: Bool
    public var job: String?

    public init(cameraName: String?, format: FormatChoice?, recording: MCPRecordingState, recordingStartedAt: Date?,
                timelapse: MCPTimelapseStatus?, folder: String?, jobsEnabled: Bool, job: String?) {
        self.cameraName = cameraName; self.format = format; self.recording = recording
        self.recordingStartedAt = recordingStartedAt; self.timelapse = timelapse; self.folder = folder
        self.jobsEnabled = jobsEnabled; self.job = job
    }
}

/// What went wrong, in a sentence an agent can act on. These are sent to
/// agents, not shown in the app, so they stay in English.
public enum MCPToolError: Error, Equatable, Sendable {
    case noCamera, noFrame, noStorageFolder
    case alreadyRecording, recordingStarting, stillSaving, notRecording
    case jobsDisabled
    case captureNotFound(String)
    case failed(String)

    public var message: String {
        switch self {
        case .noCamera: "No camera is connected to microCAM."
        case .noFrame: "The camera isn't sending a picture. Check that it's connected and try again."
        case .noStorageFolder: "microCAM has no folder for saving yet. Someone at the Mac has to choose one in Settings → Storage."
        case .alreadyRecording: "A recording is already running. Call stop_recording first."
        case .recordingStarting: "A recording is starting (waiting for the microphone). Try again in a moment."
        case .stillSaving: "The previous video is still being saved. Try again in a moment."
        case .notRecording: "No recording is running."
        case .jobsDisabled: "Jobs are turned off in microCAM (Settings → Storage → Use jobs), so there is no job to set."
        case .captureNotFound(let name): "There is no capture named \"\(name)\" in the current folder. Use list_captures to see the names."
        case .failed(let text): text
        }
    }
}

/// The app side of the MCP server. `MCPRouter` calls it on the main queue;
/// completions may be called on any queue.
public protocol MCPBackend: AnyObject {
    func status() -> MCPStatus
    /// Folders listed for the current job, as in the side panel.
    func captureFolders() -> [URL]
    /// The live picture with image adjustments, not saved.
    func captureFrame(maxDimension: Int, completion: @escaping (Result<MCPImage, MCPToolError>) -> Void)
    /// Same as the photo button; the returned image is scaled for the agent.
    func takePhoto(maxDimension: Int, completion: @escaping (Result<MCPSavedPhoto, MCPToolError>) -> Void)
    func loadPhoto(_ url: URL, maxDimension: Int, completion: @escaping (Result<MCPImage, MCPToolError>) -> Void)
    /// Completes once the recording runs (or failed to start).
    func startRecording(completion: @escaping (Result<Void, MCPToolError>) -> Void)
    /// Completes once the video file is saved.
    func stopRecording(completion: @escaping (Result<URL, MCPToolError>) -> Void)
    /// nil clears the job. Returns the folder new captures now go to.
    func setJob(_ job: JobCode?) -> Result<String?, MCPToolError>
}
