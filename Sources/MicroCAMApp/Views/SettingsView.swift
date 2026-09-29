import MicroCAMCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            DeviceSettingsTab()
                .tabItem { Label("Zařízení", systemImage: "camera") }
        }
        .frame(width: 520)
        .padding(20)
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
