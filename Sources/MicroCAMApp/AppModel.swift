import AVFoundation
import AppKit
import MicroCAMCore

struct StatusMessage: Equatable {
    let text: String
    let isError: Bool
}

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            store.save(settings)
            if settings.pauseWhenHidden != oldValue.pauseWhenHidden {
                lifecycle.update { $0.pauseWhenHidden = settings.pauseWhenHidden }
            }
        }
    }
    @Published private(set) var cameraAuthorized: Bool?
    @Published var message: StatusMessage?

    let engine = CaptureEngine()
    let lifecycle = LifecycleMonitor()
    weak var mainWindow: NSWindow?
    private let store = SettingsStore()

    let adjustmentsBox = LockedValue(ImageAdjustments.neutral)
    let adjustedMode = LockedValue(false)
    let previewRenderer: MetalPreviewRenderer?
    weak var previewView: PreviewContainerView?
    @Published private(set) var renderMode = RenderMode.passthrough

    /// Adjustments of the current camera; neutral values are not stored.
    var currentAdjustments: ImageAdjustments {
        get { settings.adjustments(forDevice: engine.currentCameraID) }
        set {
            guard let id = engine.currentCameraID else { return }
            let value = newValue.clamped()
            settings.adjustmentsByDevice[id] = value.isNeutral ? nil : value
            syncAdjustments()
        }
    }

    func syncAdjustments() {
        let a = currentAdjustments
        adjustmentsBox.value = a
        adjustedMode.value = !a.isNeutral
        renderMode = a.isNeutral ? .passthrough : .adjusted
        previewRenderer?.invalidate()
    }

    init() {
        previewRenderer = MetalPreviewRenderer(adjustments: adjustmentsBox)
        settings = store.load()
        let renderer = previewRenderer
        let adjusted = adjustedMode
        engine.onVideoSample = { sampleBuffer in
            if adjusted.value, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                renderer?.push(pixelBuffer)
            }
        }
        lifecycle.update { $0.pauseWhenHidden = settings.pauseWhenHidden }
        lifecycle.onChange = { [weak self] _ in self?.applyLifecycle() }
        engine.onCameraDisconnected = { [weak self] in
            self?.message = StatusMessage(text: "Kamera byla odpojena. Po připojení se obraz obnoví.", isError: true)
        }
        engine.onCamerasChanged = { [weak self] in
            guard let self, self.cameraAuthorized == true, self.engine.currentCameraID == nil,
                  !self.engine.cameras.isEmpty else { return }
            self.selectCamera(self.settings.lastDeviceID)
            self.message = nil
            self.applyLifecycle()
        }
        Task { await start() }
    }

    func attachMainWindow(_ window: NSWindow) {
        mainWindow = window
        lifecycle.attach(window: window)
    }

    /// Single place that decides whether the camera runs.
    func applyLifecycle() {
        guard cameraAuthorized == true else { return }
        engine.setRunning(CaptureLifecyclePolicy.shouldRun(lifecycle.state))
    }

    func start() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        cameraAuthorized = granted
        guard granted else { return }
        selectCamera(settings.lastDeviceID)
        applyLifecycle()
    }

    func selectCamera(_ id: String?) {
        let wanted = id.flatMap { settings.lastFormatByDevice[$0] }
        engine.selectCamera(id: id, format: wanted) { [weak self] applied in
            guard let self, let device = self.engine.currentCameraID else { return }
            self.settings.lastDeviceID = device
            if let applied { self.settings.lastFormatByDevice[device] = applied }
            self.syncAdjustments()
        }
    }

    func selectFormat(_ format: FormatChoice) {
        engine.selectCamera(id: engine.currentCameraID, format: format) { [weak self] applied in
            guard let self, let device = self.engine.currentCameraID, let applied else { return }
            self.settings.lastFormatByDevice[device] = applied
            self.syncAdjustments()
        }
    }

    func openPrivacySettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
