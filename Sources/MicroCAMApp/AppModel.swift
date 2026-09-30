import AVFoundation
import AppKit
import ImageIO
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
            scheduleSave()
            if settings.pauseWhenHidden != oldValue.pauseWhenHidden {
                lifecycle.update { $0.pauseWhenHidden = settings.pauseWhenHidden }
            }
            if settings.jobContext != oldValue.jobContext || settings.storageRootPath != oldValue.storageRootPath
                || settings.sortByType != oldValue.sortByType { capturesChanged() }
            if settings.streamingEnabled != oldValue.streamingEnabled
                || settings.streamingPort != oldValue.streamingPort { applyStreaming() }
        }
    }
    @Published private(set) var cameraAuthorized: Bool?
    @Published var message: StatusMessage?

    let engine = CaptureEngine()
    /// Camera or viewer, fixed for the life of the process; a change in
    /// Settings takes effect after `relaunch()`.
    let launchMode: AppMode
    lazy var viewer = ViewerModel(settings: { [unowned self] in self.settings },
                                  update: { [unowned self] body in body(&self.settings) })
    let lifecycle = LifecycleMonitor()
    weak var mainWindow: NSWindow?
    private let store: SettingsStore
    /// Set only when launched by `scripts/make-screenshots.sh`.
    let demo = DemoConfig.fromEnvironment()
    private var demoDriver: DemoDriver?

    // Presentation state, owned here so the demo script can drive it.
    @Published var showAdjustments = false
    @Published var showTimelapse = false
    @Published var comparePair: ComparePair?
    @Published var compareInitialMode = 0
    @Published var settingsTab = "device"
    /// Incremented to ask the main window to open Settings (SwiftUI `openSettings`).
    @Published var openSettingsRequest = 0
    private var pendingSave: DispatchWorkItem?

    /// Slider drags change settings dozens of times per second; write them
    /// once they settle (and on a normal quit).
    private func scheduleSave() {
        pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.flushSettings() }
        }
        pendingSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    func flushSettings() {
        pendingSave?.cancel()
        pendingSave = nil
        store.save(settings)
    }

    let adjustmentsBox = LockedValue(ImageAdjustments.neutral)
    let adjustedMode = LockedValue(false)
    let previewRenderer: MetalPreviewRenderer?
    weak var previewView: PreviewContainerView?
    @Published private(set) var renderMode = RenderMode.passthrough
    @Published var gridVisible = false
    @Published private(set) var zoomScale: CGFloat = 1
    private var keyboard: KeyboardMonitor?

    func handle(_ action: ShortcutAction) {
        guard launchMode == .camera else { return }
        switch action {
        case .toggleGrid: gridVisible.toggle()
        case .resetZoom: previewView?.resetZoom()
        case .photo: takePhoto()
        case .toggleRecording: toggleRecording()
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
        // Demo mode has no capture session, so it always uses the Metal view.
        renderMode = a.isNeutral && demo == nil ? .passthrough : .adjusted
        previewRenderer?.invalidate()
    }

    init() {
        previewRenderer = MetalPreviewRenderer(adjustments: adjustmentsBox)
        store = demo?.settingsStore() ?? SettingsStore()
        let loaded = store.load()
        settings = loaded
        launchMode = loaded.appMode
        showFirstRun = settings.storageRoot == nil && launchMode == .camera
        let renderer = previewRenderer
        let adjusted = adjustedMode
        let recorder = self.recorder
        let adjustments = adjustmentsBox
        let hub = streamHub
        engine.onVideoSample = { sampleBuffer in
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                if adjusted.value { renderer?.push(pixelBuffer) }
                hub.offer(pixelBuffer, adjustments: adjustments.value)
            }
            recorder.appendVideo(sampleBuffer, adjustments: adjustments.value)
        }
        streamHub.onViewersChanged = { [weak self] count in
            guard let self else { return }
            self.streamViewers = count
            self.lifecycle.update { $0.streamViewers = count > 0 }
        }
        engine.onAudioSample = { recorder.appendAudio($0) }
        recorder.onFailure = { [weak self] error in
            self?.stopRecording(reason: error.localizedDescription)
        }
        lifecycle.onWillSleep = { [weak self] in
            self?.stopRecording(reason: String(localized: "the Mac went to sleep"))
            self?.stopTimelapse()
        }
        timelapse.onShot = { [weak self] in self?.takePhoto(kind: .timelapse) }
        timelapse.onFinish = { [weak self] in
            guard let self else { return }
            self.lifecycle.update { $0.timelapseRunning = false }
            self.message = StatusMessage(text: String(localized: "Timelapse finished. Photos taken: \(self.timelapse.shotsTaken)."), isError: false)
        }
        lifecycle.update { $0.pauseWhenHidden = settings.pauseWhenHidden }
        lifecycle.onChange = { [weak self] _ in self?.applyLifecycle() }
        engine.onCameraDisconnected = { [weak self] in
            self?.stopRecording(reason: String(localized: "the camera was disconnected"))
            self?.stopTimelapse()
            self?.message = StatusMessage(text: String(localized: "The camera was disconnected. The picture comes back when you connect it again."), isError: true)
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
        checkUnfinishedRecordings()
        capturesChanged()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushSettings() }
        }
        // Files may change in Finder while microCAM is in the background.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.capturesChanged() }
        }
        if let demo {
            demoDriver = DemoDriver(model: self, config: demo)
            demoDriver?.start()
        } else if launchMode == .viewer {
            viewer.start()
        } else {
            Task { await start() }
        }
    }

    /// Demo mode: a fake camera fed with still photos, no permission prompts.
    /// With `streamPort` the stream runs too (no Bonjour, PIN only in memory),
    /// so `scripts/stream-smoke.sh` can check it without a camera.
    func activateDemo(root: URL, job: String?, streamPort: Int? = nil, streamPIN: String? = nil,
                      streamMode: StreamMode? = nil) {
        cameraAuthorized = true
        engine.activateDemo()
        settings.storageRootPath = root.path
        settings.activeJob = job.flatMap(JobCode.init)
        settings.recordAudio = false
        showFirstRun = false
        syncAdjustments()
        capturesChanged()
        // The demo never reads or writes the real photo PIN.
        cachedStreamPIN = .some(streamPIN.flatMap { PinGuard.isValidPIN($0) ? $0 : nil })
        if let streamPort {
            settings.streamingPort = streamPort
            if let streamMode { settings.streamingMode = streamMode }
            settings.streamingEnabled = true
        }
    }

    func attachMainWindow(_ window: NSWindow) {
        mainWindow = window
        // AppKit focuses the job field on launch, which would swallow Space/R/G.
        // Start with no text field focused so the shortcuts work right away.
        DispatchQueue.main.async { window.makeFirstResponder(nil) }
        lifecycle.attach(window: window)
    }

    /// Single place that decides whether the camera runs.
    func applyLifecycle() {
        guard cameraAuthorized == true, demo == nil else { return }
        engine.setRunning(CaptureLifecyclePolicy.shouldRun(lifecycle.state))
    }

    func start() async {
        guard launchMode == .camera else { return }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        cameraAuthorized = granted
        guard granted else { return }
        selectCamera(settings.lastDeviceID)
        applyLifecycle()
        applyStreaming()
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
            case .noStorageRoot: String(localized: "No folder is chosen for saving. Choose one in Settings → Storage.")
            case .noFrame: String(localized: "The camera isn't sending a picture. Check that it's connected.")
            }
        }
    }

    @Published var showFirstRun = false
    @Published private(set) var captureRevision = 0
    private let photoCapturer = PhotoCapturer()
    /// Names handed out but not yet on disk, so two captures in one second never collide.
    private var pendingURLs = Set<URL>()

    /// Where captures go, named in the app's language.
    var layout: StorageLayout? { settings.layout(language: .app) }

    var captureFolder: URL? {
        layout?.baseFolder(for: settings.jobContext)
    }

    func reserveURL(kind: CaptureKind) throws -> URL {
        guard let layout else { throw CaptureError.noStorageRoot }
        let folder = try layout.prepareFolder(for: settings.jobContext, kind: kind)
        let pending = pendingURLs
        let namer = CaptureFileNamer(fileExists: {
            pending.contains($0) || FileManager.default.fileExists(atPath: $0.path)
        })
        let url = namer.nextURL(in: folder, prefix: layout.prefix(for: settings.jobContext), kind: kind, date: Date())
        pendingURLs.insert(url)
        return url
    }

    func releaseURL(_ url: URL) { pendingURLs.remove(url) }

    func capturesChanged() {
        captureRevision += 1
        library.reload(folders: layout?.listedFolders(for: settings.jobContext) ?? [])
    }

    /// `remote` marks a photo requested from the stream page; `completion`
    /// reports the saved file (main queue).
    func takePhoto(kind: CaptureKind = .photo, remote: Bool = false,
                   completion: ((Result<URL, Error>) -> Void)? = nil) {
        guard let frame = engine.latestFrame.value, Date().timeIntervalSince(frame.receivedAt) < 1 else {
            report(CaptureError.noFrame, prefix: String(localized: "Photo not saved"))
            completion?(.failure(CaptureError.noFrame))
            return
        }
        let url: URL
        do {
            url = try reserveURL(kind: kind)
        } catch {
            report(error, prefix: String(localized: "Photo not saved"))
            completion?(.failure(error))
            return
        }
        photoCapturer.capture(frame.pixelBuffer, adjustments: adjustmentsBox.value,
                              quality: settings.jpegQuality, to: url) { [weak self] result in
            guard let self else { return }
            self.releaseURL(url)
            switch result {
            case .success:
                let name = url.lastPathComponent
                self.message = StatusMessage(text: remote ? String(localized: "Photo from another device saved: \(name)")
                                                    : String(localized: "Saved: \(name)"),
                                             isError: false)
                self.capturesChanged()
                completion?(.success(url))
            case .failure(let error):
                self.report(error, prefix: String(localized: "Photo not saved"))
                completion?(.failure(error))
            }
        }
    }

    /// Renders shapes onto a saved capture and stores the result as the next
    /// index of the same timestamp (`…_2.jpg`); the original stays untouched.
    func saveAnnotatedCopy(of source: URL, shapes: [AnnotationShape],
                           completion: @escaping (Result<URL, Error>) -> Void) {
        guard let name = CaptureFileName.parse(source.lastPathComponent) else {
            return completion(.failure(CocoaError(.fileReadInvalidFileName)))
        }
        let pending = pendingURLs
        let destination = CaptureFileNamer(fileExists: {
            pending.contains($0) || FileManager.default.fileExists(atPath: $0.path)
        }).availableURL(in: source.deletingLastPathComponent(), prefix: name.prefix, timestamp: name.timestamp, ext: "jpg")
        pendingURLs.insert(destination)
        let quality = settings.jpegQuality
        Task.detached(priority: .userInitiated) {
            let result: Result<URL, Error> = Result {
                guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(src, 0, nil),
                      let rendered = AnnotationRenderer.render(shapes, onto: image),
                      let dest = CGImageDestinationCreateWithURL(destination as CFURL, "public.jpeg" as CFString, 1, nil)
                else { throw CocoaError(.fileWriteUnknown) }
                CGImageDestinationAddImage(dest, rendered, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
                guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
                return destination
            }
            await MainActor.run {
                self.releaseURL(destination)
                switch result {
                case .success(let url):
                    self.message = StatusMessage(text: String(localized: "Drawing from another device saved: \(url.lastPathComponent)"), isError: false)
                    self.capturesChanged()
                case .failure(let error):
                    self.report(error, prefix: String(localized: "Drawing not saved"))
                }
                completion(result)
            }
        }
    }

    func report(_ error: Error, prefix: String) {
        let detail: String
        switch error {
        case StorageError.rootUnavailable(let url):
            detail = String(localized: "the folder \(url.path) isn't available. Check it in Settings → Storage.")
        case StorageError.cannotCreateFolder(let url):
            detail = String(localized: "can't create the folder \(url.path).")
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
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose the folder where microCAM saves photos and videos")
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
            report(error, prefix: String(localized: "Can't create the folder"))
        }
    }

    func revealCaptureFolder() {
        guard let root = settings.storageRoot else { showFirstRun = true; return }
        let folder = captureFolder ?? root
        let target = FileManager.default.fileExists(atPath: folder.path) ? folder : root
        guard FileManager.default.fileExists(atPath: target.path) else {
            report(StorageError.rootUnavailable(root), prefix: String(localized: "Can't open the folder"))
            return
        }
        NSWorkspace.shared.open(target)
    }

    // MARK: Recording

    @Published private(set) var isRecording = false
    /// Waiting for the microphone before the writer starts.
    @Published private(set) var isStartingRecording = false
    /// Set when the user presses stop while the start is still pending.
    private var pendingStartCancelled = false
    /// The previous file is still being finalized; a new recording must wait.
    @Published private(set) var isFinalizingRecording = false
    @Published private(set) var recordingStartedAt: Date?
    @Published private(set) var droppedFrames = 0
    let recorder = Recorder()
    private var recordingFinalURL: URL?
    private var sleepAssertion: SleepAssertion?
    private var recordingTimer: Timer?

    func toggleRecording() {
        if isRecording {
            stopRecording(reason: nil)
        } else if isStartingRecording {
            pendingStartCancelled = true
        } else {
            startRecording()
        }
    }

    /// Worst status of the staging volume (where the file grows) and the
    /// storage root (where it is moved at the end).
    private func diskStatus() -> DiskSpaceStatus? {
        let volumes = [try? Recorder.stagingDirectory(), settings.storageRoot].compactMap { $0 }
        let bytes = volumes.compactMap {
            try? $0.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage
        }
        guard let lowest = bytes.min() else { return nil }
        return DiskSpacePolicy.status(availableBytes: lowest)
    }

    func startRecording() {
        guard !isRecording, !isStartingRecording else { return }
        guard !isFinalizingRecording else {
            message = StatusMessage(text: String(localized: "Still saving the previous video. Try again in a moment."), isError: false)
            return
        }
        guard settings.storageRoot != nil else { showFirstRun = true; return }
        guard let format = engine.activeFormat, engine.latestFrame.value != nil else {
            report(CaptureError.noFrame, prefix: String(localized: "Recording didn't start"))
            return
        }
        if diskStatus() == .critical {
            message = StatusMessage(text: String(localized: "Recording didn't start: less than 500 MB free on the disk. Free up some space."), isError: true)
            return
        }
        let finalURL: URL
        let stagingURL: URL
        do {
            finalURL = try reserveURL(kind: .video)
            stagingURL = try Recorder.stagingDirectory().appendingPathComponent("\(UUID().uuidString).mov")
        } catch {
            report(error, prefix: String(localized: "Recording didn't start"))
            return
        }
        isStartingRecording = true
        pendingStartCancelled = false
        let begin: (Bool) -> Void = { [weak self] withAudio in
            guard let self else { return }
            self.isStartingRecording = false
            guard !self.pendingStartCancelled else {
                self.pendingStartCancelled = false
                self.releaseURL(finalURL)
                self.engine.setAudioCapture(microphoneID: nil) { _ in }
                self.message = StatusMessage(text: String(localized: "Recording cancelled."), isError: false)
                return
            }
            // The camera may have stopped while waiting for the microphone.
            guard self.engine.latestFrame.value != nil else {
                self.releaseURL(finalURL)
                self.engine.setAudioCapture(microphoneID: nil) { _ in }
                self.report(CaptureError.noFrame, prefix: String(localized: "Recording didn't start"))
                return
            }
            do {
                try self.recorder.start(stagingURL: stagingURL, finalURL: finalURL, format: format,
                                        codec: self.settings.videoCodec, quality: self.settings.videoQuality,
                                        withAudio: withAudio)
            } catch {
                self.releaseURL(finalURL)
                self.engine.setAudioCapture(microphoneID: nil) { _ in }
                self.report(error, prefix: String(localized: "Recording didn't start"))
                return
            }
            self.isRecording = true
            self.recordingStartedAt = Date()
            self.recordingFinalURL = finalURL
            self.droppedFrames = 0
            self.lifecycle.update { $0.recording = true }
            if self.settings.preventSleepWhileRecording {
                self.sleepAssertion = SleepAssertion(reason: String(localized: "microCAM is recording a video"))
            }
            if self.diskStatus() == .low {
                self.message = StatusMessage(text: String(localized: "The disk is almost full. Recording stops at 500 MB free."), isError: true)
            }
            self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.recordingTick() }
            }
        }
        guard settings.recordAudio else { begin(false); return }
        Task {
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                message = StatusMessage(text: String(localized: "Recording without sound: microCAM isn't allowed to use the microphone (System Settings → Privacy & Security)."), isError: true)
                begin(false)
                return
            }
            engine.setAudioCapture(microphoneID: settings.lastMicrophoneID) { [weak self] attached in
                if !attached {
                    self?.message = StatusMessage(text: String(localized: "Recording without sound: the microphone can't be used."), isError: true)
                }
                begin(attached)
            }
        }
    }

    private func recordingTick() {
        droppedFrames = recorder.stats.value.framesDropped
        if diskStatus() == .critical { stopRecording(reason: String(localized: "the disk is full")) }
    }

    func stopRecording(reason: String?) {
        guard isRecording else { return }
        isRecording = false
        isFinalizingRecording = true
        recordingTimer?.invalidate()
        recordingTimer = nil
        sleepAssertion = nil
        let finalURL = recordingFinalURL
        recordingFinalURL = nil
        recorder.stop { [weak self] result in
            guard let self else { return }
            self.isFinalizingRecording = false
            if let finalURL { self.releaseURL(finalURL) }
            self.engine.setAudioCapture(microphoneID: nil) { _ in }
            self.recordingStartedAt = nil
            self.droppedFrames = self.recorder.stats.value.framesDropped
            self.lifecycle.update { $0.recording = false }
            switch result {
            case .success(let url):
                let name = url.lastPathComponent
                let text = reason.map { String(localized: "Recording stopped (\($0)). Video saved: \(name)") }
                    ?? String(localized: "Video saved: \(name)")
                self.message = StatusMessage(text: text, isError: reason != nil)
                self.capturesChanged()
            case .failure(let error):
                self.report(error, prefix: String(localized: "Video not saved"))
            }
        }
    }

    /// Leftovers in the staging folder mean a previous run crashed mid-recording.
    private func checkUnfinishedRecordings() {
        guard let dir = try? Recorder.stagingDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil),
              !files.isEmpty else { return }
        message = StatusMessage(text: String(localized: "Found a recording that wasn't finished. Opening its folder."), isError: true)
        NSWorkspace.shared.open(dir)
    }

    // MARK: Timelapse

    let timelapse = TimelapseRunner()

    func startTimelapse() {
        guard !timelapse.isRunning else { return }
        guard settings.storageRoot != nil else { showFirstRun = true; return }
        guard let schedule = TimelapseSchedule(interval: settings.timelapseInterval,
                                               duration: settings.timelapseDuration) else {
            message = StatusMessage(text: String(localized: "Timelapse didn't start: the interval must be at least 1 second and the duration at least one interval (at most 7 days)."),
                                    isError: true)
            return
        }
        lifecycle.update { $0.timelapseRunning = true }
        timelapse.start(schedule)
    }

    func stopTimelapse() { timelapse.stop() }

    // MARK: Library

    let library = LibraryModel()
    @Published var filesToMove: [URL]?

    @Published private(set) var isMovingFiles = false

    /// Runs off the main thread: a move to another volume copies whole videos.
    func moveFiles(_ urls: [URL], to target: JobContext) {
        guard let layout else { showFirstRun = true; return }
        guard !isMovingFiles else {
            message = StatusMessage(text: String(localized: "Still moving the previous files. Try again in a moment."), isError: false)
            return
        }
        isMovingFiles = true
        message = StatusMessage(text: String(localized: "Moving files: \(urls.count)…"), isError: false)
        Task {
            let outcomes = await Task.detached(priority: .userInitiated) {
                JobFileMover(layout: layout).move(urls, to: target)
            }.value
            isMovingFiles = false
            var moved = 0, skipped = 0
            var failed: [MoveOutcome] = []
            for outcome in outcomes {
                switch outcome.result {
                case .success: moved += 1
                case .failure(.alreadyThere): skipped += 1
                case .failure: failed.append(outcome)
                }
            }
            var parts = [String(localized: "Moved: \(moved)")]
            if skipped > 0 { parts.append(String(localized: "already in that job: \(skipped)")) }
            if let first = failed.first {
                parts.append(String(localized: "failed: \(failed.count) (\(first.source.lastPathComponent))"))
            }
            message = StatusMessage(text: parts.joined(separator: ", "), isError: !failed.isEmpty)
            capturesChanged()
        }
    }

    // MARK: Streaming

    let streamHub = StreamHub(queue: DispatchQueue(label: "microcam.stream"))
    private var streamServer: StreamServer?
    @Published private(set) var streamViewers = 0
    @Published private(set) var streamError: String?
    private var cachedStreamPIN: String?? = nil
    private lazy var streamBackend = StreamBackendAdapter(model: self)

    var streamPIN: String? {
        if case .some(let value) = cachedStreamPIN { return value }
        let value = KeychainToken.read(account: "stream-pin")
        cachedStreamPIN = .some(value)
        return value
    }

    func setStreamPIN(_ pin: String?) {
        let value = pin.flatMap { PinGuard.isValidPIN($0) ? $0 : nil }
        KeychainToken.write(value, account: "stream-pin")
        cachedStreamPIN = .some(value)
    }

    /// Starts, restarts or stops the server to match settings (camera mode only;
    /// a pending switch to viewer mode keeps streaming until the relaunch).
    func applyStreaming() {
        guard launchMode == .camera, settings.streamingEnabled else {
            streamServer?.stop()
            streamServer = nil
            streamError = nil
            return
        }
        if streamServer == nil {
            // The server calls the router on the main queue, so these closures may assume the main actor.
            let router = StreamRouter(backend: streamBackend, mode: { [weak self] in
                MainActor.assumeIsolated { self?.settings.streamingMode ?? .imageOnly }
            }, pin: { [weak self] in
                MainActor.assumeIsolated { self?.streamPIN }
            })
            let server = StreamServer(router: router, hub: streamHub, queue: DispatchQueue(label: "microcam.stream.server"))
            server.onError = { [weak self] in self?.streamError = $0 }
            streamServer = server
        }
        guard StreamPort.isValid(settings.streamingPort) else {
            streamServer?.stop()
            streamError = String(localized: "The port must be a number from 1024 to 65535.")
            return
        }
        // Demo mode stays on loopback and off Bonjour so it never shows up as a real bench.
        streamServer?.start(port: UInt16(settings.streamingPort),
                            serviceName: demo == nil ? (Host.current().localizedName ?? "microCAM") : nil,
                            loopbackOnly: demo != nil)
    }

    /// Addresses shown in Settings → Stream. The demo shows a documentation
    /// address so screenshots never reveal a real network.
    func streamAddresses() -> [String] {
        demo == nil ? NetworkAddresses.streamIPv4() : ["192.0.2.10"]
    }

    // MARK: Viewer mode

    /// Mode changes take effect on a fresh process. The helper waits for this
    /// one to quit, opens the bundle again and, should `open` fail, starts the
    /// executable directly. Quits only when the helper is running; otherwise
    /// the user is told to restart by hand and the app stays open.
    func relaunch() {
        flushSettings()
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app", let executable = Bundle.main.executableURL else {
            return relaunchFailed(String(localized: "microCAM isn't running as an app (.app)."))
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$0\" || exec \"$1\"", bundle.path, executable.path]
        do {
            try process.run()
        } catch {
            return relaunchFailed(error.localizedDescription)
        }
        NSApp.terminate(nil)
    }

    private func relaunchFailed(_ detail: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Couldn't restart microCAM")
        alert.informativeText = detail + "\n" + String(localized: "Quit microCAM and open it again. The change applies on the next start.")
        alert.runModal()
    }

    func showFullScreen(on screen: NSScreen) {
        guard let window = mainWindow else { return }
        if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        window.setFrame(screen.visibleFrame, display: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { window.toggleFullScreen(nil) }
    }

    // MARK: Integrations

    @Published private(set) var isSending = false

    /// Webhook is usable when enabled and the URL is valid http(s).
    var webhookEndpoint: URL? {
        guard settings.webhookEnabled, let raw = settings.webhookURL,
              let url = URL(string: raw.trimmingCharacters(in: .whitespaces)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    /// Sends the given captures one by one; videos only when enabled in Settings.
    func sendToWebhook(_ urls: [URL]) {
        guard let endpoint = webhookEndpoint else {
            message = StatusMessage(text: String(localized: "The webhook isn't set up. Set it up in Settings → Integrations."), isError: true)
            return
        }
        guard !isSending else {
            message = StatusMessage(text: String(localized: "Still sending the previous files. Try again in a moment."), isError: false)
            return
        }
        let files = urls.filter { settings.webhookSendVideos || $0.pathExtension.lowercased() != "mov" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else {
            message = StatusMessage(text: String(localized: "Nothing to send. Sending videos is off in Settings → Integrations."), isError: false)
            return
        }
        isSending = true
        let client = WebhookClient(endpoint: endpoint, token: KeychainToken.read())
        Task {
            var sent = 0
            var failure: String?
            for (index, file) in files.enumerated() {
                message = StatusMessage(text: String(localized: "Sending \(index + 1) of \(files.count)…"), isError: false)
                do {
                    try await client.upload(file: file)
                    sent += 1
                } catch WebhookError.httpStatus(let code) {
                    failure = String(localized: "the server answered with code \(code)")
                    break
                } catch {
                    failure = error.localizedDescription
                    break
                }
            }
            isSending = false
            if let failure {
                message = StatusMessage(text: String(localized: "Sent \(sent) of \(files.count). Error: \(failure)"), isError: true)
            } else {
                message = StatusMessage(text: String(localized: "Files sent: \(sent)"), isError: false)
            }
        }
    }
}
