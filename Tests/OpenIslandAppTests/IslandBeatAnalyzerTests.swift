import CoreAudio
import Foundation
import Testing
@testable import OpenIslandApp

/// The beat analyzer on made-up signals (D56). No sound device is touched:
/// every signal is an array built here.
struct IslandBeatAnalyzerTests {
    private static let sampleRate: Double = 48_000

    // MARK: Signals

    /// A sound struck at each of `times`: a few tones that die away together.
    private static func struck(
        at times: [Double], seconds: Double, tones: [Double], amplitude: Float, decay: Double
    ) -> [Float] {
        var signal = [Float](repeating: 0, count: Int(seconds * sampleRate))
        // A strike is heard for about ten times its decay.
        let length = Int(decay * 10 * sampleRate)
        for time in times {
            let start = Int((time * sampleRate).rounded())
            for offset in 0..<length where start + offset < signal.count {
                let since = Double(offset) / sampleRate
                var sample = 0.0
                for tone in tones { sample += sin(2 * .pi * tone * since) }
                signal[start + offset] += amplitude * Float(exp(-since / decay) * sample / Double(tones.count))
            }
        }
        return signal
    }

    private static func times(every gap: Double, from start: Double = 0, until end: Double) -> [Double] {
        Array(stride(from: start, to: end, by: gap))
    }

    /// A kick drum: a 60 Hz tone that dies away.
    private static func kicks(
        at times: [Double], seconds: Double, amplitude: Float = 0.8, decay: Double = 0.08
    ) -> [Float] {
        struck(at: times, seconds: seconds, tones: [60], amplitude: amplitude, decay: decay)
    }

    private static func kicks(
        perMinute: Double, seconds: Double, amplitude: Float = 0.8, decay: Double = 0.08
    ) -> [Float] {
        kicks(at: times(every: 60 / perMinute, until: seconds), seconds: seconds, amplitude: amplitude, decay: decay)
    }

    /// A kick as a drum machine makes it: a tone that drops from 160 Hz to
    /// 50 Hz in its first moments, which is what lets it be heard over a
    /// long bass note of nearly its own pitch.
    private static func sweptKicks(at times: [Double], seconds: Double, amplitude: Float = 0.9) -> [Float] {
        var signal = [Float](repeating: 0, count: Int(seconds * sampleRate))
        let length = Int(0.5 * sampleRate)
        for time in times {
            let start = Int((time * sampleRate).rounded())
            var phase = 0.0
            for offset in 0..<length where start + offset < signal.count {
                let since = Double(offset) / sampleRate
                phase += 2 * .pi * (50 + 110 * exp(-since / 0.02)) / sampleRate
                signal[start + offset] += amplitude * Float(exp(-since / 0.07) * sin(phase))
            }
        }
        return signal
    }

    /// A clap or a snare: a short burst in the middle of the spectrum.
    private static func claps(at times: [Double], seconds: Double, amplitude: Float = 0.6) -> [Float] {
        struck(at: times, seconds: seconds, tones: [800, 1_300, 1_900], amplitude: amplitude, decay: 0.025)
    }

    /// A closed hat: a tick far up the spectrum.
    private static func hats(at times: [Double], seconds: Double, amplitude: Float = 0.4) -> [Float] {
        struck(at: times, seconds: seconds, tones: [7_000, 9_300, 11_100], amplitude: amplitude, decay: 0.008)
    }

    private static func tone(hertz: Double, seconds: Double, amplitude: Float = 0.5) -> [Float] {
        (0..<Int(seconds * sampleRate)).map { index in
            amplitude * Float(sin(2 * .pi * hertz * Double(index) / sampleRate))
        }
    }

    private static func mixed(_ signals: [Float]...) -> [Float] {
        guard var sum = signals.first else { return [] }
        for signal in signals.dropFirst() {
            for index in sum.indices where index < signal.count { sum[index] += signal[index] }
        }
        return sum
    }

    /// What the analyzer found, by kind, with the time of the hop that
    /// found it, and the low level after every hop.
    private struct Found {
        var kicks: [Double] = []
        var snares: [Double] = []
        var hats: [Double] = []
        var lowLevels: [Float] = []
        /// How hard each low hit was, in the order of `kicks`.
        var punches: [Float] = []
    }

    /// The signal goes in one hop at a time, which puts each hit in the
    /// chunk it fell in.
    private static func found(in signal: [Float], scaledBy scale: Float = 1) -> Found {
        var analyzer = IslandBeatAnalyzer(sampleRate: sampleRate)
        let hop = analyzer.hopSize
        var found = Found()
        var start = 0
        while start + hop <= signal.count {
            let chunk = scale == 1 ? Array(signal[start..<start + hop]) : signal[start..<start + hop].map { $0 * scale }
            let summary = analyzer.process(chunk)
            let time = Double(start) / sampleRate
            if summary.kicks > 0 {
                found.kicks.append(time)
                found.punches.append(summary.punch)
            }
            if summary.snares > 0 { found.snares.append(time) }
            if summary.hats > 0 { found.hats.append(time) }
            found.lowLevels.append(summary.low)
            start += hop
        }
        return found
    }

    private static let hopTime = 512.0 / 48_000

    /// How many of `hits` have one of `times` within two hops after them,
    /// which is how late a hit may be known.
    private static func caught(_ hits: [Double], in times: [Double]) -> Int {
        hits.filter { hit in times.contains { $0 > hit - hopTime && $0 <= hit + hopTime } }.count
    }

    private static func gaps(_ times: [Double]) -> [Double] {
        zip(times.dropFirst(), times).map { $0 - $1 }
    }

    // MARK: Kicks and the reach

    @Test func everyKickPunchesTheReach() {
        let hits = Self.times(every: 0.5, until: 10)
        let found = Self.found(in: Self.kicks(at: hits, seconds: 10))

        #expect(Self.caught(hits, in: found.kicks) == hits.count)
        #expect(found.kicks.count == hits.count)
        // No hats and nothing in the middle were made up from a kick.
        #expect(found.hats.isEmpty)
    }

    @Test func kicksUnderAHeldBassNoteAreAllCaught() {
        // A long 808 at 45 Hz, struck again every two seconds and still
        // loud when the next one comes, with a kick on every beat over it.
        let bass = Self.struck(
            at: Self.times(every: 2, until: 10), seconds: 10, tones: [45], amplitude: 0.7, decay: 2.5
        )
        let hits = Self.times(every: 0.5, until: 10)
        let found = Self.found(in: Self.mixed(bass, Self.sweptKicks(at: hits, seconds: 10)))

        #expect(Self.caught(hits, in: found.kicks) == hits.count)
    }

    @Test func aHeldLowToneOfThreeSecondsIsOnePunch() {
        // An 808 that starts after a second of nothing and holds for three.
        let silence = [Float](repeating: 0, count: Int(Self.sampleRate))
        let found = Self.found(in: silence + Self.tone(hertz: 45, seconds: 3, amplitude: 0.7) + silence)

        // One hit, where it starts. Nothing after that is a jump, however
        // long it holds.
        #expect(found.kicks.count == 1)
        #expect(Self.caught([1], in: found.kicks) == 1)
        #expect(found.snares.isEmpty)
        // And it is a hard one: out of silence, all the way.
        #expect(found.punches == [1])
    }

    @Test func kicksAHundredFiftyMillisecondsApartGiveOnePunchEach() {
        // A run of sixteen fast kicks, each short enough to end before the next.
        let hits = Self.times(every: 0.15, from: 1, until: 3.4)
        let found = Self.found(in: Self.kicks(at: hits, seconds: 4, decay: 0.03))

        #expect(hits.count == 16)
        #expect(Self.caught(hits, in: found.kicks) == hits.count)
        #expect(found.kicks.count == hits.count)
        #expect(Self.gaps(found.kicks).allSatisfy { $0 >= IslandBeatLimits.punchGap })
    }

    @Test func aPunchGoesAsFarAsItsHitIsHard() {
        // Loud kicks, and one a fifth as loud between each two.
        let loud = Self.times(every: 1, until: 8)
        let soft = Self.times(every: 1, from: 0.5, until: 8)
        let found = Self.found(in: Self.mixed(
            Self.kicks(at: loud, seconds: 8, amplitude: 0.9), Self.kicks(at: soft, seconds: 8, amplitude: 0.18)
        ))

        #expect(found.punches.count == found.kicks.count)
        #expect(found.punches.allSatisfy { $0 >= IslandBeatAnalyzer.leastPunch && $0 <= 1 })
        // A hard hit goes all the way and a soft one visibly less far.
        #expect(Self.caught(loud, in: found.kicks) == loud.count)
        #expect((found.punches.max() ?? 0) == 1)
        #expect((found.punches.min() ?? 1) < 0.9)
    }

    @Test func aHeldBassNoteHoldsTheLevelUp() {
        // Ten seconds of one low tone. After the first half second the
        // level never sags, however long the note goes on.
        let found = Self.found(in: Self.tone(hertz: 50, seconds: 10))
        let settled = found.lowLevels.dropFirst(Int(0.5 / Self.hopTime))

        #expect(settled.count > 800)
        #expect((settled.min() ?? 0) > 0.7)
        // And a note that only holds is hit once, when it starts.
        #expect(found.kicks.count <= 1)
    }

    @Test func aKickPatternOverAHeldToneStillGivesItsKicks() {
        let hits = Self.times(every: 0.5, from: 1, until: 10)
        let found = Self.found(in: Self.mixed(
            Self.tone(hertz: 50, seconds: 10, amplitude: 0.3),
            Self.sweptKicks(at: hits, seconds: 10)
        ))

        #expect(Self.caught(hits, in: found.kicks) == hits.count)
    }

    @Test func aHitIsKnownByItsSecondHop() {
        // Kicks and claps that start anywhere inside a hop, which is where
        // a real song puts them.
        let kickTimes = Self.times(every: 60.0 / 128, until: 12)
        let clapTimes = Self.times(every: 60.0 / 128, from: 0.23, until: 12)
        let found = Self.found(in: Self.mixed(
            Self.kicks(at: kickTimes, seconds: 12), Self.claps(at: clapTimes, seconds: 12)
        ))

        for (hits, times) in [(kickTimes, found.kicks), (clapTimes, found.snares)] {
            #expect(Self.caught(hits, in: times) >= hits.count - 1)
            for time in times {
                // The time is where the hop that found the hit began. It
                // is known when that hop ends.
                let nearest = hits.min { abs($0 - time) < abs($1 - time) } ?? 0
                let knownAfter = time + Self.hopTime - nearest
                #expect(knownAfter > 0)
                #expect(knownAfter <= Self.hopTime * Double(IslandBeatTiming.hopsToDetect) + 0.000_5)
            }
        }
    }

    // MARK: Claps, hats and the color

    @Test func aClapOnTwoAndFourIsAFlashAndAKickIsAPunch() {
        // Kicks on one and three, claps on two and four, at 120 a minute.
        let kickTimes = Self.times(every: 1, until: 12)
        let clapTimes = Self.times(every: 1, from: 0.5, until: 12)
        let found = Self.found(in: Self.mixed(
            Self.kicks(at: kickTimes, seconds: 12), Self.claps(at: clapTimes, seconds: 12)
        ))

        // Each is its own kind, and neither is taken for the other.
        #expect(Self.caught(clapTimes, in: found.snares) == clapTimes.count)
        #expect(found.snares.count == clapTimes.count)
        #expect(Self.caught(kickTimes, in: found.kicks) == kickTimes.count)
        #expect(found.kicks.count == kickTimes.count)
    }

    @Test func aHatPatternAloneNeverStepsTheColorOrMovesTheReach() {
        let hits = Self.times(every: 0.125, until: 8)
        let found = Self.found(in: Self.hats(at: hits, seconds: 8))

        #expect(found.snares.isEmpty)
        #expect(found.kicks.isEmpty)
        #expect(found.hats.count >= hits.count - 2)
        // What little of a hat is down in the bass moves the reach by a
        // twentieth at the most.
        #expect(found.lowLevels.allSatisfy { $0 < 0.06 })
    }

    @Test func hatsOverABeatAreStillOnlyHats() {
        let kickTimes = Self.times(every: 0.5, until: 8)
        let hatTimes = Self.times(every: 0.125, from: 0.0625, until: 8)
        let found = Self.found(in: Self.mixed(
            Self.kicks(at: kickTimes, seconds: 8), Self.hats(at: hatTimes, seconds: 8, amplitude: 0.2)
        ))

        #expect(Self.caught(hatTimes, in: found.hats) >= hatTimes.count - 4)
        #expect(Self.caught(kickTimes, in: found.kicks) == kickTimes.count)
    }

    @Test func aWeakBeatDoesNotStepTheColor() {
        // Loud claps every second, and one a seventh as loud between them.
        let loud = Self.times(every: 1, until: 10)
        let weak = Self.times(every: 1, from: 0.5, until: 10)
        let found = Self.found(in: Self.mixed(
            Self.claps(at: loud, seconds: 10, amplitude: 0.7), Self.claps(at: weak, seconds: 10, amplitude: 0.1)
        ))

        #expect(Self.caught(loud, in: found.snares) == loud.count)
        #expect(Self.caught(weak, in: found.snares) == 0)
        #expect(found.snares.count == loud.count)
    }

    @Test func aRollOfHitsATenthOfASecondApartFlashesForEach() {
        let roll = Self.times(every: 0.1, from: 1, until: 3)
        let found = Self.found(in: Self.claps(at: roll, seconds: 4))

        #expect(Self.caught(roll, in: found.snares) == roll.count)
        #expect(found.snares.count == roll.count)
    }

    @Test func hitsCloserThanTheGapAreOneFlash() {
        // A flam: two claps 30 ms apart. The eye gets one hit.
        let flams = Self.times(every: 0.5, from: 1, until: 4)
        let found = Self.found(in: Self.mixed(
            Self.claps(at: flams, seconds: 5), Self.claps(at: flams.map { $0 + 0.03 }, seconds: 5)
        ))

        #expect(found.snares.count == flams.count)
        #expect(Self.gaps(found.snares).allSatisfy { $0 >= IslandBeatLimits.flashGap })
    }

    // MARK: Nothing, and the same at any loudness

    @Test func silenceDoesNothing() {
        var analyzer = IslandBeatAnalyzer(sampleRate: Self.sampleRate)
        let summary = analyzer.process([Float](repeating: 0, count: Int(2 * Self.sampleRate)))

        #expect(summary == IslandBeatSummary())
        #expect(summary.hit == nil)
        #expect(summary.isSilent)
    }

    @Test func aTenthOfTheLoudnessGivesTheSameEvents() {
        let song = Self.mixed(
            Self.kicks(at: Self.times(every: 0.5, until: 8), seconds: 8),
            Self.claps(at: Self.times(every: 1, from: 0.5, until: 8), seconds: 8),
            Self.hats(at: Self.times(every: 0.25, from: 0.125, until: 8), seconds: 8, amplitude: 0.25),
            Self.tone(hertz: 45, seconds: 8, amplitude: 0.2)
        )
        let loud = Self.found(in: song)
        let quiet = Self.found(in: song, scaledBy: 0.1)

        #expect(loud.kicks == quiet.kicks)
        #expect(loud.snares == quiet.snares)
        #expect(loud.hats == quiet.hats)
        #expect(loud.kicks.count >= 15)
        #expect(loud.snares.count >= 7)
        #expect(loud.hats.count >= 20)
    }

    @Test func theLevelsStayBetweenZeroAndOne() {
        var generator = SplitMix(seed: 7)
        var analyzer = IslandBeatAnalyzer(sampleRate: Self.sampleRate)
        let kicks = Self.kicks(perMinute: 140, seconds: 6, amplitude: 1)
        var start = 0
        while start < kicks.count {
            // Chunks of uneven size, as a device hands them over, with
            // noise far louder than any real sample on top.
            let size = min(Int.random(in: 64...2_048, using: &generator), kicks.count - start)
            let chunk = kicks[start..<start + size].map { $0 + Float.random(in: -4...4, using: &generator) }
            let summary = analyzer.process(chunk)
            for level in [summary.low, summary.mid, summary.high] {
                #expect((0...1).contains(level))
            }
            start += size
        }
    }

    @Test func theSameSoundInDifferentChunksGivesTheSameHits() {
        let signal = Self.mixed(
            Self.kicks(perMinute: 120, seconds: 6),
            Self.claps(at: Self.times(every: 1, from: 0.5, until: 6), seconds: 6)
        )
        func hits(chunk: Int) -> [Int] {
            var analyzer = IslandBeatAnalyzer(sampleRate: Self.sampleRate)
            var total = IslandBeatSummary()
            var start = 0
            while start < signal.count {
                let size = min(chunk, signal.count - start)
                total = total.followed(by: analyzer.process(Array(signal[start..<start + size])))
                start += size
            }
            return [total.kicks, total.snares, total.hats]
        }

        #expect(hits(chunk: 512) == hits(chunk: 4_096))
        #expect(hits(chunk: 512) == hits(chunk: 37))
        #expect(hits(chunk: 512)[0] >= 11)
    }

    @Test func aChunkToldAboutOnlyItsBestHit() {
        // A kick with a clap on it is the kick: a punch shows both.
        #expect(IslandBeatSummary(snares: 1, kicks: 1, hats: 1).hit == .kick)
        #expect(IslandBeatSummary(snares: 2, hats: 1).hit == .snare)
        #expect(IslandBeatSummary(hats: 3).hit == .hat)
        #expect(IslandBeatSummary(low: 0.9).hit == nil)
    }

    @Test func aRateTheDeviceDidNotReportFallsBackToAUsualOne() {
        #expect(IslandBeatAnalyzer(sampleRate: 0).sampleRate == IslandBeatAnalyzer.fallbackSampleRate)
        #expect(IslandBeatAnalyzer(sampleRate: .nan).sampleRate == IslandBeatAnalyzer.fallbackSampleRate)
        #expect(IslandBeatAnalyzer(sampleRate: 44_100).hopSize == 470)
    }

    @Test func oneDeviceBufferIsOneHopWhenItIsAUsualSize() {
        #expect(IslandBeatAnalyzer(sampleRate: 48_000).hopSize == 512)
        #expect(IslandBeatAnalyzer(sampleRate: 48_000, bufferFrames: 512).hopSize == 512)
        #expect(IslandBeatAnalyzer(sampleRate: 48_000, bufferFrames: 256).hopSize == 256)
        #expect(IslandBeatAnalyzer(sampleRate: 44_100, bufferFrames: 1_024).hopSize == 1_024)
        // A device with huge or tiny buffers gets the usual hop.
        #expect(IslandBeatAnalyzer(sampleRate: 48_000, bufferFrames: 4_096).hopSize == 512)
        #expect(IslandBeatAnalyzer(sampleRate: 48_000, bufferFrames: 16).hopSize == 512)
        #expect(IslandBeatAnalyzer(sampleRate: 48_000, bufferFrames: 0).hopSize == 512)
    }

    @Test func theGapsAreNeverShorterThanTheirLimitsAtAnyRate() {
        for rate in [44_100.0, 48_000, 88_200, 96_000, 192_000] {
            let analyzer = IslandBeatAnalyzer(sampleRate: rate)
            let hop = Double(analyzer.hopSize) / rate
            #expect(Double(analyzer.flashGapHops) * hop >= IslandBeatLimits.flashGap)
            #expect(Double(analyzer.flashGapHops) * hop < IslandBeatLimits.flashGap + hop)
            #expect(Double(analyzer.punchGapHops) * hop >= IslandBeatLimits.punchGap)
            #expect(Double(analyzer.shimmerGapHops) * hop >= IslandBeatLimits.shimmerGap)
        }
    }

    // MARK: On the beat

    @Test func aHitReachesTheLightWithinThirtyFiveMilliseconds() {
        let delay = IslandBeatTiming.pipelineDelay(sampleRate: 48_000, hopSize: 512)

        #expect(delay <= 0.035)
        #expect(abs(delay - 2 * 512.0 / 48_000) < 0.000_001)
        #expect(IslandBeatTiming.usualPipelineDelay == delay)
        // Its parts: two hops to find it, no wait for a turn, no rise.
        #expect(IslandBeatTiming.hopsToDetect == 2)
        #expect(IslandBeatTiming.beatHandOff == 0)
        #expect(IslandBeatTiming.beatRise == 0)
        // What the first build did, from the same function: a 20 ms hop,
        // a threshold on the envelope, a turn in the 30 a second line and
        // an 80 ms rise.
        let before = IslandBeatTiming.pipelineDelay(
            sampleRate: 48_000, hopSize: 960, hopsToDetect: 3, handOff: 1.0 / 30, rise: 0.08
        )
        #expect(before > 0.15)
    }

    @Test func theSpeakersDelayIsItsLatencyItsOffsetsAndOneBuffer() {
        // Parts that add up to the 12.9 ms the owner's MacBook speakers report.
        let builtIn = IslandBeatTiming.outputDelay(
            deviceLatency: 59, safetyOffset: 48, streamLatency: 0, bufferFrames: 512, sampleRate: 48_000
        )
        #expect(abs(builtIn - 0.0129) < 0.000_1)
        #expect(IslandBeatTiming.outputDelay(
            deviceLatency: 1, safetyOffset: 1, streamLatency: 1, bufferFrames: 1, sampleRate: 0
        ) == 0)
    }

    @Test func aSlowSpeakerHoldsTheHitAndAFastOneDoesNot() {
        let pipeline = IslandBeatTiming.usualPipelineDelay

        // Bluetooth: the light waits for the sound.
        #expect(abs(IslandBeatTiming.hold(outputDelay: 0.180) - (0.180 - pipeline)) < 0.000_001)
        // Built-in and wired: at once.
        #expect(IslandBeatTiming.hold(outputDelay: 0.005) == 0)
        #expect(IslandBeatTiming.hold(outputDelay: 0.0129) == 0)
        #expect(IslandBeatTiming.hold(outputDelay: pipeline) == 0)
        #expect(IslandBeatTiming.hold(outputDelay: 0) == 0)
        // Never longer than the cap, whatever a device claims.
        #expect(IslandBeatTiming.hold(outputDelay: 2) == 0.4)
        #expect(IslandBeatTiming.hold(outputDelay: .infinity) == 0)
        #expect(IslandBeatTiming.hold(outputDelay: .nan) == 0)
        #expect(IslandBeatTiming.longestHold == 0.4)
    }

    // MARK: The throttle

    private static func levels(_ low: Float) -> IslandBeatSummary {
        IslandBeatSummary(low: low, mid: low / 2, high: low / 4, isSilent: false)
    }

    @Test func theMainActorHearsALevelFifteenTimesASecondAndNeverMoreThanThirty() {
        // A chunk every millisecond for one second.
        func frames(_ throttle: IslandBeatThrottle) -> Int {
            var throttle = throttle
            return (0..<1_000).compactMap { throttle.take(Self.levels(0.5), at: Double($0) / 1_000) }.count
        }

        // What the sound queue uses: Core Animation fills in between.
        #expect(IslandBeatThrottle().interval == IslandBeatLimits.levelInterval)
        #expect((13...15).contains(frames(IslandBeatThrottle())))
        // The limit itself, and asking for more gets the limit.
        #expect((25...30).contains(frames(IslandBeatThrottle(interval: IslandBeatLimits.frameInterval))))
        #expect(IslandBeatThrottle(interval: 0.001).interval == IslandBeatLimits.frameInterval)
        #expect(frames(IslandBeatThrottle(interval: 0)) <= 30)
    }

    @Test func aFrameKeepsTheHighestLevelsOfTheChunksItSkipped() {
        var throttle = IslandBeatThrottle(interval: IslandBeatLimits.frameInterval)

        func frame(_ low: Float) -> IslandBeatFrame {
            IslandBeatFrame(low: Double(low), mid: Double(low / 2), high: Double(low / 4), hit: nil)
        }
        #expect(throttle.take(Self.levels(0.1), at: 0) == frame(0.1))
        // A level that arrives too soon waits for the next frame.
        #expect(throttle.take(Self.levels(0.8), at: 0.010) == nil)
        #expect(throttle.take(Self.levels(0.1), at: 0.020) == nil)
        #expect(throttle.take(Self.levels(0.1), at: 0.040) == frame(0.8))
        // And then it is spent.
        #expect(throttle.take(Self.levels(0.1), at: 0.080) == frame(0.1))
    }

    @Test func aKickAndASnareDoNotWaitInLine() {
        for hit in [IslandBeatSummary(low: 0.9, snares: 1, isSilent: false),
                    IslandBeatSummary(low: 0.4, kicks: 1, isSilent: false, punch: 0.9)] {
            var throttle = IslandBeatThrottle()
            _ = throttle.take(Self.levels(0.1), at: 0)

            // Two milliseconds after a frame, and it goes out all the same.
            // A kick's frame says how hard the kick was, not how loud the
            // bass is.
            let frame = throttle.take(hit, at: 0.002)
            #expect(frame?.hit == hit.hit)
            #expect(frame?.low == Double(Float(0.9)))
            // The level's turn is counted from the hit.
            #expect(throttle.take(Self.levels(0.1), at: 0.040) == nil)
            #expect(throttle.take(Self.levels(0.1), at: 0.070) != nil)
        }
    }

    @Test func aHatWaitsForTheLimitAtMostAndNeverForALevelsTurn() {
        var throttle = IslandBeatThrottle()
        _ = throttle.take(Self.levels(0.1), at: 0)

        // Ten milliseconds after a frame a hat is kept.
        #expect(throttle.take(IslandBeatSummary(high: 0.7, hats: 1, isSilent: false), at: 0.010) == nil)
        // It goes with the first chunk a thirtieth of a second after that
        // frame, and not with the level's turn a fifteenth after.
        #expect(throttle.take(Self.levels(0.1), at: 0.020) == nil)
        let frame = throttle.take(Self.levels(0.1), at: 0.034)
        #expect(frame?.hit == .hat)
        #expect(frame?.high == Double(Float(0.7)))
    }

    @Test func aFrameTellsTheBestHitOfItsChunks() {
        var throttle = IslandBeatThrottle()
        _ = throttle.take(Self.levels(0.1), at: 0)
        _ = throttle.take(IslandBeatSummary(hats: 1, isSilent: false), at: 0.005)

        #expect(throttle.take(IslandBeatSummary(kicks: 1, isSilent: false), at: 0.010)?.hit == .kick)
    }

    // MARK: The mix to one channel, and only of the tap's own stream

    private static let stereo = IslandTapLayout(sampleRate: 48_000, channels: 2, isInterleaved: true)
    private static let twoBuffers = IslandTapLayout(sampleRate: 48_000, channels: 2, isInterleaved: false)

    /// Runs `body` with a list of one buffer that holds `channels` side by side.
    private static func withList<Result>(
        _ samples: [Float], channels: UInt32, _ body: (UnsafePointer<AudioBufferList>) -> Result
    ) -> Result {
        var samples = samples
        return samples.withUnsafeMutableBytes { bytes in
            var list = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(mNumberChannels: channels, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress)
            )
            return body(&list)
        }
    }

    /// Runs `body` with a list of one buffer for each array, one channel each.
    private static func withList<Result>(
        buffers: [[Float]], _ body: (UnsafePointer<AudioBufferList>) -> Result
    ) -> Result {
        let list = AudioBufferList.allocate(maximumBuffers: buffers.count)
        defer { free(list.unsafeMutablePointer) }
        let copies = buffers.map { samples -> UnsafeMutableBufferPointer<Float> in
            let copy = UnsafeMutableBufferPointer<Float>.allocate(capacity: max(samples.count, 1))
            _ = copy.initialize(from: samples)
            return copy
        }
        defer { copies.forEach { $0.deallocate() } }
        for index in buffers.indices {
            list[index] = AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: UInt32(buffers[index].count * MemoryLayout<Float>.size),
                mData: UnsafeMutableRawPointer(copies[index].baseAddress)
            )
        }
        return body(list.unsafePointer)
    }

    private static func mixed(_ list: UnsafePointer<AudioBufferList>, layout: IslandTapLayout) -> [Float]? {
        guard let frames = IslandBeatMixdown.frames(in: list, layout: layout) else { return nil }
        var out = [Float](repeating: 9, count: frames)
        out.withUnsafeMutableBufferPointer {
            guard let base = $0.baseAddress else { return }
            IslandBeatMixdown.mix(list, layout: layout, from: 0, count: frames, into: base)
        }
        return out
    }

    private static func near(_ values: [Float]?, _ expected: [Float]) -> Bool {
        guard let values, values.count == expected.count else { return false }
        return zip(values, expected).allSatisfy { abs($0 - $1) < 0.000_1 }
    }

    @Test func twoChannelsSideBySideMixToTheirMean() {
        let mono = Self.withList([1, 0, 0.5, 0.5, -1, 1, 0.2, 0.4], channels: 2) { Self.mixed($0, layout: Self.stereo) }
        #expect(Self.near(mono, [0.5, 0.5, 0, 0.3]))
    }

    @Test func oneBufferAChannelMixesToTheMeanToo() {
        let mono = Self.withList(buffers: [[1, 0.5, -1], [0, 0.5, 1]]) { Self.mixed($0, layout: Self.twoBuffers) }
        #expect(Self.near(mono, [0.5, 0.5, 0]))
    }

    @Test func aPieceOfABufferMixesFromWhereItStarts() {
        let piece = Self.withList([1, 1, 2, 2, 3, 3, 4, 4], channels: 2) { list -> [Float] in
            var out = [Float](repeating: 0, count: 2)
            out.withUnsafeMutableBufferPointer {
                IslandBeatMixdown.mix(list, layout: Self.stereo, from: 1, count: 2, into: $0.baseAddress!)
            }
            return out
        }
        #expect(Self.near(piece, [2, 3]))
    }

    @Test func aListThatIsNotTheTapsOwnIsNeverRead() {
        // A third buffer, which is how a headset's microphone would come.
        #expect(Self.withList(buffers: [[1, 1], [1, 1], [0.9, 0.9]]) {
            IslandBeatMixdown.frames(in: $0, layout: Self.twoBuffers)
        } == nil)
        // Too few buffers, the wrong count of channels in one, and one
        // buffer where two were promised.
        #expect(Self.withList(buffers: [[1, 1]]) { IslandBeatMixdown.frames(in: $0, layout: Self.twoBuffers) } == nil)
        #expect(Self.withList([1, 1, 1, 1, 1, 1], channels: 3) { IslandBeatMixdown.frames(in: $0, layout: Self.stereo) } == nil)
        #expect(Self.withList([1, 1, 1, 1], channels: 2) { IslandBeatMixdown.frames(in: $0, layout: Self.twoBuffers) } == nil)
        // Buffers of different lengths, and a size that is no whole frame.
        #expect(Self.withList(buffers: [[1, 1, 1], [1, 1]]) {
            IslandBeatMixdown.frames(in: $0, layout: Self.twoBuffers)
        } == nil)
        #expect(Self.withList([1, 1, 1], channels: 2) { IslandBeatMixdown.frames(in: $0, layout: Self.stereo) } == nil)
        // A buffer with nothing behind it.
        var empty = AudioBufferList(
            mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: 16, mData: nil)
        )
        #expect(IslandBeatMixdown.frames(in: &empty, layout: Self.stereo) == nil)
        // The tap's own, for contrast.
        #expect(Self.withList([1, 1, 1, 1], channels: 2) { IslandBeatMixdown.frames(in: $0, layout: Self.stereo) } == 2)
    }

    @Test func theLayoutIsReadFromTheTapsOwnFormat() {
        var format = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
            mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0
        )
        #expect(IslandTapLayout(format: format) == Self.stereo)
        #expect(Self.stereo.bufferCount == 1)
        #expect(Self.stereo.channelsInABuffer == 2)

        format.mFormatFlags |= kAudioFormatFlagIsNonInterleaved
        #expect(IslandTapLayout(format: format) == Self.twoBuffers)
        #expect(Self.twoBuffers.bufferCount == 2)
        #expect(Self.twoBuffers.channelsInABuffer == 1)

        // Anything that is not 32-bit float sound is refused outright.
        var integers = format
        integers.mFormatFlags = kAudioFormatFlagIsSignedInteger
        #expect(IslandTapLayout(format: integers) == nil)
        var sixteen = format
        sixteen.mBitsPerChannel = 16
        #expect(IslandTapLayout(format: sixteen) == nil)
        var none = format
        none.mChannelsPerFrame = 0
        #expect(IslandTapLayout(format: none) == nil)
        var many = format
        many.mChannelsPerFrame = 64
        #expect(IslandTapLayout(format: many) == nil)
    }

    @Test func aMicrophoneOnTheOutputKeepsItOutOfTheDevice() {
        #expect(IslandSoundTapPlan.usesOutputAsSubDevice(outputHasInputs: false))
        #expect(!IslandSoundTapPlan.usesOutputAsSubDevice(outputHasInputs: true))

        let alone = IslandSoundTapPlan.deviceDescription(name: "n", uid: "u", tapUID: "t", outputUID: nil)
        #expect(alone[kAudioAggregateDeviceSubDeviceListKey] == nil)
        #expect(alone[kAudioAggregateDeviceMainSubDeviceKey] == nil)
        let taps = alone[kAudioAggregateDeviceTapListKey] as? [[String: Any]]
        #expect(taps?.count == 1)
        #expect(taps?.first?[kAudioSubTapUIDKey] as? String == "t")
        #expect(alone[kAudioAggregateDeviceIsPrivateKey] as? Bool == true)

        let clocked = IslandSoundTapPlan.deviceDescription(name: "n", uid: "u", tapUID: "t", outputUID: "speakers")
        #expect(clocked[kAudioAggregateDeviceMainSubDeviceKey] as? String == "speakers")
        let subs = clocked[kAudioAggregateDeviceSubDeviceListKey] as? [[String: Any]]
        #expect(subs?.count == 1)
        #expect(subs?.first?[kAudioSubDeviceUIDKey] as? String == "speakers")
    }

    // MARK: The sound queue's own path

    @Test @MainActor func theRelayUsesOneBlockOfMemoryForEveryBuffer() {
        let relay = IslandBeatRelay(deliver: { _ in }, refuse: {})
        let memory = relay.scratchAddress
        var generator = SplitMix(seed: 11)

        // Buffers of every size a device hands over, one of them larger
        // than the working memory, which goes through in pieces.
        for frames in [512, 64, 1_024, 480, 4_096, 10_000, 1] {
            let samples = (0..<frames * 2).map { _ in Float.random(in: -1...1, using: &generator) }
            let summary = Self.withList(samples, channels: 2) { relay.read($0, layout: Self.stereo, frames: frames) }
            #expect(summary != nil)
            #expect(relay.scratchAddress == memory)
        }
        #expect(IslandBeatScratch.capacity == 4_096)
    }

    @Test @MainActor func aBufferLargerThanTheMemoryReadsTheSameInPieces() {
        let signal = Self.kicks(perMinute: 150, seconds: 3)
        let stereo = signal.flatMap { [$0, $0] }
        // All at once, which is 144,000 frames against 4,096 of memory.
        let whole = IslandBeatRelay(deliver: { _ in }, refuse: {})
        let atOnce = Self.withList(stereo, channels: 2) { whole.read($0, layout: Self.stereo, frames: signal.count) }
        // And the plain analyzer on the same mono signal.
        var analyzer = IslandBeatAnalyzer(sampleRate: 48_000, bufferFrames: signal.count)
        let plain = analyzer.process(signal)

        #expect(atOnce?.kicks == plain.kicks)
        #expect(atOnce?.snares == plain.snares)
        #expect((7...8).contains(plain.kicks))
    }

    @Test @MainActor func aNewSampleRateIsANewAnalyzerAndItsTimesHold() throws {
        let relay = IslandBeatRelay(deliver: { _ in }, refuse: {})
        let quiet = [Float](repeating: 0, count: 1_024)

        _ = Self.withList(quiet, channels: 2) { relay.read($0, layout: Self.stereo, frames: 512) }
        let first = try #require(relay.analyzerInUse)
        #expect(first.sampleRate == 48_000)

        // The output goes to 96 kHz and the tap is built again.
        let fast = IslandTapLayout(sampleRate: 96_000, channels: 2, isInterleaved: true)
        _ = Self.withList(quiet, channels: 2) { relay.read($0, layout: fast, frames: 512) }
        let second = try #require(relay.analyzerInUse)
        #expect(second.sampleRate == 96_000)
        // The gap between two flashes is the same time at both rates.
        for analyzer in [first, second] {
            let gap = Double(analyzer.flashGapHops * analyzer.hopSize) / analyzer.sampleRate
            #expect(gap >= IslandBeatLimits.flashGap)
        }
        // The old analyzer at the new rate would have halved it, and all
        // of its other times with it.
        #expect(Double(first.flashGapHops * first.hopSize) / 96_000 < IslandBeatLimits.flashGap)
    }

    @Test func theAnalyzerNeedsNoMoreMemoryThanItWasHanded() {
        let scratch = IslandBeatScratch()
        var analyzer = IslandBeatAnalyzer(sampleRate: 48_000)
        // More frames than there is room for are not read.
        let summary = analyzer.process(frames: 1_000_000, in: scratch)
        #expect(summary.isSilent)
        #expect(analyzer.process(frames: 0, in: scratch) == IslandBeatSummary())
        #expect(analyzer.process(frames: -5, in: scratch) == IslandBeatSummary())
    }
}

/// A small generator with a seed, which makes a test's noise the same on
/// every run.
private struct SplitMix: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
