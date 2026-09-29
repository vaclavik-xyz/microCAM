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
            if settings.jobContext != oldValue.jobContext || settings.storageRootPath != oldValue.storageRootPath
                || settings.sortByType != oldValue.sortByType { capturesChanged() }
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
    @Published var gridVisible = false
    @Published private(set) var zoomScale: CGFloat = 1
    private var keyboard: KeyboardMonitor?

    func handle(_ action: ShortcutAction) {
        switch action {
        case .toggleGrid: gridVisible.toggle()
        case .resetZoom: previewView?.resetZoom()
        case .photo: takePhoto()
        case .toggleRecording: break // wired in Task 13
        }
    }

    func zoomChanged(_ scale: CGFloat) { zoomScale = scale }

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
        showFirstRun = settings.storageRoot == nil
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
            guard let self, self.cameraAuthorized == true,
                  CameraReselectPolicy.shouldSelect(currentID: self.engine.currentCameraID,
                                                    rememberedID: self.settings.lastDeviceID,
                                                    available: self.engine.cameras.map(\.id)) else { return }
            self.selectCamera(self.settings.lastDeviceID)
            self.message = nil
            self.applyLifecycle()
        }
        keyboard = KeyboardMonitor(isMainWindow: { [weak self] window in
            window != nil && window === self?.mainWindow
        }, handler: { [weak self] action in self?.handle(action) })
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

    // MARK: Storage and photos

    enum CaptureError: LocalizedError {
        case noStorageRoot, noFrame
        var errorDescription: String? {
            switch self {
            case .noStorageRoot: "Není vybraná složka pro ukládání."
            case .noFrame: "Kamera právě nedává obraz."
            }
        }
    }

    @Published var showFirstRun = false
    @Published private(set) var captureRevision = 0
    private let photoCapturer = PhotoCapturer()
    /// Names handed out but not yet on disk, so two captures in one second never collide.
    private var pendingURLs = Set<URL>()

    var captureFolder: URL? {
        settings.layout?.baseFolder(for: settings.jobContext)
    }

    func reserveURL(kind: CaptureKind) throws -> URL {
        guard let layout = settings.layout else { throw CaptureError.noStorageRoot }
        let folder = try layout.prepareFolder(for: settings.jobContext, kind: kind)
        let pending = pendingURLs
        let namer = CaptureFileNamer(fileExists: {
            pending.contains($0) || FileManager.default.fileExists(atPath: $0.path)
        })
        let url = namer.nextURL(in: folder, context: settings.jobContext, kind: kind, date: Date())
        pendingURLs.insert(url)
        return url
    }

    func releaseURL(_ url: URL) { pendingURLs.remove(url) }

    func capturesChanged() { captureRevision += 1 }

    func takePhoto(kind: CaptureKind = .photo) {
        guard let frame = engine.latestFrame.value, Date().timeIntervalSince(frame.receivedAt) < 1 else {
            report(CaptureError.noFrame, prefix: "Fotka neuložena")
            return
        }
        let url: URL
        do {
            url = try reserveURL(kind: kind)
        } catch {
            report(error, prefix: "Fotka neuložena")
            return
        }
        photoCapturer.capture(frame.pixelBuffer, adjustments: adjustmentsBox.value,
                              quality: settings.jpegQuality, to: url) { [weak self] result in
            guard let self else { return }
            self.releaseURL(url)
            switch result {
            case .success:
                self.message = StatusMessage(text: "Uloženo: \(url.lastPathComponent)", isError: false)
                self.capturesChanged()
            case .failure(let error):
                self.report(error, prefix: "Fotka neuložena")
            }
        }
    }

    func report(_ error: Error, prefix: String) {
        let detail: String
        switch error {
        case StorageError.rootUnavailable(let url):
            detail = "složka \(url.path) není dostupná. Zkontroluj ji v Nastavení."
        case StorageError.cannotCreateFolder(let url):
            detail = "nelze vytvořit složku \(url.path)."
        default:
            detail = error.localizedDescription
        }
        message = StatusMessage(text: "\(prefix): \(detail)", isError: true)
    }

    /// Empty input clears the job. Returns false for an invalid code.
    func setActiveJob(_ raw: String) -> Bool {
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.activeJob = nil
            return true
        }
        guard let code = JobCode(raw) else { return false }
        settings.activeJob = code
        return true
    }

    func chooseStorageRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Vybrat"
        panel.message = "Složka, do které bude microCAM ukládat fotky a videa"
        panel.directoryURL = settings.storageRoot
            ?? FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        if panel.runModal() == .OK, let url = panel.url {
            settings.storageRootPath = url.path
            showFirstRun = false
            capturesChanged()
        }
    }

    /// Explicit user choice from the first-run sheet, so creating it is fine.
    func useDefaultStorageRoot() {
        guard let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first else { return }
        let url = pictures.appendingPathComponent("microCAM", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            settings.storageRootPath = url.path
            showFirstRun = false
            capturesChanged()
        } catch {
            report(error, prefix: "Složku nelze vytvořit")
        }
    }

    func revealCaptureFolder() {
        guard let root = settings.storageRoot else { showFirstRun = true; return }
        let folder = captureFolder ?? root
        let target = FileManager.default.fileExists(atPath: folder.path) ? folder : root
        guard FileManager.default.fileExists(atPath: target.path) else {
            report(StorageError.rootUnavailable(root), prefix: "Nelze otevřít")
            return
        }
        NSWorkspace.shared.open(target)
    }
}
