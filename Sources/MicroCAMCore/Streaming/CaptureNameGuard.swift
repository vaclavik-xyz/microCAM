import Foundation

/// Maps a name from a URL to a capture file, refusing anything that is not a
/// plain capture file name existing directly in one of `folders`.
public enum CaptureNameGuard {
    public static func resolve(_ rawName: String, in folders: [URL], fileManager: FileManager = .default) -> URL? {
        guard let name = rawName.removingPercentEncoding, !name.isEmpty,
              !name.contains("/"), !name.contains("\\"), !name.hasPrefix("."),
              let parsed = CaptureFileName.parse(name), parsed.ext.lowercased() == "jpg" else { return nil }
        for folder in folders {
            let candidate = folder.appendingPathComponent(name, isDirectory: false)
            guard candidate.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL else { continue }
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDir), !isDir.boolValue {
                return candidate
            }
        }
        return nil
    }
}
