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

    private var cameraBody: some View {
        VStack(spacing: 0) {
            if model.settings.jobsEnabled {
                JobBar()
                Divider()
            }
            HSplitView {
                SidePanel(library: model.library, compare: $model.comparePair)
                    .frame(minWidth: 200, idealWidth: 240, maxWidth: 360)
            ZStack {
                PreviewView()
                CameraStateOverlay(engine: model.engine)
                if model.zoomScale > 1.01 {
                    Text(String(format: "%.1f×", model.zoomScale))
                        .font(.caption.monospacedDigit()).padding(6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(10)
                }
            }
            .background(Color.black)
            .frame(minWidth: 400)
            }
            .background(WindowAccessor { model.attachMainWindow($0) })
            Divider()
            StatusBar()
        }
        .toolbar {
            ToolbarItemGroup {
                Button { model.takePhoto() } label: { Label("Take photo", systemImage: "camera") }
                    .help("Take a photo (Space)")
                RecordButton()
                Button { model.revealCaptureFolder() } label: { Label("Open folder", systemImage: "folder") }
                    .help("Open the folder where captures are saved now")
                TimelapseToolbarButton(runner: model.timelapse, show: $model.showTimelapse)
                Button { model.showAdjustments.toggle() } label: {
                    Label("Image adjustments", systemImage: "slider.horizontal.3")
                }
                .help("Image adjustments")
                .popover(isPresented: $model.showAdjustments) {
                    AdjustmentsForm().padding().frame(width: 360)
                }
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
        .popover(isPresented: $show) {
            TimelapseForm(runner: runner).padding().frame(width: 340)
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
                    Label("Stop recording", systemImage: "stop.circle.fill")
                } else {
                    Label("Record", systemImage: "record.circle")
                }
            }
            .tint(model.isRecording ? .red : nil)
            .help(model.isStartingRecording ? String(localized: "Waiting for the microphone. Click to cancel.")
                                            : String(localized: "Start or stop recording (R)"))
        }
    }
}
