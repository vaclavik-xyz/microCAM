import AppKit
import SwiftUI

@main
struct MicroCAMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    /// Never in the screenshot demo, which must not check the network.
    @StateObject private var updater = Updater(enabled: DemoConfig.fromEnvironment() == nil)

    var body: some Scene {
        Window("microCAM", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 640, minHeight: 420)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About microCAM") { AboutPanel.show() }
                if updater.isAvailable {
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheck)
                }
            }
            // Menu shortcuts use ⌘ like other Mac apps (⌘T is Take Photo in
            // Photo Booth). The quick single keys (Space, S, R, G, 0) are handled by
            // KeyboardMonitor instead: as menu shortcuts they would also fire
            // while typing in a text field, e.g. R in a job code.
            CommandMenu("Camera") {
                Button("Take photo") { model.handle(.photo) }
                    .keyboardShortcut("t")
                // Cancels a running countdown, like S.
                Button("Take photo with self-timer") { model.handle(.selfTimer) }
                    .keyboardShortcut("t", modifiers: [.command, .option])
                Menu("Self-timer") { SelfTimerPicker().environmentObject(model) }
                Button("Start or stop recording") { model.handle(.toggleRecording) }
                    .keyboardShortcut("r")
                Divider()
                Button("Show or hide grid") { model.handle(.toggleGrid) }
                    .keyboardShortcut("'")
                Button("Zoom in") { model.zoom(by: 1.25) }
                    .keyboardShortcut("+")
                Button("Zoom out") { model.zoom(by: 0.8) }
                    .keyboardShortcut("-")
                Button("Reset zoom") { model.handle(.resetZoom) }
                    .keyboardShortcut("0")
                Divider()
                Toggle("Draw", isOn: $model.isDrawing)
                    .keyboardShortcut("d")
                Button("Clear drawing") { model.clearDrawing() }
                    .disabled(!model.hasDrawing)
                Divider()
                // Every toolbar action is also in the menu bar.
                Button("Timelapse…") { model.showTimelapse = true }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Image adjustments…") { model.showAdjustments = true }
                    .keyboardShortcut("i")
                Divider()
                Button("Open folder") { model.revealCaptureFolder() }
            }
            // Into the system View menu, next to Enter Full Screen.
            CommandGroup(after: .toolbar) {
                ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { _, screen in
                    Button("Full screen on \(screen.localizedName)") { model.showFullScreen(on: screen) }
                }
            }
            // File → Import from iPhone or iPad (Continuity Camera); the main
            // window receives the photo (`importsItemProviders` in ContentView).
            ImportFromDevicesCommands()
            CommandGroup(replacing: .help) {
                Button("microCAM on GitHub") { NSWorkspace.shared.open(AboutPanel.repository) }
                Button("Report a problem…") { NSWorkspace.shared.open(AboutPanel.issues) }
                Divider()
                Button("Keyboard shortcuts") {
                    let alert = NSAlert()
                    alert.messageText = String(localized: "Keyboard shortcuts")
                    alert.informativeText = [
                        String(localized: "Space – take a photo"),
                        String(localized: "S – take a photo after the self-timer countdown, Esc – cancel it"),
                        String(localized: "Space in the side panel – Quick Look of the selected files"),
                        String(localized: "⌘C – copy the selected files"),
                        String(localized: "⌘⌫ – move the selected files to the Trash"),
                        String(localized: "R – start or stop recording"),
                        String(localized: "G – show or hide the grid"),
                        String(localized: "D – draw on the picture, Esc – stop drawing"),
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
                .environmentObject(updater)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Closing the window quits and releases the camera.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
