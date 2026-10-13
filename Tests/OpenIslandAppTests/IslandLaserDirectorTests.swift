import Foundation
import Testing
@testable import OpenIslandApp

/// The show's director (D56) as plain values: a song's program, the
/// phrase rule, the bass gate, and what a hit may change. It is fed
/// made-up frames and a clock. No window, no layer and no sound device.
@Suite struct IslandLaserDirectorTests {
    private static let step = 1.0 / 15

    private static func director(_ title: String = "Sky", _ artist: String = "Playboi Carti") -> IslandLaserDirector {
        IslandLaserDirector(
            program: IslandLaserProgram(seed: IslandLaserSeed.seed(title: title, artist: artist, tint: nil))
        )
    }

    /// Frames of a groove: bass that holds, mids and highs, a low hit
    /// every half second and whatever `hit` adds on the frames between.
    private static func groove(
        from start: Double,
        for length: Double,
        kick: Double = 1,
        between: (Int) -> IslandBeatHit? = { _ in nil }
    ) -> [(Double, IslandBeatFrame)] {
        let count = Int((length / step).rounded())
        return (0..<count).map { index in
            let time = start + Double(index) * step
            let isKick = index % 8 == 0
            return (time, IslandBeatFrame(
                low: isKick ? kick : 0.7, mid: 0.6, high: 0.5, hit: isKick ? .kick : between(index)
            ))
        }
    }

    /// How a band's level falls once its sound stops: the analyzer's
    /// envelope lets go over a quarter of a second, down to what leaks in
    /// from the other bands.
    private static func faded(_ level: Double, after time: Double) -> Double {
        max(0.02, level * exp(-max(time, 0) / IslandBeatAnalyzer.fall))
    }

    /// Frames with no bass: what was held fades as the analyzer's level
    /// does, and the mids and the highs carry on.
    private static func noBass(
        from start: Double, for length: Double, rest: Double = 0.6
    ) -> [(Double, IslandBeatFrame)] {
        let count = Int((length / step).rounded())
        return (0..<count).map { index in
            let passed = Double(index) * step
            return (start + passed, IslandBeatFrame(low: faded(0.7, after: passed), mid: rest, high: rest))
        }
    }

    @discardableResult
    private static func run(
        _ director: inout IslandLaserDirector, _ frames: [(Double, IslandBeatFrame)]
    ) -> [(time: Double, cue: IslandLaserCue)] {
        var cues: [(Double, IslandLaserCue)] = []
        for (time, frame) in frames {
            for cue in director.follow(frame, at: time) {
                cues.append((time, cue))
            }
        }
        return cues
    }

    private static func isDark(_ cue: IslandLaserCue) -> Bool { cue == .dark }

    private static func isBurst(_ cue: IslandLaserCue) -> Bool {
        if case .burst = cue { return true }
        return false
    }

    private static func shown(_ cue: IslandLaserCue) -> IslandLaserPicture? {
        if case let .show(picture) = cue { return picture }
        return nil
    }

    // MARK: A program for each song

    @Test func theSameTitleAndArtistGiveTheSameSeedOnEveryRun() {
        let seed = IslandLaserSeed.seed(title: "Sky", artist: "Playboi Carti", tint: nil)
        // A number written down: it must not move from one launch to the
        // next, which Swift's own hashing would.
        #expect(seed == IslandLaserSeed.hash(Array("sky".utf8) + [0x1F] + Array("playboi carti".utf8)))
        #expect(IslandLaserSeed.hash([]) == 0xCBF2_9CE4_8422_2325)
        #expect(IslandLaserSeed.hash([0x61]) == 0xAF63_DC4C_8601_EC8C)
        #expect(seed == IslandLaserSeed.seed(title: "  SKY ", artist: "playboi carti\n", tint: nil))
        // The color plays no part while the song has a name.
        #expect(seed == IslandLaserSeed.seed(title: "Sky", artist: "Playboi Carti", tint: IslandHaloRGB(rgb: 0x112233)))

        #expect(seed != IslandLaserSeed.seed(title: "Sky", artist: "Yeat", tint: nil))
        #expect(seed != IslandLaserSeed.seed(title: "Stop Breathing", artist: "Playboi Carti", tint: nil))
        #expect(
            IslandLaserSeed.seed(title: "ab", artist: "c", tint: nil)
                != IslandLaserSeed.seed(title: "a", artist: "bc", tint: nil)
        )
    }

    @Test func aSongWithNoNameIsSeededFromItsColor() {
        let red = IslandHaloRGB(rgb: 0xE0245E)
        let blue = IslandHaloRGB(rgb: 0x2060FF)
        let fromRed = IslandLaserSeed.seed(title: nil, artist: nil, tint: red)
        #expect(fromRed == IslandLaserSeed.seed(title: " ", artist: "", tint: red))
        #expect(fromRed != IslandLaserSeed.seed(title: nil, artist: nil, tint: blue))
        // And with nothing at all, one fixed number.
        #expect(IslandLaserSeed.seed(title: nil, artist: nil, tint: nil) == IslandLaserSeed.hash([]))
    }

    @Test func theSameSongGetsTheSameProgramAndTwoSongsDiffer() {
        let songs = [
            ("Sky", "Playboi Carti"), ("Stop Breathing", "Playboi Carti"), ("Talk", "Yeat"),
            ("XO Tour Llif3", "Lil Uzi Vert"), ("20 Min", "Lil Uzi Vert"), ("Miss The Rage", "Trippie Redd"),
            ("hot girl", "Charli xcx"), ("Dior", "Pop Smoke"),
        ]
        var programs: [IslandLaserProgram] = []
        for (title, artist) in songs {
            let seed = IslandLaserSeed.seed(title: title, artist: artist, tint: nil)
            let program = IslandLaserProgram(seed: seed)
            #expect(program == IslandLaserProgram(seed: seed))
            programs.append(program)

            // Four to six looks, each another arrangement, one Odd Even.
            #expect(IslandLaserProgram.lookCounts.contains(program.looks.count))
            #expect(Set(program.looks.map(\.arrangement)).count == program.looks.count)
            #expect(program.looks.filter { $0.kind == .oddEven }.count == 1)
            #expect(program.looks.allSatisfy { $0.kind == .oddEven || $0.kind == .still })
            #expect(program.looks.allSatisfy { IslandLaserLook.grooveArrangements.contains($0.arrangement) })
            #expect(Set(program.lulls) == Set(IslandLaserLook.lulls))
            #expect(program.hueOrder.sorted() == [0, 1, 2, 3])
            // The largest look is the one a drop lands on.
            let sizes = program.looks.map(\.size)
            #expect(sizes[program.biggest] == sizes.max())
        }
        // No two of these songs have the same show.
        for first in programs.indices {
            for second in programs.indices where second > first {
                #expect(programs[first].looks != programs[second].looks
                    || programs[first].hueOrder != programs[second].hueOrder)
            }
        }
        #expect(Set(programs.map(\.looks.count)).count > 1)
    }

    @Test func aPaletteIsTwoOfTheFourHuesAndTheNextKeepsOne() {
        let program = Self.director().program
        for index in 0..<8 {
            let palette = program.palette(index)
            let next = program.palette(index + 1)
            #expect(palette.base != palette.accent)
            #expect((0..<4).contains(palette.base) && (0..<4).contains(palette.accent))
            // The old accent is the new base.
            #expect(next.base == palette.accent)
            #expect(program.palette(index + 4).base == palette.base)
        }
        #expect(program.palette(0).base == program.hueOrder[0])
        #expect(program.palette(0).accent == program.hueOrder[1])
    }

    // MARK: What a hit may change

    @Test func noHitEverChangesTheLookOrTheHues() {
        var director = Self.director()
        // Fifteen seconds as busy as a song gets: a low hit every half
        // second, and a clap or a hat on every frame between.
        let cues = Self.run(&director, Self.groove(from: 0, for: 15) { $0.isMultiple(of: 2) ? .snare : .hat })

        let palette = director.program.palette(0)
        let look = director.program.looks[0]
        #expect(cues.compactMap { Self.shown($0.cue) }.count == 1)
        for (_, cue) in cues {
            let picture: IslandLaserPicture? = switch cue {
            case let .show(picture), let .push(picture, _), let .flash(picture), let .burst(picture), let .stir(picture): picture
            case .shimmer, .dark: nil
            }
            guard let picture else { continue }
            #expect(picture.look == look)
            #expect(Set([picture.base, picture.accent]) == Set([palette.base, palette.accent]))
        }
        #expect(director.lookIndex == 0)
        #expect(director.paletteIndex == 0)
        #expect(director.drops == 0 && director.blackouts == 0)
        // And the hits did land: pushes, flashes and shimmers.
        #expect(cues.contains { if case .push = $0.cue { true } else { false } })
        #expect(cues.contains { if case .flash = $0.cue { true } else { false } })
    }

    @Test func aSnareIsAWhiteFlashThatSwapsBaseAndAccent() {
        var director = Self.director()
        Self.run(&director, [(0, IslandBeatFrame(low: 0.7, mid: 0.5, high: 0.5))])
        let before = director.picture

        let first = director.follow(IslandBeatFrame(low: 0.7, mid: 1, high: 0.5, hit: .snare), at: 1)
        #expect(first == [.flash(director.picture)])
        #expect(director.picture.base == before.accent)
        #expect(director.picture.accent == before.base)
        #expect(director.picture.look == before.look)

        // The next one changes them back.
        let second = director.follow(IslandBeatFrame(low: 0.7, mid: 1, high: 0.5, hit: .snare), at: 2)
        #expect(second == [.flash(before)])
        #expect(director.picture == before)
    }

    @Test func aLowHitPushesTheBeamsAsFarAsItWasHardAndChangesNoColor() {
        var director = Self.director()
        Self.run(&director, [(0, IslandBeatFrame(low: 0.7, mid: 0.5, high: 0.5))])
        let before = director.picture

        for (index, strength) in [1.0, 0.6, 0.8].enumerated() {
            let cues = director.follow(IslandBeatFrame(low: strength, hit: .kick), at: 1 + Double(index))
            guard case let .push(picture, pushed)? = cues.first, cues.count == 1 else {
                Issue.record("No push for a low hit")
                continue
            }
            #expect(pushed == strength)
            #expect(picture.base == before.base && picture.accent == before.accent)
            #expect(picture.look == before.look)
        }
    }

    @Test func theOddEvenLightsItsOtherGroupOnEachLowHit() throws {
        var director = Self.director()
        let odd = try #require(director.program.looks.firstIndex { $0.kind == .oddEven })
        // Walk the phrases until the Odd Even is on.
        var time = 0.0
        Self.run(&director, [(time, IslandBeatFrame(low: 0.7, mid: 0.5, high: 0.5))])
        while director.lookIndex != odd {
            time += IslandLaserShow.phrase
            _ = director.follow(IslandBeatFrame(low: 1, hit: .kick), at: time)
        }
        #expect(director.picture.look.kind == .oddEven)

        var groups: [Int] = []
        for _ in 0..<6 {
            time += 0.5
            for cue in director.follow(IslandBeatFrame(low: 1, hit: .kick), at: time) {
                if case let .push(picture, _) = cue { groups.append(picture.litGroup) }
            }
        }
        #expect(groups.count == 6)
        #expect(zip(groups.dropFirst(), groups).allSatisfy { $0 != $1 })
        #expect(Set(groups) == [0, 1])
    }

    @Test func aHatIsAShimmerAndWaitsWhileAHitFades() {
        var director = Self.director()
        Self.run(&director, [(0, IslandBeatFrame(low: 0.7, mid: 0.5, high: 0.5))])
        #expect(director.follow(IslandBeatFrame(low: 0.7, high: 0.9, hit: .hat), at: 1) == [.shimmer(0.9)])

        _ = director.follow(IslandBeatFrame(low: 1, hit: .kick), at: 2)
        #expect(director.follow(IslandBeatFrame(low: 0.7, high: 0.9, hit: .hat), at: 2.05).isEmpty)
        #expect(director.follow(IslandBeatFrame(low: 0.7, high: 0.9, hit: .hat), at: 2.2) == [.shimmer(0.9)])
    }

    @Test func withDimFlashingLightsOnNoSecondHoldsMoreThanThreeFlashes() {
        var director = Self.director()
        director.flashRule = .dimmed
        let cues = Self.run(&director, Self.groove(from: 0, for: 6) { _ in .snare })
        let flashes = cues.filter {
            switch $0.cue {
            case .push, .flash, .burst: true
            case .show, .shimmer, .dark, .stir: false
            }
        }.map(\.time)
        #expect(!flashes.isEmpty)
        for start in flashes {
            #expect(flashes.filter { $0 >= start && $0 < start + 1 - 0.000_001 }.count <= 3)
        }
    }

    // MARK: The phrase

    @Test func aLookGivesWayOnlyAfterItsHoldAndOnAStrongHitAfterAPhrase() {
        #expect(IslandLaserShow.leastHold == 8)
        #expect(IslandLaserShow.phrase == 16)
        #expect(!IslandLaserPhrase.turns(shownFor: 0, isStrongHit: true))
        #expect(!IslandLaserPhrase.turns(shownFor: 7.9, isStrongHit: true))
        #expect(!IslandLaserPhrase.turns(shownFor: 12, isStrongHit: true))
        #expect(!IslandLaserPhrase.turns(shownFor: 15.9, isStrongHit: true))
        #expect(!IslandLaserPhrase.turns(shownFor: 16, isStrongHit: false))
        #expect(!IslandLaserPhrase.turns(shownFor: 400, isStrongHit: false))
        #expect(IslandLaserPhrase.turns(shownFor: 16, isStrongHit: true))
        #expect(IslandLaserPhrase.turns(shownFor: 40, isStrongHit: true))
    }

    @Test func theShowWalksItsLooksAPhraseAtATimeAndItsColorsEveryFourth() {
        var director = Self.director()
        let looks = director.program.looks
        let cues = Self.run(&director, Self.groove(from: 0, for: 100))

        // The first look at the first sound, and a new one at the first
        // strong low hit after each sixteen seconds.
        let shows = cues.compactMap { entry in Self.shown(entry.cue).map { (entry.time, $0) } }
        #expect(shows.count == 7)
        #expect(shows[0].0 == 0)
        for (index, show) in shows.enumerated() {
            #expect(show.1.look == looks[index % looks.count])
            if index > 0 {
                let held = show.0 - shows[index - 1].0
                #expect(held >= IslandLaserShow.phrase)
                #expect(held < IslandLaserShow.phrase + 0.6)
            }
        }
        // The colors change with the fourth phrase and not before it.
        let palettes = shows.map { Set([$0.1.base, $0.1.accent]) }
        let first = director.program.palette(0)
        let second = director.program.palette(1)
        #expect(palettes[0...3].allSatisfy { $0 == Set([first.base, first.accent]) })
        #expect(palettes[4...6].allSatisfy { $0 == Set([second.base, second.accent]) })
        #expect(director.paletteIndex == 1)
    }

    @Test func softLowHitsNeverEndAPhrase() {
        var director = Self.director()
        let cues = Self.run(&director, Self.groove(from: 0, for: 60, kick: IslandLaserShow.strongHit - 0.1))
        #expect(cues.compactMap { Self.shown($0.cue) }.count == 1)
        #expect(director.lookIndex == 0)
    }

    // MARK: The bass gate

    @Test func aBassGapOfTwoSecondsThenAFullReturnIsOneBlackoutAndOneDrop() throws {
        var director = Self.director()
        var frames = Self.groove(from: 0, for: 10)
        frames += Self.noBass(from: 10, for: 2)
        // Everything back at once: a hard low hit with the mids and the
        // highs loud.
        frames.append((12, IslandBeatFrame(low: 1, mid: 0.9, high: 0.9, hit: .kick)))
        frames += Array(Self.groove(from: 12, for: 6).dropFirst())
        let cues = Self.run(&director, frames)

        let darks = cues.filter { Self.isDark($0.cue) }
        let bursts = cues.filter { Self.isBurst($0.cue) }
        #expect(darks.count == 1)
        #expect(bursts.count == 1)
        #expect(director.blackouts == 1 && director.drops == 1)
        // Dark a second after the low band emptied, which takes its
        // level a moment to show, and the burst with the bass's return.
        let dark = try #require(darks.first)
        #expect(dark.time >= 10 + IslandLaserShow.gapBeforeBlackout)
        #expect(dark.time < 10 + IslandLaserShow.gapBeforeBlackout + 0.6)
        #expect(12 - dark.time >= IslandLaserShow.leastDark)
        #expect(bursts.first?.time == 12)

        // After the burst: the largest look, and new colors.
        let after = try #require(cues.first { $0.time > 12 && Self.shown($0.cue) != nil })
        #expect(after.time >= 12 + IslandLaserShow.burstLength)
        #expect(after.time < 12 + IslandLaserShow.burstLength + 0.1)
        let landed = try #require(Self.shown(after.cue))
        #expect(landed.look == director.program.looks[director.program.biggest])
        let palette = director.program.palette(1)
        #expect(Set([landed.base, landed.accent]) == Set([palette.base, palette.accent]))
        #expect(director.paletteIndex == 1)
        // Nothing else was shown while the burst ran.
        #expect(!cues.contains { $0.time > 12 && $0.time < after.time })
    }

    @Test func aQuietOutroGivesNoDrop() {
        var director = Self.director()
        var frames = Self.groove(from: 0, for: 10)
        // Everything fades over three seconds and stays gone.
        for index in 0..<Int(8 / Self.step) {
            let time = 10 + Double(index) * Self.step
            let level = max(0, 0.6 * (1 - (time - 10) / 3))
            frames.append((time, IslandBeatFrame(low: level * 0.2, mid: level, high: level)))
        }
        let cues = Self.run(&director, frames)

        #expect(director.drops == 0)
        #expect(!cues.contains { Self.isBurst($0.cue) })
        #expect(director.isDark)
        #expect(director.section == .idle)
    }

    @Test func aGapShorterThanASecondGivesNothing() {
        var director = Self.director()
        var frames = Self.groove(from: 0, for: 10)
        frames += Self.noBass(from: 10, for: 0.8)
        frames.append((10.8, IslandBeatFrame(low: 1, mid: 0.9, high: 0.9, hit: .kick)))
        frames += Array(Self.groove(from: 10.8, for: 4).dropFirst())
        let cues = Self.run(&director, frames)

        #expect(director.blackouts == 0 && director.drops == 0)
        #expect(!cues.contains { Self.isDark($0.cue) || Self.isBurst($0.cue) })
        #expect(director.section == .groove)
    }

    @Test func aSongWithOnlyAKickNowAndThenIsNotGated() {
        var director = Self.director()
        // A hard low hit every two seconds and nothing held under it: the
        // low band is empty most of the time, and that is how the song
        // goes. Its level falls away after each hit as the analyzer's does.
        var frames: [(Double, IslandBeatFrame)] = []
        for index in 0..<Int(40 / Self.step) {
            let time = Double(index) * Self.step
            let isKick = index % 30 == 0
            let low = isKick ? 1 : Self.faded(1, after: Double(index % 30) * Self.step)
            frames.append((time, IslandBeatFrame(low: low, mid: 0.9, high: 0.8, hit: isKick ? .kick : nil)))
        }
        let cues = Self.run(&director, frames)
        #expect(director.blackouts == 0 && director.drops == 0)
        #expect(!cues.contains { Self.isDark($0.cue) || Self.isBurst($0.cue) })
    }

    @Test func oneHeldBassNoteABarUnderAVoiceIsNeitherABlackoutNorADrop() {
        var director = Self.director()
        // A bar of three and a half seconds: a hard 808 held for a second
        // and a half, then nothing under the voice until the next bar.
        // Every bar the low band is empty for about a second and a half
        // and comes back hard, with the mids loud.
        let bar = 3.5
        var frames: [(Double, IslandBeatFrame)] = []
        for index in 0..<Int(60 / Self.step) {
            let time = Double(index) * Self.step
            let inBar = time.truncatingRemainder(dividingBy: bar)
            let isHit = inBar < Self.step
            let low = isHit ? 1 : (inBar < 1.5 ? 0.9 : Self.faded(0.9, after: inBar - 1.5))
            frames.append((time, IslandBeatFrame(low: low, mid: 0.9, high: 0.6, hit: isHit ? .kick : nil)))
        }
        let cues = Self.run(&director, frames)

        #expect(director.blackouts == 0)
        #expect(director.drops == 0)
        #expect(!cues.contains { Self.isDark($0.cue) || Self.isBurst($0.cue) })
        // The show itself went on: its looks changed with the phrases.
        #expect(director.lookIndex > 0)
    }

    @Test func theBassIsSteadyOnlyAfterFourSecondsWithNoBreakInIt() {
        func isArmed(after held: Double) -> Bool {
            var gate = IslandLaserGate()
            var time = 0.0
            while time < held {
                gate.read(IslandBeatFrame(low: 0.8, mid: 0.6, high: 0.5), at: time)
                time += Self.step
            }
            // The bass goes, and the rest carries on for a second.
            let gone = time
            while time < gone + 1.2 {
                gate.read(IslandBeatFrame(low: 0.02, mid: 0.6, high: 0.5), at: time)
                time += Self.step
            }
            #expect(gate.bassGap(at: time) >= 1)
            return gate.isArmed
        }
        #expect(isArmed(after: 10))
        #expect(isArmed(after: IslandLaserShow.steadyFor + 0.5))
        #expect(!isArmed(after: 3))
        #expect(!isArmed(after: 1))

        // A dip shorter than a break is no break: a kick drum's own gaps.
        var gate = IslandLaserGate()
        var time = 0.0
        while time < 8 {
            let inBeat = time.truncatingRemainder(dividingBy: 0.5)
            gate.read(IslandBeatFrame(low: Self.faded(1, after: inBeat), mid: 0.6, high: 0.5), at: time)
            time += Self.step
        }
        let gone = time
        while time < gone + 1.2 {
            gate.read(IslandBeatFrame(low: 0.02, mid: 0.6, high: 0.5), at: time)
            time += Self.step
        }
        #expect(gate.isArmed)
    }

    @Test func aDropNeedsTheBeamsToHaveBeenDarkAMoment() {
        var director = Self.director()
        var frames = Self.groove(from: 0, for: 10)
        frames += Self.noBass(from: 10, for: 1.6)
        Self.run(&director, frames)
        // Dark only just now: the bass back this soon is the groove again.
        guard case let .blackout(since) = director.section else {
            Issue.record("Not dark after a second and a half with no bass")
            return
        }
        let soon = since + IslandLaserShow.leastDark - 0.1
        let cues = director.follow(IslandBeatFrame(low: 1, mid: 0.9, high: 0.9, hit: .kick), at: soon)
        #expect(!cues.contains { Self.isBurst($0) })
        #expect(Self.shown(cues[0]) != nil)
        #expect(director.drops == 0 && director.section == .groove)
    }

    @Test func thereIsOneDropAPhraseAtMost() {
        var director = Self.director()
        var frames = Self.groove(from: 0, for: 10)
        // The same gap and the same full return, three times over, eight
        // seconds apart: the first is the drop and the two after it,
        // inside the same phrase, are only the groove again.
        for start in [10.0, 20, 30] {
            frames += Self.noBass(from: start, for: 2)
            frames.append((start + 2, IslandBeatFrame(low: 1, mid: 0.9, high: 0.9, hit: .kick)))
            frames += Array(Self.groove(from: start + 2, for: 8).dropFirst())
        }
        let cues = Self.run(&director, frames)
        let bursts = cues.filter { Self.isBurst($0.cue) }.map(\.time)
        #expect(bursts == [12, 32])
        #expect(director.drops == 2)
        #expect(director.blackouts == 3)
        #expect(32 - 12 >= IslandLaserShow.phrase)
    }

    @Test func withDimFlashingLightsOnADropWithNoRoomForItsFlashIsNoDrop() {
        func cues(dimmed: Bool) -> (director: IslandLaserDirector, cues: [IslandLaserCue]) {
            var director = Self.director()
            if dimmed { director.flashRule = .dimmed }
            Self.run(&director, Self.groove(from: 0, for: 10))
            // The bass goes at once, and three claps land in the second
            // before the beams go dark.
            for index in 0..<20 {
                let time = 10 + Double(index) * Self.step
                let clap = [6, 10, 14].contains(index)
                _ = director.follow(
                    IslandBeatFrame(low: 0.02, mid: 0.9, high: 0.6, hit: clap ? .snare : nil), at: time
                )
            }
            // Dark for a third of a second, and everything is back.
            let back = director.follow(IslandBeatFrame(low: 1, mid: 0.9, high: 0.9, hit: .kick), at: 11.35)
            return (director, back)
        }

        // As the owner has it: the hits are followed, and it is a drop.
        let free = cues(dimmed: false)
        #expect(free.director.drops == 1)
        #expect(free.cues.count == 1 && Self.isBurst(free.cues[0]))

        // With the system asked to dim flashing lights the three claps
        // were the second's three flashes, and the burst would be a fourth.
        let dimmed = cues(dimmed: true)
        #expect(dimmed.director.drops == 0)
        #expect(!dimmed.cues.contains { Self.isBurst($0) })
        #expect(dimmed.director.section == .groove)
        let log = dimmed.director.flashLog
        #expect(log.count <= IslandBeatLimits.dimmedFlashesPerSecond)
    }

    @Test func aNewShowCountsTheFlashesThatCameJustBeforeIt() {
        var first = Self.director()
        first.flashRule = .dimmed
        Self.run(&first, [(0, IslandBeatFrame(low: 0.7, mid: 0.5, high: 0.5))])
        for time in [1.0, 1.3, 1.6] {
            #expect(!first.follow(IslandBeatFrame(low: 0.7, mid: 1, hit: .snare), at: time).isEmpty)
        }
        #expect(first.flashLog == [1.0, 1.3, 1.6])

        // The next song, with no gap: its show starts with those three.
        var next = IslandLaserDirector(
            program: IslandLaserProgram(seed: IslandLaserSeed.seed(title: "Talk", artist: "Yeat", tint: nil)),
            flashLog: first.flashLog
        )
        next.flashRule = .dimmed
        Self.run(&next, [(1.7, IslandBeatFrame(low: 0.7, mid: 0.5, high: 0.5))])
        #expect(next.follow(IslandBeatFrame(low: 0.7, mid: 1, hit: .snare), at: 1.9).isEmpty)
        // A second after the first of them there is room again.
        #expect(!next.follow(IslandBeatFrame(low: 0.7, mid: 1, hit: .snare), at: 2.05).isEmpty)
        // Carried in from the other mode, they count the same.
        var carried = Self.director()
        carried.carry(flashes: [1.6, 1.0, 1.3, 1.0])
        #expect(carried.flashLog == [1.0, 1.3, 1.6])
    }

    @Test func aQuietLookIsStillUntilAHitStirsItAndThenOnlyOnce() throws {
        var director = Self.director()
        var frames = Self.groove(from: 0, for: 10)
        frames += Self.noBass(from: 10, for: 10)
        Self.run(&director, frames)
        #expect(director.section == .lull)

        // Seconds with no hit: nothing is asked of the beams at all.
        let quiet = Self.run(&director, Self.noBass(from: 20, for: 6).map { ($0.0, IslandBeatFrame(low: 0.02, mid: 0.6, high: 0.6)) })
        #expect(quiet.isEmpty)

        // A clap moves the look once, and claps during that move wait.
        let look = director.picture
        #expect(director.follow(IslandBeatFrame(low: 0.02, mid: 1, hit: .snare), at: 26) == [.stir(look)])
        #expect(director.follow(IslandBeatFrame(low: 0.02, mid: 1, hit: .snare), at: 27).isEmpty)
        #expect(director.follow(IslandBeatFrame(low: 0.02, mid: 1, hit: .snare), at: 29.9).isEmpty)
        #expect(director.follow(IslandBeatFrame(low: 0.02, mid: 1, hit: .snare), at: 30) == [.stir(look)])
        // A hat is the small flicker it always is.
        #expect(director.follow(IslandBeatFrame(low: 0.02, high: 0.8, hit: .hat), at: 31) == [.shimmer(0.8)])

        // A phrase on, a clap brings the other quiet look.
        let turned = director.follow(IslandBeatFrame(low: 0.02, mid: 1, hit: .snare), at: 40)
        #expect(Self.shown(try #require(turned.first))?.look == director.program.lulls[1])
    }

    @Test func aBlackoutGivesUpAfterEightSecondsAndTheQuietLooksComeOn() throws {
        var director = Self.director()
        var frames = Self.groove(from: 0, for: 10)
        frames += Self.noBass(from: 10, for: 14)
        let cues = Self.run(&director, frames)

        let dark = try #require(cues.first { Self.isDark($0.cue) })
        let lull = try #require(cues.first { $0.time > dark.time && Self.shown($0.cue) != nil })
        #expect(lull.time - dark.time >= IslandLaserShow.longestBlackout)
        #expect(lull.time - dark.time < IslandLaserShow.longestBlackout + 0.1)
        #expect(Self.shown(lull.cue)?.look == director.program.lulls[0])
        #expect(director.section == .lull)
        #expect(director.drops == 0)

        // The bass back with everything is the drop from here too.
        let back = director.follow(IslandBeatFrame(low: 1, mid: 0.9, high: 0.9, hit: .kick), at: 24)
        #expect(back.count == 1 && Self.isBurst(back[0]))
        #expect(director.drops == 1)
    }

    @Test func theBassComingBackSoftlyIsTheGrooveAgainAndNoDrop() {
        var director = Self.director()
        var frames = Self.groove(from: 0, for: 10)
        frames += Self.noBass(from: 10, for: 3)
        let before = director.program.looks[0]
        Self.run(&director, frames)
        #expect(director.isDark)

        // A low hit with nothing else rising with it.
        let cues = director.follow(IslandBeatFrame(low: 0.7, mid: 0.3, high: 0.2, hit: .kick), at: 13)
        #expect(Self.shown(cues[0])?.look == before)
        #expect(!cues.contains { Self.isBurst($0) })
        #expect(director.section == .groove)
        #expect(director.drops == 0 && director.paletteIndex == 0)
    }

    /// The same gap as sound, through the analyzer and the throttle the
    /// app uses: ten seconds of a held bass with a kick every half second
    /// under a mid tone and a high one, two seconds of the tones alone,
    /// and everything back louder.
    @Test func theGateHearsAGapAndAReturnInSoundTheAnalyzerRead() {
        let rate = 48_000.0
        let hop = 512
        var analyzer = IslandBeatAnalyzer(sampleRate: rate, bufferFrames: hop)
        var throttle = IslandBeatThrottle()
        var director = Self.director()
        var darkAt: [Double] = []
        var burstAt: [Double] = []

        for index in 0..<Int(16 * rate) / hop {
            let samples: [Float] = (0..<hop).map { offset in
                let time = Double(index * hop + offset) / rate
                let isGap = time >= 10 && time < 12
                let gain = time >= 12 ? 1.5 : 1
                let kick = 0.3 + 0.35 * exp(-time.truncatingRemainder(dividingBy: 0.5) / 0.08)
                let bass = isGap ? 0 : kick * sin(2 * Double.pi * 55 * time)
                let tones = 0.12 * sin(2 * Double.pi * 900 * time) + 0.06 * sin(2 * Double.pi * 8_000 * time)
                return Float(gain * (bass + tones))
            }
            let time = Double((index + 1) * hop) / rate
            guard let frame = throttle.take(analyzer.process(samples), at: time) else { continue }
            for cue in director.follow(frame, at: time) {
                if Self.isDark(cue) { darkAt.append(time) }
                if Self.isBurst(cue) { burstAt.append(time) }
            }
        }

        #expect(director.blackouts == 1)
        #expect(director.drops == 1)
        #expect(darkAt.count == 1 && burstAt.count == 1)
        // Dark once the bass had been gone a second, which the analyzer
        // needs a moment to be sure of, and the burst with its return.
        #expect((darkAt.first ?? 0) > 11 && (darkAt.first ?? 0) < 11.9)
        #expect((burstAt.first ?? 0) >= 12 && (burstAt.first ?? 0) < 12.1)
    }

    // MARK: Idle

    @Test func twoSecondsUnderTheFloorIsDarknessAndSoundBringsTheLookBack() throws {
        var director = Self.director()
        #expect(director.isDark)
        var frames = Self.groove(from: 0, for: 4)
        let silence = (0..<Int(5 / Self.step)).map { (4 + Double($0) * Self.step, IslandBeatFrame()) }
        frames += silence
        let cues = Self.run(&director, frames)

        let dark = try #require(cues.first { Self.isDark($0.cue) })
        #expect(dark.time >= 4 + IslandLaserShow.idleAfter)
        #expect(dark.time < 4 + IslandLaserShow.idleAfter + 0.1)
        #expect(cues.filter { Self.isDark($0.cue) }.count == 1)
        #expect(director.section == .idle)

        let back = director.follow(IslandBeatFrame(low: 0.6, mid: 0.5, high: 0.4), at: 9.5)
        #expect(back == [.show(director.picture)])
        #expect(!director.isDark)
    }
}
