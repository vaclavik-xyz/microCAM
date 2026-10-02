import CoreImage
import Metal
import MicroCAMCore
import Network

/// Viewer registry and MJPEG broadcaster. Encodes only while someone is
/// watching, at most 15 fps, one frame at a time; a viewer whose previous
/// frame is still being sent simply skips frames (never queues them), so a
/// slow Wi-Fi client cannot slow down anyone else or the bench.
final class StreamHub {
    private final class Client {
        let connection: NWConnection
        var busy = false
        init(_ connection: NWConnection) { self.connection = connection }
    }

    static let maxFPS = 15.0

    /// Settings → Stream; one size for all viewers (each frame is encoded once).
    let quality = LockedValue(StreamQuality.smooth)

    let hasViewers = LockedValue(false)
    /// Called on the main queue with the new viewer count.
    var onViewersChanged: ((Int) -> Void)?

    private let queue: DispatchQueue            // owns `clients`
    private let encodeQueue = DispatchQueue(label: "microcam.stream.encode", qos: .utility)
    private var clients: [ObjectIdentifier: Client] = [:]
    private let encoding = LockedValue(false)
    private var lastOffer: CFAbsoluteTime = 0   // video queue only
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let context: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() { return CIContext(mtlDevice: device, options: [.cacheIntermediates: false]) }
        return CIContext(options: [.cacheIntermediates: false])
    }()

    init(queue: DispatchQueue) { self.queue = queue }

    /// Takes over a connection that asked for `/stream`. Callable from any
    /// queue; the client list is only touched on `queue`.
    func add(_ connection: NWConnection) {
        queue.async { self.register(connection) }
    }

    private func register(_ connection: NWConnection) {
        let client = Client(connection)
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
        connection.send(content: MJPEG.responseHead(), completion: .contentProcessed { _ in })
        publishCount()
    }

    /// Video queue, every camera frame. Cheap unless someone is watching.
    func offer(_ pixelBuffer: CVPixelBuffer, adjustments: ImageAdjustments) {
        guard hasViewers.value else { return }
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
        for client in clients.values where !client.busy {
            client.busy = true
            client.connection.send(content: part, completion: .contentProcessed { [weak self] error in
                self?.queue.async {
                    client.busy = false
                    if error != nil { self?.remove(ObjectIdentifier(client.connection)) }
                }
            })
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
        DispatchQueue.main.async { self.onViewersChanged?(count) }
    }
}
