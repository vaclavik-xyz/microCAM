import MicroCAMCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView(selection: $model.settingsTab) {
            DeviceSettingsTab().tabItem { Label("Zařízení", systemImage: "camera") }.tag("device")
            AdjustmentsForm().padding(.horizontal).tabItem { Label("Obraz", systemImage: "slider.horizontal.3") }.tag("image")
            StorageSettingsTab().tabItem { Label("Ukládání", systemImage: "folder") }.tag("storage")
            TimelapseSettingsTab().tabItem { Label("Časosběr", systemImage: "timer") }.tag("timelapse")
            PreviewSettingsTab().tabItem { Label("Náhled", systemImage: "grid") }.tag("preview")
            IntegrationSettingsTab().tabItem { Label("Integrace", systemImage: "arrow.up.forward.app") }.tag("integrations")
            BehaviourSettingsTab().tabItem { Label("Chování", systemImage: "gearshape") }.tag("behaviour")
        }
        .frame(width: 540)
        .padding(20)
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
        let type = model.settings.sortByType ? "Fotky/" : ""
        let prefix = model.settings.jobsEnabled ? "PR-260042" : "microcam"
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
                    Text("Zadej platnou adresu http(s).").font(.caption).foregroundStyle(.red)
                }
                Text("Každý soubor se pošle jako multipart/form-data POST s poli file, job, kind, capturedAt a idempotencyKey; token jako Authorization: Bearer.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
