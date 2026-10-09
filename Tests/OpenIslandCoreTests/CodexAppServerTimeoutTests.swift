import Foundation
import Testing
@testable import OpenIslandCore

/// Pins the per-request timeout for `CodexAppServerClient`. Without it,
/// a wedged codex app-server (no disconnect, no reply) would suspend
/// the caller's `Task` and pin a `CheckedThrowingContinuation` plus
/// every byte its closure captured for the lifetime of the process.
struct CodexAppServerTimeoutTests {
    @Test
    func sendRequestThrowsTimeoutWhenAppServerNeverReplies() async {
        let client = CodexAppServerClient()
        client.requestTimeoutSeconds = 0.1

        // Discard pipe stands in for a real codex stdin — writes
        // succeed (empty 64 KB kernel buffer absorbs them) but
        // nothing on the read side ever produces a reply.
        let pipe = Pipe()
        client.stdin = pipe.fileHandleForWriting

        let start = Date()

        await #expect(throws: CodexAppServerError.self) {
            _ = try await client.listLoadedThreads()
        }

        // Should fail fast relative to the configured timeout, not hang on the
        // global test timeout. The bound is deliberately loose: on CI runners
        // this test shares the process with suites that block on ~2 s
        // osascript timeouts, and that scheduling contention was pushing
        // elapsed to 2.0–2.4 s against the previous 2.0 s bound.
        // Raised again from 5 to 15 seconds: with this fork's larger suite a
        // shared CI runner measured 5.09. The point is that it fails long
        // before the global test timeout.
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < max(15.0, client.requestTimeoutSeconds * 20))
    }

    @Test
    func sendRequestSurfacesTimeoutErrorCase() async throws {
        let client = CodexAppServerClient()
        client.requestTimeoutSeconds = 0.1

        let pipe = Pipe()
        client.stdin = pipe.fileHandleForWriting

        do {
            _ = try await client.listLoadedThreads()
            Issue.record("Expected CodexAppServerError.timeout, got nothing")
        } catch let error as CodexAppServerError {
            switch error {
            case .timeout:
                break  // expected
            default:
                Issue.record("Expected .timeout, got \(error)")
            }
        } catch {
            Issue.record("Expected CodexAppServerError, got \(type(of: error))")
        }
    }
}
