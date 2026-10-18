import Foundation
@testable import OpenIslandApp

/// Opens once, and lets everything waiting on it go. A scripted answer waits
/// on one to keep a request in flight while the test looks at the card.
actor TodoLatch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let released = waiters
        waiters = []
        for waiter in released { waiter.resume() }
    }
}

/// What a test scripts for `TestTodoBackend`, and what the backend was
/// asked. The backend is a type with static functions, so the script lives
/// in one shared box behind a lock. A suite that uses it runs one test at a
/// time, and every harness resets it.
final class TestTodoScript: @unchecked Sendable {
    typealias Check = @Sendable (_ token: String) async throws -> NookTodoRemoteCheck
    typealias Load = @Sendable (_ placeID: String?) async throws -> NookTodoRemoteLoad
    typealias Write = @Sendable () async throws -> Void

    static let defaultPlaces = [NookTodoPlaceChoice(id: "w1", name: "Work")]

    private let lock = NSLock()
    private var recorded: [String] = []
    private var checkAnswer: Check = { _ in NookTodoRemoteCheck(places: TestTodoScript.defaultPlaces, accountName: "Sam") }
    private var loadAnswer: Load = { _ in NookTodoRemoteLoad(items: [], placeName: "Work") }
    private var addAnswer: Write = {}
    private var completeAnswer: Write = {}
    private var notesAnswer: Write = {}

    /// One line per call: `check`, `load:<place>`, `add:<title>:<day>:<place>`,
    /// `complete:<id>`, `notes:<id>:<text>`.
    var calls: [String] { lock.withLock { recorded } }

    func count(prefix: String) -> Int {
        calls.filter { $0.hasPrefix(prefix) }.count
    }

    func reset() {
        lock.withLock {
            recorded = []
            checkAnswer = { _ in NookTodoRemoteCheck(places: Self.defaultPlaces, accountName: "Sam") }
            loadAnswer = { _ in NookTodoRemoteLoad(items: [], placeName: "Work") }
            addAnswer = {}
            completeAnswer = {}
            notesAnswer = {}
        }
    }

    func onCheck(_ answer: @escaping Check) { lock.withLock { checkAnswer = answer } }
    func onLoad(_ answer: @escaping Load) { lock.withLock { loadAnswer = answer } }
    func onAdd(_ answer: @escaping Write) { lock.withLock { addAnswer = answer } }
    func onComplete(_ answer: @escaping Write) { lock.withLock { completeAnswer = answer } }
    func onSetNotes(_ answer: @escaping Write) { lock.withLock { notesAnswer = answer } }

    func checked(token: String) async throws -> NookTodoRemoteCheck {
        let answer: Check = lock.withLock {
            recorded.append("check")
            return checkAnswer
        }
        return try await answer(token)
    }

    func loaded(placeID: String?) async throws -> NookTodoRemoteLoad {
        let answer: Load = lock.withLock {
            recorded.append("load:\(placeID ?? "-")")
            return loadAnswer
        }
        return try await answer(placeID)
    }

    func added(title: String, day: String, placeID: String?) async throws {
        let answer: Write = lock.withLock {
            recorded.append("add:\(title):\(day):\(placeID ?? "-")")
            return addAnswer
        }
        try await answer()
    }

    func completed(id: String) async throws {
        let answer: Write = lock.withLock {
            recorded.append("complete:\(id)")
            return completeAnswer
        }
        try await answer()
    }

    func notesSet(id: String, text: String) async throws {
        let answer: Write = lock.withLock {
            recorded.append("notes:\(id):\(text)")
            return notesAnswer
        }
        try await answer()
    }
}

/// A backend that never reaches a network: the test scripts each answer.
/// It stands in for Asana's keys and token file name, takes a place, and can
/// do every write.
enum TestTodoBackend: NookTodoBackend {
    static let script = TestTodoScript()

    static var kind: NookTodoSourceKind { .asana }
    static var needsPlace: Bool { true }
    static var canAdd: Bool { true }
    static var canComplete: Bool { true }
    static var canEditNotes: Bool { true }
    static var canSetDue: Bool { true }

    static func check(_ session: NookTodoRemoteSession) async throws -> NookTodoRemoteCheck {
        try await script.checked(token: session.token)
    }

    static func load(
        _ session: NookTodoRemoteSession, placeID: String?, placeName: String?
    ) async throws -> NookTodoRemoteLoad {
        try await script.loaded(placeID: placeID)
    }

    static func add(
        _ title: String, due: DateComponents?, session: NookTodoRemoteSession, placeID: String?, context: [String: String]
    ) async throws {
        let day = due.map { "\($0.year ?? 0)-\($0.month ?? 0)-\($0.day ?? 0)" } ?? "none"
        try await script.added(title: title, day: day, placeID: placeID)
    }

    static func complete(
        _ id: String, session: NookTodoRemoteSession, placeID: String?, context: [String: String]
    ) async throws {
        try await script.completed(id: id)
    }

    static func setNotes(
        _ notes: String, for id: String, session: NookTodoRemoteSession, placeID: String?, context: [String: String]
    ) async throws {
        try await script.notesSet(id: id, text: notes)
    }
}

enum RemoteTodoFixtures {
    static let token = "remote_test_token_value"

    static func item(_ id: String, _ title: String = "Task", notes: String? = nil) -> NookTodoItem {
        NookTodoItem(id: id, title: title, dueDate: nil, isCompleted: false, listName: "Work", notes: notes)
    }

    static func load(_ items: [NookTodoItem]) -> NookTodoRemoteLoad {
        NookTodoRemoteLoad(items: items, placeName: "Work")
    }
}

/// Everything one remote service needs, with nothing shared between tests
/// but the scripted backend, which each harness clears.
@MainActor
final class RemoteTodoHarness {
    typealias Service = NookRemoteTodoService<TestTodoBackend>

    let tokens: InMemoryTodoTokenStore
    let defaults: UserDefaults = MemoryDefaults()
    let clock = TestClock()
    let service: Service

    var script: TestTodoScript { TestTodoBackend.script }

    init(token: String? = RemoteTodoFixtures.token, placeID: String? = nil, placeName: String? = nil) {
        TestTodoBackend.script.reset()
        tokens = InMemoryTodoTokenStore(token: token)
        if let placeID { defaults.set(placeID, forKey: Service.placeIDKey) }
        if let placeName { defaults.set(placeName, forKey: Service.placeNameKey) }
        let clock = clock
        service = Service(
            defaults: defaults, transport: StubTodoTransport(), tokenStore: tokens, now: { clock.now }
        )
    }

    func activate() async {
        service.setActive(true)
        await service.setupTask?.value
    }

    /// Waits for work that runs off the main actor, up to two seconds.
    func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
