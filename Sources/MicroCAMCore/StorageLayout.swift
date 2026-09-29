import Foundation

/// Where captures go right now.
public enum JobContext: Equatable, Sendable {
    case job(JobCode)
    case unassigned
    case jobsDisabled
}

public enum StorageError: Error, Equatable {
    case rootUnavailable(URL)
    case cannotCreateFolder(URL)
}

/// Default layout is flat: `<root>/<CODE>/`, `<root>/_Nezařazeno/`, or
/// `<root>` itself when jobs are disabled. With `sortByType` (user opt-in) a
/// type folder (`Fotky`, `Videa`, `Časosběr`) is appended.
public struct StorageLayout: Sendable {
    public static let unassignedFolderName = "_Nezařazeno"

    public let root: URL
    public let sortByType: Bool

    public init(root: URL, sortByType: Bool = false) {
        self.root = root
        self.sortByType = sortByType
    }

    public func baseFolder(for context: JobContext) -> URL {
        switch context {
        case .job(let code): root.appendingPathComponent(code.value, isDirectory: true)
        case .unassigned: root.appendingPathComponent(Self.unassignedFolderName, isDirectory: true)
        case .jobsDisabled: root
        }
    }

    public func folder(for context: JobContext, kind: CaptureKind) -> URL {
        let base = baseFolder(for: context)
        return sortByType ? base.appendingPathComponent(kind.typeFolderName, isDirectory: true) : base
    }

    /// Folders the side panel lists for a context. With `sortByType` the base
    /// folder is included too, so files saved before the user switched modes
    /// stay visible.
    public func listedFolders(for context: JobContext) -> [URL] {
        let base = baseFolder(for: context)
        return sortByType ? [base] + CaptureKind.allCases.map { folder(for: context, kind: $0) } : [base]
    }

    public static func prefix(for context: JobContext) -> String {
        switch context {
        case .job(let code): code.value
        case .unassigned: "bez-zakazky"
        case .jobsDisabled: "microcam"
        }
    }

    /// Returns the target folder, creating only job/unassigned/type
    /// subfolders. The root itself is never created: a missing root (e.g. an
    /// iCloud folder that is not there) must fail loudly instead of writing
    /// somewhere unexpected.
    public func prepareFolder(for context: JobContext, kind: CaptureKind,
                              fileManager: FileManager = .default) throws -> URL {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            throw StorageError.rootUnavailable(root)
        }
        let folder = folder(for: context, kind: kind)
        if fileManager.fileExists(atPath: folder.path, isDirectory: &isDir) {
            guard isDir.boolValue else { throw StorageError.cannotCreateFolder(folder) }
            return folder
        }
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw StorageError.cannotCreateFolder(folder)
        }
        return folder
    }
}
