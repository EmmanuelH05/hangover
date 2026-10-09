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

    /// Hangover's update feed. There is none yet, which is why this is nil
    /// and why Sparkle is never started: no check is made, by timer or by
    /// hand, and nothing is fetched. A feed set here must be Hangover's
    /// own. The upstream feed lists Open Island and would replace this app
    /// with it. Neither bundle plist carries an `SUFeedURL` either.
    nonisolated static let feedURL: URL? = nil

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

    /// Called once after app launch. Starts nothing: Hangover has no update
    /// feed of its own (`feedURL`), and Sparkle never starts without one,
    /// debug or release. `canCheckForUpdates` stays false, which keeps the
    /// button in Settings off. Starting Sparkle is to be written together
    /// with the feed (RELEASE.md, "Later").
    func startIfNeeded() {
        print("[UpdateChecker] off: Hangover has no update feed yet")
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
