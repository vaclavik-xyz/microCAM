import AppIntents
import MicroCAMCore

// Actions for the Shortcuts app, Spotlight and Siri: a shortcut on a key, a
// Stream Deck or a foot pedal takes a photo without touching the Mac. They go
// through the same code as the buttons. `scripts/make-app.sh` compiles their
// metadata (Metadata.appintents); without it Shortcuts doesn't see them.

struct TakePhotoIntent: AppIntent {
    static let title = LocalizedStringResource("Take photo")
    static let description = IntentDescription(LocalizedStringResource("Takes a photo into the current folder and returns it. With a delay, the self-timer counts down on the Mac first."))

    /// The self-timer countdown in seconds; 0 takes the photo right away.
    @Parameter(title: LocalizedStringResource("Delay"),
               description: LocalizedStringResource("Seconds of self-timer countdown before the photo. 0 takes it right away."),
               default: 0, inclusiveRange: (0, 30))   // SelfTimer.maxDelay; the metadata needs a literal
    var delay: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Take photo after \(\.$delay) seconds")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let model = try ShortcutAccess.cameraModel()
        let url: URL = try await ShortcutAccess.holdingCamera(model) {
            // On this Mac, like the photo button: the countdown shows over the
            // picture. A busy or cancelled self-timer fails with its own message.
            try await withCheckedThrowingContinuation { continuation in
                model.takePhoto(after: delay) { continuation.resume(with: $0) }
            }
        }
        return .result(value: IntentFile(fileURL: url))
    }
}

struct StartRecordingIntent: AppIntent {
    static let title = LocalizedStringResource("Start recording")
    static let description = IntentDescription(LocalizedStringResource("Starts a video in the current folder."))

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = try ShortcutAccess.cameraModel()
        if model.isRecording || model.isStartingRecording { throw ShortcutError.alreadyRecording }
        if model.isFinalizingRecording { throw ShortcutError.stillSaving }
        try await ShortcutAccess.holdingCamera(model) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                model.startRecording { continuation.resume(with: $0) }
            }
        }
        return .result()
    }
}

struct StopRecordingIntent: AppIntent {
    static let title = LocalizedStringResource("Stop recording")
    static let description = IntentDescription(LocalizedStringResource("Stops the video and returns it once it is saved."))

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let model = try ShortcutAccess.cameraModel()
        guard model.isRecording else { throw ShortcutError.notRecording }
        let url: URL = try await withCheckedThrowingContinuation { continuation in
            model.stopRecording(reason: nil) { continuation.resume(with: $0) }
        }
        return .result(value: IntentFile(fileURL: url))
    }
}

struct SetJobIntent: AppIntent {
    static let title = LocalizedStringResource("Set job")
    static let description = IntentDescription(LocalizedStringResource("New photos and videos go into the job's folder. Leave it empty for no job."))

    @Parameter(title: LocalizedStringResource("Job"))
    var job: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Set job to \(\.$job)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // Only settings: works without a camera, like the job button.
        let model = try ShortcutAccess.appModel()
        guard model.settings.jobsEnabled else { throw ShortcutError.jobsDisabled }
        guard model.setActiveJob(job ?? "") else { throw ShortcutError.invalidJob }
        return .result()
    }
}

/// Listed in Spotlight and the Shortcuts app without any setup.
struct MicroCAMShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TakePhotoIntent(),
                    phrases: ["Take a photo with \(.applicationName)", "\(.applicationName) photo"],
                    shortTitle: LocalizedStringResource("Take photo"), systemImageName: "camera")
        AppShortcut(intent: StartRecordingIntent(),
                    phrases: ["Start recording in \(.applicationName)"],
                    shortTitle: LocalizedStringResource("Start recording"), systemImageName: "record.circle")
        AppShortcut(intent: StopRecordingIntent(),
                    phrases: ["Stop recording in \(.applicationName)"],
                    shortTitle: LocalizedStringResource("Stop recording"), systemImageName: "stop.circle")
    }
}

enum ShortcutError: Error, CustomLocalizedStringResourceConvertible {
    case notRunning, viewerMode, noCamera, noStorageFolder, noPicture, alreadyRecording, notRecording,
         stillSaving, jobsDisabled, invalidJob

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notRunning: LocalizedStringResource("microCAM isn't ready yet. Try again in a moment.")
        case .viewerMode: LocalizedStringResource("microCAM is in viewer mode. Switch to camera mode in Settings → General.")
        case .noCamera: LocalizedStringResource("No camera connected.")
        case .noStorageFolder: LocalizedStringResource("Choose where to save photos and videos in microCAM first.")
        case .noPicture: LocalizedStringResource("The camera sends no picture. Check it in microCAM.")
        case .alreadyRecording: LocalizedStringResource("microCAM is already recording.")
        case .notRecording: LocalizedStringResource("microCAM isn't recording.")
        case .stillSaving: LocalizedStringResource("microCAM is still saving the previous video. Try again in a moment.")
        case .jobsDisabled: LocalizedStringResource("Jobs are off. Turn them on in Settings → Storage.")
        case .invalidJob: LocalizedStringResource("Use only letters, digits and hyphens.")
        }
    }
}

@MainActor
private enum ShortcutAccess {
    /// How long to wait for a paused camera to deliver a picture.
    static let startTimeout: TimeInterval = 5

    static func appModel() throws -> AppModel {
        guard let model = AppModel.current else { throw ShortcutError.notRunning }
        guard model.launchMode == .camera else { throw ShortcutError.viewerMode }
        return model
    }

    static func cameraModel() throws -> AppModel {
        let model = try appModel()
        guard model.engine.currentCameraID != nil else { throw ShortcutError.noCamera }
        guard model.settings.storageRoot != nil else { throw ShortcutError.noStorageFolder }
        return model
    }

    /// Keeps the camera on (a hidden window pauses it) and waits for a fresh
    /// picture before `body`; a recording holds the camera itself afterwards.
    static func holdingCamera<T>(_ model: AppModel, _ body: () async throws -> T) async throws -> T {
        model.lifecycle.update { $0.shortcutRunning = true }
        defer { model.lifecycle.update { $0.shortcutRunning = false } }
        let frame = await withCheckedContinuation { continuation in
            model.waitForFrame(timeout: startTimeout) { continuation.resume(returning: $0) }
        }
        guard frame != nil else { throw ShortcutError.noPicture }
        return try await body()
    }
}
