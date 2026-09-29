import AppKit
import SwiftUI

@main
struct MicroCAMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("microCAM", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 640, minHeight: 420)
        }
        .commands {
            CommandMenu("Kamera") {
                Button("Vyfotit (mezerník)") { model.handle(.photo) }
                Button("Nahrávat / zastavit (R)") { model.handle(.toggleRecording) }
                Divider()
                Button("Mřížka (G)") { model.handle(.toggleGrid) }
                Button("Zrušit zoom (0)") { model.handle(.resetZoom) }
            }
            CommandMenu("Zobrazení") {
                ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { _, screen in
                    Button("Na celou obrazovku: \(screen.localizedName)") { model.showFullScreen(on: screen) }
                }
            }
            CommandGroup(replacing: .help) {
                Button("Klávesové zkratky") {
                    let alert = NSAlert()
                    alert.messageText = "Klávesové zkratky"
                    alert.informativeText = """
                    Mezerník – vyfotit
                    R – nahrávat / zastavit
                    G – mřížka
                    0 – zrušit zoom (nebo dvojklik do obrazu)
                    Kolečko / sevření – zoom, tažení – posun
                    ⌘, – nastavení
                    """
                    alert.runModal()
                }
            }
        }
        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Closing the window quits and releases the camera.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
