import Foundation

/// Which folder the stream page's photo browser shows: the camera Mac's
/// current one, the photos without a job, or a job. Looking at another job
/// never changes the job the camera Mac saves into.
public enum GalleryFolder: Equatable, Sendable {
    case current
    case unassigned
    case job(JobCode)

    static let unassignedToken = "_unassigned"

    /// The `folder` query value: missing or empty for the current folder,
    /// `_unassigned`, or a job code exactly as microCAM writes it. nil for
    /// anything else.
    public init?(query: String?) {
        guard let raw = query, !raw.isEmpty else { self = .current; return }
        if raw == Self.unassignedToken { self = .unassigned; return }
        guard let code = JobCode(raw), code.value == raw else { return nil }
        self = .job(code)
    }

    /// The value for `?folder=`; empty for the current folder.
    public var token: String {
        switch self {
        case .current: ""
        case .unassigned: Self.unassignedToken
        case .job(let code): code.value
        }
    }
}

/// Where the camera Mac saves, as the stream needs it.
public struct StreamStorage: Sendable {
    public let layout: StorageLayout
    public let context: JobContext

    public init(layout: StorageLayout, context: JobContext) {
        self.layout = layout
        self.context = context
    }

    public var jobsEnabled: Bool { context != .jobsDisabled }

    /// The job context a gallery folder stands for; nil for a job or the
    /// photos without a job while jobs are off.
    public func context(for folder: GalleryFolder) -> JobContext? {
        switch folder {
        case .current: context
        case .unassigned: jobsEnabled ? .unassigned : nil
        case .job(let code): jobsEnabled ? .job(code) : nil
        }
    }

    /// The folders a gallery folder lists, like the side panel: every
    /// language and, with `sortByType`, the type folders. Never anything
    /// outside the storage root.
    public func folders(for folder: GalleryFolder) -> [URL]? {
        context(for: folder).map(layout.listedFolders(for:))
    }
}

/// A photo in the gallery, with the addresses of the photo and its thumbnail.
public struct GalleryPhoto: Encodable, Equatable, Sendable {
    public let name: String
    public let url: String
    public let thumb: String

    public init(name: String, folder: GalleryFolder) {
        self.name = name
        url = CaptureRef(name: name, folder: folder).url
        thumb = StreamGallery.path("/thumbs/", name: name, folder: folder)
    }
}

public struct GalleryDay: Encodable, Equatable, Sendable {
    /// "2026-09-25", or "" for names without a date.
    public let day: String
    public let photos: [GalleryPhoto]
}

/// `GET /gallery` for the stream page.
public struct GalleryListing: Encodable, Equatable, Sendable {
    /// The `?folder=` value to read these photos and save drawings next to them.
    public let folder: String
    /// The job shown; nil for photos without a job or with jobs off.
    public let job: String?
    /// It is the camera Mac's current folder, so new photos show up in it.
    public let current: Bool
    /// Jobs are on: the page offers other jobs and the photos without one.
    public let jobs: Bool
    /// Newest first.
    public let days: [GalleryDay]
    /// Older photos were left out (`StreamGallery.limit`).
    public let more: Bool
}

/// `GET /jobs`: the job folders, newest capture first.
public struct GalleryJob: Encodable, Equatable, Sendable {
    public let code: String
    public let files: Int
    public let lastDay: String?

    public init(_ job: JobSummary) {
        code = job.code.value
        files = job.files
        lastDay = job.lastDay
    }
}

public enum StreamGallery {
    /// The newest photos a listing shows. Without jobs every photo sits in
    /// one folder, and a page with thousands of thumbnails gets slow.
    public static let limit = 500

    /// Photos only: the stream sends JPEGs, not videos.
    public static func listing(_ folder: GalleryFolder, storage: StreamStorage, limit: Int = limit,
                               fileManager: FileManager = .default) -> GalleryListing? {
        guard let context = storage.context(for: folder), let folders = storage.folders(for: folder) else { return nil }
        let photos = CaptureLibrary.captureFiles(in: folders, fileManager: fileManager)
            .filter { CaptureFileName.parse($0.lastPathComponent)?.ext.lowercased() == "jpg" }
        let shown = Array(photos.prefix(limit))
        let job: String? = if case .job(let code) = context { code.value } else { nil }
        return GalleryListing(
            folder: folder.token, job: job, current: context == storage.context, jobs: storage.jobsEnabled,
            days: CaptureDays.group(shown).map { day in
                GalleryDay(day: day.day, photos: day.files.map { GalleryPhoto(name: $0.lastPathComponent, folder: folder) })
            },
            more: photos.count > shown.count)
    }

    static func path(_ prefix: String, name: String, folder: GalleryFolder) -> String {
        let base = prefix + (name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name)
        return folder.token.isEmpty ? base : base + "?folder=" + folder.token
    }
}

/// Small JPEGs for the gallery grid, kept in memory by file and modification
/// date, so scrolling back and new photos in the current folder cost nothing.
public final class ThumbnailCache: @unchecked Sendable {
    public static let maxDimension = 360

    private let cache = NSCache<NSString, NSData>()

    public init(countLimit: Int = 1_000) {
        cache.countLimit = countLimit
    }

    public func jpeg(for file: URL, fileManager: FileManager = .default) -> Data? {
        let modified = (try? fileManager.attributesOfItem(atPath: file.path)[.modificationDate] as? Date)?
            .timeIntervalSinceReferenceDate ?? 0
        let key = "\(file.standardizedFileURL.path)|\(modified)" as NSString
        if let hit = cache.object(forKey: key) { return hit as Data }
        guard let jpeg = JPEGScaler.scaled(contentsOf: file, maxDimension: Self.maxDimension, quality: 0.7)?.jpeg else { return nil }
        cache.setObject(jpeg as NSData, forKey: key)
        return jpeg
    }
}
