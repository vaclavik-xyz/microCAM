import AVFoundation
import AppKit
import SwiftUI

/// Hosts the preview. Task 8: passthrough only (AVCaptureVideoPreviewLayer,
/// no frame touches the CPU). Tasks 10–11 add the Metal view, zoom and grid.
final class PreviewContainerView: NSView {
    let previewLayer: AVCaptureVideoPreviewLayer
    /// Layer-hosting view: we own its sublayers, AppKit does not reset them.
    private let passthroughHost = NSView()
    /// Parent of the preview layer; zoom transforms are applied to it.
    let contentLayer = CALayer()
    let renderer: MetalPreviewRenderer?

    init(session: AVCaptureSession, renderer: MetalPreviewRenderer?) {
        self.renderer = renderer
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspect
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        passthroughHost.layer = CALayer()
        passthroughHost.wantsLayer = true
        passthroughHost.layer?.masksToBounds = true
        passthroughHost.autoresizingMask = [.width, .height]
        contentLayer.addSublayer(previewLayer)
        passthroughHost.layer?.addSublayer(contentLayer)
        addSubview(passthroughHost)
        if let renderer {
            renderer.view.isHidden = true
            renderer.view.autoresizingMask = [.width, .height]
            addSubview(renderer.view)
        }
    }

    func setMode(_ mode: RenderMode) {
        let adjusted = mode == .adjusted && renderer != nil
        renderer?.view.isHidden = !adjusted
        renderer?.setActive(adjusted)
        passthroughHost.isHidden = adjusted
        // A hidden preview layer would still be fed frames; disable its connection.
        previewLayer.connection?.isEnabled = !adjusted
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        passthroughHost.frame = bounds
        renderer?.view.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // With a non-identity transform, set bounds/position, never frame.
        contentLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        contentLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        previewLayer.frame = contentLayer.bounds
        CATransaction.commit()
    }
}

struct PreviewView: NSViewRepresentable {
    @EnvironmentObject private var model: AppModel

    func makeNSView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView(session: model.engine.session, renderer: model.previewRenderer)
        model.previewView = view
        view.setMode(model.renderMode)
        return view
    }

    func updateNSView(_ view: PreviewContainerView, context: Context) {
        view.setMode(model.renderMode)
    }
}
