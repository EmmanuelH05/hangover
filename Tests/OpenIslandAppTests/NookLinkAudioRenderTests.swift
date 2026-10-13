import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Draws the Link to MP3 card with `ImageRenderer`, on a service of its own
/// that runs on fakes. Set `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to also write
/// the one picture of the card to `output/render/link-audio/` under the repo
/// root for a visual check.
///
/// `ImageRenderer` cannot draw AppKit-backed views, which is why the card is
/// drawn still: the text field is swapped for a plain look-alike. No window
/// is opened, no process is started and the clipboard is never read.
@MainActor
struct NookLinkAudioRenderTests {
    private typealias Fixture = LinkAudioFixture

    private static let scale: CGFloat = 2
    private static let snapshotEnvKey = "OPEN_ISLAND_RENDER_SNAPSHOTS"

    private static func cardSize(_ size: NookWidgetSize) -> CGSize {
        CGSize(width: size == .small ? 204 : 416, height: NookLinkAudioCard.height(for: size))
    }

    /// One job finished, one running at 62 percent and one waiting for it.
    private func filled(_ fixture: Fixture) {
        fixture.submit(1)
        fixture.finishRunningJob(title: "Morning run mix", file: "/Users/tester/Music/Hangover/Morning run mix [k7Qp2x].mp3")
        fixture.submit(2, from: 2)
        let run = fixture.runner.last
        run?.say(Fixture.titleLine("Interview with the band, part two"))
        run?.say(Fixture.progressLine(done: 62, of: 100, file: "Interview with the band, part two [m3Zr9w].webm"))
    }

    // MARK: The picture

    @Test func theCardWithAWaitingAJobRunningAndAFinishedJobIsDrawn() throws {
        let fixture = Fixture()
        filled(fixture)
        #expect(fixture.service.jobs.map(\.phase) == [
            .downloading(fraction: 0.62),
            .waiting,
            .done(URL(fileURLWithPath: "/Users/tester/Music/Hangover/Morning run mix [k7Qp2x].mp3")),
        ])

        let picture = try card("link-audio-large", fixture, .large, writes: true)

        let empty = try card("empty", Fixture(), .large)
        #expect(picture != empty)
    }

    @Test(arguments: NookWidgetSize.allCases)
    func theCardIsDrawnAtEverySize(size: NookWidgetSize) throws {
        let fixture = Fixture()
        let none = try card("none", fixture, size)
        filled(fixture)
        let some = try card("some", fixture, size)
        #expect(none != some)
    }

    @Test func aBarThatMovesIsASeenChange() throws {
        let fixture = Fixture()
        filled(fixture)
        let before = try card("before", fixture, .large)
        fixture.runner.last?.say(Fixture.progressLine(done: 90, of: 100, file: "Interview with the band, part two [m3Zr9w].webm"))
        let after = try card("after", fixture, .large)
        #expect(before != after)
    }

    @Test func aJobThatIsMakingTheMP3IsNotDrawnLikeOneThatIsDownloading() throws {
        let fixture = Fixture()
        fixture.submit(1)
        fixture.runner.last?.say(Fixture.progressLine(done: 100, of: 100))
        let downloading = try card("downloading", fixture, .medium)
        fixture.runner.last?.say(Fixture.downloadDoneLine())
        let converting = try card("converting", fixture, .medium)
        #expect(downloading != converting)
    }

    @Test func aFailedJobAndAFinishedJobLookDifferent() throws {
        let failed = Fixture()
        failed.submit(1)
        failed.runner.last?.say("ERROR: Unsupported URL: https://example.com/x")
        failed.runner.last?.end(status: 1)

        let done = Fixture()
        done.submit(1)
        done.runner.last?.end()

        #expect(try card("failed", failed, .medium) != card("done", done, .medium))
    }

    @Test func aMissingProgramShowsItsLineInPlaceOfTheEmptyHint() throws {
        let installed = Fixture()
        let missing = Fixture()
        missing.executables = [Fixture.ffmpeg]
        missing.service.refreshTools()
        #expect(try card("installed", installed, .medium) != card("missing", missing, .medium))
    }

    @Test func aLineAboutTheLinkShowsUnderTheField() throws {
        let fixture = Fixture()
        let clean = try card("clean", fixture, .medium)
        fixture.service.submit("-x")
        #expect(fixture.service.problem != nil)
        let problem = try card("problem", fixture, .medium)
        #expect(clean != problem)
    }

    @Test func aTypedLinkShowsInTheField() throws {
        let fixture = Fixture()
        let empty = try card("empty", fixture, .medium)
        let typed = try card("typed", fixture, .medium, text: "https://example.com/watch?v=abc")
        #expect(empty != typed)
    }

    @Test func theSampleDrawsAtEverySize() throws {
        for size in NookWidgetSize.allCases {
            let framed = NookLinkAudioCard.sample(size: size)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(width: Self.cardSize(size).width, height: Self.cardSize(size).height, alignment: .topLeading)
                .background(NookCardBackground())
                .environment(\.colorScheme, .dark)
            _ = try render("sample-\(size.rawValue)", framed, writes: false)
        }
    }

    // MARK: Rendering

    private func card(
        _ name: String,
        _ fixture: Fixture,
        _ size: NookWidgetSize,
        text: String = "",
        writes: Bool = false
    ) throws -> Data {
        let cardSize = Self.cardSize(size)
        let framed = NookLinkAudioCard(service: fixture.service, isStill: true, text: text)
            .environment(\.nookWidgetSize, size)
            .frame(width: cardSize.width, height: cardSize.height)
            .padding(8)
            .background(V6Palette.ink)
            .environment(\.colorScheme, .dark)
        return try render(name, framed, writes: writes)
    }

    private func render(_ name: String, _ view: some View, writes: Bool) throws -> Data {
        let renderer = ImageRenderer(content: view)
        renderer.scale = Self.scale
        let image = try #require(renderer.cgImage, "ImageRenderer returned no image for \(name)")
        let png = try #require(
            NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
            "PNG encoding failed for \(name)"
        )
        if writes, ProcessInfo.processInfo.environment[Self.snapshotEnvKey] == "1" {
            let directory = Self.repoRoot.appendingPathComponent("output/render/link-audio", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return png
    }

    /// `Tests/OpenIslandAppTests/<this file>` sits three levels below the root.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
