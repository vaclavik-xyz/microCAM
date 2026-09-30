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
            CommandMenu("Camera") {
                Button("Take photo (Space)") { model.handle(.photo) }
                Button("Start or stop recording (R)") { model.handle(.toggleRecording) }
                Divider()
                Button("Show or hide grid (G)") { model.handle(.toggleGrid) }
                Button("Reset zoom (0)") { model.handle(.resetZoom) }
            }
            // Into the system View menu, next to Enter Full Screen.
            CommandGroup(after: .toolbar) {
                ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { _, screen in
                    Button("Full screen on \(screen.localizedName)") { model.showFullScreen(on: screen) }
                }
            }
            CommandGroup(replacing: .help) {
                Button("Keyboard shortcuts") {
                    let alert = NSAlert()
                    alert.messageText = String(localized: "Keyboard shortcuts")
                    alert.informativeText = [
                        String(localized: "Space – take a photo"),
                        String(localized: "R – start or stop recording"),
                        String(localized: "G – show or hide the grid"),
                        String(localized: "0 – reset zoom (or double-click the image)"),
                        String(localized: "Scroll or pinch – zoom, drag – move the image"),
                        String(localized: "⌘, – settings"),
                    ].joined(separator: "\n")
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
