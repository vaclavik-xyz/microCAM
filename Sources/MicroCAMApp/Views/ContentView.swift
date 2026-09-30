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
                RecordingBadge()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(12)
                if model.zoomScale > 1.01 {
                    Text(String(format: "%.1f×", model.zoomScale))
                        .font(.caption.monospacedDigit()).padding(6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(12)
                }
                MessageToast()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(16)
            }
            .animation(.easeOut(duration: 0.2), value: model.message)
            .animation(.easeOut(duration: 0.2), value: model.recordingStartedAt)
            .frame(minWidth: 400)
            .background(WindowAccessor { model.attachMainWindow($0) })
        }
        .modifier(WindowTitle(engine: model.engine))
        .toolbar {
            if model.settings.jobsEnabled {
                ToolbarItem(placement: .navigation) { JobToolbarButton() }
            }
            ToolbarItem(placement: .principal) {
                ControlGroup {
                    Button { model.takePhoto() } label: { Label("Take photo", systemImage: "camera") }
                        .help("Take a photo (Space)")
                    RecordButton()
                    TimelapseToolbarButton(runner: model.timelapse, show: $model.showTimelapse)
                }
                .controlGroupStyle(.navigation)
                // Anchored on the group: a popover on a button inside a toolbar
                // ControlGroup never appears.
                .popover(isPresented: $model.showTimelapse, arrowEdge: .bottom) {
                    TimelapseForm(runner: model.timelapse).padding().frame(width: 340)
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if model.streamViewers > 0 {
                    Label("Watching: \(model.streamViewers)", systemImage: "dot.radiowaves.left.and.right")
                        .labelStyle(.titleAndIcon).foregroundStyle(.secondary)
                        .help("Watching now")
                }
                Button { model.showAdjustments.toggle() } label: {
                    Label("Image adjustments", systemImage: "slider.horizontal.3")
                }
                .help("Image adjustments")
                .popover(isPresented: $model.showAdjustments) {
                    AdjustmentsForm().padding().frame(width: 360)
                }
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

/// Title: the camera the picture comes from; subtitle: its format, or the
/// recording state while recording. The app name stays in the menu bar and Dock.
private struct WindowTitle: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var engine: CaptureEngine

    func body(content: Content) -> some View {
        content
            .navigationTitle(engine.cameras.first { $0.id == engine.currentCameraID }?.name
                             ?? String(localized: "No camera"))
            .navigationSubtitle(model.isRecording ? String(localized: "● Recording")
                                                  : engine.activeFormat?.label ?? "")
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
            Text(error).foregroundStyle(.red)
                .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .frame(maxHeight: .infinity, alignment: .top).padding(.top, 12)
        }
    }
}

struct TimelapseToolbarButton: View {
    @ObservedObject var runner: TimelapseRunner
    @Binding var show: Bool

    var body: some View {
        Button { show.toggle() } label: {
            Label("Timelapse", systemImage: runner.isRunning ? "timer.circle.fill" : "timer")
        }
        .help("Timelapse")
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
