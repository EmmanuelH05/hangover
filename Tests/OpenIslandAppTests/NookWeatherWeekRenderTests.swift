import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Draws the weather tile's hours and its week offscreen, from a saved
/// answer. Set `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to also write the PNGs to
/// `output/render/weather/` under the repo root. Nothing here asks a server.
@MainActor
@Suite struct NookWeatherWeekRenderTests {
    private static let scale: CGFloat = 2
    /// A wide card on the notch display's page, the narrowest there is, on
    /// the top bar's page, and on a wider island than either.
    private static let notchWidth = NookLayoutEditor.pageWidth(for: .notch)
    private static let topBarWidth = NookLayoutEditor.pageWidth(for: .topBar)
    private static let wideWidth: CGFloat = 648
    private static let smallWidth: CGFloat = 219
    /// The card's padding, top and bottom together.
    private static let verticalPadding: CGFloat = 24

    /// The tallest the tile's content may measure at its natural height.
    /// The content ends in a spacer, and the stack's gap before that spacer
    /// is counted in the natural height though nothing is drawn in it: 6
    /// in the medium tile and 8 in the large one.
    private static func allowedNaturalHeight(for size: NookWidgetSize) -> CGFloat {
        let trailingGap: CGFloat = size == .large ? 8 : 6
        return NookWeatherLayout.height(for: size) - verticalPadding + trailingGap
    }

    private static func content(
        _ size: NookWidgetSize,
        _ mode: NookWeatherForecastMode,
        unit: NookTemperatureUnit = .fahrenheit,
        report: NookWeatherReport? = nil,
        now: Date = NookWeatherFixtures.weekFetchedAt
    ) throws -> NookWeatherContent {
        NookWeatherContent(
            place: NookWeatherFixtures.losAngeles,
            report: try report ?? NookWeatherFixtures.weekReport(),
            unit: unit,
            size: size,
            now: now,
            isInteractive: false,
            mode: mode
        )
    }

    // MARK: The two rows

    @Test func theLargeTileDrawsTheWeekInPlaceOfTheHours() throws {
        let hours = try card("large-hours", .large, width: Self.notchWidth) { try Self.content(.large, .hours) }
        let week = try card("large-week", .large, width: Self.notchWidth) { try Self.content(.large, .week) }
        let celsius = try card("large-week-celsius", .large, width: Self.notchWidth) {
            try Self.content(.large, .week, unit: .celsius)
        }

        #expect(hours.png != week.png)
        #expect(week.png != celsius.png)
        // The same card, at the same height, in both.
        #expect(hours.size == week.size)
    }

    @Test func theMediumTileDrawsTheWeekBesideTheCurrentWeather() throws {
        let hours = try card("medium-hours", .medium, width: Self.notchWidth) { try Self.content(.medium, .hours) }
        let week = try card("medium-week", .medium, width: Self.notchWidth) { try Self.content(.medium, .week) }

        #expect(hours.png != week.png)
        #expect(hours.size == week.size)
    }

    @Test func theSmallTileHasNoWeekAndNoSwitch() throws {
        let hours = try card("small-hours", .small, width: Self.smallWidth) { try Self.content(.small, .hours) }
        let week = try card(nil, .small, width: Self.smallWidth) { try Self.content(.small, .week) }

        #expect(hours.png == week.png)
    }

    @Test(arguments: [NookWidgetSize.medium, .large])
    func aReportWithNoWeekDrawsItsHoursWhateverTheChoice(size: NookWidgetSize) throws {
        let older = try NookWeatherFixtures.report()
        let now = NookWeatherFixtures.fetchedAt
        let hours = try card("\(size.rawValue)-no-week", size, width: Self.notchWidth) {
            try Self.content(size, .hours, report: older, now: now)
        }
        let week = try card(nil, size, width: Self.notchWidth) {
            try Self.content(size, .week, report: older, now: now)
        }

        #expect(hours.png == week.png)
    }

    // MARK: Room

    /// The row under the header must fit the card at every island width,
    /// with nothing pushed past the card's own padding. Drawn at its
    /// natural height, the content is never taller than the card allows.
    @Test(arguments: [NookWidgetSize.medium, .large], NookWeatherForecastMode.allCases)
    func bothRowsFitTheCardsHeightAtEveryWidth(size: NookWidgetSize, mode: NookWeatherForecastMode) throws {
        let allowed = Self.allowedNaturalHeight(for: size)
        for width in [Self.notchWidth, Self.topBarWidth, Self.wideWidth] {
            let inner = width - 2 * NookWeatherLayout.cardPadding
            let natural = try render(nil) {
                try Self.content(size, mode)
                    .frame(width: inner)
                    .fixedSize(horizontal: false, vertical: true)
            }
            #expect(natural.size.height <= allowed, "\(size) \(mode) at \(width): \(natural.size.height)")
            #expect(natural.size.width == inner, "\(size) \(mode) at \(width)")
        }
    }

    /// The hottest and coldest numbers the row has to hold, three digits
    /// and a minus sign, still leave seven columns in the medium tile.
    @Test func aWeekOfLongNumbersStillDrawsAtTheNarrowestWidth() throws {
        var report = try NookWeatherFixtures.weekReport()
        report.days = report.days.enumerated().map { index, day in
            var changed = day
            changed.high = index.isMultiple(of: 2) ? 44 : -19
            changed.low = index.isMultiple(of: 2) ? 39 : -31
            changed.code = 95
            return changed
        }
        let allowed = Self.allowedNaturalHeight(for: .medium)
        let inner = Self.notchWidth - 2 * NookWeatherLayout.cardPadding
        let natural = try render(nil) {
            try Self.content(.medium, .week, report: report)
                .frame(width: inner)
                .fixedSize(horizontal: false, vertical: true)
        }
        _ = try card("medium-week-long-numbers", .medium, width: Self.notchWidth) {
            try Self.content(.medium, .week, report: report)
        }

        #expect(natural.size.height <= allowed)
        #expect(natural.size.width == inner)
    }

    // MARK: Pictures for a look

    @Test func theWeekDrawsOnAWiderIslandAndInTheSettingsPreview() throws {
        let topBar = try card("medium-week-topbar", .medium, width: Self.topBarWidth) {
            try Self.content(.medium, .week)
        }
        let wideMedium = try card("medium-week-wide", .medium, width: Self.wideWidth) {
            try Self.content(.medium, .week)
        }
        let wideLarge = try card("large-week-wide", .large, width: Self.wideWidth) {
            try Self.content(.large, .week)
        }
        let sample = try card("large-week-sample", .large, width: Self.notchWidth) {
            NookWeatherContent.sample(size: .large, mode: .week)
        }
        let sampleHours = try card("large-hours-sample", .large, width: Self.notchWidth) {
            NookWeatherContent.sample(size: .large)
        }

        #expect(topBar.png != wideMedium.png)
        #expect(wideLarge.size.width > topBar.size.width)
        #expect(sample.png != sampleHours.png)
    }

    // MARK: Rendering

    private struct Rendered {
        let png: Data
        let size: CGSize
    }

    /// `content` in a Nook card of this size, the way the page pads it.
    private func card<Content: View>(
        _ name: String?,
        _ size: NookWidgetSize,
        width: CGFloat,
        @ViewBuilder content: () throws -> Content
    ) throws -> Rendered {
        let inside = try content()
        return try render(name) {
            inside
                .padding(.horizontal, NookWeatherLayout.cardPadding)
                .padding(.vertical, Self.verticalPadding / 2)
                .frame(width: width, height: NookWeatherLayout.height(for: size), alignment: .topLeading)
                .background(NookCardBackground())
                .padding(8)
        }
    }

    private func render<Content: View>(_ name: String?, @ViewBuilder content: () throws -> Content) throws -> Rendered {
        let renderer = ImageRenderer(
            content: try content()
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
                .appendingPathComponent("output/render/weather", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return Rendered(
            png: png,
            size: CGSize(width: CGFloat(image.width) / Self.scale, height: CGFloat(image.height) / Self.scale)
        )
    }
}
