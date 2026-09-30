import AppKit
import MicroCAMCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.launchMode == .viewer {
                ModeSettingsTab()
            } else {
                cameraTabs
            }
        }
        .frame(width: 540)
        .padding(20)
    }

    private var cameraTabs: some View {
        TabView(selection: $model.settingsTab) {
            ModeSettingsTab().tabItem { Label("Režim", systemImage: "rectangle.on.rectangle") }.tag("mode")
            DeviceSettingsTab().tabItem { Label("Zařízení", systemImage: "camera") }.tag("device")
            AdjustmentsForm().padding(.horizontal).tabItem { Label("Obraz", systemImage: "slider.horizontal.3") }.tag("image")
            StorageSettingsTab().tabItem { Label("Ukládání", systemImage: "folder") }.tag("storage")
            TimelapseSettingsTab().tabItem { Label("Časosběr", systemImage: "timer") }.tag("timelapse")
            PreviewSettingsTab().tabItem { Label("Náhled", systemImage: "grid") }.tag("preview")
            IntegrationSettingsTab().tabItem { Label("Integrace", systemImage: "arrow.up.forward.app") }.tag("integrations")
            StreamSettingsTab().tabItem { Label("Přenos", systemImage: "dot.radiowaves.left.and.right") }.tag("stream")
            BehaviourSettingsTab().tabItem { Label("Chování", systemImage: "gearshape") }.tag("behaviour")
        }
    }
}

struct ModeSettingsTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Picker("Režim appky", selection: $model.settings.appMode) {
                Text("Kamera – mikroskop je připojený k tomuto Macu").tag(AppMode.camera)
                Text("Prohlížeč – zobrazuje přenos z jiného Macu").tag(AppMode.viewer)
            }
            .pickerStyle(.radioGroup)
            if model.settings.appMode != model.launchMode {
                HStack {
                    Text("Změna se projeví po restartu.").foregroundStyle(.secondary)
                    Button("Restartovat") { model.relaunch() }
                }
            }
        }
    }
}

struct StorageSettingsTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            LabeledContent("Složka") {
                HStack {
                    Text(model.settings.storageRootPath.map { DisplayPath.string(for: $0) } ?? "není vybraná")
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        .help(model.settings.storageRootPath ?? "")
                    Button("Změnit…") { model.chooseStorageRoot() }
                    Button("Otevřít ve Finderu") { model.revealCaptureFolder() }
                        .disabled(model.settings.storageRootPath == nil)
                }
            }
            Toggle("Používat zakázky (podsložka pro každou zakázku)", isOn: $model.settings.jobsEnabled)
            Toggle("Třídit podle typu (Fotky / Videa / Časosběr)", isOn: $model.settings.sortByType)
            Text(layoutExample).font(.caption).foregroundStyle(.secondary)
            Slider(value: $model.settings.jpegQuality, in: 0.5...1) {
                Text("Kvalita JPEG \(Int(model.settings.jpegQuality * 100)) %")
            }
            Picker("Kodek videa", selection: $model.settings.videoCodec) {
                Text("HEVC (menší soubory)").tag(VideoCodec.hevc)
                Text("H.264 (kompatibilnější)").tag(VideoCodec.h264)
            }
            Picker("Kvalita videa", selection: $model.settings.videoQuality) {
                Text("Standardní").tag(VideoQuality.standard)
                Text("Vysoká").tag(VideoQuality.high)
            }
        }
        .disabled(model.isRecording)
    }

    private var layoutExample: String {
        let job = model.settings.jobsEnabled ? "PR-260042/" : ""
        let type = model.settings.sortByType ? FolderLanguage.app.typeFolderName(for: .photo) + "/" : ""
        let prefix = model.settings.jobsEnabled ? "PR-260042" : StorageLayout.jobsDisabledPrefix
        return "Příklad: …/\(job)\(type)\(prefix)_2026-09-29_14-03-12.jpg"
    }
}

struct TimelapseSettingsTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            DurationField(title: "Fotit každých", seconds: $model.settings.timelapseInterval,
                          units: [("sekund", 1), ("minut", 60)])
            DurationField(title: "Po dobu", seconds: $model.settings.timelapseDuration,
                          units: [("minut", 60), ("hodin", 3600)])
        }
    }
}

struct PreviewSettingsTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Picker("Mřížka", selection: $model.settings.gridType) {
                Text("Třetiny").tag(GridType.thirds)
                Text("Jemná").tag(GridType.fine)
            }
            Picker("Barva mřížky", selection: $model.settings.gridColor) {
                Text("Bílá").tag(GridColor.white)
                Text("Žlutá").tag(GridColor.yellow)
                Text("Zelená").tag(GridColor.green)
                Text("Červená").tag(GridColor.red)
            }
        }
    }
}

struct BehaviourSettingsTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Toggle("Vypnout kameru, když okno není vidět", isOn: $model.settings.pauseWhenHidden)
            Toggle("Nenechat Mac usnout během nahrávání", isOn: $model.settings.preventSleepWhileRecording)
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
            Picker("Kamera", selection: Binding(
                get: { engine.currentCameraID ?? "" },
                set: { model.selectCamera($0) }
            )) {
                ForEach(engine.cameras) { Text($0.name).tag($0.id) }
            }
            .disabled(model.isRecording)
            Picker("Formát", selection: Binding(
                get: { engine.activeFormat },
                set: { if let f = $0 { model.selectFormat(f) } }
            )) {
                ForEach(engine.formats, id: \.self) { Text($0.label).tag(Optional($0)) }
            }
            .disabled(model.isRecording)
            Toggle("Nahrávat zvuk z mikrofonu", isOn: $model.settings.recordAudio)
            Picker("Mikrofon", selection: Binding(
                get: { model.settings.lastMicrophoneID ?? "" },
                set: { model.settings.lastMicrophoneID = $0.isEmpty ? nil : $0 }
            )) {
                Text("Výchozí systémový").tag("")
                ForEach(engine.microphones) { Text($0.name).tag($0.id) }
            }
            .disabled(!model.settings.recordAudio)
        }
    }
}

struct IntegrationSettingsTab: View {
    @EnvironmentObject private var model: AppModel
    @State private var token = KeychainToken.read() ?? ""

    var body: some View {
        Form {
            Text("Sdílení (AirDrop, Mail, Zprávy…) je vždy k dispozici v bočním panelu.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Odesílat přes webhook", isOn: $model.settings.webhookEnabled)
            if model.settings.webhookEnabled {
                TextField("URL", text: Binding(
                    get: { model.settings.webhookURL ?? "" },
                    set: { model.settings.webhookURL = $0.isEmpty ? nil : $0 }
                ), prompt: Text("https://…"))
                SecureField("Token (volitelný)", text: $token)
                    .onSubmit { KeychainToken.write(token) }
                    .onDisappear { KeychainToken.write(token) }
                Toggle("Posílat i videa", isOn: $model.settings.webhookSendVideos)
                if model.webhookEndpoint == nil {
                    Text("Zadej platnou adresu https://… (http:// funguje jen v místní síti nebo na IP adrese).")
                        .font(.caption).foregroundStyle(.red)
                }
                Text("Každý soubor se pošle jako multipart/form-data POST s poli file, job, kind, capturedAt a idempotencyKey; token jako Authorization: Bearer.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
            Toggle("Živý přenos obrazu do sítě", isOn: $model.settings.streamingEnabled)
            if model.settings.streamingEnabled {
                Picker("Stránka", selection: $model.settings.streamingMode) {
                    Text("S ovládáním (focení, kreslení)").tag(StreamMode.controls)
                    Text("Jen obraz").tag(StreamMode.imageOnly)
                }
                TextField("Port", text: $portText)
                    .onSubmit(commitPort)
                    .onDisappear(perform: commitPort)
                if StreamPort.parse(portText) == nil {
                    Text("Port musí být číslo 1024–65535 (potvrď Enterem).").font(.caption).foregroundStyle(.red)
                } else if StreamPort.parse(portText) != model.settings.streamingPort {
                    Text("Potvrď Enterem – přenos se restartuje a diváci se znovu připojí.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                SecureField("PIN pro focení (4–8 číslic)", text: $pin)
                    .onSubmit(savePIN)
                    .onDisappear(perform: savePIN)
                if pinInvalid { Text("PIN musí mít 4–8 číslic.").font(.caption).foregroundStyle(.red) }
                if model.streamPIN == nil, model.settings.streamingMode == .controls {
                    Text("Bez PINu je focení z jiného zařízení vypnuté.").font(.caption).foregroundStyle(.secondary)
                }
                if let error = model.streamError { Text(error).font(.caption).foregroundStyle(.red) }
                if model.streamError == nil, StreamPort.isValid(model.settings.streamingPort) {
                    LabeledContent("Otevřít na jiném zařízení") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(NetworkAddresses.streamIPv4(), id: \.self) { address in
                                let url = "http://\(address):\(model.settings.streamingPort)/"
                                HStack {
                                    Text(url).textSelection(.enabled).monospaced()
                                    Button("Kopírovat") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(url, forType: .string)
                                    }
                                }
                            }
                        }
                    }
                }
                Text("Sleduje: \(model.streamViewers)").font(.caption).foregroundStyle(.secondary)
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
