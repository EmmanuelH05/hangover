import Foundation
import Testing
@testable import OpenIslandCore

/// Pins `SessionActivityUpdated.finishedTool`: the app's "what it did" card
/// counts a tool only from the update that carries it, which is why it has
/// to sit on a tool a hook saw end, whole, and on nothing else.
struct ToolFinishMarkerTests {
    private enum TestError: Error {
        case streamEnded
    }

    /// Longer than the 110 characters a hook preview is cut to.
    private static let deepPath = "/Users/someone/Library/Mobile Documents/iCloud~md~obsidian/Documents/Study-Notes/UCLA/F2026/Ling 132/weekly-notes/week-02.md"

    private static func hook(
        _ event: ClaudeHookEventName,
        session: String,
        tool: String? = nil,
        input: ClaudeHookJSONValue? = nil,
        useID: String? = nil
    ) -> ClaudeHookPayload {
        ClaudeHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: event,
            sessionID: session,
            toolName: tool,
            toolInput: input,
            toolUseID: useID
        )
    }

    @Test
    func onlyAToolTheHooksSawEndIsMarkedAndItsInputIsWhole() async throws {
        #expect(Self.deepPath.count > 110)

        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let sessionID = "claude-tool-finish"
        let edit = ClaudeHookJSONValue.object(["file_path": .string(Self.deepPath), "old_string": .string("a")])
        let tests = ClaudeHookJSONValue.object(["command": .string("swift test")])
        let status = ClaudeHookJSONValue.object(["command": .string("git status")])
        let hooks: [ClaudeHookPayload] = [
            ClaudeHookPayload(cwd: "/tmp/worktree", hookEventName: .userPromptSubmit, sessionID: sessionID, prompt: "fix the bug"),
            Self.hook(.preToolUse, session: sessionID, tool: "Edit", input: edit, useID: "use-1"),
            Self.hook(.postToolUse, session: sessionID, tool: "Edit", input: edit, useID: "use-1"),
            // A tool that fails gets PostToolUseFailure and no PostToolUse.
            Self.hook(.preToolUse, session: sessionID, tool: "Bash", input: tests, useID: "use-2"),
            Self.hook(.postToolUseFailure, session: sessionID, tool: "Bash", input: tests, useID: "use-2"),
            Self.hook(.preToolUse, session: sessionID, tool: "Bash", input: status, useID: "use-3"),
            Self.hook(.postToolUse, session: sessionID, tool: "Bash", input: status, useID: "use-3"),
            ClaudeHookPayload(cwd: "/tmp/worktree", hookEventName: .stop, sessionID: sessionID, lastAssistantMessage: "Fixed."),
        ]
        for hook in hooks {
            _ = try BridgeCommandClient(socketURL: socketURL).send(.processClaudeHook(hook))
        }

        var iterator = stream.makeAsyncIterator()
        var finishes: [AgentToolFinish?] = []
        var sawFinish = false
        while !sawFinish {
            guard let event = try await iterator.next() else { throw TestError.streamEnded }
            switch event {
            case let .activityUpdated(payload):
                finishes.append(payload.finishedTool)
            case .sessionCompleted:
                sawFinish = true
            default:
                break
            }
        }

        // The prompt, then for each tool its start and its end.
        #expect(finishes == [
            nil,
            nil, AgentToolFinish(toolName: "Edit", filePath: Self.deepPath),
            nil, nil,
            nil, AgentToolFinish(toolName: "Bash", command: "git status"),
        ])
    }

    @Test
    func aClaudeToolEndCarriesTheFileOrTheCommandFromItsOwnInput() {
        let notebook = Self.hook(.postToolUse, session: "s", tool: "NotebookEdit", input: .object(["notebook_path": .string("/repo/n.ipynb")]))
        #expect(notebook.finishedTool == AgentToolFinish(toolName: "NotebookEdit", filePath: "/repo/n.ipynb"))

        let background = Self.hook(.postToolUse, session: "s", tool: "Bash", input: .object([
            "command": .string("swift test"),
            "run_in_background": .boolean(true),
        ]))
        #expect(background.finishedTool == AgentToolFinish(toolName: "Bash", command: "swift test", ranInBackground: true))

        // No input to read: the tool is named and nothing more is said.
        #expect(Self.hook(.postToolUse, session: "s", tool: "Read").finishedTool == AgentToolFinish(toolName: "Read"))
        #expect(Self.hook(.postToolUse, session: "s", tool: "  ").finishedTool == nil)
        #expect(Self.hook(.postToolUse, session: "s").finishedTool == nil)
    }

    @Test
    func aCodexToolEndCarriesItsWholeCommand() {
        let long = "swift test --filter " + String(repeating: "VeryLongSuiteName", count: 12)
        func payload(_ command: String?) -> CodexHookPayload {
            CodexHookPayload(
                cwd: "/tmp/worktree",
                hookEventName: .postToolUse,
                model: "gpt-5",
                permissionMode: .default,
                sessionID: "codex",
                transcriptPath: nil,
                toolName: "Bash",
                toolInput: command.map { CodexHookToolInput(command: $0) }
            )
        }
        #expect(long.count > 110)
        #expect(payload(long).finishedTool == AgentToolFinish(toolName: "Bash", command: long))
        #expect(payload(nil).finishedTool == nil)
    }

    @Test
    func theMarkerTravelsOverTheBridgeAndOldUpdatesReadWithoutIt() throws {
        let marked = AgentEvent.activityUpdated(SessionActivityUpdated(
            sessionID: "s",
            summary: "Edit finished.",
            phase: .running,
            timestamp: Date(timeIntervalSince1970: 1_000),
            finishedTool: AgentToolFinish(toolName: "Edit", filePath: "/repo/a.swift")
        ))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(AgentEvent.self, from: encoder.encode(marked)) == marked)

        // An update written before the marker existed.
        let old = Data("""
        {"type":"activityUpdated","activityUpdated":{"sessionID":"s","summary":"Working","phase":"running","timestamp":"2026-01-01T00:00:00Z"}}
        """.utf8)
        guard case let .activityUpdated(payload) = try decoder.decode(AgentEvent.self, from: old) else {
            Issue.record("Expected an activity update")
            return
        }
        #expect(payload.finishedTool == nil)
    }
}
