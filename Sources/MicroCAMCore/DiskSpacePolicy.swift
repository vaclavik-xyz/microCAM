public enum DiskSpaceStatus: Equatable, Sendable { case ok, low, critical }

public enum DiskSpacePolicy {
    /// Warn below ~2 h of standard HEVC 1080p60; stop recording below 500 MB.
    public static let lowBytes: Int64 = 5_000_000_000
    public static let criticalBytes: Int64 = 500_000_000

    public static func status(availableBytes: Int64) -> DiskSpaceStatus {
        if availableBytes < criticalBytes { return .critical }
        if availableBytes < lowBytes { return .low }
        return .ok
    }
}
