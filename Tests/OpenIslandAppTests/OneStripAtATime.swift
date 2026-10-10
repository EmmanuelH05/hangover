import Testing

/// Strip drawing asks AppKit for a font by name off the main thread
/// (`NookPhotoStripTheme`), and two of those at once once killed the whole
/// test process with a recursive `os_unfair_lock` in `NSFont`. `.serialized`
/// orders the tests of one suite. This trait orders the suites that draw
/// strips against each other: at most one of their tests runs at a time.
struct OneStripAtATimeTrait: TestTrait, SuiteTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        guard testCase != nil else {
            try await function()
            return
        }
        await StripGate.shared.acquire()
        do {
            try await function()
        } catch {
            await StripGate.shared.release()
            throw error
        }
        await StripGate.shared.release()
    }
}

extension Trait where Self == OneStripAtATimeTrait {
    static var oneStripAtATime: Self { OneStripAtATimeTrait() }
}

private actor StripGate {
    static let shared = StripGate()

    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isHeld else {
            isHeld = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            isHeld = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
