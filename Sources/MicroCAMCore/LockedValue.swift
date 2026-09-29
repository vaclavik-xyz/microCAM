import Foundation

/// Small lock-protected box for values shared between the main thread and
/// capture queues (current adjustments, latest frame).
public final class LockedValue<T>: @unchecked Sendable {
    private var stored: T
    private let lock = NSLock()

    public init(_ value: T) { stored = value }

    public var value: T {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }

    public func update(_ body: (inout T) -> Void) {
        lock.lock(); defer { lock.unlock() }
        body(&stored)
    }
}
