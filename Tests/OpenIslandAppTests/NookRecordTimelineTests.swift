import CoreMedia
import Testing
@testable import OpenIslandApp

@Suite struct NookRecordTimelineTests {
    func t(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600) }

    @Test func samplesBeforeAPauseKeepTheirTime() {
        var timeline = NookRecordTimeline()
        timeline.pause(at: t(10))
        #expect(timeline.adjusted(t(9)) == t(9))
    }

    @Test func samplesDuringAPauseAreDropped() {
        var timeline = NookRecordTimeline()
        timeline.pause(at: t(10))
        #expect(timeline.adjusted(t(10)) == nil)
        #expect(timeline.adjusted(t(12)) == nil)
    }

    @Test func samplesAfterResumeMoveBackByThePause() {
        var timeline = NookRecordTimeline()
        timeline.pause(at: t(10))
        timeline.resume(at: t(14))
        #expect(timeline.adjusted(t(14)) == t(10))
        #expect(timeline.adjusted(t(15)) == t(11))
    }

    @Test func twoPausesAddUp() {
        var timeline = NookRecordTimeline()
        timeline.pause(at: t(10)); timeline.resume(at: t(14))
        timeline.pause(at: t(20)); timeline.resume(at: t(21))
        #expect(timeline.adjusted(t(25)) == t(20))
    }

    @Test func aLateSampleFromInsideAPauseIsStillDropped() {
        var timeline = NookRecordTimeline()
        timeline.pause(at: t(10)); timeline.resume(at: t(14))
        #expect(timeline.adjusted(t(12)) == nil)
    }

    @Test func aSecondPauseWhilePausedChangesNothing() {
        var timeline = NookRecordTimeline()
        timeline.pause(at: t(10)); timeline.pause(at: t(12)); timeline.resume(at: t(14))
        #expect(timeline.adjusted(t(14)) == t(10))
    }
}
