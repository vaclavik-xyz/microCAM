import Foundation

public struct MCPCaptureFile: Equatable, Sendable {
    public var url: URL
    public var kind: CaptureKind
    /// ISO 8601 from the file name.
    public var capturedAt: String?
    public var sizeBytes: Int

    public var name: String { url.lastPathComponent }

    public var json: JSONValue {
        ["name": .string(name), "path": .string(url.path), "kind": .string(kind.webhookName),
         "capturedAt": capturedAt.map(JSONValue.string) ?? .null, "sizeBytes": .int(sizeBytes)]
    }
}

/// Captures an agent may list and open: files named like captures directly
/// in the folders of the current job, nothing else.
public enum MCPCaptureCatalog {
    public static func list(in folders: [URL], limit: Int) -> [MCPCaptureFile] {
        CaptureLibrary.captureFiles(in: folders)
            .filter { ["jpg", "mov"].contains($0.pathExtension.lowercased()) }
            .prefix(limit).map(describe)
    }

    public static func resolve(_ name: String, in folders: [URL]) -> MCPCaptureFile? {
        CaptureNameGuard.resolve(name, in: folders, extensions: ["jpg", "mov"]).map(describe)
    }

    static func describe(_ url: URL) -> MCPCaptureFile {
        let kind = CaptureKind.fromTypeFolder(url.deletingLastPathComponent().lastPathComponent)
            ?? CaptureKind.fromExtension(url.pathExtension)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return MCPCaptureFile(url: url, kind: kind, capturedAt: WebhookClient.capturedAt(url), sizeBytes: size)
    }
}
