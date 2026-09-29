import Foundation

/// Human-readable folder path for Settings: `iCloud Drive/…` instead of
/// `~/Library/Mobile Documents/com~apple~CloudDocs/…`, and `~` for home.
public enum DisplayPath {
    public static func string(for path: String, home: String = NSHomeDirectory()) -> String {
        let iCloud = home + "/Library/Mobile Documents/com~apple~CloudDocs"
        if path == iCloud || path.hasPrefix(iCloud + "/") {
            return "iCloud Drive" + path.dropFirst(iCloud.count)
        }
        if path == home || path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
