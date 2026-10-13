import AppKit
import QuartzCore
import Testing
@testable import OpenIslandApp

/// The Show mode of the lasers (D56) past the director: a picture as
/// beams, what the layer does with a scene, the stage that runs it, and
/// the saved choice. No window is shown: the stage draws on a fake.
@MainActor
@Suite struct IslandLaserShowTests {
    /// A 14 inch MacBook's screen, and its closed island at the top middle.
    private static let screen = CGRect(x: 0, y: 0, width: 1_512, height: 982)
    private static let pill = CGRect(x: 619, y: 950, width: 274, height: 32)
    private static let space = IslandLaserSpace(pill: pill, screen: screen)
    private static let length = IslandLaserWindowPlan.beamLength(
        reach: IslandLaserReach.standard, pill: pill, screen: screen
    )
    private static let hues = IslandBeatHues.fixed
    private static let seed = IslandLaserSeed.seed(title: "Sky", artist: "Playboi Carti", tint: nil)

    private static func scene(
        _ kind: IslandLaserLook.Kind,
        _ arrangement: IslandLaserArrangement = .fan,
        base: Int = 0,
        accent: Int = 1,
        lit: Int = 0,
        count: Int = 16
    ) -> IslandLaserScene {
        IslandLaserScene(
            picture: IslandLaserPicture(
                look: IslandLaserLook(kind: kind, arrangement: arrangement), base: base, accent: accent, litGroup: lit
            ),
            hues: hues, count: count, space: space, reach: IslandLaserReach.standard, fullLength: length
        )
    }

    private static func makeLayer() -> IslandLaserLayer {
        let layer = IslandLaserLayer()
        layer.container.frame = screen
        layer.setContentsScale(2)
        layer.layout(notch: pill, length: length)
        return layer
    }

    // MARK: A picture as beams

    @Test func aStillLookIsEveryBeamOnInTwoColorsWithRoomForAPush() {
        for count in [8, 16, 24] {
            let scene = Self.scene(.still, count: count)
            let stands = IslandLaserArrangement.fan.lineup(count: count, space: Self.space, reach: 0.25).stands
            #expect(scene.beams.count == count)
            #expect(scene.motion == .still)
            #expect(scene.haze == Self.hues[0])
            for (index, beam) in scene.beams.enumerated() {
                #expect(beam.brightness == 1)
                // No sway: the beams stand exactly where the shape says.
                #expect(beam.lean == stands[index].lean * Double.pi / 180)
                #expect(beam.start == stands[index].start)
                // Short of full by what a low hit pushes it out.
                let full = Self.length * stands[index].share
                #expect(abs(beam.length * (1 + IslandLaserShow.pushLength) - full) < 0.001)
                // The outer quarter on each side is the accent.
                let isOuter = min(index, count - 1 - index) < count / 4
                #expect(beam.color == Self.hues[isOuter ? 1 : 0])
            }
            #expect(Set(scene.beams.map(\.color)).count == 2)
        }
    }

    @Test func theOddEvenIsOneColorForEachGroupAndOneGroupLit() {
        let first = Self.scene(.oddEven, lit: 0)
        let second = Self.scene(.oddEven, lit: 1)
        for index in 0..<16 {
            let color = Self.hues[index.isMultiple(of: 2) ? 0 : 1]
            #expect(first.beams[index].color == color)
            #expect(second.beams[index].color == color)
            #expect(first.beams[index].brightness == (index.isMultiple(of: 2) ? 1 : IslandLaserScene.dimGroup))
            #expect(second.beams[index].brightness == (index.isMultiple(of: 2) ? IslandLaserScene.dimGroup : 1))
        }
        // A snare changes the two colors over, and nothing else.
        let swapped = Self.scene(.oddEven, base: 1, accent: 0)
        #expect(swapped.beams.map(\.length) == first.beams.map(\.length))
        #expect(swapped.beams[0].color == Self.hues[1] && swapped.beams[1].color == Self.hues[0])
    }

    @Test func theQuietLooksAreOneColorAndMoveByThemselves() {
        let wave = Self.scene(.wave)
        #expect(wave.motion == .wave(depth: 0.5, period: 4))
        #expect(Set(wave.beams.map(\.color)) == [Self.hues[0]])
        #expect(wave.beams.allSatisfy { $0.brightness == IslandLaserScene.waveBrightness })
        // At rest six tenths of the length, moving three tenths up and down.
        let stands = IslandLaserArrangement.fan.lineup(count: 16, space: Self.space, reach: 0.25).stands
        #expect(abs(wave.beams[7].length - Self.length * stands[7].share * 0.6) < 0.001)

        let breath = Self.scene(.breathe)
        #expect(breath.motion == .breathe(narrow: 40.0 / 128, period: 4))
        #expect(Set(breath.beams.map(\.color)) == [Self.hues[0]])
        #expect(breath.beams.allSatisfy { $0.brightness == 1 })
    }

    @Test func aLookCanFaceTheViewerAndTheBurstIsWhiteAndFull() {
        let forward = Self.scene(.still, IslandLaserArrangement.fan.forward)
        #expect(forward.tilt == IslandLaserTilt.standard)
        #expect(forward.eye == IslandLaserTilt.eyeDistance(fullLength: Self.length, tilt: forward.tilt))
        #expect(Self.scene(.still).tilt == 0)
        #expect(Self.scene(.still, .curtain).beams.allSatisfy { $0.lean == 0 })

        let burst = forward.burst
        let stands = IslandLaserArrangement.fan.lineup(count: 16, space: Self.space, reach: 0.25).stands
        #expect(burst.motion == .still)
        #expect(burst.tilt == forward.tilt)
        for (index, beam) in burst.beams.enumerated() {
            #expect(beam.color == IslandLaserScene.white)
            #expect(beam.brightness == 1)
            #expect(abs(beam.length - Self.length * stands[index].share) < 0.001)
        }
        // From the middle pair outward.
        #expect(IslandLaserScene.ranks(count: 8) == [3, 2, 1, 0, 0, 1, 2, 3])
        #expect(IslandLaserScene.ranks(count: 16).max() == 7)
    }

    // MARK: The layer

    @Test func aSceneIsOnAtOnceInEachBeamsOwnColor() throws {
        let layer = Self.makeLayer()
        let scene = Self.scene(.still)
        layer.show(scene)

        #expect(layer.scene == scene)
        #expect(layer.fan == nil)
        #expect(layer.container.opacity == IslandLaserLayer.showRest)
        #expect(layer.shownBeamCount == 16)
        for (index, beam) in scene.beams.enumerated() {
            #expect(abs(layer.lean(ofBeam: index) - beam.lean) < 0.000_1)
            #expect(abs(layer.length(ofBeam: index) - beam.length) < 0.01)
            #expect(layer.beams[index].holder.animationKeys() == nil)
            #expect(layer.beams[index].stem.animationKeys() == nil)
        }
        // Two colors on the beams at once.
        let outer = try #require(layer.coreColor(ofBeam: 0)?.components)
        let inner = try #require(layer.coreColor(ofBeam: 7)?.components)
        #expect(outer != inner)
        #expect(layer.coreColor(ofBeam: 0)?.components == layer.coreColor(ofBeam: 15)?.components)
    }

    @Test func aLowHitPushesEveryLitBeamOutAndBack() throws {
        let layer = Self.makeLayer()
        let scene = Self.scene(.still)
        layer.show(scene)
        layer.push(scene, by: IslandLaserShow.pushLength, over: IslandLaserShow.pushFall)

        for index in 0..<16 {
            let push = try #require(layer.lengthFall(ofBeam: index))
            #expect(push.duration == IslandLaserShow.pushFall)
            let from = try #require((push.fromValue as? NSValue)?.caTransform3DValue).m22
            let to = try #require((push.toValue as? NSValue)?.caTransform3DValue).m22
            #expect(abs(from / to - CGFloat(1 + IslandLaserShow.pushLength)) < 0.001)
            // The beam's own length is what is left when it is over.
            #expect(abs(layer.length(ofBeam: index) - scene.beams[index].length) < 0.01)
        }
        let lift = try #require(layer.lift)
        #expect(lift.fromValue as? Float == 1)
        #expect(lift.toValue as? Float == IslandLaserLayer.showRest)
        // No color moved.
        #expect(layer.colorFlash(ofBeam: 0) == nil)

        // The Odd Even's other group: the scene is cut to, and only the
        // group that is lit is pushed.
        let other = Self.scene(.oddEven, lit: 1)
        layer.push(other, by: IslandLaserShow.pushLength, over: IslandLaserShow.pushFall)
        #expect(layer.scene == other)
        #expect(layer.lengthFall(ofBeam: 0) == nil)
        #expect(layer.lengthFall(ofBeam: 1) != nil)
        #expect(layer.beams[0].holder.opacity == Float(IslandLaserScene.dimGroup))
    }

    @Test func aSnareFlashesEveryBeamWhiteAndLeavesTheSwappedColors() throws {
        let layer = Self.makeLayer()
        layer.show(Self.scene(.oddEven))
        let before = try #require(layer.coreColor(ofBeam: 0)?.components)

        layer.flashWhite(into: Self.scene(.oddEven, base: 1, accent: 0), over: IslandLaserShow.flashFall)

        for index in 0..<16 {
            let flash = try #require(layer.colorFlash(ofBeam: index))
            #expect(flash.duration == IslandLaserShow.flashFall)
            let from = try #require(flash.fromValue as? [CGColor])
            // White the whole way along the beam.
            #expect(from.allSatisfy { ($0.components ?? []).prefix(3).allSatisfy { $0 == 1 } })
        }
        // What is left is the other group's color.
        #expect(layer.coreColor(ofBeam: 0)?.components != before)
        #expect(layer.coreColor(ofBeam: 1)?.components == before)
        #expect(layer.lift?.fromValue as? Float == 1)
    }

    @Test func aQuietLookMovesOnceAndIsStillAgain() throws {
        let layer = Self.makeLayer()
        layer.show(Self.scene(.wave))
        var firsts: Set<Double> = []
        for index in 0..<16 {
            let wave = try #require(layer.wave(ofBeam: index))
            #expect(wave.duration == 4)
            // Once through and no more: an endless animation is composed
            // for every frame it is up (D60).
            #expect(wave.repeatCount == 0)
            #expect(wave.repeatDuration == 0)
            #expect(wave.preferredFrameRateRange == Motion.Halo.slowFrameRateRange)
            let values = try #require(wave.values as? [Double])
            // One whole turn: it ends where it began, and every beam is
            // at another place in it.
            #expect(abs((values.first ?? 0) - (values.last ?? 1)) < 0.000_1)
            #expect((values.max() ?? 0) > (values.min() ?? 0) * 1.5)
            firsts.insert(((values.first ?? 0) * 10_000).rounded())
        }
        #expect(firsts.count > 8)

        layer.show(Self.scene(.breathe))
        #expect(layer.wave(ofBeam: 0) == nil)
        let breath = try #require(layer.breath(ofBeam: 0))
        #expect(breath.autoreverses)
        #expect(breath.duration == 2)
        #expect(breath.repeatCount == 0)
        #expect(breath.preferredFrameRateRange == Motion.Halo.slowFrameRateRange)
        let wide = IslandLaserLayer.tilt(of: CATransform3DIdentity)
        #expect(wide == 0)
        let from = try #require((breath.fromValue as? NSValue)?.caTransform3DValue)
        let to = try #require((breath.toValue as? NSValue)?.caTransform3DValue)
        // From its own lean in to 40 degrees of the fan's 128.
        #expect(abs(atan2(to.m12, to.m11) / atan2(from.m12, from.m11) - 40.0 / 128) < 0.001)

        // A hit in a quiet look brightens it and leaves the motion alone.
        layer.push(Self.scene(.breathe), by: IslandLaserShow.pushLength, over: 0.14)
        #expect(layer.breath(ofBeam: 0) === breath)
        #expect(layer.lift != nil)

        // Stirred, it makes its one move again, and nothing else changes.
        let starts = layer.animationStarts
        layer.stir(Self.scene(.breathe))
        let again = try #require(layer.breath(ofBeam: 0))
        #expect(again !== breath)
        #expect(again.repeatCount == 0)
        #expect(layer.animationStarts == starts + 1)
        #expect(layer.scene == Self.scene(.breathe))
        // A still look has nothing to stir.
        layer.show(Self.scene(.still))
        layer.stir(Self.scene(.still))
        #expect(layer.breath(ofBeam: 0) == nil && layer.wave(ofBeam: 0) == nil)
    }

    @Test func everyMoveOfTheLasersNamesItsFrameRate() throws {
        let layer = Self.makeLayer()
        let hit = Motion.Halo.hitFrameRateRange
        #expect(hit.maximum == 60 && hit.preferred == 60)
        #expect(Motion.Halo.slowFrameRateRange.maximum == 30)

        // A show's push, lift, white flash and burst.
        let scene = Self.scene(.still)
        layer.show(scene)
        layer.push(scene, by: IslandLaserShow.pushLength, over: IslandLaserShow.pushFall)
        #expect(layer.lengthFall(ofBeam: 0)?.preferredFrameRateRange == hit)
        #expect(layer.lift?.preferredFrameRateRange == hit)
        layer.flashWhite(into: scene, over: IslandLaserShow.flashFall)
        #expect(layer.colorFlash(ofBeam: 0)?.preferredFrameRateRange == hit)
        layer.burst(scene.burst, spread: 0.08, hold: 0.4, fall: 0.14)
        #expect(layer.burstLength(ofBeam: 0)?.preferredFrameRateRange == hit)

        // Reactive's shot, its haze and the lunge.
        let fan = IslandLaserFan(
            frame: IslandBeatFrame(low: 1, hit: .kick), reach: 0.25, tint: nil,
            lineup: IslandLaserArrangement.fan.forward.lineup(count: 16, space: Self.space, reach: 0.25),
            hueIndex: 0, time: 0, fullLength: Self.length
        )
        layer.shoot(fan, over: IslandBeatGlow.punchFall, lunge: IslandLaserTilt.lunge)
        #expect(layer.lengthFall(ofBeam: 0)?.preferredFrameRateRange == hit)
        #expect(layer.tiltFall?.preferredFrameRateRange == hit)
        #expect(layer.hazeFall?.preferredFrameRateRange == hit)
    }

    @Test func darknessStopsEverythingAndTheBurstLightsFromTheMiddleOut() throws {
        let layer = Self.makeLayer()
        layer.show(Self.scene(.wave))
        layer.blackOut(over: 0)
        #expect(layer.container.opacity == 0)
        #expect(layer.scene == nil)
        #expect(layer.wave(ofBeam: 3) == nil)

        let burst = Self.scene(.still).burst
        layer.burst(
            burst, spread: IslandLaserShow.burstSpread, hold: IslandLaserShow.burstHold,
            fall: IslandLaserShow.burstFall
        )
        #expect(layer.container.opacity == 1)
        let middle = try #require(layer.burstLength(ofBeam: 7))
        let outer = try #require(layer.burstLength(ofBeam: 0))
        #expect(middle.duration == IslandLaserShow.burstLength)
        let middleTimes = try #require(middle.keyTimes?.map(\.doubleValue))
        let outerTimes = try #require(outer.keyTimes?.map(\.doubleValue))
        // The middle pair is lit first and comes back last.
        #expect(middleTimes[1] == 0)
        #expect(abs(outerTimes[1] * IslandLaserShow.burstLength - IslandLaserShow.burstSpread) < 0.000_1)
        #expect(outerTimes[3] < middleTimes[3])
        #expect(abs((middleTimes[4] - middleTimes[3]) * IslandLaserShow.burstLength - IslandLaserShow.burstFall) < 0.000_1)
        // White, and nothing left on when it is over.
        #expect(layer.coreColor(ofBeam: 4)?.components?.prefix(3).allSatisfy { $0 == 1 } == true)
        #expect(layer.shownBeamCount == 0)
        #expect(layer.length(ofBeam: 7) < 1)
    }

    @Test func afterAShowAFanPaintsEveryBeamAgain() throws {
        let layer = Self.makeLayer()
        layer.show(Self.scene(.oddEven))
        let fan = IslandLaserFan(
            frame: IslandBeatFrame(low: 1, hit: .kick), reach: 0.25, tint: nil,
            lineup: IslandLaserArrangement.fan.lineup(count: 16, space: Self.space, reach: 0.25),
            hueIndex: 2, time: 0, fullLength: Self.length
        )
        layer.shoot(fan, over: 0.14)
        #expect(layer.scene == nil)
        let colors = Set((0..<16).compactMap { layer.coreColor(ofBeam: $0)?.components })
        #expect(colors.count == 1)

        // And a show after that paints each beam its own color again.
        layer.show(Self.scene(.oddEven))
        #expect(layer.coreColor(ofBeam: 0)?.components != layer.coreColor(ofBeam: 1)?.components)
    }

    // MARK: The stage

    @MainActor
    private final class Rig {
        let stage = IslandLaserStage()
        var surfaces: [FakeLaserSurface] = []
        var time = 10.0

        init() {
            stage.makeSurface = { [unowned self] in
                let surface = FakeLaserSurface()
                self.surfaces.append(surface)
                return surface
            }
            stage.now = { [unowned self] in self.time }
            stage.flashingLights = FakeFlashingLights()
            stage.isDemo = { false }
        }

        func show(_ pulse: IslandHaloPulse?) {
            stage.update(
                pulse: pulse, pill: IslandLaserShowTests.pill, screen: IslandLaserShowTests.screen,
                contentsScale: 2, islandWindowNumber: 41
            )
        }
    }

    private static func pulse(mode: IslandLaserMode, seed: UInt64 = IslandLaserShowTests.seed) -> IslandHaloPulse {
        IslandHaloPulse(
            low: 0.25, high: 0.85, hues: IslandBeatHues.fixed, look: .lasers, laserMode: mode,
            laserSeed: mode == .show ? seed : 0, tint: nil
        )
    }

    @Test func aShowStartsDarkAndTheFirstSoundBringsItsFirstLook() throws {
        let rig = Rig()
        rig.show(Self.pulse(mode: .show))
        #expect(rig.stage.isShowing)
        #expect(rig.stage.director?.program == IslandLaserProgram(seed: Self.seed))
        #expect(rig.stage.picture == nil)
        #expect(rig.stage.layer.container.opacity == 0)

        rig.stage.follow(IslandBeatFrame(low: 0.7, mid: 0.5, high: 0.4))
        let picture = try #require(rig.stage.picture)
        #expect(picture.look == IslandLaserProgram(seed: Self.seed).looks[0])
        #expect(rig.stage.layer.scene != nil)
        #expect(rig.stage.layer.shownBeamCount > 0)
        // The beams stay on between hits.
        for _ in 0..<30 {
            rig.time += 1.0 / 15
            rig.stage.follow(IslandBeatFrame(low: 0.7, mid: 0.5, high: 0.4))
        }
        #expect(rig.stage.layer.shownBeamCount > 0)
        #expect(rig.stage.picture == picture)
    }

    @Test func inAShowAHitNeverChangesTheLookAndASnareSwapsTheTwoColors() throws {
        let rig = Rig()
        rig.show(Self.pulse(mode: .show))
        rig.stage.follow(IslandBeatFrame(low: 0.7, mid: 0.5, high: 0.4))
        let first = try #require(rig.stage.picture)

        rig.time += 0.5
        rig.stage.follow(IslandBeatFrame(low: 1, hit: .kick))
        #expect(rig.stage.picture?.look == first.look)
        #expect(rig.stage.picture?.base == first.base)
        #expect(rig.stage.layer.colorFlash(ofBeam: 0) == nil)
        #expect(rig.stage.layer.lift?.duration == IslandLaserShow.pushFall)

        rig.time += 0.5
        rig.stage.follow(IslandBeatFrame(low: 0.7, mid: 1, hit: .snare))
        #expect(rig.stage.picture?.look == first.look)
        #expect(rig.stage.picture?.base == first.accent)
        #expect(rig.stage.picture?.accent == first.base)
        #expect(rig.stage.layer.colorFlash(ofBeam: 0)?.duration == IslandLaserShow.flashFall)
    }

    @Test func aNewSongStartsItsOwnShowAndTheSameSongKeepsItsOwn() {
        let rig = Rig()
        rig.show(Self.pulse(mode: .show))
        rig.stage.follow(IslandBeatFrame(low: 0.7, mid: 0.5, high: 0.4))
        rig.time += 20
        rig.stage.follow(IslandBeatFrame(low: 1, hit: .kick))
        #expect(rig.stage.director?.lookIndex == 1)

        // The same pulse again: the show goes on where it was.
        rig.show(Self.pulse(mode: .show))
        #expect(rig.stage.director?.lookIndex == 1)

        let other = IslandLaserSeed.seed(title: "Talk", artist: "Yeat", tint: nil)
        rig.show(Self.pulse(mode: .show, seed: other))
        #expect(rig.stage.director?.program == IslandLaserProgram(seed: other))
        #expect(rig.stage.director?.lookIndex == 0)
        #expect(rig.stage.picture == nil)
        #expect(rig.surfaces.count == 1)
    }

    @Test func switchingModesChangesWhoRunsTheBeams() throws {
        let rig = Rig()
        rig.show(Self.pulse(mode: .reactive))
        #expect(rig.stage.director == nil)
        rig.stage.follow(IslandBeatFrame(low: 1, hit: .kick))
        // Reactive: out and all the way back, with no beam left on.
        #expect(rig.stage.layer.lengthFall(ofBeam: 0)?.duration == IslandBeatGlow.punchFall)
        #expect(rig.stage.layer.shownBeamCount == 0)
        #expect(rig.stage.hueIndex == 1)

        rig.show(Self.pulse(mode: .show))
        #expect(rig.stage.director != nil)
        #expect(rig.stage.layer.fan == nil)
        rig.time += 1
        rig.stage.follow(IslandBeatFrame(low: 0.7, mid: 0.5, high: 0.4))
        #expect(rig.stage.layer.scene != nil)
        // The show's hits do not step Reactive's color.
        rig.time += 0.5
        rig.stage.follow(IslandBeatFrame(low: 1, hit: .kick))
        #expect(rig.stage.hueIndex == 1)

        rig.show(Self.pulse(mode: .reactive))
        #expect(rig.stage.picture == nil)
        #expect(rig.stage.layer.scene == nil)
        #expect(rig.stage.layer.fan?.beams.allSatisfy { $0.length == 0 } == true)
        #expect(rig.surfaces.count == 1 && rig.surfaces[0].closeCount == 0)
        // Reactive runs the beams again: out and all the way back.
        rig.time += 0.5
        rig.stage.follow(IslandBeatFrame(low: 1, hit: .kick))
        #expect(rig.stage.hueIndex == 2)
        #expect(rig.stage.layer.shownBeamCount == 0)

        // Back in the show, the song's show is where it was left.
        let kept = rig.stage.director?.lookIndex
        rig.show(Self.pulse(mode: .show))
        #expect(rig.stage.director?.lookIndex == kept)
        #expect(rig.stage.picture != nil)
        #expect(rig.stage.layer.scene != nil)
    }

    @Test func anInterruptionDoesNotRestartTheShow() throws {
        let rig = Rig()
        rig.show(Self.pulse(mode: .show))
        rig.stage.follow(IslandBeatFrame(low: 0.7, mid: 0.5, high: 0.4))
        // A phrase on, and a snare that changed the two colors over.
        rig.time += 20
        rig.stage.follow(IslandBeatFrame(low: 1, hit: .kick))
        rig.time += 0.5
        rig.stage.follow(IslandBeatFrame(low: 0.7, mid: 1, hit: .snare))
        let before = try #require(rig.stage.picture)
        #expect(rig.stage.director?.lookIndex == 1)

        // A hover, a notice or an agent's flash: the lasers go away.
        rig.show(nil)
        #expect(!rig.stage.isShowing)
        #expect(rig.stage.picture == nil)
        #expect(rig.surfaces[0].closeCount == 1)

        // And come back to the same look in the same colors, at once.
        rig.time += 3
        rig.show(Self.pulse(mode: .show))
        #expect(rig.stage.director?.lookIndex == 1)
        #expect(rig.stage.picture == before)
        #expect(rig.stage.layer.scene != nil)
        #expect(rig.stage.layer.shownBeamCount > 0)
        #expect(rig.surfaces.count == 2)
    }

    @Test func theCountOfFlashesCarriesOverToANewSongsShow() throws {
        let rig = Rig()
        rig.show(Self.pulse(mode: .show))
        rig.stage.follow(IslandBeatFrame(low: 0.7, mid: 0.5, high: 0.4))
        rig.time += 1
        rig.stage.follow(IslandBeatFrame(low: 0.7, mid: 1, hit: .snare))
        let flashed = rig.time
        #expect(rig.stage.director?.flashLog == [flashed])

        // The next track starts with no gap: its show knows of the flash.
        rig.time += 0.1
        let other = IslandLaserSeed.seed(title: "Talk", artist: "Yeat", tint: nil)
        rig.show(Self.pulse(mode: .show, seed: other))
        #expect(rig.stage.director?.program == IslandLaserProgram(seed: other))
        #expect(rig.stage.director?.flashLog == [flashed])
    }

    @Test func aDropOnTheStageIsTheBurstAndThenTheLargestLook() throws {
        let rig = Rig()
        rig.show(Self.pulse(mode: .show))
        let step = 1.0 / 15
        // Ten seconds of groove, two with no bass, and everything back.
        for index in 0..<150 {
            rig.stage.follow(IslandBeatFrame(low: index % 8 == 0 ? 1 : 0.7, mid: 0.6, high: 0.5, hit: index % 8 == 0 ? .kick : nil))
            rig.time += step
        }
        for _ in 0..<30 {
            rig.stage.follow(IslandBeatFrame(low: 0.02, mid: 0.6, high: 0.6))
            rig.time += step
        }
        #expect(rig.stage.picture == nil)
        #expect(rig.stage.layer.container.opacity == 0)

        rig.stage.follow(IslandBeatFrame(low: 1, mid: 0.9, high: 0.9, hit: .kick))
        #expect(rig.stage.layer.burstLength(ofBeam: 0) != nil)
        #expect(rig.stage.director?.drops == 1)

        rig.time += IslandLaserShow.burstLength + step
        rig.stage.follow(IslandBeatFrame(low: 0.7, mid: 0.6, high: 0.5))
        let program = IslandLaserProgram(seed: Self.seed)
        #expect(rig.stage.picture?.look == program.looks[program.biggest])
        #expect(rig.stage.layer.scene != nil)
    }

    // MARK: The saved choice

    @Test func theModeIsReactiveUntilSomebodyPicksTheShow() {
        #expect(NookDisplayPreferences().haloLaserMode == .reactive)
        #expect(IslandLaserMode(storageValue: nil) == .reactive)
        #expect(IslandLaserMode(storageValue: "strobe") == .reactive)
        #expect(IslandLaserMode(storageValue: "show") == .show)

        let defaults = MemoryDefaults()
        // A copy from before the choice: the lasers, with no mode.
        defaults.set(IslandBeatLook.lasers.rawValue, forKey: "nook.display.notch.haloBeatLook")
        var mine = NookDisplayPreferences.load(for: .notch, defaults: defaults)
        #expect(mine.haloLaserMode == .reactive)

        mine.persist(for: .notch, defaults: defaults)
        let before = mine
        let saved = defaults.all
        mine.haloLaserMode = .show
        mine.persistChanges(from: before, for: .notch, defaults: defaults)
        let changed = defaults.all.filter { key, value in (saved[key] as? NSObject) != (value as? NSObject) }
        #expect(Array(changed.keys) == ["nook.display.notch.haloLaserMode"])
        #expect(NookDisplayPreferences.load(for: .notch, defaults: defaults).haloLaserMode == .show)
        #expect(NookDisplayPreferences.load(for: .topBar, defaults: defaults).haloLaserMode == .reactive)
        #expect(!mine.changesThePage(from: before))
        if let template = PersonalizationTemplate.all.first {
            #expect(template.applying(to: mine).haloLaserMode == .show)
        }
        defaults.set(7, forKey: "nook.display.notch.haloLaserMode")
        #expect(NookDisplayPreferences.load(for: .notch, defaults: defaults).haloLaserMode == .reactive)
    }

    @Test func theModeAndTheSongReachThePulseOnlyForAShowOfLasers() {
        var inputs = IslandHaloInputs(
            style: .subtle, policy: .full, isOpened: false, waiting: nil, flashToken: nil,
            noticeTint: nil, musicTint: IslandHaloRGB.rgb255(10, 200, 30), isRunning: false,
            isMusicPlaying: true, pulsesWithBeat: true
        )
        inputs.pulseLaserMode = .show
        inputs.pulseLaserSeed = 77
        func pulse() -> IslandHaloPulse? {
            if case let .pulse(pulse) = IslandHaloState.resolve(inputs).motion { return pulse }
            return nil
        }
        // The Glow look: no mode and no song in the pulse, which leaves
        // the glow as it was when the track changes.
        #expect(pulse()?.laserMode == .reactive)
        #expect(pulse()?.laserSeed == 0)

        inputs.pulseLook = .lasers
        #expect(pulse()?.laserMode == .show)
        #expect(pulse()?.laserSeed == 77)

        inputs.pulseLaserMode = .reactive
        #expect(pulse()?.laserMode == .reactive)
        #expect(pulse()?.laserSeed == 0)
    }

    @Test func theModesHaveTheirWordsInAllThreeLanguages() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let keys = [IslandLaserMode.titleKey] + IslandLaserMode.allCases.map(\.titleKey)
        #expect(keys == [
            "settings.appearance.nook.halo.beat.mode",
            "settings.appearance.nook.halo.beat.mode.reactive",
            "settings.appearance.nook.halo.beat.mode.show",
        ])
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let url = root.appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
            let text = try String(contentsOf: url, encoding: .utf8)
            for key in keys {
                #expect(text.contains("\"\(key)\" = \""), "\(language) has no \(key)")
            }
        }
        let english = try String(
            contentsOf: root.appendingPathComponent("Sources/OpenIslandApp/Resources/en.lproj/Localizable.strings"),
            encoding: .utf8
        )
        for line in ["mode\" = \"Mode\";", "mode.reactive\" = \"Reactive\";", "mode.show\" = \"Show\";"] {
            #expect(english.contains("settings.appearance.nook.halo.beat.\(line)"))
        }
    }
}
