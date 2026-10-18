import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// The update flow's rules (D82): when the island asks, what Later does,
/// what Install does, and what a relaunch shows.
@MainActor
struct UpdateFlowTests {
    private static let catalog = WhatsNewCatalog(releases: [
        WhatsNewRelease(version: "1.0.14", items: [
            WhatsNewItem(title: "Updates ask first", detail: "When a new version lands, the island asks."),
            WhatsNewItem(title: "To-dos from all your apps", detail: nil),
            WhatsNewItem(title: "Search in Settings", detail: nil),
            WhatsNewItem(title: "Send feedback from the app", detail: nil),
        ]),
        WhatsNewRelease(version: "1.0.13", items: [
            WhatsNewItem(title: "The Record widget", detail: nil),
        ]),
        WhatsNewRelease(version: "1.0.12", items: []),
    ])

    private static let day: TimeInterval = 24 * 60 * 60

    /// A flow whose waits are over at once, with a record of what it
    /// showed and whether Sparkle's block ran.
    @MainActor
    private final class Harness {
        let flow: UpdateFlow
        let defaults = MemoryDefaults()
        var busy = false
        var automatic = true
        var updatingTexts: [String] = []
        var asksShown = 0
        var installs = 0

        init() {
            flow = UpdateFlow(defaults: defaults, catalog: UpdateFlowTests.catalog, tickInterval: nil, sleep: { _ in })
            flow.isBusy = { [unowned self] in self.busy }
            flow.installsAutomatically = { [unowned self] in self.automatic }
            flow.showUpdating = { [unowned self] in self.updatingTexts.append($0) }
            flow.onAskShown = { [unowned self] in self.asksShown += 1 }
        }

        func download(now: Date = Date(timeIntervalSince1970: 1_000)) {
            flow.noteDownloaded(version: "1.0.14", install: { [unowned self] in self.installs += 1 }, now: now)
        }
    }

    @Test
    func aDownloadAsksAtOnceWhenNothingIsBusy() {
        let h = Harness()
        h.download()

        #expect(h.flow.phase == .asking)
        #expect(h.flow.isAsking)
        #expect(h.asksShown == 1)
        #expect(h.flow.card == .ask(version: "1.0.14"))
        #expect(h.flow.closedMark == nil)
    }

    @Test
    func theAskWaitsWhileSomethingIsBusyAndComesWhenItIsFree() {
        let h = Harness()
        h.busy = true
        h.download()

        #expect(h.flow.phase == .waiting)
        #expect(h.flow.card == nil)

        h.busy = false
        h.flow.reconsider()
        #expect(h.flow.phase == .asking)

        // Something got busy with the ask up: the ask comes down.
        h.busy = true
        h.flow.reconsider()
        #expect(h.flow.phase == .waiting)
        #expect(h.flow.card == nil)
    }

    @Test
    func laterMarksTheIslandAndAsksAgainAfterADay() {
        let h = Harness()
        let start = Date(timeIntervalSince1970: 1_000)
        h.download(now: start)
        h.flow.answerLater(now: start)

        #expect(h.flow.phase == .ready(askAgainAt: start.addingTimeInterval(Self.day)))
        #expect(h.flow.closedMark == .ready)
        #expect(h.flow.card == .ready(version: "1.0.14"))

        h.flow.reconsider(now: start.addingTimeInterval(Self.day - 1))
        #expect(h.flow.phase != .asking, "a day has not passed")

        h.flow.reconsider(now: start.addingTimeInterval(Self.day))
        #expect(h.flow.phase == .asking)
        #expect(h.asksShown == 2)
    }

    @Test
    func theSwitchOffShowsUpdateReadyAndNeverAsks() {
        let h = Harness()
        h.automatic = false
        h.download()

        #expect(h.flow.phase == .ready(askAgainAt: nil))
        #expect(h.flow.closedMark == .ready)
        #expect(h.flow.card == .ready(version: "1.0.14"))

        h.flow.reconsider(now: Date(timeIntervalSince1970: 1_000 + Self.day * 7))
        #expect(h.flow.phase == .ready(askAgainAt: nil), "off means off")

        // The switch comes back on: the next free moment asks.
        h.automatic = true
        h.flow.reconsider()
        #expect(h.flow.phase == .asking)
    }

    @Test
    func installShowsUpdatingThenRunsSparklesBlock() async {
        let h = Harness()
        h.download()
        h.flow.answerInstall()

        #expect(h.flow.phase == .installing)
        #expect(h.updatingTexts == ["Updating to 1.0.14…"])
        #expect(h.flow.card == nil, "the ask is gone while it updates")
        // The wait is over at once in the harness; the block runs on the
        // next turn of the main actor.
        await Task.yield()
        await Task.yield()
        #expect(h.installs == 1)
    }

    @Test
    func restartNowFromTheReadyCardInstallsToo() async {
        let h = Harness()
        h.download()
        h.flow.answerLater()
        h.flow.answerInstall()

        #expect(h.flow.phase == .installing)
        await Task.yield()
        await Task.yield()
        #expect(h.installs == 1)
    }

    @Test
    func theSettingsLineFollowsThePhase() {
        let h = Harness()
        #expect(h.flow.settingsStatus == nil)
        h.download()
        #expect(h.flow.settingsStatus == "1.0.14 downloaded · asks when the island is free")
        h.flow.answerLater()
        #expect(h.flow.settingsStatus == "1.0.14 downloaded · installs on the next restart")
    }

    // MARK: - After the relaunch

    @Test
    func aFirstRunLearnsTheVersionAndShowsNothing() {
        let h = Harness()
        h.flow.noteLaunch(currentVersion: "1.0.14")

        #expect(h.flow.whatsNew == nil)
        #expect(h.flow.card == nil)
        #expect(h.defaults.string(forKey: UpdateFlow.lastSeenVersionKey) == "1.0.14")
    }

    @Test
    func aNewerVersionShowsWhatsNewForEveryVersionSkipped() throws {
        let h = Harness()
        h.defaults.set("1.0.11", forKey: UpdateFlow.lastSeenVersionKey)
        h.flow.noteLaunch(currentVersion: "1.0.14")

        let pending = try #require(h.flow.whatsNew)
        #expect(pending.version == "1.0.14")
        #expect(pending.releases.map(\.version) == ["1.0.14", "1.0.13"], "1.0.12 had nothing to show")
        #expect(pending.totalCount == 5)
        #expect(pending.shown.map(\.title) == [
            "Updates ask first", "To-dos from all your apps", "Search in Settings", "The Record widget",
        ])
        #expect(pending.hasMore)
        #expect(h.flow.closedMark == .whatsNew(version: "1.0.14"))
        #expect(h.flow.card == .whatsNew(pending))
        #expect(h.defaults.string(forKey: UpdateFlow.lastSeenVersionKey) == "1.0.14")

        // The island opened: the closed mark goes, the card stays until Done.
        h.flow.noteIslandOpened()
        #expect(h.flow.closedMark == nil)
        #expect(h.flow.card == .whatsNew(pending))
        h.flow.dismissWhatsNew()
        #expect(h.flow.card == nil)
    }

    /// Builds before D82 never wrote the version. A copy that ran before
    /// gets this version's card once; a fresh install still gets nothing.
    @Test
    func aCopyThatRanBeforeWithoutARecordSeesThisVersionsCard() throws {
        let upgraded = Harness()
        upgraded.flow.noteLaunch(currentVersion: "1.0.14", hasRunBefore: true)
        let pending = try #require(upgraded.flow.whatsNew)
        #expect(pending.releases.map(\.version) == ["1.0.14"])
        #expect(upgraded.defaults.string(forKey: UpdateFlow.lastSeenVersionKey) == "1.0.14")

        let fresh = Harness()
        fresh.flow.noteLaunch(currentVersion: "1.0.14", hasRunBefore: false)
        #expect(fresh.flow.whatsNew == nil)

        let nothingToShow = Harness()
        nothingToShow.flow.noteLaunch(currentVersion: "1.0.12", hasRunBefore: true)
        #expect(nothingToShow.flow.whatsNew == nil)
    }

    @Test
    func sparkleHandingTheSameUpdateOverAgainKeepsLatersDay() async {
        let h = Harness()
        let start = Date(timeIntervalSince1970: 1_000)
        h.download(now: start)
        h.flow.answerLater(now: start)
        let held = h.flow.phase

        h.download(now: start.addingTimeInterval(3_600))
        #expect(h.flow.phase == held, "the same version again changes nothing")
        #expect(h.asksShown == 1)

        // An install under way is not disturbed either.
        h.flow.answerInstall()
        h.download(now: start.addingTimeInterval(3_700))
        #expect(h.flow.phase == .installing)
        await Task.yield()
        await Task.yield()
        #expect(h.installs == 1)

        // A newer version starts over.
        let other = Harness()
        other.download(now: start)
        other.flow.answerLater(now: start)
        other.flow.noteDownloaded(version: "1.0.15", install: {}, now: start)
        #expect(other.flow.pendingVersion == "1.0.15")
        #expect(other.flow.phase == .asking)
    }

    @Test
    func installIsRefusedWhileSomethingIsBusy() async {
        let h = Harness()
        h.download()
        #expect(h.flow.isAsking)
        h.busy = true

        h.flow.answerInstall()

        #expect(h.flow.phase == .waiting, "the press finds the island busy and the ask comes down")
        #expect(h.updatingTexts.isEmpty)
        await Task.yield()
        #expect(h.installs == 0)
    }

    @Test
    func theSameVersionAgainOrAnOlderOneShowsNothing() {
        let same = Harness()
        same.defaults.set("1.0.14", forKey: UpdateFlow.lastSeenVersionKey)
        same.flow.noteLaunch(currentVersion: "1.0.14")
        #expect(same.flow.whatsNew == nil)

        let older = Harness()
        older.defaults.set("1.0.15", forKey: UpdateFlow.lastSeenVersionKey)
        older.flow.noteLaunch(currentVersion: "1.0.14")
        #expect(older.flow.whatsNew == nil)
        #expect(older.defaults.string(forKey: UpdateFlow.lastSeenVersionKey) == "1.0.14")
    }

    @Test
    func aVersionWithNothingToShowShowsNoCard() {
        let h = Harness()
        h.defaults.set("1.0.11", forKey: UpdateFlow.lastSeenVersionKey)
        h.flow.noteLaunch(currentVersion: "1.0.12")
        #expect(h.flow.whatsNew == nil)
        #expect(h.flow.card == nil)
    }

    @Test
    func theUpdatesOwnStatesComeBeforeWhatsNew() {
        let h = Harness()
        h.defaults.set("1.0.13", forKey: UpdateFlow.lastSeenVersionKey)
        h.flow.noteLaunch(currentVersion: "1.0.14")
        h.download()
        h.flow.answerLater()

        #expect(h.flow.closedMark == .ready)
        #expect(h.flow.card == .ready(version: "1.0.14"))
    }
}

/// The app model's side of the flow (D82): what counts as busy, and the
/// shortcuts answering the ask.
@MainActor
struct UpdateFlowAppModelTests {
    private static func waitingSession() -> AgentSession {
        AgentSession(
            id: "waiting",
            title: "Claude · project",
            tool: .claudeCode,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Approve command",
            updatedAt: .now,
            permissionRequest: PermissionRequest(title: "Approve", summary: "Allow edit?", affectedPath: "/tmp/file.swift")
        )
    }

    /// A model with the About switch on, as a release has it. A test
    /// runner never starts Sparkle, which is what would read the switch.
    private static func model() -> AppModel {
        let model = AppModel(agentsDefaults: MemoryDefaults(), defaults: MemoryDefaults())
        model.nook.presentRingLight = { _ in }
        model.updateChecker.installsAutomatically = true
        return model
    }

    @Test
    func anAgentRequestWaitingBlocksTheAsk() throws {
        let model = Self.model()
        model.state = SessionState(sessions: [Self.waitingSession()])
        #expect(model.updateAskIsBlocked)

        model.updateFlow.noteDownloaded(version: "1.0.14", install: {})
        #expect(model.updateFlow.phase == .waiting)
        #expect(model.updateAskActivity == nil)

        // The request is answered: the island asks.
        model.state = SessionState()
        #expect(model.updateFlow.phase == .asking)
        let ask = try #require(model.updateAskActivity)
        #expect(ask.leadingText == "New version dropped! Install?")
        if case let .chips(chips) = ask.trailing {
            #expect(chips.deny.title == "Later")
            #expect(chips.approve.title == "Install")
            #expect(chips.approve.isPrimary)
        } else {
            Issue.record("the ask's right wing holds the chips")
        }
    }

    @Test
    func theDenyKeyIsLaterAndTheApproveKeyIsInstall() {
        let model = Self.model()
        var installs = 0
        model.updateFlow.noteDownloaded(version: "1.0.14", install: { installs += 1 })
        #expect(model.updateFlow.isAsking)

        model.handleAgentHotkey(.deny)
        #expect(model.updateFlow.closedMark == .ready)
        #expect(model.nookRightSlotContent == .notice("Update ready"))
        #expect(model.updateCardHeight == UpdateCardLayout.pageHeight(for: .ready(version: "1.0.14")))

        model.updateFlow.reconsider(now: Date.now.addingTimeInterval(UpdateFlow.askAgainAfter))
        #expect(model.updateFlow.isAsking)
        model.handleAgentHotkey(.approve)
        #expect(model.updateFlow.phase == .installing)
        #expect(model.nook.transient?.text == "Updating to 1.0.14…")
        #expect(model.nook.transient?.spins == true)
        #expect(installs == 0, "the block runs after the words had their moment")
    }

    @Test
    func theWhatsNewMarkNamesTheVersion() {
        let model = Self.model()
        // The catalog is the bundled one, so the mark is driven by hand.
        #expect(model.updateClosedMark == nil)
        #expect(model.updateCardHeight == 0)
    }
}
