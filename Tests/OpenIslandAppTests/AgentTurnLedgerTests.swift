import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct AgentTurnLedgerTests {
    private static let id = "session-1"
    private static let start = Date(timeIntervalSince1970: 50_000)

    private static func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    private static func prompt(at seconds: TimeInterval = 0, session: String = id) -> AgentEvent {
        .activityUpdated(SessionActivityUpdated(
            sessionID: session,
            summary: "Prompt: fix the bug",
            phase: .running,
            timestamp: at(seconds),
            startsTurn: true
        ))
    }

    private static func activity(_ phase: SessionPhase, at seconds: TimeInterval) -> AgentEvent {
        .activityUpdated(SessionActivityUpdated(
            sessionID: id,
            summary: "Working",
            phase: phase,
            timestamp: at(seconds)
        ))
    }

    /// PreToolUse: the session says which tool it is about to use. The tool
    /// has not run, and may never.
    private static func asked(_ tool: String?, _ detail: String? = nil, at seconds: TimeInterval = 1) -> AgentEvent {
        .claudeSessionMetadataUpdated(ClaudeSessionMetadataUpdated(
            sessionID: id,
            claudeMetadata: ClaudeSessionMetadata(
                lastUserPrompt: "fix the bug",
                currentTool: tool,
                currentToolInputPreview: detail
            ),
            timestamp: at(seconds)
        ))
    }

    /// PostToolUse: a hook saw the tool through to its end.
    private static func finished(_ finish: AgentToolFinish, at seconds: TimeInterval = 2) -> AgentEvent {
        .activityUpdated(SessionActivityUpdated(
            sessionID: id,
            summary: "\(finish.toolName) finished.",
            phase: .running,
            timestamp: at(seconds),
            finishedTool: finish
        ))
    }

    private static func bash(_ command: String, inBackground: Bool? = nil) -> AgentToolFinish {
        AgentToolFinish(toolName: "Bash", command: command, ranInBackground: inBackground)
    }

    private static func edit(_ path: String?, tool: String = "Edit") -> AgentToolFinish {
        AgentToolFinish(toolName: tool, filePath: path)
    }

    private static func permission(at seconds: TimeInterval) -> AgentEvent {
        .permissionRequested(PermissionRequested(
            sessionID: id,
            request: PermissionRequest(title: "Allow", summary: "rm", affectedPath: ""),
            timestamp: at(seconds)
        ))
    }

    private static func completed(at seconds: TimeInterval, isSessionEnd: Bool? = nil) -> AgentEvent {
        .sessionCompleted(SessionCompleted(
            sessionID: id,
            summary: "Done",
            timestamp: at(seconds),
            isSessionEnd: isSessionEnd
        ))
    }

    private static func ledger(_ events: [AgentEvent]) -> AgentTurnLedger {
        var ledger = AgentTurnLedger()
        events.forEach { ledger.record($0) }
        return ledger
    }

    // MARK: Recording

    @Test
    func aSessionWhosePromptWasNeverSeenHasNoRecord() {
        let ledger = Self.ledger([
            Self.activity(.running, at: 1),
            Self.finished(Self.bash("swift test")),
            Self.completed(at: 9),
        ])
        #expect(ledger.turn(for: Self.id) == nil)
    }

    @Test
    func aPromptStartsARecordAndAFinishEndsIt() {
        let ledger = Self.ledger([Self.prompt(), Self.completed(at: 42)])
        let record = ledger.turn(for: Self.id)
        #expect(record?.startedAt == Self.start)
        #expect(record?.endedAt == Self.at(42))
        #expect(record?.finishedTools.isEmpty == true)
    }

    @Test
    func aToolIsRecordedWhenAHookSawItFinishAndNotWhenItWasAskedFor() {
        var ledger = Self.ledger([Self.prompt(), Self.asked("Bash", "swift test")])
        #expect(ledger.turn(for: Self.id)?.finishedTools.isEmpty == true)

        ledger.record(Self.finished(Self.bash("swift test")))
        #expect(ledger.turn(for: Self.id)?.finishedTools == [Self.bash("swift test")])
    }

    @Test
    func aDeniedToolIsNeverRecorded() throws {
        // Claude asks to edit a file and to run the tests. The user denies
        // both, and each denial ends the turn.
        let ledger = Self.ledger([
            Self.prompt(),
            Self.asked("Edit", "/repo/a.swift"),
            Self.permission(at: 2),
            Self.completed(at: 3),
            Self.activity(.running, at: 4),
            Self.asked("Bash", "swift test", at: 5),
            Self.permission(at: 6),
            Self.completed(at: 7),
        ])
        let record = try #require(ledger.turn(for: Self.id))
        #expect(record.finishedTools.isEmpty)
        #expect(record.permissionRequests == 2)

        let summary = try #require(AgentTurnSummary.make(from: record, tool: .claudeCode))
        #expect(summary.fileEdits == .files([]))
        #expect(summary.commands.isEmpty)
        #expect(summary.testCommands.isEmpty)
        // Nothing was edited and no tests ran. The line says the time only.
        #expect(AgentTurnSummaryPart.parts(for: summary) == [.duration("7s")])
    }

    @Test
    func aToolThatFailedIsNeverRecorded() {
        // PostToolUseFailure reaches the app as an update with no finished
        // tool on it.
        let ledger = Self.ledger([
            Self.prompt(),
            Self.asked("Bash", "swift test"),
            Self.activity(.running, at: 2),
            Self.completed(at: 9),
        ])
        #expect(ledger.turn(for: Self.id)?.finishedTools.isEmpty == true)
    }

    @Test
    func twoCallsThatLookTheSameAreTwoEntries() {
        // The second identical call changes nothing about "the tool the
        // session is in", which is why that is not what is counted.
        let ledger = Self.ledger([
            Self.prompt(),
            Self.asked("Edit", "/repo/a.swift"),
            Self.finished(Self.edit("/repo/a.swift")),
            Self.finished(Self.edit("/repo/a.swift")),
            Self.finished(Self.edit("/repo/a.swift")),
        ])
        #expect(ledger.turn(for: Self.id)?.finishedTools.count == 3)
    }

    @Test
    func callsRunningSideBySideAreEachCountedOnce() {
        // Pre A, Pre B, Post A, Post B.
        let ledger = Self.ledger([
            Self.prompt(),
            Self.asked("Read", "/tmp/a.swift"),
            Self.asked("Read", "/tmp/b.swift"),
            Self.asked("Read", "/tmp/a.swift"),
            Self.finished(AgentToolFinish(toolName: "Read", filePath: "/tmp/a.swift")),
            Self.asked("Read", "/tmp/b.swift"),
            Self.finished(AgentToolFinish(toolName: "Read", filePath: "/tmp/b.swift")),
        ])
        #expect(ledger.turn(for: Self.id)?.finishedTools.count == 2)
    }

    @Test
    func aNewPromptStartsOver() {
        let ledger = Self.ledger([
            Self.prompt(),
            Self.finished(Self.bash("ls")),
            // Interrupted in the terminal: no finish ever arrives.
            Self.prompt(at: 100),
            Self.finished(Self.bash("pwd"), at: 101),
            Self.completed(at: 130),
        ])
        let record = ledger.turn(for: Self.id)
        #expect(record?.startedAt == Self.at(100))
        #expect(record?.finishedTools == [Self.bash("pwd")])
    }

    @Test
    func workAfterAFinishWithNoNewPromptBelongsToTheSamePrompt() {
        // A denied tool reports a finish, and the agent carries on.
        var ledger = Self.ledger([
            Self.prompt(),
            Self.asked("Bash", "rm -rf build"),
            Self.permission(at: 2),
            Self.completed(at: 3),
        ])
        #expect(ledger.turn(for: Self.id)?.endedAt == Self.at(3))

        ledger.record(Self.activity(.running, at: 4))
        #expect(ledger.turn(for: Self.id)?.endedAt == nil)

        ledger.record(Self.finished(Self.bash("swift build"), at: 5))
        ledger.record(Self.completed(at: 60))
        let record = ledger.turn(for: Self.id)
        #expect(record?.startedAt == Self.start)
        #expect(record?.endedAt == Self.at(60))
        // The denied "rm" never ran. The build did.
        #expect(record?.finishedTools == [Self.bash("swift build")])
        #expect(record?.permissionRequests == 1)
    }

    @Test
    func aToolThatFinishesAfterTheFinishReopensTheRecord() {
        var ledger = Self.ledger([Self.prompt(), Self.completed(at: 10)])
        ledger.record(Self.finished(Self.bash("swift build"), at: 20))
        let record = ledger.turn(for: Self.id)
        #expect(record?.endedAt == nil)
        #expect(record?.finishedTools.count == 1)
    }

    @Test
    func aLaterIdleNoticeDoesNotMoveTheFinish() {
        let ledger = Self.ledger([
            Self.prompt(),
            Self.completed(at: 20),
            Self.activity(.completed, at: 80),
        ])
        #expect(ledger.turn(for: Self.id)?.endedAt == Self.at(20))
    }

    @Test
    func anAgentThatQuitsMidWorkLeavesNoRecord() {
        let quitMidWork = Self.ledger([Self.prompt(), Self.completed(at: 5, isSessionEnd: true)])
        #expect(quitMidWork.turn(for: Self.id) == nil)

        // Quitting after the work was done keeps what it did.
        let quitAfter = Self.ledger([
            Self.prompt(),
            Self.completed(at: 5),
            Self.completed(at: 90, isSessionEnd: true),
        ])
        #expect(quitAfter.turn(for: Self.id)?.endedAt == Self.at(5))
    }

    @Test
    func finishesPastTheLimitAreCountedAndNotKept() {
        var ledger = Self.ledger([Self.prompt()])
        for index in 0..<(AgentTurnLedger.finishedToolLimit + 3) {
            ledger.record(Self.finished(Self.bash("echo \(index)")))
        }
        let record = ledger.turn(for: Self.id)
        #expect(record?.finishedTools.count == AgentTurnLedger.finishedToolLimit)
        #expect(record?.unkeptFinishedTools == 3)
    }

    @Test
    func sessionsThatAreGoneAreForgotten() {
        var ledger = Self.ledger([Self.prompt(), Self.prompt(session: "other")])
        ledger.prune(keeping: ["other"])
        #expect(ledger.turn(for: Self.id) == nil)
        #expect(ledger.turn(for: "other") != nil)
    }

    // MARK: Summary

    private static func record(
        _ finished: [AgentToolFinish],
        seconds: TimeInterval? = 252,
        unkept: Int = 0,
        permissions: Int = 0
    ) -> AgentTurnRecord {
        AgentTurnRecord(
            startedAt: start,
            endedAt: seconds.map(at),
            finishedTools: finished,
            unkeptFinishedTools: unkept,
            permissionRequests: permissions
        )
    }

    @Test
    func aSessionStillWorkingHasNoSummary() {
        #expect(AgentTurnSummary.make(from: Self.record([], seconds: nil), tool: .claudeCode) == nil)
    }

    @Test
    func aClaudeSummaryHoldsWhatItsHooksSawFinish() throws {
        let summary = try #require(AgentTurnSummary.make(
            from: Self.record(
                [
                    AgentToolFinish(toolName: "Read", filePath: "/repo/Sources/A.swift"),
                    Self.edit("/repo/Sources/A.swift"),
                    Self.edit("/repo/Sources/A.swift"),
                    Self.edit("/repo/Tests/ATests.swift", tool: "Write"),
                    Self.bash("swift build"),
                    Self.bash("swift test --filter ATests"),
                ],
                permissions: 2
            ),
            tool: .claudeCode
        ))

        let expectedDuration: TimeInterval = 252
        #expect(summary.duration == expectedDuration)
        // One entry per file, in the order they were first edited. A file
        // that was only read is not in it.
        #expect(summary.fileEdits == .files(["/repo/Sources/A.swift", "/repo/Tests/ATests.swift"]))
        #expect(summary.commands == ["swift build", "swift test --filter ATests"])
        #expect(summary.testCommands == ["swift test --filter ATests"])
        #expect(summary.permissionRequests == 2)
    }

    @Test
    func noFinishedEditMeansNoFilesAndNoClaimAboutTests() throws {
        let summary = try #require(AgentTurnSummary.make(
            from: Self.record([Self.bash("git status")]),
            tool: .claudeCode
        ))
        #expect(summary.fileEdits == .files([]))
        #expect(summary.testCommands.isEmpty)
        #expect(AgentTurnSummaryPart.parts(for: summary) == [.duration("4m 12s"), .commands(1)])
    }

    @Test
    func anEditThatDoesNotNameItsFileLeavesTheFilesLineOff() throws {
        let summary = try #require(AgentTurnSummary.make(
            from: Self.record([Self.edit("/repo/a.swift"), Self.edit(nil, tool: "NotebookEdit")]),
            tool: .claudeCode
        ))
        #expect(summary.fileEdits == .unknown)
        #expect(AgentTurnSummaryPart.parts(for: summary) == [.duration("4m 12s")])
    }

    @Test
    func aClippedPreviewIsNeverAFilePath() throws {
        let clipped = "/Users/someone/Library/Mobile Documents/iCloud~md~obsidian/Documents/Study-Notes/UCLA/F2026/Ling 1\u{2026}"
        #expect(AgentTurnRules.filePath(from: clipped) == nil)
        #expect(AgentTurnRules.filePath(from: "/repo/Sources/Deep/Fol...") == nil)

        // A turn with such an edit says nothing about files.
        let summary = try #require(AgentTurnSummary.make(
            from: Self.record([Self.edit("/repo/a.swift"), Self.edit(clipped)]),
            tool: .claudeCode
        ))
        #expect(summary.fileEdits == .unknown)
    }

    @Test
    func twoFilesInOneDeepFolderAreTwoFiles() throws {
        let folder = "/Users/someone/Library/Mobile Documents/iCloud~md~obsidian/Documents/Study-Notes/UCLA/F2026/Ling 132/weekly-notes"
        #expect(folder.count > 110)
        let summary = try #require(AgentTurnSummary.make(
            from: Self.record([Self.edit("\(folder)/week-01.md"), Self.edit("\(folder)/week-02.md")]),
            tool: .claudeCode
        ))
        #expect(summary.fileEdits == .files(["\(folder)/week-01.md", "\(folder)/week-02.md"]))
        #expect(AgentTurnRules.fileName("\(folder)/week-02.md") == "week-02.md")
    }

    @Test
    func workHandedToASubagentLeavesTheCountsOff() throws {
        // The bridge drops a subagent's own hooks. What it edited and ran
        // is not known, which makes any count here a short one.
        let summary = try #require(AgentTurnSummary.make(
            from: Self.record([
                Self.edit("/repo/a.swift"),
                Self.bash("swift test"),
                AgentToolFinish(toolName: "Agent"),
            ]),
            tool: .claudeCode
        ))
        #expect(summary.fileEdits == .unknown)
        #expect(summary.commands.isEmpty)
        // That the session itself ran the tests is still true.
        #expect(summary.testCommands == ["swift test"])
        #expect(AgentTurnSummaryPart.parts(for: summary) == [.duration("4m 12s"), .testsRan])
    }

    @Test
    func aCommandHandedToTheBackgroundIsNotOneThatRan() throws {
        let summary = try #require(AgentTurnSummary.make(
            from: Self.record([Self.bash("git status"), Self.bash("swift test", inBackground: true)]),
            tool: .claudeCode
        ))
        // The test run was started and not seen to end.
        #expect(summary.testCommands.isEmpty)
        // The list would be short by one: no count is given.
        #expect(summary.commands.isEmpty)
    }

    @Test
    func codexGetsItsShellCommandsAndNothingAboutFiles() throws {
        let summary = try #require(AgentTurnSummary.make(
            from: Self.record([Self.bash("cargo test"), Self.bash("git diff")], permissions: 3),
            tool: .codex
        ))
        #expect(summary.fileEdits == .unknown)
        #expect(summary.commands == ["cargo test", "git diff"])
        #expect(summary.testCommands == ["cargo test"])
        // A Codex request can reach the app twice. No count is given.
        #expect(summary.permissionRequests == nil)
    }

    @Test(arguments: [AgentTool.openCode, .pi, .cursor, .geminiCLI])
    func anAgentWhoseHooksProveNoFinishedToolGetsTheTimeOnly(tool: AgentTool) throws {
        let summary = try #require(AgentTurnSummary.make(
            from: Self.record([Self.edit("/repo/a.swift"), Self.bash("swift test")], seconds: 12),
            tool: tool
        ))
        #expect(summary.fileEdits == .unknown)
        #expect(summary.commands.isEmpty)
        #expect(summary.testCommands.isEmpty)
        #expect(AgentTurnSummaryPart.parts(for: summary) == [.duration("12s")])
    }

    @Test
    func aSummaryThatLostFinishesGivesNoCounts() throws {
        let summary = try #require(AgentTurnSummary.make(
            from: Self.record([Self.edit("/repo/a.swift"), Self.bash("swift test")], unkept: 4),
            tool: .claudeCode
        ))
        #expect(summary.fileEdits == .unknown)
        #expect(summary.commands.isEmpty)
        #expect(summary.testCommands == ["swift test"])
    }

    @Test
    func agentsAreSortedByWhatTheirHooksProve() {
        #expect(AgentTurnRules.finishEvidence(for: .claudeCode) == .everyTool)
        #expect(AgentTurnRules.finishEvidence(for: .qoder) == .everyTool)
        #expect(AgentTurnRules.finishEvidence(for: .codex) == .shellOnly)
        #expect(AgentTurnRules.finishEvidence(for: .openCode) == AgentFinishEvidence.none)
        #expect(AgentTurnRules.finishEvidence(for: .pi) == AgentFinishEvidence.none)
        #expect(AgentTurnRules.finishEvidence(for: .cursor) == AgentFinishEvidence.none)
        #expect(AgentTurnRules.finishEvidence(for: .geminiCLI) == AgentFinishEvidence.none)

        #expect(AgentTurnRules.countsPermissionRequests(.claudeCode))
        #expect(AgentTurnRules.countsPermissionRequests(.openCode))
        #expect(!AgentTurnRules.countsPermissionRequests(.codex))
    }

    @Test
    func toolNamesFromOtherAgentsAreRecognized() {
        #expect(AgentTurnRules.isShellTool("exec_command"))
        #expect(AgentTurnRules.isShellTool("bash"))
        #expect(!AgentTurnRules.isShellTool("Read"))
        #expect(AgentTurnRules.isEditTool("apply_patch"))
        #expect(AgentTurnRules.isEditTool("MultiEdit"))
        #expect(!AgentTurnRules.isEditTool("Bash"))
        #expect(AgentTurnRules.isDelegatingTool("Agent"))
        #expect(AgentTurnRules.isDelegatingTool("Task"))
        #expect(!AgentTurnRules.isDelegatingTool("TaskCreate"))

        #expect(AgentTurnRules.filePath(from: "/repo/a.swift") == "/repo/a.swift")
        #expect(AgentTurnRules.filePath(from: "~/notes.md") == "~/notes.md")
        #expect(AgentTurnRules.filePath(from: "a.swift") == nil)
        #expect(AgentTurnRules.filePath(from: nil) == nil)
        #expect(AgentTurnRules.fileName("/repo/Sources/A.swift") == "A.swift")
        #expect(AgentTurnRules.oneLine("cd pkg &&\n  swift   test") == "cd pkg && swift test")
    }

    @Test
    func durationsReadTheWayTheRestOfTheIslandWritesThem() {
        #expect(AgentTurnRules.durationText(0.2) == "0s")
        #expect(AgentTurnRules.durationText(38) == "38s")
        #expect(AgentTurnRules.durationText(252) == "4m 12s")
        #expect(AgentTurnRules.durationText(3_900) == "1h 5m")
    }

    // MARK: Test runs

    @Test(arguments: [
        "swift test",
        "swift build && swift test --filter Foo",
        "cd app; bun test",
        "cd app\nbun test",
        "FOO=1 npm run test:unit",
        "NAME=\"a b\" pytest -q",
        "uv run pytest -q",
        "./node_modules/.bin/jest src",
        "xcodebuild -scheme App -destination 'platform=macOS' test",
        "cargo test --workspace | tee out.log",
        "(cd pkg && go test ./...)",
        "git commit -m \"wip\" && swift test",
        "echo \"building; not yet\"; npm test",
        "swift test 2>&1 | tail -5",
        "cat > notes.txt <<EOF\nrun later\nEOF\nswift test",
    ])
    func commandsThatStartATestRunner(command: String) {
        #expect(AgentTestCommands.startsTestRunner(command))
    }

    @Test(arguments: [
        "swift build",
        "echo swift test",
        "git commit -m 'add go test coverage'",
        "git commit -m \"wip; swift test still red\"",
        "git commit -m 'fix && npm test'",
        "git commit -m \"it said \\\"done; swift test\\\" again\"",
        "echo $'it\\'s; swift test'",
        "bash -c \"swift test\"",
        "\"swift\" test",
        "cargo test --no-run",
        "pytest --collect-only",
        "swift test --help",
        "swift build || swift test",
        "ls # ; swift test",
        "# swift test",
        "cat > notes.txt <<EOF\nswift test\nEOF",
        "cat <<-'DONE' > plan.md\n\tthen: npm test\n\tDONE",
        "git commit -m \"$(cat <<'EOF'\nfix thing) say \"hi; swift test\nEOF\n)\"",
        "git commit -m \"$(printf \"x; swift test\")\"",
        "cat pytest.ini",
        "npm run build",
        "ls tests",
        "",
    ])
    func commandsThatDoNot(command: String) {
        #expect(!AgentTestCommands.startsTestRunner(command))
    }

    @Test
    func aCommandLineIsSplitTheWayAShellReadsIt() {
        let commands = AgentShellWords.commands(in: "FOO=1 swift test; echo 'a; b' | wc -l || true")
        #expect(commands.map { $0.words.map(\.text) } == [
            ["FOO=1", "swift", "test"],
            ["echo", "a; b"],
            ["wc", "-l"],
            ["true"],
        ])
        #expect(commands.map(\.followsOr) == [false, false, false, true])
        #expect(commands[1].words[1].hasQuotes)
        #expect(commands[1].words[1].startsQuoted)
        #expect(!commands[0].words[0].hasQuotes)

        // The text of a here-document is no command.
        let hereDocument = AgentShellWords.commands(in: "cat <<EOF > out.txt\nrm -rf /\nEOF\nls")
        #expect(hereDocument.map { $0.words.map(\.text) } == [["cat", ">", "out.txt"], ["ls"]])

        // One that never ends takes the rest with it.
        let unfinished = AgentShellWords.commands(in: "cat <<EOF\nswift test")
        #expect(unfinished.map { $0.words.map(\.text) } == [["cat"]])
    }

    // MARK: The one line

    @Test
    func theLineKeepsWhatIsKnownAndDropsZeroes() throws {
        let full = try #require(AgentTurnSummary.make(
            from: Self.record([Self.edit("/repo/a.swift"), Self.bash("swift test")]),
            tool: .claudeCode
        ))
        #expect(AgentTurnSummaryPart.parts(for: full) == [.duration("4m 12s"), .files(1), .commands(1), .testsRan])

        let talkOnly = try #require(AgentTurnSummary.make(from: Self.record([], seconds: 12), tool: .claudeCode))
        #expect(AgentTurnSummaryPart.parts(for: talkOnly) == [.duration("12s")])

        let codex = try #require(AgentTurnSummary.make(
            from: Self.record([Self.bash("ls")], seconds: 5),
            tool: .codex
        ))
        #expect(AgentTurnSummaryPart.parts(for: codex) == [.duration("5s"), .commands(1)])
    }
}

struct AgentReplyDraftTests {
    private static let promptA = UUID()
    private static let promptB = UUID()

    @Test
    func onlyAgentsWithAHeldQuestionTakeATypedAnswer() {
        #expect(AgentQuestionReplyRoute.route(for: .claudeCode) == .bridge)
        #expect(AgentQuestionReplyRoute.route(for: .kimiCLI) == .bridge)
        #expect(AgentQuestionReplyRoute.route(for: .openCode) == .bridge)
        // Codex only says it is waiting. Nothing carries an answer back.
        #expect(AgentQuestionReplyRoute.route(for: .codex) == .terminalOnly)
        #expect(AgentQuestionReplyRoute.route(for: .geminiCLI) == .terminalOnly)
    }

    @Test
    func aDraftBelongsToOneQuestion() {
        var store = AgentReplyDraftStore()
        var draft = AgentQuestionDraft()
        draft.typedReply = "use sqlite"
        draft.selections["Which database?"] = ["Other"]
        store.setQuestionDraft(draft, sessionID: "s", promptID: Self.promptA)

        #expect(store.questionDraft(sessionID: "s", promptID: Self.promptA) == draft)
        // A later question of the same session starts empty.
        #expect(store.questionDraft(sessionID: "s", promptID: Self.promptB).isEmpty)
        #expect(store.questionDraft(sessionID: "other", promptID: Self.promptA).isEmpty)
    }

    @Test
    func anEmptiedDraftIsNotKept() {
        var store = AgentReplyDraftStore()
        var draft = AgentQuestionDraft()
        draft.typedReply = "x"
        store.setQuestionDraft(draft, sessionID: "s", promptID: Self.promptA)
        store.setQuestionDraft(AgentQuestionDraft(), sessionID: "s", promptID: Self.promptA)
        store.setCompletionDraft("y", sessionID: "s")
        store.setCompletionDraft("", sessionID: "s")
        #expect(store.isEmpty)
    }

    @Test
    func draftsWithNothingLeftToAnswerAreDropped() {
        var store = AgentReplyDraftStore()
        var draft = AgentQuestionDraft()
        draft.typedReply = "half an answer"
        store.setQuestionDraft(draft, sessionID: "asking", promptID: Self.promptA)
        store.setQuestionDraft(draft, sessionID: "answered", promptID: Self.promptA)
        store.setCompletionDraft("keep going", sessionID: "finished")
        store.setCompletionDraft("too late", sessionID: "working-again")
        store.setCompletionDraft("gone", sessionID: "gone")

        let prompt = QuestionPrompt(id: Self.promptA, title: "Which?", options: [])
        func session(_ id: String, _ phase: SessionPhase, prompt: QuestionPrompt? = nil) -> AgentSession {
            AgentSession(id: id, title: id, tool: .claudeCode, phase: phase, summary: "", updatedAt: .now, questionPrompt: prompt)
        }
        store.prune(to: [
            session("asking", .waitingForAnswer, prompt: prompt),
            session("answered", .running),
            session("finished", .completed),
            session("working-again", .running),
        ])

        #expect(store.questionDraft(sessionID: "asking", promptID: Self.promptA) == draft)
        #expect(store.questionDraft(sessionID: "answered", promptID: Self.promptA).isEmpty)
        #expect(store.completionDraft(sessionID: "finished") == "keep going")
        #expect(store.completionDraft(sessionID: "working-again").isEmpty)
        #expect(store.completionDraft(sessionID: "gone").isEmpty)
    }
}
