import AVFoundation
import AppKit
import CoreImage
import MicroCAMCore
import Quartz

/// Screenshot demo, enabled only by environment variables set by
/// `scripts/make-screenshots.sh`. Still photos stand in for the camera and the
/// app captures its own windows (own windows need no Screen Recording
/// permission). Never active in normal use. `MICROCAM_DEMO_STREAM_PORT` (and
/// optionally `MICROCAM_DEMO_STREAM_PIN`, `MICROCAM_DEMO_STREAM_MODE=imageOnly`)
/// also serves the frames as a live stream for `scripts/stream-smoke.sh`.
/// `MICROCAM_DEMO_MCP_PORT` (and optionally `MICROCAM_DEMO_MCP_TOKEN`) serves
/// the MCP server on 127.0.0.1 with an in-memory token, never the Keychain one.
/// `MICROCAM_DEMO_VIEWER=1` starts in viewer mode instead (no network search).
struct DemoConfig {
    let frames: [URL]
    let root: URL
    let job: String?
    let compare: (URL, URL)?
    let shotsDir: URL?
    var streamPort: Int? = nil
    var streamPIN: String? = nil
    var streamMode: StreamMode? = nil
    var mcpPort: Int? = nil
    var mcpToken: String? = nil
    var viewer = false

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
                          shotsDir: env["MICROCAM_DEMO_SHOTS"].map { URL(fileURLWithPath: $0, isDirectory: true) },
                          streamPort: env["MICROCAM_DEMO_STREAM_PORT"].flatMap { Int($0) },
                          streamPIN: env["MICROCAM_DEMO_STREAM_PIN"],
                          streamMode: env["MICROCAM_DEMO_STREAM_MODE"].flatMap(StreamMode.init(rawValue:)),
                          mcpPort: env["MICROCAM_DEMO_MCP_PORT"].flatMap { Int($0) },
                          mcpToken: env["MICROCAM_DEMO_MCP_TOKEN"],
                          viewer: env["MICROCAM_DEMO_VIEWER"] == "1")
    }

    /// Separate, freshly reset settings domain: the demo never touches real settings.
    func settingsStore() -> SettingsStore {
        let suite = "xyz.vaclavik.microcam.demo"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        let store = SettingsStore(defaults: UserDefaults(suiteName: suite) ?? .standard)
        if viewer {
            var settings = AppSettings()
            settings.appMode = .viewer
            store.save(settings)
        }
        return store
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
        if model.launchMode == .viewer {
            NSApp.activate(ignoringOtherApps: true)
            if let dir = config.shotsDir { Task { await runViewerScript(into: dir) } }
            return
        }
        model.activateDemo(root: config.root, job: config.job, streamPort: config.streamPort, streamPIN: config.streamPIN,
                           streamMode: config.streamMode, mcpPort: config.mcpPort, mcpToken: config.mcpToken)
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
        model.streamHub.offer(frame, adjustments: model.adjustmentsBox.value)
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
        let name = "\(config.job ?? StorageLayout.jobsDisabledPrefix)_2026-09-25_14-24-00.jpg"
        model.message = StatusMessage(text: String(localized: "Saved: \(name)"), isError: false)
        await pause(1.5)
        capture(main, withChildren: true, as: "01-main-window", in: dir)

        // 1b. Side panel scrolled half-way in a shorter window, two photos selected.
        main.setFrame(NSRect(x: 80, y: 80, width: 1100, height: 560), display: true)
        model.message = nil
        let photos = model.library.files.filter { $0.pathExtension.lowercased() == "jpg" }
        model.library.grid = GridSelection(selected: Set(photos.dropFirst(2).prefix(2)))
        await pause(1)
        if let scroll = scrollViews(in: main.contentView).first(where: { $0.convert($0.bounds, to: nil).minX < 50 }) {
            let clip = scroll.contentView
            clip.scroll(to: NSPoint(x: 0, y: (scroll.documentView?.bounds.height ?? 0) / 3))
            scroll.reflectScrolledClipView(clip)
        }
        await pause(1)
        capture(main, withChildren: true, as: "01b-side-panel-scrolled", in: dir)
        model.library.grid = GridSelection()
        main.setFrame(NSRect(x: 80, y: 80, width: 1440, height: 860), display: true)
        await pause(1)

        // 1c. An AI agent at work: its photo message and "Agent is watching" in the subtitle.
        model.mcp.noteAgentWatching()
        model.message = StatusMessage(text: String(localized: "An agent took a photo: \(name)"), isError: false)
        await pause(1.5)
        capture(main, withChildren: true, as: "01c-agent-watching", in: dir)
        model.message = nil

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
        capture(main, withChildren: true, as: "02-image-adjustments", in: dir)
        model.showAdjustments = false
        model.currentAdjustments = .neutral

        // 3. Digital zoom with grid.
        show(frame(2))
        model.gridVisible = true
        model.previewView?.zoom(by: 2.5, anchor: CGPoint(x: 0.55, y: 0.55))
        await pause(1.5)
        capture(main, withChildren: true, as: "03-zoom-and-grid", in: dir)
        model.gridVisible = false
        model.previewView?.resetZoom()

        // 3b–3e. Drawing on the live picture with the mouse, a label, a pointer,
        // the same drawing zoomed in, and a photo that saves a copy with it.
        await drawingScript(main, into: dir)

        // 4. Recording in progress.
        show(frame(0))
        model.startRecording()
        await pause(4)
        capture(main, withChildren: true, as: "04-recording", in: dir)
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
        capture(main, withChildren: true, as: "05-timelapse", in: dir)
        model.showTimelapse = false
        await pause(0.5)
        model.stopTimelapse()
        model.message = nil

        // 6–7. Before/after compare.
        if let (before, after) = config.compare {
            model.compareInitialMode = 1
            model.comparePair = ComparePair(before: before, after: after)
            await pause(2.5)
            capture(main, withChildren: true, as: "06-compare-slider", in: dir)
            model.comparePair = nil
            await pause(1)
            model.compareInitialMode = 0
            model.comparePair = ComparePair(before: before, after: after)
            await pause(2.5)
            capture(main, withChildren: true, as: "07-compare-side-by-side", in: dir)
            model.comparePair = nil
            await pause(1)
        }

        // 8. Move to job.
        model.filesToMove = Array(model.library.files.prefix(2))
        await pause(1.5)
        capture(main, withChildren: true, as: "08-move-to-job", in: dir)
        model.filesToMove = nil
        await pause(1)

        // 8b. Quick Look (Space in the side panel) and 8c. the Markup editor on a photo.
        if let photo = model.library.files.first(where: { $0.pathExtension.lowercased() == "jpg" }) {
            model.library.grid = GridSelection(selected: [photo], anchor: photo)
            model.previewSelection()
            await pause(2)
            if let panel = NSApp.windows.first(where: { $0 is QLPreviewPanel && $0.isVisible }) {
                capture(panel, withChildren: false, as: "08b-quick-look", in: dir)
            }
            model.quickLook.close()
            await pause(1)
            model.markUp(photo)
            await pause(3)
            capture(main, withChildren: true, as: "08c-markup", in: dir)
            // Cancel: the demo never saves a copy.
            if let sheet = main.attachedSheet { main.endSheet(sheet) }
            model.library.grid = GridSelection()
            await pause(1)
        }

        // 9. First launch: where to save.
        model.showFirstRun = true
        await pause(1.5)
        capture(main, withChildren: true, as: "09-first-run", in: dir)
        model.showFirstRun = false
        await pause(1)

        // 10. Every Settings tab, with the optional parts switched on.
        model.settings.webhookEnabled = true
        model.settings.webhookURL = "https://crm.example.com/microcam"
        // In-memory token (see `activateDemo`); the listener stays on loopback.
        model.settings.mcpEnabled = true
        if !model.settings.streamingEnabled { model.settings.streamingEnabled = true }
        let tabs = ["general", "device", "image", "storage", "timelapse", "preview", "integrations", "stream"]
        for (index, tab) in tabs.enumerated() {
            model.settingsTab = tab
            if index == 0 { model.openSettingsRequest += 1 }
            await pause(index == 0 ? 2 : 1.2)
            if let settings = settingsWindow(besides: main) {
                capture(settings, withChildren: false, as: String(format: "10-settings-%d-%@", index + 1, tab), in: dir)
            }
            if tab == "general", let other = model.languageChoices.first(where: { $0 != model.language }) {
                // A language change offers a restart (the demo keeps it in memory only).
                model.language = other
                await pause(1)
                if let settings = settingsWindow(besides: main) {
                    capture(settings, withChildren: false, as: "10-settings-1-general-restart", in: dir)
                }
                model.language = model.launchLanguage
            }
        }
        NSApp.terminate(nil)
    }

    private func drawingScript(_ main: NSWindow, into dir: URL) async {
        guard let overlay = model.previewView?.annotationView else { return }
        var checks: [String] = []
        func check(_ ok: Bool, _ what: String) { checks.append("\(ok ? "ok  " : "FAIL") \(what)") }

        show(frame(0))
        model.isDrawing = true
        model.drawColor = AppModel.drawColors[1]
        await pause(1)
        // Real mouse events through the window: they must reach the overlay, not pan the image.
        model.drawTool = .ellipse
        await pause(0.2)
        drag(in: main, overlay, from: .init(x: 0.52, y: 0.3), to: .init(x: 0.78, y: 0.72))
        model.drawTool = .arrow
        await pause(0.2)
        drag(in: main, overlay, from: .init(x: 0.18, y: 0.2), to: .init(x: 0.45, y: 0.47))
        model.drawColor = AppModel.drawColors[0]
        model.drawTool = .pen
        await pause(0.2)
        drag(in: main, overlay, from: .init(x: 0.15, y: 0.78), to: .init(x: 0.48, y: 0.8), wave: 0.03)
        check(model.board.persistent.map(\.kind) == [.ellipse, .arrow, .pen], "three shapes drawn with the mouse")
        check(model.zoomScale == 1, "drawing did not pan or zoom the image")
        model.drawColor = AppModel.drawColors[1]
        model.drawTool = .text
        model.textSize = .large
        await pause(0.2)
        overlay.beginText(at: .init(x: 0.55, y: 0.17), text: "C12 short")
        overlay.commitText()
        check(model.board.persistent.last?.text == "C12 short", "label added")
        model.drawTool = .pointer
        await pause(0.2)
        drag(in: main, overlay, from: .init(x: 0.25, y: 0.62), to: .init(x: 0.42, y: 0.56), wave: 0.02)
        check(model.board.hasPointers, "pointer on the board")
        await pause(0.3)
        capture(main, withChildren: true, as: "03b-drawing", in: dir)
        await pause(Double(AnnotationBoard.pointerLifetime) + 0.5)
        check(!model.board.hasPointers, "pointer gone after 2.5 s")

        // A click on the label with the text tool edits it.
        model.drawTool = .text
        await pause(0.2)
        if let label = model.board.persistent.last, let p = label.points.first {
            click(in: main, overlay, at: .init(x: p.x + 0.01, y: p.y + 0.02))
        }
        await pause(0.8)
        let editor = overlay.subviews.compactMap { $0 as? NSTextField }.first
        check(editor?.stringValue == "C12 short", "click on a label opens it for editing")
        capture(main, withChildren: true, as: "03c-text-editing", in: dir)
        overlay.cancelText()

        // The drawing stays on the board when zoomed.
        model.isDrawing = false
        model.previewView?.zoom(by: 2, anchor: CGPoint(x: 0.6, y: 0.55))
        await pause(1)
        capture(main, withChildren: true, as: "03d-drawing-zoomed", in: dir)
        model.previewView?.resetZoom()

        // A photo: the original and a copy with the drawing, including a label
        // still being typed (the photo button does not take the focus from it).
        model.isDrawing = true
        model.drawTool = .text
        await pause(0.3)
        overlay.beginText(at: .init(x: 0.1, y: 0.08), text: "R7")
        let before = Set(model.library.files)
        model.takePhoto()
        check(model.board.persistent.contains { $0.text == "R7" }, "a label being typed goes into the photo")
        model.isDrawing = false
        await pause(3)
        capture(main, withChildren: true, as: "03e-photo-with-drawing", in: dir)
        let added = Set(model.library.files).subtracting(before).map(\.lastPathComponent).sorted()
        check(added.count == 2 && added.contains { $0.hasSuffix("_2.jpg") }, "photo and copy saved: \(added)")
        model.clearDrawing()
        check(model.board.isEmpty && overlay.isHidden, "clear all empties the board and hides the overlay")
        model.message = nil
        try? checks.joined(separator: "\n").appending("\n")
            .write(to: dir.appendingPathComponent("demo-checks.txt"), atomically: true, encoding: .utf8)
    }

    /// A drag from `a` to `b` (image points), sent to the window like a real mouse.
    private func drag(in window: NSWindow, _ overlay: AnnotationOverlayView, from a: AnnotationPoint,
                      to b: AnnotationPoint, wave: Double = 0) {
        let steps = 16
        window.sendEvent(mouse(.leftMouseDown, a, overlay, window))
        for i in 1...steps {
            let f = Double(i) / Double(steps)
            let p = AnnotationPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f + (i % 2 == 0 ? wave : -wave))
            window.sendEvent(mouse(.leftMouseDragged, p, overlay, window))
        }
        window.sendEvent(mouse(.leftMouseUp, b, overlay, window))
    }

    private func click(in window: NSWindow, _ overlay: AnnotationOverlayView, at p: AnnotationPoint) {
        window.sendEvent(mouse(.leftMouseDown, p, overlay, window))
        window.sendEvent(mouse(.leftMouseUp, p, overlay, window))
    }

    private func mouse(_ type: NSEvent.EventType, _ p: AnnotationPoint, _ overlay: AnnotationOverlayView,
                       _ window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: overlay.convert(overlay.geometry.viewPoint(p), to: nil),
                           modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                           pressure: type == .leftMouseUp ? 0 : 1)!
    }

    /// Viewer mode before a camera computer is found, and its Settings.
    private func runViewerScript(into dir: URL) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        await pause(1.5)
        guard let main = model.mainWindow else { NSApp.terminate(nil); return }
        main.setFrame(NSRect(x: 80, y: 80, width: 1280, height: 800), display: true)
        await pause(1.5)
        capture(main, withChildren: true, as: "11-viewer", in: dir)
        model.openSettingsRequest += 1
        await pause(2)
        if let settings = settingsWindow(besides: main) {
            capture(settings, withChildren: false, as: "12-viewer-settings", in: dir)
        }
        NSApp.terminate(nil)
    }

    private func scrollViews(in view: NSView?) -> [NSScrollView] {
        guard let view else { return [] }
        return (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }

    /// By its SwiftUI identifier first: the Markup window from 8c can linger
    /// visible and would otherwise be captured instead.
    private func settingsWindow(besides main: NSWindow) -> NSWindow? {
        let candidates = NSApp.windows.filter {
            $0 !== main && $0.isVisible && !String(describing: type(of: $0)).contains("Popover")
        }
        return candidates.first { $0.identifier?.rawValue.contains("Settings") == true } ?? candidates.first
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
