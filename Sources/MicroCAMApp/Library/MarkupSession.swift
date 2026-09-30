import AppKit
import UniformTypeIdentifiers

/// The system Markup editor (arrows, shapes, text, loupe, crop…), the same
/// one Finder and Quick Look use, as a sheet on the main window.
///
/// macOS has no public Quick Look editing mode (`QLPreviewItemEditingMode` is
/// iOS only), but Markup is a system extension that `NSSharingService` runs
/// by its identifier. When Markup finishes it hands back the edited image and
/// leaves the file alone; the caller saves it as a new copy. If a future macOS
/// renames the extension, `isAvailable` turns false and the side panel
/// offers Open in Preview instead (Preview has the same Markup tools).
@MainActor
final class MarkupSession: NSObject, NSSharingServiceDelegate {
    private static let serviceName = NSSharingService.Name("com.apple.MarkupUI.Markup")

    static func isAvailable(for url: URL) -> Bool {
        url.pathExtension.lowercased() != "mov"
            && NSSharingService(named: serviceName)?.canPerform(withItems: [url]) == true
    }

    private static var previewApp: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview")
    }

    static func canOpenInPreview(_ url: URL) -> Bool {
        url.pathExtension.lowercased() != "mov" && previewApp != nil
    }

    static func openInPreview(_ url: URL) {
        guard let app = previewApp else { return }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    private let window: NSWindow
    private var service: NSSharingService?
    private let completion: (Result<Data, Error>) -> Void
    /// Keeps the running session alive; the service holds its delegate weakly.
    private static var running: MarkupSession?

    /// Opens Markup for `url`. `completion` (main queue) gets the edited
    /// image as JPEG data when the user clicks Done; Cancel calls nothing.
    static func start(_ url: URL, in window: NSWindow, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let service = NSSharingService(named: serviceName) else { return }
        let session = MarkupSession(window: window, completion: completion)
        running = session
        session.service = service
        service.delegate = session
        service.perform(withItems: [url])
    }

    private init(window: NSWindow, completion: @escaping (Result<Data, Error>) -> Void) {
        self.window = window
        self.completion = completion
    }

    nonisolated func sharingService(_ sharingService: NSSharingService,
                                    sourceWindowForShareItems items: [Any],
                                    sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? {
        MainActor.assumeIsolated { window }
    }

    /// Markup places its editor over this frame; without it the editor
    /// opens at the left edge of the screen, away from the window.
    nonisolated func sharingService(_ sharingService: NSSharingService,
                                    sourceFrameOnScreenForShareItem item: Any) -> NSRect {
        MainActor.assumeIsolated { window.frame }
    }

    nonisolated func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        let provider = items.lazy.compactMap { $0 as? NSItemProvider }.first
        MainActor.assumeIsolated {
            Self.running = nil
            guard let provider else { return }
            let completion = self.completion
            // Markup returns the photo's own type (JPEG for captures); anything
            // else is converted, the copy is always a .jpg.
            let type = provider.registeredTypeIdentifiers.contains(UTType.jpeg.identifier)
                ? UTType.jpeg.identifier : UTType.image.identifier
            _ = provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                let result: Result<Data, Error> = Result {
                    guard let data, let jpeg = type == UTType.jpeg.identifier ? data : Self.jpeg(from: data)
                    else { throw error ?? CocoaError(.fileReadCorruptFile) }
                    return jpeg
                }
                DispatchQueue.main.async { completion(result) }
            }
        }
    }

    nonisolated func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        MainActor.assumeIsolated { Self.running = nil }
    }

    private nonisolated static func jpeg(from data: Data) -> Data? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }
}
