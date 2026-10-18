import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Draws the update flow's states (D82) with `ImageRenderer`: the closed
/// pill asking, updating, and carrying its marks, and the three cards of
/// the open island. Set `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to also write the
/// PNGs to `output/render/update-flow/` under the repo root, which is how
/// they are compared with the frames in `design/update-flow/`.
@MainActor
struct UpdateFlowRenderTests {
    private static let scale: CGFloat = 2
    private static let notchWidth: CGFloat = 180
    private static let pillHeight: CGFloat = 32
    /// The page width of the open island, which the cards span.
    private static let pageWidth: CGFloat = 416

    private static let ask = NookClosedActivity(
        leading: .symbol("arrow.down.circle.fill", V6Palette.paper),
        trailing: .chips(NookClosedChips(
            deny: NookClosedChip(keys: "⌃⌥N", title: "Later"),
            approve: NookClosedChip(keys: "⌃⌥Y", title: "Install", isPrimary: true)
        )),
        yieldsToAgents: false,
        leadingText: "New version dropped! Install?"
    )

    /// The shipped words, which is what the picture is compared with; a
    /// bundle without them (never, in this package) falls back to one row.
    private static let whatsNew: WhatsNewPending = {
        let bundled = WhatsNewCatalog.bundled().releases.filter { $0.version == "1.0.14" }
        return WhatsNewPending(releases: bundled.isEmpty ? whatsNewOne.releases : bundled)
    }()

    private static let whatsNewOne = WhatsNewPending(releases: [
        WhatsNewRelease(version: "1.0.14", items: [
            WhatsNewItem(title: "Updates ask first", detail: "When a new version lands, the island asks. One press and it's back."),
        ]),
    ])

    // MARK: - The closed pill

    @Test
    func theAskWidensThePillForTheQuestionAndTheChips() throws {
        let plain = Self.pill(activity: nil)
        let asking = Self.pill(activity: Self.ask)

        #expect(plain.resolvedWidth == V6ClosedPill.plainWingWidth * 2 + Self.notchWidth)
        #expect(asking.resolvedWidth > plain.resolvedWidth + 200, "the question and two chips need room on both sides")
        // The pill is centred on the notch: both wings grow alike, or one
        // side's words would slide under it.
        #expect(asking.resolvedWidth == (V6ClosedPill.mediaWingWidth + asking.macbookWingGrowth) * 2 + Self.notchWidth)
        #expect(asking.macbookWingGrowth == V6ClosedPill.maxWingGrowth, "the question is longer than the cap")

        let png = try Self.renderPill("closed-ask", asking)
        #expect(!png.isEmpty)
    }

    @Test
    func updatingShowsASpinnerAndTheVersion() throws {
        let updating = Self.pill(activity: NookClosedActivity(
            leading: .spinner,
            trailing: .text("Updating to 1.0.14…"),
            yieldsToAgents: false
        ))
        let timer = Self.pill(activity: NookClosedActivity(
            leading: .symbol("timer", .orange),
            trailing: .text("24m"),
            yieldsToAgents: false
        ))
        #expect(updating.resolvedWidth > timer.resolvedWidth, "the words widen the right wing, a short time does not")
        #expect(timer.resolvedWidth == V6ClosedPill.mediaWingWidth * 2 + Self.notchWidth, "a short time keeps the wing as it was")
        let tenMinutes = Self.pill(activity: NookClosedActivity(
            leading: .symbol("timer", .orange), trailing: .text("10:00"), yieldsToAgents: false
        ))
        #expect(tenMinutes.resolvedWidth == timer.resolvedWidth, "a time a hair too wide shrinks instead of moving the pill")

        let png = try Self.renderPill("closed-updating", updating)
        #expect(!png.isEmpty)
    }

    @Test
    func theMarksSitOnTheRightWithAPaperDot() throws {
        let whatsNew = Self.pill(activity: nil, rightExtra: .notice("1.0.14 · what's new"))
        let ready = Self.pill(activity: nil, rightExtra: .notice("Update ready"))
        let plain = Self.pill(activity: nil)

        #expect(whatsNew.resolvedWidth > ready.resolvedWidth)
        #expect(ready.resolvedWidth > plain.resolvedWidth)
        #expect(whatsNew.contentKey != ready.contentKey)

        let notice = try Self.renderPill("closed-notice", whatsNew)
        let mark = try Self.renderPill("closed-update-ready", ready)
        #expect(notice != mark)
    }

    @Test
    func anAgentWaitingKeepsTheRightSideOverAMark() {
        let pill = V6ClosedPill(
            mode: .waiting,
            label: nil,
            rightSlot: .count(1),
            layout: .macbook,
            height: Self.pillHeight,
            physicalNotchWidth: Self.notchWidth,
            agentsNeedAttention: true,
            rightExtra: .notice("Update ready")
        )
        #expect(pill.contentKey.rightExtra == nil, "the agent's slot wins while it waits")
    }

    // MARK: - The cards

    @Test
    func theThreeCardsRenderAtTheirOwnHeights() throws {
        let hint = AgentHotkeyHint(approve: "⌃⌥Y", deny: "⌃⌥N")
        let ask = try Self.renderCard("open-ask", .ask(version: "1.0.14"), hint: hint)
        let ready = try Self.renderCard("open-update-ready", .ready(version: "1.0.14"))
        let three = try Self.renderCard("open-whats-new-3", .whatsNew(Self.whatsNew))
        let one = try Self.renderCard("open-whats-new-1", .whatsNew(Self.whatsNewOne))

        #expect(ask != ready)
        #expect(three != one)
        #expect(UpdateCardLayout.height(for: .whatsNew(Self.whatsNew)) == UpdateCardLayout.whatsNewBaseHeight + 3 * UpdateCardLayout.whatsNewRowHeight, "three rows, not four")
        #expect(UpdateCardLayout.height(for: .whatsNew(Self.whatsNewOne)) == UpdateCardLayout.whatsNewBaseHeight + UpdateCardLayout.whatsNewRowHeight)
        #expect(UpdateCardLayout.height(for: .ask(version: "1.0.14")) > UpdateCardLayout.height(for: .ready(version: "1.0.14")), "the ask carries the line of keys")
    }

    /// The About pane is a `Form`, which `ImageRenderer` draws empty; the
    /// words under the switch are checked as words.
    @Test
    func theAboutPaneCarriesTheStatusLine() {
        let model = AppModel(agentsDefaults: MemoryDefaults(), defaults: MemoryDefaults())
        model.nook.presentRingLight = { _ in }
        model.updateChecker.installsAutomatically = true
        #expect(model.updateFlow.settingsStatus == nil)
        model.updateFlow.noteDownloaded(version: "1.0.14", install: {})
        #expect(model.updateFlow.settingsStatus == "1.0.14 downloaded · asks when the island is free")
        model.updateFlow.answerLater()
        #expect(model.updateFlow.settingsStatus == "1.0.14 downloaded · installs on the next restart")
    }

    // MARK: - Helpers

    /// The agent bars on the left are a view `ImageRenderer` cannot draw,
    /// so the pictures leave that side empty.
    private static func pill(activity: NookClosedActivity?, rightExtra: NookSideSlotContent? = nil) -> V6ClosedPill {
        V6ClosedPill(
            mode: .idle,
            label: nil,
            rightSlot: nil,
            layout: .macbook,
            height: pillHeight,
            physicalNotchWidth: notchWidth,
            activity: activity,
            leftSlot: activity == nil ? .hidden : nil,
            rightExtra: rightExtra
        )
    }

    /// The pill on a mid grey, since its fill is black on a MacBook.
    private static func renderPill(_ name: String, _ pill: V6ClosedPill) throws -> Data {
        try render(name, size: CGSize(width: pill.resolvedWidth + 40, height: pillHeight + 24), background: Color(white: 0.35)) {
            pill
        }
    }

    private static func renderCard(_ name: String, _ kind: UpdateCardKind, hint: AgentHotkeyHint? = nil) throws -> Data {
        let height = UpdateCardLayout.height(for: kind)
        return try render(name, size: CGSize(width: pageWidth + 24, height: height + 24)) {
            UpdateCardView(kind: kind, hint: hint)
                .frame(width: pageWidth, height: height)
        }
    }

    private static func render<Content: View>(
        _ name: String,
        size: CGSize,
        background: Color = V6Palette.ink,
        @ViewBuilder content: () -> Content
    ) throws -> Data {
        let framed = content()
            .frame(width: size.width, height: size.height)
            .background(background)
            .environment(\.colorScheme, .dark)
            .environment(\.nookDrawsStill, true)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = scale
        let image = try #require(renderer.cgImage, "ImageRenderer returned no image for \(name)")
        let png = try #require(
            NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
            "PNG encoding failed for \(name)"
        )
        if ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_SNAPSHOTS"] == "1" {
            let directory = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("output/render/update-flow", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return png
    }
}
