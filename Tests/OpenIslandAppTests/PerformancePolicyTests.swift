import AppKit
import Foundation
import QuartzCore
import Testing
@testable import OpenIslandApp

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

    @MainActor
    @Test
    func monitoringPollIntervalBacksOffOutsideStartupResolution() {
        #expect(ProcessMonitoringCoordinator.monitoringPollInterval(
            isResolvingInitialLiveSessions: true,
            hasTrackedLiveSessions: false
        ) == 2)
        #expect(ProcessMonitoringCoordinator.monitoringPollInterval(
            isResolvingInitialLiveSessions: false,
            hasTrackedLiveSessions: true
        ) == 60)
        #expect(ProcessMonitoringCoordinator.monitoringPollInterval(
            isResolvingInitialLiveSessions: false,
            hasTrackedLiveSessions: false
        ) == 300)
    }

    @MainActor
    @Test
    func codexDesktopProbeKeepsShortWakeCadenceWhileFullReconcileBacksOff() {
        #expect(ProcessMonitoringCoordinator.monitoringWakeInterval(
            isResolvingInitialLiveSessions: false,
            hasTrackedLiveSessions: false
        ) == 2)
        #expect(ProcessMonitoringCoordinator.monitoringWakeInterval(
            isResolvingInitialLiveSessions: false,
            hasTrackedLiveSessions: true
        ) == 2)
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
}
