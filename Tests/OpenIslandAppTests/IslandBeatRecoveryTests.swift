import Foundation
import Testing
@testable import OpenIslandApp

/// The analyzer after a sample that is no number (D56). A filter keeps
/// its last two outputs, and one such sample left in them would make
/// every sample after it none too: every band would read nothing until
/// the tap was built again.
@Suite struct IslandBeatRecoveryTests {
    private static let rate = 48_000.0
    private static let hop = 512

    /// A buffer of a held bass note under a mid tone and a high one.
    private static func buffer(_ index: Int) -> [Float] {
        (0..<hop).map { offset in
            let time = Double(index * hop + offset) / rate
            return Float(
                0.5 * sin(2 * Double.pi * 60 * time) + 0.2 * sin(2 * Double.pi * 900 * time)
                    + 0.1 * sin(2 * Double.pi * 8_000 * time)
            )
        }
    }

    @Test func aFilterDropsASampleThatIsNoNumberAndReadsTheNextBufferAsItShould() {
        for bad in [Float.nan, .infinity, -.infinity] {
            var filter = IslandBiquad.lowPass(200, rate: Self.rate)
            var clean = IslandBiquad.lowPass(200, rate: Self.rate)
            let input = UnsafeMutablePointer<Float>.allocate(capacity: Self.hop + 2)
            let output = UnsafeMutablePointer<Float>.allocate(capacity: Self.hop + 2)
            defer {
                input.deallocate()
                output.deallocate()
            }
            // One buffer with the bad sample in it, read by one filter only.
            input.update(repeating: 0, count: Self.hop + 2)
            input[100] = bad
            filter.run(input, into: output, count: Self.hop)

            // The buffer after it: the filter that saw the bad sample gives
            // numbers again, and soon the same ones as a filter that never
            // saw it.
            let samples = Self.buffer(1)
            input[0] = 0
            input[1] = 0
            for (offset, sample) in samples.enumerated() { input[offset + 2] = sample }
            filter.run(input, into: output, count: Self.hop)
            let mine = (2..<Self.hop + 2).map { output[$0] }
            clean.run(input, into: output, count: Self.hop)
            let other = (2..<Self.hop + 2).map { output[$0] }
            #expect(mine.allSatisfy { $0.isFinite })
            #expect(mine == other)
            #expect(mine.contains { abs($0) > 0.1 })
        }
    }

    @Test func theBandsReadTheSongAgainAfterASampleThatIsNoNumber() {
        for bad in [Float.nan, .infinity] {
            var analyzer = IslandBeatAnalyzer(sampleRate: Self.rate, bufferFrames: Self.hop)
            for index in 0..<100 {
                _ = analyzer.process(Self.buffer(index))
            }
            #expect(analyzer.low.level > 0.5)
            #expect(analyzer.mid.level > 0.5)

            var broken = Self.buffer(100)
            broken[7] = bad
            _ = analyzer.process(broken)

            // A second later the three bands read the same song.
            var last = IslandBeatSummary()
            for index in 101..<200 {
                last = analyzer.process(Self.buffer(index))
            }
            #expect(last.low.isFinite && last.mid.isFinite && last.high.isFinite)
            #expect(analyzer.low.level > 0.5)
            #expect(analyzer.mid.level > 0.5)
            #expect(analyzer.high.level > 0.5)
            #expect(!last.isSilent)
        }
    }
}
