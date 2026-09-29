import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            PreviewView(session: model.engine.session)
            CameraStateOverlay(engine: model.engine)
        }
        .background(Color.black)
        .background(WindowAccessor { model.attachMainWindow($0) })
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
