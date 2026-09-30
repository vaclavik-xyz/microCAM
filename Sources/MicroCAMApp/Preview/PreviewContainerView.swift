import AVFoundation
import AppKit
import MicroCAMCore
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
    let gridView = GridOverlayView()
    var onZoomChange: ((CGFloat) -> Void)?
    private(set) var zoom = ZoomState() {
        didSet {
            applyZoom()
            if zoom.scale != oldValue.scale { onZoomChange?(zoom.scale) }
        }
    }

    init(session: AVCaptureSession, renderer: MetalPreviewRenderer?) {
        self.renderer = renderer
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspect
        super.init(frame: .zero)
        connectionObservation = previewLayer.observe(\.connection) { [weak self] _, _ in
            DispatchQueue.main.async { if let self, let mode = self.mode { self.setMode(mode) } }
        }
        wantsLayer = true
        applyBackdrop()

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
        gridView.isHidden = true
        gridView.autoresizingMask = [.width, .height]
        addSubview(gridView)
    }

    func resetZoom() { zoom.reset() }

    /// Programmatic zoom (demo screenshots); `anchor` is a normalized view point.
    func zoom(by factor: CGFloat, anchor: CGPoint) { zoom.zoom(by: factor, anchor: anchor) }

    private func applyZoom() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.setAffineTransform(zoom.layerTransform(viewSize: bounds.size))
        CATransaction.commit()
        renderer?.zoom = zoom
    }

    override func scrollWheel(with event: NSEvent) {
        let step = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.1
        zoom(at: event, factor: exp(step))
    }

    override func magnify(with event: NSEvent) {
        zoom(at: event, factor: 1 + event.magnification)
    }

    override func mouseDragged(with event: NSEvent) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        // AppKit deltaY is positive downwards; our coordinates are bottom-left.
        zoom.pan(byNormalized: CGPoint(x: event.deltaX / bounds.width, y: -event.deltaY / bounds.height))
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { zoom.reset() }
    }

    private func zoom(at event: NSEvent, factor: CGFloat) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let p = convert(event.locationInWindow, from: nil)
        zoom.zoom(by: factor, anchor: CGPoint(x: p.x / bounds.width, y: p.y / bounds.height))
    }

    private var mode: RenderMode?
    private var windowVisible = true
    private var occlusionObserver: NSObjectProtocol?
    /// The layer's connection appears only once the session runs; re-apply
    /// the enabled state then, or a camera started while the window is
    /// hidden would feed the preview again.
    private var connectionObservation: NSKeyValueObservation?

    private var fullScreenObservers: [NSObjectProtocol] = []

    deinit {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        fullScreenObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func setMode(_ mode: RenderMode) {
        self.mode = mode
        let adjusted = mode == .adjusted && renderer != nil
        renderer?.view.isHidden = !adjusted
        renderer?.setActive(adjusted && windowVisible)
        passthroughHost.isHidden = adjusted
        // A hidden preview layer would still be fed frames; disable its connection.
        // The same while the window is minimized or covered: nothing draws the
        // layer then, its queue fills up and the session started dropping
        // frames for every output — a recording lost a third of its frames
        // while the window was minimized.
        previewLayer.connection?.isEnabled = !adjusted && windowVisible
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        fullScreenObservers.forEach(NotificationCenter.default.removeObserver)
        fullScreenObservers = []
        guard let window else { return }
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in self?.updateWindowVisibility() }
        fullScreenObservers = [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification].map {
            NotificationCenter.default.addObserver(forName: $0, object: window, queue: .main) { [weak self] _ in
                self?.isFullScreen = self?.window?.styleMask.contains(.fullScreen) ?? false
            }
        }
        isFullScreen = window.styleMask.contains(.fullScreen)
        updateWindowVisibility()
    }

    /// Around the picture: the window colour (light in Light Mode), black only
    /// in full screen, where the picture should be alone.
    private var isFullScreen = false {
        didSet { if isFullScreen != oldValue { applyBackdrop() } }
    }

    private func applyBackdrop() {
        let color = isFullScreen ? NSColor.black : NSColor.windowBackgroundColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = color.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBackdrop()
    }

    private func updateWindowVisibility() {
        let visible = window?.occlusionState.contains(.visible) ?? false
        guard visible != windowVisible else { return }
        windowVisible = visible
        if let mode { setMode(mode) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        passthroughHost.frame = bounds
        renderer?.view.frame = bounds
        gridView.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // With a non-identity transform, set bounds/position, never frame.
        contentLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        contentLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        previewLayer.frame = contentLayer.bounds
        CATransaction.commit()
        applyZoom()
    }
}

struct PreviewView: NSViewRepresentable {
    @EnvironmentObject private var model: AppModel

    func makeNSView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView(session: model.engine.session, renderer: model.previewRenderer)
        model.previewView = view
        view.onZoomChange = { [weak model] in model?.zoomChanged($0) }
        view.setMode(model.renderMode)
        return view
    }

    func updateNSView(_ view: PreviewContainerView, context: Context) {
        view.setMode(model.renderMode)
        view.gridView.isHidden = !model.gridVisible
        view.gridView.gridType = model.settings.gridType
        view.gridView.gridColor = model.settings.gridColor
        view.gridView.contentSize = model.engine.activeFormat.map { CGSize(width: $0.width, height: $0.height) }
    }
}
