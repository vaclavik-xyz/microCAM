import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if model.launchMode == .viewer {
                ViewerView(viewer: model.viewer)
                    .background(WindowAccessor { model.attachMainWindow($0) })
            } else {
                cameraBody
            }
        }
        .onChange(of: model.openSettingsRequest) { openSettings() }
    }

    /// Sidebar width and visibility survive a relaunch.
    @AppStorage("sidebarVisible") private var sidebarVisible = true
    private let sidebarWidth = UserDefaults.standard.object(forKey: "sidebarWidth") as? Double ?? 200

    private var cameraBody: some View {
        NavigationSplitView(columnVisibility: Binding(
            get: { sidebarVisible ? .all : .detailOnly },
            set: { sidebarVisible = $0 != .detailOnly }
        )) {
            SidePanel(library: model.library, compare: $model.comparePair)
                .navigationSplitViewColumnWidth(min: 150, ideal: sidebarWidth, max: 420)
                .background(GeometryReader { proxy in
                    Color.clear.onChange(of: proxy.size.width) { _, width in
                        if width >= 150 { UserDefaults.standard.set(Double(width), forKey: "sidebarWidth") }
                    }
                })
        } detail: {
            ZStack {
                PreviewView()
                CameraStateOverlay(engine: model.engine)
                if model.zoomScale > 1.01 {
                    Text(String(format: "%.1f×", model.zoomScale))
                        .font(.caption.monospacedDigit()).padding(6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(12)
                }
                if model.isDrawing {
                    DrawingPalette()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                // Above the palette while drawing.
                MessageToast()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(16)
                    .padding(.bottom, model.isDrawing ? 52 : 0)
            }
            .animation(.easeOut(duration: 0.2), value: model.message)
            .animation(.easeOut(duration: 0.2), value: model.isDrawing)
            .frame(minWidth: 400)
            .background(WindowAccessor { model.attachMainWindow($0) })
        }
        .modifier(WindowTitle(engine: model.engine, timelapse: model.timelapse, mcp: model.mcp))
        .importsItemProviders([.image]) { model.importPhotos($0) }
        // Customizable (right-click the toolbar → Customize Toolbar…): every
        // item can be removed, all actions stay in the menu bar with shortcuts.
        // The id keeps the user's choice across launches; changing it resets it.
        .toolbar(id: "main") {
            if model.settings.jobsEnabled {
                ToolbarItem(id: "job", placement: .navigation) { JobToolbarButton() }
            }
            // Separate items, not a ControlGroup: each button keeps its own
            // popover anchor (a popover on a button inside a toolbar
            // ControlGroup never appears, one on the group points at its middle).
            ToolbarItem(id: "photo", placement: .principal) {
                Button { model.takePhoto() } label: { Label("Take photo", systemImage: "camera") }
                    .help("Take a photo (Space)")
            }
            ToolbarItem(id: "record", placement: .principal) { RecordButton() }
            ToolbarItem(id: "timelapse", placement: .principal) {
                TimelapseToolbarButton(runner: model.timelapse, show: $model.showTimelapse)
            }
            ToolbarItem(id: "draw", placement: .primaryAction) {
                Toggle(isOn: $model.isDrawing) { Label("Draw", systemImage: "pencil.tip.crop.circle") }
                    .toggleStyle(.button)
                    .help("Draw on the picture (D)")
            }
            if model.streamViewers > 0 {
                // Status, not an action: it can't be removed.
                ToolbarItem(id: "viewers", placement: .primaryAction) {
                    Label("Watching: \(model.streamViewers)", systemImage: "dot.radiowaves.left.and.right")
                        .labelStyle(.titleAndIcon).foregroundStyle(.secondary)
                        .help("Watching now")
                }
                .customizationBehavior(.disabled)
            }
            ToolbarItem(id: "adjustments", placement: .primaryAction) {
                Button { model.showAdjustments.toggle() } label: {
                    Label("Image adjustments", systemImage: "slider.horizontal.3")
                }
                .help("Image adjustments")
                .popover(isPresented: $model.showAdjustments) {
                    // Titled like the timelapse and job popovers.
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Image adjustments").font(.headline)
                        AdjustmentsForm()
                    }
                    .padding(16).frame(width: 360)
                }
            }
            ToolbarItem(id: "settings", placement: .primaryAction) {
                SettingsLink { Label("Settings", systemImage: "gearshape") }
                    .help("Settings (⌘,)")
            }
        }
        .sheet(isPresented: $model.showFirstRun) {
            FirstRunView().interactiveDismissDisabled()
        }
        .sheet(item: Binding(
            get: { model.filesToMove.map { MoveRequest(files: $0) } },
            set: { if $0 == nil { model.filesToMove = nil } }
        )) { request in
            MoveToJobSheet(files: request.files)
        }
        .sheet(item: $model.comparePair) { pair in
            CompareView(before: pair.before, after: pair.after, initialMode: model.compareInitialMode)
        }
    }
}

/// Title: the camera the picture comes from (the user's name for it, if set).
/// Subtitle: its format (unless turned off in Settings → Preview); while recording "🔴 Recording 0:12:34" (and dropped
/// frames), then "Saving video…"; a running timelapse adds its progress, and
/// "Agent is watching" shows while an AI agent pulls frames over MCP.
/// This is the only recording indicator besides the red stop button, so the
/// picture stays clean. The app name stays in the menu bar and Dock.
private struct WindowTitle: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var engine: CaptureEngine
    @ObservedObject var timelapse: TimelapseRunner
    @ObservedObject var mcp: MCPController
    /// Ticks once a second while recording, to advance the time.
    @State private var now = Date()
    /// In @State so one timer survives re-evaluation; a `let` would create a
    /// new one on every redraw and could keep resetting it before it fires.
    @State private var tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    func body(content: Content) -> some View {
        content
            .navigationTitle(engine.cameras.first { $0.id == engine.currentCameraID }
                .map { model.settings.cameraName(for: $0.id, systemName: $0.name) }
                ?? String(localized: "No camera"))
            .navigationSubtitle(subtitle)
            .onReceive(tick) { date in if model.isRecording { now = date } }
    }

    private var subtitle: String {
        var parts: [String] = []
        if model.isRecording, let started = model.recordingStartedAt {
            let seconds = max(0, Int(now.timeIntervalSince(started)))
            let time = String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            parts.append(String(localized: "🔴 Recording \(time)"))
            if model.droppedFrames > 0 { parts.append(String(localized: "Dropped frames: \(model.droppedFrames)")) }
        } else if model.isFinalizingRecording {
            parts.append(String(localized: "Saving video…"))
        }
        if timelapse.isRunning, let schedule = timelapse.schedule {
            parts.append(String(localized: "Timelapse \(timelapse.shotsTaken) of \(schedule.shotCount)"))
        }
        if parts.isEmpty, model.settings.showFormatInTitle, let format = engine.activeFormat {
            parts.append(format.label)
        }
        if mcp.agentWatching { parts.append(String(localized: "Agent is watching")) }
        return parts.joined(separator: " · ")
    }
}

/// Message over the preview when there is nothing to show.
struct CameraStateOverlay: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var engine: CaptureEngine

    var body: some View {
        if model.cameraAuthorized == false {
            VStack(spacing: 12) {
                Text("microCAM isn't allowed to use the camera.").font(.title3)
                Text("Allow it in System Settings → Privacy & Security → Camera.").foregroundStyle(.secondary)
                Button("Open System Settings") { model.openPrivacySettings("Privacy_Camera") }
            }
            .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        } else if model.cameraAuthorized == true && engine.currentCameraID == nil {
            VStack(spacing: 8) {
                Text("No camera connected.").font(.title3)
                Text("Connect a USB microscope or a capture card.").foregroundStyle(.secondary)
            }
                .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        } else if let error = engine.lastError {
            // Same look as an error toast; stays at the top while the camera fails.
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text(error).lineLimit(3)
            }
            .font(.callout)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
            .frame(maxWidth: 560)
            .frame(maxHeight: .infinity, alignment: .top).padding(.top, 12)
        }
    }
}

struct TimelapseToolbarButton: View {
    @ObservedObject var runner: TimelapseRunner
    @Binding var show: Bool

    var body: some View {
        // Same symbol while running, in the accent colour: "timer.circle.fill"
        // drew visibly smaller than "timer" next to it.
        Button { show.toggle() } label: {
            Label {
                Text("Timelapse")
            } icon: {
                // Colour only while running: an explicit colour when idle kept
                // the icon bright in an inactive window, unlike its neighbours.
                if runner.isRunning {
                    Image(systemName: "timer").foregroundStyle(.tint)
                } else {
                    Image(systemName: "timer")
                }
            }
        }
        .help("Timelapse")
        .popover(isPresented: $show, arrowEdge: .bottom) {
            TimelapseForm(runner: runner).padding(16).frame(width: 320)
        }
    }
}

struct MoveRequest: Identifiable {
    let files: [URL]
    var id: String { files.map(\.path).joined(separator: "|") }
}

/// Record/stop, with visible "starting" (waiting for the microphone; pressing
/// again cancels) and "saving" (previous file still finalizing) states.
struct RecordButton: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.isFinalizingRecording {
            Label("Saving video…", systemImage: "hourglass")
                .help("Finishing the previous video")
        } else {
            Button { model.toggleRecording() } label: {
                if model.isStartingRecording {
                    Label("Cancel recording", systemImage: "xmark.circle")
                } else if model.isRecording {
                    Label {
                        Text("Stop recording")
                    } icon: {
                        Image(systemName: "stop.circle.fill")
                            .symbolRenderingMode(.palette).foregroundStyle(.white, .red)
                    }
                } else {
                    Label("Record", systemImage: "record.circle")
                }
            }
            .help(model.isStartingRecording ? String(localized: "Waiting for the microphone. Click to cancel.")
                                            : String(localized: "Start or stop recording (R)"))
        }
    }
}
