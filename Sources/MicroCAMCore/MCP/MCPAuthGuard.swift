import Foundation

/// Checks the MCP bearer token. Unlike the stream's `PinGuard` the lockout is
/// per address: agents run on several machines, and one misconfigured agent
/// must not lock out the others. After `maxFailures` wrong or missing tokens
/// in a row an address is refused for `lockout` seconds, even with the right token.
public final class MCPAuthGuard: @unchecked Sendable {
    public enum Outcome: Equatable {
        case ok, unauthorized, locked(until: Date), notConfigured
    }

    private struct Entry {
        var failures = 0
        var lockedUntil: Date?
        var lastSeen: Date
    }

    private let maxFailures: Int
    private let lockout: TimeInterval
    private let maxTracked: Int
    private let now: () -> Date
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    public init(maxFailures: Int = 5, lockout: TimeInterval = 300, maxTracked: Int = 256,
                now: @escaping () -> Date = Date.init) {
        self.maxFailures = maxFailures
        self.lockout = lockout
        self.maxTracked = maxTracked
        self.now = now
    }

    var trackedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return entries.count
    }

    /// `authorization` is the raw header value; `peer` the client's IP address.
    public func check(_ authorization: String?, expected: String?, peer: String) -> Outcome {
        guard let expected, !expected.isEmpty else { return .notConfigured }
        lock.lock(); defer { lock.unlock() }
        let t = now()
        if let until = entries[peer]?.lockedUntil {
            if t < until { return .locked(until: until) }
            entries[peer] = nil
        }
        if let token = MCPToken.bearer(from: authorization), ConstantTime.equals(token, expected) {
            entries[peer] = nil
            return .ok
        }
        var entry = entries[peer] ?? Entry(lastSeen: t)
        entry.failures += 1
        entry.lastSeen = t
        if entry.failures >= maxFailures { entry.lockedUntil = t.addingTimeInterval(lockout) }
        entries[peer] = entry
        prune(at: t)
        return .unauthorized
    }

    /// Drops expired lockouts, then the oldest entries beyond `maxTracked`,
    /// so a scan from many addresses cannot grow the table without bound.
    private func prune(at t: Date) {
        entries = entries.filter { _, e in e.lockedUntil.map { t < $0 } ?? (t.timeIntervalSince(e.lastSeen) < lockout) }
        guard entries.count > maxTracked else { return }
        let oldest = entries.sorted { $0.value.lastSeen < $1.value.lastSeen }.prefix(entries.count - maxTracked)
        for (key, _) in oldest { entries[key] = nil }
    }
}
