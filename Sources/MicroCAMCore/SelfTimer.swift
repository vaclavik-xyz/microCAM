import Foundation

/// Self-timer: a countdown before a photo, so both hands are free to hold a
/// probe or tweezers in the picture. While it's on in the toolbar, local
/// photos (Space, the photo button, ⌘T) wait for it; S starts one countdown
/// either way. The stream page and the Shortcuts action ask for their own delay.
public enum SelfTimer {
    /// The choices in the toolbar and on the stream page, in seconds.
    public static let delays = [3, 5, 10]
    public static let defaultDelay = 5
    /// The longest delay the stream page or a shortcut may ask for.
    public static let maxDelay = 30

    /// A delay asked for by another device or a shortcut: 0 is a photo right away.
    public static func isValid(remoteDelay seconds: Int) -> Bool { (0...maxDelay).contains(seconds) }

    /// The `delay` query parameter of `POST /photo`: missing means 0, anything
    /// but a whole number of seconds in range is nil (a bad request).
    public static func remoteDelay(query value: String?) -> Int? {
        guard let value else { return 0 }
        guard let seconds = Int(value), isValid(remoteDelay: seconds) else { return nil }
        return seconds
    }
}

/// One running countdown.
public struct SelfTimerCountdown: Equatable, Sendable {
    public let seconds: Int
    public let firesAt: Date

    public init(seconds: Int, startedAt: Date) {
        self.seconds = seconds
        firesAt = startedAt.addingTimeInterval(TimeInterval(seconds))
    }

    /// Whole seconds left, as shown on the picture: 5, 4, …, 1, then 0 when
    /// the photo is due.
    public func remaining(at now: Date) -> Int {
        max(0, Int(firesAt.timeIntervalSince(now).rounded(.up)))
    }

    public func isDue(at now: Date) -> Bool { remaining(at: now) == 0 }
}
