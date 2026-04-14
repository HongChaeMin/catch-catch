import Foundation
import Sparkle

/// Sparkle wrapper. Sparkle handles download/install/relaunch UI itself;
/// this class just exposes the updater and current version to SwiftUI.
class UpdateChecker: ObservableObject {
    private let controller: SPUStandardUpdaterController

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Shows Sparkle's update dialog (checks feed, downloads, relaunches).
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
