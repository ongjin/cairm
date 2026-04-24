import Foundation
import Sparkle

final class UpdaterService: NSObject, SPUUpdaterDelegate {
    static let feedURL = URL(string: "https://github.com/ongjin/cairn/releases/latest/download/appcast.xml")!

    @MainActor private lazy var controller: SPUStandardUpdaterController = {
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        controller.updater.automaticallyChecksForUpdates = true
        return controller
    }()

    @MainActor override init() {
        super.init()
        _ = controller
    }

    @MainActor func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    @MainActor func feedURLString(for updater: SPUUpdater) -> String? {
        Self.feedURL.absoluteString
    }
}
