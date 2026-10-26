import Foundation

public struct StreamStatus: Codable, Equatable, Sendable {
    public var job: String?
    public var mode: StreamMode
    public var photoEnabled: Bool
    public var viewers: Int
    /// Goes up whenever captures change on the camera Mac, so an open photo
    /// browser knows when to reload.
    public var captures: Int
    public init(job: String?, mode: StreamMode, photoEnabled: Bool, viewers: Int, captures: Int = 0) {
        self.job = job; self.mode = mode; self.photoEnabled = photoEnabled; self.viewers = viewers; self.captures = captures
    }
}

public struct CaptureRef: Codable, Equatable, Sendable {
    public var name: String
    public var url: String
    public init(name: String, folder: GalleryFolder = .current) {
        self.name = name
        url = StreamGallery.path("/captures/", name: name, folder: folder)
    }
}

public protocol StreamBackend: AnyObject {
    func status() -> StreamStatus
    func page(mode: StreamMode, embedded: Bool) -> String
    /// nil while no storage folder is chosen.
    func storage() -> StreamStorage?
    /// `delay` is the self-timer countdown in seconds (0: right away); the
    /// completion runs once the photo is saved, after the countdown.
    func takePhoto(delay: Int, completion: @escaping (Result<String, Error>) -> Void)
    func saveAnnotated(_ request: AnnotationRequest, source: URL, completion: @escaping (Result<String, Error>) -> Void)
}

/// Photo failures the stream page explains in its own language: the
/// self-timer is already counting down (from another device or the camera
/// computer), or someone at the camera computer cancelled it.
public enum StreamPhotoError: Error, Equatable {
    case selfTimerBusy, selfTimerCancelled
}

/// The two live feeds: H.264 in fragmented MP4 for Media Source Extensions,
/// and Motion JPEG for browsers without them.
public enum LiveFeed: Sendable {
    case video
    case mjpeg
}

public enum StreamRoute {
    case response(HTTPResponse)
    case stream(LiveFeed)
}

public final class StreamRouter {
    private struct ErrorBody: Encodable { let error: String; var retryAfter: Int? = nil }
    private struct JobList: Encodable { let jobs: [GalleryJob] }

    private weak var backend: StreamBackend?
    private let pinGuard: PinGuard
    private let mode: () -> StreamMode
    private let pin: () -> String?
    /// Runs file work (listing folders, reading photos, thumbnails) off the
    /// main queue; tests run it in place.
    private let work: (@escaping () -> Void) -> Void
    private let thumbnails = ThumbnailCache()

    public init(backend: StreamBackend, pinGuard: PinGuard = PinGuard(),
                mode: @escaping () -> StreamMode, pin: @escaping () -> String?,
                work: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.global(qos: .userInitiated).async(execute: $0) }) {
        self.backend = backend
        self.pinGuard = pinGuard
        self.mode = mode
        self.pin = pin
        self.work = work
    }

    public func handle(_ request: HTTPRequest, completion: @escaping (StreamRoute) -> Void) {
        guard let backend else { return completion(.response(.text(503, "unavailable"))) }
        let path = request.path
        if request.method == "OPTIONS" { return completion(.response(.text(405, "no"))) }

        switch (request.method, path) {
        case ("GET", "/"):
            completion(.response(.html(backend.page(mode: mode(), embedded: request.query["embedded"] == "1"))))
        case ("GET", "/status"):
            completion(.response(.json(200, backend.status())))
        case ("GET", "/stream"):
            completion(.stream(.mjpeg))
        case ("GET", "/video"):
            completion(.stream(.video))
        case (_, _) where path.hasPrefix("/captures/") || path.hasPrefix("/thumbs/"):
            if let denied = remoteActionDenied(request, method: "GET") { return completion(.response(denied)) }
            let thumb = path.hasPrefix("/thumbs/")
            let name = String(path.dropFirst(thumb ? "/thumbs/".count : "/captures/".count))
            guard let folder = GalleryFolder(query: request.query["folder"]),
                  let file = CaptureNameGuard.resolve(name, in: backend.storage()?.folders(for: folder) ?? [])
            else { return completion(.response(.text(404, "not found"))) }
            work { [thumbnails] in
                guard let data = thumb ? thumbnails.jpeg(for: file) : try? Data(contentsOf: file) else {
                    return completion(.response(.text(404, "not found")))
                }
                completion(.response(HTTPResponse(status: 200, headers: [("Content-Type", "image/jpeg")], body: data)))
            }
        case (_, "/gallery"):
            if let denied = remoteActionDenied(request, method: "GET") { return completion(.response(denied)) }
            guard let folder = GalleryFolder(query: request.query["folder"]) else {
                return completion(.response(.json(400, ErrorBody(error: "folder"))))
            }
            guard let storage = backend.storage() else { return completion(.response(.json(404, ErrorBody(error: "storage")))) }
            work {
                guard let listing = StreamGallery.listing(folder, storage: storage) else {
                    return completion(.response(.json(404, ErrorBody(error: "folder"))))
                }
                completion(.response(.json(200, listing)))
            }
        case (_, "/jobs"):
            if let denied = remoteActionDenied(request, method: "GET") { return completion(.response(denied)) }
            guard let storage = backend.storage(), storage.jobsEnabled else { return completion(.response(.json(200, JobList(jobs: [])))) }
            work { completion(.response(.json(200, JobList(jobs: JobFinder.jobs(in: storage.layout).map(GalleryJob.init))))) }
        case (_, "/photo"), (_, "/annotated"):
            if let denied = remoteActionDenied(request, method: "POST") { return completion(.response(denied)) }
            path == "/photo" ? photo(request, backend, completion) : annotated(request, backend, completion)
        case (_, "/"), (_, "/status"), (_, "/stream"), (_, "/video"):
            completion(.response(.text(405, "method not allowed")))
        default:
            completion(.response(.text(404, "not found")))
        }
    }

    /// Photos, annotated copies and reading captures (the gallery, its
    /// thumbnails and the job list too) all need controls
    /// mode, the expected method, the same origin and the PIN header (which a
    /// cross-site page cannot send without a CORS preflight we never answer).
    private func remoteActionDenied(_ request: HTTPRequest, method: String) -> HTTPResponse? {
        guard mode() == .controls else { return .json(403, ErrorBody(error: "disabled")) }
        guard request.method == method else { return .text(405, "method not allowed") }
        if let origin = request.header("origin") {
            let originHost = URLComponents(string: origin).map { c in
                c.port.map { "\(c.host ?? ""):\($0)" } ?? (c.host ?? "")
            }
            guard originHost == request.header("host") else { return .json(403, ErrorBody(error: "origin")) }
        }
        switch pinGuard.check(request.header("x-microcam-pin"), expected: pin()) {
        case .ok: return nil
        case .notConfigured: return .json(403, ErrorBody(error: "pin-not-set"))
        case .wrong: return .json(401, ErrorBody(error: "pin"))
        case .locked(let until):
            return .json(429, ErrorBody(error: "locked", retryAfter: max(1, Int(until.timeIntervalSinceNow.rounded(.up)))))
        }
    }

    /// `POST /photo?delay=5`: the answer comes after the countdown and the
    /// photo. 409 `busy` / `cancelled` when the self-timer is in the way.
    private func photo(_ request: HTTPRequest, _ backend: StreamBackend, _ completion: @escaping (StreamRoute) -> Void) {
        guard let delay = SelfTimer.remoteDelay(query: request.query["delay"]) else {
            return completion(.response(.json(400, ErrorBody(error: "delay"))))
        }
        backend.takePhoto(delay: delay) { result in
            switch result {
            case .success(let name): completion(.response(.json(200, CaptureRef(name: name))))
            case .failure(let error as StreamPhotoError):
                completion(.response(.json(409, ErrorBody(error: error == .selfTimerBusy ? "busy" : "cancelled"))))
            case .failure(let error): completion(.response(.json(500, ErrorBody(error: error.localizedDescription))))
            }
        }
    }

    private func annotated(_ request: HTTPRequest, _ backend: StreamBackend, _ completion: @escaping (StreamRoute) -> Void) {
        guard let decoded = try? JSONDecoder().decode(AnnotationRequest.self, from: request.body) else {
            return completion(.response(.json(400, ErrorBody(error: "json"))))
        }
        let clean = decoded.sanitized()
        guard let folder = GalleryFolder(query: clean.folder),
              let source = CaptureNameGuard.resolve(clean.source, in: backend.storage()?.folders(for: folder) ?? []) else {
            return completion(.response(.json(404, ErrorBody(error: "source"))))
        }
        // The copy lands next to the source, so it is read from the same folder.
        backend.saveAnnotated(clean, source: source) { result in
            switch result {
            case .success(let name): completion(.response(.json(200, CaptureRef(name: name, folder: folder))))
            case .failure(let error): completion(.response(.json(500, ErrorBody(error: error.localizedDescription))))
            }
        }
    }
}
