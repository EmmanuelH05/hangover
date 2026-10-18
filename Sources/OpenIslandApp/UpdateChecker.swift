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

    /// Whether the island asks to install a downloaded version the moment
    /// it lands (on), or shows "Update ready" and waits for Restart now or
    /// the next quit (off). The app's own preference (D82): Sparkle
    /// downloads a new version either way. Before D82 the switch was
    /// Sparkle's download setting; a copy that had it off keeps the ask
    /// off, which `startIfNeeded` reads once.
    var installsAutomatically: Bool {
        didSet {
            guard installsAutomatically != oldValue else { return }
            defaults.set(installsAutomatically, forKey: Self.installsAutomaticallyKey)
            onInstallsAutomaticallyChanged?()
        }
    }

    static let installsAutomaticallyKey = "update.installsAutomatically"

    private(set) var canCheckForUpdates = false
    private(set) var hasUpdate = false
    private(set) var latestVersion: String?

    /// Sparkle downloaded a version and holds the block that installs it
    /// and relaunches the app. The update flow takes it from here (D82).
    @ObservationIgnored
    var onDownloaded: ((_ version: String, _ install: @escaping () -> Void) -> Void)?
    /// The About switch changed, by the user or by Sparkle's own value at
    /// launch.
    @ObservationIgnored
    var onInstallsAutomaticallyChanged: (() -> Void)?

    @ObservationIgnored
    private var updaterController: SPUStandardUpdaterController!

    @ObservationIgnored
    private var cancellable: AnyCancellable?
    @ObservationIgnored
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        installsAutomatically = defaults.object(forKey: Self.installsAutomaticallyKey) as? Bool ?? true
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    /// Called once after app launch. Starts Sparkle in a release bundle:
    /// it checks the feed at the first launch and once a day after that,
    /// and downloads a new version by itself; the island then asks before
    /// it installs (D82). Everywhere else it starts nothing, and
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
        // The switch before D82 was Sparkle's own download setting. A copy
        // that had it off keeps the ask off; read once, before the
        // preference exists.
        if defaults.object(forKey: Self.installsAutomaticallyKey) == nil, !updater.automaticallyDownloadsUpdates {
            installsAutomatically = false
        }
        // Sparkle downloads in every case now; the switch decides what the
        // island does with the download.
        updater.automaticallyDownloadsUpdates = true
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

    /// Sparkle has the new version downloaded and would install it when
    /// the app quits, or show its own alert after a week. Returning true
    /// takes that over: the island asks, and the held block installs and
    /// relaunches when the user says so (D82). Sparkle still installs on
    /// quit either way.
    nonisolated func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        let version = item.displayVersionString
        let install = UpdateInstallHandle(immediateInstallHandler)
        Task { @MainActor in
            self.onDownloaded?(version) { install.run() }
        }
        return true
    }
}

/// Sparkle's install block, carried to the main actor. The block is called
/// on the main thread only, which is what Sparkle expects.
private final class UpdateInstallHandle: @unchecked Sendable {
    private let block: () -> Void

    init(_ block: @escaping () -> Void) {
        self.block = block
    }

    func run() {
        block()
    }
}
