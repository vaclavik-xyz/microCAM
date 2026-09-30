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

/// Default layout is flat: `<root>/<CODE>/`, `<root>/_Unsorted/`, or
/// `<root>` itself when jobs are disabled. With `sortByType` (user opt-in) a
/// type folder (`Photos`, `Videos`, `Timelapse`) is appended. Names follow
/// `language` (Czech: `_Nezařazeno`, `Fotky`, `Videa`, `Časosběr`).
public struct StorageLayout: Sendable {
    public static let jobsDisabledPrefix = "microcam"

    public let root: URL
    public let sortByType: Bool
    public let language: FolderLanguage

    public init(root: URL, sortByType: Bool = false, language: FolderLanguage) {
        self.root = root
        self.sortByType = sortByType
        self.language = language
    }

    public func baseFolder(for context: JobContext) -> URL {
        baseFolder(for: context, in: language)
    }

    public func folder(for context: JobContext, kind: CaptureKind) -> URL {
        folder(for: context, kind: kind, in: language)
    }

    /// Folders the side panel lists for a context: the folders of every
    /// language, so a language switch never hides captures. With `sortByType`
    /// the base folders are included too, so files saved before the user
    /// switched modes stay visible.
    public func listedFolders(for context: JobContext) -> [URL] {
        var result: [URL] = []
        for base in language.withOthers.map({ baseFolder(for: context, in: $0) }) where !result.contains(base) {
            result.append(base)
            guard sortByType else { continue }
            for lang in language.withOthers {
                result += CaptureKind.allCases.map { base.appendingPathComponent(lang.typeFolderName(for: $0), isDirectory: true) }
            }
        }
        return result
    }

    public func prefix(for context: JobContext) -> String {
        prefix(for: context, in: language)
    }

    /// Whether a capture in `folder` named with `prefix` already sits where
    /// `context` would put it, in any language.
    public func isInPlace(folder: URL, prefix: String, context: JobContext, kind: CaptureKind) -> Bool {
        let folder = folder.standardizedFileURL
        return FolderLanguage.allCases.contains { lang in
            prefix == self.prefix(for: context, in: lang)
                && FolderLanguage.allCases.contains { typeLang in
                    let base = baseFolder(for: context, in: lang)
                    let target = sortByType ? base.appendingPathComponent(typeLang.typeFolderName(for: kind), isDirectory: true) : base
                    return target.standardizedFileURL == folder
                }
        }
    }

    /// True for the prefixes of captures without a job, in any language.
    public static func isJoblessPrefix(_ prefix: String) -> Bool {
        prefix == jobsDisabledPrefix || FolderLanguage.allCases.contains { $0.unassignedPrefix == prefix }
    }

    private func baseFolder(for context: JobContext, in lang: FolderLanguage) -> URL {
        switch context {
        case .job(let code): root.appendingPathComponent(code.value, isDirectory: true)
        case .unassigned: root.appendingPathComponent(lang.unassignedFolderName, isDirectory: true)
        case .jobsDisabled: root
        }
    }

    private func folder(for context: JobContext, kind: CaptureKind, in lang: FolderLanguage) -> URL {
        let base = baseFolder(for: context, in: lang)
        return sortByType ? base.appendingPathComponent(lang.typeFolderName(for: kind), isDirectory: true) : base
    }

    private func prefix(for context: JobContext, in lang: FolderLanguage) -> String {
        switch context {
        case .job(let code): code.value
        case .unassigned: lang.unassignedPrefix
        case .jobsDisabled: Self.jobsDisabledPrefix
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
