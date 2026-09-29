import AppKit
import MicroCAMCore

/// Translates window occlusion, screen lock, display sleep and system sleep
/// into `CaptureLifecycleState`. Decisions live in `CaptureLifecyclePolicy`.
@MainActor
final class LifecycleMonitor {
    private(set) var state = CaptureLifecycleState() {
        didSet { if state != oldValue { onChange?(state) } }
    }
    var onChange: ((CaptureLifecycleState) -> Void)?
    /// Called before `systemSleeping` becomes true, so a recording can be finalized.
    var onWillSleep: (() -> Void)?

    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private weak var window: NSWindow?

    init() {
        let ws = NSWorkspace.shared.notificationCenter
        observe(ws, NSWorkspace.willSleepNotification) { $0.onWillSleep?(); $0.state.systemSleeping = true }
        observe(ws, NSWorkspace.didWakeNotification) { $0.state.systemSleeping = false }
        observe(ws, NSWorkspace.screensDidSleepNotification) { $0.state.displayAsleep = true }
        observe(ws, NSWorkspace.screensDidWakeNotification) { $0.state.displayAsleep = false }
        let dc = DistributedNotificationCenter.default()
        observe(dc, Notification.Name("com.apple.screenIsLocked")) { $0.state.screenLocked = true }
        observe(dc, Notification.Name("com.apple.screenIsUnlocked")) { $0.state.screenLocked = false }
    }

    func attach(window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        observe(NotificationCenter.default, NSWindow.didChangeOcclusionStateNotification, object: window) { monitor in
            monitor.state.windowVisible = window.occlusionState.contains(.visible)
        }
        state.windowVisible = window.occlusionState.contains(.visible)
    }

    func update(_ body: (inout CaptureLifecycleState) -> Void) {
        var copy = state
        body(&copy)
        state = copy
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, object: AnyObject? = nil,
                         _ handler: @escaping @MainActor (LifecycleMonitor) -> Void) {
        let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        }
        tokens.append((center, token))
    }
}
