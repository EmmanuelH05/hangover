import Foundation
import Testing
@testable import OpenIslandApp

/// Hangover has no update feed yet. Until it has one of its own, no build
/// may check for updates, and nothing may lead to the upstream project's
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

    @Test @MainActor func noCheckCanStartWithoutAFeedOfHangoversOwn() {
        let checker = UpdateChecker()
        #expect(UpdateChecker.feedURL == nil)

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

    @Test(arguments: ["scripts/package-app.sh", "scripts/launch-dev-app.sh"])
    func noBundleCarriesAFeedAddress(script: String) throws {
        let text = try Self.text(of: script)
        #expect(!text.contains("SUFeedURL"), "\(script) gives the bundle an update feed")
        #expect(!text.contains("SUPublicEDKey"), "\(script) gives the bundle an update key")
    }

    @Test func theFeedFileHoldsNoUpstreamDownload() throws {
        let feed = try Self.text(of: "appcast.xml")
        #expect(!feed.contains(Self.upstreamOwner))
        #expect(!feed.contains("<item>"))
        #expect(feed.contains(AppBrand.releasesURL.absoluteString))
    }

    @Test func theFeedScriptWritesHangoversDownloadAddress() throws {
        let script = try Self.text(of: "scripts/update-appcast.sh")
        #expect(script.contains("\(AppBrand.releasesURL.absoluteString)/download/"))
        #expect(!script.contains(Self.upstreamOwner))
    }
}
