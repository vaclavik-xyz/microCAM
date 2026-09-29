import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showAdjustments = false

    var body: some View {
        VStack(spacing: 0) {
            if model.settings.jobsEnabled {
                JobBar()
                Divider()
            }
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
            .background(WindowAccessor { model.attachMainWindow($0) })
            Divider()
            StatusBar()
        }
        .toolbar {
            ToolbarItemGroup {
                Button { model.takePhoto() } label: { Label("Vyfotit", systemImage: "camera") }
                    .help("Vyfotit (mezerník)")
                Button { model.revealCaptureFolder() } label: { Label("Složka", systemImage: "folder") }
                    .help("Otevřít složku, kam se teď ukládá")
                Button { showAdjustments.toggle() } label: {
                    Label("Úpravy obrazu", systemImage: "slider.horizontal.3")
                }
                .popover(isPresented: $showAdjustments) {
                    AdjustmentsForm().padding().frame(width: 360)
                }
            }
        }
        .sheet(isPresented: $model.showFirstRun) {
            FirstRunView().interactiveDismissDisabled()
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
                Text("microCAM nemá přístup ke kameře.").font(.title3)
                Button("Otevřít Nastavení systému") { model.openPrivacySettings("Privacy_Camera") }
            }
            .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        } else if model.cameraAuthorized == true && engine.currentCameraID == nil {
            Text("Není připojená žádná kamera.").font(.title3)
                .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        } else if let error = engine.lastError {
            Text(error).foregroundStyle(.red)
                .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .frame(maxHeight: .infinity, alignment: .top).padding(.top, 12)
        }
    }
}
