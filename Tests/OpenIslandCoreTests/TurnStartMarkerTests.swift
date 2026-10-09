import Foundation
import Testing
@testable import OpenIslandCore

/// Pins `SessionActivityUpdated.startsTurn`: the app's "what it did" card
/// counts a session's work from the update that carries it, which is why it
/// has to sit on the prompt and on nothing else.
struct TurnStartMarkerTests {
    private enum TestError: Error {
        case streamEnded
    }

    @Test
    func aClaudePromptStartsATurnAndItsToolsDoNot() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let sessionID = "claude-turn-start"
        let hooks: [ClaudeHookPayload] = [
            ClaudeHookPayload(
                cwd: "/tmp/worktree",
                hookEventName: .userPromptSubmit,
                sessionID: sessionID,
                prompt: "fix the bug"
            ),
            ClaudeHookPayload(
                cwd: "/tmp/worktree",
                hookEventName: .preToolUse,
                sessionID: sessionID,
                toolName: "Bash",
                toolInput: .object(["command": .string("swift test")]),
                toolUseID: "tool-use-1"
            ),
            ClaudeHookPayload(
                cwd: "/tmp/worktree",
                hookEventName: .postToolUse,
                sessionID: sessionID,
                toolName: "Bash",
                toolInput: .object(["command": .string("swift test")]),
                toolUseID: "tool-use-1"
            ),
            ClaudeHookPayload(
                cwd: "/tmp/worktree",
                hookEventName: .stop,
                sessionID: sessionID,
                lastAssistantMessage: "Fixed."
            ),
        ]
        for hook in hooks {
            _ = try BridgeCommandClient(socketURL: socketURL).send(.processClaudeHook(hook))
        }

        var iterator = stream.makeAsyncIterator()
        var markers: [Bool?] = []
        var sawFinish = false
        while !sawFinish {
            guard let event = try await iterator.next() else { throw TestError.streamEnded }
            switch event {
            case let .activityUpdated(payload):
                markers.append(payload.startsTurn)
            case .sessionCompleted:
                sawFinish = true
            default:
                break
            }
        }

        // The prompt, then the tool starting and the tool finishing.
        #expect(markers == [true, nil, nil])
    }

    @Test
    func theMarkerTravelsOverTheBridgeAndOldUpdatesReadWithoutIt() throws {
        let marked = AgentEvent.activityUpdated(SessionActivityUpdated(
            sessionID: "s",
            summary: "Prompt: fix the bug",
            phase: .running,
            timestamp: Date(timeIntervalSince1970: 1_000),
            startsTurn: true
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
        #expect(payload.startsTurn == nil)
    }
}
