import Foundation

public enum CaptureLibrary {
    /// Capture files directly inside each folder (not recursive), merged and
    /// sorted newest first by the timestamp in the name, then collision index.
    public static func captureFiles(in folders: [URL], fileManager: FileManager = .default) -> [URL] {
        let parsed: [(URL, CaptureFileName)] = folders.flatMap { folder -> [(URL, CaptureFileName)] in
            let urls = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                             options: [.skipsHiddenFiles])) ?? []
            return urls.compactMap { url in CaptureFileName.parse(url.lastPathComponent).map { (url, $0) } }
        }
        return parsed.sorted { a, b in
            if a.1.timestamp != b.1.timestamp { return a.1.timestamp > b.1.timestamp }
            return (a.1.index ?? 1) > (b.1.index ?? 1)
        }.map(\.0)
    }
}
