import Foundation
import MicroCAMCore

extension FolderLanguage {
    /// The language the app runs in (fixed for the life of the process).
    static let app = FolderLanguage(localization: Bundle.main.preferredLocalizations.first)
}
