import Darwin
import Foundation

/// Runs a program with `Process`. The only place in the widget that starts
/// one, and no test goes through it.
@MainActor
final class NookLinkAudioProcessRunner: NookLinkAudioRunner {
    func run(
        _ launch: NookLinkAudioLaunch,
        onLine: @escaping @MainActor @Sendable (String) -> Void,
        onExit: @escaping @MainActor @Sendable (NookLinkAudioExit) -> Void
    ) throws -> any NookLinkAudioRun {
        let process = Process()
        process.executableURL = launch.executable
        process.arguments = launch.arguments
        process.environment = launch.environment
        process.currentDirectoryURL = launch.currentDirectory
        // The program is never asked a question.
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        let session = NookLinkAudioProcessSession(
            handles: [output.fileHandleForReading, errors.fileHandleForReading],
            onLine: onLine,
            onExit: onExit
        )
        process.terminationHandler = { ended in
            session.processEnded(NookLinkAudioExit(
                status: ended.terminationStatus,
                wasSignalled: ended.terminationReason == .uncaughtSignal
            ))
        }
        try process.run()
        // Output that came before this point waits in the pipe.
        session.startReading()
        return NookLinkAudioProcessRun(process: process)
    }
}

/// A started process, and the way to stop it: an interrupt first, which
/// lets `yt-dlp` stop `ffmpeg` too, then a terminate and a kill for one
/// that does not listen.
@MainActor
private final class NookLinkAudioProcessRun: NookLinkAudioRun {
    private static let terminateAfter: Duration = .seconds(2)
    private static let killAfter: Duration = .seconds(3)
    private static let quitInterruptWait: TimeInterval = 1
    private static let quitTerminateWait: TimeInterval = 0.5

    private let process: Process
    private var isCancelling = false

    init(process: Process) {
        self.process = process
    }

    func cancel() {
        guard !isCancelling, process.isRunning else { return }
        isCancelling = true
        process.interrupt()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.terminateAfter)
            guard let self, self.process.isRunning else { return }
            self.process.terminate()
            try? await Task.sleep(for: Self.killAfter)
            guard self.process.isRunning else { return }
            kill(self.process.processIdentifier, SIGKILL)
        }
    }

    /// For a quit: the same three steps, one after the other, with a short wait
    /// after each, on the main thread. The process is gone, or killed, when
    /// this returns.
    func stopForQuit() {
        guard process.isRunning else { return }
        // A cancel that is already under way has sent its interrupt.
        if !isCancelling {
            isCancelling = true
            process.interrupt()
        }
        if waitForEnd(Self.quitInterruptWait) { return }
        process.terminate()
        if waitForEnd(Self.quitTerminateWait) { return }
        kill(process.processIdentifier, SIGKILL)
        _ = waitForEnd(Self.quitTerminateWait)
    }

    private func waitForEnd(_ limit: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(limit)
        while process.isRunning, Date() < deadline { usleep(10_000) }
        return !process.isRunning
    }
}

/// Collects a process's lines and its end, from the queues the system calls
/// back on, and hands both to the main actor in order. The end is held until
/// both outputs have closed, which keeps the last lines (the finished file's
/// path comes last) from arriving after it. A helper that kept an output open
/// after the process ended costs a short wait and no more.
private final class NookLinkAudioProcessSession: @unchecked Sendable {
    private static let drainLimit: TimeInterval = 1.5

    private let handles: [FileHandle]
    private let onLine: @MainActor @Sendable (String) -> Void
    private let onExit: @MainActor @Sendable (NookLinkAudioExit) -> Void
    private let lock = NSLock()
    private var buffers: [NookLinkAudioLineBuffer]
    private var openOutputs: Int
    private var exit: NookLinkAudioExit?
    private var isDelivered = false

    init(
        handles: [FileHandle],
        onLine: @escaping @MainActor @Sendable (String) -> Void,
        onExit: @escaping @MainActor @Sendable (NookLinkAudioExit) -> Void
    ) {
        self.handles = handles
        self.onLine = onLine
        self.onExit = onExit
        buffers = Array(repeating: NookLinkAudioLineBuffer(), count: handles.count)
        openOutputs = handles.count
    }

    func startReading() {
        for (index, handle) in handles.enumerated() {
            handle.readabilityHandler = { [self] readable in
                let data = readable.availableData
                if data.isEmpty {
                    readable.readabilityHandler = nil
                    outputClosed(index)
                } else {
                    received(data, from: index)
                }
            }
        }
    }

    func processEnded(_ result: NookLinkAudioExit) {
        lock.lock()
        exit = result
        lock.unlock()
        finishIfDone()
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.drainLimit) { [self] in
            deliverNow()
        }
    }

    // MARK: Output

    private func received(_ data: Data, from index: Int) {
        lock.lock()
        let lines = isDelivered ? [] : buffers[index].append(data)
        lock.unlock()
        send(lines)
    }

    private func outputClosed(_ index: Int) {
        lock.lock()
        let last = isDelivered ? nil : buffers[index].flush()
        openOutputs -= 1
        lock.unlock()
        send(last.map { [$0] } ?? [])
        finishIfDone()
    }

    private func send(_ lines: [String]) {
        for line in lines {
            DispatchQueue.main.async { [onLine] in
                MainActor.assumeIsolated { onLine(line) }
            }
        }
    }

    // MARK: End

    private func finishIfDone() {
        lock.lock()
        let isReady = exit != nil && openOutputs == 0
        lock.unlock()
        if isReady { deliverNow() }
    }

    /// Hands the end on, once. Lines still unread are let go of.
    private func deliverNow() {
        lock.lock()
        guard let exit, !isDelivered else {
            lock.unlock()
            return
        }
        isDelivered = true
        let leftover = buffers.indices.compactMap { buffers[$0].flush() }
        lock.unlock()
        for handle in handles { handle.readabilityHandler = nil }
        send(leftover)
        DispatchQueue.main.async { [onExit] in
            MainActor.assumeIsolated { onExit(exit) }
        }
    }
}
