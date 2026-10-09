import Foundation
import Testing
@testable import OpenIslandApp

/// Hangover updates itself from a feed of its own. Only the packaged
/// release may check it, and nothing may lead to the upstream project's
/// feed or downloads, which hold a different app.
struct UpdateCheckerTests {
    static let upstreamOwner: String = "Octane0411"

    static func text(of file: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
    }

    @Test func theFeedIsAFileInHangoversOwnRepository() {
        let feed = UpdateChecker.feedURL
        #expect(feed == AppBrand.updateFeedURL)
        #expect(feed.scheme == "https")
        #expect(feed.host == "raw.githubusercontent.com")
        #expect(feed.path == "/EmmanuelH05/hangover/main/appcast.xml")
        #expect(!feed.absoluteString.contains(Self.upstreamOwner))
    }

    @Test func onlyABundleWithHangoversFeedAndKeyStartsUpdates() {
        let feed = AppBrand.updateFeedURL.absoluteString
        let key = AppBrand.updatePublicKey

        #expect(UpdateChecker.shouldStart(bundleFeed: feed, bundleKey: key))
        #expect(!UpdateChecker.shouldStart(bundleFeed: nil, bundleKey: nil))
        #expect(!UpdateChecker.shouldStart(bundleFeed: feed, bundleKey: nil))
        #expect(!UpdateChecker.shouldStart(bundleFeed: nil, bundleKey: key))
        #expect(!UpdateChecker.shouldStart(bundleFeed: feed, bundleKey: "another key"))
        #expect(!UpdateChecker.shouldStart(
            bundleFeed: "https://raw.githubusercontent.com/\(Self.upstreamOwner)/open-vibe-island/main/appcast.xml",
            bundleKey: key
        ))
    }

    @Test @MainActor func aTestRunNeverStartsTheUpdater() {
        let checker = UpdateChecker()

        checker.startIfNeeded()
        checker.checkForUpdates()

        #expect(!checker.canCheckForUpdates)
        #expect(!checker.hasUpdate)
        #expect(checker.latestVersion == nil)
    }

    @Test func theReleasesLinkIsHangoversAndNotUpstreams() {
        let link = UpdateChecker.releasesURL.absoluteString
        #expect(UpdateChecker.releasesURL == AppBrand.releasesURL)
        #expect(link.hasPrefix(AppBrand.sourceCodeURL.absoluteString))
        #expect(!link.contains(Self.upstreamOwner))
    }

    @Test func theReleaseBundleCarriesHangoversFeedAndKey() throws {
        let script = try Self.text(of: "scripts/package-app.sh")
        #expect(script.contains("<key>SUFeedURL</key>\n    <string>\(AppBrand.updateFeedURL.absoluteString)</string>"))
        #expect(script.contains("<key>SUPublicEDKey</key>\n    <string>\(AppBrand.updatePublicKey)</string>"))
        #expect(!script.contains(Self.upstreamOwner))
    }

    @Test func theDevBundleCarriesNoFeedAndNoKey() throws {
        let script = try Self.text(of: "scripts/launch-dev-app.sh")
        #expect(!script.contains("SUFeedURL"))
        #expect(!script.contains("SUPublicEDKey"))
    }

    @Test func theFeedFileHoldsOnlyHangoverDownloads() throws {
        let feed = try Self.text(of: "appcast.xml")
        #expect(!feed.contains(Self.upstreamOwner))
        #expect(feed.contains(AppBrand.releasesURL.absoluteString))
        let download = "\(AppBrand.releasesURL.absoluteString)/download/"
        for line in feed.split(separator: "\n") where line.contains("<enclosure") {
            #expect(line.contains("url=\"\(download)"), "an update points somewhere else: \(line)")
            #expect(line.contains("sparkle:edSignature=\""), "an update is not signed: \(line)")
        }
    }

    @Test func theFeedScriptWritesHangoversDownloadAddress() throws {
        let script = try Self.text(of: "scripts/update-appcast.sh")
        #expect(script.contains("\(AppBrand.releasesURL.absoluteString)/download/"))
        #expect(!script.contains(Self.upstreamOwner))
    }

    @Test func aCopyThatNeverCheckedLooksAtTheFeedAtItsFirstLaunch() {
        let earlier = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(UpdateChecker.checksRightAway(lastCheck: nil, checksAutomatically: true))
        // After the first check Sparkle keeps its own once-a-day pace.
        #expect(UpdateChecker.checksRightAway(lastCheck: earlier, checksAutomatically: true) == false)
        // Someone who turned checks off is left alone.
        #expect(UpdateChecker.checksRightAway(lastCheck: nil, checksAutomatically: false) == false)
    }

    @Test func theReleaseInstallsUpdatesWithoutAskingAndTheDevBundleDoesNot() throws {
        let release = try Self.text(of: "scripts/package-app.sh")
        let dev = try Self.text(of: "scripts/launch-dev-app.sh")

        #expect(release.contains("<key>SUAutomaticallyUpdate</key>\n    <true/>"))
        #expect(release.contains("<key>SUEnableAutomaticChecks</key>\n    <true/>"))
        #expect(!dev.contains("SUAutomaticallyUpdate"))
    }

    @Test func theReadmesDownloadIsAlwaysTheNewestVersion() throws {
        let readme = try Self.text(of: "README.md")

        #expect(readme.contains("\(AppBrand.releasesURL.absoluteString)/latest/download/Hangover.zip"))
    }
}
