import CoreImage
import MetalKit
import MicroCAMCore

enum RenderMode { case passthrough, adjusted }

/// Adjusted preview: CIImage → filters → rendered by a Metal-backed CIContext
/// straight into the drawable. No CGImage, no GPU→CPU readback. Draws only
/// when a new frame, zoom or adjustment arrived.
final class MetalPreviewRenderer: NSObject, MTKViewDelegate {
    let view: MTKView
    var zoom = ZoomState() { didSet { invalidate() } }

    private let queue: MTLCommandQueue
    private let context: CIContext
    private let adjustments: LockedValue<ImageAdjustments>
    private let latestImage = LockedValue<CIImage?>(nil)
    private let dirty = LockedValue(false)
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    init?(adjustments: LockedValue<ImageAdjustments>) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.queue = queue
        self.adjustments = adjustments
        context = CIContext(mtlCommandQueue: queue, options: [.cacheIntermediates: false])
        view = MTKView(frame: .zero, device: device)
        super.init()
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.isPaused = true
        view.delegate = self
    }

    func setActive(_ active: Bool) {
        view.isPaused = !active
        if !active { latestImage.value = nil }
        invalidate()
    }

    /// Video queue.
    func push(_ pixelBuffer: CVPixelBuffer) {
        latestImage.value = CIImage(cvPixelBuffer: pixelBuffer)
        dirty.value = true
    }

    func invalidate() { dirty.value = true }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { invalidate() }

    func draw(in view: MTKView) {
        guard dirty.value, let source = latestImage.value,
              let drawable = view.currentDrawable, let buffer = queue.makeCommandBuffer() else { return }
        dirty.value = false
        let size = view.drawableSize
        let adjusted = AdjustmentPipeline.apply(adjustments.value, to: source)
        let e = adjusted.extent
        let fit = min(size.width / e.width, size.height / e.height)
        let fitted = adjusted
            .transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
            .transformed(by: CGAffineTransform(scaleX: fit, y: fit))
            .transformed(by: CGAffineTransform(translationX: (size.width - e.width * fit) / 2,
                                               y: (size.height - e.height * fit) / 2))
            .transformed(by: zoom.absoluteTransform(viewSize: size))
        let canvas = CGRect(origin: .zero, size: size)
        let image = fitted.composited(over: CIImage(color: .black).cropped(to: canvas)).cropped(to: canvas)
        let destination = CIRenderDestination(width: Int(size.width), height: Int(size.height),
                                              pixelFormat: view.colorPixelFormat, commandBuffer: buffer) {
            drawable.texture
        }
        destination.colorSpace = colorSpace
        _ = try? context.startTask(toRender: image, to: destination)
        buffer.present(drawable)
        buffer.commit()
    }
}
