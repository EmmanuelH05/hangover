import Foundation
import Testing
@testable import OpenIslandApp

@Suite struct NookRecordTypesTests {
    let start = Date(timeIntervalSince1970: 1_000)

    @Test func pausingKeepsTheStartAndStampsThePause() {
        let phase = NookRecordPhase.recording(startedAt: start, pausedTotal: 2)
        let paused = phase.pausing(at: start.addingTimeInterval(10))
        #expect(paused == .paused(startedAt: start, pausedAt: start.addingTimeInterval(10), pausedTotal: 2))
    }

    @Test func resumingAddsThePauseToTheTotal() {
        let phase = NookRecordPhase.paused(startedAt: start, pausedAt: start.addingTimeInterval(10), pausedTotal: 2)
        let resumed = phase.resuming(at: start.addingTimeInterval(15))
        #expect(resumed == .recording(startedAt: start, pausedTotal: 7))
    }

    @Test func pausingAnythingButRecordingChangesNothing() {
        #expect(NookRecordPhase.idle.pausing(at: start) == .idle)
        #expect(NookRecordPhase.saving.resuming(at: start) == .saving)
    }

    @Test func onlyTheRunningPhasesAreBusy() {
        #expect(NookRecordPhase.countdown(secondsLeft: 2).isBusy)
        #expect(NookRecordPhase.saving.isBusy)
        #expect(!NookRecordPhase.idle.isBusy)
        #expect(!NookRecordPhase.failed(.lowDisk).isBusy)
    }

    @Test func optionsDefaultToFullScreenStandardWithTheNotch() {
        let options = NookRecordOptions()
        #expect(options.capture == .fullScreen)
        #expect(options.quality == .standard)
        #expect(options.includeIsland)
        #expect(options.macSound)
        #expect(!options.faceCam)
        #expect(!options.voice)
    }

    @Test func qualitySetsSizeAndFrameRate() {
        #expect(NookRecordQuality.standard.maxLongSide == 1920)
        #expect(NookRecordQuality.high.maxLongSide == nil)
        #expect(NookRecordQuality.standard.framesPerSecond == 30)
        #expect(NookRecordQuality.high.framesPerSecond == 60)
    }
}
