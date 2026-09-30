import AVFoundation
import CoreImage
import Metal
import MicroCAMCore
import os

private let log = Logger(subsystem: "xyz.vaclavik.microcam", category: "recorder")

enum RecorderError: LocalizedError {
    case cannotStart(String)
    case noFrames
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cannotStart(let d): String(localized: "Recording can't start: \(d)")
        case .noFrames: String(localized: "No frames were recorded. Check that the camera sends a picture.")
        case .failed(let d): String(localized: "Recording failed: \(d)")
        }
    }
}

/// AVAssetWriter-based recorder. `appendVideo`/`appendAudio` are called on
/// the capture queues; all mutable state is guarded by `lock`.
final class Recorder {
    struct Stats { var framesWritten = 0; var framesDropped = 0 }

    let stats = LockedValue(Stats())
    /// Called on the main queue once when the writer fails mid-recording.
    var onFailure: ((Error) -> Void)?

    private let lock = NSLock()
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var startTime: CMTime?
    private var stagingURL: URL?
    private var finalURL: URL?
    private var size = CGSize.zero
    private var failureReported = false
    private let context: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() { return CIContext(mtlDevice: device, options: [.cacheIntermediates: false]) }
        return CIContext(options: [.cacheIntermediates: false])
    }()
    private let videoColorSpace = CGColorSpace(name: CGColorSpace.itur_709)!

    static func stagingDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("microCAM/Recording", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func start(stagingURL: URL, finalURL: URL, format: FormatChoice, codec: VideoCodec,
               quality: VideoQuality, withAudio: Bool) throws {
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: stagingURL, fileType: .mov)
        } catch {
            throw RecorderError.cannotStart(ErrorDetails.describe(error))
        }
        writer.movieFragmentInterval = CMTime(seconds: 10, preferredTimescale: 600)

        let video = AVAssetWriterInput(mediaType: .video, outputSettings: VideoEncoding.videoSettings(
            codec: codec, quality: quality, width: format.width, height: format.height, fps: format.fps))
        video.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: format.width,
            kCVPixelBufferHeightKey as String: format.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ])
        guard writer.canAdd(video) else { throw RecorderError.cannotStart("video input") }
        writer.add(video)

        var audio: AVAssetWriterInput?
        if withAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: VideoEncoding.audioSettings)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                audio = input
            }
        }
        guard writer.startWriting() else {
            throw RecorderError.cannotStart(ErrorDetails.describe(writer.error, fallback: "writer"))
        }

        lock.lock()
        self.writer = writer
        self.videoInput = video
        self.audioInput = audio
        self.adaptor = adaptor
        self.startTime = nil
        self.stagingURL = stagingURL
        self.finalURL = finalURL
        self.size = CGSize(width: format.width, height: format.height)
        self.failureReported = false
        lock.unlock()
        stats.value = Stats()
    }

    func appendVideo(_ sampleBuffer: CMSampleBuffer, adjustments: ImageAdjustments) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        lock.lock()
        guard let writer, let videoInput, let adaptor else { lock.unlock(); return }
        guard writer.status == .writing else { reportFailureLocked(writer); lock.unlock(); return }
        if startTime == nil {
            writer.startSession(atSourceTime: pts)
            startTime = pts
        }
        guard videoInput.isReadyForMoreMediaData else {
            lock.unlock()
            stats.update { $0.framesDropped += 1 }
            return
        }
        let pool = adaptor.pixelBufferPool
        let size = self.size
        lock.unlock()

        // Render outside the lock so a slow GPU frame never blocks audio appends.
        var output = pixelBuffer
        if !adjustments.isNeutral {
            var rendered: CVPixelBuffer?
            guard let pool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &rendered) == kCVReturnSuccess,
                  let rendered else {
                stats.update { $0.framesDropped += 1 }
                return
            }
            let image = AdjustmentPipeline.apply(adjustments, to: CIImage(cvPixelBuffer: pixelBuffer))
            context.render(image, to: rendered, bounds: CGRect(origin: .zero, size: size), colorSpace: videoColorSpace)
            CVBufferPropagateAttachments(pixelBuffer, rendered)
            output = rendered
        }

        lock.lock()
        defer { lock.unlock() }
        // The recording may have been stopped (or restarted) while rendering.
        guard self.adaptor === adaptor, writer.status == .writing else { return }
        if adaptor.append(output, withPresentationTime: pts) {
            stats.update { $0.framesWritten += 1 }
        } else {
            reportFailureLocked(writer)
        }
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let writer, writer.status == .writing, let audioInput, let startTime,
              CMSampleBufferGetPresentationTimeStamp(sampleBuffer) >= startTime,
              audioInput.isReadyForMoreMediaData else { return }
        if !audioInput.append(sampleBuffer) {
            reportFailureLocked(writer)
        }
    }

    func stop(completion: @escaping (Result<URL, Error>) -> Void) {
        lock.lock()
        let writer = self.writer, video = videoInput, audio = audioInput
        let started = startTime != nil, staging = stagingURL, final = finalURL
        self.writer = nil; videoInput = nil; audioInput = nil; adaptor = nil; startTime = nil
        lock.unlock()

        guard let writer, let staging, let final else { return }
        guard started, writer.status == .writing else {
            let error: Error
            if started {
                // No cancelWriting(): it may delete the output file.
                // The writer failed mid-recording. Keep the file: movie
                // fragments make it playable up to the last one written.
                log.error("writer not writing at stop: \(ErrorDetails.describe(writer.error), privacy: .public)")
                error = RecorderError.failed(String(localized: "the file was left in \(staging.path) (\(ErrorDetails.describe(writer.error)))"))
            } else {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: staging)
                error = RecorderError.noFrames
            }
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }
        video?.markAsFinished()
        audio?.markAsFinished()
        writer.finishWriting {
            let result: Result<URL, Error>
            if writer.status == .completed {
                do {
                    try FileManager.default.moveItem(at: staging, to: final)
                    result = .success(final)
                } catch {
                    result = .failure(RecorderError.failed(String(localized: "the file was left in \(staging.path) (\(error.localizedDescription))")))
                }
            } else {
                log.error("finishWriting failed: \(ErrorDetails.describe(writer.error), privacy: .public)")
                result = .failure(RecorderError.failed(ErrorDetails.describe(writer.error)))
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func reportFailureLocked(_ writer: AVAssetWriter) {
        guard !failureReported else { return }
        failureReported = true
        log.error("writer failed while recording: \(ErrorDetails.describe(writer.error), privacy: .public)")
        let error = RecorderError.failed(ErrorDetails.describe(writer.error, fallback: String(localized: "writing the file failed")))
        DispatchQueue.main.async { self.onFailure?(error) }
    }
}
