import CoreGraphics
import Foundation
import Testing
@testable import OpenIslandApp

/// The lasers' arrangements and their count (D56), as plain numbers: where
/// the beams stand for 8, 16 and 24 of them, the room they need, and the
/// saved choice. No window, no layer and no sound.
@Suite struct IslandLaserArrangementTests {
    private static let counts = [8, 16, 24]
    /// A 14 inch MacBook's screen, and its closed island at the top middle.
    private static let screen = CGRect(x: 0, y: 0, width: 1_512, height: 982)
    private static let pill = CGRect(x: 619, y: 950, width: 274, height: 32)
    private static let space = IslandLaserSpace(pill: pill, screen: screen)
    private static let soft = IslandLaserLimits.softHalfWidth
    private static let degrees = 180 / Double.pi
    private static let close = 0.000_1

    /// The four fan shapes, flat on the screen.
    private static let leaning: [IslandLaserArrangement] = [.fan, .wings, .comb, .crossed]
    private static let vertical = IslandLaserArrangement.uprights

    /// The distance from each start to the next.
    private static func gaps(_ stands: [IslandLaserStand]) -> [Double] {
        zip(stands.dropFirst(), stands).map { $0.start - $1.start }
    }

    // MARK: The list

    @Test func everyArrangementIsAValueWithANameOfItsOwn() {
        let every = IslandLaserArrangement.all + IslandLaserArrangement.uprights
        #expect(Set(every).count == every.count)
        #expect(Set(every.map(\.name)).count == every.count)
        #expect(Self.leaning.map(\.name) == ["fan", "wings", "comb", "crossed"])
        #expect(Self.vertical.map(\.name) == ["curtain", "wideCurtain", "split"])
        #expect(Self.leaning.allSatisfy { !$0.isUpright })
        #expect(Self.vertical.allSatisfy { $0.isUpright })
    }

    @Test func thePickIsTheIndexHandedInAndNothingElse() {
        let count = IslandLaserArrangement.all.count
        for index in -20...40 {
            let picked = IslandLaserArrangement.at(index)
            // The same index is the same arrangement, every time.
            #expect(picked == IslandLaserArrangement.at(index))
            #expect(picked == IslandLaserArrangement.at(index + count))
        }
        #expect(IslandLaserArrangement.at(0) == .fan)
        #expect(IslandLaserArrangement.at(1) == IslandLaserArrangement.wings.forward)
        #expect(IslandLaserArrangement.at(-1) == IslandLaserArrangement.comb.forward)
        // And the same lineup: nothing in it is rolled.
        for arrangement in IslandLaserArrangement.all {
            let first = arrangement.lineup(count: 16, space: Self.space, reach: 0.25)
            #expect(first == arrangement.lineup(count: 16, space: Self.space, reach: 0.25))
        }
    }

    @Test func everyArrangementHasTheBeamsAskedForAndTheSameOnBothSides() {
        for arrangement in IslandLaserArrangement.all + IslandLaserArrangement.uprights {
            for count in Self.counts {
                let stands = arrangement.lineup(count: count, space: Self.space, reach: 0.25).stands
                #expect(stands.count == count, "\(arrangement.name) with \(count)")
                #expect(stands.allSatisfy { $0.share > 0 && $0.share <= 1 })
                // The longest beam is the full length.
                #expect(stands.map(\.share).max() == 1, "\(arrangement.name) with \(count)")
                // The island is in the middle of its screen: the left half
                // is the right half turned around.
                for index in stands.indices {
                    let other = stands[count - 1 - index]
                    #expect(abs(stands[index].start + other.start) < Self.close)
                    #expect(abs(stands[index].lean + other.lean) < Self.close)
                    #expect(abs(stands[index].share - other.share) < Self.close)
                }
            }
        }
    }

    // MARK: The ones that lean

    @Test func theOnesThatLeanPointDownAndOutFromUnderTheNotch() {
        let sway = IslandLaserLimits.driftLean * Self.degrees
        let halfEdge = Double(Self.pill.width) / 2
        for arrangement in Self.leaning {
            for count in Self.counts {
                let lineup = arrangement.lineup(count: count, space: Self.space, reach: 0.25)
                #expect(lineup.sways)
                #expect(lineup.longest == .infinity)
                for stand in lineup.stands {
                    #expect(abs(stand.lean) + sway <= IslandLaserLimits.widestLean * Self.degrees + Self.close)
                    // Every one of them leaves from under the notch.
                    #expect(abs(stand.start) <= halfEdge)
                }
            }
        }
    }

    @Test func theFanOpensFromSixtyFourDegreesOnOneSideToSixtyFourOnTheOther() {
        for count in Self.counts {
            let stands = IslandLaserArrangement.fan.lineup(count: count, space: Self.space, reach: 0.25).stands
            #expect(abs(stands[0].lean + 64) < Self.close)
            #expect(abs(stands[count - 1].lean - 64) < Self.close)
            #expect(zip(stands.dropFirst(), stands).allSatisfy { $0.lean > $1.lean && $0.start > $1.start })
            // A little shorter at its ends than in the middle.
            #expect(stands[0].share < stands[count / 2].share)
        }
    }

    @Test func theWingsLeaveTheMiddleEmpty() {
        let halfEdge = Double(Self.pill.width) / 2
        for count in Self.counts {
            let stands = IslandLaserArrangement.wings.lineup(count: count, space: Self.space, reach: 0.25).stands
            let left = stands.prefix(count / 2)
            let right = stands.suffix(count / 2)
            #expect(left.allSatisfy { $0.lean <= -36 + Self.close && $0.lean >= -68 - Self.close })
            #expect(right.allSatisfy { $0.lean >= 36 - Self.close && $0.lean <= 68 + Self.close })
            #expect(stands.allSatisfy { abs($0.start) >= 0.3 * halfEdge - Self.close })
        }
    }

    @Test func theCombIsLongAndShortInTurnAndTheCrossedOnesLeanAcross() {
        for count in Self.counts {
            let comb = IslandLaserArrangement.comb.lineup(count: count, space: Self.space, reach: 0.25).stands
            for index in 0..<count / 2 {
                #expect(comb[index].share == (index.isMultiple(of: 2) ? 1 : 0.78))
            }
            let crossed = IslandLaserArrangement.crossed.lineup(count: count, space: Self.space, reach: 0.25).stands
            // The left ones lean right and the right ones left.
            #expect(crossed.allSatisfy { $0.start * $0.lean < 0 })
            #expect(abs(crossed[0].lean - 40) < Self.close)
            #expect(abs(crossed[count - 1].lean + 40) < Self.close)
        }
    }

    // MARK: The ones that come straight down

    @Test func theOnesThatComeStraightDownAreUprightAndSideBySide() {
        for arrangement in Self.vertical {
            for count in Self.counts {
                for reach in [0.0, 0.25, 0.6, 1] {
                    let lineup = arrangement.lineup(count: count, space: Self.space, reach: reach)
                    let label = "\(arrangement.name) with \(count) at \(reach)"
                    #expect(!lineup.sways, "\(label)")
                    // To the bottom of the screen and no further.
                    #expect(lineup.longest == Double(Self.pill.minY - Self.screen.minY), "\(label)")
                    #expect(lineup.stands.allSatisfy { $0.lean == 0 }, "\(label)")
                    #expect(Self.gaps(lineup.stands).allSatisfy { $0 > 0 }, "\(label)")
                    // With its soft edge, every one is on the screen.
                    #expect(lineup.stands.allSatisfy { abs($0.start) + Self.soft <= Self.space.left + Self.close }, "\(label)")
                }
            }
        }
    }

    @Test func theCurtainGoesAcrossTheNotchAndALittleBeyond() {
        let half = Double(Self.pill.width) / 2 + IslandLaserLimits.curtainBeyond
        for count in Self.counts {
            let near = IslandLaserArrangement.curtain.lineup(count: count, space: Self.space, reach: 0).stands
            #expect(abs(near[0].start + half) < Self.close)
            #expect(abs(near[count - 1].start - half) < Self.close)
            // The same distance from each beam to the next.
            let gaps = Self.gaps(near)
            #expect(gaps.allSatisfy { abs($0 - half * 2 / Double(count - 1)) < Self.close })
            #expect(near.allSatisfy { $0.share == 1 })
            // The reach makes it longer and never wider.
            #expect(near == IslandLaserArrangement.curtain.lineup(count: count, space: Self.space, reach: 1).stands)
        }
    }

    @Test func theWideCurtainGrowsWithTheReachUpToTheWholeScreen() {
        let curtain = Double(Self.pill.width) / 2 + IslandLaserLimits.curtainBeyond
        for count in Self.counts {
            func stands(_ reach: Double) -> [IslandLaserStand] {
                IslandLaserArrangement.wideCurtain.lineup(count: count, space: Self.space, reach: reach).stands
            }
            // Twice the curtain at the near end.
            #expect(abs(stands(0)[count - 1].start - curtain * IslandLaserLimits.wideStart) < Self.close)
            // The screen's own side at the far end, less the soft edge.
            #expect(abs(stands(1)[count - 1].start - (Self.space.right - Self.soft)) < Self.close)
            #expect(abs(stands(1)[0].start + (Self.space.left - Self.soft)) < Self.close)
            var last = 0.0
            for step in 0...20 {
                let width = stands(Double(step) / 20)[count - 1].start
                #expect(width > last)
                last = width
            }
            let middle = stands(0.25)
            let gaps = Self.gaps(middle)
            #expect(gaps.allSatisfy { abs($0 - gaps[0]) < Self.close })
            // Longest in the middle, and shorter toward the sides.
            #expect(middle[count / 2].share == 1)
            #expect(abs(middle[0].share - (1 - IslandLaserLimits.wideDip)) < Self.close)
        }
    }

    @Test func theSplitIsHalfOnEachSideWithTheMiddleEmpty() {
        for count in Self.counts {
            for reach in [0.0, 0.25, 1] {
                let stands = IslandLaserArrangement.split.lineup(count: count, space: Self.space, reach: reach).stands
                let wide = Self.space.wide(reach: reach)
                let left = Array(stands.prefix(count / 2))
                let right = Array(stands.suffix(count / 2))
                // From the wide curtain's own ends in to a third of the way.
                #expect(abs(left[0].start + wide.left) < Self.close)
                #expect(abs(right[count / 2 - 1].start - wide.right) < Self.close)
                #expect(left.allSatisfy { $0.start <= -wide.left * IslandLaserLimits.splitGap + Self.close })
                #expect(right.allSatisfy { $0.start >= wide.right * IslandLaserLimits.splitGap - Self.close })
                // The gap in the middle is far wider than the one from a
                // beam to its neighbor.
                let neighbor = Self.gaps(left)[0]
                #expect(right[0].start - left[count / 2 - 1].start > neighbor * 2)
                #expect(Self.gaps(left).allSatisfy { abs($0 - neighbor) < Self.close })
                #expect(Self.gaps(right).allSatisfy { abs($0 - neighbor) < Self.close })
                #expect(stands.allSatisfy { $0.share == 1 })
            }
        }
    }

    @Test func uprightBeamsNeverSwayAndStopAtTheBottomOfTheScreen() {
        let down = Double(Self.pill.minY - Self.screen.minY)
        for arrangement in Self.vertical {
            for count in Self.counts {
                let lineup = arrangement.lineup(count: count, space: Self.space, reach: 1)
                var time = 0.0
                while time < IslandLaserLimits.driftPeriod {
                    // Far longer than the screen is tall, with every beam
                    // nudged as far as a hat may nudge it.
                    let fan = IslandLaserFan(
                        frame: IslandBeatFrame(low: 1, hit: .kick), reach: 1, tint: nil, lineup: lineup, hueIndex: 0,
                        nudges: Array(repeating: 1 + IslandLaserLimits.hatCeiling, count: count),
                        time: time, fullLength: 5_000
                    )
                    #expect(fan.beams.allSatisfy { $0.lean == 0 })
                    #expect(fan.beams.allSatisfy { $0.length <= down })
                    #expect(fan.beams.contains { $0.length == down })
                    time += 0.5
                }
                // A length that fits is left as it is.
                let short = IslandLaserFan(
                    frame: IslandBeatFrame(low: 1, hit: .kick), reach: 1, tint: nil, lineup: lineup, hueIndex: 0,
                    time: 0, fullLength: 400
                )
                for index in lineup.stands.indices {
                    #expect(abs(short.beams[index].length - 400 * lineup.stands[index].share) < Self.close)
                }
            }
        }
    }

    // MARK: Room

    private static let displays: [(screen: CGRect, pill: CGRect)] = [
        (screen, pill),
        // An external display beside the MacBook, with its island near the
        // left edge.
        (CGRect(x: 1_512, y: 0, width: 1_920, height: 1_080), CGRect(x: 1_540, y: 1_056, width: 200, height: 24)),
        // One to the left, with negative coordinates.
        (CGRect(x: -2_560, y: 200, width: 2_560, height: 1_440), CGRect(x: -1_460, y: 1_616, width: 360, height: 24)),
    ]

    @Test func theRoomHoldsEveryUprightBeamAndStaysOnTheIslandsScreen() {
        for (screen, pill) in Self.displays {
            let space = IslandLaserSpace(pill: pill, screen: screen)
            for step in 0...10 {
                let reach = Double(step) / 10
                let length = IslandLaserWindowPlan.beamLength(reach: reach, pill: pill, screen: screen)
                let room = IslandLaserRoom.rect(length: length, reach: reach, pill: pill, screen: screen)
                #expect(screen.contains(room))
                #expect(room.contains(pill))
                // Everything the beams that lean need, as far as the
                // screen goes.
                #expect(room.contains(IslandLaserRoom.rect(length: length, notch: pill).intersection(screen)))

                for arrangement in Self.vertical {
                    for count in Self.counts {
                        let fan = IslandLaserFan(
                            frame: IslandBeatFrame(low: 1, hit: .kick), reach: reach, tint: nil,
                            lineup: arrangement.lineup(count: count, space: space, reach: reach), hueIndex: 0,
                            nudges: Array(repeating: 1 + IslandLaserLimits.hatCeiling, count: count),
                            time: 0, fullLength: length
                        )
                        var outside = 0
                        for beam in fan.beams {
                            let x = Double(pill.midX) + beam.start
                            let tip = Double(pill.minY) - beam.length
                            let isInside = beam.lean == 0
                                && x - Self.soft >= Double(room.minX) - Self.close
                                && x + Self.soft <= Double(room.maxX) + Self.close
                                && tip >= Double(room.minY) - Self.close
                            if !isInside { outside += 1 }
                        }
                        #expect(outside == 0, "\(arrangement.name) with \(count) at \(reach) on \(screen)")
                    }
                }
            }
        }
    }

    @Test func aWideIslandGetsRoomForACurtainWiderThanItsFan() {
        // An island 600 points wide on a very wide screen, at the near end
        // of the reach: the wide curtain goes further to the side than the
        // beams that lean.
        let screen = CGRect(x: 0, y: 0, width: 3_440, height: 1_440)
        let pill = CGRect(x: 1_420, y: 1_408, width: 600, height: 32)
        let length = IslandLaserWindowPlan.beamLength(reach: 0, pill: pill, screen: screen)
        let leaning = IslandLaserRoom.rect(length: length, notch: pill)
        let wide = IslandLaserSpace(pill: pill, screen: screen).wide(reach: 0)
        #expect(Double(pill.midX) - wide.left < Double(leaning.minX))

        let room = IslandLaserRoom.rect(length: length, reach: 0, pill: pill, screen: screen)
        #expect(Double(room.minX) <= Double(pill.midX) - wide.left - Self.soft + Self.close)
        #expect(Double(room.maxX) >= Double(pill.midX) + wide.right + Self.soft - Self.close)
        #expect(screen.contains(room))
    }

    @Test func anIslandAtTheEdgeOfItsScreenKeepsItsCurtainOnThatScreen() {
        let screen = CGRect(x: 1_512, y: 0, width: 1_920, height: 1_080)
        let pill = CGRect(x: 1_540, y: 1_056, width: 200, height: 24)
        let space = IslandLaserSpace(pill: pill, screen: screen)
        #expect(space.left == 128)
        #expect(space.right == 1_792)
        // There is less room on the left than the curtain would take.
        #expect(space.curtain.left == space.left - Self.soft)
        #expect(space.curtain.right == 100 + IslandLaserLimits.curtainBeyond)
        for reach in [0.0, 0.5, 1] {
            let wide = space.wide(reach: reach)
            #expect(wide.left == space.left - Self.soft)
            #expect(wide.right <= space.right - Self.soft + Self.close)
        }
        #expect(abs(space.wide(reach: 1).right - (space.right - Self.soft)) < Self.close)
    }

    // MARK: How many

    @Test func theCountIsHeldBetweenEightAndTwentyFour() {
        #expect(IslandLaserCount.least == 8)
        #expect(IslandLaserCount.most == 24)
        #expect(IslandLaserCount.standard == 16)
        #expect(IslandLaserCount.clamped(16) == 16)
        #expect(IslandLaserCount.clamped(3) == 8)
        #expect(IslandLaserCount.clamped(-5) == 8)
        #expect(IslandLaserCount.clamped(400) == 24)
        #expect(IslandLaserCount.clamped(.max) == 24)

        // What a saved value reads as.
        #expect(IslandLaserCount.stored(nil) == nil)
        #expect(IslandLaserCount.stored("many") == nil)
        #expect(IslandLaserCount.stored(12) == 12)
        #expect(IslandLaserCount.stored(2) == 8)
        #expect(IslandLaserCount.stored(12.0) == 12)
        #expect(IslandLaserCount.stored(99.0) == 24)
        #expect(IslandLaserCount.stored(1e300) == 24)
        #expect(IslandLaserCount.stored(Double.nan) == nil)
        #expect(IslandLaserCount.stored(Double.infinity) == nil)
    }

    @Test func oldSettingsGetSixteenLasersAndTheCountIsSavedForOneDisplay() {
        let defaults = MemoryDefaults()
        // A copy from before the count: the lasers, their reach, no count.
        defaults.set(IslandBeatLook.lasers.rawValue, forKey: "nook.display.notch.haloBeatLook")
        defaults.set(0.8, forKey: "nook.display.notch.haloLaserReach")
        var mine = NookDisplayPreferences.load(for: .notch, defaults: defaults)
        #expect(mine.haloLaserCount == 16)
        #expect(mine.haloLaserReach == 0.8)
        #expect(NookDisplayPreferences().haloLaserCount == IslandLaserCount.standard)

        mine.persist(for: .notch, defaults: defaults)
        let before = mine
        let saved = defaults.all
        mine.haloLaserCount = 24
        mine.persistChanges(from: before, for: .notch, defaults: defaults)

        let changed = defaults.all.filter { key, value in (saved[key] as? NSObject) != (value as? NSObject) }
        #expect(Array(changed.keys) == ["nook.display.notch.haloLaserCount"])
        let loaded = NookDisplayPreferences.load(for: .notch, defaults: defaults)
        #expect(loaded.haloLaserCount == 24)
        #expect(loaded.haloLaserReach == 0.8)
        #expect(NookDisplayPreferences.load(for: .topBar, defaults: defaults).haloLaserCount == 16)
        // A drag of it is not a change to the page.
        #expect(!mine.changesThePage(from: before))

        // Anything outside 8 to 24 is held to an end, and what is no
        // number is the standard.
        defaults.set(2, forKey: "nook.display.notch.haloLaserCount")
        #expect(NookDisplayPreferences.load(for: .notch, defaults: defaults).haloLaserCount == 8)
        defaults.set(900, forKey: "nook.display.notch.haloLaserCount")
        #expect(NookDisplayPreferences.load(for: .notch, defaults: defaults).haloLaserCount == 24)
        defaults.set("lots", forKey: "nook.display.notch.haloLaserCount")
        #expect(NookDisplayPreferences.load(for: .notch, defaults: defaults).haloLaserCount == 16)
    }

    @Test func aLayoutTemplateLeavesTheCountAlone() throws {
        let template = try #require(PersonalizationTemplate.all.first)
        var mine = NookDisplayPreferences()
        mine.haloLaserCount = 22

        let applied = template.applying(to: mine)
        #expect(applied.haloLaserCount == 22)
        #expect(template.matches(appearance: template.appearance, nook: applied))
    }

    @Test func theCountGoesFromTheDisplaysChoiceToThePulse() {
        var inputs = IslandHaloInputs(
            style: .subtle, policy: .full, isOpened: false, waiting: nil, flashToken: nil,
            noticeTint: nil, musicTint: IslandHaloRGB.rgb255(10, 200, 30), isRunning: false,
            isMusicPlaying: true, pulsesWithBeat: true
        )
        guard case let .pulse(standard) = IslandHaloState.resolve(inputs).motion else {
            Issue.record("No pulse")
            return
        }
        #expect(standard.laserCount == 16)

        inputs.pulseLaserCount = 20
        if case let .pulse(pulse) = IslandHaloState.resolve(inputs).motion { #expect(pulse.laserCount == 20) }
        inputs.pulseLaserCount = 5_000
        if case let .pulse(held) = IslandHaloState.resolve(inputs).motion { #expect(held.laserCount == 24) }
    }

    @Test func theCountHasItsWordsInAllThreeLanguages() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        #expect(IslandLaserCount.titleKey == "settings.appearance.nook.halo.beat.laserCount")
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let url = root.appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.contains("\"\(IslandLaserCount.titleKey)\" = \""), "\(language) has no word for the count")
        }
        let english = try String(
            contentsOf: root.appendingPathComponent("Sources/OpenIslandApp/Resources/en.lproj/Localizable.strings"),
            encoding: .utf8
        )
        #expect(english.contains("\"\(IslandLaserCount.titleKey)\" = \"How many lasers\";"))
    }
}
