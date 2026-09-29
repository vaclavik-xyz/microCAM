import AVFoundation
import MicroCAMCore

struct DeviceInfo: Identifiable, Hashable {
    let id: String
    let name: String
}

struct LatestFrame {
    let pixelBuffer: CVPixelBuffer
    let receivedAt: Date
}

enum EngineError: LocalizedError {
    case formatUnavailable
    var errorDescription: String? { "Zvolený formát kamera nepodporuje." }
}

/// Owns the AVCaptureSession. All session mutations run on `sessionQueue`;
/// published properties are updated on the main queue.
final class CaptureEngine: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var cameras: [DeviceInfo] = []
    @Published private(set) var microphones: [DeviceInfo] = []
    @Published private(set) var currentCameraID: String?
    @Published private(set) var formats: [FormatChoice] = []
    @Published private(set) var activeFormat: FormatChoice?
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    /// Set once before the session starts; called on the video/audio queue.
    var onVideoSample: ((CMSampleBuffer) -> Void)?
    var onAudioSample: ((CMSampleBuffer) -> Void)?
    /// Called on the main queue.
    var onCamerasChanged: (() -> Void)?
    var onCameraDisconnected: (() -> Void)?

    let latestFrame = LockedValue<LatestFrame?>(nil)

    private let sessionQueue = DispatchQueue(label: "microcam.session")
    private let videoQueue = DispatchQueue(label: "microcam.video", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "microcam.audio", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var demoActive = false

    /// Screenshot demo: pretend a Cam Link is attached; frames are pushed by `DemoDriver`.
    func activateDemo() {
        demoActive = true
        let device = DeviceInfo(id: "demo", name: "Cam Link 4K")
        let format = FormatChoice(width: 1920, height: 1080, fps: 60)
        cameras = [device]
        currentCameraID = device.id
        formats = [format]
        activeFormat = format
        isRunning = true
    }

    override init() {
        super.init()
        // Center Stage runs face detection on every frame and reframes the
        // image; a microscope never wants either. Take control and turn it off.
        AVCaptureDevice.centerStageControlMode = .app
        AVCaptureDevice.isCenterStageEnabled = false
        videoOutput.alwaysDiscardsLateVideoFrames = true
        // Native Cam Link format: no conversion on the way in.
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        audioOutput.setSampleBufferDelegate(self, queue: audioQueue)
        sessionQueue.async {
            self.session.beginConfiguration()
            if self.session.canAddOutput(self.videoOutput) { self.session.addOutput(self.videoOutput) }
            self.session.commitConfiguration()
        }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(deviceConnected(_:)),
                           name: AVCaptureDevice.wasConnectedNotification, object: nil)
        center.addObserver(self, selector: #selector(deviceDisconnected(_:)),
                           name: AVCaptureDevice.wasDisconnectedNotification, object: nil)
        center.addObserver(self, selector: #selector(runtimeError(_:)),
                           name: AVCaptureSession.runtimeErrorNotification, object: session)
        refreshDevices()
    }

    // MARK: Devices

    static func videoDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.external, .builtInWideAngleCamera, .continuityCamera],
                                         mediaType: .video, position: .unspecified).devices
    }

    static func audioDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external],
                                         mediaType: .audio, position: .unspecified).devices
    }

    static func formatChoices(for device: AVCaptureDevice) -> [FormatChoice] {
        var set = Set<FormatChoice>()
        for format in device.formats {
            let d = format.formatDescription.dimensions
            for range in format.videoSupportedFrameRateRanges {
                set.insert(FormatChoice(width: Int(d.width), height: Int(d.height), fps: range.maxFrameRate.rounded()))
            }
        }
        return set.sorted { ($0.width, $0.fps) > ($1.width, $1.fps) }
    }

    /// 1920×1080 at the highest rate up to 60 fps, otherwise the first choice.
    static func defaultChoice(_ choices: [FormatChoice]) -> FormatChoice? {
        choices.filter { $0.width == 1920 && $0.height == 1080 && $0.fps <= 60 }.max { $0.fps < $1.fps }
            ?? choices.first
    }

    func refreshDevices() {
        let cams = Self.videoDevices().map { DeviceInfo(id: $0.uniqueID, name: $0.localizedName) }
        let mics = Self.audioDevices().map { DeviceInfo(id: $0.uniqueID, name: $0.localizedName) }
        DispatchQueue.main.async {
            guard !self.demoActive else { return }
            self.cameras = cams
            self.microphones = mics
            self.onCamerasChanged?()
        }
    }

    /// Selects `id` (or the first external camera, or any camera) with
    /// `format` if supported, else the default format. Completion gets the
    /// applied format on the main queue (nil when no camera is available).
    func selectCamera(id: String?, format: FormatChoice?, completion: @escaping (FormatChoice?) -> Void) {
        sessionQueue.async {
            let devices = Self.videoDevices()
            guard let device = devices.first(where: { $0.uniqueID == id })
                ?? devices.first(where: { $0.deviceType == .external })
                ?? devices.first
            else {
                DispatchQueue.main.async {
                    self.currentCameraID = nil
                    self.formats = []
                    self.activeFormat = nil
                    completion(nil)
                }
                return
            }
            let choices = Self.formatChoices(for: device)
            let target = format.flatMap { choices.contains($0) ? $0 : nil } ?? Self.defaultChoice(choices)
            var applied: FormatChoice?
            var errorText: String?
            self.session.beginConfiguration()
            if let old = self.videoInput { self.session.removeInput(old); self.videoInput = nil }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.videoInput = input
                }
                if let target {
                    try Self.apply(target, to: device)
                    applied = target
                }
            } catch {
                errorText = error.localizedDescription
            }
            self.session.commitConfiguration()
            DispatchQueue.main.async {
                self.currentCameraID = device.uniqueID
                self.formats = choices
                self.activeFormat = applied
                self.lastError = errorText
                completion(applied)
            }
        }
    }

    private static func apply(_ choice: FormatChoice, to device: AVCaptureDevice) throws {
        let is420v = { (f: AVCaptureDevice.Format) in
            CMFormatDescriptionGetMediaSubType(f.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        }
        let sameSize = device.formats.filter {
            let d = $0.formatDescription.dimensions
            return Int(d.width) == choice.width && Int(d.height) == choice.height
        }
        let ordered = sameSize.filter(is420v) + sameSize.filter { !is420v($0) }
        guard let (format, range) = ordered.lazy.compactMap({ f in
            f.videoSupportedFrameRateRanges.first { abs($0.maxFrameRate - choice.fps) < 0.5 }.map { (f, $0) }
        }).first else { throw EngineError.formatUnavailable }
        try device.lockForConfiguration()
        device.activeFormat = format
        device.activeVideoMinFrameDuration = range.minFrameDuration
        device.activeVideoMaxFrameDuration = range.minFrameDuration
        device.unlockForConfiguration()
    }

    // MARK: Running

    func setRunning(_ run: Bool) {
        sessionQueue.async {
            if run, !self.session.isRunning {
                self.session.startRunning()
            } else if !run, self.session.isRunning {
                self.session.stopRunning()
                // Never hand out a frozen frame as a new photo.
                self.latestFrame.value = nil
            }
            let running = self.session.isRunning
            DispatchQueue.main.async { self.isRunning = running }
        }
    }

    /// Adds the microphone (nil removes it). Only attached while recording.
    func setAudioCapture(microphoneID: String?, completion: @escaping (Bool) -> Void) {
        sessionQueue.async {
            self.session.beginConfiguration()
            if let old = self.audioInput { self.session.removeInput(old); self.audioInput = nil }
            if self.session.outputs.contains(self.audioOutput) { self.session.removeOutput(self.audioOutput) }
            var ok = microphoneID == nil
            if let microphoneID {
                let mics = Self.audioDevices()
                if let device = mics.first(where: { $0.uniqueID == microphoneID }) ?? AVCaptureDevice.default(for: .audio) ?? mics.first,
                   let input = try? AVCaptureDeviceInput(device: device),
                   self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.audioInput = input
                    if self.session.canAddOutput(self.audioOutput) {
                        self.session.addOutput(self.audioOutput)
                        ok = true
                    }
                }
            }
            self.session.commitConfiguration()
            DispatchQueue.main.async { completion(ok) }
        }
    }

    // MARK: Notifications

    @objc private func deviceConnected(_ note: Notification) {
        refreshDevices()
    }

    @objc private func deviceDisconnected(_ note: Notification) {
        let gone = (note.object as? AVCaptureDevice)?.uniqueID
        refreshDevices()
        DispatchQueue.main.async {
            if gone != nil, gone == self.currentCameraID {
                self.currentCameraID = nil
                self.latestFrame.value = nil
                self.removeVideoInput(ofDeviceID: gone)
                self.onCameraDisconnected?()
            }
        }
    }

    /// Drops the dead input of an unplugged camera; the camera is added
    /// again by `selectCamera` when it comes back. Checks the device ID at
    /// execution time: a selection queued earlier may already have replaced
    /// the input with a different, working camera.
    private func removeVideoInput(ofDeviceID deviceID: String?) {
        sessionQueue.async {
            guard let input = self.videoInput, input.device.uniqueID == deviceID else { return }
            self.session.beginConfiguration()
            self.session.removeInput(input)
            self.videoInput = nil
            self.session.commitConfiguration()
        }
    }

    @objc private func runtimeError(_ note: Notification) {
        let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error
        DispatchQueue.main.async { self.lastError = error?.localizedDescription ?? "Chyba kamery" }
    }
}

extension CaptureEngine: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if output === videoOutput {
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                latestFrame.value = LatestFrame(pixelBuffer: pixelBuffer, receivedAt: Date())
            }
            onVideoSample?(sampleBuffer)
        } else {
            onAudioSample?(sampleBuffer)
        }
    }
}
