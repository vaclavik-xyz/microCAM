import Foundation

/// Guards remote photo/annotation requests. Lockout is global (one shop, a
/// handful of viewers): after `maxFailures` wrong PINs every attempt is
/// refused for `lockout` seconds, even with the right PIN.
public final class PinGuard: @unchecked Sendable {
    public enum Outcome: Equatable {
        case ok, wrong, locked(until: Date), notConfigured
    }

    private let maxFailures: Int
    private let lockout: TimeInterval
    private let now: () -> Date
    private let lock = NSLock()
    private var failures = 0
    private var lockedUntil: Date?

    public init(maxFailures: Int = 5, lockout: TimeInterval = 60, now: @escaping () -> Date = Date.init) {
        self.maxFailures = maxFailures
        self.lockout = lockout
        self.now = now
    }

    public static func isValidPIN(_ pin: String) -> Bool {
        (4...8).contains(pin.count) && pin.allSatisfy(\.isASCII) && pin.allSatisfy(\.isNumber)
    }

    public func check(_ candidate: String?, expected: String?) -> Outcome {
        guard let expected, !expected.isEmpty else { return .notConfigured }
        lock.lock(); defer { lock.unlock() }
        let t = now()
        if let until = lockedUntil {
            if t < until { return .locked(until: until) }
            lockedUntil = nil
            failures = 0
        }
        if let candidate, ConstantTime.equals(candidate, expected) {
            failures = 0
            return .ok
        }
        failures += 1
        if failures >= maxFailures { lockedUntil = t.addingTimeInterval(lockout) }
        return .wrong
    }
}
