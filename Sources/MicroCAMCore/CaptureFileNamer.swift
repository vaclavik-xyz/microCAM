import Foundation

/// Picks a file URL that does not exist yet. Never overwrites: a collision
/// within the same second gets `_2`, `_3`, …
public struct CaptureFileNamer {
    private let fileExists: (URL) -> Bool

    public init(fileExists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) {
        self.fileExists = fileExists
    }

    public func availableURL(in folder: URL, prefix: String, timestamp: String, ext: String) -> URL {
        var index: Int? = nil
        while true {
            let name = CaptureFileName(prefix: prefix, timestamp: timestamp, index: index, ext: ext)
            let url = folder.appendingPathComponent(name.fileName, isDirectory: false)
            if !fileExists(url) { return url }
            index = (index ?? 1) + 1
        }
    }

    public func nextURL(in folder: URL, context: JobContext, kind: CaptureKind, date: Date,
                        timeZone: TimeZone = .current) -> URL {
        availableURL(in: folder,
                     prefix: StorageLayout.prefix(for: context),
                     timestamp: CaptureFileName.timestampString(date, timeZone: timeZone),
                     ext: kind.fileExtension)
    }
}
