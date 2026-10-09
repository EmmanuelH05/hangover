import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Draws the opened island's looks (D35) offscreen with `ImageRenderer`:
/// the black shape at each width and corner choice, a Nook page at each,
/// the Settings cards and the tour's page. Everything drawn is plain
/// SwiftUI. Set `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to also write the PNGs to
/// `output/render/opened-look/` under the repo root.
@MainActor
struct IslandOpenedLookRenderTests {
    private static let scale: CGFloat = 2
    private static let snapshotEnvKey = "OPEN_ISLAND_RENDER_SNAPSHOTS"
    /// The stage every shape is drawn on. No other render test uses this
    /// size, which matters because `ImageRenderer` reuses a bitmap a size.
    private static let stage = CGSize(width: 812, height: 286)

    private static func name(_ look: IslandOpenedLook) -> String {
        "\(look.width.rawValue)-\(look.corners.rawValue)"
    }

    // MARK: The shape

    @Test(arguments: IslandAppearanceDisplayProfile.allCases)
    func everyLookDrawsAShapeOfItsOwn(profile: IslandAppearanceDisplayProfile) throws {
        let pictures = try IslandOpenedLook.all.map { look in
            try render("shape-\(profile.rawValue)-\(Self.name(look))") { shape(look, profile: profile) }
        }
        #expect(Set(pictures).count == IslandOpenedLook.all.count, "two looks drew the same shape on \(profile)")
    }

    @Test func aWiderLookCoversMoreOfTheStage() throws {
        let covered = try IslandOpenedWidth.allCases.map { width in
            try darkPixels { shape(IslandOpenedLook(width: width), profile: .notch) }
        }
        #expect(covered == covered.sorted())
        #expect(Set(covered).count == covered.count)
    }

    @Test func squareCornersCoverMoreOfTheirFrameThanSoftOnes() throws {
        // The same frame, with less cut away at its four corners.
        let soft = try darkPixels { shape(IslandOpenedLook(corners: .soft), profile: .topBar) }
        let square = try darkPixels { shape(IslandOpenedLook(corners: .square), profile: .topBar) }
        #expect(square > soft)
    }

    // MARK: A Nook page at each look

    @Test func theNookPreviewFollowsTheLook() throws {
        let placements = [
            NookWidgetPlacement(kind: .media, size: .medium),
            NookWidgetPlacement(kind: .timer, size: .small),
            NookWidgetPlacement(kind: .tray, size: .small),
        ]
        let widths = try IslandOpenedLook.all.map { look in
            try image("nook-notch-\(Self.name(look))") {
                PreviewNookPanel(
                    placements: placements,
                    calendarStyle: .strip,
                    profile: .notch,
                    look: look,
                    showsAgentsBar: false,
                    emptyTitle: ""
                )
            }.width
        }
        let expected = IslandOpenedLook.all.map { look in
            let panel = IslandOpenedMetrics.resolve(look: look, profile: .notch).panelWidth
            return Int(min(panel, PreviewNookPanel.maxWidth) * Self.scale)
        }
        #expect(widths == expected)
    }

    // MARK: The Settings cards

    @Test func theSettingsCardsDrawEachChoice() throws {
        let cards = try render("settings-cards") { settingsCards(selected: .standard) }
        let other = try render("settings-cards-widest-square") {
            settingsCards(selected: IslandOpenedLook(width: .widest, corners: .square))
        }
        #expect(cards != other)

        // Each card's picture is its own.
        let arts = try IslandOpenedLook.all.map { look in
            try render(nil) {
                OpenedLookArt(look: look, profile: .notch)
                    .frame(width: 131, height: 57)
                    .background(Color(white: 0.2))
            }
        }
        #expect(Set(arts).count == IslandOpenedLook.all.count)
    }

    // MARK: The tour's page

    @Test func theToursPageDrawsTheChoices() throws {
        let standard = try render("tour-opened") { tourPage(OnboardingState()) }
        let wide = try render("tour-opened-wide-square") {
            tourPage(OnboardingState(openedLook: IslandOpenedLook(width: .wide, corners: .square)))
        }
        let topBar = try render("tour-opened-top-bar") {
            tourPage(OnboardingState(displayProfile: .topBar))
        }
        #expect(standard != wide)
        #expect(standard != topBar)
    }

    // MARK: - What is drawn

    /// The island's own shape at the look's real size, hanging from the top
    /// of a stand-in screen.
    private func shape(_ look: IslandOpenedLook, profile: IslandAppearanceDisplayProfile) -> some View {
        let metrics = IslandOpenedMetrics.resolve(look: look, profile: profile)
        let surface = OpenedIslandSurfaceShape(
            topProfile: profile == .notch ? .notch : .topBar,
            topCornerRadius: metrics.topRadius,
            bottomCornerRadius: metrics.bottomRadius
        )
        return ZStack(alignment: .top) {
            Color(white: 0.42)
            surface
                .fill(Color.black)
                .frame(width: metrics.panelWidth, height: 230)
        }
        .frame(width: Self.stage.width, height: Self.stage.height)
    }

    private func settingsCards(selected: IslandOpenedLook) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ForEach(IslandOpenedWidth.allCases) { width in
                    PersonalizationCard(
                        title: LanguageManager.shared.t("settings.appearance.openedLook.width.\(width.rawValue)"),
                        selected: selected.width == width,
                        action: {}
                    ) {
                        OpenedLookArt(look: IslandOpenedLook(width: width, corners: selected.corners), profile: .notch)
                    }
                }
            }
            HStack(spacing: 12) {
                ForEach(IslandOpenedCorners.allCases) { corners in
                    PersonalizationCard(
                        title: LanguageManager.shared.t("settings.appearance.openedLook.corners.\(corners.rawValue)"),
                        selected: selected.corners == corners,
                        action: {}
                    ) {
                        OpenedLookArt(look: IslandOpenedLook(width: selected.width, corners: corners), profile: .notch)
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 574)
        .background(Color(red: 0.07, green: 0.07, blue: 0.08))
        .environment(\.colorScheme, .dark)
    }

    private func tourPage(_ state: OnboardingState) -> some View {
        OnboardingView(
            tour: OnboardingTour(startingAt: .opened, state: { state }),
            lang: LanguageManager.shared
        )
    }

    // MARK: - Rendering

    /// How many pixels of a picture are close to black.
    private func darkPixels<Content: View>(@ViewBuilder _ content: () -> Content) throws -> Int {
        let picture = try image(nil, content)
        let width = picture.width
        let height = picture.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
        var dark = 0
        for index in stride(from: 0, to: bytes.count, by: 4)
        where bytes[index] < 24 && bytes[index + 1] < 24 && bytes[index + 2] < 24 {
            dark += 1
        }
        return dark
    }

    private func image<Content: View>(_ name: String?, @ViewBuilder _ content: () -> Content) throws -> CGImage {
        let renderer = ImageRenderer(content: content().environment(\.nookDrawsStill, true))
        renderer.scale = Self.scale
        let rendered = try #require(renderer.cgImage, "no image for \(name ?? "a picture")")
        if let name, ProcessInfo.processInfo.environment[Self.snapshotEnvKey] == "1" {
            try write(rendered, name: name)
        }
        return rendered
    }

    private func render<Content: View>(_ name: String?, @ViewBuilder _ content: () -> Content) throws -> Data {
        let representation = NSBitmapImageRep(cgImage: try image(name, content))
        let encoded = representation.representation(using: .png, properties: [:])
        return try #require(encoded, "PNG encoding failed for \(name ?? "a picture")")
    }

    private func write(_ picture: CGImage, name: String) throws {
        let encoded = NSBitmapImageRep(cgImage: picture).representation(using: .png, properties: [:])
        let png = try #require(encoded, "PNG encoding failed for \(name)")
        let directory = Self.repoRoot.appendingPathComponent("output/render/opened-look", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    /// `Tests/OpenIslandAppTests/<this file>` sits three levels below the root.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
