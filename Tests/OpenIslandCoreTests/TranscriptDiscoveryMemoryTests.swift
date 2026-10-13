import Foundation
import Testing
@testable import OpenIslandCore

/// The launch parses every recent transcript in one job. Whatever that job
/// leaves for the autorelease pool stays until the job ends, which on a Mac
/// with a day of long sessions reached 746 MB (D54). These tests parse a few
/// made-up transcripts the way the launch does and watch the process
/// footprint while they are read.
/// The limit is the size of the files: the bug held about twice that,
/// the fix holds about one chunk, and the room between is for whatever
/// the other suites allocate meanwhile.
@Suite(.serialized)
struct TranscriptDiscoveryMemoryTests {
    /// Three files of about twelve megabytes each, in lines shaped like the
    /// real ones: a user line, an assistant line with a tool call, and a
    /// user line carrying the tool's result.
    private static let fileCount = 3
    private static let linesPerFile = 600
    private static let resultSize = 20_000

    @Test(.timeLimit(.minutes(2)))
    func parsingClaudeTranscriptsHoldsAboutOneChunkAtATime() throws {
        let root = try Self.makeRoot(name: "claude")
        defer { try? FileManager.default.removeItem(at: root) }
        var bytes = 0
        for index in 0..<Self.fileCount {
            bytes += try Self.writeClaudeTranscript(in: root, index: index)
        }
        // A fresh discovery for every reading: a retry must parse the files
        // again, never answer from a cache.
        let growth = Self.memoryGrowth(limit: bytes) { ClaudeTranscriptDiscovery(rootURL: root).discoverRecentSessions().count }

        #expect(growth.result == Self.fileCount)
        #expect(
            growth.bytes < bytes,
            "parsing \(bytes / 1_048_576) MB of transcripts held \(growth.bytes / 1_048_576) MB at once"
        )
    }

    @Test(.timeLimit(.minutes(2)))
    func parsingCodexRolloutsHoldsAboutOneChunkAtATime() throws {
        let root = try Self.makeRoot(name: "codex")
        defer { try? FileManager.default.removeItem(at: root) }
        var bytes = 0
        for index in 0..<Self.fileCount {
            bytes += try Self.writeCodexRollout(in: root, index: index)
        }
        // The Codex discovery keeps parse state per file, which is why each
        // reading gets a discovery of its own.
        let growth = Self.memoryGrowth(limit: bytes) { CodexRolloutDiscovery(rootURL: root).discoverRecentSessions().count }

        #expect(growth.result == Self.fileCount)
        #expect(
            growth.bytes < bytes,
            "parsing \(bytes / 1_048_576) MB of rollouts held \(growth.bytes / 1_048_576) MB at once"
        )
    }

    // MARK: - Fixtures

    private static func makeRoot(name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-memory-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func writeClaudeTranscript(in root: URL, index: Int) throws -> Int {
        let sessionID = UUID().uuidString
        let folder = root.appendingPathComponent("-Users-someone-project-\(index)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let result = String(repeating: "x", count: resultSize)
        var lines: [String] = []
        lines.reserveCapacity(linesPerFile * 3)
        for line in 0..<linesPerFile {
            let toolID = "toolu_\(index)_\(line)"
            lines.append(
                #"{"type":"user","sessionId":"\#(sessionID)","cwd":"/Users/someone/project-\#(index)","timestamp":"2026-10-11T10:00:00Z","message":{"role":"user","content":[{"type":"text","text":"prompt \#(line)"}]}}"#
            )
            lines.append(
                #"{"type":"assistant","sessionId":"\#(sessionID)","timestamp":"2026-10-11T10:00:01Z","message":{"role":"assistant","model":"claude","content":[{"type":"text","text":"working on \#(line)"},{"type":"tool_use","id":"\#(toolID)","name":"Read","input":{"file_path":"/tmp/file-\#(line)"}}]}}"#
            )
            lines.append(
                #"{"type":"user","sessionId":"\#(sessionID)","timestamp":"2026-10-11T10:00:02Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"\#(toolID)","content":"\#(result)"}]}}"#
            )
        }
        let text = lines.joined(separator: "\n") + "\n"
        let url = folder.appendingPathComponent("\(sessionID).jsonl")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return text.utf8.count
    }

    private static func writeCodexRollout(in root: URL, index: Int) throws -> Int {
        let sessionID = UUID().uuidString
        let folder = root.appendingPathComponent("2026/10/11", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let result = String(repeating: "x", count: resultSize)
        var lines: [String] = [
            #"{"timestamp":"2026-10-11T10:00:00Z","type":"session_meta","payload":{"id":"\#(sessionID)","cwd":"/Users/someone/project-\#(index)","originator":"codex_cli_rs"}}"#
        ]
        lines.reserveCapacity(linesPerFile * 3 + 1)
        for line in 0..<linesPerFile {
            lines.append(
                #"{"timestamp":"2026-10-11T10:00:01Z","type":"event_msg","payload":{"type":"user_message","message":"prompt \#(line)"}}"#
            )
            lines.append(
                #"{"timestamp":"2026-10-11T10:00:02Z","type":"response_item","payload":{"type":"function_call","name":"shell","arguments":"{\"command\":[\"cat\",\"file-\#(line)\"]}","call_id":"call_\#(line)"}}"#
            )
            lines.append(
                #"{"timestamp":"2026-10-11T10:00:03Z","type":"response_item","payload":{"type":"function_call_output","call_id":"call_\#(line)","output":"\#(result)"}}"#
            )
        }
        let text = lines.joined(separator: "\n") + "\n"
        let url = folder.appendingPathComponent("rollout-2026-10-11T10-00-00-\(sessionID).jsonl")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return text.utf8.count
    }

    // MARK: - The memory probe

    /// Runs `work` on a thread of its own, the way the launch runs the
    /// discovery in one job, and reports the most that the bytes malloc holds
    /// rose above the starting point while the work ran. Memory another test
    /// allocates at the same time can only add to the reading, which is why
    /// the first reading under the limit is believed and a high one is read
    /// again, up to four times.
    private static func memoryGrowth<T: Sendable>(limit: Int, _ work: @escaping @Sendable () -> T) -> (bytes: Int, result: T) {
        var lowest = singleMemoryGrowth(work)
        var readings = 1
        while lowest.bytes >= limit, readings < 4 {
            let reading = singleMemoryGrowth(work)
            if reading.bytes < lowest.bytes { lowest = reading }
            readings += 1
        }
        return lowest
    }

    private static func singleMemoryGrowth<T: Sendable>(_ work: @escaping @Sendable () -> T) -> (bytes: Int, result: T) {
        let box = ResultBox<T>()
        let start = bytesInUse()
        let worker = Thread {
            box.finish(with: work())
        }
        worker.stackSize = 8 * 1_048_576
        worker.start()
        // The thread's own pool drains as it ends, which is why the wait is
        // for the thread and not for the work: a reading that starts before
        // the drain would be low for the wrong reason.
        while !worker.isFinished {
            box.record(bytesInUse())
            usleep(1_000)
        }
        return (max(0, box.peak - start), box.result!)
    }

    /// The bytes every malloc zone has handed out and not had back. An
    /// object waiting in an autorelease pool still counts, which is the
    /// whole point.
    private static func bytesInUse() -> Int {
        var statistics = malloc_statistics_t()
        malloc_zone_statistics(nil, &statistics)
        return Int(statistics.size_in_use)
    }

    private final class ResultBox<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var highest = 0
        private var value: T?

        var peak: Int { lock.withLock { highest } }
        var result: T? { lock.withLock { value } }

        func record(_ bytes: Int) {
            lock.withLock { highest = max(highest, bytes) }
        }

        func finish(with value: T) {
            lock.withLock { self.value = value }
        }
    }
}
