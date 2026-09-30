import Sparkle
import SwiftUI

/// Sparkle's standard updater: checks the appcast in `SUFeedURL`, verifies the
/// download against `SUPublicEDKey` (and the Developer ID signature), installs
/// and relaunches. Off in demo mode and in builds without a public key.
@MainActor
final class Updater: ObservableObject {
    private let controller: SPUStandardUpdaterController?
    @Published private(set) var canCheck = false

    init(enabled: Bool) {
        let configured = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?.isEmpty == false
        guard enabled, configured else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                      userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }

    var isAvailable: Bool { controller != nil }

    func checkForUpdates() { controller?.checkForUpdates(nil) }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }
}
