import AppKit
import MicroCAMCore
import Quartz

/// Space in the side panel: the system Quick Look panel over the selected
/// captures, full size, arrows move on (see `GridSelection.previewItems`).
/// Quick Look on macOS has no public editing mode (that exists only on iOS),
/// so marking up goes through `MarkupSession`.
///
/// The panel takes its data from the first object in the key window's
/// responder chain that accepts control, so `attach(to:)` puts this object
/// right after the main window.
@MainActor
final class QuickLookController: NSResponder, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private var items: [URL] = []
    private var start = 0

    func attach(to window: NSWindow) {
        guard window.nextResponder !== self else { return }
        nextResponder = window.nextResponder
        window.nextResponder = self
    }

    var isVisible: Bool { QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible }

    /// Shows `items` from `start`; replaces what an open panel shows.
    func show(items: [URL], start: Int) {
        guard !items.isEmpty else { return }
        self.items = items
        self.start = start
        let panel = QLPreviewPanel.shared()!
        panel.updateController()
        if (panel.currentController as AnyObject?) === self {
            panel.reloadData()
            panel.currentPreviewItemIndex = start
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        if isVisible { QLPreviewPanel.shared().orderOut(nil) }
    }

    // MARK: QLPreviewPanelController

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = start
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    // MARK: QLPreviewPanelDataSource

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { items.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated {
            items.indices.contains(index) ? items[index] as NSURL : nil
        }
    }
}
