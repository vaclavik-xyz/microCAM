import AppKit
import MicroCAMCore

/// Single-key shortcuts for the main window only. Keys pass through while a
/// text field is being edited (job codes contain R and 0) and in other
/// windows (Settings, sheets). Key repeat is ignored.
///
/// The side panel counts as focused from a click in it (`isInSidePanel`)
/// until a click elsewhere in the main window; Space then previews the
/// selection (`hasSelection`), as in Finder. SwiftUI focus doesn't follow clicks on the tiles.
@MainActor
final class KeyboardMonitor {
    private var token: Any?
    private var mouseToken: Any?
    private var inSidePanel = false

    init(isMainWindow: @escaping (NSWindow?) -> Bool, isInSidePanel: @escaping (NSEvent) -> Bool,
         hasSelection: @escaping () -> Bool, handler: @escaping (ShortcutAction) -> Void) {
        mouseToken = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if isMainWindow(event.window) { self?.inSidePanel = isInSidePanel(event) }
            return event
        }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard !event.isARepeat, isMainWindow(event.window) else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .numericPad, .function])
            let editing = event.window?.firstResponder is NSText
            guard let action = ShortcutAction.from(characters: event.charactersIgnoringModifiers,
                                                   hasModifiers: !modifiers.isEmpty,
                                                   isEditingText: editing,
                                                   inSidePanel: self?.inSidePanel == true,
                                                   hasSelection: hasSelection()) else { return event }
            handler(action)
            return nil
        }
    }

    deinit {
        if let token { NSEvent.removeMonitor(token) }
        if let mouseToken { NSEvent.removeMonitor(mouseToken) }
    }
}
