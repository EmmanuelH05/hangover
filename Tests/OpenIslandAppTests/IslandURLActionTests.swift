import AppKit
import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// `hangover://` links from other apps: which links read as an action,
/// which are thrown away, and what an action does to the live models. No
/// test opens the island from closed, because that would put a real island
/// on the screen; the closed case is covered by the pure page rule.
@Suite struct IslandURLActionTests {
    /// Reads a link. A link written with Hangover's scheme is also read
    /// with the upstream scheme in its place, and the two answers must be
    /// the same. Every case in this suite therefore holds both schemes to
    /// the same rules.
    private func parse(_ text: String) throws -> Result<IslandURLAction, IslandURLActionError> {
        let result = IslandURLAction.parse(try #require(URL(string: text), "\(text) is not a URL"))
        if let twin = Self.upstreamTwin(of: text) {
            let twinResult = IslandURLAction.parse(try #require(URL(string: twin), "\(twin) is not a URL"))
            #expect(twinResult == result, "\(twin) and \(text) read differently")
        }
        return result
    }

    /// The same link under the upstream scheme, keeping the case the scheme
    /// was written in. Nil for a link of any other scheme.
    static func upstreamTwin(of text: String) -> String? {
        let ours = IslandURLAction.scheme + ":"
        guard text.lowercased().hasPrefix(ours) else { return nil }
        let written = text.prefix(ours.count)
        let upstream = IslandURLAction.upstreamScheme + ":"
        let isUppercase = written == written.uppercased()
        return (isUppercase ? upstream.uppercased() : upstream) + text.dropFirst(ours.count)
    }

    // MARK: The two schemes

    @Test func theParserReadsHangoverAndTheUpstreamSchemeAndNoOther() {
        let ours: String = "hangover"
        let upstream: String = "openisland"
        let both: Set<String> = [ours, upstream]
        #expect(IslandURLAction.scheme == ours)
        #expect(IslandURLAction.upstreamScheme == upstream)
        #expect(IslandURLAction.acceptedSchemes == both)
    }

    @Test(arguments: [
        ("openisland://nook", IslandURLAction.openNook),
        ("openisland://timer/start?minutes=25", .startTimer(minutes: 25)),
        ("OPENISLAND://Mirror/Toggle", .setMirror(.toggle)),
        ("openisland:/timer/stop", .stopTimer),
    ])
    func aLinkWrittenForTheUpstreamAppStillReads(text: String, expected: IslandURLAction) {
        #expect(IslandURLAction.parse(URL(string: text)!) == .success(expected))
    }

    @Test(arguments: [
        ("openisland://timer/start?minutes=0", IslandURLActionError.badMinutes),
        ("openisland://timer/start?minutes=5&then=quit", .malformed),
        ("openisland://user@nook", .malformed),
        ("openisland://nook:8080", .malformed),
        ("openisland://nook#section", .malformed),
    ])
    func theUpstreamSchemeIsHeldToTheSameRules(text: String, expected: IslandURLActionError) {
        #expect(IslandURLAction.parse(URL(string: text)!) == .failure(expected))
    }

    @Test func theTwinOfALinkOnlySwapsTheScheme() {
        let lower: String = "openisland://timer/start?minutes=5"
        let upper: String = "OPENISLAND://Timer/Start"
        #expect(Self.upstreamTwin(of: "hangover://timer/start?minutes=5") == lower)
        #expect(Self.upstreamTwin(of: "HANGOVER://Timer/Start") == upper)
        #expect(Self.upstreamTwin(of: "https://nook") == nil)
        #expect(Self.upstreamTwin(of: "hangover-dev://nook") == nil)
    }

    /// The schemes a bundle script writes into its Info.plist.
    private func registeredSchemes(inScript name: String) throws -> [String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("scripts/\(name)"), encoding: .utf8)
        let key = try #require(text.range(of: "<key>CFBundleURLSchemes</key>"), "\(name) registers no scheme")
        let close = try #require(text.range(of: "</array>", range: key.upperBound..<text.endIndex))
        return text[key.upperBound..<close.lowerBound]
            .components(separatedBy: "<string>")
            .dropFirst()
            .compactMap { $0.components(separatedBy: "</string>").first }
    }

    @Test func theReleaseBundleRegistersOnlyHangoverAndTheDevBundleBoth() throws {
        let release: [String] = ["hangover"]
        let dev: [String] = ["hangover", "openisland"]
        #expect(try registeredSchemes(inScript: "package-app.sh") == release)
        #expect(try registeredSchemes(inScript: "launch-dev-app.sh") == dev)
        // Whatever a bundle registers, the parser reads.
        #expect(Set(dev).isSubset(of: IslandURLAction.acceptedSchemes))
    }

    // MARK: Links that read

    @Test(arguments: [
        ("hangover://nook", IslandURLAction.openNook),
        ("hangover://nook/", .openNook),
        ("hangover://agents", .openAgents),
        ("hangover://timer/start", .startTimer(minutes: nil)),
        ("hangover://timer/start?minutes=25", .startTimer(minutes: 25)),
        ("hangover://timer/start?minutes=1", .startTimer(minutes: 1)),
        ("hangover://timer/start?minutes=1440", .startTimer(minutes: 1440)),
        ("hangover://timer/start?minutes=007", .startTimer(minutes: 7)),
        ("hangover://timer/pomodoro", .startPomodoro),
        ("hangover://timer/stop", .stopTimer),
        ("hangover://mirror/on", .setMirror(.on)),
        ("hangover://mirror/off", .setMirror(.off)),
        ("hangover://mirror/toggle", .setMirror(.toggle)),
        ("hangover://ringlight/on", .setRingLight(.on)),
        ("hangover://ringlight/off", .setRingLight(.off)),
        ("hangover://ringlight/toggle", .setRingLight(.toggle)),
        // Case and the single-slash spelling do not matter.
        ("HANGOVER://Timer/Start?minutes=5", .startTimer(minutes: 5)),
        ("hangover:/timer/stop", .stopTimer),
    ])
    func aKnownLinkReadsAsItsAction(text: String, expected: IslandURLAction) throws {
        #expect(try parse(text) == .success(expected))
    }

    // MARK: Links that are thrown away

    @Test(arguments: [
        "https://nook", "http://timer/start?minutes=5", "file:///timer/start", "nook",
        // A scheme that only starts like one of ours is not ours.
        "hangover-dev://nook", "hangovers://nook", "openisland-dev://nook", "openislands://nook",
    ])
    func anotherSchemeIsNotOurs(text: String) throws {
        #expect(try parse(text) == .failure(.wrongScheme))
    }

    @Test(arguments: [
        "hangover://timer/start?minutes=0",
        "hangover://timer/start?minutes=1441",
        "hangover://timer/start?minutes=99999",
        "hangover://timer/start?minutes=-5",
        "hangover://timer/start?minutes=2.5",
        "hangover://timer/start?minutes=1e3",
        "hangover://timer/start?minutes=abc",
        "hangover://timer/start?minutes=",
        "hangover://timer/start?minutes=%2025",
        "hangover://timer/start?minutes=25%3Brm",
        "hangover://timer/start?minutes=0x10",
    ])
    func minutesMustBeAWholeNumberInRange(text: String) throws {
        #expect(try parse(text) == .failure(.badMinutes))
    }

    @Test(arguments: [
        "hangover://timer/start?minutes=5&minutes=6",
        "hangover://timer/start?minutes=5&then=quit",
        "hangover://timer/start?seconds=30",
        "hangover://timer/start?minutes",
        "hangover://nook?x=1",
        "hangover://timer/stop?minutes=5",
        "hangover://user@nook",
        "hangover://user:secret@timer/stop",
        "hangover://nook:8080",
        "hangover://nook#section",
    ])
    func anythingExtraOnALinkMakesItMalformed(text: String) throws {
        #expect(try parse(text) == .failure(.malformed))
    }

    @Test(arguments: [
        "hangover://",
        "hangover://quit",
        "hangover://timer",
        "hangover://timer/start/now",
        "hangover://timer/reset",
        "hangover://mirror",
        "hangover://mirror/explode",
        "hangover://ringlight/dim",
        "hangover://settings/open",
        "hangover://shell/rm",
        "hangover://nook/agents",
        "hangover://open?url=https://evil.example",
        "hangover://run?script=/bin/sh",
    ])
    func anUnknownActionIsNeverRead(text: String) throws {
        guard case .failure = try parse(text) else {
            Issue.record("\(text) was read as an action")
            return
        }
    }

    @Test func anOverlongLinkIsNotReadAtAll() throws {
        let long = "hangover://nook?" + String(repeating: "a", count: 400)

        #expect(try parse(long) == .failure(.malformed))
    }

    @Test func anUnknownActionIsNamedShortInTheLog() throws {
        let noise = String(repeating: "z", count: 120)
        guard case .failure(.unknownAction(let words)) = try parse("hangover://\(noise)") else {
            Issue.record("expected an unknown action")
            return
        }

        #expect(words.count == 40)
        #expect(IslandURLActionError.badMinutes.logLine.contains("1440"))
    }

    // MARK: What an action is

    @Test func onlyActionsThatShowTheIslandKeepTheKeyboard() {
        #expect(IslandURLAction.openNook.opensIsland)
        #expect(IslandURLAction.openAgents.opensIsland)
        #expect(IslandURLAction.setMirror(.on).opensIsland)
        #expect(IslandURLAction.setMirror(.toggle).opensIsland)
        #expect(!IslandURLAction.setMirror(.off).opensIsland)
        #expect(!IslandURLAction.startTimer(minutes: 25).opensIsland)
        #expect(!IslandURLAction.startPomodoro.opensIsland)
        #expect(!IslandURLAction.stopTimer.opensIsland)
        #expect(!IslandURLAction.setRingLight(.on).opensIsland)
    }

    @Test func aSwitchChangeTurnsOnOffOrOver() {
        #expect(IslandSwitchChange.on.applied(to: false))
        #expect(IslandSwitchChange.on.applied(to: true))
        #expect(!IslandSwitchChange.off.applied(to: true))
        #expect(IslandSwitchChange.toggle.applied(to: false))
        #expect(!IslandSwitchChange.toggle.applied(to: true))
    }

    @Test func aPageActionOpensTurnsOrLeavesACardAlone() {
        func move(_ status: NotchStatus, _ reason: NotchOpenReason?, waiting: Bool = false) -> IslandURLPageMove {
            IslandURLPageMove.resolve(status: status, reason: reason, showsWaitingRequest: waiting)
        }

        #expect(move(.closed, nil) == .open)
        #expect(move(.popping, nil) == .open)
        #expect(move(.opened, .hover) == .turn)
        #expect(move(.opened, .click) == .turn)
        #expect(move(.opened, .boot) == .turn)
        // A card that waits for an answer is never pushed aside.
        #expect(move(.opened, .notification) == .refuse)
    }

    @Test func aPageActionLeavesAnApprovalInTheOpenListAlone() {
        func move(_ status: NotchStatus, _ reason: NotchOpenReason?) -> IslandURLPageMove {
            IslandURLPageMove.resolve(status: status, reason: reason, showsWaitingRequest: true)
        }

        // "Show all" on a card, a click, a hover or the boot animation: an
        // approval or a question in a row is on screen all the same.
        #expect(move(.opened, .click) == .refuse)
        #expect(move(.opened, .hover) == .refuse)
        #expect(move(.opened, .boot) == .refuse)
        #expect(move(.opened, .notification) == .refuse)
        // Nothing is on screen while the island is closed.
        #expect(move(.closed, nil) == .open)
        #expect(move(.popping, nil) == .open)
    }

    @Test func aTurnedPagePinsAnIslandThatWasOnlyPassingThrough() {
        #expect(IslandURLPageMove.pinsOnTurn(reason: .hover))
        #expect(IslandURLPageMove.pinsOnTurn(reason: .boot))
        #expect(!IslandURLPageMove.pinsOnTurn(reason: .click))
        #expect(!IslandURLPageMove.pinsOnTurn(reason: .notification))
        #expect(!IslandURLPageMove.pinsOnTurn(reason: nil))
    }

    // MARK: The boot animation and links

    @Test func theBootAnimationOnlyOpensAClosedIslandAndOnlyClosesItsOwn() {
        #expect(IslandBootAnimation.shouldOpen(status: .closed))
        // A link or a card got there first.
        #expect(!IslandBootAnimation.shouldOpen(status: .opened))
        #expect(!IslandBootAnimation.shouldOpen(status: .popping))

        #expect(IslandBootAnimation.shouldClose(reason: .boot))
        // Opened or pinned by something else since.
        #expect(!IslandBootAnimation.shouldClose(reason: .click))
        #expect(!IslandBootAnimation.shouldClose(reason: .hover))
        #expect(!IslandBootAnimation.shouldClose(reason: .notification))
        #expect(!IslandBootAnimation.shouldClose(reason: nil))
    }

    // MARK: What goes to the log

    @Test func linkTextIsCleanedBeforeItReachesTheLog() {
        #expect(IslandLinkLog.clean("mirror/on\u{0}") == "mirror/on")
        #expect(IslandLinkLog.clean("a\nb\rc\td") == "abcd")
        #expect(IslandLinkLog.clean("fake\u{1B}[2K line") == "fake[2K line")
        // Right-to-left override and a zero-width space.
        #expect(IslandLinkLog.clean("ab\u{202E}cd\u{200B}e") == "abcde")
        #expect(IslandLinkLog.clean("line\u{2028}two\u{2029}three") == "linetwothree")
        // Ordinary text in any script stays.
        #expect(IslandLinkLog.clean("timer/开始 ok") == "timer/开始 ok")
        let cutTo: Int = 5
        #expect(IslandLinkLog.clean("abcdefghij", limit: cutTo) == "abcde")
        let longest: Int = IslandLinkLog.limit
        #expect(IslandLinkLog.clean(String(repeating: "z", count: 500)).count == longest)
    }

    @Test func anUnknownActionWithAControlCharacterIsLoggedWithoutIt() throws {
        guard case .failure(.unknownAction(let words)) = try parse("hangover://mirror/on%00") else {
            Issue.record("expected an unknown action")
            return
        }

        #expect(words == "mirror/on")
        guard case .failure(.unknownAction(let broken)) = try parse("hangover://quit%0Afake%20log%20line") else {
            Issue.record("expected an unknown action")
            return
        }
        #expect(broken == "quitfake log line")
    }

    @Test func aLinkThatIsNotAURLGetsALogLine() {
        #expect(IslandLinkLog.unreadableLine(for: nil) == "no link text")
        #expect(IslandLinkLog.unreadableLine(for: "") == "no link text")
        #expect(IslandLinkLog.unreadableLine(for: "open island\u{7}") == "not a URL \"open island\"")
        let noise = String(repeating: "q", count: 300)
        let shortest: Int = "not a URL \"\"".count + 40
        #expect(IslandLinkLog.unreadableLine(for: noise).count == shortest)
    }

    @Test func theKeyboardGoesBackOnlyWhenTheLinkTookIt() {
        let asked = Date(timeIntervalSince1970: 1_800_000_000)
        func givesBack(active: Bool = true, since: Date?, settingsUp: Bool = false) -> Bool {
            IslandFocusKeeper.shouldGiveBack(
                isActive: active, becameActiveAt: since, askedAt: asked, hasOwnWindowUp: settingsUp
            )
        }

        // The link brought the app forward a moment before or after it arrived.
        #expect(givesBack(since: asked.addingTimeInterval(-0.3)))
        #expect(givesBack(since: asked.addingTimeInterval(0.1)))
        // In front for a while: the user is typing in the island.
        #expect(!givesBack(since: asked.addingTimeInterval(-30)))
        #expect(!givesBack(since: .distantPast))
        // Settings is up, or the link never brought the app forward.
        #expect(!givesBack(since: asked, settingsUp: true))
        #expect(!givesBack(active: false, since: asked))
        #expect(!givesBack(since: nil))
    }

    // MARK: On the live models

    @Test @MainActor func linksAreIgnoredWhileSwitchedOff() throws {
        let model = AppModel()
        model.nook.presentRingLight = { _ in }
        let timer = model.nook.timer
        timer.reset()
        // The switch is saved to the shared defaults. Put it back before
        // any other test can read it.
        model.allowsLinksFromOtherApps = false
        defer {
            model.allowsLinksFromOtherApps = true
            timer.reset()
        }
        let link = try #require(URL(string: "hangover://timer/start?minutes=3"))

        #expect(model.handleIncomingURL(link) == nil)
        #expect(!timer.isActive)

        model.allowsLinksFromOtherApps = true
        #expect(model.handleIncomingURL(link) == .startTimer(minutes: 3))
        #expect(timer.isRunning)
    }

    @Test @MainActor func timerLinksStartAndStopTheTimer() throws {
        let model = AppModel()
        model.nook.presentRingLight = { _ in }
        let timer = model.nook.timer
        defer { timer.reset() }
        let preset = timer.preset
        let threeMinutes: TimeInterval = 180

        let started = model.handleIncomingURL(try #require(URL(string: "hangover://timer/start?minutes=3")))
        #expect(started == .startTimer(minutes: 3))
        #expect(timer.isRunning)
        #expect(timer.oneOffTotal == threeMinutes)
        #expect(timer.preset == preset)

        #expect(model.perform(.startPomodoro))
        #expect(timer.pomodoro == .first)

        #expect(model.perform(.stopTimer))
        #expect(!timer.isActive)
        #expect(timer.pomodoro == nil)

        // No minutes: the saved length.
        #expect(model.perform(.startTimer(minutes: nil)))
        #expect(timer.isRunning)
        #expect(timer.oneOffTotal == nil)
        #expect(timer.remaining <= preset)
    }

    @Test @MainActor func aLinkThatDoesNotReadChangesNothing() throws {
        let model = AppModel()
        model.nook.presentRingLight = { _ in }
        let timer = model.nook.timer
        let wasLit = model.nook.isRingLightOn

        for text in ["hangover://quit", "hangover://timer/start?minutes=0", "https://example.com/timer/start"] {
            #expect(model.handleIncomingURL(try #require(URL(string: text))) == nil)
        }

        #expect(!timer.isActive)
        #expect(!model.nook.isMirrorOn)
        #expect(model.nook.isRingLightOn == wasLit)
        #expect(model.notchStatus == .closed)
    }

    @Test @MainActor func ringLightLinksFlipTheSavedSwitchAndLightNothingWithTheMirrorOff() {
        let model = AppModel()
        var lit: [Bool] = []
        // Nothing in this test may light the real screen.
        model.nook.presentRingLight = { lit.append($0) }
        let wasOn = model.nook.isRingLightOn
        defer { model.nook.isRingLightOn = wasOn }
        model.nook.isRingLightOn = false
        lit.removeAll()

        #expect(model.perform(.setRingLight(.on)))
        #expect(model.nook.isRingLightOn)
        #expect(model.perform(.setRingLight(.toggle)))
        #expect(!model.nook.isRingLightOn)
        #expect(model.perform(.setRingLight(.toggle)))
        #expect(model.perform(.setRingLight(.off)))
        #expect(!model.nook.isRingLightOn)

        // The mirror is off, which keeps every one of those dark.
        #expect(!lit.contains(true))
    }

    @Test @MainActor func aPageLinkTurnsAnOpenIslandAndKeepsItOpen() {
        let model = AppModel()
        model.nook.presentRingLight = { _ in }
        model.notchStatus = .opened
        model.notchOpenReason = .hover
        model.nook.pageOverride = .agents

        #expect(model.perform(.openNook))
        #expect(model.nook.pageOverride == .nook)
        // Pinned: it no longer closes when the pointer leaves.
        #expect(model.notchOpenReason == .click)

        #expect(model.perform(.openAgents))
        #expect(model.nook.pageOverride == .agents)
        #expect(model.notchStatus == .opened)
    }

    private static func waitingSession(_ phase: SessionPhase = .waitingForApproval) -> AgentSession {
        AgentSession(
            id: "waiting",
            title: "Claude · project",
            tool: .claudeCode,
            attachmentState: .attached,
            phase: phase,
            summary: "Approve command",
            updatedAt: .now,
            permissionRequest: PermissionRequest(title: "Approve", summary: "Allow edit?", affectedPath: "/tmp/file.swift")
        )
    }

    @Test @MainActor func anApprovalInTheOpenListIsNeverCoveredByAPageLink() {
        let model = AppModel()
        model.nook.presentRingLight = { _ in }
        model.state = SessionState(sessions: [Self.waitingSession()])
        // "Show all" on a card leaves the list open with the approval in
        // its row and the reason set to a click.
        model.notchStatus = .opened
        model.notchOpenReason = .click
        model.nook.pageOverride = .agents

        #expect(model.showsWaitingRequestInList)
        #expect(!model.perform(.openNook))
        #expect(!model.perform(.openAgents))
        #expect(!model.perform(.setMirror(.on)))
        #expect(!model.nook.isMirrorOn)
        #expect(model.nook.pageOverride == .agents)
        #expect(model.notchOpenReason == .click)

        // Hover-opened on the list: the same, and the island is not pinned.
        model.notchOpenReason = .hover
        #expect(!model.perform(.openNook))
        #expect(model.notchOpenReason == .hover)
    }

    @Test @MainActor func aWaitingRequestThatIsNotOnScreenDoesNotBlockAPageLink() {
        let model = AppModel()
        model.nook.presentRingLight = { _ in }
        model.state = SessionState(sessions: [Self.waitingSession(.waitingForAnswer)])
        // The Nook page shows no rows.
        model.notchStatus = .opened
        model.notchOpenReason = .click
        model.nook.pageOverride = .nook

        #expect(!model.showsWaitingRequestInList)
        #expect(model.perform(.openAgents))
        #expect(model.nook.pageOverride == .agents)
        // Now it is on screen.
        #expect(model.showsWaitingRequestInList)
        #expect(!model.perform(.openNook))

        // A running session is nothing to answer.
        model.state = SessionState(sessions: [Self.waitingSession(.running)])
        #expect(!model.showsWaitingRequestInList)
        #expect(model.perform(.openNook))
    }

    @Test @MainActor func aPageLinkDuringTheBootAnimationPinsTheIslandOpen() {
        let model = AppModel()
        model.nook.presentRingLight = { _ in }
        model.notchStatus = .opened
        model.notchOpenReason = .boot

        #expect(model.perform(.openNook))
        #expect(model.nook.pageOverride == .nook)
        // No longer the animation's to close.
        #expect(model.notchOpenReason == .click)
        #expect(!IslandBootAnimation.shouldClose(reason: model.notchOpenReason))
    }

    @Test @MainActor func aCardWaitingForAnAnswerIsNeverPushedAside() {
        let model = AppModel()
        model.nook.presentRingLight = { _ in }
        model.notchStatus = .opened
        model.notchOpenReason = .notification

        #expect(!model.perform(.openNook))
        #expect(!model.perform(.openAgents))
        // With or without a Mirror tile on the page, the card stays and the
        // camera stays off.
        #expect(!model.perform(.setMirror(.on)))
        #expect(!model.nook.isMirrorOn)
        #expect(model.nook.pageOverride == nil)
        #expect(model.notchOpenReason == .notification)
    }

    @Test @MainActor func turningTheMirrorOffNeedsNoPage() {
        let model = AppModel()
        model.nook.presentRingLight = { _ in }
        model.nook.isMirrorOn = true

        #expect(model.perform(.setMirror(.off)))
        #expect(!model.nook.isMirrorOn)
        #expect(model.notchStatus == .closed)
    }
}
