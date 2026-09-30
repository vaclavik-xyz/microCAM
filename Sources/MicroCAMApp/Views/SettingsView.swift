import AppKit
import MicroCAMCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.launchMode == .viewer {
                GeneralSettingsTab()
            } else {
                cameraTabs
            }
        }
        .formStyle(.grouped)
        // Each tab is as tall as its content, so the window resizes per tab
        // instead of cutting long tabs off.
        .scrollDisabled(true)
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var cameraTabs: some View {
        TabView(selection: $model.settingsTab) {
            GeneralSettingsTab().tabItem { Label("General", systemImage: "gearshape") }.tag("general")
            DeviceSettingsTab().tabItem { Label("Device", systemImage: "camera") }.tag("device")
            ImageSettingsTab().tabItem { Label("Image", systemImage: "slider.horizontal.3") }.tag("image")
            StorageSettingsTab().tabItem { Label("Storage", systemImage: "folder") }.tag("storage")
            TimelapseSettingsTab().tabItem { Label("Timelapse", systemImage: "timer") }.tag("timelapse")
            PreviewSettingsTab().tabItem { Label("Preview", systemImage: "grid") }.tag("preview")
            IntegrationSettingsTab().tabItem { Label("Integrations", systemImage: "arrow.up.forward.app") }.tag("integrations")
            StreamSettingsTab().tabItem { Label("Stream", systemImage: "dot.radiowaves.left.and.right") }.tag("stream")
        }
    }
}

/// Settings that apply to both modes (the viewer shows only this tab), plus
/// what the camera does while the window is hidden or a recording runs.
struct GeneralSettingsTab: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var updater: Updater

    var body: some View {
        Form {
            Section {
                Picker(selection: $model.settings.appMode) {
                    Text("Camera – the microscope is connected to this Mac").tag(AppMode.camera)
                    Text("Viewer – shows the live stream from another Mac").tag(AppMode.viewer)
                } label: {
                    Text("Mode")
                    Text("A viewer only watches. It finds the camera computer on the network by itself.")
                }
                .pickerStyle(.radioGroup)
                Picker(selection: $model.language) {
                    Text("System").tag(String?.none)
                    ForEach(model.languageChoices, id: \.self) { code in
                        Text(verbatim: Self.name(of: code)).tag(Optional(code))
                    }
                } label: {
                    Text("Language")
                    Text("For microCAM and the names of new folders. Existing files keep their names.")
                }
                if model.settings.appMode != model.launchMode || model.language != model.launchLanguage {
                    RestartRow()
                }
            }
            if updater.isAvailable {
                Section {
                    Toggle(isOn: Binding(get: { updater.automaticallyChecks },
                                         set: { updater.automaticallyChecks = $0 })) {
                        Text("Check for updates automatically")
                        Text("microCAM asks before it installs anything. You can also check in the microCAM menu.")
                    }
                }
            }
            if model.launchMode == .camera {
                Section {
                    Toggle(isOn: $model.settings.pauseWhenHidden) {
                        Text("Turn off the camera when the window is hidden")
                        Text("Saves energy while the window is minimized or covered, or the screen is locked. Recording, timelapse and viewers of the live stream keep it on.")
                    }
                    Toggle(isOn: $model.settings.preventSleepWhileRecording) {
                        Text("Keep the Mac awake while recording")
                        Text("A long recording doesn't stop because the Mac went to sleep. Closing the lid still stops it.")
                    }
                }
            }
        }
    }
}

extension GeneralSettingsTab {
    /// A language's name in that language itself, e.g. "English" for en.
    static func name(of code: String) -> String {
        let locale = Locale(identifier: code)
        return (locale.localizedString(forLanguageCode: code) ?? code).capitalized(with: locale)
    }
}

/// "Takes effect after a restart" with a button that does it.
struct RestartRow: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack {
            Text("The change applies after a restart.").foregroundStyle(.secondary)
            Spacer()
            Button("Restart now") { model.relaunch() }
        }
    }
}

struct ImageSettingsTab: View {
    var body: some View {
        Form {
            Section {
                AdjustmentsForm()
            } footer: {
                Text("You can also open these from the toolbar while you work.")
            }
        }
    }
}

struct StorageSettingsTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    HStack {
                        Group {
                            if let path = model.settings.storageRootPath {
                                Text(verbatim: DisplayPath.string(for: path)).help(path)
                            } else {
                                Text("Not chosen")
                            }
                        }
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        Button("Change…") { model.chooseStorageRoot() }
                        Button("Show in Finder") { model.revealCaptureFolder() }
                            .disabled(model.settings.storageRootPath == nil)
                    }
                } label: {
                    Text("Folder")
                    Text("Where photos and videos are saved.")
                }
                Toggle(isOn: $model.settings.jobsEnabled) {
                    Text("Use jobs")
                    Text("Each job gets its own folder, and its files start with the job code.")
                }
                Toggle(isOn: $model.settings.sortByType) {
                    Text("Sort by type")
                    Text("Separate subfolders for photos, videos and timelapse.")
                }
                Text("Example: \(layoutExample)").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent {
                    HStack {
                        Slider(value: $model.settings.jpegQuality, in: 0.5...1) { Text("Photo quality") }
                            .labelsHidden()
                        Text(verbatim: "\(Int(model.settings.jpegQuality * 100)) %").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                } label: {
                    Text("Photo quality")
                    Text("Higher quality makes bigger files.")
                }
                Picker(selection: $model.settings.videoCodec) {
                    Text("HEVC (smaller files)").tag(VideoCodec.hevc)
                    Text("H.264 (plays everywhere)").tag(VideoCodec.h264)
                } label: {
                    Text("Video format")
                    Text("HEVC files are about half the size. Choose H.264 for older software.")
                }
                Picker(selection: $model.settings.videoQuality) {
                    Text("Standard").tag(VideoQuality.standard)
                    Text("High").tag(VideoQuality.high)
                } label: {
                    Text("Video quality")
                    Text("Higher quality makes bigger files.")
                }
            } footer: {
                if model.isRecording { Text("You can change these after the recording ends.") }
            }
            .disabled(model.isRecording)
        }
    }

    private var layoutExample: String {
        let job = model.settings.jobsEnabled ? "PR-260042/" : ""
        let type = model.settings.sortByType ? FolderLanguage.app.typeFolderName(for: .photo) + "/" : ""
        let prefix = model.settings.jobsEnabled ? "PR-260042" : StorageLayout.jobsDisabledPrefix
        return "…/\(job)\(type)\(prefix)_2026-09-29_14-03-12.jpg"
    }
}

struct TimelapseSettingsTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                DurationField.interval($model.settings.timelapseInterval)
                DurationField.duration($model.settings.timelapseDuration)
            } footer: {
                Text("Takes a photo at a fixed interval into the current folder. Start it from the toolbar.")
            }
        }
    }
}

struct PreviewSettingsTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                Picker(selection: $model.settings.gridType) {
                    Text("Thirds").tag(GridType.thirds)
                    Text("Fine").tag(GridType.fine)
                } label: {
                    Text("Grid")
                    Text("Press G to show or hide it. The grid is never saved in photos or videos.")
                }
                Picker(selection: $model.settings.gridColor) {
                    Text("White").tag(GridColor.white)
                    Text("Yellow").tag(GridColor.yellow)
                    Text("Green").tag(GridColor.green)
                    Text("Red").tag(GridColor.red)
                } label: {
                    Text("Grid color")
                    Text("Pick one that stands out against the board.")
                }
            }
        }
    }
}

struct DeviceSettingsTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        DeviceSettingsForm(engine: model.engine)
    }
}

struct DeviceSettingsForm: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var engine: CaptureEngine

    var body: some View {
        Form {
            Section {
                Picker(selection: Binding(
                    get: { engine.currentCameraID ?? "" },
                    set: { model.selectCamera($0) }
                )) {
                    ForEach(engine.cameras) {
                        Text(verbatim: model.settings.cameraName(for: $0.id, systemName: $0.name)).tag($0.id)
                    }
                } label: {
                    Text("Camera")
                    Text("A USB microscope, or an HDMI camera behind a capture card.")
                }
                if let camera = engine.cameras.first(where: { $0.id == engine.currentCameraID }) {
                    TextField(text: Binding(
                        get: { model.settings.cameraNames[camera.id] ?? "" },
                        set: { model.settings.cameraNames[camera.id] = $0.isEmpty ? nil : $0 }
                    ), prompt: Text(verbatim: camera.name)) {
                        Text("Name")
                        Text("Shown in the window title. Leave it empty to use the camera's own name.")
                    }
                }
                Picker(selection: Binding(
                    get: { engine.activeFormat },
                    set: { if let f = $0 { model.selectFormat(f) } }
                )) {
                    ForEach(engine.formats, id: \.self) { Text(verbatim: $0.label).tag(Optional($0)) }
                } label: {
                    Text("Format")
                    Text("Picture size and frames per second.")
                }
            } footer: {
                if model.isRecording { Text("You can change these after the recording ends.") }
            }
            .disabled(model.isRecording)
            Section {
                Toggle(isOn: $model.settings.recordAudio) {
                    Text("Record sound")
                    Text("Adds sound from a microphone to videos, for example your narration.")
                }
                Picker(selection: Binding(
                    get: { model.settings.lastMicrophoneID ?? "" },
                    set: { model.settings.lastMicrophoneID = $0.isEmpty ? nil : $0 }
                )) {
                    Text("System default").tag("")
                    ForEach(engine.microphones) { Text(verbatim: $0.name).tag($0.id) }
                } label: {
                    Text("Microphone")
                    Text("microCAM uses it only while recording.")
                }
                .disabled(!model.settings.recordAudio)
            }
        }
    }
}

struct IntegrationSettingsTab: View {
    @EnvironmentObject private var model: AppModel
    /// Loaded when the tab appears; the demo never touches the real token.
    @State private var token = ""

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $model.settings.webhookEnabled) {
                    Text("Send to a webhook")
                    Text("Sends the files you select to your own server or automation tool, such as your CRM, n8n, Make or Zapier.")
                }
                if model.settings.webhookEnabled {
                    TextField("URL", text: Binding(
                        get: { model.settings.webhookURL ?? "" },
                        set: { model.settings.webhookURL = $0.isEmpty ? nil : $0 }
                    ), prompt: Text(verbatim: "https://…"))
                    if model.webhookEndpoint == nil {
                        Text("Enter a valid https:// address. Plain http:// works only for addresses on your local network.")
                            .font(.caption).foregroundStyle(.red)
                    }
                    SecureField(text: $token, prompt: Text("Not set")) {
                        Text("Token")
                        Text("Optional. Sent with every file so the server knows it comes from you.")
                    }
                    .onSubmit(saveToken)
                    .onDisappear(perform: saveToken)
                    Toggle(isOn: $model.settings.webhookSendVideos) {
                        Text("Send videos too")
                        Text("Videos can be large, so sending them may take a while.")
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sharing (AirDrop, Mail, Messages…) is always available in the side panel.")
                    if model.settings.webhookEnabled {
                        Text("For developers: each file is sent as a multipart/form-data POST with the fields file, job, kind, capturedAt and idempotencyKey. The token goes in the Authorization: Bearer header.")
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { if model.demo == nil { token = KeychainToken.read() ?? "" } }
    }

    private func saveToken() {
        if model.demo == nil { KeychainToken.write(token) }
    }
}

struct StreamSettingsTab: View {
    @EnvironmentObject private var model: AppModel
    @State private var pin = ""
    @State private var pinInvalid = false
    /// Edited text; the port is applied only on Enter or when leaving the tab,
    /// because every change restarts the server and drops the viewers.
    @State private var portText = ""

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $model.settings.streamingEnabled) {
                    Text("Live stream")
                    Text("Shows the live picture in a browser on other devices on your network, or in microCAM on another Mac.")
                }
            }
            if model.settings.streamingEnabled {
                Section {
                    Picker(selection: $model.settings.streamingMode) {
                        Text("Watch, draw and take photos").tag(StreamMode.controls)
                        Text("Only watch").tag(StreamMode.imageOnly)
                    } label: {
                        Text("Viewers can")
                        Text("Photos taken from another device are saved on this Mac, like your own.")
                    }
                    SecureField(text: $pin, prompt: Text("Not set")) {
                        Text("PIN for photos")
                        Text("4–8 digits. Other devices need it to take photos.")
                    }
                    .onSubmit(savePIN)
                    .onDisappear(perform: savePIN)
                    if pinInvalid {
                        Text("The PIN must have 4–8 digits.").font(.caption).foregroundStyle(.red)
                    }
                }
                Section {
                    // Title and field on one line, the description below over the full
                    // width, so it doesn't wrap into a narrow column beside the field.
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Port")
                            Spacer()
                            TextField(text: $portText) { Text("Port") }
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                                .onSubmit(commitPort)
                                .onDisappear(perform: commitPort)
                        }
                        Text("Change it only if another app already uses this port.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if StreamPort.parse(portText) == nil {
                        Text("The port must be a number from 1024 to 65535. Press Return to apply it.")
                            .font(.caption).foregroundStyle(.red)
                    } else if StreamPort.parse(portText) != model.settings.streamingPort {
                        Text("Press Return to apply. The stream restarts and viewers reconnect.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = model.streamError { Text(error).font(.caption).foregroundStyle(.red) }
                    if model.streamError == nil, StreamPort.isValid(model.settings.streamingPort) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open on another device")
                            Text("Type the address into a browser on a device on the same network.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            ForEach(model.streamAddresses(), id: \.self) { address in
                                let url = "http://\(address):\(model.settings.streamingPort)/"
                                HStack {
                                    Text(verbatim: url).textSelection(.enabled).monospaced()
                                    Spacer()
                                    Button("Copy") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(url, forType: .string)
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                    LabeledContent("Watching now", value: "\(model.streamViewers)")
                }
            }
        }
        .onAppear {
            pin = model.streamPIN ?? ""
            portText = String(model.settings.streamingPort)
        }
    }

    private func commitPort() {
        guard let port = StreamPort.parse(portText), port != model.settings.streamingPort else { return }
        model.settings.streamingPort = port
    }

    private func savePIN() {
        pinInvalid = !pin.isEmpty && !PinGuard.isValidPIN(pin)
        if !pinInvalid, pin != (model.streamPIN ?? "") { model.setStreamPIN(pin.isEmpty ? nil : pin) }
    }
}
