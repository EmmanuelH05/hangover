import AppKit
import Foundation
import QuartzCore
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

struct PerformancePolicyTests {
    @Test
    func idleUnifiedBarsDoesNotRequireAnimationTimeline() {
        #expect(UnifiedBars.Mode.idle.timelineInterval == nil)
    }

    @Test
    func activeUnifiedBarsDoNotRequireAnimationTimeline() {
        #expect(UnifiedBars.Mode.running.timelineInterval == nil)
        #expect(UnifiedBars.Mode.waiting.timelineInterval == nil)
    }

    @Test
    func activeUnifiedBarsUseCoreAnimationLayerAnimation() {
        #expect(!UnifiedBars.Mode.idle.usesLayerAnimation)
        #expect(UnifiedBars.Mode.running.usesLayerAnimation)
        #expect(UnifiedBars.Mode.waiting.usesLayerAnimation)
    }

    // MARK: The glow's loops name a frame rate (D60)

    @Test
    func theGlowsLoopsRunAtFifteenAndThirtyFramesASecond() {
        #expect(Motion.Halo.driftFramesPerSecond == 15)
        #expect(Motion.Halo.breathingFramesPerSecond == 30)
    }

    @Test
    func everyDriftTheAppShowsIsSlowAndEveryBreathIsNot() {
        for metrics in [IslandHaloMetrics.subtle, .vivid] {
            for rest in [metrics.musicOpacity, metrics.runningOpacity] {
                // The drift's range, as the layer builds it around the rest opacity.
                let speed = (min(1, rest * 1.15) - rest * 0.75) / Motion.Halo.driftPeriod
                #expect(Motion.Halo.loopFramesPerSecond(opacityPerSecond: speed) == 15)
            }
            for period in [Motion.Halo.approvalPeriod, Motion.Halo.questionPeriod] {
                let speed = (metrics.breathingHigh - metrics.breathingLow) / (period / 2)
                #expect(Motion.Halo.loopFramesPerSecond(opacityPerSecond: speed) == 30)
            }
        }
    }

    // MARK: The monitor sleeps until something changes (D55)

    @MainActor
    @Test
    func theFullPassIsASafetyNetMinutesApartOutsideStartupResolution() {
        #expect(ProcessMonitoringCoordinator.monitoringPollInterval(
            isResolvingInitialLiveSessions: true,
            hasTrackedLiveSessions: false
        ) == 2)
        #expect(ProcessMonitoringCoordinator.monitoringPollInterval(
            isResolvingInitialLiveSessions: false,
            hasTrackedLiveSessions: true
        ) == 600)
        #expect(ProcessMonitoringCoordinator.monitoringPollInterval(
            isResolvingInitialLiveSessions: false,
            hasTrackedLiveSessions: false
        ) == 1_800)
    }

    @MainActor
    @Test
    func theLoopWakesOnlyForCodexAppAndPiHeartbeatsBetweenPasses() {
        #expect(ProcessMonitoringCoordinator.monitoringWakeInterval(
            isResolvingInitialLiveSessions: false,
            hasTrackedLiveSessions: false,
            isCodexAppRunning: false,
            hasPiHeartbeatSessions: false
        ) == 1_800)
        #expect(ProcessMonitoringCoordinator.monitoringWakeInterval(
            isResolvingInitialLiveSessions: false,
            hasTrackedLiveSessions: true,
            isCodexAppRunning: false,
            hasPiHeartbeatSessions: false
        ) == 600)
        #expect(ProcessMonitoringCoordinator.monitoringWakeInterval(
            isResolvingInitialLiveSessions: false,
            hasTrackedLiveSessions: true,
            isCodexAppRunning: true,
            hasPiHeartbeatSessions: false
        ) == 10)
        #expect(ProcessMonitoringCoordinator.monitoringWakeInterval(
            isResolvingInitialLiveSessions: false,
            hasTrackedLiveSessions: true,
            isCodexAppRunning: false,
            hasPiHeartbeatSessions: true
        ) == 45)
        #expect(ProcessMonitoringCoordinator.monitoringWakeInterval(
            isResolvingInitialLiveSessions: true,
            hasTrackedLiveSessions: false,
            isCodexAppRunning: true,
            hasPiHeartbeatSessions: true
        ) == 2)
    }

    @MainActor
    @Test
    func aRequestRunsTheFullPassBeforeItsDeadline() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        #expect(ProcessMonitoringCoordinator.shouldPerformFullMonitorReconcile(
            now: now,
            nextFullReconcileAt: now.addingTimeInterval(600),
            isResolvingInitialLiveSessions: false,
            hasTrackedLiveSessions: true,
            hadTrackedLiveSessions: true,
            isRequested: true
        ))
        #expect(!ProcessMonitoringCoordinator.shouldPerformFullMonitorReconcile(
            now: now,
            nextFullReconcileAt: now.addingTimeInterval(600),
            isResolvingInitialLiveSessions: false,
            hasTrackedLiveSessions: true,
            hadTrackedLiveSessions: true,
            isRequested: false
        ))
    }

    @MainActor
    @Test
    func theUsageMeterReadsOnItsOwnOnceAMinuteAndOnceAfterABurstOfClaudeHooks() {
        #expect(HookInstallationCoordinator.claudeUsageRefreshInterval == 60)
        #expect(HookInstallationCoordinator.claudeUsageRefreshDebounce == 1.5)
    }

    @MainActor
    @Test
    func aFirstMissIsConfirmedWithinSecondsNotAtTheSafetyNet() {
        var missedOnce = AgentSession(id: "a", title: "A", tool: .claudeCode, phase: .running, summary: "", updatedAt: .now)
        missedOnce.processNotSeenCount = 1
        var ended = missedOnce
        ended.processNotSeenCount = 2
        ended.isSessionEnded = true
        let seen = AgentSession(id: "b", title: "B", tool: .claudeCode, phase: .running, summary: "", updatedAt: .now)

        #expect(ProcessMonitoringCoordinator.needsConfirmationPass([missedOnce, seen]))
        #expect(!ProcessMonitoringCoordinator.needsConfirmationPass([ended, seen]))
        #expect(!ProcessMonitoringCoordinator.needsConfirmationPass([]))
        #expect(ProcessMonitoringCoordinator.monitoringPollInterval(
            isResolvingInitialLiveSessions: false,
            hasTrackedLiveSessions: true,
            needsConfirmation: true
        ) == 5)
        #expect(ProcessMonitoringCoordinator.confirmationInterval < ProcessMonitoringCoordinator.liveSafetyNetInterval)
    }

    @MainActor
    @Test
    func theSleepNeverPassesTheNextFullPassAndRequestsKeepAFloor() {
        let now = Date(timeIntervalSinceReferenceDate: 2_000)
        #expect(ProcessMonitoringCoordinator.monitoringSleep(
            wakeInterval: 1_800, nextFullReconcileAt: now.addingTimeInterval(5), now: now
        ) == 5)
        #expect(ProcessMonitoringCoordinator.monitoringSleep(
            wakeInterval: 10, nextFullReconcileAt: now.addingTimeInterval(600), now: now
        ) == 10)
        #expect(ProcessMonitoringCoordinator.monitoringSleep(
            wakeInterval: 10, nextFullReconcileAt: now.addingTimeInterval(-1), now: now
        ) == 0.05)
        #expect(ProcessMonitoringCoordinator.requestedPassTime(now: now, lastFullReconcileAt: .distantPast) == now)
        #expect(ProcessMonitoringCoordinator.requestedPassTime(
            now: now, lastFullReconcileAt: now.addingTimeInterval(-2)
        ) == now.addingTimeInterval(3))
        #expect(ProcessMonitoringCoordinator.requestedPassTime(
            now: now, lastFullReconcileAt: now.addingTimeInterval(-5)
        ) == now)
    }

    @MainActor
    @Test
    func trackedSessionTransitionForcesFullReconcileBeforeIdleDeadline() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let idleDeadline = now.addingTimeInterval(300)

        #expect(!ProcessMonitoringCoordinator.shouldPerformFullMonitorReconcile(
            now: now,
            nextFullReconcileAt: idleDeadline,
            isResolvingInitialLiveSessions: false,
            hasTrackedLiveSessions: false,
            hadTrackedLiveSessions: false
        ))
        #expect(ProcessMonitoringCoordinator.shouldPerformFullMonitorReconcile(
            now: now,
            nextFullReconcileAt: idleDeadline,
            isResolvingInitialLiveSessions: false,
            hasTrackedLiveSessions: true,
            hadTrackedLiveSessions: false
        ))
    }

    @Test
    func inactiveSessionDotDoesNotRequireAnimationTimeline() {
        #expect(IslandSessionStateIndicator.animatedDot.timelineInterval(
            presence: .inactive,
            isActionable: false
        ) == nil)
        #expect(IslandSessionStateIndicator.animatedDot.timelineInterval(
            presence: .active,
            isActionable: false
        ) == nil)
        #expect(IslandSessionStateIndicator.animatedDot.timelineInterval(
            presence: .running,
            isActionable: false
        ) == 1.0 / 15.0)
        #expect(IslandSessionStateIndicator.animatedDot.timelineInterval(
            presence: .inactive,
            isActionable: true
        ) == 1.0 / 15.0)
    }

    // MARK: UnifiedBars motion (D16)

    @Test
    func barHeightsDescribeTheRestingShapeOfEachMode() {
        #expect(UnifiedBars.barHeights(for: .idle) == [3, 5, 3])
        #expect(UnifiedBars.barHeights(for: .running) == [4, 6, 4])
        #expect(UnifiedBars.barHeights(for: .waiting) == [10, 0, 10])
    }

    @Test
    func alignedBeginTimeSitsOnTheCycleGridAtOrBeforeNow() {
        let period: CFTimeInterval = 0.9
        let delay: CFTimeInterval = 0.15

        let begin = UnifiedBars.alignedBeginTime(now: 10.3, period: period, delay: delay)

        #expect(abs(begin - 10.05) < 1e-9)
        #expect(begin <= 10.3)
        #expect(begin > 10.3 - period)
        let cycles = (begin - delay) / period
        #expect(abs(cycles - cycles.rounded()) < 1e-9)
    }

    @Test
    func alignedBeginTimeIsStableWithinACycleAndAdvancesByWholePeriods() {
        let period: CFTimeInterval = 1.8
        let first = UnifiedBars.alignedBeginTime(now: 100.1, period: period, delay: 0.9)
        let sameCycle = UnifiedBars.alignedBeginTime(now: 100.7, period: period, delay: 0.9)
        let nextCycle = UnifiedBars.alignedBeginTime(now: 100.1 + period, period: period, delay: 0.9)

        #expect(abs(first - sameCycle) < 1e-9)
        #expect(abs((nextCycle - first) - period) < 1e-9)
    }

    @Test
    func alignedBeginTimeLandsOnTheGridExactlyAtABoundaryAndIgnoresBadPeriods() {
        #expect(abs(UnifiedBars.alignedBeginTime(now: 1.8, period: 0.9, delay: 0) - 1.8) < 1e-9)
        #expect(UnifiedBars.alignedBeginTime(now: 5, period: 0, delay: 0.3) == 5)
        #expect(UnifiedBars.alignedBeginTime(now: 5, period: -1, delay: 0.3) == 5)
    }

    @MainActor
    @Test
    func updatingWithTheSameStateKeepsTheSameLoopAnimation() throws {
        let view = makeBarsView()
        view.update(mode: .running, tint: .white, isPaused: false)
        let loops = view.barLayers.compactMap { $0.animation(forKey: UnifiedBars.LayerView.loopKey) }
        #expect(loops.count == 3)

        view.update(mode: .running, tint: .white, isPaused: false)
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()

        for (barLayer, loop) in zip(view.barLayers, loops) {
            let current = try #require(barLayer.animation(forKey: UnifiedBars.LayerView.loopKey))
            // Core Animation hands back its stored copy, so identity proves no re-add.
            #expect(current === loop)
            #expect(current.beginTime == loop.beginTime)
        }
    }

    @MainActor
    @Test
    func layoutPlacesTheDesignBoxWithoutTouchingAnimations() throws {
        let view = makeBarsView()
        view.update(mode: .waiting, tint: .white, isPaused: false)
        let before = view.barLayers.map { $0.animation(forKey: UnifiedBars.LayerView.loopKey) }

        view.setFrameSize(NSSize(width: 48, height: 48))
        view.layoutSubtreeIfNeeded()

        let box = try #require(view.barLayers[0].superlayer)
        #expect(box.affineTransform().a == 2)
        #expect(box.position == CGPoint(x: 24, y: 24))
        for (barLayer, loop) in zip(view.barLayers, before) {
            #expect(barLayer.animation(forKey: UnifiedBars.LayerView.loopKey) === loop)
        }
    }

    @MainActor
    @Test
    func runningLoopsStartOnTheSharedGridAndStayInPhaseAcrossInstances() throws {
        let first = makeBarsView()
        let second = makeBarsView()
        first.update(mode: .running, tint: .white, isPaused: false)
        second.update(mode: .running, tint: .white, isPaused: false)

        let delays: [CFTimeInterval] = [0, 0.15, 0.30]
        for index in 0..<3 {
            let a = try #require(first.barLayers[index].animation(forKey: UnifiedBars.LayerView.loopKey))
            let b = try #require(second.barLayers[index].animation(forKey: UnifiedBars.LayerView.loopKey))
            let cycles = (a.beginTime - delays[index]) / UnifiedBars.runningPeriod
            #expect(abs(cycles - cycles.rounded()) < 1e-6)
            let apart = (a.beginTime - b.beginTime) / UnifiedBars.runningPeriod
            #expect(abs(apart - apart.rounded()) < 1e-6)
            #expect(a.duration == UnifiedBars.runningPeriod)
        }
    }

    @MainActor
    @Test
    func waitingFadesOuterBarsOnTheGridAndHidesTheMiddleBarWithOpacity() throws {
        let view = makeBarsView()
        view.update(mode: .waiting, tint: .white, isPaused: false)

        let outerDelays: [Int: CFTimeInterval] = [0: 0, 2: 0.9]
        for (index, delay) in outerDelays {
            let loop = try #require(view.barLayers[index].animation(forKey: UnifiedBars.LayerView.loopKey))
            let cycles = (loop.beginTime - delay) / UnifiedBars.waitingPeriod
            #expect(abs(cycles - cycles.rounded()) < 1e-6)
            #expect(loop.duration == UnifiedBars.waitingPeriod)
        }
        #expect(view.barLayers[1].animation(forKey: UnifiedBars.LayerView.loopKey) == nil)
        #expect(view.barLayers[1].opacity == 0)
        #expect(!view.barLayers[1].isHidden)
    }

    @MainActor
    @Test
    func modeChangeSpringsEveryBarThenHandsOverToTheNewLoop() throws {
        let view = makeBarsView()
        view.update(mode: .idle, tint: .white, isPaused: false)
        for barLayer in view.barLayers {
            #expect(barLayer.animationKeys() == nil)
        }

        view.update(mode: .running, tint: .white, isPaused: false)
        for barLayer in view.barLayers {
            let move = try #require(barLayer.animation(forKey: UnifiedBars.LayerView.pathMoveKey) as? CASpringAnimation)
            #expect(move.keyPath == "path")
            #expect(move.settlingDuration > 0.2 && move.settlingDuration < 0.45)
            #expect(barLayer.animation(forKey: UnifiedBars.LayerView.opacityMoveKey) != nil)
            #expect(barLayer.animation(forKey: UnifiedBars.LayerView.loopKey) != nil)
        }

        view.update(mode: .idle, tint: .white, isPaused: false)
        for barLayer in view.barLayers {
            #expect(barLayer.animation(forKey: UnifiedBars.LayerView.loopKey) == nil)
            #expect(barLayer.animation(forKey: UnifiedBars.LayerView.pathMoveKey) != nil)
        }
    }

    @MainActor
    @Test
    func tintChangeCrossFadesFillColorOverThreeTenths() throws {
        let view = makeBarsView()
        view.update(mode: .idle, tint: .white, isPaused: false)
        #expect(view.barLayers[0].animation(forKey: UnifiedBars.LayerView.tintKey) == nil)

        view.update(mode: .idle, tint: .systemBlue, isPaused: false)

        for barLayer in view.barLayers {
            let fade = try #require(barLayer.animation(forKey: UnifiedBars.LayerView.tintKey))
            #expect(abs(fade.duration - 0.3) < 1e-9)
            #expect(barLayer.fillColor == NSColor.systemBlue.cgColor)
        }
    }

    @MainActor
    @Test
    func pausingFreezesTheLayerAndResumingContinuesFromTheFrozenTime() throws {
        let view = makeBarsView()
        let root = try #require(view.layer)
        view.update(mode: .running, tint: .white, isPaused: false)
        #expect(root.speed == 1)

        view.update(mode: .running, tint: .white, isPaused: true)
        #expect(root.speed == 0)
        let frozenAt = root.timeOffset
        #expect(frozenAt > 0)

        view.update(mode: .running, tint: .white, isPaused: false)
        #expect(root.speed == 1)
        #expect(root.timeOffset == 0)
        // The layer's clock picks up from the frozen time, not from media time.
        let local = root.convertTime(CACurrentMediaTime(), from: nil)
        #expect(abs(local - frozenAt) < 0.5)
    }

    @MainActor
    private func makeBarsView() -> UnifiedBars.LayerView {
        UnifiedBars.LayerView(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
    }

    // MARK: The glow that follows a song (D56)

    @Test
    func flashesFollowTheHitsWithOnlyAShortGap() {
        // The owner's rule: a kick, a snare and a clap may each flash, and
        // the gap is only what keeps a fast roll from smearing.
        #expect(IslandBeatLimits.flashGap == 0.07)
        #expect(IslandFlashRule.followsHits.gap == IslandBeatLimits.flashGap)
        #expect(IslandFlashRule.followsHits.mostASecond == nil)
        // The analyzer counts in hops, rounded up: never sooner than the
        // gap, at any sample rate a Mac plays at.
        for rate in [44_100.0, 48_000, 88_200, 96_000, 192_000] {
            let analyzer = IslandBeatAnalyzer(sampleRate: rate)
            let gap = Double(analyzer.flashGapHops * analyzer.hopSize) / rate
            #expect(gap >= IslandBeatLimits.flashGap)
            #expect(gap < IslandBeatLimits.flashGap + IslandBeatAnalyzer.hop)
        }
    }

    @Test
    func aUserWhoAskedForItGetsNoMoreThanThreeFlashesASecond() {
        // "Dim flashing lights" in macOS. Reduce Motion goes further and
        // turns the pulse off through the motion policy.
        #expect(IslandBeatLimits.dimmedFlashesPerSecond == 3)
        #expect(IslandFlashRule.dimmed.mostASecond == 3)
        #expect(IslandFlashRule.dimmed.gap == IslandBeatLimits.dimmedFlashGap)
        #expect(IslandBeatLimits.dimmedFlashGap >= IslandBeatLimits.flashGap)
        #expect(!IslandBeatRules.allowsPulse(.reduced))
    }

    @MainActor
    @Test
    func theGlowItselfCountsTheFlashesOnTheWallClock() {
        // Snares every 20 ms for three seconds, far faster than a song.
        func steps(dims: Bool) -> [Double] {
            let glow = IslandBeatGlow()
            glow.flashingLights = FakeFlashingLights(dims: dims)
            glow.layout(
                frame: CGRect(x: 0, y: 0, width: 360, height: 200), pill: CGSize(width: 200, height: 40), path: nil
            )
            glow.begin(
                IslandHaloPulse(low: 0.25, high: 0.85, hues: IslandBeatHues.fixed, reach: 0.5),
                radius: 12, drop: 3, animated: false
            )
            var time = 50.0
            glow.now = { time }
            var steps: [Double] = []
            for step in 0..<150 {
                time = 50 + Double(step) * 0.02
                let before = glow.hueIndex
                glow.follow(IslandBeatFrame(low: 1, mid: 1, high: 0, hit: .snare))
                if glow.hueIndex != before { steps.append(time) }
            }
            return steps
        }
        func mostInASecond(_ times: [Double]) -> Int {
            times.map { start in times.filter { $0 >= start && $0 < start + 1 - 0.000_001 }.count }.max() ?? 0
        }

        // By default: one flash every 70 ms or more, and no fewer than ten
        // a second when the hits come that fast.
        let free = steps(dims: false)
        #expect(zip(free.dropFirst(), free).allSatisfy { $0 - $1 >= IslandBeatLimits.flashGap - 0.000_001 })
        #expect(mostInASecond(free) >= 10)
        #expect(mostInASecond(free) <= 15)
        // With the setting on: three in any second, whatever arrives.
        let dimmed = steps(dims: true)
        #expect(!dimmed.isEmpty)
        #expect(mostInASecond(dimmed) <= 3)
    }

    @Test
    func theMainActorHearsFromTheListenerAtMostThirtyTimesASecond() {
        // Thirty is the limit that is pinned. Fifteen is what is used, with
        // Core Animation drawing the frames between two targets.
        #expect(IslandBeatLimits.framesPerSecond == 30)
        #expect(IslandBeatLimits.frameInterval == 1.0 / 30)
        #expect(IslandBeatLimits.levelFramesPerSecond == 15)
        #expect(IslandBeatLimits.levelInterval >= IslandBeatLimits.frameInterval)

        // The sound queue hands over a chunk every few milliseconds. Ten
        // seconds of them make no more than three hundred frames at the
        // limit, and no more than a hundred and fifty as used.
        let summary = IslandBeatSummary(low: 0.6, mid: 0.3, high: 0.1, isSilent: false)
        func frames(_ start: IslandBeatThrottle) -> Int {
            var throttle = start
            var frames = 0
            var time = 0.0
            while time < 10 {
                if throttle.take(summary, at: time) != nil { frames += 1 }
                time += 0.0027
            }
            return frames
        }
        let atTheLimit = frames(IslandBeatThrottle(interval: IslandBeatLimits.frameInterval))
        #expect(atTheLimit <= 300)
        #expect(atTheLimit > 200)
        #expect(frames(IslandBeatThrottle(interval: 0)) <= 300)
        let asUsed = frames(IslandBeatThrottle())
        #expect(asUsed <= 150)
        #expect(asUsed > 100)
    }

    @Test
    func theHitsThatSkipTheLineAreFewBecauseOfTheirGaps() {
        // The busiest a song gets: a snare, a kick and a hat as often as
        // the analyzer may give them. Every hop is 10.7 ms.
        let analyzer = IslandBeatAnalyzer(sampleRate: 48_000)
        let hop = Double(analyzer.hopSize) / 48_000
        let atOnce = 1 / (Double(analyzer.flashGapHops) * hop) + 1 / (Double(analyzer.punchGapHops) * hop)
        // Under thirty frames a second even then, without counting levels,
        // which wait for their turn after every hit.
        #expect(atOnce < 30)
        #expect(IslandBeatLimits.punchGap >= IslandBeatLimits.flashGap)
        #expect(IslandBeatLimits.shimmerCeiling == 0.15)
    }

    @MainActor
    @Test
    func aHitCostsTwoShortLayerChangesAndNoPictureIsDrawnAgain() {
        let glow = IslandBeatGlow()
        glow.flashingLights = FakeFlashingLights()
        glow.room = (side: 80, below: 80)
        glow.layout(
            frame: CGRect(x: 0, y: 0, width: 360, height: 200), pill: CGSize(width: 200, height: 40), path: nil
        )
        glow.begin(
            IslandHaloPulse(low: 0.25, high: 0.85, hues: IslandBeatHues.fixed, reach: 1),
            radius: 12, drop: 3, animated: false
        )
        var time = 0.0
        glow.now = {
            time += 0.5
            return time
        }
        let colors = glow.hueLayers.map(\.shadowColor)
        let radii = glow.hueLayers.map(\.shadowRadius)

        // A second of frames at the limit, with every kind of hit.
        let hits: [IslandBeatHit?] = [.snare, nil, nil, .kick, nil, .hat, nil, nil, nil, nil]
        for index in 0..<30 {
            let level = Double(index % 10) / 10
            glow.follow(IslandBeatFrame(low: level, mid: level, high: level, hit: hits[index % 10]))
        }

        // Only a hit moves a layer, and a level alone costs nothing at all.
        #expect(glow.punches + glow.flashes + glow.flickers == 9)
        #expect(glow.hueLayers.allSatisfy { $0.shouldRasterize })
        // Only opacity and scale moved. The colors and the blur radius,
        // which would mean a new blur, did not, at the largest reach too.
        #expect(glow.hueLayers.map(\.shadowColor) == colors)
        #expect(glow.hueLayers.map(\.shadowRadius) == radii)
        #expect(glow.hueLayers.allSatisfy { $0.animationKeys()?.contains { $0.contains("shadow") } != true })
        #expect(glow.hueLayers.allSatisfy { $0.animation(forKey: "beat.color") == nil })
        #expect(glow.peakScale.width > 1)
    }

    @Test
    @MainActor
    func theLightIsBackAtTheNotchFastAfterEveryHit() {
        // The owner's rule: it retracts all the way, and it is fast.
        #expect(IslandBeatGlow.punchFall == 0.14)
        #expect(IslandBeatGlow.flashFall == 0.12)
        // Low hits may come 90 ms apart at the closest, and are shown 70 ms
        // apart at the closest.
        #expect(IslandBeatLimits.punchGap == 0.09)
        #expect(IslandBeatLimits.flashGap == 0.07)
    }
}
