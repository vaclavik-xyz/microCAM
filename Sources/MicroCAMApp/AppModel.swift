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

    init() {
        settings = store.load()
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
        }
    }

    func selectFormat(_ format: FormatChoice) {
        engine.selectCamera(id: engine.currentCameraID, format: format) { [weak self] applied in
            guard let self, let device = self.engine.currentCameraID, let applied else { return }
            self.settings.lastFormatByDevice[device] = applied
        }
    }

    func openPrivacySettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
