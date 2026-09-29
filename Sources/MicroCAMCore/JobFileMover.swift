import Foundation

public enum MoveError: Error, Equatable {
    case notACaptureFile
    case alreadyThere
    case storage(StorageError)
    case fileSystem(String)
}

public struct MoveOutcome: Equatable {
    public let source: URL
    public let result: Result<URL, MoveError>
}

/// Moves captures to another job and renames them to the target prefix,
/// keeping the original timestamp and type. Never overwrites; each file is
/// moved independently and every failure is reported.
public struct JobFileMover {
    private let layout: StorageLayout
    private let fileManager: FileManager

    public init(layout: StorageLayout, fileManager: FileManager = .default) {
        self.layout = layout
        self.fileManager = fileManager
    }

    public func move(_ urls: [URL], to target: JobContext) -> [MoveOutcome] {
        urls.map { MoveOutcome(source: $0, result: moveOne($0, to: target)) }
    }

    private func moveOne(_ source: URL, to target: JobContext) -> Result<URL, MoveError> {
        guard let name = CaptureFileName.parse(source.lastPathComponent) else { return .failure(.notACaptureFile) }
        let kind = CaptureKind.fromTypeFolder(source.deletingLastPathComponent().lastPathComponent)
            ?? CaptureKind.fromExtension(name.ext)
        let prefix = StorageLayout.prefix(for: target)
        if source.deletingLastPathComponent().standardizedFileURL
            == layout.folder(for: target, kind: kind).standardizedFileURL, name.prefix == prefix {
            return .failure(.alreadyThere)
        }
        let folder: URL
        do {
            folder = try layout.prepareFolder(for: target, kind: kind, fileManager: fileManager)
        } catch let error as StorageError {
            return .failure(.storage(error))
        } catch {
            return .failure(.fileSystem(error.localizedDescription))
        }
        let namer = CaptureFileNamer(fileExists: { fileManager.fileExists(atPath: $0.path) })
        let destination = namer.availableURL(in: folder, prefix: prefix, timestamp: name.timestamp, ext: name.ext)
        do {
            try fileManager.moveItem(at: source, to: destination)
            return .success(destination)
        } catch {
            return .failure(.fileSystem(error.localizedDescription))
        }
    }
}
