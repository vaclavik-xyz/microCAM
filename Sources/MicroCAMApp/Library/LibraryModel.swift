import AppKit
import MicroCAMCore
import QuickLookThumbnailing

@MainActor
final class LibraryModel: ObservableObject {
    @Published private(set) var files: [URL] = []
    @Published var selection = Set<URL>()

    private let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 300
        return cache
    }()
    private var reloadTask: Task<Void, Never>?

    func reload(folders: [URL]) {
        reloadTask?.cancel()
        reloadTask = Task {
            let found = await Task.detached(priority: .utility) { CaptureLibrary.captureFiles(in: folders) }.value
            guard !Task.isCancelled else { return }
            files = found
            selection.formIntersection(found)
        }
    }

    func thumbnail(for url: URL) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 120, height: 90),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2,
                                                   representationTypes: .thumbnail)
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        else { return nil }
        let image = representation.nsImage
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
