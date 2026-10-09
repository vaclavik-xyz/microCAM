import Foundation
import MicroCAMCore

/// Bridges the router (called on the main queue by `HTTPServer`) to the
/// main-actor `AppModel`.
final class StreamBackendAdapter: StreamBackend {
    private unowned let model: AppModel

    init(model: AppModel) { self.model = model }

    func status() -> StreamStatus {
        MainActor.assumeIsolated {
            let s = model.settings
            return StreamStatus(job: s.jobsEnabled ? s.activeJob?.value : nil, mode: s.streamingMode,
                                photoEnabled: s.streamingMode == .controls && model.streamPIN != nil,
                                viewers: model.streamViewers)
        }
    }

    func page(mode: StreamMode, embedded: Bool) -> String { StreamPage.html(mode: mode, embedded: embedded) }

    func captureFolders() -> [URL] {
        MainActor.assumeIsolated { model.layout?.listedFolders(for: model.settings.jobContext) ?? [] }
    }

    func takePhoto(delay: Int, completion: @escaping (Result<String, Error>) -> Void) {
        MainActor.assumeIsolated {
            model.takePhoto(after: delay, source: .remote) { result in
                completion(result.map(\.lastPathComponent).mapError(Self.pageError))
            }
        }
    }

    /// The page shows its own text for a busy or cancelled self-timer.
    private static func pageError(_ error: Error) -> Error {
        switch error as? AppModel.SelfTimerError {
        case .busy: StreamPhotoError.selfTimerBusy
        case .cancelled: StreamPhotoError.selfTimerCancelled
        case .invalidDelay, nil: error
        }
    }

    func saveAnnotated(_ request: AnnotationRequest, source: URL, completion: @escaping (Result<String, Error>) -> Void) {
        MainActor.assumeIsolated {
            model.saveAnnotatedCopy(of: source, shapes: request.shapes) { completion($0.map(\.lastPathComponent)) }
        }
    }
}
