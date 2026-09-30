import AVFoundation
import AppKit
import CoreImage
import MicroCAMCore

/// Screenshot demo, enabled only by environment variables set by
/// `scripts/make-screenshots.sh`. Still photos stand in for the camera and the
/// app captures its own windows (own windows need no Screen Recording
/// permission). Never active in normal use.
struct DemoConfig {
    let frames: [URL]
    let root: URL
    let job: String?
    let compare: (URL, URL)?
    let shotsDir: URL?

    static func fromEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) -> DemoConfig? {
        let urls = { (key: String) in
            (env[key] ?? "").split(separator: ":").map { URL(fileURLWithPath: String($0)) }
        }
        let frames = urls("MICROCAM_DEMO_FRAMES")
        guard !frames.isEmpty, let root = env["MICROCAM_DEMO_ROOT"] else { return nil }
        let pair = urls("MICROCAM_DEMO_COMPARE")
        return DemoConfig(frames: frames,
                          root: URL(fileURLWithPath: root, isDirectory: true),
                          job: env["MICROCAM_DEMO_JOB"],
                          compare: pair.count == 2 ? (pair[0], pair[1]) : nil,
                          shotsDir: env["MICROCAM_DEMO_SHOTS"].map { URL(fileURLWithPath: $0, isDirectory: true) })
    }

    /// Separate, freshly reset settings domain: the demo never touches real settings.
    func settingsStore() -> SettingsStore {
        let suite = "xyz.vaclavik.microcam.demo"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return SettingsStore(defaults: UserDefaults(suiteName: suite) ?? .standard)
    }
}

@MainActor
final class DemoDriver {
    private unowned let model: AppModel
    private let config: DemoConfig
    private let context = CIContext()
    private var frame: CVPixelBuffer?
    private var timer: Timer?

    init(model: AppModel, config: DemoConfig) {
        self.model = model
        self.config = config
    }

    func start() {
        model.activateDemo(root: config.root, job: config.job)
        NSApp.activate(ignoringOtherApps: true)
        show(config.frames[0])
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pushFrame() }
        }
        if let dir = config.shotsDir {
            Task { await runScript(into: dir) }
        }
    }

    private func show(_ url: URL) {
        guard let image = CIImage(contentsOf: url) else { return }
        let width = Int(image.extent.width), height = Int(image.extent.height)
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary, &buffer)
        guard let buffer else { return }
        context.render(image, to: buffer)
        frame = buffer
        pushFrame()
    }

    /// Feeds the still frame through the same paths as the camera, including
    /// the recorder (as a timestamped sample buffer), so recording works too.
    private func pushFrame() {
        guard let frame else { return }
        model.engine.latestFrame.value = LatestFrame(pixelBuffer: frame, receivedAt: Date())
        model.previewRenderer?.push(frame)
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: frame, formatDescriptionOut: &format)
        guard let format else { return }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 10),
                                        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: frame, formatDescription: format,
                                                 sampleTiming: &timing, sampleBufferOut: &sample)
        if let sample { model.recorder.appendVideo(sample, adjustments: model.adjustmentsBox.value) }
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func frame(_ index: Int) -> URL { config.frames[min(index, config.frames.count - 1)] }

    // MARK: Script

    private func runScript(into dir: URL) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        await pause(1.5)
        guard let main = model.mainWindow else { NSApp.terminate(nil); return }
        main.setFrame(NSRect(x: 80, y: 80, width: 1440, height: 860), display: true)
        await pause(1.5)

        // 1. Main window: live image, job, side panel.
        model.message = StatusMessage(text: "Uloženo: \(config.job ?? "microcam")_2026-09-25_14-24-00.jpg", isError: false)
        await pause(1.5)
        capture(main, withChildren: true, as: "01-hlavni-okno", in: dir)

        // 2. Image adjustments popover on a warmer, punchier picture.
        show(frame(1))
        var adjustments = ImageAdjustments.neutral
        adjustments.contrast = 1.15
        adjustments.saturation = 1.3
        adjustments.temperature = 7300
        adjustments.sharpness = 0.6
        model.currentAdjustments = adjustments
        model.message = nil
        model.showAdjustments = true
        await pause(2)
        capture(main, withChildren: true, as: "02-upravy-obrazu", in: dir)
        model.showAdjustments = false
        model.currentAdjustments = .neutral

        // 3. Digital zoom with grid.
        show(frame(2))
        model.gridVisible = true
        model.previewView?.zoom(by: 2.5, anchor: CGPoint(x: 0.55, y: 0.55))
        await pause(1.5)
        capture(main, withChildren: true, as: "03-zoom-a-mrizka", in: dir)
        model.gridVisible = false
        model.previewView?.resetZoom()

        // 4. Recording in progress.
        show(frame(0))
        model.startRecording()
        await pause(4)
        capture(main, withChildren: true, as: "04-nahravani", in: dir)
        model.stopRecording(reason: nil)
        await pause(2)
        model.message = nil

        // 5. Timelapse running.
        show(frame(3))
        model.settings.timelapseInterval = 30
        model.settings.timelapseDuration = 3600
        model.startTimelapse()
        model.showTimelapse = true
        await pause(2)
        capture(main, withChildren: true, as: "05-casosber", in: dir)
        model.showTimelapse = false
        await pause(0.5)
        model.stopTimelapse()
        model.message = nil

        // 6–7. Before/after compare.
        if let (before, after) = config.compare {
            model.compareInitialMode = 1
            model.comparePair = ComparePair(before: before, after: after)
            await pause(2.5)
            capture(main, withChildren: true, as: "06-porovnani-posuvnik", in: dir)
            model.comparePair = nil
            await pause(1)
            model.compareInitialMode = 0
            model.comparePair = ComparePair(before: before, after: after)
            await pause(2.5)
            capture(main, withChildren: true, as: "07-porovnani-vedle-sebe", in: dir)
            model.comparePair = nil
            await pause(1)
        }

        // 8. Settings → storage.
        model.settingsTab = "storage"
        model.openSettingsRequest += 1
        await pause(2)
        if let settings = NSApp.windows.first(where: {
            $0 !== main && $0.isVisible && !String(describing: type(of: $0)).contains("Popover")
        }) {
            capture(settings, withChildren: false, as: "08-nastaveni-ukladani", in: dir)
        }
        NSApp.terminate(nil)
    }

    // MARK: Capture

    private typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    /// `CGWindowListCreateImage` is unavailable in the macOS 15 SDK headers but
    /// still works for the app's own windows; resolve it at runtime.
    private let createImage: CreateImage? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(symbol, to: CreateImage.self)
    }()

    private func image(of window: NSWindow) -> CGImage? {
        // kCGWindowListOptionIncludingWindow, kCGWindowImageBoundsIgnoreFraming | kCGWindowImageBestResolution
        createImage?(.null, 1 << 3, UInt32(window.windowNumber), (1 << 0) | (1 << 3))?.takeRetainedValue()
    }

    /// Composites the window with its sheet and popovers onto a soft backdrop.
    private func capture(_ window: NSWindow, withChildren: Bool, as name: String, in dir: URL) {
        var windows = [window]
        if withChildren {
            windows += (window.childWindows ?? []).filter(\.isVisible)
            if let sheet = window.attachedSheet { windows.append(sheet) }
            windows += NSApp.windows.filter {
                $0.isVisible && !windows.contains($0) && String(describing: type(of: $0)).contains("Popover")
            }
        }
        let margin: CGFloat = 48, scale: CGFloat = 2
        let union = windows.map(\.frame).reduce(window.frame) { $0.union($1) }.insetBy(dx: -margin, dy: -margin)
        let width = Int(union.width * scale), height = Int(union.height * scale)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        let colors = [NSColor(calibratedRed: 0.20, green: 0.23, blue: 0.30, alpha: 1).cgColor,
                      NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.13, alpha: 1).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(height)), end: CGPoint(x: CGFloat(width), y: 0), options: [])
        }
        for w in windows {
            guard let img = image(of: w) else { continue }
            let rect = CGRect(x: (w.frame.minX - union.minX) * scale, y: (w.frame.minY - union.minY) * scale,
                              width: w.frame.width * scale, height: w.frame.height * scale)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 40, color: NSColor.black.withAlphaComponent(0.5).cgColor)
            ctx.draw(img, in: rect)
            ctx.restoreGState()
        }
        guard let result = ctx.makeImage(),
              let png = NSBitmapImageRep(cgImage: result).representation(using: .png, properties: [:]) else { return }
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
