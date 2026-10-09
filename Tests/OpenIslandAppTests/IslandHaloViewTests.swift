import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

@MainActor
@Suite struct IslandHaloViewTests {
    private static let opacityKey = "halo.opacity"
    private static let paneSize = CGSize(width: 160, height: 60)

    private static func breathing(
        color: IslandHaloRGB = .approval,
        period: TimeInterval = 2,
        rest: Double = 0.55
    ) -> IslandHaloState {
        IslandHaloState(
            source: .approval, color: color,
            motion: .breathing(period: period, low: 0.35, high: 0.75),
            restOpacity: rest, radius: 10, drop: 3
        )
    }

    private static func flash(token: UInt64, peak: Double = 0.85, rest: Double = 0) -> IslandHaloState {
        IslandHaloState(
            source: .completed, color: .completed,
            motion: .flash(token: token, peak: peak, duration: 1.2),
            restOpacity: rest, radius: 10, drop: 3
        )
    }

    private static func drift(rest: Double = 0.3) -> IslandHaloState {
        IslandHaloState(source: .music, color: .running, motion: .drift(period: 8), restOpacity: rest, radius: 10, drop: 3)
    }

    private static func steady(color: IslandHaloRGB = .completed, rest: Double = 0.7, radius: CGFloat = 10) -> IslandHaloState {
        IslandHaloState(source: .notice, color: color, motion: .steady, restOpacity: rest, radius: radius, drop: 3)
    }

    /// A view sized the way the modifier sizes it: the pill plus `spread` on each side.
    private static func makeView(for state: IslandHaloState, cornerRadius: CGFloat = 16) -> IslandHaloLayerView {
        let spread = IslandHaloLayerView.maxSpread
        let view = IslandHaloLayerView(
            frame: CGRect(x: 0, y: 0, width: paneSize.width + spread * 2, height: paneSize.height + spread * 2)
        )
        view.cornerRadius = cornerRadius
        view.layoutSubtreeIfNeeded()
        return view
    }

    private static func opacityAnimation(of view: IslandHaloLayerView) -> CAAnimation? {
        view.glowLayer.animation(forKey: opacityKey)
    }

    // MARK: Breathing

    @Test func applyingTheSameBreathingStateTwiceKeepsTheAnimation() throws {
        let state = Self.breathing()
        let view = Self.makeView(for: state)

        view.apply(state: state)
        let first = try #require(Self.opacityAnimation(of: view))
        let firstBegin = first.beginTime

        view.apply(state: state)
        let second = try #require(Self.opacityAnimation(of: view))

        #expect(view.opacityAnimationStarts == 1)
        #expect(second.beginTime == firstBegin)
        #expect(second.duration == first.duration)
        #expect(second.repeatCount == .infinity)
        #expect(second.autoreverses)
    }

    @Test func breathingRunsHalfAPeriodBetweenLowAndHighOnAGlobalGrid() throws {
        let period: TimeInterval = 2.6
        let state = Self.breathing(period: period)
        let view = Self.makeView(for: state)

        view.apply(state: state)
        let animation = try #require(Self.opacityAnimation(of: view) as? CABasicAnimation)

        #expect(animation.keyPath == "opacity")
        #expect(animation.fromValue as? Float == 0.35)
        #expect(animation.toValue as? Float == 0.75)
        #expect(animation.duration == period / 2)
        let gridSteps = animation.beginTime / period
        #expect(abs(gridSteps - gridSteps.rounded()) < 1e-9)
        #expect(animation.beginTime <= CACurrentMediaTime())
    }

    @Test func gridBeginTimeIsSharedAcrossCalls() {
        #expect(IslandHaloLayerView.gridBeginTime(cycle: 2, now: 7.3) == 6)
        #expect(IslandHaloLayerView.gridBeginTime(cycle: 2, now: 7.9) == 6)
        #expect(IslandHaloLayerView.gridBeginTime(cycle: 2, now: 8.0) == 8)
    }

    @Test func changingOnlyTheColorDoesNotRestartTheLoop() throws {
        let view = Self.makeView(for: Self.breathing())
        view.apply(state: Self.breathing(color: .approval))
        let begin = try #require(Self.opacityAnimation(of: view)).beginTime

        view.apply(state: Self.breathing(color: .question))

        #expect(view.opacityAnimationStarts == 1)
        #expect(Self.opacityAnimation(of: view)?.beginTime == begin)
    }

    // MARK: Flash

    @Test func aNewFlashTokenReplacesTheAnimationAndTheSameTokenDoesNot() throws {
        let view = Self.makeView(for: Self.flash(token: 1))

        view.apply(state: Self.flash(token: 1))
        let first = try #require(Self.opacityAnimation(of: view) as? CAKeyframeAnimation)
        #expect(view.opacityAnimationStarts == 1)
        #expect(first.keyTimes == [0, 0.18, 0.5, 1])
        #expect(first.duration == 1.2)

        // Same token, different peak: not a new flash.
        view.apply(state: Self.flash(token: 1, peak: 0.6))
        #expect(view.opacityAnimationStarts == 1)

        view.apply(state: Self.flash(token: 2))
        #expect(view.opacityAnimationStarts == 2)
        #expect(Self.opacityAnimation(of: view) is CAKeyframeAnimation)
    }

    @Test func aFlashPeaksThenFallsToItsRestOpacity() throws {
        let view = Self.makeView(for: Self.flash(token: 1))
        view.apply(state: Self.flash(token: 1))

        let animation = try #require(Self.opacityAnimation(of: view) as? CAKeyframeAnimation)
        let values = try #require(animation.values as? [Float])

        #expect(values.count == 4)
        #expect(values[0] == 0)
        #expect(values[1] == 0.85)
        #expect(abs(values[2] - 0.85 * 0.55) < 1e-6)
        #expect(values[3] == 0)
    }

    @Test func aForcedFlashKeepsItsPeakAtRest() {
        let state = Self.flash(token: 1, peak: 0.8, rest: 0.8)
        let view = Self.makeView(for: state)

        view.apply(state: state)

        #expect(view.glowLayer.opacity == 0.8)
    }

    // MARK: Spread, fades and policy

    @Test func spreadIsOneConstantForEveryState() {
        let states = [Self.breathing(), Self.flash(token: 1), Self.drift(), Self.steady(radius: 18), .off]
        let radius = [IslandHaloMetrics.subtle, .vivid, .opened].map(\.radius).max() ?? 0
        let drop = [IslandHaloMetrics.subtle, .vivid, .opened].map(\.drop).max() ?? 0
        #expect(IslandHaloLayerView.maxSpread == radius * 2 + drop)
        for state in states {
            #expect(IslandHaloLayerView.spread(for: state) == IslandHaloLayerView.maxSpread)
        }
    }

    @Test func aLoopStartedFromNothingAddsAFadeEnvelope() throws {
        let view = Self.makeView(for: .off)
        view.apply(state: .off)

        view.apply(state: Self.breathing())

        let envelope = try #require(view.glowLayer.animation(forKey: "halo.envelope") as? CABasicAnimation)
        #expect(envelope.keyPath == "shadowOpacity")
        #expect(envelope.fromValue as? Float == 0)
        #expect(envelope.toValue as? Float == 1)
        #expect(envelope.duration == Motion.Halo.fade)
    }

    @Test func aLoopReplacingAVisibleGlowLeavesAFadingCopy() {
        let view = Self.makeView(for: Self.steady())
        view.apply(state: Self.steady())

        view.apply(state: Self.drift())

        #expect(view.outgoingLayerCount == 1)
    }

    @Test func aDriftRestOpacityChangeReplacesTheLoop() throws {
        let view = Self.makeView(for: Self.drift(rest: 0.3))
        view.apply(state: Self.drift(rest: 0.3))
        #expect(view.opacityAnimationStarts == 1)

        view.apply(state: Self.drift(rest: 0.5))

        #expect(view.opacityAnimationStarts == 2)
        let animation = try #require(Self.opacityAnimation(of: view) as? CABasicAnimation)
        #expect(abs((animation.toValue as? Float ?? 0) - 0.5 * 1.15) < 1e-6)
    }

    @Test func anEqualLoopStateStartsNothingAndAddsNoCopy() {
        let view = Self.makeView(for: Self.drift())
        view.apply(state: Self.drift())
        view.apply(state: Self.drift())
        #expect(view.opacityAnimationStarts == 1)
        #expect(view.outgoingLayerCount == 0)
    }

    @Test func aReducedMotionFlashIsOneTwoValueFade() throws {
        let view = Self.makeView(for: Self.flash(token: 1))
        view.policyProvider = { .reduced }

        view.apply(state: Self.flash(token: 1))

        let fade = try #require(Self.opacityAnimation(of: view) as? CABasicAnimation)
        #expect(fade.fromValue as? Float == 0.85)
        #expect(fade.toValue as? Float == 0)
        #expect(fade.duration == 1.2)
    }

    // MARK: Opacity at rest

    @Test func layerOpacityEqualsRestOpacityAfterApply() {
        let states = [
            Self.breathing(rest: 0.55),
            Self.flash(token: 1, rest: 0),
            Self.drift(rest: 0.3),
            Self.steady(rest: 0.7),
        ]
        for state in states {
            let view = Self.makeView(for: state)
            view.apply(state: state)
            #expect(view.glowLayer.opacity == Float(state.restOpacity), "\(state.motion)")
        }
    }

    @Test func offLeavesTheLayerInvisible() {
        let view = Self.makeView(for: .off)

        view.apply(state: .off)

        #expect(view.glowLayer.opacity == 0)
        #expect(Self.opacityAnimation(of: view) == nil)
        #expect(view.opacityAnimationStarts == 0)
    }

    @Test func driftMovesAroundRestOpacityOverItsPeriod() throws {
        let state = Self.drift(rest: 0.3)
        let view = Self.makeView(for: state)

        view.apply(state: state)
        let animation = try #require(Self.opacityAnimation(of: view) as? CABasicAnimation)

        #expect(abs((animation.fromValue as? Float ?? 0) - 0.3 * 0.75) < 1e-6)
        #expect(abs((animation.toValue as? Float ?? 0) - 0.3 * 1.15) < 1e-6)
        #expect(animation.duration == 8)
        #expect(animation.autoreverses)
    }

    @Test func steadyFadesInFromWhatIsOnScreenWithoutAnimatingTheFirstApply() {
        let state = Self.steady(rest: 0.7)
        let view = Self.makeView(for: state)

        view.apply(state: state)

        #expect(view.glowLayer.opacity == 0.7)
        #expect(Self.opacityAnimation(of: view) == nil)

        view.apply(state: Self.steady(rest: 0.4))
        #expect(view.glowLayer.opacity == 0.4)
        #expect(Self.opacityAnimation(of: view)?.duration == Motion.Halo.fade)
    }

    @Test func goingOffFadesTheLoopOutAndKeepsTheOldLook() throws {
        let state = Self.breathing()
        let view = Self.makeView(for: state)
        view.apply(state: state)

        view.apply(state: .off)

        #expect(view.glowLayer.opacity == 0)
        let fade = try #require(Self.opacityAnimation(of: view) as? CABasicAnimation)
        #expect(fade.repeatCount == 0)
        #expect(fade.duration == Motion.Halo.fade)
        #expect(fade.toValue as? Float == 0)
        // The glow keeps its color and size while it fades out.
        #expect(view.glowLayer.shadowRadius == 10)
        #expect(view.glowLayer.shadowColor == IslandHaloRGB.approval.cgColor)
    }

    // MARK: Look

    @Test func theLayerIsAShadowOfThePillWithNoContents() {
        let state = Self.steady(color: .question, radius: 12)
        let view = Self.makeView(for: state)

        view.apply(state: state)
        let layer = view.glowLayer

        #expect(layer.contents == nil)
        #expect(layer.shadowOpacity == 1)
        #expect(layer.shadowOffset == .zero)
        #expect(layer.shadowRadius == 12)
        #expect(layer.shadowColor == IslandHaloRGB.question.cgColor)
        #expect(layer.shouldRasterize)
        #expect(layer.rasterizationScale == layer.contentsScale)
    }

    @Test func theShadowPathIsThePillInsetAndShiftedDown() throws {
        let state = Self.steady(radius: 10)
        let view = Self.makeView(for: state, cornerRadius: 16)
        let spread = IslandHaloLayerView.maxSpread
        #expect(spread == 41)

        view.apply(state: state)
        view.layoutSubtreeIfNeeded()
        let box = try #require(view.glowLayer.shadowPath).boundingBox

        // The pill is the bounds inset by spread; the glow is inset by
        // pillInset more and dropped by 3. The view is flipped, so down is +y.
        let inset = spread + IslandHaloLayerView.pillInset
        #expect(view.isFlipped)
        #expect(abs(box.minX - inset) < 0.001)
        #expect(abs(box.minY - (inset + 3)) < 0.001)
        let pillInset = IslandHaloLayerView.pillInset
        #expect(abs(box.width - (Self.paneSize.width - pillInset * 2)) < 0.001)
        #expect(abs(box.height - (Self.paneSize.height - pillInset * 2)) < 0.001)
    }

    @Test func resizingTheViewMovesThePathWithoutTouchingAnimations() throws {
        let state = Self.breathing()
        let view = Self.makeView(for: state)
        view.apply(state: state)
        let begin = try #require(Self.opacityAnimation(of: view)).beginTime
        let before = try #require(view.glowLayer.shadowPath).boundingBox

        view.setFrameSize(NSSize(width: view.frame.width + 40, height: view.frame.height))
        view.layoutSubtreeIfNeeded()
        let after = try #require(view.glowLayer.shadowPath).boundingBox

        #expect(abs(after.width - (before.width + 40)) < 0.001)
        #expect(view.glowLayer.frame.width == view.bounds.width)
        #expect(view.opacityAnimationStarts == 1)
        #expect(Self.opacityAnimation(of: view)?.beginTime == begin)
    }

    // MARK: Color and radius

    @Test func aColorChangeCrossfadesFromWhatIsOnScreen() throws {
        let view = Self.makeView(for: Self.steady(color: .approval))
        view.apply(state: Self.steady(color: .approval))
        #expect(view.glowLayer.animation(forKey: "halo.color") == nil)

        view.apply(state: Self.steady(color: .question))

        let animation = try #require(view.glowLayer.animation(forKey: "halo.color") as? CABasicAnimation)
        #expect(animation.keyPath == "shadowColor")
        #expect(animation.duration == Motion.Halo.colorCrossfade)
        #expect(animation.toValue as! CGColor == IslandHaloRGB.question.cgColor)
        #expect(view.glowLayer.shadowColor == IslandHaloRGB.question.cgColor)
    }

    @Test func aColorChangeFromInvisibleJustSetsTheColor() {
        let view = Self.makeView(for: .off)
        view.apply(state: .off)

        view.apply(state: Self.steady(color: .question))

        #expect(view.glowLayer.animation(forKey: "halo.color") == nil)
        #expect(view.glowLayer.shadowColor == IslandHaloRGB.question.cgColor)
    }

    @Test func aRadiusChangeAnimatesTheShadowRadius() throws {
        let view = Self.makeView(for: Self.steady(radius: 10))
        view.apply(state: Self.steady(radius: 10))

        view.apply(state: Self.steady(radius: 16))

        let animation = try #require(view.glowLayer.animation(forKey: "halo.radius") as? CABasicAnimation)
        #expect(animation.keyPath == "shadowRadius")
        #expect(animation.duration == Motion.Halo.fade)
        #expect(view.glowLayer.shadowRadius == 16)
    }

    // MARK: Hosting

    @Test func theModifierReachesPastTheViewWithoutChangingItsLayout() throws {
        let state = Self.steady(radius: 10)
        let spread = IslandHaloLayerView.maxSpread
        let pill = Color.black.frame(width: Self.paneSize.width, height: Self.paneSize.height)
        let host = NSHostingView(rootView: pill.islandHalo(state, cornerRadius: 16))
        host.frame = CGRect(origin: .zero, size: Self.paneSize)
        host.layoutSubtreeIfNeeded()

        let haloView = try #require(Self.findHaloView(in: host))
        let frame = host.convert(haloView.bounds, from: haloView)

        #expect(host.fittingSize == Self.paneSize)
        #expect(abs(frame.width - (Self.paneSize.width + spread * 2)) < 0.5)
        #expect(abs(frame.height - (Self.paneSize.height + spread * 2)) < 0.5)
        #expect(abs(frame.minX + spread) < 0.5)
        #expect(abs(frame.minY + spread) < 0.5)
        #expect(haloView.lastState == state)
        #expect(haloView.glowLayer.opacity == Float(state.restOpacity))
    }

    @Test func theHaloNeverTakesAHit() throws {
        let state = Self.steady()
        let host = NSHostingView(rootView: Color.black.frame(width: 160, height: 60).islandHalo(state, cornerRadius: 16))
        host.frame = CGRect(x: 0, y: 0, width: 160, height: 60)
        host.layoutSubtreeIfNeeded()
        let haloView = try #require(Self.findHaloView(in: host))

        #expect(haloView.hitTest(NSPoint(x: 30, y: 30)) == nil)
        #expect(haloView.hitTest(NSPoint(x: haloView.bounds.midX, y: haloView.bounds.midY)) == nil)
    }

    private static func findHaloView(in view: NSView) -> IslandHaloLayerView? {
        if let halo = view as? IslandHaloLayerView { return halo }
        for subview in view.subviews {
            if let halo = findHaloView(in: subview) { return halo }
        }
        return nil
    }

    // MARK: Preview

    @Test func theSwiftUIPreviewRenders() {
        for state in [Self.breathing(), Self.flash(token: 3), Self.drift(), Self.steady(), .off] {
            let content = Color.black
                .frame(width: 120, height: 40)
                .islandHaloPreview(state, cornerRadius: 16)
                .padding(30)
            let renderer = ImageRenderer(content: content.environment(\.nookDrawsStill, true))
            renderer.scale = 2

            #expect(renderer.cgImage != nil, "\(state.motion)")
        }
    }

    @Test func theSwiftUIPreviewDrawsTheGlowPastTheViewAndNothingWhenOff() throws {
        func alphaOutsideThePill(_ state: IslandHaloState) throws -> Double {
            let content = Color.clear
                .frame(width: 100, height: 40)
                .islandHaloPreview(state, cornerRadius: 16)
                .padding(40)
            let renderer = ImageRenderer(content: content.environment(\.nookDrawsStill, true))
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            let rep = NSBitmapImageRep(cgImage: image)
            // Just below the view's bottom edge, centered.
            return try #require(rep.colorAt(x: rep.pixelsWide / 2, y: 40 + 40 + 6)).alphaComponent
        }

        let glowing = Self.steady(color: .approval, rest: 1, radius: 14)
        #expect(try alphaOutsideThePill(glowing) > 0.05)
        #expect(try alphaOutsideThePill(.off) == 0)
    }
}
