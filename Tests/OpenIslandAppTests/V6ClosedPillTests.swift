import CoreGraphics
import SwiftUI
import Testing
@testable import OpenIslandApp

struct V6ClosedPillTests {
    @Test
    @MainActor
    func reportsRenderedWidthForPanelMorphing() {
        let macbookPill = V6ClosedPill(
            mode: .idle,
            label: nil,
            rightSlot: nil,
            layout: .macbook,
            height: 32,
            physicalNotchWidth: 224
        )
        let externalPill = V6ClosedPill(
            mode: .idle,
            label: nil,
            rightSlot: nil,
            layout: .external,
            height: 32
        )

        #expect(macbookPill.resolvedWidth == 312)
        #expect(externalPill.resolvedWidth == 70)
    }

    // MARK: Content key

    @Test
    @MainActor
    func contentKeyDiffersForDateAndBatteryLeftSlotsOfEqualWidth() {
        let datePill = makePill(leftSlot: .date(8))
        let batteryPill = makePill(leftSlot: .battery(percent: 80, isCharging: false))

        #expect(datePill.resolvedWidth == batteryPill.resolvedWidth)
        #expect(datePill.contentKey != batteryPill.contentKey)
    }

    @Test
    @MainActor
    func contentKeyFollowsTheNumberInsideALevelRing() {
        let seventyEight = makePill(activity: activity(symbol: "bolt.fill", level: 78))
        let seventyNine = makePill(activity: activity(symbol: "bolt.fill", level: 79))
        let words = makePill(activity: activity(symbol: "bolt.fill", text: "78"))

        #expect(seventyEight.contentKey != seventyNine.contentKey)
        #expect(seventyEight.contentKey != words.contentKey)
    }

    @Test
    @MainActor
    func contentKeyFollowsTheNumberInsideASlot() {
        let eighty = makePill(leftSlot: .battery(percent: 80, isCharging: false))
        let seventyNine = makePill(leftSlot: .battery(percent: 79, isCharging: false))

        #expect(eighty.contentKey != seventyNine.contentKey)
    }

    @Test
    @MainActor
    func contentKeyCoversLabelRightSlotModeAndLayout() {
        let base = makePill(label: "main", rightSlot: .count(2))

        #expect(base.contentKey != makePill(label: "dev", rightSlot: .count(2)).contentKey)
        #expect(base.contentKey != makePill(label: "main", rightSlot: .count(3)).contentKey)
        #expect(base.contentKey != makePill(label: "main", rightSlot: .count(2), mode: .running).contentKey)
        #expect(base.contentKey != makePill(label: "main", rightSlot: .count(2), layout: .macbook).contentKey)
    }

    @Test
    @MainActor
    func contentKeyFollowsAgentCellStates() {
        let running = IslandRightSlotContent.agents([.session(color: .blue, state: .running)])
        let waiting = IslandRightSlotContent.agents([.session(color: .blue, state: .waiting)])

        #expect(makePill(rightSlot: running).contentKey != makePill(rightSlot: waiting).contentKey)
    }

    @Test
    @MainActor
    func contentKeyIgnoresTheLabelOnMacbook() {
        let first = makePill(label: "main", layout: .macbook)
        let second = makePill(label: "dev", layout: .macbook)

        #expect(first.contentKey == second.contentKey)
    }

    @Test
    @MainActor
    func contentKeyFollowsTheActivityKindAndText() {
        let timer = makePill(activity: activity(symbol: "timer", text: "12:00"))
        let laterTimer = makePill(activity: activity(symbol: "timer", text: "11:59"))
        let charger = makePill(activity: activity(symbol: "bolt.fill", text: "12:00"))

        #expect(timer.contentKey != laterTimer.contentKey)
        #expect(timer.contentKey != charger.contentKey)
        #expect(timer.contentKey != makePill().contentKey)
    }

    // MARK: Equatable

    @Test
    @MainActor
    func equalInputsGiveEqualPills() {
        let left = makePill(label: "main", rightSlot: .count(2), leftSlot: .date(8))
        let right = makePill(label: "main", rightSlot: .count(2), leftSlot: .date(8))

        #expect(left == right)
    }

    @Test
    @MainActor
    func differentInputsGiveUnequalPills() {
        let base = makePill(label: "main")

        #expect(base != makePill(label: "dev"))
        #expect(base != makePill(label: "main", leftSlot: .date(8)))
        #expect(base != V6ClosedPill(mode: .idle, label: "main", rightSlot: nil, layout: .external, drawsBackground: false))
        #expect(base != V6ClosedPill(mode: .idle, label: "main", rightSlot: nil, layout: .external, isLive: false))
    }

    @Test
    @MainActor
    func artworkComparesByIdentity() {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        let sameImage = activity(artwork: image)
        let otherImage = activity(artwork: NSImage(size: NSSize(width: 4, height: 4)))

        #expect(makePill(activity: sameImage) == makePill(activity: sameImage))
        #expect(makePill(activity: sameImage) != makePill(activity: otherImage))
    }

    @Test
    @MainActor
    func previewPillIgnoresTheClock() {
        func previewPill(now: Date?) -> IslandPreviewPill {
            IslandPreviewPill(
                mode: .idle,
                label: nil,
                rightSlot: nil,
                layout: .external,
                physicalNotchWidth: 0,
                now: now
            )
        }

        #expect(previewPill(now: nil) == previewPill(now: Date(timeIntervalSince1970: 0)))
        #expect(previewPill(now: Date(timeIntervalSince1970: 1)) == previewPill(now: Date(timeIntervalSince1970: 2)))
    }

    // MARK: Background

    @Test
    @MainActor
    func pillWithoutBackgroundStillRenders() throws {
        // ImageRenderer reuses its bitmap per size without clearing it, so this
        // test owns a width no other render uses, and renders the empty pill first.
        let width: CGFloat = 91
        let omitted = try renderedAlpha(of: makePill(minWidth: width, leftSlot: .hidden, drawsBackground: false))
        let drawn = try renderedAlpha(of: makePill(minWidth: width, leftSlot: .hidden, drawsBackground: true))

        #expect(drawn.size == omitted.size)
        #expect(drawn.size.width == width)
        #expect(drawn.size.height == 32)
        #expect(drawn.alphaNearTopCenter > 0.99)
        #expect(omitted.alphaNearTopCenter < 0.01)
    }

    @Test
    func surfaceIsBlackOnMacbookAndInkOnExternal() {
        #expect(V6Palette.surface(for: .macbook) == Color.black)
        #expect(V6Palette.surface(for: .external) == V6Palette.ink)
    }

    // MARK: Waiting tile

    /// One waiting agent in a one-tile grid.
    private var waitingGrid: IslandRightSlotContent {
        .agents([.session(color: .white, state: .waiting)])
    }

    /// The opacity a not-live waiting tile is drawn at, within one 8-bit step.
    private func expectStaticWaitingOpacity(_ alpha: Double) {
        #expect(abs(alpha - Double(WaitingTilePulse.restOpacity)) < 0.02)
    }

    @Test
    @MainActor
    func notLiveRightSlotDrawsTheWaitingTileStatic() throws {
        // Each ImageRenderer test below owns a size no other render uses.
        let rendered = try renderedPixels(of: V6RightSlotView(content: waitingGrid, isLive: false))

        #expect(rendered.size == CGSize(width: 8, height: 8))
        expectStaticWaitingOpacity(rendered.centerAlpha)
    }

    @Test
    @MainActor
    func notLiveSideSlotReachesTheWaitingTile() throws {
        let rendered = try renderedPixels(of: NookSideSlotView(content: .agentSlot(waitingGrid), size: 26, isLive: false))

        #expect(rendered.size == CGSize(width: 26, height: 26))
        expectStaticWaitingOpacity(rendered.centerAlpha)
    }

    @Test
    @MainActor
    func notLivePillReachesTheWaitingTileInEveryAgentSlot() throws {
        let rightSlot = try renderedPixels(
            of: makePill(rightSlot: waitingGrid, minWidth: 93, leftSlot: .hidden, drawsBackground: false, isLive: false)
        )
        let leftSlot = try renderedPixels(
            of: makePill(minWidth: 95, leftSlot: .agentSlot(waitingGrid), drawsBackground: false, isLive: false)
        )
        let rightExtra = try renderedPixels(
            of: makePill(minWidth: 97, leftSlot: .hidden, rightExtra: .agentSlot(waitingGrid), drawsBackground: false, isLive: false)
        )

        for rendered in [rightSlot, leftSlot, rightExtra] {
            expectStaticWaitingOpacity(rendered.maxAlpha)
        }
    }

    @Test
    func restOpacitySitsBetweenIdleAndRunning() {
        #expect(WaitingTilePulse.restOpacity > 0.22)
        #expect(WaitingTilePulse.restOpacity < 1)
    }

    @Test
    @MainActor
    func liveWaitingTilePulsesOnACoreAnimationLoop() throws {
        let view = WaitingTilePulseLayerView()
        view.update(color: NSColor.white, radius: 1.5)

        let loop = try #require(view.layer?.animation(forKey: WaitingTilePulse.animationKey) as? CAKeyframeAnimation)
        #expect(loop.keyPath == "opacity")
        #expect(loop.repeatCount == .infinity)
        #expect(loop.duration == WaitingTilePulse.period)
        let low = Float(WaitingTilePulse.lowOpacity)
        let high = Float(WaitingTilePulse.highOpacity)
        #expect(loop.values as? [Float] == [low, high, low])
        // The loop starts on the shared grid, so every tile pulses in step.
        let phase = loop.beginTime.truncatingRemainder(dividingBy: WaitingTilePulse.period)
        #expect(min(phase, WaitingTilePulse.period - phase) < 1e-6)
    }

    @Test
    @MainActor
    func updatingTheWaitingTileAgainKeepsTheRunningLoop() throws {
        let view = WaitingTilePulseLayerView()
        view.update(color: NSColor.white, radius: 1.5)
        let first = try #require(view.layer?.animation(forKey: WaitingTilePulse.animationKey) as? CAKeyframeAnimation)

        view.update(color: NSColor.white, radius: 1.5)
        view.update(color: NSColor.red, radius: 1)
        let later = try #require(view.layer?.animation(forKey: WaitingTilePulse.animationKey) as? CAKeyframeAnimation)

        #expect(first.beginTime == later.beginTime)
        #expect(view.layer?.cornerRadius == 1)
    }

    // MARK: Slot swap

    @Test
    func slotSwapBlursOnlyWhenNothingRestrictsIt() {
        #expect(PillSlotSwap.resolve(reduceMotion: false, allowsBlur: true) == .blurReplace)
        #expect(PillSlotSwap.resolve(reduceMotion: true, allowsBlur: true) == .fade)
        #expect(PillSlotSwap.resolve(reduceMotion: false, allowsBlur: false) == .fade)
        #expect(PillSlotSwap.resolve(reduceMotion: true, allowsBlur: false) == .fade)
    }

    @Test
    func slotSwapFadesUnderEveryPolicyThatDropsBlur() {
        func swap(under policy: IslandMotionPolicy) -> PillSlotSwap {
            PillSlotSwap.resolve(reduceMotion: false, allowsBlur: policy.allowsBlur)
        }

        #expect(swap(under: .full) == .blurReplace)
        #expect(swap(under: .reduced) == .fade)
        #expect(swap(under: .conserving) == .fade)
        #expect(swap(under: .minimal) == .fade)
    }

    @Test
    @MainActor
    func lowPowerOverrideTurnsTheSlotSwapIntoAFade() {
        let monitor = SystemMotionMonitor(environment: ["OPEN_ISLAND_MOTION_POLICY": "conserving"])

        #expect(PillSlotSwap.resolve(reduceMotion: false, allowsBlur: monitor.policy.allowsBlur) == .fade)
    }

    // MARK: Helpers

    @MainActor
    private func makePill(
        label: String? = nil,
        rightSlot: IslandRightSlotContent? = nil,
        mode: UnifiedBars.Mode = .idle,
        layout: V6ClosedLayout = .external,
        minWidth: CGFloat = 70,
        activity: NookClosedActivity? = nil,
        leftSlot: NookSideSlotContent? = nil,
        rightExtra: NookSideSlotContent? = nil,
        drawsBackground: Bool = true,
        isLive: Bool = true
    ) -> V6ClosedPill {
        V6ClosedPill(
            mode: mode,
            label: label,
            rightSlot: rightSlot,
            layout: layout,
            height: 32,
            physicalNotchWidth: layout == .macbook ? 224 : 0,
            minWidth: minWidth,
            activity: activity,
            leftSlot: leftSlot,
            rightExtra: rightExtra,
            drawsBackground: drawsBackground,
            isLive: isLive
        )
    }

    private func activity(symbol: String, level: Int) -> NookClosedActivity {
        NookClosedActivity(
            leading: .symbol(symbol, .green),
            trailing: .level(percent: level, tint: .green),
            yieldsToAgents: false
        )
    }

    private func activity(symbol: String, text: String) -> NookClosedActivity {
        NookClosedActivity(
            leading: .symbol(symbol, .white),
            trailing: .text(text),
            yieldsToAgents: false
        )
    }

    private func activity(artwork: NSImage) -> NookClosedActivity {
        NookClosedActivity(
            leading: .artwork(artwork),
            trailing: .text("1:00"),
            yieldsToAgents: false
        )
    }

    private struct RenderedPixels {
        var size: CGSize
        var centerAlpha: Double
        var maxAlpha: Double
    }

    /// Renders the view at 1x into an RGBA bitmap and reads its alpha: at the
    /// center and the most any pixel has. ImageRenderer cannot draw AppKit
    /// views, so only static SwiftUI content is meaningful here.
    @MainActor
    private func renderedPixels(of view: some View) throws -> RenderedPixels {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)

        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(
            CGContext(
                data: &pixels,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        let alphas = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
        let center = (image.height / 2) * image.width + image.width / 2
        return RenderedPixels(
            size: CGSize(width: image.width, height: image.height),
            centerAlpha: Double(alphas[center]) / 255,
            maxAlpha: Double(alphas.max() ?? 0) / 255
        )
    }

    private struct RenderedAlpha {
        var size: CGSize
        var alphaNearTopCenter: Double
    }

    /// Renders the pill at 1x and reads the alpha of a pixel just under the
    /// flat top edge, in the middle, which only the fill can cover.
    @MainActor
    private func renderedAlpha(of pill: V6ClosedPill) throws -> RenderedAlpha {
        let renderer = ImageRenderer(content: pill)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)

        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(
            CGContext(
                data: &pixel,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        // Draw the whole image so the sampled pixel lands in the context's one
        // pixel: shift the image so (x, y) from the top-left is at the origin.
        let x = image.width / 2
        let y = 2
        context.draw(
            image,
            in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height)
        )
        return RenderedAlpha(
            size: CGSize(width: image.width, height: image.height),
            alphaNearTopCenter: Double(pixel[3]) / 255
        )
    }
}
