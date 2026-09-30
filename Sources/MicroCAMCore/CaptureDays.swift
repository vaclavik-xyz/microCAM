import Foundation

/// Side-panel sections: captures grouped by the day in their file name.
public struct CaptureDay: Equatable, Sendable {
    /// "2026-09-25", or "" for files whose name has no timestamp.
    public let day: String
    public let files: [URL]
}

public enum CaptureDays {
    /// Keeps the order of `files` (newest first from `CaptureLibrary`);
    /// unparsable names go into one group at the end.
    public static func group(_ files: [URL]) -> [CaptureDay] {
        var order: [String] = []
        var byDay: [String: [URL]] = [:]
        for url in files {
            let day = CaptureFileName.parse(url.lastPathComponent)
                .flatMap { $0.timestamp.split(separator: "_").first.map(String.init) } ?? ""
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(url)
        }
        let sorted = order.filter { !$0.isEmpty } + order.filter(\.isEmpty)
        return sorted.map { CaptureDay(day: $0, files: byDay[$0] ?? []) }
    }

    /// "14:30:05", "14:30:05 (3)" for the third capture in that second.
    public static func timeOfDay(_ url: URL) -> String {
        guard let name = CaptureFileName.parse(url.lastPathComponent) else { return url.lastPathComponent }
        let parts = name.timestamp.split(separator: "_")
        guard parts.count == 2 else { return name.timestamp }
        return parts[1].replacingOccurrences(of: "-", with: ":") + (name.index.map { " (\($0))" } ?? "")
    }

    public static func date(ofDay day: String, timeZone: TimeZone = .current) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: day)
    }
}
