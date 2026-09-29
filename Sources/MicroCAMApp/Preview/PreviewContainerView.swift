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

    init(session: AVCaptureSession) {
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        passthroughHost.frame = bounds
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
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewContainerView {
        PreviewContainerView(session: session)
    }

    func updateNSView(_ view: PreviewContainerView, context: Context) {}
}
