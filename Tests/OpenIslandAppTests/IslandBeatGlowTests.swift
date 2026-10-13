import AppKit
import QuartzCore
import Testing
@testable import OpenIslandApp

/// A "Dim flashing lights" setting a test sets by hand.
@MainActor
final class FakeFlashingLights: IslandFlashingLightsSetting {
    var dimsFlashingLights: Bool

    init(dims: Bool = false) {
        dimsFlashingLights = dims
    }
}

/// The glow's layers while it follows a song (D56). No window is shown: a
/// glow is made, handed frames, and read back.
@MainActor
@Suite struct IslandBeatGlowTests {
    private static let paneSize = CGSize(width: 160, height: 60)
    private static let hues = IslandBeatHues.fixed

    private static func pulseState(
        low: Double = 0.25,
        high: Double = 0.85,
        hues: [IslandHaloRGB] = IslandBeatGlowTests.hues,
        radius: CGFloat = 12,
        reach: Double = IslandBeatReach.standard
    ) -> IslandHaloState {
        IslandHaloState(
            source: .music, color: hues[0],
            motion: .pulse(IslandHaloPulse(low: low, high: high, hues: hues, reach: reach)),
            restOpacity: low, radius: radius, drop: 3
        )
    }

    private static let drift = IslandHaloState(
        source: .music, color: .running, motion: .drift(period: 8), restOpacity: 0.45, radius: 12, drop: 3
    )

    private static let waiting = IslandHaloState(
        source: .approval, color: .approval,
        motion: .breathing(period: 2, low: 0.5, high: 0.95), restOpacity: 0.95, radius: 12, drop: 3
    )

    /// A clock a test moves by hand.
    private final class Clock {
        var time = 10.0
    }

    /// A glow with a clock that moves a second with every look, far enough
    /// apart that every hit is one of its own, and with the system's
    /// setting off.
    private static func ready(_ glow: IslandBeatGlow) {
        var time = 0.0
        glow.now = {
            time += 1
            return time
        }
        glow.flashingLights = FakeFlashingLights()
    }

    private static func makeView() -> IslandHaloLayerView {
        let spread = IslandHaloLayerView.maxSpread
        let view = IslandHaloLayerView(
            frame: CGRect(x: 0, y: 0, width: paneSize.width + spread * 2, height: paneSize.height + spread * 2)
        )
        view.cornerRadius = 16
        view.layoutSubtreeIfNeeded()
        ready(view.beatGlow)
        return view
    }

    /// A glow of its own, pulsing, with room to grow. With a clock, the
    /// test says what time it is.
    private static func makeGlow(reach: Double = 0.5, clock: Clock? = nil, dims: Bool = false) -> IslandBeatGlow {
        let glow = IslandBeatGlow()
        ready(glow)
        if let clock { glow.now = { clock.time } }
        glow.flashingLights = FakeFlashingLights(dims: dims)
        glow.room = (side: 80, below: 80)
        glow.layout(
            frame: CGRect(x: 0, y: 0, width: 320, height: 220), pill: CGSize(width: 160, height: 60), path: nil
        )
        glow.begin(
            IslandHaloPulse(low: 0.25, high: 0.85, hues: hues, reach: reach), radius: 12, drop: 3, animated: false
        )
        return glow
    }

    private static func kick(_ strength: Double = 1) -> IslandBeatFrame {
        IslandBeatFrame(low: strength, mid: 0.2, high: 0.1, hit: .kick)
    }

    private static let snare = IslandBeatFrame(low: 0.3, mid: 1, high: 0.2, hit: .snare)

    private static func hat(_ high: Double = 1) -> IslandBeatFrame {
        IslandBeatFrame(low: 0, mid: 0, high: high, hit: .hat)
    }

    private static func near(_ value: Float, _ expected: Double) -> Bool {
        abs(Double(value) - expected) < 0.000_1
    }

    private static func isAtRest(_ glow: IslandBeatGlow) -> Bool {
        near(glow.container.opacity, 0.25) && CATransform3DIsIdentity(glow.container.transform)
    }

    private static func scaleFall(of glow: IslandBeatGlow) -> CABasicAnimation? {
        glow.container.animation(forKey: "beat.scale") as? CABasicAnimation
    }

    private static func glowFall(of glow: IslandBeatGlow) -> CABasicAnimation? {
        glow.container.animation(forKey: "beat.level") as? CABasicAnimation
    }

    private static func size(_ value: Any?) -> CGSize? {
        guard let transform = (value as? NSValue)?.caTransform3DValue else { return nil }
        return CGSize(width: transform.m11, height: transform.m22)
    }

    // MARK: Taking over from the resting glow

    @Test func aPulseRestsLowInItsFirstColorAndTheLiveLayerStepsAside() {
        let view = Self.makeView()
        view.apply(state: Self.pulseState())
        let glow = view.beatGlow

        #expect(glow.isActive)
        #expect(view.glowLayer.opacity == 0)
        #expect(Self.isAtRest(glow))
        #expect(glow.hueLayers.count == 4)
        #expect(glow.hueIndex == 0)
        #expect(glow.hueLayers.map(\.opacity) == [1, 0, 0, 0])
        #expect(glow.hueLayers.map(\.shadowColor) == Self.hues.map(\.cgColor))
        #expect(glow.punches == 0)
    }

    @Test func everyColorIsAFinishedPictureOnThePillsOutline() {
        let view = Self.makeView()
        view.apply(state: Self.pulseState(radius: 18))

        for layer in view.beatGlow.hueLayers {
            #expect(layer.shouldRasterize)
            #expect(layer.shadowRadius == 18)
            #expect(layer.shadowPath != nil)
            #expect(layer.shadowPath == view.glowLayer.shadowPath)
            #expect(layer.frame.size == view.bounds.size)
            #expect(layer.contents == nil)
        }
        #expect(view.beatGlow.container.frame == view.bounds)
    }

    @Test func theGlowNeverTakesAHitWhileItPulses() {
        let view = Self.makeView()
        view.apply(state: Self.pulseState())
        #expect(view.hitTest(CGPoint(x: view.bounds.midX, y: view.bounds.midY)) == nil)
    }

    // MARK: A low hit is a punch

    @Test func aLowHitIsOutAtOnceAndComesAllTheWayBack() throws {
        let glow = Self.makeGlow()

        glow.follow(Self.kick())

        // One animation, from the peak to the notch. The layer's own value
        // is the rest: when the fall is over nothing is left out.
        let reach = try #require(Self.scaleFall(of: glow))
        #expect(reach.keyPath == "transform")
        #expect(Self.size(reach.fromValue) == glow.peakScale)
        #expect(Self.size(reach.toValue) == CGSize(width: 1, height: 1))
        #expect(reach.duration == IslandBeatGlow.punchFall)
        #expect(CATransform3DIsIdentity(glow.container.transform))
        // Bright with it, and back with it.
        let bright = try #require(Self.glowFall(of: glow))
        #expect(bright.fromValue as? Float == 0.85)
        #expect(bright.toValue as? Float == 0.25)
        #expect(bright.duration == IslandBeatGlow.punchFall)
        #expect(Self.near(glow.container.opacity, 0.25))
        #expect(glow.punches == 1)
        #expect(glow.lastPunch == 1)
    }

    @Test func thePunchIsBackAtTheNotchWellInsideTwoHundredMilliseconds() {
        // The layer's fall times, pinned.
        #expect(IslandBeatGlow.punchFall == 0.14)
        #expect(IslandBeatGlow.flashFall == 0.12)
        #expect(IslandBeatGlow.punchFall < 0.2)
        // Two low hits 150 ms apart: the first is back before the second.
        #expect(IslandBeatGlow.punchFall < 0.15)
        #expect(IslandBeatGlow.shimmerFall < IslandBeatGlow.flashFall)
    }

    @Test func aHeldBassNoteIsOnePunchAndHoldsNothingOut() {
        // An 808 that starts and then holds for three seconds: one hit,
        // then level frames with the bass at its top, fifteen a second.
        let clock = Clock()
        let glow = Self.makeGlow(clock: clock)
        glow.follow(Self.kick())
        let punch = Self.scaleFall(of: glow)

        for step in 1...45 {
            clock.time = 10 + Double(step) / 15
            glow.follow(IslandBeatFrame(low: 1, mid: 0.4, high: 0.2, hit: nil))
        }

        #expect(glow.punches == 1)
        #expect(glow.hueIndex == 1)
        // Nothing but that one fall was ever asked for, and the layer's
        // own value never left the notch.
        #expect(Self.scaleFall(of: glow) === punch)
        #expect(Self.isAtRest(glow))
    }

    @Test func kicksAHundredFiftyMillisecondsApartAreSeparatePunches() throws {
        let clock = Clock()
        let glow = Self.makeGlow(clock: clock)
        var falls: [CABasicAnimation] = []

        for step in 0..<6 {
            clock.time = 10 + Double(step) * 0.15
            glow.follow(Self.kick())
            falls.append(try #require(Self.scaleFall(of: glow)))
        }

        #expect(glow.punches == 6)
        // Each one starts from its own peak and goes all the way back.
        for fall in falls {
            #expect(Self.size(fall.fromValue) == glow.peakScale)
            #expect(Self.size(fall.toValue) == CGSize(width: 1, height: 1))
        }
        #expect(Set(falls.map(ObjectIdentifier.init)).count == 6)
    }

    @Test func aHitsStrengthAndTheSliderSetHowFarItGoes() throws {
        let glow = Self.makeGlow()
        let peak = glow.peakScale

        glow.follow(Self.kick(0.5))
        let half = try #require(Self.size(Self.scaleFall(of: glow)?.fromValue))
        #expect(abs(half.width - (1 + (peak.width - 1) / 2)) < 0.000_1)
        #expect(abs(half.height - (1 + (peak.height - 1) / 2)) < 0.000_1)

        // The weakest hit that counts is still a hit you can see.
        glow.follow(Self.kick(0.05))
        #expect(glow.lastPunch == IslandBeatGlow.leastPunch)
        // A strength outside 0 to 1 is held inside.
        glow.follow(Self.kick(9))
        #expect(glow.lastPunch == 1)

        // The slider: the same hit goes further with a longer reach.
        let far = Self.makeGlow(reach: 1)
        far.follow(Self.kick())
        let near = Self.makeGlow(reach: 0)
        near.follow(Self.kick())
        let farPeak = try #require(Self.size(Self.scaleFall(of: far)?.fromValue))
        let nearPeak = try #require(Self.size(Self.scaleFall(of: near)?.fromValue))
        #expect(farPeak.width > half.width)
        #expect(nearPeak.width < farPeak.width)
        #expect(nearPeak.width > 1)
    }

    // MARK: One color per low hit

    @Test func consecutiveLowHitsGetDifferentColors() {
        let glow = Self.makeGlow()
        var seen: [Int] = [glow.hueIndex]

        for _ in 0..<8 {
            glow.follow(Self.kick())
            #expect(glow.hueIndex != seen.last)
            seen.append(glow.hueIndex)
        }

        #expect(seen == [0, 1, 2, 3, 0, 1, 2, 3, 0])
        #expect(glow.hueLayers.map(\.opacity) == [1, 0, 0, 0])
    }

    @Test func aClapDuringAPunchFlashesAndKeepsTheColor() throws {
        let clock = Clock()
        let glow = Self.makeGlow(clock: clock)
        glow.follow(Self.kick())
        let punch = try #require(Self.scaleFall(of: glow))
        #expect(glow.hueIndex == 1)

        // 80 ms later, with the punch still on its way back.
        clock.time += 0.08
        glow.follow(Self.snare)

        #expect(glow.hueIndex == 1)
        #expect(glow.flashes == 1)
        // Brightness is at its peak again, with the flash's own fall.
        let bright = try #require(Self.glowFall(of: glow))
        #expect(bright.fromValue as? Float == 0.85)
        #expect(bright.duration == IslandBeatGlow.flashFall)
        // The punch's trip back goes on untouched.
        #expect(Self.scaleFall(of: glow) === punch)
    }

    @Test func aClapAloneFlashesAndStepsTheColor() throws {
        let glow = Self.makeGlow()

        glow.follow(Self.snare)

        #expect(glow.hueIndex == 1)
        #expect(glow.hueLayers.map(\.opacity) == [0, 1, 0, 0])
        #expect(glow.flashes == 1)
        let bright = try #require(Self.glowFall(of: glow))
        #expect(bright.fromValue as? Float == 0.85)
        #expect(bright.toValue as? Float == 0.25)
        #expect(bright.duration == IslandBeatGlow.flashFall)
        // A flash is brightness: nothing reaches out.
        #expect(Self.scaleFall(of: glow) == nil)
        #expect(CATransform3DIsIdentity(glow.container.transform))
        #expect(glow.punches == 0)
    }

    @Test func aClapAfterThePunchIsBackStepsTheColorAgain() {
        let clock = Clock()
        let glow = Self.makeGlow(clock: clock)
        glow.follow(Self.kick())

        clock.time += IslandBeatGlow.punchFall + 0.01
        glow.follow(Self.snare)

        #expect(glow.hueIndex == 2)
    }

    @Test func aLowHitRightAfterAClapStillTakesItsOwnColor() {
        let clock = Clock()
        let glow = Self.makeGlow(clock: clock)
        glow.follow(Self.snare)

        clock.time += 0.1
        glow.follow(Self.kick())

        #expect(glow.hueIndex == 2)
        #expect(glow.punches == 1)
    }

    // MARK: Hats, and nothing

    @Test func aHatIsASmallFlickerAtTheNotch() throws {
        let glow = Self.makeGlow()

        glow.follow(Self.hat(1))

        let flicker = try #require(Self.glowFall(of: glow))
        let lift = Double(IslandBeatLimits.shimmerCeiling) * (0.85 - 0.25)
        #expect(Self.near(try #require(flicker.fromValue as? Float), 0.25 + lift))
        #expect(flicker.toValue as? Float == 0.25)
        #expect(flicker.duration == IslandBeatGlow.shimmerFall)
        #expect(IslandBeatLimits.shimmerCeiling == 0.15)
        // No color, no reach.
        #expect(glow.hueIndex == 0)
        #expect(Self.scaleFall(of: glow) == nil)
        #expect(glow.flickers == 1)
        // A quiet hat is a smaller one, and never under half the ceiling.
        let quiet = Self.makeGlow()
        quiet.follow(Self.hat(0.1))
        let small = try #require(Self.glowFall(of: quiet)?.fromValue as? Float)
        #expect(Self.near(small, 0.25 + lift / 2))
    }

    @Test func hatsAloneNeverExceedTheShimmersCeiling() throws {
        let glow = Self.makeGlow()
        let most = Float(0.25 + Double(IslandBeatLimits.shimmerCeiling) * (0.85 - 0.25)) + 0.000_1

        for _ in 0..<400 {
            glow.follow(Self.hat(1))
            #expect(try #require(Self.glowFall(of: glow)?.fromValue as? Float) <= most)
            #expect(Self.near(glow.container.opacity, 0.25))
            #expect(CATransform3DIsIdentity(glow.container.transform))
            #expect(glow.hueIndex == 0)
        }
        #expect(glow.punches == 0)
        #expect(glow.flashes == 0)
    }

    @Test func aHatDoesNotCutAPunchOrAFlashShort() {
        let clock = Clock()
        let glow = Self.makeGlow(clock: clock)
        glow.follow(Self.kick())
        let bright = Self.glowFall(of: glow)

        clock.time += 0.05
        glow.follow(Self.hat())

        #expect(glow.flickers == 0)
        #expect(Self.glowFall(of: glow) === bright)
        // When the punch is back, the next hat flickers.
        clock.time += 0.2
        glow.follow(Self.hat())
        #expect(glow.flickers == 1)
    }

    @Test func levelsAloneMoveNothing() {
        let glow = Self.makeGlow()
        var generator = SystemRandomNumberGenerator()

        for _ in 0..<500 {
            glow.follow(IslandBeatFrame(
                low: Double.random(in: -1...2, using: &generator),
                mid: Double.random(in: 0...1, using: &generator),
                high: Double.random(in: 0...1, using: &generator),
                hit: nil
            ))
        }

        #expect(Self.isAtRest(glow))
        #expect(Self.scaleFall(of: glow) == nil)
        #expect(Self.glowFall(of: glow) == nil)
        #expect(glow.hueIndex == 0)
    }

    // MARK: How far out

    @Test func theReachSetsHowFarThePeakGoes() {
        // The pane is 160 by 60, and the glow's radius is 12.
        func peak(reach: Double) -> CGSize {
            let view = Self.makeView()
            view.apply(state: Self.pulseState(reach: reach))
            return view.beatGlow.peakScale
        }
        let least = peak(reach: 0)
        let standard = peak(reach: IslandBeatReach.standard)
        let most = peak(reach: 1)

        // Each side's scale puts the glow's edge the same distance out.
        #expect(abs(standard.width - (80 + 1.4 * 12) / (80 + 12)) < 0.000_1)
        #expect(abs(standard.height - (30 + 1.4 * 12) / (30 + 12)) < 0.000_1)
        #expect(abs(most.width - (80 + 2.2 * 12) / (80 + 12)) < 0.000_1)
        #expect(abs(most.height - (30 + 2.2 * 12) / (30 + 12)) < 0.000_1)
        // At the least it barely grows.
        #expect(least.width > 1 && least.width < 1.01)
        #expect(least.height > 1 && least.height < 1.02)
        #expect(least.width < standard.width && standard.width < most.width)
    }

    @Test func aNewReachMovesNoBlurAndKeepsTheColor() {
        let view = Self.makeView()
        view.apply(state: Self.pulseState(reach: 0.2))
        view.applyBeat(Self.kick())
        let glow = view.beatGlow
        let radii = glow.hueLayers.map(\.shadowRadius)
        let before = glow.peakScale

        view.apply(state: Self.pulseState(reach: 0.9))

        #expect(glow.peakScale.width > before.width)
        #expect(glow.hueLayers.map(\.shadowRadius) == radii)
        #expect(glow.hueIndex == 1)
        #expect(Self.isAtRest(glow))
    }

    @Test func aGlowWithNoRoomBrightensAndDoesNotGrow() throws {
        let glow = Self.makeGlow(reach: 1)
        glow.room = (side: 0, below: 0)

        glow.follow(Self.kick())

        #expect(glow.peakScale == CGSize(width: 1, height: 1))
        #expect(Self.size(Self.scaleFall(of: glow)?.fromValue) == CGSize(width: 1, height: 1))
        #expect(try #require(Self.glowFall(of: glow)).fromValue as? Float == 0.85)
        // Room that comes back is used again.
        glow.room = (side: 80, below: 80)
        #expect(glow.peakScale.width > 1)
    }

    // MARK: How often it flashes

    /// Feeds a glow one kind of hit every `gap` seconds and gives back the
    /// times at which it was shown.
    private static func shown(_ frame: IslandBeatFrame, gap: Double, seconds: Double, dims: Bool) -> [Double] {
        let clock = Clock()
        let glow = makeGlow(clock: clock, dims: dims)
        var times: [Double] = []
        for step in 0..<Int((seconds / gap).rounded()) {
            clock.time = 100 + Double(step) * gap
            let before = glow.punches + glow.flashes
            glow.follow(frame)
            if glow.punches + glow.flashes != before { times.append(clock.time) }
        }
        return times
    }

    /// The most that fall inside any one second. The second is a hair
    /// short, which keeps a time that is one whole second later, give or
    /// take a rounding error, out of it.
    private static func mostInASecond(_ times: [Double]) -> Int {
        times.map { start in times.filter { $0 >= start && $0 < start + 1 - 0.000_001 }.count }.max() ?? 0
    }

    @Test func aRollOfHitsATenthOfASecondApartIsShownHitForHit() {
        // The owner's rule: the light follows the hits.
        for frame in [Self.snare, Self.kick()] {
            let times = Self.shown(frame, gap: 0.1, seconds: 4, dims: false)
            #expect(times.count == 40)
            #expect(Self.mostInASecond(times) == 10)
        }
    }

    @Test func hitsCloserThanTheGapSmearIntoOne() {
        // A frame every 10 ms: one hit every 70 ms and no more.
        let times = Self.shown(Self.snare, gap: 0.01, seconds: 3, dims: false)
        let gaps = zip(times.dropFirst(), times).map { $0 - $1 }

        #expect(gaps.allSatisfy { $0 >= IslandBeatLimits.flashGap - 0.000_001 })
        #expect(Self.mostInASecond(times) <= 15)
        #expect(IslandBeatLimits.flashGap == 0.07)
    }

    @Test func withDimFlashingLightsOnNoSecondHoldsMoreThanThree() {
        for frame in [Self.snare, Self.kick()] {
            for gap in [0.1, 0.05, 0.01, 1.0 / 120, 0.15, 0.26, 0.34] {
                let times = Self.shown(frame, gap: gap, seconds: 6, dims: true)
                #expect(!times.isEmpty)
                #expect(Self.mostInASecond(times) <= 3, "a hit every \(gap) s")
                let gaps = zip(times.dropFirst(), times).map { $0 - $1 }
                #expect(gaps.allSatisfy { $0 >= IslandBeatLimits.dimmedFlashGap - 0.000_001 })
            }
        }
        #expect(IslandBeatLimits.dimmedFlashesPerSecond == 3)
    }

    @Test func punchesAndFlashesShareTheOneLimit() {
        // Kicks and claps turn about, every 100 ms, with the setting on.
        let clock = Clock()
        let glow = Self.makeGlow(clock: clock, dims: true)
        var times: [Double] = []
        for step in 0..<50 {
            clock.time = 100 + Double(step) * 0.1
            let before = glow.punches + glow.flashes
            glow.follow(step.isMultiple(of: 2) ? Self.kick() : Self.snare)
            if glow.punches + glow.flashes != before { times.append(clock.time) }
        }

        #expect(Self.mostInASecond(times) <= 3)
    }

    @Test func theSettingIsReadForEveryHit() {
        let clock = Clock()
        let glow = Self.makeGlow(clock: clock)
        let setting = FakeFlashingLights()
        glow.flashingLights = setting

        // Off: four punches in 0.3 s.
        for _ in 0..<4 {
            glow.follow(Self.kick())
            clock.time += 0.1
        }
        #expect(glow.punches == 4)
        // Switched on in System Settings while the song plays: the very
        // next hit is turned away, with four already in the last second.
        setting.dimsFlashingLights = true
        glow.follow(Self.kick())
        #expect(glow.punches == 4)
        #expect(glow.hueIndex == 0)
        clock.time += 1
        glow.follow(Self.kick())
        #expect(glow.punches == 5)
    }

    @Test func aHitThatIsTurnedAwayShowsNothingAndChangesNoColor() {
        let clock = Clock()
        let glow = Self.makeGlow(clock: clock)
        glow.follow(Self.kick())
        let punch = Self.scaleFall(of: glow)

        // A second low hit 40 ms after the first, inside the gap.
        clock.time += 0.04
        glow.follow(Self.kick())

        #expect(glow.punches == 1)
        #expect(glow.hueIndex == 1)
        #expect(Self.scaleFall(of: glow) === punch)
    }

    @Test func aClockThatJumpsBackDoesNotLockTheGlowOut() {
        let clock = Clock()
        let glow = Self.makeGlow(clock: clock, dims: true)
        clock.time = 1_000
        glow.follow(Self.kick())
        clock.time = 3
        glow.follow(Self.kick())
        glow.follow(Self.hat())

        #expect(glow.punches == 2)
        #expect(glow.hueIndex == 2)
    }

    // MARK: Colors

    @Test func aColorGivesWayByFadingAndNeverByCutting() throws {
        let glow = Self.makeGlow()

        glow.follow(Self.kick())

        let out = try #require(glow.hueLayers[0].animation(forKey: "beat.hue") as? CABasicAnimation)
        let into = try #require(glow.hueLayers[1].animation(forKey: "beat.hue") as? CABasicAnimation)
        #expect(out.duration == IslandBeatGlow.hueCrossfade)
        #expect(into.duration == IslandBeatGlow.hueCrossfade)
        #expect(out.toValue as? Float == 0)
        #expect(into.toValue as? Float == 1)
        // A fade is over before the next hit may come.
        #expect(IslandBeatGlow.hueCrossfade < IslandBeatLimits.flashGap)
        // No picture is drawn again for a hit: the color of a layer stays.
        #expect(glow.hueLayers.map(\.shadowColor) == Self.hues.map(\.cgColor))
        #expect(glow.hueLayers.allSatisfy { $0.animation(forKey: "beat.color") == nil })
    }

    // MARK: States around the pulse

    @Test func applyingTheSamePulseAgainRestartsNothing() {
        let view = Self.makeView()
        let state = Self.pulseState()
        view.apply(state: state)
        view.applyBeat(Self.kick())
        let punch = Self.scaleFall(of: view.beatGlow)

        view.apply(state: state)
        view.apply(state: Self.pulseState())

        #expect(Self.scaleFall(of: view.beatGlow) === punch)
        #expect(view.beatGlow.punches == 1)
        #expect(view.beatGlow.hueIndex == 1)
    }

    @Test func aNewTrackChangesTheColorsAndKeepsThePulseGoing() throws {
        let view = Self.makeView()
        view.apply(state: Self.pulseState())
        view.applyBeat(Self.kick())
        let glow = view.beatGlow
        let next = IslandBeatHues.hues(around: IslandHaloRGB.rgb255(10, 200, 30))

        view.apply(state: Self.pulseState(hues: next))

        #expect(glow.isActive)
        #expect(glow.hueIndex == 1)
        #expect(glow.hueLayers.map(\.shadowColor) == next.map(\.cgColor))
        // The color on screen fades to its new one. The hidden ones just take theirs.
        let shown = try #require(glow.hueLayers[1].animation(forKey: "beat.color") as? CABasicAnimation)
        #expect(shown.duration == Motion.Halo.colorCrossfade)
        #expect(glow.hueLayers[0].animation(forKey: "beat.color") == nil)
    }

    @Test func framesAreIgnoredWhileTheGlowShowsSomethingElse() {
        for state in [Self.drift, Self.waiting, IslandHaloState.off] {
            let view = Self.makeView()
            view.apply(state: state)

            view.applyBeat(Self.kick())

            #expect(!view.beatGlow.isActive)
            #expect(view.beatGlow.container.opacity == 0)
            #expect(view.beatGlow.hueIndex == 0)
            #expect(view.beatGlow.punches == 0)
        }
    }

    @Test func anAgentThatWaitsTakesTheGlowBackFromThePulse() {
        let view = Self.makeView()
        view.apply(state: Self.pulseState())
        view.applyBeat(Self.kick())

        view.apply(state: Self.waiting)

        #expect(!view.beatGlow.isActive)
        #expect(view.beatGlow.container.opacity == 0)
        #expect(view.glowLayer.opacity > 0)
        // A frame still on its way moves nothing.
        view.applyBeat(Self.kick())
        #expect(view.beatGlow.container.opacity == 0)
        #expect(view.beatGlow.punches == 1)
    }

    @Test func leavingThePulseForTodaysGlowFadesItOutAndBringsTheLoopBack() throws {
        let view = Self.makeView()
        view.apply(state: Self.pulseState())

        view.apply(state: Self.drift)

        #expect(!view.beatGlow.isActive)
        #expect(view.beatGlow.container.opacity == 0)
        let fade = try #require(Self.glowFall(of: view.beatGlow))
        #expect(fade.duration == Motion.Halo.fade)
        #expect(view.glowLayer.animation(forKey: "halo.opacity") != nil)
        #expect(Self.near(view.glowLayer.opacity, 0.45))
    }

    @Test func aPulseStartsAgainFromItsFirstColorAndItsRest() {
        let view = Self.makeView()
        view.apply(state: Self.pulseState())
        view.applyBeat(Self.kick())
        view.apply(state: Self.drift)

        view.apply(state: Self.pulseState())

        #expect(view.beatGlow.hueIndex == 0)
        #expect(view.beatGlow.hueLayers.map(\.opacity) == [1, 0, 0, 0])
        #expect(Self.isAtRest(view.beatGlow))
    }

    // MARK: The feed

    @Test func theFeedReachesTheLayerWithNoViewInBetween() {
        let view = Self.makeView()
        let feed = IslandBeatFeed()
        view.beatFeed = feed
        view.apply(state: Self.pulseState(low: 0.25, high: 0.85))

        feed.onFrame?(Self.kick())

        #expect(view.beatGlow.punches == 1)
        #expect(view.beatGlow.hueIndex == 1)
    }

    @Test func aViewWithNoFeedNeverPulsesByItself() {
        let view = Self.makeView()
        #expect(view.beatFeed == nil)
        view.apply(state: Self.pulseState())
        #expect(Self.isAtRest(view.beatGlow))
        #expect(view.beatGlow.punches == 0)
    }

    @Test func aFeedOutlivesItsViewWithoutHoldingIt() {
        let feed = IslandBeatFeed()
        weak var gone: IslandHaloLayerView?
        autoreleasepool {
            let view = Self.makeView()
            view.beatFeed = feed
            gone = view
        }

        #expect(gone == nil)
        feed.onFrame?(Self.kick())
    }
}
