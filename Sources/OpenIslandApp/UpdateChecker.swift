import Combine
import Foundation
import Sparkle

/// Wraps Sparkle's `SPUUpdater` to provide observable update state for SwiftUI.
///
/// Sparkle handles the full lifecycle: checking for updates, downloading,
/// extracting, replacing the app bundle, and relaunching.
/// This wrapper simply exposes the current state so the UI can react.
@MainActor
@Observable
final class UpdateChecker: NSObject {
    /// Hangover's own releases page. Never the upstream project's, which
    /// holds a different app.
    nonisolated static let releasesURL = AppBrand.releasesURL

    /// Hangover's update feed, a file in its own repository. It must
    /// never be the upstream project's: that feed lists Open Island and
    /// would replace this app with it.
    nonisolated static let feedURL: URL = AppBrand.updateFeedURL

    /// Updates run only in a bundle that names Hangover's feed and carries
    /// Hangover's key, which is the packaged release. The dev bundle and a
    /// test run carry neither and never start Sparkle.
    nonisolated static func shouldStart(bundleFeed: String?, bundleKey: String?) -> Bool {
        bundleFeed == feedURL.absoluteString && bundleKey == AppBrand.updatePublicKey
    }

    /// A copy that has never checked looks at the feed as soon as it
    /// starts, not a day later. Nobody should have to press "Check for
    /// Updates" after a first download to get onto the newest version.
    nonisolated static func checksRightAway(lastCheck: Date?, checksAutomatically: Bool) -> Bool {
        checksAutomatically && lastCheck == nil
    }

    /// Whether a new version is downloaded and installed without asking.
    /// The release sets this on (`SUAutomaticallyUpdate`), and the switch
    /// in Settings, About turns it off.
    var installsAutomatically = false {
        didSet {
            // Only a real change is written. Copying Sparkle's own value in
            // at launch must not save it as the user's choice, which would
            // outlive a later change to the release's default.
            guard cancellable != nil,
                  updaterController.updater.automaticallyDownloadsUpdates != installsAutomatically else { return }
            updaterController.updater.automaticallyDownloadsUpdates = installsAutomatically
        }
    }

    private(set) var canCheckForUpdates = false
    private(set) var hasUpdate = false
    private(set) var latestVersion: String?

    @ObservationIgnored
    private var updaterController: SPUStandardUpdaterController!

    @ObservationIgnored
    private var cancellable: AnyCancellable?

    override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    /// Called once after app launch. Starts Sparkle in a release bundle:
    /// it checks the feed at the first launch and once a day after that,
    /// downloads a new version by itself and installs it the next time the
    /// app starts. Everywhere else it starts nothing, and
    /// `canCheckForUpdates` stays false, which keeps the button in
    /// Settings off.
    func startIfNeeded() {
        let info = Bundle.main.infoDictionary
        guard Self.shouldStart(
            bundleFeed: info?["SUFeedURL"] as? String,
            bundleKey: info?["SUPublicEDKey"] as? String
        ) else {
            print("[UpdateChecker] off: this build carries no update feed")
            return
        }
        guard cancellable == nil else { return }
        cancellable = updaterController.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in
                Task { @MainActor in self?.canCheckForUpdates = value }
            }
        updaterController.startUpdater()
        let updater = updaterController.updater
        installsAutomatically = updater.automaticallyDownloadsUpdates
        if Self.checksRightAway(
            lastCheck: updater.lastUpdateCheckDate,
            checksAutomatically: updater.automaticallyChecksForUpdates
        ) {
            updater.checkForUpdatesInBackground()
        }
    }

    /// Manually trigger an update check (from Settings UI).
    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        updaterController.checkForUpdates(nil)
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdateChecker: SPUUpdaterDelegate {
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        Set()
    }

    /// Pins the feed to Hangover's own, whatever a bundle's plist says.
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        Self.feedURL.absoluteString
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in
            self.hasUpdate = true
            self.latestVersion = version
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        Task { @MainActor in
            self.hasUpdate = false
            self.latestVersion = nil
        }
    }
}
