import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Draws the preview stage offscreen. Set `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to
/// also write the PNGs to `output/render/` under the repo root.
@MainActor
struct PreviewStageRenderTests {
    private static let scale: CGFloat = 2
    private static let enabled = NookWidgetKind.defaultEnabled

    private static func setup(_ template: PersonalizationTemplate) -> PersonalizationSetup {
        PersonalizationSetup(appearance: template.appearance, nook: template.applying(to: NookDisplayPreferences()))
    }

    // MARK: Sheet

    @Test
    func everyTemplateDrawsItsOwnNookPage() throws {
        let renders = try PersonalizationTemplate.all.map { template in
            try render("stage-\(template.id.rawValue)-nook") {
                sheet(template, moment: .openNook, profile: .notch)
            }
        }
        #expect(Set(renders.map(\.png)).count == renders.count, "every template should draw its own page")
    }

    @Test
    func everyMomentOfOneTemplateDrawsDifferently() throws {
        let renders = try PreviewMoment.allCases.map { moment in
            try render("stage-cockpit-\(moment.rawValue)") {
                sheet(.cockpit, moment: moment, profile: .notch)
            }
        }
        #expect(Set(renders.map(\.png)).count == renders.count, "each moment should change the picture or its caption")
    }

    @Test
    func bothPagesOfEveryTemplateFitTheStageWithoutScrolling() throws {
        for template in PersonalizationTemplate.all {
            let setup = Self.setup(template)
            let area = PreviewStageMetrics.areaHeight(setup: setup, enabledWidgets: Self.enabled)
            let room = (area - PreviewStageMetrics.bottomPadding) / PreviewStageMetrics.scale
            let nook = PreviewStageMetrics.nookPanelHeight(setup: setup, enabledWidgets: Self.enabled)
            let agents = try render(nil) { agentsPanel(setup) }.height

            #expect(nook <= room + 1, "\(template.id): the Nook page is \(nook), the stage holds \(room)")
            #expect(agents <= room + 1, "\(template.id): the agents page is \(agents), the stage holds \(room)")
        }
    }

    @Test
    func theStageDrawsOnBothDisplays() throws {
        let notch = try render("stage-planner-agents-notch") { sheet(.planner, moment: .openAgents, profile: .notch) }
        let topBar = try render("stage-planner-agents-topbar") { sheet(.planner, moment: .openAgents, profile: .topBar) }
        let music = try render("stage-nowPlaying-music-topbar") { sheet(.nowPlaying, moment: .music, profile: .topBar) }
        #expect(notch.png != topBar.png)
        #expect(music.height > 0)
    }

    // MARK: Where the stage opens from

    @Test
    func theTemplateCardsShowAPreviewControl() throws {
        let plain = try render(nil) { GalleryHarness(showsPreview: false).frame(width: 488) }
        let withPreview = try render("template-gallery-preview") { GalleryHarness(showsPreview: true).frame(width: 488) }
        // The narrowest the settings window lets the tab get.
        let narrow = try render("template-gallery-preview-narrow") { GalleryHarness(showsPreview: true).frame(width: 464) }

        #expect(plain.png != withPreview.png, "each card should carry a preview control")
        // The control sits under the thumbnail. A card only grows when its
        // text was shorter than that, which is at most the control per card.
        let most = CGFloat(PersonalizationTemplate.all.count) * (TemplatePreviewControl.height + TemplatePreviewControl.gap)
        #expect(withPreview.height >= plain.height)
        #expect(withPreview.height - plain.height <= most, "\(plain.height) became \(withPreview.height)")
        #expect(narrow.height > 0)
    }

    private struct GalleryHarness: View {
        let showsPreview: Bool
        @Namespace private var ring

        var body: some View {
            TemplateGallery(
                lang: .shared,
                applied: .planner,
                canUndo: false,
                isCollapsed: .constant(false),
                ringNamespace: ring,
                apply: { _ in },
                undo: {},
                preview: showsPreview ? { _ in } : nil
            )
            .padding(16)
        }
    }

    // MARK: Nook sample page

    @Test
    func theNookSamplePageFitsEveryWidgetAtEverySizeAndLook() throws {
        for profile in [IslandAppearanceDisplayProfile.notch, .topBar] {
            for size in NookWidgetSize.allCases {
                let placements = NookWidgetKind.allCases.map { NookWidgetPlacement(kind: $0, size: size) }
                let page = try render("nook-samples-\(profile.rawValue)-\(size.rawValue)") {
                    PreviewNookPanel(
                        placements: placements,
                        calendarStyle: .strip,
                        profile: profile,
                        showsAgentsBar: true,
                        emptyTitle: ""
                    )
                    .padding(24)
                }
                #expect(page.height > 200, "\(profile) \(size)")
            }
        }
        // Every calendar look at medium and at large, with the todo card
        // under it the way a real page pairs them.
        for style in NookCalendarStyle.allCases {
            for size in [NookWidgetSize.medium, .large] {
                let page = try render("nook-samples-calendar-\(style.rawValue)-\(size.rawValue)") {
                    PreviewNookPanel(
                        placements: [
                            NookWidgetPlacement(kind: .calendar, size: size),
                            NookWidgetPlacement(kind: .todo, size: .small),
                        ],
                        calendarStyle: style,
                        profile: .notch,
                        showsAgentsBar: false,
                        emptyTitle: ""
                    )
                    .padding(24)
                }
                #expect(page.height > 200, "\(style) \(size)")
            }
        }
    }

    @Test
    func theNookPanelIsAsTallAsTheSizingMathSays() throws {
        for template in PersonalizationTemplate.all {
            let setup = Self.setup(template)
            let expected = PreviewStageMetrics.nookPanelHeight(setup: setup, enabledWidgets: Self.enabled)
            let panel = try render(nil) {
                PreviewNookPanel(
                    placements: setup.nook.placements(enabled: Self.enabled),
                    calendarStyle: setup.nook.calendarStyle,
                    profile: .notch,
                    showsAgentsBar: setup.nook.showsAgentsBar,
                    emptyTitle: ""
                )
            }
            #expect(abs(panel.height - expected) <= 1, "\(template.id): drew \(panel.height), math says \(expected)")
        }
    }

    @Test
    func theAgentsPageIsNoTallerThanTheSizingMathSays() throws {
        for group in IslandSessionGroup.allCases {
            var setup = Self.setup(.cockpit)
            setup.appearance.sessionGroup = group
            let expected = PreviewStageMetrics.agentsPanelHeight(setup: setup)
            let panel = try render(nil) { agentsPanel(setup) }
            #expect(panel.height <= expected + 1, "\(group): drew \(panel.height), math allows \(expected)")
            #expect(panel.height >= expected - 40, "\(group): the allowance is far too generous")
        }
    }

    // MARK: Rendering

    /// The agents page the way the stage draws it for `setup`.
    private func agentsPanel(_ setup: PersonalizationSetup) -> some View {
        SessionListPanelPreview(
            sections: SessionListPreviewSamples.sections(
                lang: .shared,
                group: setup.appearance.sessionGroup,
                sort: setup.appearance.sessionSort,
                staleThreshold: setup.appearance.completedStaleThreshold,
                limit: PreviewStageMetrics.agentsListLimit
            ),
            showsSections: setup.appearance.sessionGroup != .none,
            indicator: setup.appearance.sessionStateIndicator,
            profile: .notch,
            lang: .shared,
            showsNowPlayingRow: setup.nook.showsCompactBar
        )
        .frame(width: 560)
    }

    private func sheet(
        _ template: PersonalizationTemplate,
        moment: PreviewMoment,
        profile: IslandAppearanceDisplayProfile
    ) -> some View {
        PreviewStageSheet(
            title: "Template",
            setup: Self.setup(template),
            profile: profile,
            enabledWidgets: Self.enabled,
            lang: .shared,
            primaryTitle: "Use this template",
            onClose: {},
            startsPlaying: false,
            initialMoment: moment,
            isScrollable: false
        )
    }

    private struct Rendered {
        let png: Data
        let height: CGFloat
    }

    /// Renders `content` at its own size. A name also writes the PNG when
    /// snapshots are on.
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
