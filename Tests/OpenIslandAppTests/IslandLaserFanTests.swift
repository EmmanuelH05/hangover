import CoreGraphics
import Foundation
import Testing
@testable import OpenIslandApp

/// The lasers as plain numbers (D56): the fan, what a hit does to it, the
/// room it needs and the saved choice. No window, no layer and no sound.
@Suite struct IslandLaserFanTests {
    private static let notchWidth = 200.0
    /// A notch 200 points wide with 700 to each side and 900 below it.
    private static let space = IslandLaserSpace(notchWidth: notchWidth, left: 700, right: 700, down: 900)
    private static let red = IslandHaloRGB(rgb: 0xE0245E)
    private static let degrees = 180 / Double.pi
    private static let counts = [IslandLaserCount.least, IslandLaserCount.standard, IslandLaserCount.most]
    /// The four fan shapes, flat on the screen.
    private static let leaning: [IslandLaserArrangement] = [.fan, .wings, .comb, .crossed]

    private static func lineup(
        _ arrangement: IslandLaserArrangement = .fan,
        count: Int = IslandLaserCount.standard,
        reach: Double = IslandBeatReach.standard
    ) -> IslandLaserLineup {
        arrangement.lineup(count: count, space: space, reach: reach)
    }

    private static func fan(
        low: Double,
        mid: Double = 0,
        hit: IslandBeatHit? = nil,
        arrangement: IslandLaserArrangement = .fan,
        count: Int = IslandLaserCount.standard,
        reach: Double = IslandBeatReach.standard,
        nudges: [Double] = [],
        time: TimeInterval = 0
    ) -> IslandLaserFan {
        IslandLaserFan(
            frame: IslandBeatFrame(low: low, mid: mid, hit: hit),
            reach: reach,
            tint: red,
            lineup: lineup(arrangement, count: count, reach: reach),
            hueIndex: 0,
            nudges: nudges,
            time: time
        )
    }

    // MARK: The fan

    @Test func theBassSetsHowLongTheBeamsAreAtThreeLevels() {
        let quiet = Self.fan(low: 0)
        let half = Self.fan(low: 0.5)
        let full = Self.fan(low: 1)
        let stands = Self.lineup().stands
        #expect(quiet.beams.count == IslandLaserCount.standard)
        #expect(stands.count == IslandLaserCount.standard)
        for index in stands.indices {
            #expect(quiet.beams[index].length < half.beams[index].length)
            #expect(half.beams[index].length < full.beams[index].length)
            let whole = IslandLaserLimits.standardLength * stands[index].share
            #expect(abs(full.beams[index].length - whole) < 0.0001)
            #expect(abs(quiet.beams[index].length - whole * IslandLaserLimits.restingShare) < 0.0001)
            // The start follows the notch's edge, and never leaves it.
            #expect(abs(full.beams[index].start) <= Self.notchWidth / 2)
            #expect(abs(full.beams[index].start - stands[index].start) < 0.0001)
        }
        #expect(quiet.beams[0].brightness < half.beams[0].brightness)
        #expect(half.beams[0].brightness < full.beams[0].brightness)
        #expect(quiet.haze < full.haze)
        for fan in [quiet, half, full] {
            #expect(!fan.landsAtOnce)
            for beam in fan.beams {
                #expect((0...1).contains(beam.brightness))
                #expect(abs(beam.lean) <= IslandLaserLimits.widestLean)
            }
        }
    }

    @Test func theMidsMakeTheBeamsBrighterAndNeverPastFull() {
        #expect(Self.fan(low: 0.3, mid: 0.8).beams[0].brightness > Self.fan(low: 0.3).beams[0].brightness)
        #expect(Self.fan(low: 1, mid: 1).beams[0].brightness == 1)
        // A level that is not a number is no level.
        #expect(Self.fan(low: .nan, mid: .infinity) == Self.fan(low: 0, mid: 0))
        #expect(Self.fan(low: 7) == Self.fan(low: 1))
    }

    @Test func theReachScalesTheBeams() {
        func longest(_ reach: Double) -> Double {
            Self.fan(low: 1, reach: reach).beams.map(\.length).max() ?? 0
        }
        #expect(abs(longest(0) - IslandLaserLimits.leastLength) < 0.0001)
        #expect(abs(longest(0.5) - IslandLaserLimits.standardLength) < 0.0001)
        #expect(abs(longest(1) - IslandLaserLimits.mostLength) < 0.0001)
        var last = 0.0
        for step in 0...20 {
            let length = longest(Double(step) / 20)
            #expect(length > last)
            last = length
        }
        // Outside 0 to 1 is held to an end, and a reach that is no number
        // is the standard.
        #expect(longest(-3) == longest(0))
        #expect(longest(9) == longest(1))
        #expect(longest(.nan) == longest(IslandBeatReach.standard))
    }

    // MARK: Hits

    @Test func aKickIsTheBassAtItsTopAndLandsAtOnce() {
        let kick = Self.fan(low: 0.2, hit: .kick)
        let full = Self.fan(low: 1)
        #expect(kick.landsAtOnce)
        #expect(kick.beams.map(\.length) == full.beams.map(\.length))
        #expect(kick.beams[0].brightness >= 0.9)
        #expect(Self.fan(low: 0.2, hit: .snare).beams[0].brightness == 1)
        #expect(Self.fan(low: 0.2, hit: .hat).landsAtOnce)
    }

    @Test func aSnareMovesTheFanToTheNextArrangementAndTheNextColor() {
        var score = IslandLaserScore()
        let frame = IslandBeatFrame(low: 0.5)
        let first = score.fan(for: frame, reach: 0.5, tint: Self.red, space: Self.space, time: 0)
        #expect(score.arrangementIndex == 0)
        #expect(score.arrangement == .fan)
        #expect(first.beams.count == IslandLaserCount.standard)

        let hit = IslandBeatFrame(low: 0.5, mid: 1, hit: .snare)
        let second = score.fan(for: hit, reach: 0.5, tint: Self.red, space: Self.space, time: 0.5)
        #expect(score.arrangementIndex == 1)
        #expect(score.arrangement == IslandLaserArrangement.all[1])
        #expect(score.hueIndex == 1)
        #expect(second.landsAtOnce)
        // The same beams, standing another way: another shape, and out of
        // the screen toward the viewer where the first was flat.
        #expect(second.beams.count == first.beams.count)
        #expect(second.beams.map(\.lean) != first.beams.map(\.lean))
        #expect(first.tilt == 0)
        #expect(second.tilt == IslandLaserTilt.standard)
        #expect(second.color != first.color)
        #expect(second.color == IslandBeatHues.hues(around: Self.red)[1])

        // Every arrangement shows once, each shape flat and toward the
        // viewer, and then the first one is back. The colors go around in
        // four.
        var seen = [score.arrangement]
        var colors = [second.color]
        for step in 2...IslandLaserArrangement.all.count {
            colors.append(
                score.fan(for: hit, reach: 0.5, tint: Self.red, space: Self.space, time: Double(step) / 2).color
            )
            seen.append(score.arrangement)
        }
        #expect(seen == Array(IslandLaserArrangement.all.dropFirst()) + [IslandLaserArrangement.all[0]])
        #expect(score.arrangementIndex == 0)
        #expect(score.hueIndex == IslandLaserArrangement.all.count % IslandBeatHues.offsets.count)
        #expect(Set(colors).count == 4)
        #expect(colors[3] == first.color)
    }

    @Test func theScoreMakesAsManyBeamsAsItIsAskedFor() {
        for count in Self.counts {
            var score = IslandLaserScore()
            for step in 0..<IslandLaserArrangement.all.count * 2 {
                let fan = score.fan(
                    for: IslandBeatFrame(low: 1, mid: 1, hit: .snare), reach: 0.5, tint: Self.red,
                    count: count, space: Self.space, time: Double(step)
                )
                #expect(fan.beams.count == count)
                #expect(score.nudges.count == count)
            }
        }
    }

    @Test func aKickOrAHatAloneNeverChangesTheArrangementOrTheColor() {
        var score = IslandLaserScore()
        let first = score.fan(
            for: IslandBeatFrame(low: 0.4), reach: 0.5, tint: Self.red, space: Self.space, time: 0
        )
        for step in 1...40 {
            let hit: IslandBeatHit = step.isMultiple(of: 4) ? .kick : .hat
            let fan = score.fan(
                for: IslandBeatFrame(low: 0.4, high: 1, hit: hit),
                reach: 0.5, tint: Self.red, space: Self.space, time: Double(step) * 0.05
            )
            #expect(fan.color == first.color)
            #expect(fan.beams.count == first.beams.count)
        }
        #expect(score.arrangementIndex == 0)
        #expect(score.hueIndex == 0)
    }

    @Test func aHatMovesOneBeamAndNeverPastItsCeiling() throws {
        var score = IslandLaserScore()
        let plain = Self.fan(low: 0.6)
        let hat = score.fan(
            for: IslandBeatFrame(low: 0.6, high: 1, hit: .hat),
            reach: 0.5, tint: Self.red, space: Self.space, time: 0
        )
        let moved = hat.beams.indices.filter { hat.beams[$0].length != plain.beams[$0].length }
        #expect(moved.count == 1)
        let index = try #require(moved.first)
        let ratio = hat.beams[index].length / plain.beams[index].length
        #expect(abs(ratio - (1 + IslandLaserLimits.hatCeiling)) < 0.0001)
        #expect(hat.beams.map(\.lean) == plain.beams.map(\.lean))

        // Hat after hat with no time between them, far louder than a level
        // can be: every beam stays inside the ceiling.
        var seenLonger = false
        var seenShorter = false
        for _ in 0..<60 {
            let fan = score.fan(
                for: IslandBeatFrame(low: 0.6, high: 50, hit: .hat),
                reach: 0.5, tint: Self.red, space: Self.space, time: 0
            )
            for beam in fan.beams.indices {
                let ratio = fan.beams[beam].length / plain.beams[beam].length
                #expect(ratio <= 1 + IslandLaserLimits.hatCeiling + 0.0001)
                #expect(ratio >= 1 - IslandLaserLimits.hatCeiling - 0.0001)
                seenLonger = seenLonger || ratio > 1.01
                seenShorter = seenShorter || ratio < 0.99
            }
        }
        #expect(seenLonger && seenShorter)

        // A nudge handed in from outside is held to the ceiling too.
        let wild = Self.fan(low: 0.6, nudges: Array(repeating: 4, count: plain.beams.count))
        for beam in wild.beams.indices {
            #expect(wild.beams[beam].length / plain.beams[beam].length <= 1 + IslandLaserLimits.hatCeiling + 0.0001)
        }
    }

    @Test func aSoftHatMovesABeamByHalfTheCeilingAndTheNudgeLetsGo() {
        var score = IslandLaserScore()
        let plain = Self.fan(low: 0.6)
        let soft = score.fan(
            for: IslandBeatFrame(low: 0.6, high: 0.1, hit: .hat),
            reach: 0.5, tint: Self.red, space: Self.space, time: 0
        )
        let ratios = soft.beams.indices.map { soft.beams[$0].length / plain.beams[$0].length }
        #expect(abs((ratios.max() ?? 0) - (1 + IslandLaserLimits.hatCeiling / 2)) < 0.0001)

        // A second later, with no hit, the beams are back to what the bass
        // alone gives at that moment.
        let later = score.fan(
            for: IslandBeatFrame(low: 0.6), reach: 0.5, tint: Self.red, space: Self.space, time: 1
        )
        let alone = Self.fan(low: 0.6, time: 1)
        for beam in later.beams.indices {
            #expect(abs(later.beams[beam].length - alone.beams[beam].length) < 0.01)
        }
        #expect(!later.landsAtOnce)
    }

    @Test func theSwayBetweenHitsIsSlow() {
        let step = 0.05
        var fastest = 0.0
        var widest = 0.0
        for arrangement in Self.leaning {
            let stands = Self.lineup(arrangement).stands
            var time = 0.0
            while time < IslandLaserLimits.driftPeriod * 2 {
                let now = Self.fan(low: 0.5, arrangement: arrangement, time: time)
                let next = Self.fan(low: 0.5, arrangement: arrangement, time: time + step)
                for beam in now.beams.indices {
                    fastest = max(fastest, abs(next.beams[beam].lean - now.beams[beam].lean) / step * Self.degrees)
                    widest = max(widest, abs(now.beams[beam].lean * Self.degrees - stands[beam].lean))
                }
                time += step
            }
        }
        #expect(fastest > 0)
        #expect(fastest <= IslandLaserLimits.mostDriftDegreesASecond)
        #expect(widest <= IslandLaserLimits.driftLean * Self.degrees + 0.0001)
    }

    @Test func artWithNoColorOfItsOwnUsesTheFixedFour() {
        var score = IslandLaserScore()
        let first = score.fan(for: IslandBeatFrame(low: 0.5), reach: 0.5, tint: nil, space: Self.space, time: 0)
        #expect(first.color == IslandBeatHues.fixed[0])
        let gray = IslandHaloRGB(red: 0.5, green: 0.5, blue: 0.5)
        let second = score.fan(
            for: IslandBeatFrame(low: 0.5, hit: .snare), reach: 0.5, tint: gray, space: Self.space, time: 0.5
        )
        #expect(second.color == IslandBeatHues.fixed[1])
    }

    // MARK: Room

    @Test func everyBeamThatLeansStaysInsideItsRoom() {
        let notch = CGRect(x: 400, y: 600, width: Self.notchWidth, height: 32)
        for reach in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let room = IslandLaserRoom.rect(reach: reach, notch: notch)
            #expect(room.contains(notch))
            for arrangement in Self.leaning {
                for count in Self.counts {
                    var outside = 0
                    var time = 0.0
                    while time < IslandLaserLimits.driftPeriod {
                        // The bass at its top and every beam nudged as far
                        // as a hat may nudge it.
                        let fan = Self.fan(
                            low: 1, hit: .kick, arrangement: arrangement, count: count, reach: reach,
                            nudges: Array(repeating: 1 + IslandLaserLimits.hatCeiling, count: count), time: time
                        )
                        for beam in fan.beams {
                            let start = CGPoint(x: notch.midX + beam.start, y: notch.minY)
                            let tip = CGPoint(
                                x: start.x + beam.length * sin(beam.lean),
                                y: start.y - beam.length * cos(beam.lean)
                            )
                            let soft = IslandLaserLimits.softHalfWidth
                            let isInside = tip.x - soft >= room.minX - 0.0001 && tip.x + soft <= room.maxX + 0.0001
                                && tip.y - soft >= room.minY - 0.0001 && tip.y <= room.maxY + 0.0001
                                && beam.length <= IslandLaserRoom.longestBeam(reach: reach) + 0.0001
                            if !isInside { outside += 1 }
                        }
                        time += 0.35
                    }
                    #expect(outside == 0, "\(arrangement.name) with \(count) beams at a reach of \(reach)")
                }
            }
        }
    }

    @Test func theRoomGrowsWithTheReachAndIsTheSameOnBothSides() {
        let notch = CGRect(x: 400, y: 600, width: Self.notchWidth, height: 32)
        let small = IslandLaserRoom.insets(reach: 0)
        let middle = IslandLaserRoom.insets(reach: 0.5)
        let large = IslandLaserRoom.insets(reach: 1)
        #expect(small.side < middle.side && middle.side < large.side)
        #expect(small.below < middle.below && middle.below < large.below)
        let rect = IslandLaserRoom.rect(reach: 1, notch: notch)
        #expect(abs((notch.minX - rect.minX) - (rect.maxX - notch.maxX)) < 0.0001)
        #expect(abs((notch.minX - rect.minX) - large.side) < 0.0001)
        #expect(abs((notch.minY - rect.minY) - large.below) < 0.0001)
        // Nothing is asked for above the notch.
        #expect(rect.maxY == notch.maxY)
    }

    // MARK: The saved choice

    @Test func theLookIsTheGlowUntilSomebodyPicksTheLasers() {
        #expect(NookDisplayPreferences().haloBeatLook == .glow)
        #expect(IslandBeatLook(storageValue: nil) == .glow)
        #expect(IslandBeatLook(storageValue: "strobe") == .glow)
        #expect(IslandBeatLook(storageValue: "lasers") == .lasers)

        let defaults = MemoryDefaults()
        // A copy from before the choice: the pulse on, a reach, and no look.
        defaults.set(true, forKey: "nook.display.notch.haloPulsesWithBeat")
        defaults.set(0.8, forKey: "nook.display.notch.haloPulseReach")
        #expect(NookDisplayPreferences.load(for: .notch, defaults: defaults).haloBeatLook == .glow)
        defaults.set("strobe", forKey: "nook.display.notch.haloBeatLook")
        #expect(NookDisplayPreferences.load(for: .notch, defaults: defaults).haloBeatLook == .glow)
        defaults.set(7, forKey: "nook.display.notch.haloBeatLook")
        #expect(NookDisplayPreferences.load(for: .notch, defaults: defaults).haloBeatLook == .glow)
    }

    @Test func theLookIsSavedForOneDisplayAndWritesOneKey() {
        let defaults = MemoryDefaults()
        var mine = NookDisplayPreferences.load(for: .notch, defaults: defaults)
        mine.persist(for: .notch, defaults: defaults)
        let before = mine
        let saved = defaults.all
        mine.haloBeatLook = .lasers
        mine.persistChanges(from: before, for: .notch, defaults: defaults)

        let changed = defaults.all.filter { key, value in (saved[key] as? NSObject) != (value as? NSObject) }
        #expect(Array(changed.keys) == ["nook.display.notch.haloBeatLook"])
        #expect(defaults.string(forKey: "nook.display.notch.haloBeatLook") == "lasers")
        #expect(NookDisplayPreferences.load(for: .notch, defaults: defaults).haloBeatLook == .lasers)
        #expect(NookDisplayPreferences.load(for: .topBar, defaults: defaults).haloBeatLook == .glow)
        // The look changes nothing on the Nook page.
        #expect(!mine.changesThePage(from: before))
    }

    @Test func aLayoutTemplateLeavesTheLookAlone() throws {
        let template = try #require(PersonalizationTemplate.all.first)
        var mine = NookDisplayPreferences()
        mine.haloPulsesWithBeat = true
        mine.haloBeatLook = .lasers

        let applied = template.applying(to: mine)
        #expect(applied.haloBeatLook == .lasers)
        #expect(template.matches(appearance: template.appearance, nook: applied))
    }

    @Test func theLooksHaveTheirWordsInAllThreeLanguages() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let keys = ["settings.appearance.nook.halo.beat.look"] + IslandBeatLook.allCases.map(\.titleKey)
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let url = root.appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
            let text = try String(contentsOf: url, encoding: .utf8)
            for key in keys {
                #expect(text.contains("\"\(key)\" = \""), "\(language) has no \(key)")
            }
        }
    }
}
