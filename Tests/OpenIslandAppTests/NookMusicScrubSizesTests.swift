import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Which music cards show the scrub bar and how it is drawn there. A plain
/// value test: no view, no player.
@Suite struct NookScrubBarStyleTests {
    @Test func everySizeShowsTheBarForATrackWithALength() {
        for size in NookWidgetSize.allCases {
            #expect(NookScrubBarLayout.style(for: size, duration: 215) != nil, "\(size)")
        }
    }

    @Test func aTrackWithNoLengthGetsNoBarAtAnySize() {
        let none: [TimeInterval?] = [nil, 0, -4, .infinity, .nan]
        for size in NookWidgetSize.allCases {
            for duration in none {
                #expect(NookScrubBarLayout.style(for: size, duration: duration) == nil, "\(size) \(String(describing: duration))")
            }
        }
    }

    @Test func theWideCardsKeepTheBarTheyHadWithItsTimes() {
        // Medium and large span the page. The grid gives a card narrower than
        // that only the small size.
        #expect(NookScrubBarLayout.style(for: .medium, duration: 215) == .standard)
        #expect(NookScrubBarLayout.style(for: .large, duration: 215) == .standard)
        #expect(NookScrubBarStyle.standard.showsTimes)
        #expect(NookScrubBarStyle.standard.hitHeight == NookScrubBarLayout.hitHeight)
    }

    @Test func theNarrowCardGetsABareLineWithATallerBandToGrab() throws {
        let narrow = try #require(NookScrubBarLayout.style(for: .small, duration: 215))
        let minimum: CGFloat = 16
        #expect(narrow == .narrow)
        #expect(!narrow.showsTimes)
        #expect(narrow.hitHeight >= minimum)
        // The line itself is no heavier than on the wide cards.
        #expect(NookScrubBarLayout.restThickness <= 3)
        #expect(NookScrubBarLayout.activeThickness <= 5)
    }
}

/// Draws the narrow music card offscreen, the one column wide card the grid
/// calls small. Set `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to also write the PNGs
/// to `output/render/music/` under the repo root. The sample player stands
/// in for a real one, and nothing here shows a window or sends a command.
@MainActor
struct NookMusicScrubSizesTests {
    private static let scale: CGFloat = 2
    /// One column of a page about 484 points wide.
    private static let narrowWidth: CGFloat = 237
    private static let clock = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func theNarrowCardDrawsTheBarPartWayThroughATrackAndNoneWithoutALength() throws {
        let partWay = try render("narrow-scrub", track: Self.track(duration: 214), elapsed: 84)
        let noLength = try render("narrow-no-length", track: Self.track(duration: 0), elapsed: 0)

        #expect(partWay.png != noLength.png)
        // Both sit in the grid's shared small height, bar or not.
        let expected: CGFloat = NookMediaCard.height(for: .small) + 16
        #expect(partWay.height == expected)
        #expect(noLength.height == expected)
    }

    @Test
    func theBarMovesWithTheTrackOnTheNarrowCard() throws {
        let early = try render(nil, track: Self.track(duration: 214), elapsed: 30)
        let late = try render(nil, track: Self.track(duration: 214), elapsed: 180)
        #expect(early.png != late.png)
    }

    // MARK: Helpers

    private static func track(duration: TimeInterval) -> DemoTrack {
        DemoTrack(title: "Angel Dust", artist: "Hollow Pines", album: "Small Hours", duration: duration, hue: 0.55)
    }

    private struct Rendered {
        let png: Data
        let height: CGFloat
    }

    /// The music card at the small size on a paused sample track, which keeps
    /// the picture still.
    private func render(_ name: String?, track: DemoTrack, elapsed: TimeInterval) throws -> Rendered {
        let player = DemoPlayer(tracks: [track], startsPlaying: false, elapsed: elapsed, now: { Self.clock })
        let media = MediaRemoteService(sample: player)
        media.start()
        let nook = NookModel(media: media, defaults: MemoryDefaults(), looksForImportedGIF: false, asksMacOSForAccess: false)
        let renderer = ImageRenderer(
            content: NookMediaCard(nook: nook)
                .environment(\.nookWidgetSize, .small)
                .frame(width: Self.narrowWidth, height: NookMediaCard.height(for: .small))
                .padding(8)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color.black)
                .environment(\.colorScheme, .dark)
                .environment(\.nookDrawsStill, true)
        )
        renderer.scale = Self.scale
        let image = try #require(renderer.cgImage, "ImageRenderer returned no image for \(name ?? "a view")")
        let png = try #require(
            NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
            "PNG encoding failed"
        )
        if let name, ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_SNAPSHOTS"] == "1" {
            let directory = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("output/render/music", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return Rendered(png: png, height: CGFloat(image.height) / Self.scale)
    }
}
