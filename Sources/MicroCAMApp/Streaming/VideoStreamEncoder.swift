import CoreImage
import Metal
import MicroCAMCore
import VideoToolbox

/// Hardware H.264 for the live stream: low-latency rate control, no frame
/// reordering (every frame comes out as soon as it is encoded), a keyframe at
/// least every 2 s and on request when a viewer joins or falls behind. One
/// encode serves every viewer. Camera frames go to the encoder as they are
/// (no copy) unless adjustments or a picture wider than full HD need a render.
final class VideoStreamEncoder {
    static let maxFPS = 30.0

    /// Called on the encoder's queue with each frame and its capture time.
    var onFrame: ((EncodedFrame, CFAbsoluteTime) -> Void)?

    private let queue = DispatchQueue(label: "microcam.stream.video", qos: .userInitiated)
    private var session: VTCompressionSession?      // queue only
    private var sessionSize = (width: 0, height: 0)
    private var sessionBitRate = 0
    private let inFlight = LockedValue(0)
    private let forceKeyframe = LockedValue(false)
    private var lastOffer: CFAbsoluteTime = 0       // caller's queue only
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private lazy var context: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() { return CIContext(mtlDevice: device, options: [.cacheIntermediates: false]) }
        return CIContext(options: [.cacheIntermediates: false])
    }()

    func requestKeyframe() { forceKeyframe.value = true }

    /// Video queue, every camera frame while someone watches the video stream.
    func offer(_ pixelBuffer: CVPixelBuffer, adjustments: ImageAdjustments, bitRate: Int) {
        let now = CFAbsoluteTimeGetCurrent()
        // A frame at most every 1/30 s, with a little slack for camera timing jitter;
        // two at most waiting in the encoder, so a busy Mac drops frames instead of lagging.
        guard now - lastOffer >= 0.9 / Self.maxFPS, inFlight.value < 2 else { return }
        lastOffer = now
        inFlight.update { $0 += 1 }
        queue.async { [self] in
            guard let buffer = prepare(pixelBuffer, adjustments: adjustments, bitRate: bitRate),
                  let session else { return done() }
            var properties: CFDictionary?
            if forceKeyframe.value {
                forceKeyframe.value = false
                properties = [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue] as CFDictionary
            }
            let status = VTCompressionSessionEncodeFrame(
                session, imageBuffer: buffer, presentationTimeStamp: CMTime(seconds: now, preferredTimescale: 90_000),
                duration: .invalid, frameProperties: properties, infoFlagsOut: nil) { [weak self] status, _, sample in
                    guard let self else { return }
                    self.done()
                    guard status == noErr, let sample, let frame = EncodedFrame(sample) else { return }
                    self.onFrame?(frame, now)
                }
            if status != noErr {
                done()
                invalidate()   // recreated with the next frame
            }
        }
    }

    private func done() { inFlight.update { $0 = max(0, $0 - 1) } }

    /// Frees the hardware encoder when nobody watches.
    func stop() {
        queue.async { self.invalidate() }
    }

    // MARK: Queue

    /// The buffer to encode, at most full HD with even sides, with the
    /// adjustments burnt in; the session matches its size.
    private func prepare(_ source: CVPixelBuffer, adjustments: ImageAdjustments, bitRate: Int) -> CVPixelBuffer? {
        let sourceWidth = CVPixelBufferGetWidth(source), sourceHeight = CVPixelBufferGetHeight(source)
        let scale = min(1, Double(StreamQuality.videoMaxWidth) / Double(sourceWidth))
        let width = Int(Double(sourceWidth) * scale) & ~1, height = Int(Double(sourceHeight) * scale) & ~1
        guard width > 0, height > 0, makeSession(width: width, height: height, bitRate: bitRate), let session else { return nil }
        let direct = adjustments.isNeutral && width == sourceWidth && height == sourceHeight
            && CVPixelBufferGetPixelFormatType(source) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        if direct { return source }

        guard let pool = VTCompressionSessionGetPixelBufferPool(session) else { return nil }
        var output: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output)
        guard let output else { return nil }
        var image = AdjustmentPipeline.apply(adjustments, to: CIImage(cvPixelBuffer: source))
        if scale < 1 {
            image = image.transformed(by: CGAffineTransform(scaleX: Double(width) / Double(sourceWidth),
                                                            y: Double(height) / Double(sourceHeight)))
        }
        context.render(image, to: output, bounds: CGRect(x: 0, y: 0, width: width, height: height), colorSpace: colorSpace)
        return output
    }

    private func makeSession(width: Int, height: Int, bitRate: Int) -> Bool {
        if session != nil, sessionSize == (width, height) {
            if sessionBitRate != bitRate, let session {
                VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitRate as CFNumber)
                sessionBitRate = bitRate
            }
            return true
        }
        invalidate()
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey: width, kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        // Low-latency rate control needs the hardware encoder; without it, a regular real-time session.
        for lowLatency in [true, false] {
            var created: VTCompressionSession?
            let specification: CFDictionary? = lowLatency
                ? [kVTVideoEncoderSpecification_EnableLowLatencyRateControl: kCFBooleanTrue] as CFDictionary : nil
            guard VTCompressionSessionCreate(allocator: nil, width: Int32(width), height: Int32(height),
                                             codecType: kCMVideoCodecType_H264, encoderSpecification: specification,
                                             imageBufferAttributes: attributes as CFDictionary, compressedDataAllocator: nil,
                                             outputCallback: nil, refcon: nil, compressionSessionOut: &created) == noErr,
                  let created else { continue }
            let properties: [CFString: Any] = [
                kVTCompressionPropertyKey_RealTime: kCFBooleanTrue!,
                kVTCompressionPropertyKey_AllowFrameReordering: kCFBooleanFalse!,
                kVTCompressionPropertyKey_ProfileLevel: lowLatency ? kVTProfileLevel_H264_ConstrainedHigh_AutoLevel
                                                                   : kVTProfileLevel_H264_High_AutoLevel,
                kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration: 2 as CFNumber,
                kVTCompressionPropertyKey_ExpectedFrameRate: Self.maxFPS as CFNumber,
                kVTCompressionPropertyKey_AverageBitRate: bitRate as CFNumber,
            ]
            for (key, value) in properties { VTSessionSetProperty(created, key: key, value: value as CFTypeRef) }
            VTCompressionSessionPrepareToEncodeFrames(created)
            session = created
            sessionSize = (width, height)
            sessionBitRate = bitRate
            forceKeyframe.value = false   // a new session starts with one
            return true
        }
        return false
    }

    private func invalidate() {
        guard let session else { return }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        VTCompressionSessionInvalidate(session)
        self.session = nil
        sessionSize = (0, 0)
        inFlight.value = 0
    }
}
