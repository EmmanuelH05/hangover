import Foundation
import Testing
@testable import OpenIslandApp

struct IslandHaloStateTests {
    // MARK: Helpers

    private static let tint = IslandHaloRGB.rgb255(10, 200, 30)
    private static let otherTint = IslandHaloRGB.rgb255(200, 10, 90)

    private func inputs(
        style: IslandHaloStyle = .subtle,
        policy: IslandMotionPolicy = .full,
        isOpened: Bool = false,
        waiting: IslandWaitingKind? = nil,
        flashToken: UInt64? = nil,
        noticeTint: IslandHaloRGB? = nil,
        musicTint: IslandHaloRGB? = nil,
        isRunning: Bool = false
    ) -> IslandHaloInputs {
        IslandHaloInputs(
            style: style,
            policy: policy,
            isOpened: isOpened,
            waiting: waiting,
            flashToken: flashToken,
            noticeTint: noticeTint,
            musicTint: musicTint,
            isRunning: isRunning
        )
    }

    private func resolved(_ inputs: IslandHaloInputs) -> IslandHaloState {
        IslandHaloState.resolve(inputs)
    }

    private let subtle = IslandHaloMetrics.subtle
    private let vivid = IslandHaloMetrics.vivid

    // MARK: Priority table

    @Test
    func idleIsOff() {
        #expect(resolved(inputs()) == .off)
        #expect(!resolved(inputs()).isVisible)
    }

    @Test
    func approvalBreathesOrange() {
        let state = resolved(inputs(waiting: .approval))

        #expect(state.source == .approval)
        #expect(state.color == .approval)
        #expect(state.motion == .breathing(period: Motion.Halo.approvalPeriod, low: subtle.breathingLow, high: subtle.breathingHigh))
        #expect(state.restOpacity == subtle.breathingHigh)
        #expect(state.radius == subtle.radius)
        #expect(state.drop == subtle.drop)
        #expect(state.isVisible)
    }

    @Test
    func questionBreathesYellowOnItsOwnPeriod() {
        let state = resolved(inputs(waiting: .question))

        #expect(state.source == .question)
        #expect(state.color == .question)
        #expect(state.motion == .breathing(period: Motion.Halo.questionPeriod, low: subtle.breathingLow, high: subtle.breathingHigh))
        #expect(state.restOpacity == subtle.breathingHigh)
    }

    @Test
    func completionFlashesGreenAndRestsAtZero() {
        let state = resolved(inputs(flashToken: 7))

        #expect(state.source == .completed)
        #expect(state.color == .completed)
        #expect(state.motion == .flash(token: 7, peak: subtle.flashPeak, duration: Motion.Halo.flash))
        #expect(state.restOpacity == 0)
        #expect(state.radius == subtle.radius)
        #expect(state.drop == subtle.drop)
    }

    @Test
    func noticeIsItsOwnTintHeldSteady() {
        let state = resolved(inputs(noticeTint: Self.tint))

        #expect(state.source == .notice)
        #expect(state.color == Self.tint)
        #expect(state.motion == .steady)
        #expect(state.restOpacity == subtle.noticeOpacity)
    }

    @Test
    func musicDriftsInTheArtworkTint() {
        let state = resolved(inputs(musicTint: Self.tint))

        #expect(state.source == .music)
        #expect(state.color == Self.tint)
        #expect(state.motion == .drift(period: Motion.Halo.driftPeriod))
        #expect(state.restOpacity == subtle.musicOpacity)
    }

    @Test
    func runningDriftsBlue() {
        let state = resolved(inputs(isRunning: true))

        #expect(state.source == .running)
        #expect(state.color == .running)
        #expect(state.motion == .drift(period: Motion.Halo.driftPeriod))
        #expect(state.restOpacity == subtle.runningOpacity)
    }

    @Test
    func fullPriorityOrderPeelsOneLayerAtATime() {
        var all = inputs(
            waiting: .approval,
            flashToken: 1,
            noticeTint: Self.tint,
            musicTint: Self.otherTint,
            isRunning: true
        )
        #expect(resolved(all).source == .approval)

        all.waiting = .question
        #expect(resolved(all).source == .question)

        all.waiting = nil
        #expect(resolved(all).source == .completed)

        all.flashToken = nil
        #expect(resolved(all).source == .notice)
        #expect(resolved(all).color == Self.tint)

        all.noticeTint = nil
        #expect(resolved(all).source == .music)
        #expect(resolved(all).color == Self.otherTint)

        all.musicTint = nil
        #expect(resolved(all).source == .running)

        all.isRunning = false
        #expect(resolved(all) == .off)
    }

    @Test
    func approvalBeatsQuestionBecauseWaitingHoldsOneKind() {
        // The inputs carry a single waiting kind (AppModel picks approval
        // first), so the resolver only has to honor what it is given.
        #expect(resolved(inputs(waiting: .approval, isRunning: true)).source == .approval)
        #expect(resolved(inputs(waiting: .question, isRunning: true)).source == .question)
    }

    @Test
    func resolvingTwiceGivesTheSameState() {
        let all = inputs(waiting: .question, flashToken: 3, noticeTint: Self.tint, isRunning: true)
        #expect(resolved(all) == resolved(all))
    }

    // MARK: Style

    @Test
    func styleOffAlwaysResolvesToOff() {
        let everything = inputs(
            style: .off,
            waiting: .approval,
            flashToken: 1,
            noticeTint: Self.tint,
            musicTint: Self.tint,
            isRunning: true
        )
        #expect(resolved(everything) == .off)

        var opened = everything
        opened.isOpened = true
        #expect(resolved(opened) == .off)
    }

    @Test
    func vividUsesTheVividMetrics() {
        let approval = resolved(inputs(style: .vivid, waiting: .approval))
        #expect(approval.motion == .breathing(period: Motion.Halo.approvalPeriod, low: vivid.breathingLow, high: vivid.breathingHigh))
        #expect(approval.radius == vivid.radius)
        #expect(approval.drop == vivid.drop)

        #expect(resolved(inputs(style: .vivid, flashToken: 2)).motion == .flash(token: 2, peak: vivid.flashPeak, duration: Motion.Halo.flash))
        #expect(resolved(inputs(style: .vivid, noticeTint: Self.tint)).restOpacity == vivid.noticeOpacity)
        #expect(resolved(inputs(style: .vivid, musicTint: Self.tint)).restOpacity == vivid.musicOpacity)
        #expect(resolved(inputs(style: .vivid, isRunning: true)).restOpacity == vivid.runningOpacity)
    }

    @Test
    func vividIsStrongerThanSubtleForEveryMoment() {
        #expect(vivid.radius > subtle.radius)
        #expect(vivid.breathingHigh >= subtle.breathingHigh)
        #expect(vivid.flashPeak >= subtle.flashPeak)
        #expect(vivid.noticeOpacity > subtle.noticeOpacity)
        #expect(vivid.musicOpacity > subtle.musicOpacity)
        #expect(vivid.runningOpacity > subtle.runningOpacity)
    }

    // MARK: Island opened

    @Test
    func openedShowsOnlyTheFlash() {
        let opened = IslandHaloMetrics.opened
        let state = resolved(inputs(
            isOpened: true,
            waiting: .approval,
            flashToken: 4,
            noticeTint: Self.tint,
            musicTint: Self.tint,
            isRunning: true
        ))

        #expect(state.source == .completed)
        #expect(state.color == .completed)
        #expect(state.motion == .flash(token: 4, peak: opened.flashPeak, duration: Motion.Halo.flash))
        #expect(state.restOpacity == 0)
        #expect(state.radius == opened.radius)
        #expect(state.drop == opened.drop)
    }

    @Test
    func openedIgnoresStyleMetricsForTheFlash() {
        let subtleFlash = resolved(inputs(style: .subtle, isOpened: true, flashToken: 1))
        let vividFlash = resolved(inputs(style: .vivid, isOpened: true, flashToken: 1))

        #expect(subtleFlash == vividFlash)
        #expect(subtleFlash.radius == IslandHaloMetrics.opened.radius)
    }

    @Test
    func openedWithoutAFlashIsOffWhateverElseIsGoingOn() {
        let busy = inputs(
            isOpened: true,
            waiting: .question,
            noticeTint: Self.tint,
            musicTint: Self.tint,
            isRunning: true
        )
        #expect(resolved(busy) == .off)
    }

    // MARK: Motion policy: reduced

    @Test
    func reducedTurnsBreathingIntoASteadyMidpointGlow() {
        let midpoint = (subtle.breathingLow + subtle.breathingHigh) / 2

        for kind in [IslandWaitingKind.approval, .question] {
            let state = resolved(inputs(policy: .reduced, waiting: kind))
            #expect(state.motion == .steady)
            #expect(state.restOpacity == midpoint)
            #expect(state.color == (kind == .approval ? .approval : .question))
        }
    }

    @Test
    func reducedTurnsDriftIntoSteady() {
        let music = resolved(inputs(policy: .reduced, musicTint: Self.tint))
        #expect(music.source == .music)
        #expect(music.motion == .steady)
        #expect(music.restOpacity == subtle.musicOpacity)

        let running = resolved(inputs(policy: .reduced, isRunning: true))
        #expect(running.source == .running)
        #expect(running.motion == .steady)
        #expect(running.restOpacity == subtle.runningOpacity)
    }

    @Test
    func reducedKeepsTheFlashAsAFlash() {
        let state = resolved(inputs(policy: .reduced, flashToken: 9))
        #expect(state.motion == .flash(token: 9, peak: subtle.flashPeak, duration: Motion.Halo.flash))

        let opened = resolved(inputs(policy: .reduced, isOpened: true, flashToken: 9))
        #expect(opened.motion == .flash(token: 9, peak: IslandHaloMetrics.opened.flashPeak, duration: Motion.Halo.flash))
    }

    @Test
    func reducedKeepsNoticesSteady() {
        let state = resolved(inputs(policy: .reduced, noticeTint: Self.tint))
        #expect(state.motion == .steady)
        #expect(state.restOpacity == subtle.noticeOpacity)
    }

    // MARK: Motion policy: conserving

    @Test
    func conservingDropsMusicAndRunning() {
        #expect(resolved(inputs(policy: .conserving, musicTint: Self.tint)) == .off)
        #expect(resolved(inputs(policy: .conserving, isRunning: true)) == .off)
        #expect(resolved(inputs(policy: .conserving, musicTint: Self.tint, isRunning: true)) == .off)
    }

    @Test
    func conservingKeepsWaitingFlashAndNotice() {
        let waiting = resolved(inputs(policy: .conserving, waiting: .approval))
        #expect(waiting.source == .approval)
        #expect(waiting.motion == .steady)

        let flash = resolved(inputs(policy: .conserving, flashToken: 5))
        #expect(flash.source == .completed)
        #expect(flash.motion == .flash(token: 5, peak: subtle.flashPeak, duration: Motion.Halo.flash))

        let notice = resolved(inputs(policy: .conserving, noticeTint: Self.tint))
        #expect(notice.source == .notice)
        #expect(notice.motion == .steady)
    }

    @Test
    func conservingFallsThroughToTheNextGlowThatIsAllowed() {
        // A notice outranks music, so it still shows; once it is gone the
        // dropped music and running glows leave nothing behind.
        let both = inputs(policy: .conserving, noticeTint: Self.tint, musicTint: Self.otherTint, isRunning: true)
        #expect(resolved(both).source == .notice)

        var without = both
        without.noticeTint = nil
        #expect(resolved(without) == .off)
    }

    // MARK: Motion policy: minimal

    @Test
    func minimalShowsOnlyASteadyWaitingGlow() {
        for kind in [IslandWaitingKind.approval, .question] {
            let state = resolved(inputs(policy: .minimal, waiting: kind))
            #expect(state.source == (kind == .approval ? .approval : .question))
            #expect(state.color == (kind == .approval ? .approval : .question))
            #expect(state.motion == .steady)
            #expect(state.restOpacity == subtle.breathingHigh)
            #expect(state.radius == subtle.radius)
            #expect(state.drop == subtle.drop)
        }
    }

    @Test
    func minimalHidesEverythingThatIsNotWaiting() {
        #expect(resolved(inputs(policy: .minimal, flashToken: 1)) == .off)
        #expect(resolved(inputs(policy: .minimal, noticeTint: Self.tint)) == .off)
        #expect(resolved(inputs(policy: .minimal, musicTint: Self.tint)) == .off)
        #expect(resolved(inputs(policy: .minimal, isRunning: true)) == .off)
        #expect(resolved(inputs(policy: .minimal, isOpened: true, flashToken: 1)) == .off)
        #expect(resolved(inputs(policy: .minimal, isOpened: true, waiting: .approval)) == .off)
    }

    @Test
    func minimalWaitingBeatsTheOtherMoments() {
        let busy = inputs(
            policy: .minimal,
            waiting: .question,
            flashToken: 1,
            noticeTint: Self.tint,
            musicTint: Self.tint,
            isRunning: true
        )
        #expect(resolved(busy).source == .question)
        #expect(resolved(busy).motion == .steady)
    }

    // MARK: Policy table

    private struct PolicyCase: Sendable {
        let reduceMotion: Bool
        let lowPower: Bool
        let thermal: ProcessInfo.ThermalState
        let expected: IslandMotionPolicy
    }

    private static let policyCases: [PolicyCase] = {
        let thermals: [ProcessInfo.ThermalState] = [.nominal, .fair, .serious, .critical]
        var cases: [PolicyCase] = []
        for reduceMotion in [false, true] {
            for lowPower in [false, true] {
                for thermal in thermals {
                    let expected: IslandMotionPolicy
                    switch (thermal, lowPower, reduceMotion) {
                    case (.critical, _, _): expected = .minimal
                    case (.serious, _, _), (_, true, _): expected = .conserving
                    case (_, _, true): expected = .reduced
                    default: expected = .full
                    }
                    cases.append(PolicyCase(reduceMotion: reduceMotion, lowPower: lowPower, thermal: thermal, expected: expected))
                }
            }
        }
        return cases
    }()

    @Test(arguments: policyCases)
    private func policyResolvesFromSystemState(_ item: PolicyCase) {
        let policy = IslandMotionPolicy.resolve(
            reduceMotion: item.reduceMotion,
            lowPower: item.lowPower,
            thermal: item.thermal
        )
        #expect(policy == item.expected)
    }

    @Test
    func policyNamedRows() {
        #expect(IslandMotionPolicy.resolve(reduceMotion: false, lowPower: false, thermal: .nominal) == .full)
        #expect(IslandMotionPolicy.resolve(reduceMotion: false, lowPower: false, thermal: .fair) == .full)
        #expect(IslandMotionPolicy.resolve(reduceMotion: true, lowPower: false, thermal: .nominal) == .reduced)
        #expect(IslandMotionPolicy.resolve(reduceMotion: false, lowPower: true, thermal: .nominal) == .conserving)
        #expect(IslandMotionPolicy.resolve(reduceMotion: false, lowPower: false, thermal: .serious) == .conserving)
        #expect(IslandMotionPolicy.resolve(reduceMotion: true, lowPower: true, thermal: .serious) == .conserving)
        #expect(IslandMotionPolicy.resolve(reduceMotion: false, lowPower: false, thermal: .critical) == .minimal)
        #expect(IslandMotionPolicy.resolve(reduceMotion: true, lowPower: true, thermal: .critical) == .minimal)
    }

    @Test
    func policyOverrideReadsTheFourNamesAndNothingElse() {
        func override(_ value: String?) -> IslandMotionPolicy? {
            IslandMotionPolicy.override(from: value.map { ["OPEN_ISLAND_MOTION_POLICY": $0] } ?? [:])
        }

        #expect(override("full") == .full)
        #expect(override("reduced") == .reduced)
        #expect(override("conserving") == .conserving)
        #expect(override("minimal") == .minimal)
        #expect(override(" Minimal ") == .minimal)
        #expect(override("fast") == nil)
        #expect(override("") == nil)
        #expect(override(nil) == nil)
    }

    // MARK: Forced states (OPEN_ISLAND_HALO)

    private func forced(_ value: String?, extra: [String: String] = [:]) -> IslandHaloState? {
        var environment = extra
        if let value { environment["OPEN_ISLAND_HALO"] = value }
        return IslandHaloState.forced(from: environment)
    }

    @Test
    func forcedWithoutTheVariableIsNil() {
        #expect(IslandHaloState.forced(from: [:]) == nil)
        #expect(IslandHaloState.forced(from: ["OPEN_ISLAND_HALOS": "approval"]) == nil)
    }

    @Test
    func forcedApprovalQuestionAndRunningMatchTheResolver() {
        #expect(forced("approval") == resolved(inputs(waiting: .approval)))
        #expect(forced("question") == resolved(inputs(waiting: .question)))
        #expect(forced("running") == resolved(inputs(isRunning: true)))
    }

    @Test
    func forcedFlashIsHeldAtItsPeak() throws {
        let state = try #require(forced("flash"))

        #expect(state.source == .completed)
        #expect(state.motion == .flash(token: 1, peak: subtle.flashPeak, duration: Motion.Halo.flash))
        #expect(state.restOpacity == subtle.flashPeak)
        #expect(state.radius == subtle.radius)
    }

    @Test
    func forcedNoticeAndMusicTakeAHexColor() throws {
        let notice = try #require(forced("notice:FF8800"))
        #expect(notice.source == .notice)
        #expect(notice.color == .rgb255(0xFF, 0x88, 0x00))
        #expect(notice.motion == .steady)
        #expect(notice.restOpacity == subtle.noticeOpacity)

        let music = try #require(forced("music:00aaFF"))
        #expect(music.source == .music)
        #expect(music.color == .rgb255(0x00, 0xAA, 0xFF))
        #expect(music.motion == .drift(period: Motion.Halo.driftPeriod))
        #expect(music.restOpacity == subtle.musicOpacity)

        let hashed = try #require(forced("notice:#336699"))
        #expect(hashed.color == .rgb255(0x33, 0x66, 0x99))
    }

    @Test
    func forcedOffReturnsTheOffState() {
        #expect(forced("off") == .off)
        #expect(forced("OFF") == .off)
    }

    @Test
    func forcedRejectsUnknownValuesAndBadHex() {
        #expect(forced("") == nil)
        #expect(forced("glow") == nil)
        #expect(forced("approvalish") == nil)
        #expect(forced("approval:FF0000") == nil)
        #expect(forced("flash:1") == nil)
        #expect(forced("off:now") == nil)
        #expect(forced("notice") == nil)
        #expect(forced("music") == nil)
        #expect(forced("notice:") == nil)
        #expect(forced("notice:zzzzzz") == nil)
        #expect(forced("notice:12345") == nil)
        #expect(forced("notice:1234567") == nil)
        #expect(forced("music:+12345") == nil)
        #expect(forced("music:GG0000") == nil)
        #expect(forced("music:#12345G") == nil)
    }

    @Test
    func forcedIsCaseAndSpaceTolerantInTheKeyword() throws {
        #expect(forced(" Approval ") == resolved(inputs(waiting: .approval)))
        #expect(try #require(forced("Notice: ff8800")).color == .rgb255(0xFF, 0x88, 0x00))
    }

    @Test
    func forcedUsesVividMetricsOnlyWhenAsked() throws {
        let vividApproval = try #require(forced("approval", extra: ["OPEN_ISLAND_HALO_STYLE": "vivid"]))
        #expect(vividApproval.radius == vivid.radius)
        #expect(vividApproval.motion == .breathing(period: Motion.Halo.approvalPeriod, low: vivid.breathingLow, high: vivid.breathingHigh))

        let vividFlash = try #require(forced("flash", extra: ["OPEN_ISLAND_HALO_STYLE": "Vivid"]))
        #expect(vividFlash.restOpacity == vivid.flashPeak)

        for style in ["subtle", "off", "loud", ""] {
            let state = try #require(forced("approval", extra: ["OPEN_ISLAND_HALO_STYLE": style]))
            #expect(state.radius == subtle.radius)
        }
    }

    @Test
    func forcedFollowsTheMotionPolicyOverride() throws {
        let reduced = try #require(forced("approval", extra: ["OPEN_ISLAND_MOTION_POLICY": "reduced"]))
        #expect(reduced.motion == .steady)

        let conserving = try #require(forced("running", extra: ["OPEN_ISLAND_MOTION_POLICY": "conserving"]))
        #expect(conserving == .off)

        let minimalFlash = try #require(forced("flash", extra: ["OPEN_ISLAND_MOTION_POLICY": "minimal"]))
        #expect(minimalFlash == .off)

        let unknown = try #require(forced("approval", extra: ["OPEN_ISLAND_MOTION_POLICY": "turbo"]))
        #expect(unknown == resolved(inputs(waiting: .approval)))
    }

    // MARK: Hex parsing

    @Test
    func hexColorsParseWithAndWithoutAHash() {
        #expect(IslandHaloRGB(hex: "FF8800") == .rgb255(255, 136, 0))
        #expect(IslandHaloRGB(hex: "#ff8800") == .rgb255(255, 136, 0))
        #expect(IslandHaloRGB(hex: "000000") == .rgb255(0, 0, 0))
        #expect(IslandHaloRGB(hex: "FFFFFF") == .rgb255(255, 255, 255))
    }

    @Test
    func hexColorsRejectAnythingThatIsNotSixHexDigits() {
        for bad in ["", "#", "FFF", "FF88001", "GGGGGG", "+12345", "-12345", "12 456", "0xFF8800", "##FF8800"] {
            #expect(IslandHaloRGB(hex: bad) == nil, "\(bad) should not parse")
        }
    }

    // MARK: SystemMotionMonitor

    @MainActor
    @Test
    func monitorStartIsIdempotent() {
        let monitor = SystemMotionMonitor(environment: [:])
        #expect(monitor.observerCount == 0)

        monitor.start()
        let afterFirst = monitor.observerCount
        monitor.start()

        #expect(afterFirst == 3)
        #expect(monitor.observerCount == afterFirst)
    }

    @MainActor
    @Test
    func monitorReadsTheSystemStateAtStart() {
        let monitor = SystemMotionMonitor(environment: [:])
        monitor.start()

        #expect(monitor.reduceMotion == Motion.prefersReducedMotion)
        #expect(monitor.lowPower == ProcessInfo.processInfo.isLowPowerModeEnabled)
        #expect(monitor.thermal == ProcessInfo.processInfo.thermalState)
        #expect(monitor.policy == IslandMotionPolicy.resolve(
            reduceMotion: monitor.reduceMotion,
            lowPower: monitor.lowPower,
            thermal: monitor.thermal
        ))
    }

    @MainActor
    @Test
    func monitorPolicyOverrideWinsOverTheSystemState() {
        let monitor = SystemMotionMonitor(environment: ["OPEN_ISLAND_MOTION_POLICY": "minimal"])
        #expect(monitor.policy == .minimal)

        monitor.start()
        #expect(monitor.policy == .minimal)
    }

    @MainActor
    @Test
    func monitorIgnoresAnUnknownOverride() {
        let monitor = SystemMotionMonitor(environment: ["OPEN_ISLAND_MOTION_POLICY": "turbo"])
        monitor.start()

        #expect(monitor.policy == IslandMotionPolicy.resolve(
            reduceMotion: monitor.reduceMotion,
            lowPower: monitor.lowPower,
            thermal: monitor.thermal
        ))
    }

    // MARK: Harness scenarios

    @Test
    func closedApprovalHasOneSessionWaitingForApproval() {
        let snapshot = IslandDebugScenario.closedApproval.snapshot()

        #expect(snapshot.notchStatus == .closed)
        #expect(snapshot.sessions.filter { $0.phase == .waitingForApproval }.count == 1)
        #expect(!snapshot.sessions.contains { $0.phase == .waitingForAnswer })
        #expect(snapshot.sessions.allSatisfy { $0.origin == .demo })
    }

    @Test
    func closedQuestionHasOneSessionWaitingForAnswer() {
        let snapshot = IslandDebugScenario.closedQuestion.snapshot()

        #expect(snapshot.notchStatus == .closed)
        #expect(snapshot.sessions.filter { $0.phase == .waitingForAnswer }.count == 1)
        #expect(!snapshot.sessions.contains { $0.phase == .waitingForApproval })
    }

    @Test
    func closedRunningHasARunningSessionAndNoneWaiting() {
        let snapshot = IslandDebugScenario.closedRunning.snapshot()

        #expect(snapshot.notchStatus == .closed)
        #expect(snapshot.sessions.contains { $0.phase == .running })
        #expect(!snapshot.sessions.contains { $0.phase == .waitingForApproval || $0.phase == .waitingForAnswer })
    }

    @Test
    func closedIdleHasSessionsButNoneNeedingAttention() {
        let snapshot = IslandDebugScenario.closedIdle.snapshot()

        #expect(snapshot.notchStatus == .closed)
        #expect(!snapshot.sessions.isEmpty)
        #expect(snapshot.sessions.allSatisfy { $0.phase == .completed })
    }
}
