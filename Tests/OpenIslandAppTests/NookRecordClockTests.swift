import Foundation
import Testing
@testable import OpenIslandApp

@Suite struct NookRecordClockTests {
    let start = Date(timeIntervalSince1970: 0)

    @Test func elapsedLeavesOutPauses() {
        let phase = NookRecordPhase.recording(startedAt: start, pausedTotal: 5)
        #expect(NookRecordClock.elapsed(phase, now: start.addingTimeInterval(65)) == 60)
    }

    @Test func elapsedStandsStillWhilePaused() {
        let phase = NookRecordPhase.paused(startedAt: start, pausedAt: start.addingTimeInterval(30), pausedTotal: 0)
        #expect(NookRecordClock.elapsed(phase, now: start.addingTimeInterval(500)) == 30)
    }

    @Test func elapsedIsZeroWhenNothingIsRecording() {
        #expect(NookRecordClock.elapsed(.idle, now: start.addingTimeInterval(500)) == 0)
        #expect(NookRecordClock.elapsed(.saving, now: start.addingTimeInterval(500)) == 0)
    }

    @Test func elapsedNeverGoesBelowZero() {
        let phase = NookRecordPhase.recording(startedAt: start, pausedTotal: 5)
        #expect(NookRecordClock.elapsed(phase, now: start.addingTimeInterval(2)) == 0)
    }

    @Test func textGrowsAnHourColumnOnlyWhenNeeded() {
        #expect(NookRecordClock.text(7) == "0:07")
        #expect(NookRecordClock.text(754) == "12:34")
        #expect(NookRecordClock.text(3723) == "1:02:03")
    }
}
