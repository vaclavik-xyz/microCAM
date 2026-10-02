import Foundation

/// A job folder under the storage root, for the side panel's search.
public struct JobSummary: Equatable, Sendable {
    public let code: JobCode
    /// Photos and videos in it.
    public let files: Int
    /// "2026-09-25", the day of its newest capture; nil when it has none.
    public let lastDay: String?

    public init(code: JobCode, files: Int, lastDay: String?) {
        self.code = code
        self.files = files
        self.lastDay = lastDay
    }
}

public enum JobFinder {
    /// Folders named exactly like a job code microCAM writes (upper case),
    /// newest capture first; jobs without captures last, by code.
    public static func jobs(in layout: StorageLayout, fileManager: FileManager = .default) -> [JobSummary] {
        let folders = (try? fileManager.contentsOfDirectory(at: layout.root, includingPropertiesForKeys: [.isDirectoryKey],
                                                            options: [.skipsHiddenFiles])) ?? []
        let jobs: [(JobSummary, String)] = folders.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let code = JobCode(url.lastPathComponent), code.value == url.lastPathComponent else { return nil }
            let files = CaptureLibrary.captureFiles(in: layout.listedFolders(for: .job(code)), fileManager: fileManager)
            let newest = files.first.flatMap { CaptureFileName.parse($0.lastPathComponent)?.timestamp } ?? ""
            let day = newest.split(separator: "_").first.map(String.init)
            return (JobSummary(code: code, files: files.count, lastDay: day), newest)
        }
        return jobs.sorted { a, b in
            a.1 != b.1 ? a.1 > b.1 : a.0.code.value < b.0.code.value
        }.map(\.0)
    }

    /// Jobs whose code contains `query`, ignoring case and spaces around it.
    public static func filter(_ jobs: [JobSummary], query: String) -> [JobSummary] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return jobs }
        return jobs.filter { $0.code.value.localizedCaseInsensitiveContains(needle) }
    }
}
