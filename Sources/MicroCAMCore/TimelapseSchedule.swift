import Foundation

public struct TimelapseSchedule: Equatable, Sendable {
    public static let maxDuration: TimeInterval = 7 * 24 * 3600

    public let interval: TimeInterval
    public let duration: TimeInterval

    public init?(interval: TimeInterval, duration: TimeInterval) {
        guard interval >= 1, duration >= interval, duration <= Self.maxDuration else { return nil }
        self.interval = interval
        self.duration = duration
    }

    /// One shot at start plus one per full interval.
    public var shotCount: Int { Int(duration / interval) + 1 }

    public func isFinished(shotsTaken: Int) -> Bool { shotsTaken >= shotCount }

    /// When the last photo is due ("done around …").
    public func lastShot(startedAt start: Date) -> Date {
        start.addingTimeInterval(Double(shotCount - 1) * interval)
    }

    /// When the next photo is due, or nil once all are taken.
    public func nextShot(startedAt start: Date, shotsTaken: Int) -> Date? {
        isFinished(shotsTaken: shotsTaken) ? nil : start.addingTimeInterval(Double(shotsTaken) * interval)
    }
}
