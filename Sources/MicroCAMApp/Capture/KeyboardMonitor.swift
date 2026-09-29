import AppKit
import MicroCAMCore

/// Single-key shortcuts for the main window only. Keys pass through while a
/// text field is being edited (job codes contain R and 0) and in other
/// windows (Settings, sheets). Key repeat is ignored.
@MainActor
final class KeyboardMonitor {
    private var token: Any?

    init(isMainWindow: @escaping (NSWindow?) -> Bool, handler: @escaping (ShortcutAction) -> Void) {
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !event.isARepeat, isMainWindow(event.window) else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .numericPad, .function])
            let editing = event.window?.firstResponder is NSText
            guard let action = ShortcutAction.from(characters: event.charactersIgnoringModifiers,
                                                   hasModifiers: !modifiers.isEmpty,
                                                   isEditingText: editing) else { return event }
            handler(action)
            return nil
        }
    }

    deinit {
        if let token { NSEvent.removeMonitor(token) }
    }
}
