import Foundation
import Testing
@testable import OpenIslandApp

/// When Hangover listens, what the pulse's colors are, and how the switch
/// is saved (D56).
struct IslandBeatRulesTests {
    private static func inputs(
        isSwitchOn: Bool = true,
        style: IslandHaloStyle = .subtle,
        followsMusic: Bool = true,
        isMusicPlaying: Bool = true,
        policy: IslandMotionPolicy = .full,
        islandShowsMusic: Bool = true,
        isIslandClosed: Bool = true,
        isScreenOn: Bool = true
    ) -> IslandBeatListeningInputs {
        IslandBeatListeningInputs(
            isSwitchOn: isSwitchOn, style: style, followsMusic: followsMusic,
            isMusicPlaying: isMusicPlaying, policy: policy, islandShowsMusic: islandShowsMusic,
            isIslandClosed: isIslandClosed, isScreenOn: isScreenOn
        )
    }

    // MARK: The listening rule

    @Test func itListensWhenEverythingHolds() {
        #expect(IslandBeatRules.decision(Self.inputs()) == .listen)
        #expect(IslandBeatRules.decision(Self.inputs(style: .vivid)) == .listen)
        #expect(IslandBeatRules.shouldListen(Self.inputs()))
    }

    @Test func theseStopTheTapAtOnce() {
        let stops: [(String, IslandBeatListeningInputs)] = [
            ("the switch is off", Self.inputs(isSwitchOn: false)),
            ("the glow is off", Self.inputs(style: .off)),
            ("glow with music is off", Self.inputs(followsMusic: false)),
            ("Reduce Motion", Self.inputs(policy: .reduced)),
            ("Low Power or a serious thermal state", Self.inputs(policy: .conserving)),
            ("a critical thermal state", Self.inputs(policy: .minimal)),
            ("the screen is locked, asleep or another user's", Self.inputs(isScreenOn: false)),
            ("a timer or a swipe took the island from the music", Self.inputs(islandShowsMusic: false)),
        ]
        for (reason, inputs) in stops {
            #expect(IslandBeatRules.decision(inputs) == .stop, "\(reason)")
            #expect(!IslandBeatRules.shouldListen(inputs), "\(reason)")
        }
    }

    @Test func aPauseAndAnOpenIslandLeaveTheTapAGraceTime() {
        #expect(IslandBeatRules.decision(Self.inputs(isMusicPlaying: false)) == .linger)
        #expect(IslandBeatRules.decision(Self.inputs(isIslandClosed: false)) == .linger)
        #expect(IslandBeatRules.decision(Self.inputs(isMusicPlaying: false, isIslandClosed: false)) == .linger)
        // Neither is listening.
        #expect(!IslandBeatRules.shouldListen(Self.inputs(isMusicPlaying: false)))
        #expect(!IslandBeatRules.shouldListen(Self.inputs(isIslandClosed: false)))
        // And a pause with the screen locked is no grace at all.
        #expect(IslandBeatRules.decision(Self.inputs(isMusicPlaying: false, isScreenOn: false)) == .stop)
        #expect(IslandBeatRules.decision(Self.inputs(isSwitchOn: false, isIslandClosed: false)) == .stop)
    }

    @Test func theRuleHoldsOverEveryCombination() {
        let policies: [IslandMotionPolicy] = [.full, .reduced, .conserving, .minimal]
        let flags = [true, false]
        for isSwitchOn in flags {
            for style in IslandHaloStyle.allCases {
                for followsMusic in flags {
                    for isMusicPlaying in flags {
                        for policy in policies {
                            for showsMusic in flags {
                                for isClosed in flags {
                                    for isScreenOn in flags {
                                        let inputs = Self.inputs(
                                            isSwitchOn: isSwitchOn, style: style, followsMusic: followsMusic,
                                            isMusicPlaying: isMusicPlaying, policy: policy,
                                            islandShowsMusic: showsMusic, isIslandClosed: isClosed,
                                            isScreenOn: isScreenOn
                                        )
                                        let hard = isSwitchOn && style != .off && followsMusic
                                            && policy == .full && showsMusic && isScreenOn
                                        let expected: IslandBeatDecision = !hard
                                            ? .stop
                                            : (isMusicPlaying && isClosed ? .listen : .linger)
                                        #expect(IslandBeatRules.decision(inputs) == expected)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func theSystemPoliciesThatSayNoAreTheOnesMacOSCanSet() {
        // Reduce Motion, Low Power Mode and a serious thermal state, each
        // alone, as the monitor resolves them.
        let reduceMotion = IslandMotionPolicy.resolve(reduceMotion: true, lowPower: false, thermal: .nominal)
        let lowPower = IslandMotionPolicy.resolve(reduceMotion: false, lowPower: true, thermal: .nominal)
        let hot = IslandMotionPolicy.resolve(reduceMotion: false, lowPower: false, thermal: .serious)
        let fine = IslandMotionPolicy.resolve(reduceMotion: false, lowPower: false, thermal: .fair)

        #expect(!IslandBeatRules.allowsPulse(reduceMotion))
        #expect(!IslandBeatRules.allowsPulse(lowPower))
        #expect(!IslandBeatRules.allowsPulse(hot))
        #expect(IslandBeatRules.allowsPulse(fine))
    }

    @Test func theOffInputsNeverListen() {
        #expect(IslandBeatRules.decision(.off) == .stop)
        #expect(!IslandBeatListeningInputs.off.isSwitchOn)
    }

    // MARK: How often it may flash

    @Test func byDefaultTheFlashesFollowTheHits() {
        let rule = IslandFlashRule.rule(dimsFlashingLights: false)

        #expect(rule == .followsHits)
        #expect(rule.gap == 0.07)
        #expect(rule.mostASecond == nil)
        // A roll a tenth of a second apart: every hit, for as long as it goes.
        var shown: [TimeInterval] = []
        for step in 0..<50 {
            let time = Double(step) * 0.1
            #expect(rule.allows(at: time, after: shown))
            shown.append(time)
        }
        // Only a hit inside the gap is turned away.
        #expect(!rule.allows(at: 4.95, after: shown))
        #expect(rule.allows(at: 4.98, after: shown))
    }

    @Test func aUserWhoAskedMacOSToDimFlashingLightsGetsThreeASecond() {
        let rule = IslandFlashRule.rule(dimsFlashingLights: true)

        #expect(rule == .dimmed)
        #expect(rule.mostASecond == 3)
        #expect(rule.gap == 0.25)
        #expect(rule.allows(at: 0, after: []))
        #expect(!rule.allows(at: 0.2, after: [0]))
        #expect(rule.allows(at: 0.3, after: [0]))
        #expect(rule.allows(at: 0.6, after: [0, 0.3]))
        // A fourth inside the second is turned away, and let through when
        // the first is a second old.
        #expect(!rule.allows(at: 0.9, after: [0, 0.3, 0.6]))
        #expect(rule.allows(at: 1.0, after: [0, 0.3, 0.6]))
    }

    // MARK: The screen

    @Test func theScreenIsOnOnlyWhileSomebodyCanSeeIt() {
        var state = IslandScreenState()
        #expect(state.isOn)

        let pairs: [(IslandScreenState.Event, IslandScreenState.Event)] = [
            (.willSleep, .didWake),
            (.screensDidSleep, .screensDidWake),
            (.locked, .unlocked),
            (.sessionResigned, .sessionBecameActive),
        ]
        for (away, back) in pairs {
            state.note(away)
            #expect(!state.isOn)
            state.note(back)
            #expect(state.isOn)
        }
    }

    @Test func aMacThatWakesBehindItsLockScreenIsStillNotOn() {
        var state = IslandScreenState()
        // The lid closes: the screens sleep, the Mac locks and sleeps.
        state.note(.screensDidSleep)
        state.note(.locked)
        state.note(.willSleep)
        // It wakes to the lock screen.
        state.note(.didWake)
        state.note(.screensDidWake)
        #expect(!state.isOn)
        state.note(.unlocked)
        #expect(state.isOn)
        // Another user takes the Mac, with this one's screen never locked.
        state.note(.sessionResigned)
        #expect(!state.isOn)
    }

    @Test @MainActor func theMonitorPassesTheStateOn() {
        let presence = IslandScreenPresence()
        #expect(presence.isOn)
        presence.note(.locked)
        #expect(!presence.isOn)
        presence.note(.screensDidSleep)
        presence.note(.unlocked)
        #expect(!presence.isOn)
        presence.note(.screensDidWake)
        #expect(presence.isOn)
    }

    // MARK: The colors

    @Test func theFourColorsSitAroundTheArtsOwn() {
        let art = NookArtworkPalette.rgb(hue: 0.6, saturation: 0.8, brightness: 0.95)
        let hues = IslandBeatHues.hues(around: art).map { NookArtworkPalette.hsb(of: $0).hue }

        #expect(hues.count == 4)
        let expected = [0.46, 0.65, 0.55, 0.74]
        #expect(zip(hues, expected).allSatisfy { abs($0 - $1) < 0.005 })
        // Two on each side of the art's color.
        #expect(hues.filter { $0 < 0.6 }.count == 2)
        #expect(hues.filter { $0 > 0.6 }.count == 2)
    }

    @Test func aColorNearTheEndOfTheWheelWrapsAround() {
        let red = NookArtworkPalette.rgb(hue: 0.02, saturation: 0.9, brightness: 1)
        let hues = IslandBeatHues.hues(around: red).map { NookArtworkPalette.hsb(of: $0).hue }

        #expect(hues.allSatisfy { (0..<1).contains($0) })
        #expect(abs(hues[0] - 0.88) < 0.005)
        #expect(abs(hues[3] - 0.16) < 0.005)
    }

    @Test func everyStepOfTheBeatIsAVisibleChange() {
        let offsets = IslandBeatHues.offsets
        for index in offsets.indices {
            let next = offsets[(index + 1) % offsets.count]
            #expect(abs(next - offsets[index]) >= 0.09)
        }
    }

    @Test func paleArtStillGivesColorsStrongEnoughToSee() {
        let pale = NookArtworkPalette.rgb(hue: 0.3, saturation: 0.25, brightness: 0.5)
        for color in IslandBeatHues.hues(around: pale) {
            let hsb = NookArtworkPalette.hsb(of: color)
            #expect(hsb.saturation >= IslandBeatHues.saturationFloor - 0.001)
            #expect(hsb.brightness >= IslandBeatHues.brightnessFloor - 0.001)
        }
    }

    @Test func grayOrMissingArtUsesMagentaCyanPurpleAndGreen() {
        let fixed = [
            IslandHaloRGB(rgb: 0xFF3DCB), IslandHaloRGB(rgb: 0x32E6FF),
            IslandHaloRGB(rgb: 0xA259FF), IslandHaloRGB(rgb: 0x4DFF88),
        ]

        #expect(IslandBeatHues.hues(around: nil) == fixed)
        #expect(IslandBeatHues.hues(around: IslandHaloRGB(red: 0.5, green: 0.5, blue: 0.5)) == fixed)
        #expect(IslandBeatHues.hues(around: IslandHaloRGB(red: 0.52, green: 0.5, blue: 0.5)) == fixed)
        // Named for what they are: each sits in its part of the wheel.
        let hues = fixed.map { NookArtworkPalette.hsb(of: $0).hue }
        #expect((0.85...0.95).contains(hues[0]))
        #expect((0.48...0.56).contains(hues[1]))
        #expect((0.70...0.80).contains(hues[2]))
        #expect((0.33...0.43).contains(hues[3]))
    }

    // MARK: The switch

    @Test func theSwitchIsOffUnlessTheUserTurnsItOn() {
        #expect(NookDisplayPreferences().haloPulsesWithBeat == false)
        #expect(NookDisplayPreferences.load(for: .notch, defaults: MemoryDefaults()).haloPulsesWithBeat == false)
    }

    @Test func settingsSavedBeforeTheSwitchExistedDecodeWithItOff() {
        // What a copy from before this version left behind: every other
        // glow choice, and no key for the pulse.
        let defaults = MemoryDefaults()
        defaults.set(IslandHaloStyle.vivid.rawValue, forKey: "nook.display.notch.haloStyle")
        defaults.set(true, forKey: "nook.display.notch.haloFollowsMusic")
        defaults.set(NookClosedMediaStyle.artAndVisual.rawValue, forKey: "nook.display.notch.mediaStyle")

        let loaded = NookDisplayPreferences.load(for: .notch, defaults: defaults)

        #expect(loaded.haloStyle == .vivid)
        #expect(loaded.haloFollowsMusic)
        #expect(loaded.haloPulsesWithBeat == false)
    }

    @Test func theSwitchIsSavedForItsOwnDisplayUnderOneKey() {
        let defaults = MemoryDefaults()
        let old = NookDisplayPreferences()
        old.persist(for: .notch, defaults: defaults)
        old.persist(for: .topBar, defaults: defaults)
        let before = defaults.all
        var new = old
        new.haloPulsesWithBeat = true

        new.persistChanges(from: old, for: .notch, defaults: defaults)

        let changed = defaults.all.filter { key, value in
            (before[key] as? NSObject) != (value as? NSObject)
        }
        #expect(Array(changed.keys) == ["nook.display.notch.haloPulsesWithBeat"])
        #expect(NookDisplayPreferences.load(for: .notch, defaults: defaults).haloPulsesWithBeat)
        #expect(NookDisplayPreferences.load(for: .topBar, defaults: defaults).haloPulsesWithBeat == false)
    }

    @Test func aLayoutTemplateLeavesTheSwitchAlone() throws {
        let template = try #require(PersonalizationTemplate.all.first)
        var mine = NookDisplayPreferences()
        mine.haloPulsesWithBeat = true

        // Applying a layout does not switch the pulse off.
        mine.haloPulseReach = 0.85
        let applied = template.applying(to: mine)
        #expect(applied.haloPulsesWithBeat)
        #expect(applied.haloPulseReach == 0.85)
        // And a display with the pulse on still counts as on that layout.
        #expect(template.matches(appearance: template.appearance, nook: applied))
        let setup = PersonalizationSetup(appearance: template.appearance, nook: applied)
        #expect(setup.appliedTemplateID == template.id)

        // Undo goes back to the earlier layout and keeps today's answer.
        var earlier = PersonalizationSetup(appearance: template.appearance, nook: NookDisplayPreferences())
        earlier.nook.haloPulsesWithBeat = false
        #expect(setup.undoing(earlier).nook.haloPulsesWithBeat)
    }

    // MARK: How far it reaches

    @Test func theReachMapsToHowFarThePeakGoes() {
        // Today's peak is 1. At 0 it barely grows, the default goes about
        // 40 percent further, and 1 goes about 2.2 times as far.
        #expect(abs(IslandBeatReach.peakFactor(0) - 1.05) < 0.000_1)
        #expect(abs(IslandBeatReach.peakFactor(IslandBeatReach.standard) - 1.4) < 0.000_1)
        #expect(abs(IslandBeatReach.peakFactor(1) - 2.2) < 0.000_1)
        #expect(IslandBeatReach.standard == 0.5)
    }

    @Test func aLargerReachNeverGoesLessFar() {
        var last = IslandBeatReach.peakFactor(0)
        for step in 1...100 {
            let factor = IslandBeatReach.peakFactor(Double(step) / 100)
            #expect(factor > last)
            last = factor
        }
    }

    @Test func aReachOutsideZeroToOneIsHeldInside() {
        #expect(IslandBeatReach.peakFactor(-3) == IslandBeatReach.peakFactor(0))
        #expect(IslandBeatReach.peakFactor(40) == IslandBeatReach.peakFactor(1))
        #expect(IslandBeatReach.clamped(-0.1) == 0)
        #expect(IslandBeatReach.clamped(1.5) == 1)
        #expect(IslandBeatReach.clamped(0.3) == 0.3)
        #expect(IslandBeatReach.clamped(.nan) == IslandBeatReach.standard)
        #expect(IslandBeatReach.clamped(.infinity) == IslandBeatReach.standard)
    }

    @Test func theScaleTakesTheGlowsEdgeToTheFactor() {
        // A pill 300 wide and 34 high with a glow 18 out, at 2.2 times.
        let wide = IslandBeatReach.peakScale(half: 150, radius: 18, factor: 2.2)
        let high = IslandBeatReach.peakScale(half: 17, radius: 18, factor: 2.2)

        // The scaled edge is 2.2 times 18 past the pill on both sides.
        #expect(abs(wide * (150 + 18) - 150 - 2.2 * 18) < 0.000_1)
        #expect(abs(high * (17 + 18) - 17 - 2.2 * 18) < 0.000_1)
        #expect(IslandBeatReach.peakScale(half: 150, radius: 18, factor: 1) == 1)
        #expect(IslandBeatReach.peakScale(half: 0, radius: 0, factor: 2) == 1)
    }

    @MainActor @Test func theLargestReachStillFitsTheGlowsDrawingArea() {
        let area = IslandHaloLayerView.maxSpread
        // Every closed island the app draws: a menu bar's height to a tall
        // notch's, a narrow pill to the widest.
        for metrics in [IslandHaloMetrics.subtle, .vivid] {
            for height in stride(from: CGFloat(22), through: 44, by: 2) {
                for width in stride(from: CGFloat(120), through: 520, by: 40) {
                    for (half, drop) in [(width / 2, CGFloat(0)), (height / 2, metrics.drop)] {
                        let scale = IslandBeatReach.peakScale(
                            half: half, radius: metrics.radius, factor: IslandBeatReach.peakFactor(1)
                        )
                        let painted = IslandBeatReach.outerExtent(
                            half: half, radius: metrics.radius, drop: drop, scale: scale
                        )
                        #expect(painted <= area, "\(width) by \(height)")
                        // And the pulse holds itself to it without being asked.
                        let fitted = IslandBeatReach.fittedScale(
                            half: half, radius: metrics.radius, drop: drop, reach: 1, room: area
                        )
                        #expect(fitted == scale)
                    }
                }
            }
        }
        // The resting glows fit as they always did.
        #expect(area >= IslandHaloMetrics.vivid.radius * 2 + IslandHaloMetrics.vivid.drop)
    }

    @Test func aGlowNeverPaintsPastItsRoom() {
        for room in [CGFloat(0), 6, 18, 40, 80, 400] {
            for reach in [0.0, 0.5, 1] {
                for half in [CGFloat(11), 17, 150] {
                    let scale = IslandBeatReach.fittedScale(half: half, radius: 18, drop: 5, reach: reach, room: room)
                    let painted = IslandBeatReach.outerExtent(half: half, radius: 18, drop: 5, scale: scale)
                    #expect(scale >= 1)
                    // Never past the room, unless the resting glow is
                    // already past it, which the pulse does not add to.
                    #expect(painted <= max(room, 18 * 2 + 5) + 0.000_1)
                    #expect(scale <= IslandBeatReach.peakScale(
                        half: half, radius: 18, factor: IslandBeatReach.peakFactor(reach)
                    ))
                }
            }
        }
    }

    @Test func theRoomIsTheWindowAroundTheClosedPill() {
        // The window is the opened island's size, bottom-up: 676 wide and
        // 262 high, with a pill 274 wide and 32 high at its top center.
        let window = CGSize(width: 676, height: 262)
        let pill = CGRect(x: 201, y: 230, width: 274, height: 32)

        let room = IslandBeatReach.room(pill: pill, inWindowOfSize: window, limit: 80)
        #expect(room.side == 80)
        #expect(room.below == 80)
        // With more to use than the drawing area, the area is the limit.
        #expect(IslandBeatReach.room(pill: pill, inWindowOfSize: window, limit: 500).side == 201)
        #expect(IslandBeatReach.room(pill: pill, inWindowOfSize: window, limit: 500).below == 230)

        // A window barely wider than the pill, which the narrowest opened
        // island on an external display is: the nearer edge counts.
        let tight = IslandBeatReach.room(
            pill: CGRect(x: 18, y: 150, width: 360, height: 24), inWindowOfSize: CGSize(width: 400, height: 174), limit: 80
        )
        #expect(tight.side == 18)
        #expect(tight.below == 80)
        // A pill that is off its window has no room and never a negative one.
        let off = IslandBeatReach.room(
            pill: CGRect(x: -20, y: -5, width: 100, height: 24), inWindowOfSize: CGSize(width: 60, height: 40), limit: 80
        )
        #expect(off.side == 0)
        #expect(off.below == 0)
    }

    @Test func theReachIsSavedAndOldSettingsGetTheDefault() {
        let defaults = MemoryDefaults()
        // A copy from before the slider: the pulse on, and no reach.
        defaults.set(true, forKey: "nook.display.notch.haloPulsesWithBeat")
        #expect(NookDisplayPreferences.load(for: .notch, defaults: defaults).haloPulseReach == IslandBeatReach.standard)
        #expect(NookDisplayPreferences().haloPulseReach == IslandBeatReach.standard)

        var mine = NookDisplayPreferences.load(for: .notch, defaults: defaults)
        let before = mine
        mine.haloPulseReach = 0.8
        mine.persistChanges(from: before, for: .notch, defaults: defaults)
        #expect(defaults.object(forKey: "nook.display.notch.haloPulseReach") as? Double == 0.8)
        #expect(NookDisplayPreferences.load(for: .notch, defaults: defaults).haloPulseReach == 0.8)
        #expect(NookDisplayPreferences.load(for: .topBar, defaults: defaults).haloPulseReach == IslandBeatReach.standard)

        // A number nobody could have set with the slider is held inside.
        defaults.set(7.5, forKey: "nook.display.notch.haloPulseReach")
        #expect(NookDisplayPreferences.load(for: .notch, defaults: defaults).haloPulseReach == 1)
        defaults.set("far", forKey: "nook.display.notch.haloPulseReach")
        #expect(NookDisplayPreferences.load(for: .notch, defaults: defaults).haloPulseReach == IslandBeatReach.standard)
    }

    @Test func draggingTheReachDoesNotCountAsAChangeToThePage() {
        var dragged = NookDisplayPreferences()
        dragged.haloPulseReach = 0.9
        #expect(!dragged.changesThePage(from: NookDisplayPreferences()))
    }

    @Test func theSwitchRoundTripsThroughAFullSave() {
        let defaults = MemoryDefaults()
        var preferences = NookDisplayPreferences()
        preferences.haloPulsesWithBeat = true

        preferences.persist(for: .topBar, defaults: defaults)

        #expect(NookDisplayPreferences.load(for: .topBar, defaults: defaults) == preferences)
    }
}

/// The resolver's music glow with and without the listener (D56).
struct IslandBeatHaloStateTests {
    private static let art = IslandHaloRGB.rgb255(10, 200, 30)

    private static func inputs(
        style: IslandHaloStyle = .subtle,
        policy: IslandMotionPolicy = .full,
        isOpened: Bool = false,
        waiting: IslandWaitingKind? = nil,
        flashToken: UInt64? = nil,
        noticeTint: IslandHaloRGB? = nil,
        musicTint: IslandHaloRGB? = IslandBeatHaloStateTests.art,
        isMusicPlaying: Bool = true,
        pulsesWithBeat: Bool = true
    ) -> IslandHaloInputs {
        IslandHaloInputs(
            style: style, policy: policy, isOpened: isOpened, waiting: waiting, flashToken: flashToken,
            noticeTint: noticeTint, musicTint: musicTint, isRunning: false,
            isMusicPlaying: isMusicPlaying, pulsesWithBeat: pulsesWithBeat
        )
    }

    @Test func whileTheListenerRunsTheMusicGlowIsAPulse() {
        let state = IslandHaloState.resolve(Self.inputs())
        let hues = IslandBeatHues.hues(around: Self.art)

        #expect(state.source == .music)
        #expect(state.motion == .pulse(IslandHaloPulse(
            low: IslandHaloMetrics.subtle.pulseLow, high: IslandHaloMetrics.subtle.pulseHigh, hues: hues, tint: Self.art
        )))
        #expect(state.color == hues[0])
        #expect(state.restOpacity == IslandHaloMetrics.subtle.pulseLow)
        #expect(state.radius == IslandHaloMetrics.subtle.radius)
        #expect(state.isVisible)
    }

    @Test func theReachGoesFromTheDisplaysChoiceToThePulse() {
        func reach(_ value: Double) -> Double? {
            var inputs = Self.inputs()
            inputs.pulseReach = value
            guard case let .pulse(pulse) = IslandHaloState.resolve(inputs).motion else { return nil }
            return pulse.reach
        }

        #expect(reach(0.2) == 0.2)
        #expect(reach(1) == 1)
        #expect(reach(9) == 1)
        #expect(reach(-1) == 0)
        // The default input is the standard reach.
        guard case let .pulse(pulse) = IslandHaloState.resolve(Self.inputs()).motion else {
            Issue.record("No pulse")
            return
        }
        #expect(pulse.reach == IslandBeatReach.standard)
    }

    @Test func vividPulsesFurtherThanSubtle() {
        let subtle = IslandHaloMetrics.subtle
        let vivid = IslandHaloMetrics.vivid

        #expect(subtle.pulseLow < subtle.pulseHigh)
        #expect(vivid.pulseLow < vivid.pulseHigh)
        #expect(vivid.pulseHigh > subtle.pulseHigh)
        #expect(vivid.pulseHigh <= 1)
        guard case let .pulse(pulse) = IslandHaloState.resolve(Self.inputs(style: .vivid)).motion else {
            Issue.record("Vivid did not pulse")
            return
        }
        #expect(pulse.low == vivid.pulseLow)
        #expect(pulse.high == vivid.pulseHigh)
    }

    @Test func withoutTheListenerTheGlowIsExactlyTodaysMusicGlow() {
        let today = IslandHaloState.resolve(Self.inputs(pulsesWithBeat: false))

        #expect(today.motion == .drift(period: Motion.Halo.driftPeriod))
        #expect(today.color == Self.art)
        #expect(today.restOpacity == IslandHaloMetrics.subtle.musicOpacity)
    }

    @Test func reduceMotionKeepsTodaysGlowEvenIfAListenerWereRunning() {
        for policy in [IslandMotionPolicy.reduced, .conserving, .minimal] {
            let pulsing = IslandHaloState.resolve(Self.inputs(policy: policy, pulsesWithBeat: true))
            let today = IslandHaloState.resolve(Self.inputs(policy: policy, pulsesWithBeat: false))
            #expect(pulsing == today)
        }
    }

    @Test func artWithNoColorStillPulsesInTheFixedFour() {
        let state = IslandHaloState.resolve(Self.inputs(musicTint: nil))

        #expect(state.source == .music)
        guard case let .pulse(pulse) = state.motion else {
            Issue.record("Gray art did not pulse")
            return
        }
        #expect(pulse.hues == IslandBeatHues.fixed)
    }

    @Test func aListenerWithNoMusicOnTheIslandPulsesNothing() {
        let state = IslandHaloState.resolve(Self.inputs(musicTint: nil, isMusicPlaying: false))
        #expect(state == .off)
    }

    @Test func everythingThatOutranksMusicOutranksThePulse() {
        #expect(IslandHaloState.resolve(Self.inputs(waiting: .approval)).source == .approval)
        #expect(IslandHaloState.resolve(Self.inputs(waiting: .question)).source == .question)
        #expect(IslandHaloState.resolve(Self.inputs(flashToken: 4)).source == .completed)
        #expect(IslandHaloState.resolve(Self.inputs(noticeTint: .approval)).source == .notice)
        #expect(IslandHaloState.resolve(Self.inputs(style: .off)) == .off)
        #expect(IslandHaloState.resolve(Self.inputs(isOpened: true)) == .off)
    }

    @Test func aStillPictureOfAPulseShowsItAtRest() {
        let state = IslandHaloState.resolve(Self.inputs())
        #expect(IslandHaloStillGlow.opacity(for: state) == IslandHaloMetrics.subtle.pulseLow)
    }
}
