import CoreImage
import Metal
import MicroCAMCore
import Network

/// Viewer registry and broadcaster for both live feeds. Encodes only what
/// someone is watching:
///
/// - **Video** (`/video`): hardware H.264 in fragmented MP4, up to 30 fps,
///   encoded once for every viewer. A viewer that falls behind skips to the
///   next keyframe (`VideoFeedGate`).
/// - **JPEG** (`/stream`), for browsers without Media Source Extensions: at
///   most 15 fps, one frame at a time; a viewer whose previous frame is still
///   being sent simply skips frames.
///
/// Either way a slow Wi-Fi client cannot slow down anyone else or the bench.
final class StreamHub {
    private final class Client {
        let connection: NWConnection
        let feed: LiveFeed
        var busy = false            // JPEG
        var gate = VideoFeedGate()  // video
        var initVersion = -1        // the init segment this viewer has
        var sequence: UInt32 = 0
        var decodeTime: UInt64 = 0
        init(_ connection: NWConnection, feed: LiveFeed) { self.connection = connection; self.feed = feed }
    }

    static let maxFPS = 15.0

    /// Settings → Stream; one size and bit rate for all viewers (each frame is encoded once).
    let quality = LockedValue(StreamQuality.smooth)

    let hasViewers = LockedValue(false)
    /// Called on the main queue with the new viewer count.
    var onViewersChanged: ((Int) -> Void)?

    private let queue: DispatchQueue            // owns `clients` and the video state below
    private let encodeQueue = DispatchQueue(label: "microcam.stream.encode", qos: .utility)
    private var clients: [ObjectIdentifier: Client] = [:]
    private let jpegViewers = LockedValue(false)
    private let videoViewers = LockedValue(false)
    private let encoding = LockedValue(false)
    private var lastOffer: CFAbsoluteTime = 0   // video queue only
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let context: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() { return CIContext(mtlDevice: device, options: [.cacheIntermediates: false]) }
        return CIContext(options: [.cacheIntermediates: false])
    }()

    private let video = VideoStreamEncoder()
    private var initSegment = Data()
    private var initKey: (avcC: Data, width: Int, height: Int)?
    private var initVersion = 0
    private var lastVideoFrame: CFAbsoluteTime = 0
    private var lastKeyframeRequest: CFAbsoluteTime = 0

    init(queue: DispatchQueue) {
        self.queue = queue
        video.onFrame = { [weak self] frame, time in
            self?.queue.async { self?.broadcast(frame, at: time) }
        }
    }

    /// Takes over a connection that asked for `/stream` or `/video`. Callable
    /// from any queue; the client list is only touched on `queue`.
    func add(_ connection: NWConnection, feed: LiveFeed) {
        queue.async { self.register(connection, feed: feed) }
    }

    private func register(_ connection: NWConnection, feed: LiveFeed) {
        let client = Client(connection, feed: feed)
        let id = ObjectIdentifier(connection)
        clients[id] = client
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.queue.async { self?.remove(id) }
            default: break
            }
        }
        // A read that completes means the viewer closed the page.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] _, _, _, _ in
            self?.queue.async { self?.remove(id) }
        }
        switch feed {
        case .mjpeg:
            connection.send(content: MJPEG.responseHead(), completion: .contentProcessed { _ in })
        case .video:
            connection.send(content: MJPEG.videoResponseHead(), completion: .contentProcessed { _ in })
            // The new viewer can start right away instead of at the next regular keyframe.
            video.requestKeyframe()
        }
        publishCount()
    }

    /// Video queue, every camera frame. Cheap unless someone is watching.
    func offer(_ pixelBuffer: CVPixelBuffer, adjustments: ImageAdjustments) {
        if videoViewers.value {
            video.offer(pixelBuffer, adjustments: adjustments, bitRate: quality.value.videoBitsPerSecond)
        }
        guard jpegViewers.value else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastOffer >= 1 / Self.maxFPS, !encoding.value else { return }
        lastOffer = now
        encoding.value = true
        let quality = quality.value
        encodeQueue.async { [weak self] in
            guard let self else { return }
            defer { self.encoding.value = false }
            var image = AdjustmentPipeline.apply(adjustments, to: CIImage(cvPixelBuffer: pixelBuffer))
            if image.extent.width > quality.maxWidth {
                let s = quality.maxWidth / image.extent.width
                image = image.transformed(by: CGAffineTransform(scaleX: s, y: s))
            }
            guard let jpeg = self.context.jpegRepresentation(
                of: image, colorSpace: self.colorSpace,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality.jpegQuality]) else { return }
            let part = MJPEG.part(jpeg: jpeg)
            self.queue.async { self.broadcast(part) }
        }
    }

    func closeAll() {
        queue.async {
            self.clients.values.forEach { $0.connection.cancel() }
            self.clients.removeAll()
            self.publishCount()
        }
    }

    private func broadcast(_ part: Data) {
        for client in clients.values where client.feed == .mjpeg && !client.busy {
            client.busy = true
            client.connection.send(content: part, completion: .contentProcessed { [weak self] error in
                self?.queue.async {
                    client.busy = false
                    if error != nil { self?.remove(ObjectIdentifier(client.connection)) }
                }
            })
        }
    }

    private func broadcast(_ frame: EncodedFrame, at time: CFAbsoluteTime) {
        if initKey.map({ $0 != (frame.avcC, frame.width, frame.height) }) ?? true {
            initKey = (frame.avcC, frame.width, frame.height)
            initSegment = FragmentedMP4.initSegment(width: frame.width, height: frame.height, avcC: frame.avcC)
            initVersion += 1
        }
        // Each viewer has its own gap-free timeline (frames it skipped never
        // existed for it); a frame lasts until the next one, which the
        // interval since the previous frame estimates.
        let interval = lastVideoFrame == 0 ? 1 / VideoStreamEncoder.maxFPS : min(0.5, max(1 / 60, time - lastVideoFrame))
        lastVideoFrame = time
        let duration = UInt32(interval * Double(FragmentedMP4.timescale))
        var needsKeyframe = false

        for client in clients.values where client.feed == .video {
            switch client.gate.admit(isKeyframe: frame.isKeyframe) {
            case .skip: continue
            case .skipAndRequestKeyframe: needsKeyframe = true; continue
            case .send: break
            }
            var payload = Data()
            if client.initVersion != initVersion {
                payload.append(initSegment)
                client.initVersion = initVersion
            }
            client.sequence += 1
            payload.append(FragmentedMP4.fragment(sequence: client.sequence, decodeTime: client.decodeTime,
                                                  duration: duration, sample: frame.data, isKeyframe: frame.isKeyframe))
            client.decodeTime += UInt64(duration)
            client.connection.send(content: payload, completion: .contentProcessed { [weak self] error in
                self?.queue.async {
                    client.gate.sent()
                    if error != nil { self?.remove(ObjectIdentifier(client.connection)) }
                }
            })
        }
        // At most one extra keyframe a second for viewers catching up: keyframes are large.
        if needsKeyframe, time - lastKeyframeRequest >= 1 {
            lastKeyframeRequest = time
            video.requestKeyframe()
        }
    }

    private func remove(_ id: ObjectIdentifier) {
        guard let client = clients.removeValue(forKey: id) else { return }
        client.connection.cancel()
        publishCount()
    }

    private func publishCount() {
        let count = clients.count
        hasViewers.value = count > 0
        jpegViewers.value = clients.values.contains { $0.feed == .mjpeg }
        let watchingVideo = clients.values.contains { $0.feed == .video }
        if videoViewers.value, !watchingVideo {
            video.stop()
            initKey = nil
            lastVideoFrame = 0
        }
        videoViewers.value = watchingVideo
        DispatchQueue.main.async { self.onViewersChanged?(count) }
    }
}
