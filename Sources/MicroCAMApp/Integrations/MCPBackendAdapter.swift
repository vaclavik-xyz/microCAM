import CoreImage
import Metal
import MicroCAMCore

/// Bridges `MCPRouter` (called on the main queue by `HTTPServer`) to the
/// main-actor `AppModel`. Photos and recordings go through the same code as
/// the buttons; only the message over the preview says an agent did it.
final class MCPBackendAdapter: MCPBackend {
    /// A frame older than this is from a camera that stopped.
    private static let freshFrame: TimeInterval = 1
    /// How long to wait for a paused camera to deliver a picture.
    private static let startTimeout: TimeInterval = 5

    private unowned let model: AppModel
    private let encodeQueue = DispatchQueue(label: "microcam.mcp.encode", qos: .userInitiated)
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let context: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() { return CIContext(mtlDevice: device, options: [.cacheIntermediates: false]) }
        return CIContext(options: [.cacheIntermediates: false])
    }()

    init(model: AppModel) { self.model = model }

    func status() -> MCPStatus {
        MainActor.assumeIsolated {
            let engine = model.engine, s = model.settings
            let camera = engine.cameras.first { $0.id == engine.currentCameraID }
            let recording: MCPRecordingState = model.isRecording ? .recording
                : model.isStartingRecording ? .starting : model.isFinalizingRecording ? .saving : .idle
            let timelapse = model.timelapse.isRunning ? model.timelapse.schedule.map {
                MCPTimelapseStatus(shotsTaken: model.timelapse.shotsTaken, shotCount: $0.shotCount)
            } : nil
            return MCPStatus(cameraName: camera.map { s.cameraName(for: $0.id, systemName: $0.name) },
                             format: engine.activeFormat, recording: recording,
                             recordingStartedAt: model.recordingStartedAt, timelapse: timelapse,
                             folder: model.captureFolder?.path, jobsEnabled: s.jobsEnabled,
                             job: s.jobsEnabled ? s.activeJob?.value : nil)
        }
    }

    func captureFolders() -> [URL] {
        MainActor.assumeIsolated { model.layout?.listedFolders(for: model.settings.jobContext) ?? [] }
    }

    func captureFrame(maxDimension: Int, completion: @escaping (Result<MCPImage, MCPToolError>) -> Void) {
        MainActor.assumeIsolated {
            guard model.engine.currentCameraID != nil else { return completion(.failure(.noCamera)) }
            model.mcp.noteAgentWatching()
            let adjustments = model.adjustmentsBox.value
            waitForFrame { [self] frame in
                guard let frame else { return completion(.failure(.noFrame)) }
                encodeQueue.async { [self] in
                    let image = encode(frame.pixelBuffer, adjustments: adjustments, maxDimension: maxDimension)
                    DispatchQueue.main.async { completion(image.map { .success($0) } ?? .failure(.failed("The picture couldn't be encoded."))) }
                }
            }
        }
    }

    func takePhoto(maxDimension: Int, completion: @escaping (Result<MCPSavedPhoto, MCPToolError>) -> Void) {
        MainActor.assumeIsolated {
            guard model.engine.currentCameraID != nil else { return completion(.failure(.noCamera)) }
            guard model.settings.storageRoot != nil else { return completion(.failure(.noStorageFolder)) }
            model.mcp.noteAgentWatching()
            waitForFrame { [self] frame in
                guard frame != nil else { return completion(.failure(.noFrame)) }
                model.takePhoto(source: .agent) { [self] result in
                    switch result {
                    case .success(let url):
                        loadPhoto(url, maxDimension: maxDimension) { image in
                            completion(image.map { MCPSavedPhoto(file: url, image: $0) })
                        }
                    case .failure(let error):
                        completion(.failure(.failed("Photo not saved: \(error.localizedDescription)")))
                    }
                }
            }
        }
    }

    func loadPhoto(_ url: URL, maxDimension: Int, completion: @escaping (Result<MCPImage, MCPToolError>) -> Void) {
        encodeQueue.async {
            let image = JPEGScaler.scaled(contentsOf: url, maxDimension: maxDimension)
            DispatchQueue.main.async {
                completion(image.map { .success($0) } ?? .failure(.failed("The photo \(url.lastPathComponent) can't be read.")))
            }
        }
    }

    func startRecording(completion: @escaping (Result<Void, MCPToolError>) -> Void) {
        MainActor.assumeIsolated {
            if model.isRecording { return completion(.failure(.alreadyRecording)) }
            if model.isStartingRecording { return completion(.failure(.recordingStarting)) }
            if model.isFinalizingRecording { return completion(.failure(.stillSaving)) }
            guard model.engine.currentCameraID != nil else { return completion(.failure(.noCamera)) }
            guard model.settings.storageRoot != nil else { return completion(.failure(.noStorageFolder)) }
            // A hidden window may have paused the camera; keep it on until the recording holds it.
            model.mcp.noteAgentWatching()
            waitForFrame { [self] frame in
                guard frame != nil else { return completion(.failure(.noFrame)) }
                model.startRecording(agent: true) { result in
                    completion(result.mapError { .failed("Recording didn't start: \($0.localizedDescription)") })
                }
            }
        }
    }

    func stopRecording(completion: @escaping (Result<URL, MCPToolError>) -> Void) {
        MainActor.assumeIsolated {
            if model.isStartingRecording { return completion(.failure(.recordingStarting)) }
            guard model.isRecording else { return completion(.failure(.notRecording)) }
            model.stopRecording(reason: nil, agent: true) { result in
                completion(result.mapError { .failed("The video wasn't saved: \($0.localizedDescription)") })
            }
        }
    }

    func setJob(_ job: JobCode?) -> Result<String?, MCPToolError> {
        MainActor.assumeIsolated {
            guard model.settings.jobsEnabled else { return .failure(.jobsDisabled) }
            model.settings.activeJob = job
            model.message = StatusMessage(text: job.map { String(localized: "An agent set the job: \($0.value)") }
                                              ?? String(localized: "An agent cleared the job."), isError: false)
            return .success(model.captureFolder?.path)
        }
    }

    // MARK: Frames

    /// Calls back on the main queue with a frame at most `freshFrame` old,
    /// or nil when the camera sends none within `startTimeout`.
    @MainActor
    private func waitForFrame(since start: Date = Date(), _ completion: @escaping (LatestFrame?) -> Void) {
        if let frame = model.engine.latestFrame.value, Date().timeIntervalSince(frame.receivedAt) < Self.freshFrame {
            return completion(frame)
        }
        guard Date().timeIntervalSince(start) < Self.startTimeout else { return completion(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
            MainActor.assumeIsolated { waitForFrame(since: start, completion) }
        }
    }

    private func encode(_ pixelBuffer: CVPixelBuffer, adjustments: ImageAdjustments, maxDimension: Int) -> MCPImage? {
        var image = AdjustmentPipeline.apply(adjustments, to: CIImage(cvPixelBuffer: pixelBuffer))
        let longest = max(image.extent.width, image.extent.height)
        if longest > CGFloat(maxDimension) {
            let s = CGFloat(maxDimension) / longest
            image = image.transformed(by: CGAffineTransform(scaleX: s, y: s))
        }
        guard let jpeg = context.jpegRepresentation(
            of: image, colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.85]) else { return nil }
        return MCPImage(jpeg: jpeg, width: Int(image.extent.width.rounded()), height: Int(image.extent.height.rounded()))
    }
}
