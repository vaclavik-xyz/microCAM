import Foundation

public enum CaptureKind: CaseIterable, Sendable {
    case photo, video, timelapse

    public var fileExtension: String {
        switch self {
        case .photo, .timelapse: "jpg"
        case .video: "mov"
        }
    }

    /// Subfolder name used only when the user enables "Třídit podle typu".
    public var typeFolderName: String {
        switch self {
        case .photo: "Fotky"
        case .video: "Videa"
        case .timelapse: "Časosběr"
        }
    }

    public static func fromTypeFolder(_ name: String) -> CaptureKind? {
        allCases.first { $0.typeFolderName == name }
    }

    /// Best guess from the extension when the folder does not tell.
    public static func fromExtension(_ ext: String) -> CaptureKind {
        ext.lowercased() == "mov" ? .video : .photo
    }
}

/// `<prefix>_<yyyy-MM-dd_HH-mm-ss>[_n].<ext>`
public struct CaptureFileName: Equatable, Sendable {
    public let prefix: String
    public let timestamp: String
    public let index: Int?
    public let ext: String

    public init(prefix: String, timestamp: String, index: Int?, ext: String) {
        self.prefix = prefix
        self.timestamp = timestamp
        self.index = index
        self.ext = ext
    }

    public var fileName: String {
        let suffix = index.map { "_\($0)" } ?? ""
        return "\(prefix)_\(timestamp)\(suffix).\(ext)"
    }

    public static func timestampString(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: date)
    }

    private static let pattern = try! NSRegularExpression(
        pattern: #"^([A-Za-z0-9-]+)_(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})(?:_(\d+))?\.([A-Za-z0-9]+)$"#
    )

    public static func parse(_ name: String) -> CaptureFileName? {
        let range = NSRange(name.startIndex..., in: name)
        guard let match = pattern.firstMatch(in: name, range: range) else { return nil }
        func group(_ i: Int) -> String? {
            Range(match.range(at: i), in: name).map { String(name[$0]) }
        }
        guard let prefix = group(1), let timestamp = group(2), let ext = group(4) else { return nil }
        return CaptureFileName(prefix: prefix, timestamp: timestamp, index: group(3).flatMap(Int.init), ext: ext)
    }
}
