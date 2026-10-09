import Dispatch
import Foundation
import Testing
@testable import OpenIslandCore

/// A home folder, a managed folder and a project of their own in the
/// temporary folder. The real `~/.claude` is never looked at.
private struct SettingsSandbox {
    let root: URL
    let home: URL
    let managed: URL
    let project: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeAskRuleSourceTests-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        home = root.appendingPathComponent("home", isDirectory: true)
        managed = root.appendingPathComponent("managed", isDirectory: true)
        project = home.appendingPathComponent("code/app", isDirectory: true)
        for folder in [home, managed, project] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    var locations: ClaudeSettingsLocations {
        ClaudeSettingsLocations(
            userSettings: home.appendingPathComponent(".claude/settings.json"),
            managedDirectory: managed,
            home: home
        )
    }

    var source: ClaudeAskRuleSource {
        let locations = locations
        return ClaudeAskRuleSource(locations: { locations })
    }

    func write(_ text: String, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    func writeAskRules(_ rules: [String], to file: URL) throws {
        let list = rules.map { "\"\($0)\"" }.joined(separator: ", ")
        try write("{\"permissions\": {\"ask\": [\(list)], \"allow\": [\"Bash\"]}}", to: file)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }
}

struct ClaudeAskRuleSourceTests {
    private static func bash(_ command: String) -> ClaudeHookJSONValue {
        .object(["command": .string(command)])
    }

    // MARK: Which files

    @Test
    func theProjectFilesAreThoseOfTheFolderAndOfEachFolderUpToHome() throws {
        let sandbox = try SettingsSandbox()
        defer { sandbox.cleanUp() }
        let deep = sandbox.project.appendingPathComponent("Sources/Core", isDirectory: true)

        let files = sandbox.locations.projectSettings(forWorkingDirectory: deep.path).map(\.path)

        let expected = [
            "code/app/Sources/Core", "code/app/Sources", "code/app", "code",
        ].flatMap { folder in
            ["settings.json", "settings.local.json"].map { sandbox.home.path + "/\(folder)/.claude/\($0)" }
        }
        #expect(files == expected)
    }

    @Test
    func aSessionInTheHomeFolderReadsOnlyItsOwnFolder() throws {
        let sandbox = try SettingsSandbox()
        defer { sandbox.cleanUp() }

        let files = sandbox.locations.projectSettings(forWorkingDirectory: sandbox.home.path).map(\.path)

        #expect(files == [
            sandbox.home.path + "/.claude/settings.json",
            sandbox.home.path + "/.claude/settings.local.json",
        ])
    }

    @Test
    func aFolderOutsideHomeIsWalkedUpToTheRootAndNotIntoIt() {
        let locations = ClaudeSettingsLocations(
            userSettings: URL(fileURLWithPath: "/nowhere/home/.claude/settings.json"),
            managedDirectory: nil,
            home: URL(fileURLWithPath: "/nowhere/home", isDirectory: true)
        )

        let files = locations.projectSettings(forWorkingDirectory: "/srv/app").map(\.path)

        #expect(files == [
            "/srv/app/.claude/settings.json", "/srv/app/.claude/settings.local.json",
            "/srv/.claude/settings.json", "/srv/.claude/settings.local.json",
        ])
        #expect(locations.projectSettings(forWorkingDirectory: "").isEmpty)
        #expect(locations.projectSettings(forWorkingDirectory: "relative/path").isEmpty)
    }

    @Test
    func managedUserAndProjectFilesAreEachReadOnce() throws {
        let sandbox = try SettingsSandbox()
        defer { sandbox.cleanUp() }
        try sandbox.write("{}", to: sandbox.managed.appendingPathComponent("managed-settings.d/20-b.json"))
        try sandbox.write("{}", to: sandbox.managed.appendingPathComponent("managed-settings.d/10-a.json"))
        try sandbox.write("notes", to: sandbox.managed.appendingPathComponent("managed-settings.d/readme.txt"))

        let files = sandbox.source.settingsFiles(forWorkingDirectory: sandbox.home.path).map(\.path)

        #expect(files == [
            sandbox.managed.path + "/managed-settings.json",
            sandbox.managed.path + "/managed-settings.d/10-a.json",
            sandbox.managed.path + "/managed-settings.d/20-b.json",
            // The user's file is also the home folder's project file. Once.
            sandbox.home.path + "/.claude/settings.json",
            sandbox.home.path + "/.claude/settings.local.json",
        ])
    }

    // MARK: Reading

    @Test
    func rulesComeFromTheUserTheProjectTheLocalAndTheManagedFile() throws {
        let sandbox = try SettingsSandbox()
        defer { sandbox.cleanUp() }
        try sandbox.writeAskRules(["Bash(launchctl *)"], to: sandbox.locations.userSettings)
        try sandbox.writeAskRules(["Bash(rm -rf *)"], to: sandbox.project.appendingPathComponent(".claude/settings.json"))
        try sandbox.writeAskRules(["Bash(sudo:*)"], to: sandbox.project.appendingPathComponent(".claude/settings.local.json"))
        try sandbox.writeAskRules(["Bash(git clean *)"], to: sandbox.managed.appendingPathComponent("managed-settings.json"))
        try sandbox.writeAskRules(["WebFetch"], to: sandbox.managed.appendingPathComponent("managed-settings.d/web.json"))
        let source = sandbox.source

        let rules = source.rules(forWorkingDirectory: sandbox.project.path)

        #expect(Set(rules.map(\.specifier)) == ["launchctl *", "rm -rf *", "sudo:*", "git clean *", nil])
        for command in ["launchctl version", "rm -rf build", "sudo ls", "git clean -fd"] {
            let rule = source.matchingRule(toolName: "Bash", toolInput: Self.bash(command), workingDirectory: sandbox.project.path)
            #expect(rule != nil, "\(command)")
        }
        #expect(source.matchingRule(toolName: "Bash", toolInput: Self.bash("swift test"), workingDirectory: sandbox.project.path) == nil)
        #expect(source.matchingRule(toolName: "WebFetch", toolInput: nil, workingDirectory: sandbox.project.path) != nil)
    }

    @Test
    func aProjectRuleCountsBelowItsFolderAndNotInAnotherProject() throws {
        let sandbox = try SettingsSandbox()
        defer { sandbox.cleanUp() }
        try sandbox.writeAskRules(["Bash(rm -rf *)"], to: sandbox.project.appendingPathComponent(".claude/settings.json"))
        let source = sandbox.source
        let below = sandbox.project.appendingPathComponent("Sources/Core").path
        let other = sandbox.home.appendingPathComponent("code/other").path

        #expect(source.matchingRule(toolName: "Bash", toolInput: Self.bash("rm -rf x"), workingDirectory: below) != nil)
        #expect(source.matchingRule(toolName: "Bash", toolInput: Self.bash("rm -rf x"), workingDirectory: other) == nil)
    }

    @Test
    func aMissingABrokenAndAnOddFileGiveNoRulesAndTheOthersStillCount() throws {
        let sandbox = try SettingsSandbox()
        defer { sandbox.cleanUp() }
        let broken = sandbox.project.appendingPathComponent(".claude/settings.json")
        let list = sandbox.project.appendingPathComponent(".claude/settings.local.json")
        try sandbox.write("{ \"permissions\": { \"ask\": [\"Bash(rm -rf *)\"", to: broken)
        try sandbox.write("[\"Bash\"]", to: list)
        try sandbox.writeAskRules(["Bash(launchctl *)"], to: sandbox.locations.userSettings)

        #expect(ClaudeAskRuleSource.read(sandbox.home.appendingPathComponent("no/such/settings.json")) == .missing)
        if case .invalid = ClaudeAskRuleSource.read(broken) {} else { Issue.record("Broken JSON was not reported as invalid") }
        if case .invalid = ClaudeAskRuleSource.read(list) {} else { Issue.record("A list at the top was not reported as invalid") }

        let rules = sandbox.source.rules(forWorkingDirectory: sandbox.project.path)
        #expect(rules == [ClaudeAskRule(tool: "Bash", specifier: "launchctl *")])
    }

    @Test
    func aFileWithoutAskRulesOrWithOddEntriesGivesWhatItCan() throws {
        let sandbox = try SettingsSandbox()
        defer { sandbox.cleanUp() }
        let file = sandbox.locations.userSettings

        try sandbox.write("{\"model\": \"opus\"}", to: file)
        #expect(ClaudeAskRuleSource.read(file) == .rules([]))

        try sandbox.write("{\"permissions\": {\"ask\": \"Bash\"}}", to: file)
        #expect(ClaudeAskRuleSource.read(file) == .rules([]))

        try sandbox.write("{\"permissions\": {\"ask\": [\"Bash(sudo *)\", 7, \"\", \"(broken\", null]}}", to: file)
        #expect(ClaudeAskRuleSource.read(file) == .rules([ClaudeAskRule(tool: "Bash", specifier: "sudo *")]))
    }

    @Test
    func aChangedFileIsReadAgainAndARemovedOneStopsCounting() throws {
        let sandbox = try SettingsSandbox()
        defer { sandbox.cleanUp() }
        let file = sandbox.locations.userSettings
        let source = sandbox.source
        func matches(_ command: String) -> Bool {
            source.matchingRule(toolName: "Bash", toolInput: Self.bash(command), workingDirectory: sandbox.project.path) != nil
        }

        try sandbox.writeAskRules(["Bash(launchctl *)"], to: file)
        #expect(matches("launchctl list"))
        #expect(!matches("sudo ls"))

        // A different size, which the source notices whatever the clock says.
        try sandbox.writeAskRules(["Bash(launchctl *)", "Bash(sudo *)"], to: file)
        #expect(matches("sudo ls"))

        try FileManager.default.removeItem(at: file)
        #expect(!matches("launchctl list"))
    }

    @Test
    func nothingIsWrittenToTheSettingsFiles() throws {
        let sandbox = try SettingsSandbox()
        defer { sandbox.cleanUp() }
        let file = sandbox.locations.userSettings
        try sandbox.writeAskRules(["Bash(launchctl *)"], to: file)
        let before = try Data(contentsOf: file)
        let listing = try FileManager.default.subpathsOfDirectory(atPath: sandbox.root.path).sorted()

        _ = sandbox.source.rules(forWorkingDirectory: sandbox.project.path)

        #expect(try Data(contentsOf: file) == before)
        #expect(try FileManager.default.subpathsOfDirectory(atPath: sandbox.root.path).sorted() == listing)
    }

    // MARK: Hook payloads

    @Test
    func onlyClaudeCodeOnThisMacIsLookedAt() throws {
        let sandbox = try SettingsSandbox()
        defer { sandbox.cleanUp() }
        try sandbox.writeAskRules(["Bash(launchctl *)"], to: sandbox.locations.userSettings)
        let source = sandbox.source
        func makePayload(source hookSource: String? = nil, remote: Bool? = nil, tool: String? = "Bash") -> ClaudeHookPayload {
            var payload = ClaudeHookPayload(
                cwd: sandbox.project.path,
                hookEventName: .permissionRequest,
                sessionID: "session",
                toolName: tool,
                toolInput: Self.bash("launchctl list")
            )
            payload.hookSource = hookSource
            payload.remote = remote
            return payload
        }

        #expect(source.matchingRule(for: makePayload()) != nil)
        #expect(source.matchingRule(for: makePayload(source: "claude")) != nil)
        // Another agent that speaks the same hook format keeps its own settings.
        #expect(source.matchingRule(for: makePayload(source: "qoder")) == nil)
        // A remote session's settings are on the other machine.
        #expect(source.matchingRule(for: makePayload(remote: true)) == nil)
        #expect(source.matchingRule(for: makePayload(tool: nil)) == nil)
    }

    /// Each agent that speaks Claude Code's hook format keeps settings of
    /// its own. Claude Code's ask rules say nothing about their requests.
    @Test(arguments: ["qoder", "qwen", "factory", "droid", "codebuddy", "kimi"])
    func anAgentThatSharesTheHookFormatIsLeftAlone(hookSource: String) throws {
        let sandbox = try SettingsSandbox()
        defer { sandbox.cleanUp() }
        try sandbox.writeAskRules(["Bash(launchctl *)", "Bash"], to: sandbox.locations.userSettings)
        var payload = ClaudeHookPayload(
            cwd: sandbox.project.path,
            hookEventName: .permissionRequest,
            sessionID: "session",
            toolName: "Bash",
            toolInput: Self.bash("launchctl list")
        )
        payload.hookSource = hookSource

        #expect(payload.resolvedAgentTool != .claudeCode)
        #expect(sandbox.source.matchingRule(for: payload) == nil)
    }
}

/// The bridge marks a request Claude Code will only take an approval for
/// in the terminal, and holds an approval back for it.
struct ClaudeAskRuleBridgeTests {
    private enum BridgeTestError: Error {
        case noPermissionEvent
    }

    private static func send(_ command: BridgeCommand, socketURL: URL) async throws -> BridgeResponse? {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    continuation.resume(returning: try BridgeCommandClient(socketURL: socketURL).send(command))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func nextPermissionRequest(
        from iterator: inout AsyncThrowingStream<AgentEvent, Error>.AsyncIterator
    ) async throws -> PermissionRequest {
        for _ in 0..<12 {
            guard let event = try await iterator.next() else { break }
            if case let .permissionRequested(payload) = event { return payload.request }
        }
        throw BridgeTestError.noPermissionEvent
    }

    private static func permissionPayload(command: String, cwd: String, session: String) -> ClaudeHookPayload {
        ClaudeHookPayload(
            cwd: cwd,
            hookEventName: .permissionRequest,
            sessionID: session,
            toolName: "Bash",
            toolInput: .object(["command": .string(command)])
        )
    }

    @Test
    func aRequestAnAskRuleMatchesIsMarkedAndOnlyADenialIsPassedOn() async throws {
        let sandbox = try SettingsSandbox()
        defer { sandbox.cleanUp() }
        try sandbox.writeAskRules(["Bash(launchctl *)"], to: sandbox.locations.userSettings)

        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL, claudeAskRules: sandbox.source)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))
        var iterator = stream.makeAsyncIterator()

        let payload = Self.permissionPayload(command: "launchctl version", cwd: sandbox.project.path, session: "ask-session")
        async let hookResponse = Self.send(.processClaudeHook(payload), socketURL: socketURL)

        let request = try await Self.nextPermissionRequest(from: &iterator)
        #expect(request.requiresTerminalApproval)

        // An approval is taken and not passed on: the hook goes on waiting,
        // which a denial sent after it proves by being the answer.
        try await observer.send(.resolvePermission(sessionID: "ask-session", resolution: .allowOnce()))
        try await observer.send(.resolvePermission(sessionID: "ask-session", resolution: .deny(message: nil, interrupt: false)))

        let response = try await hookResponse
        guard case let .some(.claudeHookDirective(.permissionRequest(.deny(message, interrupt)))) = response else {
            Issue.record("Expected the denial to be the hook's answer, got \(String(describing: response))")
            return
        }
        #expect(message == "Permission denied in Hangover.")
        #expect(!interrupt)
    }

    private static func nextResolution(
        from iterator: inout AsyncThrowingStream<AgentEvent, Error>.AsyncIterator
    ) async throws -> (resolved: ActionableStateResolved?, sawCompletion: Bool) {
        var sawCompletion = false
        for _ in 0..<12 {
            guard let event = try await iterator.next() else { break }
            if case .sessionCompleted = event { sawCompletion = true }
            if case let .actionableStateResolved(payload) = event { return (payload, sawCompletion) }
        }
        return (nil, sawCompletion)
    }

    /// The user answers in the terminal and the agent ends its hook. The
    /// bridge sees the connection close, drops the request, and a Deny
    /// pressed afterwards is told the request is gone. It never reports a
    /// denial that did not happen.
    @Test
    func aHookThatGoesAwayClearsItsRequestAndALateDenyDeniesNothing() async throws {
        let sandbox = try SettingsSandbox()
        defer { sandbox.cleanUp() }
        try sandbox.writeAskRules(["Bash(launchctl *)"], to: sandbox.locations.userSettings)

        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL, claudeAskRules: sandbox.source)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))
        var iterator = stream.makeAsyncIterator()

        // The hook gives up waiting after a moment, which closes its
        // connection the way a hook process that is ended does.
        let payload = Self.permissionPayload(command: "launchctl version", cwd: sandbox.project.path, session: "gone-session")
        let hook = Task.detached {
            _ = try? BridgeCommandClient(socketURL: socketURL).send(.processClaudeHook(payload), timeout: 0.3)
        }

        let request = try await Self.nextPermissionRequest(from: &iterator)
        #expect(request.requiresTerminalApproval)
        await hook.value

        let gone = try await Self.nextResolution(from: &iterator)
        #expect(gone.resolved?.sessionID == "gone-session")
        #expect(gone.resolved?.summary == "Hook process disconnected.")

        try await observer.send(.resolvePermission(sessionID: "gone-session", resolution: .deny(message: nil, interrupt: false)))
        let late = try await Self.nextResolution(from: &iterator)
        #expect(late.resolved?.summary == "Permission request is no longer active.")
        #expect(!late.sawCompletion)
    }

    private static func questionPayload(cwd: String, session: String) -> ClaudeHookPayload {
        ClaudeHookPayload(
            cwd: cwd,
            hookEventName: .permissionRequest,
            sessionID: session,
            toolName: "AskUserQuestion",
            toolInput: .object([
                "questions": .array([
                    .object([
                        "question": .string("Which environment?"),
                        "header": .string("Environment"),
                        "options": .array([
                            .object(["label": .string("Prod")]),
                            .object(["label": .string("Staging")]),
                        ]),
                    ]),
                ]),
            ])
        )
    }

    private static func nextQuestion(
        from iterator: inout AsyncThrowingStream<AgentEvent, Error>.AsyncIterator
    ) async throws -> QuestionPrompt? {
        for _ in 0..<12 {
            guard let event = try await iterator.next() else { break }
            if case let .questionAsked(payload) = event { return payload.prompt }
        }
        return nil
    }

    /// An ask rule on the question tool keeps the answer in the terminal.
    /// The question is marked, an answer from the island is held back, and
    /// the hook stays open, which a refusal sent after it proves.
    @Test
    func aQuestionAnAskRuleMatchesIsMarkedAndItsAnswerIsHeldBack() async throws {
        let sandbox = try SettingsSandbox()
        defer { sandbox.cleanUp() }
        try sandbox.writeAskRules(["AskUserQuestion"], to: sandbox.locations.userSettings)

        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL, claudeAskRules: sandbox.source)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))
        var iterator = stream.makeAsyncIterator()

        let payload = Self.questionPayload(cwd: sandbox.project.path, session: "question-session")
        async let hookResponse = Self.send(.processClaudeHook(payload), socketURL: socketURL)

        let prompt = try #require(try await Self.nextQuestion(from: &iterator))
        #expect(prompt.requiresTerminalAnswer)

        try await observer.send(.answerQuestion(sessionID: "question-session", response: QuestionPromptResponse(answer: "Prod")))
        try await observer.send(.resolvePermission(sessionID: "question-session", resolution: .deny(message: nil, interrupt: false)))

        let response = try await hookResponse
        guard case .some(.claudeHookDirective(.permissionRequest(.deny))) = response else {
            Issue.record("Expected the refusal to be the hook's answer, got \(String(describing: response))")
            return
        }
    }

    @Test
    func aQuestionNoAskRuleMatchesIsAnsweredAsBefore() async throws {
        let sandbox = try SettingsSandbox()
        defer { sandbox.cleanUp() }
        try sandbox.writeAskRules(["Bash(launchctl *)"], to: sandbox.locations.userSettings)

        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL, claudeAskRules: sandbox.source)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))
        var iterator = stream.makeAsyncIterator()

        let payload = Self.questionPayload(cwd: sandbox.project.path, session: "plain-question")
        async let hookResponse = Self.send(.processClaudeHook(payload), socketURL: socketURL)

        let prompt = try #require(try await Self.nextQuestion(from: &iterator))
        #expect(!prompt.requiresTerminalAnswer)

        try await observer.send(.answerQuestion(sessionID: "plain-question", response: QuestionPromptResponse(answer: "Prod")))

        let response = try await hookResponse
        guard case .some(.claudeHookDirective(.permissionRequest(.allow))) = response else {
            Issue.record("Expected the answer to be the hook's answer, got \(String(describing: response))")
            return
        }
    }

    @Test
    func aQuestionSavedBeforeTheMarkExistedReadsAsOneTheIslandCanAnswer() throws {
        let old = Data(#"{"id":"11111111-2222-3333-4444-555555555555","title":"Env","options":["A"],"questions":[]}"#.utf8)

        let prompt = try JSONDecoder().decode(QuestionPrompt.self, from: old)
        let marked = QuestionPrompt(title: "Env", options: ["A"], requiresTerminalAnswer: true)
        let roundTrip = try JSONDecoder().decode(QuestionPrompt.self, from: JSONEncoder().encode(marked))

        #expect(!prompt.requiresTerminalAnswer)
        #expect(roundTrip == marked)
    }

    @Test
    func aRequestNoAskRuleMatchesIsApprovedAsBefore() async throws {
        let sandbox = try SettingsSandbox()
        defer { sandbox.cleanUp() }
        try sandbox.writeAskRules(["Bash(launchctl *)"], to: sandbox.locations.userSettings)

        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL, claudeAskRules: sandbox.source)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))
        var iterator = stream.makeAsyncIterator()

        let payload = Self.permissionPayload(command: "swift test", cwd: sandbox.project.path, session: "plain-session")
        async let hookResponse = Self.send(.processClaudeHook(payload), socketURL: socketURL)

        let request = try await Self.nextPermissionRequest(from: &iterator)
        #expect(!request.requiresTerminalApproval)

        try await observer.send(.resolvePermission(sessionID: "plain-session", resolution: .allowOnce()))

        let response = try await hookResponse
        guard case .some(.claudeHookDirective(.permissionRequest(.allow))) = response else {
            Issue.record("Expected an approval to be the hook's answer, got \(String(describing: response))")
            return
        }
    }

    @Test
    func aBridgeWithoutAnAskRuleSourceMarksNothing() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))
        var iterator = stream.makeAsyncIterator()

        let payload = Self.permissionPayload(command: "launchctl version", cwd: "/tmp/nowhere", session: "bare-session")
        async let hookResponse = Self.send(.processClaudeHook(payload), socketURL: socketURL)

        let request = try await Self.nextPermissionRequest(from: &iterator)
        #expect(!request.requiresTerminalApproval)

        try await observer.send(.resolvePermission(sessionID: "bare-session", resolution: .deny(message: nil, interrupt: false)))
        _ = try await hookResponse
    }
}
