import AppKit
import MicroCAMCore
import QuickLookThumbnailing

@MainActor
final class LibraryModel: ObservableObject {
    @Published private(set) var files: [URL] = []
    @Published var grid = GridSelection<URL>()
    var selection: Set<URL> { grid.selected }
    /// Selected files in list order (newest first).
    var selectedFiles: [URL] { files.filter(grid.selected.contains) }

    private let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 300
        return cache
    }()
    private var reloadTask: Task<Void, Never>?
    private var pendingSelection: URL?

    /// Selects `url` once the next reload lists it (a copy just saved).
    func selectAfterReload(_ url: URL) { pendingSelection = url }

    func reload(folders: [URL]) {
        reloadTask?.cancel()
        reloadTask = Task {
            let found = await Task.detached(priority: .utility) { CaptureLibrary.captureFiles(in: folders) }.value
            guard !Task.isCancelled else { return }
            files = found
            grid.selected.formIntersection(found)
            if let anchor = grid.anchor, !found.contains(anchor) { grid.anchor = nil }
            if let url = pendingSelection, found.contains(url) {
                grid = GridSelection(selected: [url], anchor: url)
                pendingSelection = nil
            }
        }
    }

    /// A thumbnail already made for a tile, e.g. for the image of a drag.
    func cachedThumbnail(for url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }

    func thumbnail(for url: URL) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 180, height: 135),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2,
                                                   representationTypes: .thumbnail)
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        else { return nil }
        let image = representation.nsImage
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
