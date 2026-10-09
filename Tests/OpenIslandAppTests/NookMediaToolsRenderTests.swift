import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Draws the weather tile, the scrub bar and the speaker list offscreen. Set
/// `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to also write the PNGs to
/// `output/render/` under the repo root. Nothing here asks a server, plays
/// anything or touches the sound hardware.
@MainActor
struct NookMediaToolsRenderTests {
    private static let scale: CGFloat = 2
    /// A wide card and a small card on the MacBook notch page.
    private static let wideWidth: CGFloat = 432
    private static let smallWidth: CGFloat = 211

    private static func width(for size: NookWidgetSize) -> CGFloat {
        size == .small ? smallWidth : wideWidth
    }

    // MARK: Weather

    @Test
    func theWeatherTileDrawsAtEverySizeAndEachSizeLooksDifferent() throws {
        let renders = try NookWidgetSize.allCases.map { size in
            try render("weather-\(size.rawValue)") {
                card(height: NookWeatherLayout.height(for: size), width: Self.width(for: size)) {
                    NookWeatherContent.sample(size: size)
                }
            }
        }
        #expect(Set(renders.map(\.png)).count == renders.count)
        for (size, rendered) in zip(NookWidgetSize.allCases, renders) {
            let expected: CGFloat = NookWeatherLayout.height(for: size) + 16
            #expect(rendered.height == expected, "\(size)")
        }
    }

    @Test
    func aStaleReportSaysHowOldItIs() throws {
        let fresh = NookWeatherContent.sample(size: .medium)
        var stale = fresh
        stale.showsAge = true
        let plain = try render("weather-medium-fresh") {
            card(height: NookWeatherLayout.mediumHeight, width: Self.wideWidth) { fresh }
        }
        let aged = try render("weather-medium-stale") {
            card(height: NookWeatherLayout.mediumHeight, width: Self.wideWidth) { stale }
        }
        #expect(plain.png != aged.png)
    }

    @Test
    func theUnitSwitchChangesTheNumbers() throws {
        let fahrenheit = NookWeatherContent.sample(size: .large)
        let celsius = NookWeatherContent(
            place: fahrenheit.place,
            report: fahrenheit.report,
            unit: .celsius,
            size: .large,
            now: fahrenheit.now,
            isInteractive: false
        )
        let first = try render(nil) { card(height: NookWeatherLayout.largeHeight, width: Self.wideWidth) { fahrenheit } }
        let second = try render("weather-large-celsius") {
            card(height: NookWeatherLayout.largeHeight, width: Self.wideWidth) { celsius }
        }
        #expect(first.png != second.png)
    }

    @Test
    func aTileWithNoCityIsNeverBlank() throws {
        let nook = NookModel()
        nook.presentRingLight = { _ in }
        // A bare model's weather service has no city and stays off the network.
        #expect(nook.weather.place == nil)
        let empty = try render(nil) {
            Color.clear.frame(width: Self.wideWidth, height: NookWeatherLayout.mediumHeight).padding(8)
        }
        for size in NookWidgetSize.allCases {
            let rendered = try render("weather-empty-\(size.rawValue)") {
                NookWeatherCard(nook: nook)
                    .environment(\.nookWidgetSize, size)
                    .frame(width: Self.width(for: size), height: NookWeatherLayout.height(for: size))
                    .padding(8)
            }
            #expect(rendered.png != empty.png, "\(size)")
        }
    }

    // MARK: Now playing

    @Test
    func theScrubBarDrawsForASeekableTrackAndNotForOneWithNoLength() throws {
        let media = MediaRemoteService()
        let seekable = try render("scrub-seekable") {
            NookScrubBar(state: NookMediaSamples.track(isPlaying: false, duration: 215, elapsed: 84), media: media)
                .frame(width: 240)
                .padding(16)
        }
        let later = try render("scrub-later") {
            NookScrubBar(state: NookMediaSamples.track(isPlaying: false, duration: 215, elapsed: 190), media: media)
                .frame(width: 240)
                .padding(16)
        }
        #expect(seekable.png != later.png)
        // The line lays out as 3pt, 4pt of gap and one row of 9pt digits.
        #expect(seekable.height < 16 + 16 + 24)

        let hidden = try render(nil) {
            NookScrubBar(state: NookMediaSamples.track(isPlaying: false, duration: nil, elapsed: 84), media: media)
                .frame(width: 240)
                .padding(16)
        }
        let none: CGFloat = 32
        #expect(hidden.height == none)
    }

    @Test
    func theSpeakerListDrawsEveryOutputAndMarksTheCurrentOne() throws {
        let hardware = FakeAudioHardware(
            devices: [
                NookMediaSamples.speakers, NookMediaSamples.airPods, NookMediaSamples.display, NookMediaSamples.loopback,
            ],
            defaultID: NookMediaSamples.speakers.id,
            systemID: NookMediaSamples.speakers.id
        )
        let outputs = NookAudioOutputs(hardware: hardware)
        outputs.start()

        let onSpeakers = try render("speakers-builtin") { speakerCard(outputs) }
        outputs.select(NookMediaSamples.airPods.id)
        let onAirPods = try render("speakers-airpods") { speakerCard(outputs) }
        #expect(onSpeakers.png != onAirPods.png)

        hardware.refusedOutputs = [NookMediaSamples.display.id]
        outputs.select(NookMediaSamples.display.id)
        let refused = try render("speakers-refused") { speakerCard(outputs) }
        #expect(refused.png != onAirPods.png)
    }

    // MARK: Helpers

    private func speakerCard(_ outputs: NookAudioOutputs) -> some View {
        card(height: 160, width: Self.wideWidth) {
            NookSpeakerList(outputs: outputs, onDone: {})
        }
    }

    /// `content` in a Nook card of the given size, the way the page pads it.
    private func card<Content: View>(
        height: CGFloat,
        width: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(width: width, height: height, alignment: .topLeading)
            .background(NookCardBackground())
            .padding(8)
    }

    private struct Rendered {
        let png: Data
        let height: CGFloat
    }

    private func render<Content: View>(_ name: String?, @ViewBuilder content: () -> Content) throws -> Rendered {
        let renderer = ImageRenderer(
            content: content()
                .fixedSize(horizontal: false, vertical: true)
                .background(Color.black)
                .environment(\.colorScheme, .dark)
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
                .appendingPathComponent("output/render", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return Rendered(png: png, height: CGFloat(image.height) / Self.scale)
    }
}
