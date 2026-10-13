import AppKit
import QuartzCore
import Testing
@testable import OpenIslandApp

/// A surface that shows nothing: it keeps what it was asked.
@MainActor
final class FakeLaserSurface: IslandLaserSurface {
    private(set) var shown: [(plan: IslandLaserWindowPlan, below: Int)] = []
    private(set) var closeCount = 0
    private(set) var hosted: CALayer?

    func show(_ plan: IslandLaserWindowPlan, hosting layer: CALayer, below windowNumber: Int) {
        shown.append((plan, windowNumber))
        hosted = layer
    }

    func close() {
        closeCount += 1
        hosted = nil
    }
}

/// The Lasers look's window and stage (D56). No window is made here: the
/// window's rule is plain values, and the stage draws on a fake.
@MainActor
@Suite struct IslandLaserStageTests {
    /// A 14 inch MacBook's screen, and its closed island at the top middle.
    private static let screen = CGRect(x: 0, y: 0, width: 1_512, height: 982)
    private static let pill = CGRect(x: 619, y: 950, width: 274, height: 32)

    private static func plan(
        look: IslandBeatLook = .lasers,
        showsPulse: Bool = true,
        pill: CGRect? = IslandLaserStageTests.pill,
        screen: CGRect? = IslandLaserStageTests.screen,
        reach: Double = IslandLaserReach.standard,
        isDemo: Bool = false
    ) -> IslandLaserWindowPlan? {
        IslandLaserWindowPlan.plan(
            look: look, showsPulse: showsPulse, pill: pill, screen: screen, reach: reach, isDemo: isDemo
        )
    }

    /// `reach` is the lasers' own. The glow's is left at its standard.
    private static func pulse(
        look: IslandBeatLook = .lasers,
        reach: Double = IslandLaserReach.standard,
        count: Int = IslandLaserCount.standard
    ) -> IslandHaloPulse {
        IslandHaloPulse(
            low: 0.25, high: 0.85, hues: IslandBeatHues.fixed, look: look, laserReach: reach, laserCount: count,
            tint: nil
        )
    }

    // MARK: When the window exists

    @Test func theWindowExistsOnlyForLasersWhileThePulseShows() {
        #expect(Self.plan() != nil)
        // The look is Glow: no window, whatever plays.
        #expect(Self.plan(look: .glow) == nil)
        // The tap is not listening, or the island shows something else.
        #expect(Self.plan(showsPulse: false) == nil)
        // The island is on no screen yet.
        #expect(Self.plan(pill: nil) == nil)
        #expect(Self.plan(screen: nil) == nil)
        #expect(Self.plan(pill: .zero) == nil)
    }

    @Test func theWindowHoldsTheIslandAndEveryBeamUnderIt() throws {
        for reach in [0.0, 0.25, 0.6, 1] {
            let plan = try #require(Self.plan(reach: reach))
            let length = IslandLaserWindowPlan.beamLength(reach: reach, pill: Self.pill, screen: Self.screen)
            let flat = IslandLaserRoom.insets(length: length)
            let tilted = IslandLaserRoom.tiltedReach(
                length: length, tilt: IslandLaserTilt.standard, halfEdge: Double(Self.pill.width) / 2
            )
            // The fan that comes toward the viewer goes further than the
            // flat one, to the side and down.
            let side = max(flat.side + Self.pill.width / 2, tilted.side)
            let below = max(flat.below, tilted.below)
            #expect(side == tilted.side && below == tilted.below)

            // As wide and as deep as the beams go, and never past the
            // island's own screen.
            #expect(plan.frame.maxY == Self.pill.maxY)
            #expect(abs(plan.frame.minY - max(0, Self.pill.minY - below)) <= 1)
            #expect(abs(plan.frame.minX - max(0, Self.pill.midX - side)) <= 1)
            #expect(abs(plan.frame.maxX - min(Self.screen.maxX, Self.pill.midX + side)) <= 1)
            #expect(Self.screen.contains(plan.frame))
            // The island sits at the top middle of its own window.
            #expect(plan.notch.size == Self.pill.size)
            #expect(abs(plan.notch.maxY - plan.frame.height) <= 1)
            #expect(abs(plan.notch.midX - plan.frame.width / 2) <= 1)
        }
        // A longer reach is a larger window.
        let near = try #require(Self.plan(reach: 0))
        let far = try #require(Self.plan(reach: 1))
        #expect(far.frame.height > near.frame.height)
        #expect(far.frame.width > near.frame.width)
    }

    @Test func theWindowNeverReachesOntoTheDisplayBesideIt() throws {
        // An external display to the right of the MacBook, with its island
        // near the left edge: the beams that lean left are cut at the edge.
        let external = CGRect(x: 1_512, y: 0, width: 1_920, height: 1_080)
        let pill = CGRect(x: 1_540, y: 1_056, width: 200, height: 24)
        let plan = try #require(Self.plan(pill: pill, screen: external, reach: 1))

        #expect(plan.frame.minX >= external.minX)
        #expect(external.contains(plan.frame))
        // The island is still where it is on the screen.
        #expect(plan.notch.offsetBy(dx: plan.frame.minX, dy: plan.frame.minY) == pill)
    }

    @Test func theWindowSitsOverAppsAndUnderEverythingThatAsksTheUserForSomething() {
        let traits = IslandLaserWindowTraits.traits(isDemo: false)
        // Over an app's own windows and its floating panels.
        #expect(traits.level.rawValue > NSWindow.Level.normal.rawValue)
        #expect(traits.level.rawValue > NSWindow.Level.floating.rawValue)
        // Under an alert or a permission prompt, the Dock, the menu bar,
        // the status items and the island's own panel.
        #expect(traits.level.rawValue < NSWindow.Level.modalPanel.rawValue)
        #expect(traits.level.rawValue < NSWindow.Level.dock.rawValue)
        #expect(traits.level.rawValue < NSWindow.Level.mainMenu.rawValue)
        #expect(traits.level.rawValue < NSWindow.Level.statusBar.rawValue)
        #expect(traits.level.rawValue < IslandPanelLevel.standard.rawValue)
        #expect(Self.plan()?.traits == traits)
        #expect(Self.plan()?.level == traits.level)
    }

    @Test func theWindowJoinsNoFullScreenSpace() {
        for isDemo in [false, true] {
            let behavior = IslandLaserWindowTraits.traits(isDemo: isDemo).collectionBehavior
            // A film played full screen is music too: no beams across it.
            #expect(!behavior.contains(.fullScreenAuxiliary))
            #expect(!behavior.contains(.fullScreenPrimary))
            // Every desktop Space, and it stays put when the desktop is
            // revealed and is in nobody's window cycle.
            #expect(behavior.contains(.canJoinAllSpaces))
            #expect(behavior.contains(.stationary))
            #expect(behavior.contains(.ignoresCycle))
        }
    }

    @Test func theWindowTakesNoClickAndNeverBecomesKey() {
        for isDemo in [false, true] {
            let traits = IslandLaserWindowTraits.traits(isDemo: isDemo)
            #expect(traits.ignoresMouseEvents)
            #expect(!traits.acceptsMouseMovedEvents)
            #expect(traits.styleMask.contains(.borderless))
            #expect(traits.styleMask.contains(.nonactivatingPanel))
            #expect(!traits.styleMask.contains(.titled))
            #expect(!traits.hasShadow)
            #expect(!traits.isOpaque)
            #expect(traits.order == .below)
        }
    }

    @Test func inTheDemoModeTheLasersTakeTheIslandsLevelAndGoUnderItsPanel() {
        // The demo's backdrop is on the island's level, and a window
        // under that level would be behind it.
        let traits = IslandLaserWindowTraits.traits(isDemo: true)
        #expect(traits.level == DemoWindowLevels.island)
        #expect(traits.level.rawValue < DemoWindowLevels.raised.rawValue)
        #expect(traits.order == .below)
        #expect(Self.plan(isDemo: true)?.level == DemoWindowLevels.island)
        #expect(Self.plan(isDemo: true)?.traits != Self.plan(isDemo: false)?.traits)
    }

    @Test func theWindowIsOrderedOutWheneverThereIsNoPlanForIt() {
        // Every way there can be no window, each as a plain decision.
        let offScreen = Self.pill.offsetBy(dx: 0, dy: 4_000)
        let none: [IslandLaserWindowPlan?] = [
            Self.plan(look: .glow), Self.plan(showsPulse: false), Self.plan(pill: nil), Self.plan(screen: nil),
            Self.plan(pill: .zero), Self.plan(pill: offScreen),
            Self.plan(screen: CGRect(x: 0, y: 0, width: 0, height: 0)),
        ]
        #expect(none.allSatisfy { $0 == nil })

        // And the stage acts on it: one order out, and nothing left on
        // the surface.
        let rig = Rig()
        rig.show(Self.pulse())
        #expect(rig.surfaces[0].hosted != nil)
        rig.show(Self.pulse(), pill: offScreen)
        #expect(rig.surfaces[0].closeCount == 1)
        #expect(rig.surfaces[0].hosted == nil)
        #expect(!rig.stage.isShowing)
        // Asked again with nothing to show, it does nothing more.
        rig.show(nil)
        #expect(rig.surfaces[0].closeCount == 1)
    }

    // MARK: The lasers' own reach

    @Test func theLasersReachGoesFromTodaysLengthToTheScreensFarCorner() {
        let farthest = IslandLaserReach.farthest(pill: Self.pill, screen: Self.screen)
        // From under the middle of the island to a bottom corner: 756
        // across and 950 down.
        #expect(abs(farthest - (756.0 * 756 + 950.0 * 950).squareRoot()) < 0.001)

        // At 0, what the longest beam was before this slider.
        #expect(IslandLaserReach.length(reach: 0, farthest: farthest) == IslandLaserLimits.mostLength)
        // At 1, the far bottom corner of the island's screen.
        #expect(IslandLaserReach.length(reach: 1, farthest: farthest) == farthest)
        // The default sits a quarter of the way.
        #expect(IslandLaserReach.standard == 0.25)
        let standard = IslandLaserReach.length(reach: IslandLaserReach.standard, farthest: farthest)
        #expect(abs(standard - (IslandLaserLimits.mostLength + (farthest - IslandLaserLimits.mostLength) / 4)) < 0.001)
    }

    @Test func aLongerReachIsNeverAShorterBeam() {
        var last = IslandLaserReach.length(reach: 0, farthest: 1_200)
        for step in 1...100 {
            let length = IslandLaserReach.length(reach: Double(step) / 100, farthest: 1_200)
            #expect(length > last)
            last = length
        }
    }

    @Test func aReachOutsideZeroToOneAndAScreenTooSmallAreHeld() {
        #expect(IslandLaserReach.length(reach: -4, farthest: 1_200) == IslandLaserReach.length(reach: 0, farthest: 1_200))
        #expect(IslandLaserReach.length(reach: 30, farthest: 1_200) == 1_200)
        #expect(IslandLaserReach.clamped(.nan) == IslandLaserReach.standard)
        #expect(IslandLaserReach.clamped(1.5) == 1)
        #expect(IslandLaserReach.clamped(-0.5) == 0)
        // A screen smaller than today's beams: the length never drops
        // under what it was, and the window is cut to the screen anyway.
        #expect(IslandLaserReach.length(reach: 1, farthest: 100) == IslandLaserLimits.mostLength)
        #expect(IslandLaserReach.length(reach: 1, farthest: .nan) == IslandLaserLimits.mostLength)
    }

    @Test func theFarCornerIsTheFartherOneWhenTheIslandIsOffCenter() {
        // An island near the left edge of a wide display: the right corner.
        let screen = CGRect(x: 1_512, y: 0, width: 1_920, height: 1_080)
        let pill = CGRect(x: 1_540, y: 1_056, width: 200, height: 24)
        let farthest = IslandLaserReach.farthest(pill: pill, screen: screen)

        #expect(abs(farthest - Double(hypot(screen.maxX - pill.midX, pill.minY))) < 0.001)
        #expect(farthest > Double(hypot(pill.midX - screen.minX, pill.minY)))
    }

    @Test func theRoomNeverLeavesTheScreensFrameAtAnyReach() throws {
        let screens: [(CGRect, CGRect)] = [
            (Self.screen, Self.pill),
            (CGRect(x: 1_512, y: 0, width: 1_920, height: 1_080), CGRect(x: 1_540, y: 1_056, width: 200, height: 24)),
            (CGRect(x: -2_560, y: 200, width: 2_560, height: 1_440), CGRect(x: -1_460, y: 1_616, width: 360, height: 24)),
        ]
        for (screen, pill) in screens {
            for step in 0...20 {
                let plan = try #require(Self.plan(pill: pill, screen: screen, reach: Double(step) / 20))
                #expect(screen.contains(plan.frame))
                #expect(plan.notch.offsetBy(dx: plan.frame.minX, dy: plan.frame.minY) == pill)
            }
            // At the far end the window is the screen, and never more.
            let far = try #require(Self.plan(pill: pill, screen: screen, reach: 1))
            #expect(far.frame == screen)
        }
    }

    @Test func eachLookHasItsOwnReachSliderAndOnlyOneShows() {
        #expect(IslandBeatLook.glow.reachSlider == .glow)
        #expect(IslandBeatLook.lasers.reachSlider == .lasers)
        #expect(IslandBeatReachSlider.glow.titleKey == "settings.appearance.nook.halo.beat.reach")
        #expect(IslandBeatReachSlider.lasers.titleKey == "settings.appearance.nook.halo.beat.laserReach")
        #expect(IslandBeatReachSlider.glow.titleKey != IslandBeatReachSlider.lasers.titleKey)
    }

    @Test func theLasersReachIsSavedApartFromTheGlowsAndOldSettingsGetTheDefault() {
        let defaults = MemoryDefaults()
        // A copy from before the lasers had a reach of their own.
        defaults.set(0.9, forKey: "nook.display.notch.haloPulseReach")
        defaults.set(IslandBeatLook.lasers.rawValue, forKey: "nook.display.notch.haloBeatLook")
        var mine = NookDisplayPreferences.load(for: .notch, defaults: defaults)
        #expect(mine.haloLaserReach == IslandLaserReach.standard)
        #expect(mine.haloPulseReach == 0.9)
        #expect(NookDisplayPreferences().haloLaserReach == IslandLaserReach.standard)

        let before = mine
        mine.haloLaserReach = 0.8
        mine.persistChanges(from: before, for: .notch, defaults: defaults)
        let loaded = NookDisplayPreferences.load(for: .notch, defaults: defaults)
        #expect(loaded.haloLaserReach == 0.8)
        // The glow's reach is its own and did not move.
        #expect(loaded.haloPulseReach == 0.9)
        #expect(NookDisplayPreferences.load(for: .topBar, defaults: defaults).haloLaserReach == IslandLaserReach.standard)

        defaults.set(12.0, forKey: "nook.display.notch.haloLaserReach")
        #expect(NookDisplayPreferences.load(for: .notch, defaults: defaults).haloLaserReach == 1)
        // A drag of it is not a change to the page, and a layout keeps it.
        #expect(!mine.changesThePage(from: before))
        if let template = PersonalizationTemplate.all.first {
            #expect(template.applying(to: mine).haloLaserReach == 0.8)
        }
    }

    @Test func theLasersReachGoesFromTheDisplaysChoiceToThePulse() {
        var inputs = IslandHaloInputs(
            style: .subtle, policy: .full, isOpened: false, waiting: nil, flashToken: nil,
            noticeTint: nil, musicTint: IslandHaloRGB.rgb255(10, 200, 30), isRunning: false,
            isMusicPlaying: true, pulsesWithBeat: true
        )
        inputs.pulseReach = 0.1
        inputs.pulseLaserReach = 0.7
        guard case let .pulse(pulse) = IslandHaloState.resolve(inputs).motion else {
            Issue.record("No pulse")
            return
        }
        #expect(pulse.laserReach == 0.7)
        #expect(pulse.reach == 0.1)
        inputs.pulseLaserReach = 55
        if case let .pulse(held) = IslandHaloState.resolve(inputs).motion { #expect(held.laserReach == 1) }
    }

    // MARK: The stage

    /// A stage that draws on a fake, with a clock of its own.
    @MainActor
    private final class Rig {
        let stage = IslandLaserStage()
        var surfaces: [FakeLaserSurface] = []
        var time = 10.0
        let lights = FakeFlashingLights()

        init() {
            stage.makeSurface = { [unowned self] in
                let surface = FakeLaserSurface()
                self.surfaces.append(surface)
                return surface
            }
            stage.now = { [unowned self] in self.time }
            stage.flashingLights = lights
            stage.isDemo = { false }
        }

        func show(_ pulse: IslandHaloPulse?, pill: CGRect? = IslandLaserStageTests.pill) {
            stage.update(
                pulse: pulse, pill: pill, screen: IslandLaserStageTests.screen,
                contentsScale: 2, islandWindowNumber: 41
            )
        }
    }

    @Test func theStageShowsTheBeamsUnderTheIslandsPanel() throws {
        let rig = Rig()
        #expect(!rig.stage.isShowing)

        rig.show(Self.pulse())

        #expect(rig.stage.isShowing)
        let surface = try #require(rig.surfaces.first)
        #expect(surface.shown.count == 1)
        #expect(surface.shown[0].below == 41)
        #expect(surface.shown[0].plan == Self.plan())
        #expect(surface.hosted === rig.stage.layer.container)
        #expect(rig.stage.layer.container.frame.size == surface.shown[0].plan.frame.size)
        // The fan is there with every beam back at the notch, until a hit.
        #expect(rig.stage.layer.fan != nil)
        #expect(rig.stage.layer.shownBeamCount == 0)
        #expect(rig.stage.layer.fan?.beams.allSatisfy { $0.length == 0 } == true)
    }

    @Test func theSameStateAgainMovesNothing() {
        let rig = Rig()
        rig.show(Self.pulse())
        rig.show(Self.pulse())
        rig.show(Self.pulse())

        #expect(rig.surfaces.count == 1)
        #expect(rig.surfaces[0].shown.count == 1)
    }

    @Test func aNewReachOrANewPlaceMovesTheSameWindow() throws {
        let rig = Rig()
        rig.show(Self.pulse(reach: 0))

        rig.show(Self.pulse(reach: 0.1))
        // At the short end the length does not depend on where the island
        // is, and the window moves exactly as far as the island did.
        rig.show(Self.pulse(reach: 0), pill: Self.pill.offsetBy(dx: 40, dy: 0))

        #expect(rig.surfaces.count == 1)
        let shown = rig.surfaces[0].shown
        #expect(shown.count == 3)
        #expect(shown[1].plan.frame.height > shown[0].plan.frame.height)
        #expect(shown[2].plan.frame.minX == shown[0].plan.frame.minX + 40)
        #expect(rig.surfaces[0].closeCount == 0)
    }

    @Test func theWindowIsClosedTheMomentTheLasersAreNotWanted() {
        let gone: [(IslandHaloPulse?, CGRect?)] = [
            (nil, Self.pill),
            (Self.pulse(look: .glow), Self.pill),
            (Self.pulse(), nil),
        ]
        for (pulse, pill) in gone {
            let rig = Rig()
            rig.show(Self.pulse())

            rig.show(pulse, pill: pill)

            #expect(!rig.stage.isShowing)
            #expect(rig.surfaces[0].closeCount == 1)
            #expect(rig.stage.layer.fan == nil)
            // And made anew when they are wanted again.
            rig.show(Self.pulse())
            #expect(rig.surfaces.count == 2)
            #expect(rig.stage.isShowing)
        }
    }

    @Test func aStageThatShowsNothingIgnoresTheSong() {
        let rig = Rig()
        rig.stage.follow(IslandBeatFrame(low: 1, mid: 1, high: 1, hit: .snare))
        rig.stage.close()

        #expect(rig.surfaces.isEmpty)
        #expect(rig.stage.layer.fan == nil)
    }

    @Test func aLowHitShootsTheBeamsOutAndTheyComeAllTheWayBack() throws {
        let rig = Rig()
        rig.show(Self.pulse())
        let color = rig.stage.layer.fan?.color

        rig.time += 0.5
        rig.stage.follow(IslandBeatFrame(low: 1, mid: 0.2, high: 0, hit: .kick))

        // One fall for each beam, from its full length to nothing, in the
        // glow's own time. What the layer holds when it is over is nothing.
        let layer = rig.stage.layer
        let fall = try #require(layer.lengthFall(ofBeam: 0))
        #expect(fall.duration == IslandBeatGlow.punchFall)
        let from = try #require((fall.fromValue as? NSValue)?.caTransform3DValue)
        let to = try #require((fall.toValue as? NSValue)?.caTransform3DValue)
        #expect(from.m22 > 0.2)
        #expect(to.m22 <= IslandLaserLayer.retracted)
        #expect(layer.length(ofBeam: 0) < 1)
        #expect(layer.shownBeamCount == 0)
        #expect(layer.fan?.beams.allSatisfy { $0.length == 0 } == true)
        // In the next color.
        #expect(layer.fan?.color != color)
        #expect(rig.stage.hueIndex == 1)
    }

    @Test func aHeldBassNoteIsOneShotAndLevelsAloneMoveNoBeam() {
        let rig = Rig()
        rig.show(Self.pulse())
        rig.stage.follow(IslandBeatFrame(low: 1, hit: .kick))
        let fall = rig.stage.layer.lengthFall(ofBeam: 0)

        for step in 1...45 {
            rig.time += 1.0 / 15
            _ = step
            rig.stage.follow(IslandBeatFrame(low: 1, mid: 0.5, high: 0.2, hit: nil))
        }

        #expect(rig.stage.layer.lengthFall(ofBeam: 0) === fall)
        #expect(rig.stage.hueIndex == 1)
    }

    @Test func consecutiveLowHitsGetDifferentColorsOnTheBeamsToo() {
        let rig = Rig()
        rig.show(Self.pulse())
        var colors: [IslandHaloRGB?] = [rig.stage.layer.fan?.color]

        for _ in 0..<5 {
            rig.time += 0.15
            rig.stage.follow(IslandBeatFrame(low: 1, hit: .kick))
            #expect(rig.stage.layer.fan?.color != colors.last ?? nil)
            colors.append(rig.stage.layer.fan?.color)
        }
        #expect(rig.stage.hueIndex == 5)
    }

    // MARK: How many, and which way they stand

    @Test func theStageMakesTheBeamsOncePerCount() {
        let rig = Rig()
        rig.show(Self.pulse())
        #expect(rig.stage.layer.beams.count == 16)
        #expect(rig.stage.layer.rebuilds == 0)

        rig.show(Self.pulse(count: 24))
        #expect(rig.stage.layer.beams.count == 24)
        #expect(rig.stage.layer.rebuilds == 1)
        // The same window: a new count moves nothing but the beams.
        #expect(rig.surfaces.count == 1)
        #expect(rig.surfaces[0].closeCount == 0)

        // The same count again, a new reach, and a song's worth of hits.
        rig.show(Self.pulse(count: 24))
        rig.show(Self.pulse(reach: 0.6, count: 24))
        for step in 0..<120 {
            rig.time += 0.2
            let hit: IslandBeatHit = step % 4 == 2 ? .snare : (step.isMultiple(of: 2) ? .kick : .hat)
            rig.stage.follow(IslandBeatFrame(low: 1, mid: 1, high: 1, hit: hit))
        }
        #expect(rig.stage.layer.rebuilds == 1)

        rig.show(Self.pulse(reach: 0.6, count: 8))
        #expect(rig.stage.layer.beams.count == 8)
        #expect(rig.stage.layer.rebuilds == 2)
    }

    @Test func aLowHitShootsEveryBeamOfTheCount() throws {
        for count in [8, 16, 24] {
            let rig = Rig()
            rig.show(Self.pulse(count: count))
            rig.stage.follow(IslandBeatFrame(low: 1, hit: .kick))

            #expect(rig.stage.layer.fan?.beams.count == count)
            for index in 0..<count {
                let fall = try #require(rig.stage.layer.lengthFall(ofBeam: index))
                #expect(fall.duration == IslandBeatGlow.punchFall)
                #expect(try #require((fall.fromValue as? NSValue)?.caTransform3DValue).m22 > 0.2)
            }
        }
    }

    @Test func aMidHitStepsThroughTheShapesFlatAndTowardTheViewer() {
        let rig = Rig()
        rig.show(Self.pulse())
        #expect(rig.stage.layer.tilt == 0)
        var tilts: [Double] = []
        var leans: [[Double]] = []
        for _ in 0..<IslandLaserArrangement.all.count {
            // Well apart: no punch is in flight when the next one lands.
            rig.time += 0.5
            rig.stage.follow(IslandBeatFrame(low: 0.2, mid: 1, hit: .snare))
            let layer = rig.stage.layer
            tilts.append((layer.tilt * 1_000).rounded() / 1_000)
            leans.append((0..<layer.beams.count).map { (layer.lean(ofBeam: $0) * 1_000).rounded() / 1_000 })
            // A mid hit's burst does not lunge.
            #expect(layer.tiltFall == nil)
        }
        // The first mid hit leaves the fan the stage starts in, and after
        // one for every arrangement the flat fan is back.
        let expected = (1...IslandLaserArrangement.all.count).map { IslandLaserArrangement.at($0).orientation.tilt }
        #expect(tilts == expected)
        #expect(tilts.filter { $0 > 0 }.count == 4)
        #expect(tilts.last == 0)
        // Each step is another shape: the beams never lean as they did.
        #expect(zip(leans.dropFirst(), leans).allSatisfy { $0 != $1 })
    }

    @Test func aLowHitShootsTheFanThatFacesTheViewerWithALungeAndItComesAllTheWayBack() throws {
        func lungeStart(strength: Double) throws -> Double {
            let rig = Rig()
            rig.show(Self.pulse())
            // One mid hit: from the flat fan to wings toward the viewer.
            rig.stage.follow(IslandBeatFrame(low: 0.2, mid: 1, hit: .snare))
            rig.time += 0.5
            rig.stage.follow(IslandBeatFrame(low: strength, hit: .kick))

            let layer = rig.stage.layer
            #expect(abs(layer.tilt - IslandLaserTilt.standard) < 0.001)
            for index in 0..<layer.beams.count {
                let fall = try #require(layer.lengthFall(ofBeam: index))
                // Out at once and back in the same 140 ms as a flat fan.
                #expect(fall.duration == IslandBeatGlow.punchFall)
                #expect(try #require((fall.toValue as? NSValue)?.caTransform3DValue).m22 <= IslandLaserLayer.retracted)
            }
            #expect(layer.shownBeamCount == 0)
            #expect(layer.fan?.beams.allSatisfy { $0.length == 0 } == true)
            // The lunge is inside the same 140 ms.
            let lunge = try #require(layer.tiltFall)
            #expect(lunge.duration == IslandBeatGlow.punchFall)
            let to = try #require((lunge.toValue as? NSValue)?.caTransform3DValue)
            #expect(abs(IslandLaserLayer.tilt(of: to) - IslandLaserTilt.standard) < 0.001)
            return IslandLaserLayer.tilt(of: try #require((lunge.fromValue as? NSValue)?.caTransform3DValue))
        }

        // A hard hit lunges the whole way, and a soft one less.
        #expect(abs(try lungeStart(strength: 1) - (IslandLaserTilt.standard + IslandLaserTilt.lunge)) < 0.001)
        #expect(abs(try lungeStart(strength: 0.5) - (IslandLaserTilt.standard + IslandLaserTilt.lunge / 2)) < 0.001)
        #expect(IslandLaserStage.lunge(tilt: 0, strength: 1) == 0)
        #expect(IslandLaserStage.lunge(tilt: 50, strength: 7) == IslandLaserTilt.lunge)
        #expect(IslandLaserStage.lunge(tilt: 50, strength: .nan) == 0)
    }

    @Test func aFlatFanDoesNotLunge() {
        let rig = Rig()
        rig.show(Self.pulse())
        rig.stage.follow(IslandBeatFrame(low: 1, hit: .kick))

        #expect(rig.stage.layer.tilt == 0)
        #expect(rig.stage.layer.tiltFall == nil)
        #expect(rig.stage.layer.lengthFall(ofBeam: 0) != nil)
    }

    @Test func theWindowHoldsTheWideCurtainAtEveryReach() throws {
        let space = IslandLaserSpace(pill: Self.pill, screen: Self.screen)
        for step in 0...10 {
            let reach = Double(step) / 10
            let plan = try #require(Self.plan(reach: reach))
            let wide = space.wide(reach: reach)
            let soft = IslandLaserLimits.softHalfWidth
            #expect(Double(plan.frame.minX) <= Double(Self.pill.midX) - wide.left - soft + 1)
            #expect(Double(plan.frame.maxX) >= Double(Self.pill.midX) + wide.right + soft - 1)
            #expect(Self.screen.contains(plan.frame))
        }
    }

    @Test func atItsFarEndTheBeamsAreDrawnAsLongAsTheScreensFarCorner() throws {
        let rig = Rig()
        rig.show(Self.pulse(reach: 1))
        let farthest = IslandLaserReach.farthest(pill: Self.pill, screen: Self.screen)
        #expect(abs(rig.stage.beamLength - farthest) < 0.001)

        // And the punch rule holds at that length: out at once, back in
        // the same 140 ms, whatever the distance.
        rig.stage.follow(IslandBeatFrame(low: 1, hit: .kick))
        let fall = try #require(rig.stage.layer.lengthFall(ofBeam: 0))
        #expect(fall.duration == IslandBeatGlow.punchFall)
        // The window is the screen.
        #expect(rig.surfaces[0].shown[0].plan.frame == Self.screen)

        let near = Rig()
        near.show(Self.pulse(reach: 0))
        #expect(near.stage.beamLength == IslandLaserLimits.mostLength)
    }

    @Test func aHitsStrengthSetsHowFarTheBeamsShoot() throws {
        func peak(_ strength: Double) throws -> CGFloat {
            let rig = Rig()
            rig.show(Self.pulse())
            rig.stage.follow(IslandBeatFrame(low: strength, hit: .kick))
            let fall = try #require(rig.stage.layer.lengthFall(ofBeam: 0))
            return try #require((fall.fromValue as? NSValue)?.caTransform3DValue).m22
        }

        let hard = try peak(1)
        let half = try peak(0.5)
        #expect(abs(half - hard / 2) < 0.01)
        // The weakest hit that counts still shoots.
        #expect(abs(try peak(0.01) - hard * CGFloat(IslandLaserStage.leastPunch)) < 0.01)
    }

    @Test func aClapAloneSnapsTheFanAndShootsAShorterBurstInTheNextColor() throws {
        let rig = Rig()
        rig.show(Self.pulse())
        rig.stage.follow(IslandBeatFrame(low: 1, hit: .kick))
        let kicked = try #require(rig.stage.layer.fan)
        let kickFall = try #require(rig.stage.layer.lengthFall(ofBeam: 0))

        rig.time += 0.5
        rig.stage.follow(IslandBeatFrame(low: 0.2, mid: 1, hit: .snare))

        let snapped = try #require(rig.stage.layer.fan)
        let burst = try #require(rig.stage.layer.lengthFall(ofBeam: 0))
        #expect(snapped.color != kicked.color)
        #expect(snapped.beams.map(\.lean) != kicked.beams.map(\.lean))
        #expect(burst.duration == IslandBeatGlow.flashFall)
        // Shorter than a full punch.
        let burstPeak = try #require((burst.fromValue as? NSValue)?.caTransform3DValue).m22
        let kickPeak = try #require((kickFall.fromValue as? NSValue)?.caTransform3DValue).m22
        #expect(burstPeak < kickPeak)
        #expect(IslandLaserStage.snareBurst < 1)
    }

    @Test func aClapDuringAShotKeepsTheColorAndOnlyFlashesTheNotch() throws {
        let rig = Rig()
        rig.show(Self.pulse())
        rig.stage.follow(IslandBeatFrame(low: 1, hit: .kick))
        let kicked = try #require(rig.stage.layer.fan)
        let shot = rig.stage.layer.lengthFall(ofBeam: 0)

        // 80 ms later, with the beams still on their way back.
        rig.time += 0.08
        rig.stage.follow(IslandBeatFrame(low: 0.2, mid: 1, hit: .snare))

        #expect(rig.stage.layer.fan?.color == kicked.color)
        #expect(rig.stage.hueIndex == 1)
        #expect(rig.stage.layer.lengthFall(ofBeam: 0) === shot)
        let flash = try #require(rig.stage.layer.hazeFall)
        #expect(flash.fromValue as? Float == 1)
        #expect(flash.duration == IslandBeatGlow.flashFall)
    }

    @Test func aHatIsASmallFlickerAtTheNotchAndNoBeam() throws {
        let rig = Rig()
        rig.show(Self.pulse())
        rig.time += 1
        rig.stage.follow(IslandBeatFrame(high: 1, hit: .hat))

        let flicker = try #require(rig.stage.layer.hazeFall)
        let lift = try #require(flicker.fromValue as? Float) - IslandLaserLayer.restingHaze
        #expect(lift > 0)
        #expect(Double(lift) <= IslandLaserLimits.hatCeiling + 0.000_1)
        #expect(flicker.toValue as? Float == IslandLaserLayer.restingHaze)
        #expect(flicker.duration == IslandBeatGlow.shimmerFall)
        #expect(rig.stage.layer.lengthFall(ofBeam: 0) == nil)
        #expect(rig.stage.hueIndex == 0)
        // While a shot is coming back a hat leaves it alone.
        rig.stage.follow(IslandBeatFrame(low: 1, hit: .kick))
        let shotHaze = rig.stage.layer.hazeFall
        rig.time += 0.05
        rig.stage.follow(IslandBeatFrame(high: 1, hit: .hat))
        #expect(rig.stage.layer.hazeFall === shotHaze)
    }

    // MARK: Dim flashing lights

    /// Feeds the stage a snare every `gap` seconds and counts the times
    /// its color stepped.
    private static func snaps(gap: Double, seconds: Double, dims: Bool) -> [Double] {
        let rig = Rig()
        rig.lights.dimsFlashingLights = dims
        rig.show(pulse())
        var times: [Double] = []
        for step in 0..<Int((seconds / gap).rounded()) {
            rig.time = 100 + Double(step) * gap
            let before = rig.stage.layer.fan?.color
            rig.stage.follow(IslandBeatFrame(low: 0.5, mid: 1, high: 0, hit: .snare))
            if rig.stage.layer.fan?.color != before { times.append(rig.time) }
        }
        return times
    }

    private static func mostInASecond(_ times: [Double]) -> Int {
        times.map { start in times.filter { $0 >= start && $0 < start + 1 - 0.000_001 }.count }.max() ?? 0
    }

    @Test func byDefaultTheFanSnapsWithEveryHit() {
        let times = Self.snaps(gap: 0.1, seconds: 3, dims: false)
        #expect(times.count == 30)
    }

    @Test func withDimFlashingLightsOnTheLasersKeepThreeASecondToo() {
        for gap in [0.1, 0.02, 0.26, 0.34] {
            let times = Self.snaps(gap: gap, seconds: 5, dims: true)
            #expect(!times.isEmpty)
            #expect(Self.mostInASecond(times) <= 3, "a snare every \(gap) s")
        }
    }

    // MARK: The glow under the beams

    private static func state(look: IslandBeatLook) -> IslandHaloState {
        IslandHaloState(
            source: .music, color: IslandBeatHues.fixed[0],
            motion: .pulse(pulse(look: look)), restOpacity: 0.25, radius: 12, drop: 3
        )
    }

    private static func makeView() -> IslandHaloLayerView {
        let spread = IslandHaloLayerView.maxSpread
        let view = IslandHaloLayerView(frame: CGRect(x: 0, y: 0, width: 160 + spread * 2, height: 60 + spread * 2))
        view.cornerRadius = 16
        view.layoutSubtreeIfNeeded()
        var time = 0.0
        view.beatGlow.now = {
            time += 1
            return time
        }
        view.beatGlow.flashingLights = FakeFlashingLights()
        return view
    }

    @Test func aViewInNoWindowShowsNoLasersAndLeavesTheSongToTheGlow() {
        // A test's view is in no window: there is nowhere for the beams.
        let rig = Rig()
        let view = Self.makeView()
        view.laserStage = rig.stage
        view.apply(state: Self.state(look: .lasers))

        #expect(!rig.stage.isShowing)
        #expect(rig.surfaces.isEmpty)
        view.applyBeat(IslandBeatFrame(low: 1, mid: 1, high: 0, hit: .snare))
        #expect(view.beatGlow.hueIndex == 1)
        #expect(view.beatGlow.flashes == 1)
    }

    @Test func theViewListensForTheIslandChangingScreensOnlyWhileItIsInAWindow() {
        // A move to a display of the same scale, with the panel the same
        // size, lays nothing out again. These two notices are what tell
        // the view to move the lasers.
        #expect(IslandHaloLayerView.screenNotifications == [
            NSWindow.didChangeScreenNotification,
            NSApplication.didChangeScreenParametersNotification,
        ])
        // In no window there is nothing to listen for, and the notice
        // itself only closes what cannot be shown.
        let rig = Rig()
        rig.show(Self.pulse())
        let view = Self.makeView()
        #expect(view.screenObserverCount == 0)
        view.laserStage = rig.stage
        view.apply(state: Self.state(look: .lasers))
        view.screenChanged()
        #expect(!rig.stage.isShowing)
        #expect(rig.surfaces[0].closeCount == 1)
    }

    @Test func thePunchOfTheGlowNamesItsFrameRate() throws {
        let view = Self.makeView()
        view.apply(state: Self.state(look: .glow))
        view.applyBeat(IslandBeatFrame(low: 1, mid: 0, high: 0, hit: .kick))

        let reach = try #require(view.beatGlow.container.animation(forKey: "beat.scale") as? CABasicAnimation)
        #expect(reach.preferredFrameRateRange == Motion.Halo.hitFrameRateRange)
        // Every animation the punch started names one: none is left to
        // run at the display's own rate.
        let keys = view.beatGlow.container.animationKeys() ?? []
        #expect(keys.count >= 2)
        for key in keys {
            let animation = try #require(view.beatGlow.container.animation(forKey: key))
            #expect(animation.preferredFrameRateRange == Motion.Halo.hitFrameRateRange, "\(key)")
        }
    }

    @Test func withTheLookOnGlowNothingChanges() {
        let rig = Rig()
        let view = Self.makeView()
        view.laserStage = rig.stage
        view.apply(state: Self.state(look: .glow))
        view.applyBeat(IslandBeatFrame(low: 0.6, mid: 0, high: 0, hit: .kick))

        #expect(rig.surfaces.isEmpty)
        #expect(view.beatGlow.punches == 1)
        #expect(abs(view.beatGlow.lastPunch - 0.6) < 0.000_1)
    }

    @Test func switchingToLasersPutsTheGlowBackAtRest() {
        let view = Self.makeView()
        view.apply(state: Self.state(look: .glow))
        view.applyBeat(IslandBeatFrame(low: 1, mid: 1, high: 0, hit: .kick))
        #expect(view.beatGlow.punches == 1)

        view.apply(state: Self.state(look: .lasers))

        // A faint base: the pulse's rest, with nothing reaching out.
        #expect(view.beatGlow.isActive)
        #expect(CATransform3DIsIdentity(view.beatGlow.container.transform))
        #expect(abs(Double(view.beatGlow.container.opacity) - 0.25) < 0.000_1)
        #expect(view.beatGlow.container.animation(forKey: "beat.scale") == nil)
    }

    @Test func aStateThatIsNotALasersPulseClosesTheWindow() {
        let rig = Rig()
        rig.show(Self.pulse())
        let view = Self.makeView()
        view.laserStage = rig.stage

        // Handing the stage to a view with no pulse closes what was open.
        #expect(!rig.stage.isShowing)
        #expect(rig.surfaces[0].closeCount == 1)
    }

    // MARK: The look in the resolver

    @Test func theLookGoesFromTheDisplaysChoiceToThePulse() {
        var inputs = IslandHaloInputs(
            style: .subtle, policy: .full, isOpened: false, waiting: nil, flashToken: nil,
            noticeTint: nil, musicTint: IslandHaloRGB.rgb255(10, 200, 30), isRunning: false,
            isMusicPlaying: true, pulsesWithBeat: true
        )
        guard case let .pulse(glow) = IslandHaloState.resolve(inputs).motion else {
            Issue.record("No pulse")
            return
        }
        #expect(glow.look == .glow)
        #expect(glow.tint == IslandHaloRGB.rgb255(10, 200, 30))

        inputs.pulseLook = .lasers
        guard case let .pulse(lasers) = IslandHaloState.resolve(inputs).motion else {
            Issue.record("No pulse")
            return
        }
        #expect(lasers.look == .lasers)
    }

    @Test func reduceMotionAndLowPowerShowTodaysGlowInPlaceOfLasers() {
        for policy in [IslandMotionPolicy.reduced, .conserving, .minimal] {
            var inputs = IslandHaloInputs(
                style: .vivid, policy: policy, isOpened: false, waiting: nil, flashToken: nil,
                noticeTint: nil, musicTint: IslandHaloRGB.rgb255(10, 200, 30), isRunning: false,
                isMusicPlaying: true, pulsesWithBeat: true
            )
            inputs.pulseLook = .lasers
            let withLasers = IslandHaloState.resolve(inputs)
            inputs.pulseLook = .glow
            inputs.pulsesWithBeat = false

            // No pulse at all, which is no lasers: the glow it always was.
            #expect(withLasers == IslandHaloState.resolve(inputs))
            if case .pulse = withLasers.motion { Issue.record("A pulse under \(policy)") }
        }
    }
}
