import Foundation

public enum VideoCodec: String, Codable, CaseIterable, Sendable { case hevc, h264 }
public enum VideoQuality: String, Codable, CaseIterable, Sendable { case standard, high }
public enum GridType: String, Codable, CaseIterable, Sendable { case thirds, fine }
public enum GridColor: String, Codable, CaseIterable, Sendable { case white, yellow, green, red }

public struct FormatChoice: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int
    public var fps: Double

    public init(width: Int, height: Int, fps: Double) {
        self.width = width
        self.height = height
        self.fps = fps
    }

    public var label: String { "\(width)×\(height) @ \(Int(fps.rounded())) fps" }
}

public struct AppSettings: Equatable, Sendable {
    public var storageRootPath: String? = nil
    public var sortByType = false
    public var jobsEnabled = true
    public var activeJob: JobCode? = nil
    public var jpegQuality = 0.9
    public var videoCodec = VideoCodec.hevc
    public var videoQuality = VideoQuality.standard
    public var timelapseInterval: TimeInterval = 60
    public var timelapseDuration: TimeInterval = 3600
    public var gridType = GridType.thirds
    public var gridColor = GridColor.white
    public var pauseWhenHidden = true
    public var preventSleepWhileRecording = true
    public var lastDeviceID: String? = nil
    public var lastFormatByDevice: [String: FormatChoice] = [:]
    public var lastMicrophoneID: String? = nil
    public var recordAudio = true
    public var adjustmentsByDevice: [String: ImageAdjustments] = [:]
    /// Generic integration (off by default). The token lives in the Keychain.
    public var webhookEnabled = false
    public var webhookURL: String? = nil
    public var webhookSendVideos = false

    public init() {}

    public var storageRoot: URL? {
        storageRootPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    public var layout: StorageLayout? {
        storageRoot.map { StorageLayout(root: $0, sortByType: sortByType) }
    }

    public var jobContext: JobContext {
        guard jobsEnabled else { return .jobsDisabled }
        return activeJob.map(JobContext.job) ?? .unassigned
    }

    public func adjustments(forDevice id: String?) -> ImageAdjustments {
        id.flatMap { adjustmentsByDevice[$0] } ?? .neutral
    }
}

extension AppSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case storageRootPath, sortByType, jobsEnabled, activeJob, jpegQuality, videoCodec, videoQuality,
             timelapseInterval, timelapseDuration, gridType, gridColor, pauseWhenHidden,
             preventSleepWhileRecording, lastDeviceID, lastFormatByDevice, lastMicrophoneID,
             recordAudio, adjustmentsByDevice, webhookEnabled, webhookURL, webhookSendVideos
    }

    /// Every key is optional so settings from older builds keep working. A
    /// value that fails to decode (e.g. an invalid stored job code) falls back
    /// to its default instead of discarding all settings.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        let d = AppSettings()
        storageRootPath = value(.storageRootPath, d.storageRootPath)
        sortByType = value(.sortByType, d.sortByType)
        jobsEnabled = value(.jobsEnabled, d.jobsEnabled)
        activeJob = value(.activeJob, d.activeJob)
        jpegQuality = value(.jpegQuality, d.jpegQuality)
        videoCodec = value(.videoCodec, d.videoCodec)
        videoQuality = value(.videoQuality, d.videoQuality)
        timelapseInterval = value(.timelapseInterval, d.timelapseInterval)
        timelapseDuration = value(.timelapseDuration, d.timelapseDuration)
        gridType = value(.gridType, d.gridType)
        gridColor = value(.gridColor, d.gridColor)
        pauseWhenHidden = value(.pauseWhenHidden, d.pauseWhenHidden)
        preventSleepWhileRecording = value(.preventSleepWhileRecording, d.preventSleepWhileRecording)
        lastDeviceID = value(.lastDeviceID, d.lastDeviceID)
        lastFormatByDevice = value(.lastFormatByDevice, d.lastFormatByDevice)
        lastMicrophoneID = value(.lastMicrophoneID, d.lastMicrophoneID)
        recordAudio = value(.recordAudio, d.recordAudio)
        adjustmentsByDevice = value(.adjustmentsByDevice, d.adjustmentsByDevice)
        webhookEnabled = value(.webhookEnabled, d.webhookEnabled)
        webhookURL = value(.webhookURL, d.webhookURL)
        webhookSendVideos = value(.webhookSendVideos, d.webhookSendVideos)
    }
}
