import Foundation

/// Language of the folder names and file-name prefixes microCAM writes.
/// New captures follow the app's language; the side panel, the stream and
/// "Move to job" read every language, so switching the app language never
/// hides existing captures. `microcam_` and job codes are the same in all.
public enum FolderLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case czech = "cs"

    /// Picks the language for a localization such as `Bundle.main.preferredLocalizations.first`.
    public init(localization: String?) {
        let code = localization?.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)
        self = code.flatMap { FolderLanguage(rawValue: $0.lowercased()) } ?? .english
    }

    public var unassignedFolderName: String {
        switch self {
        case .english: "_Unsorted"
        case .czech: "_Nezařazeno"
        }
    }

    /// Prefix of captures without a job. Lower case, so it can never clash
    /// with a job code (those are upper case).
    public var unassignedPrefix: String {
        switch self {
        case .english: "no-job"
        case .czech: "bez-zakazky"
        }
    }

    /// Subfolder used only when the user turns on sorting by type.
    public func typeFolderName(for kind: CaptureKind) -> String {
        switch (self, kind) {
        case (.english, .photo): "Photos"
        case (.english, .video): "Videos"
        case (.english, .timelapse): "Timelapse"
        case (.czech, .photo): "Fotky"
        case (.czech, .video): "Videa"
        case (.czech, .timelapse): "Časosběr"
        }
    }

    /// The current language first, then the others.
    var withOthers: [FolderLanguage] { [self] + Self.allCases.filter { $0 != self } }
}
