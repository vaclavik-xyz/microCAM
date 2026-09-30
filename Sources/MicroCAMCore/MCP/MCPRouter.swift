import Foundation

/// MCP over Streamable HTTP: `POST /mcp`, one JSON-RPC message per request,
/// answered with `application/json` (no SSE, no sessions).
///
/// Speaks both protocol eras (modelcontextprotocol.io/specification):
/// - modern (`2026-07-28`): stateless, every request carries its version and
///   client capabilities in `params._meta`, mirrored into the
///   `MCP-Protocol-Version`, `Mcp-Method` and `Mcp-Name` headers; `server/discover`.
/// - legacy (`2025-03-26` … `2025-11-25`): `initialize` handshake. No session
///   id is issued, so every request stands on its own there too.
///
/// Order of checks: path and method, same origin, bearer token (with per-address
/// lockout), then the JSON-RPC message.
public final class MCPRouter {
    public static let modernVersion = "2026-07-28"
    /// Newest first.
    public static let legacyVersions = ["2025-11-25", "2025-06-18", "2025-03-26"]
    public static var supportedVersions: [String] { [modernVersion] + legacyVersions }
    public static let path = "/mcp"

    static let instructions = """
        microCAM is the live microscope camera at a repair bench. capture_frame shows what the camera sees \
        without saving anything; take_photo saves a photo like the person at the bench would. Captures go \
        to the current folder (and job, when jobs are on). The person at the Mac sees what you do.
        """

    private enum Era { case modern, legacy }

    /// A JSON-RPC failure with the HTTP status it is sent with.
    private struct RPCError: Error {
        var status = 200
        var code: Int
        var message: String
        var data: JSONValue? = nil
    }

    private weak var backend: MCPBackend?
    private let authGuard: MCPAuthGuard
    private let token: () -> String?
    private let serverVersion: String
    private let now: () -> Date

    public init(backend: MCPBackend, authGuard: MCPAuthGuard = MCPAuthGuard(), token: @escaping () -> String?,
                serverVersion: String, now: @escaping () -> Date = Date.init) {
        self.backend = backend
        self.authGuard = authGuard
        self.token = token
        self.serverVersion = serverVersion
        self.now = now
    }

    /// `peer` is the client's IP address (the lockout key).
    public func handle(_ request: HTTPRequest, peer: String, completion: @escaping (HTTPResponse) -> Void) {
        guard request.path == Self.path else { return completion(.text(404, "not found")) }
        guard request.method == "POST" else {
            var response = HTTPResponse.text(405, "method not allowed")
            response.headers.append(("Allow", "POST"))
            return completion(response)
        }
        if let origin = request.header("origin") {
            let originHost = URLComponents(string: origin).map { c in c.port.map { "\(c.host ?? ""):\($0)" } ?? (c.host ?? "") }
            guard originHost == request.header("host") else { return completion(.text(403, "origin not allowed")) }
        }
        switch authGuard.check(request.header("authorization"), expected: token(), peer: peer) {
        case .ok: break
        case .notConfigured: return completion(.text(503, "no token set"))
        case .unauthorized:
            var response = HTTPResponse.text(401, "missing or wrong token")
            response.headers.append(("WWW-Authenticate", #"Bearer realm="microCAM""#))
            return completion(response)
        case .locked(let until):
            var response = HTTPResponse.text(429, "too many wrong tokens, try again later")
            response.headers.append(("Retry-After", String(max(1, Int(until.timeIntervalSince(now()).rounded(.up))))))
            return completion(response)
        }
        guard let backend else { return completion(.text(503, "unavailable")) }
        handleMessage(request, backend: backend, completion: completion)
    }

    // MARK: JSON-RPC

    private func handleMessage(_ request: HTTPRequest, backend: MCPBackend, completion: @escaping (HTTPResponse) -> Void) {
        guard let message = try? JSONValue.parse(request.body) else {
            return completion(errorResponse(id: .null, RPCError(status: 400, code: -32700, message: "Parse error")))
        }
        if case .array = message {
            return completion(errorResponse(id: .null, RPCError(status: 400, code: -32600,
                                                                message: "Batches aren't supported. Send one message per request.")))
        }
        let rawID = message["id"]
        guard message["jsonrpc"] == "2.0", let method = message["method"]?.string else {
            return completion(errorResponse(id: rawID ?? .null, RPCError(status: 400, code: -32600, message: "Invalid Request")))
        }
        // A notification (no id) gets no answer.
        guard let id = rawID else { return completion(HTTPResponse(status: 202)) }
        switch id {
        case .string, .int: break
        default: return completion(errorResponse(id: .null, RPCError(status: 400, code: -32600,
                                                                      message: "The id must be a string or an integer.")))
        }
        let params = message["params"] ?? .object([:])
        guard params.object != nil else {
            return completion(errorResponse(id: id, RPCError(status: 400, code: -32602, message: "params must be an object")))
        }
        let era: Era
        do {
            era = try validate(request, method: method, params: params)
        } catch let error as RPCError {
            return completion(errorResponse(id: id, error))
        } catch {
            return completion(errorResponse(id: id, RPCError(code: -32603, message: "Internal error")))
        }
        dispatch(method, params: params, era: era, backend: backend) { [self] result in
            switch result {
            case .success(var value):
                if era == .modern, case .object(var o) = value {
                    o["resultType"] = "complete"
                    var meta = o["_meta"]?.object ?? [:]
                    meta["io.modelcontextprotocol/serverInfo"] = serverInfo
                    o["_meta"] = .object(meta)
                    value = .object(o)
                }
                completion(json(200, ["jsonrpc": "2.0", "id": id, "result": value]))
            case .failure(let error):
                completion(errorResponse(id: id, error))
            }
        }
    }

    /// Works out the era and enforces its header and metadata rules.
    private func validate(_ request: HTTPRequest, method: String, params: JSONValue) throws -> Era {
        let header = request.header("mcp-protocol-version")
        let meta = params["_meta"]
        if let version = meta?["io.modelcontextprotocol/protocolVersion"]?.string {
            guard Self.supportedVersions.contains(version) else { throw unsupported(version) }
            if version == Self.modernVersion {
                try checkModernHeaders(request, method: method, params: params, version: version)
                guard meta?["io.modelcontextprotocol/clientCapabilities"]?.object != nil else {
                    throw RPCError(status: 400, code: -32602,
                                   message: "_meta must include io.modelcontextprotocol/clientCapabilities")
                }
                return .modern
            }
            if let header, header != version {
                throw RPCError(status: 400, code: -32020, message: "MCP-Protocol-Version header doesn't match _meta")
            }
            return .legacy
        }
        if let header {
            if header == Self.modernVersion {
                throw RPCError(status: 400, code: -32602,
                               message: "Requests for \(Self.modernVersion) must carry io.modelcontextprotocol/protocolVersion and clientCapabilities in _meta")
            }
            guard Self.legacyVersions.contains(header) else { throw unsupported(header) }
        }
        return .legacy
    }

    private func checkModernHeaders(_ request: HTTPRequest, method: String, params: JSONValue, version: String) throws {
        func mismatch(_ text: String) -> RPCError { RPCError(status: 400, code: -32020, message: "Header mismatch: \(text)") }
        guard request.header("mcp-protocol-version") == version else {
            throw mismatch("MCP-Protocol-Version must be \(version)")
        }
        guard request.header("mcp-method") == method else { throw mismatch("Mcp-Method must be \(method)") }
        if method == "tools/call" {
            guard let raw = request.header("mcp-name"), let name = Self.decodeHeaderValue(raw),
                  name == params["name"]?.string else { throw mismatch("Mcp-Name must match params.name") }
        }
    }

    /// `=?base64?…?=` sentinel form or the plain value.
    static func decodeHeaderValue(_ raw: String) -> String? {
        guard raw.hasPrefix("=?base64?"), raw.hasSuffix("?="), raw.count >= 11 else { return raw }
        let encoded = String(raw.dropFirst(9).dropLast(2))
        return Data(base64Encoded: encoded).flatMap { String(data: $0, encoding: .utf8) }
    }

    private func unsupported(_ version: String) -> RPCError {
        RPCError(status: 400, code: -32022, message: "Unsupported protocol version",
                 data: ["supported": .array(Self.supportedVersions.map(JSONValue.string)), "requested": .string(version)])
    }

    private var serverInfo: JSONValue { ["name": "microCAM", "title": "microCAM", "version": .string(serverVersion)] }

    private func dispatch(_ method: String, params: JSONValue, era: Era, backend: MCPBackend,
                          completion: @escaping (Result<JSONValue, RPCError>) -> Void) {
        switch (method, era) {
        case ("initialize", .legacy):
            let requested = params["protocolVersion"]?.string ?? ""
            let version = Self.legacyVersions.contains(requested) ? requested : Self.legacyVersions[0]
            completion(.success(["protocolVersion": .string(version), "capabilities": capabilities,
                                 "serverInfo": serverInfo, "instructions": .string(Self.instructions)]))
        case ("server/discover", .modern):
            completion(.success(["supportedVersions": .array(Self.supportedVersions.map(JSONValue.string)),
                                 "capabilities": capabilities, "instructions": .string(Self.instructions)]))
        case ("ping", _):
            completion(.success([:]))
        case ("tools/list", _):
            completion(.success(["tools": .array(MCPTools.definitions(jobsEnabled: backend.status().jobsEnabled))]))
        case ("tools/call", _):
            guard let name = params["name"]?.string else {
                return completion(.failure(RPCError(code: -32602, message: "params.name must be a tool name")))
            }
            let arguments = params["arguments"]
            if let arguments, arguments.object == nil, arguments != .null {
                return completion(.failure(RPCError(code: -32602, message: "params.arguments must be an object")))
            }
            switch MCPToolCall.parse(name: name, arguments: arguments) {
            case .failure(.unknownTool(let tool)):
                completion(.failure(RPCError(code: -32602, message: "Unknown tool: \(tool)")))
            case .failure(.invalidArguments(let reason)):
                completion(.success(Self.toolError(reason)))
            case .success(let call):
                run(call, backend: backend) { completion(.success($0)) }
            }
        default:
            completion(.failure(RPCError(status: era == .modern ? 404 : 200, code: -32601,
                                         message: "Method not found: \(method)")))
        }
    }

    private var capabilities: JSONValue { ["tools": ["listChanged": false]] }

    // MARK: Tools

    private func run(_ call: MCPToolCall, backend: MCPBackend, completion: @escaping (JSONValue) -> Void) {
        switch call {
        case .getStatus:
            completion(Self.structured(statusJSON(backend.status())))
        case .captureFrame(let maxSize):
            backend.captureFrame(maxDimension: maxSize) { result in
                completion(Self.toolResult(result) { image in
                    Self.result([Self.imageBlock(image),
                                 Self.textBlock("Live picture, \(image.width)×\(image.height) px. Not saved.")])
                })
            }
        case .takePhoto(let maxSize):
            backend.takePhoto(maxDimension: maxSize) { result in
                completion(Self.toolResult(result) { photo in
                    Self.result([Self.imageBlock(photo.image),
                                 Self.textBlock("Photo saved: \(photo.file.lastPathComponent) (\(photo.file.path))")],
                                structured: ["name": .string(photo.file.lastPathComponent), "path": .string(photo.file.path)])
                })
            }
        case .listCaptures(let limit):
            let folders = backend.captureFolders()
            let files = MCPCaptureCatalog.list(in: folders, limit: limit)
            completion(Self.structured(["folder": backend.status().folder.map(JSONValue.string) ?? .null,
                                        "captures": .array(files.map(\.json))]))
        case .getCapture(let name, let maxSize):
            guard let file = MCPCaptureCatalog.resolve(name, in: backend.captureFolders()) else {
                return completion(Self.toolError(MCPToolError.captureNotFound(name).message))
            }
            guard file.kind != .video else {
                return completion(Self.structured(file.json))
            }
            backend.loadPhoto(file.url, maxDimension: maxSize) { result in
                completion(Self.toolResult(result) { image in
                    let text = String(decoding: file.json.serialized(), as: UTF8.self)
                    return Self.result([Self.imageBlock(image), Self.textBlock(text)], structured: file.json)
                })
            }
        case .startRecording:
            backend.startRecording { result in
                completion(Self.toolResult(result) { Self.result([Self.textBlock("Recording started.")]) })
            }
        case .stopRecording:
            backend.stopRecording { result in
                completion(Self.toolResult(result) { url in
                    Self.result([Self.textBlock("Recording stopped. Video saved: \(url.lastPathComponent) (\(url.path))")],
                                structured: ["name": .string(url.lastPathComponent), "path": .string(url.path)])
                })
            }
        case .setJob(let job):
            guard backend.status().jobsEnabled else { return completion(Self.toolError(MCPToolError.jobsDisabled.message)) }
            completion(Self.toolResult(backend.setJob(job)) { folder in
                Self.structured(["job": job.map { .string($0.value) } ?? .null,
                                 "folder": folder.map(JSONValue.string) ?? .null])
            })
        }
    }

    private func statusJSON(_ s: MCPStatus) -> JSONValue {
        var recording: [String: JSONValue] = ["active": .bool(s.recording == .recording), "state": .string(s.recording.rawValue)]
        if s.recording == .recording, let started = s.recordingStartedAt {
            recording["seconds"] = .int(max(0, Int(now().timeIntervalSince(started))))
            let iso = ISO8601DateFormatter()
            iso.timeZone = .current
            recording["startedAt"] = .string(iso.string(from: started))
        }
        let format: JSONValue = s.format.map { f in
            ["width": .int(f.width), "height": .int(f.height), "fps": .double(f.fps), "label": .string(f.label)]
        } ?? .null
        var timelapse: [String: JSONValue] = ["running": .bool(s.timelapse != nil)]
        if let t = s.timelapse { timelapse["shotsTaken"] = .int(t.shotsTaken); timelapse["shotCount"] = .int(t.shotCount) }
        return ["camera": ["name": s.cameraName.map(JSONValue.string) ?? .null, "connected": .bool(s.cameraName != nil)],
                "format": format, "recording": .object(recording), "timelapse": .object(timelapse),
                "folder": s.folder.map(JSONValue.string) ?? .null, "jobsEnabled": .bool(s.jobsEnabled),
                "job": s.job.map(JSONValue.string) ?? .null]
    }

    // MARK: Result building

    static func textBlock(_ text: String) -> JSONValue { ["type": "text", "text": .string(text)] }

    static func imageBlock(_ image: MCPImage) -> JSONValue {
        ["type": "image", "data": .string(image.jpeg.base64EncodedString()), "mimeType": "image/jpeg"]
    }

    static func result(_ content: [JSONValue], structured: JSONValue? = nil, isError: Bool = false) -> JSONValue {
        var out: [String: JSONValue] = ["content": .array(content), "isError": .bool(isError)]
        if let structured { out["structuredContent"] = structured }
        return .object(out)
    }

    /// Structured content, repeated as JSON text for clients that only read text.
    static func structured(_ value: JSONValue) -> JSONValue {
        result([textBlock(String(decoding: value.serialized(), as: UTF8.self))], structured: value)
    }

    static func toolError(_ message: String) -> JSONValue { result([textBlock(message)], isError: true) }

    static func toolResult<T>(_ result: Result<T, MCPToolError>, _ success: (T) -> JSONValue) -> JSONValue {
        switch result {
        case .success(let value): success(value)
        case .failure(let error): toolError(error.message)
        }
    }

    // MARK: HTTP

    private func json(_ status: Int, _ value: JSONValue) -> HTTPResponse {
        HTTPResponse(status: status, headers: [("Content-Type", "application/json")], body: value.serialized())
    }

    private func errorResponse(id: JSONValue, _ error: RPCError) -> HTTPResponse {
        var body: [String: JSONValue] = ["code": .int(error.code), "message": .string(error.message)]
        if let data = error.data { body["data"] = data }
        return json(error.status, ["jsonrpc": "2.0", "id": id, "error": .object(body)])
    }
}
