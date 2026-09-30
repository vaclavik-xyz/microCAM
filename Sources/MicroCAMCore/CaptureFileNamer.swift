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

    public func nextURL(in folder: URL, prefix: String, kind: CaptureKind, date: Date,
                        timeZone: TimeZone = .current) -> URL {
        availableURL(in: folder,
                     prefix: prefix,
                     timestamp: CaptureFileName.timestampString(date, timeZone: timeZone),
                     ext: kind.fileExtension)
    }

    /// Where an edited photo goes: next to the original, as the next free
    /// index of its timestamp (`…_2.jpg`), always JPEG. The original is never
    /// the answer. Files with another name get `<name>_2.jpg`, `_3`, …
    public func editedCopyURL(of source: URL) -> URL {
        let folder = source.deletingLastPathComponent()
        if let name = CaptureFileName.parse(source.lastPathComponent) {
            return availableURL(in: folder, prefix: name.prefix, timestamp: name.timestamp, ext: "jpg")
        }
        let stem = source.deletingPathExtension().lastPathComponent
        var index = 2
        while true {
            let url = folder.appendingPathComponent("\(stem)_\(index).jpg", isDirectory: false)
            if !fileExists(url) { return url }
            index += 1
        }
    }
}
