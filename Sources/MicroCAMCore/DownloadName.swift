import Foundation

/// Where microCAM's viewer saves a photo it downloads from the camera Mac:
/// in `folder`, under its own name, never over an existing file (a second
/// copy becomes `name 2.jpg`, as Finder names copies). A name from the
/// network is only ever a file name, never a path.
public enum DownloadName {
    public static func freeURL(for name: String, in folder: URL, exists: (URL) -> Bool) -> URL? {
        let file = (name as NSString).lastPathComponent
        guard !file.isEmpty, file != ".", file != "..", !file.hasPrefix(".") else { return nil }
        let base = (file as NSString).deletingPathExtension, ext = (file as NSString).pathExtension
        for n in 1...999 {
            let candidate = n == 1 ? file : ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            let url = folder.appendingPathComponent(candidate, isDirectory: false)
            if !exists(url) { return url }
        }
        return nil
    }
}
