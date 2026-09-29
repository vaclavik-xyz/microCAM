import CryptoKit
import Foundation

/// `multipart/form-data` body builder.
public struct MultipartBody {
    public let boundary: String
    private var data = Data()

    public init(boundary: String = "microcam-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    public func field(_ name: String, _ value: String) -> MultipartBody {
        var copy = self
        copy.data.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        return copy
    }

    public func file(_ name: String, filename: String, mimeType: String, data fileData: Data) -> MultipartBody {
        var copy = self
        copy.data.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8))
        copy.data.append(fileData)
        copy.data.append(Data("\r\n".utf8))
        return copy
    }

    public func finalized() -> Data {
        data + Data("--\(boundary)--\r\n".utf8)
    }
}

public enum WebhookError: Error, Equatable {
    case httpStatus(Int)
    case notHTTP
}

/// Generic integration: POSTs one capture as `multipart/form-data`.
///
/// Fields: `file`, `kind` (`photo` | `video` | `timelapse`), `capturedAt`
/// (ISO 8601 from the file name), `idempotencyKey` (SHA-256 of the content,
/// also sent as the `Idempotency-Key` header), and `job` when the file
/// belongs to a repair order. Optional `Authorization: Bearer <token>`.
/// Any receiver can accept this: an own server, n8n, Make, Zapier, or a small
/// endpoint in the the CRM.
public struct WebhookClient {
    public let endpoint: URL
    public let token: String?
    private let session: URLSession

    public init(endpoint: URL, token: String?, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.token = token
        self.session = session
    }

    /// Job code from the capture's file name; nil for unassigned/jobless files.
    public static func jobCode(for file: URL) -> String? {
        guard let name = CaptureFileName.parse(file.lastPathComponent),
              name.prefix != StorageLayout.prefix(for: .unassigned),
              name.prefix != StorageLayout.prefix(for: .jobsDisabled) else { return nil }
        return JobCode(name.prefix)?.value
    }

    public func upload(file: URL) async throws {
        let data = try Data(contentsOf: file)
        let key = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let kind = CaptureKind.fromTypeFolder(file.deletingLastPathComponent().lastPathComponent)
            ?? CaptureKind.fromExtension(file.pathExtension)
        var body = MultipartBody()
        if let job = Self.jobCode(for: file) { body = body.field("job", job) }
        body = body.field("kind", kind.webhookName)
        if let captured = Self.capturedAt(file) { body = body.field("capturedAt", captured) }
        body = body.field("idempotencyKey", key)
            .file("file", filename: file.lastPathComponent,
                  mimeType: kind == .video ? "video/quicktime" : "image/jpeg", data: data)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(body.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "Idempotency-Key")
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (_, response) = try await session.upload(for: request, from: body.finalized())
        guard let http = response as? HTTPURLResponse else { throw WebhookError.notHTTP }
        guard (200..<300).contains(http.statusCode) else { throw WebhookError.httpStatus(http.statusCode) }
    }

    private static func capturedAt(_ file: URL) -> String? {
        guard let name = CaptureFileName.parse(file.lastPathComponent) else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        guard let date = parser.date(from: name.timestamp) else { return nil }
        let iso = ISO8601DateFormatter()
        iso.timeZone = .current
        return iso.string(from: date)
    }
}

extension CaptureKind {
    public var webhookName: String {
        switch self {
        case .photo: "photo"
        case .video: "video"
        case .timelapse: "timelapse"
        }
    }
}
