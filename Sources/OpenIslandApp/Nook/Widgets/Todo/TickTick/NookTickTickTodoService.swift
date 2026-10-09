import Foundation
import Observation

/// TickTick as a task source for the todo card. Reads the open tasks of one
/// list, marks them done, adds new ones and edits their notes.
///
/// Idle until `setActive(true)`: no Keychain, disk or network work happens
/// while another source is selected.
@MainActor
@Observable
final class NookTickTickTodoService {
    enum Keys {
        /// Absent means the inbox.
        static let listID = "nook.todo.ticktick.listID"
        static let listName = "nook.todo.ticktick.listName"
    }

    /// Most tasks loaded for the card.
    static let taskLimit = 100
    /// Keeps a pasted page of text out of a task title. TickTick documents
    /// no limit of its own.
    static let maxTitleLength = 500
    /// Both tick a little slower than the gate spacing they must clear
    /// (60s open, 300s closed); an exact match would lose every other tick.
    static let foregroundRefreshInterval: Duration = .seconds(62)
    static let backgroundPollInterval: Duration = .seconds(305)

    // MARK: Observable state

    private(set) var isActive = false
    /// The card's rows, each with the list it lives in.
    var rows: [TickTickRow] = []
    var state: TickTickTodoState = .inactive
    var isShowingCachedItems = false
    var actionError: TickTickTodoActionError?
    /// The selected list is shared with the user as read or comment only.
    var isListReadOnly = false
    /// False after TickTick answered 403 to a write.
    var canWrite = true
    var hasToken = false
    /// TickTick answered 401 for the stored token. Stays set until a new
    /// token connects, which keeps the token field on screen.
    var tokenRejected = false
    /// Disconnect could not take the token out of the Keychain. It is
    /// still stored, and the session is as it was.
    var tokenRemovalFailed = false
    var lists: [TickTickListChoice] = []
    var hasLoadedLists = false
    var isLoadingLists = false
    /// The last try to load the lists failed. The picker shows what it had.
    var listsLoadFailed = false
    var selectedListID = TickTickClient.inboxID
    /// The selected list's name. Nil for the inbox, which is named in the
    /// user's language.
    var listName: String?
    var lastRefreshed: Date?
    /// The offline copy could not be written or removed.
    var cacheFailed = false

    var items: [NookTodoItem] { rows.map(\.item) }

    // MARK: Internals

    @ObservationIgnored var token: String?
    @ObservationIgnored var gate = NookTodoRefreshGate()
    /// The inbox's real ID, learned from a load. New inbox tasks name it.
    @ObservationIgnored var inboxProjectID: String?
    /// Rows removed optimistically whose request has not finished.
    @ObservationIgnored var pendingCompletions: Set<String> = []
    /// Notes written locally whose update has not finished, by task ID. An
    /// empty text means cleared. A load never overwrites these.
    @ObservationIgnored var pendingNotes: [String: String] = [:]
    /// Tasks with a notes update on the wire, and the newest text waiting
    /// behind each one.
    @ObservationIgnored var notesInFlight: Set<String> = []
    @ObservationIgnored var queuedNotes: [String: String] = [:]
    /// Called when a notes write ends: task ID, the text, and whether
    /// TickTick took it. The hub keeps text that did not save.
    @ObservationIgnored var onNotesWriteFinished: ((_ id: String, _ text: String, _ saved: Bool) -> Void)?
    /// Bumped whenever in-flight work must be ignored: source switch,
    /// connect, disconnect, another list.
    @ObservationIgnored var epoch = 0
    @ObservationIgnored var refreshSerial = 0
    @ObservationIgnored var refreshTask: Task<Void, Never>?
    @ObservationIgnored var setupTask: Task<Void, Never>?
    @ObservationIgnored var pollTask: Task<Void, Never>?
    @ObservationIgnored var actionTasks: [UUID: Task<Void, Never>] = [:]

    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored let tokenStore: any NookTodoTokenStoring
    @ObservationIgnored let cache: TickTickTodoCache
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored private var transport: (any NookTodoTransport)?

    init(
        defaults: UserDefaults = .standard,
        transport: (any NookTodoTransport)? = nil,
        tokenStore: any NookTodoTokenStoring = NookTodoKeychain.tickTick,
        cache: TickTickTodoCache = TickTickTodoCache(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.transport = transport
        self.tokenStore = tokenStore
        self.cache = cache
        self.now = now
    }

    // MARK: Activation

    /// Turns the source on or off. Off cancels every request and forgets
    /// the token held in memory.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            epoch += 1
            let startEpoch = epoch
            loadPreferences()
            state = .connecting
            setupTask = Task { [weak self] in await self?.finishActivation(epoch: startEpoch) }
            startBackgroundPoll()
        } else {
            deactivate()
        }
    }

    /// Reads the token and the offline copy, then refreshes.
    private func finishActivation(epoch startEpoch: Int) async {
        guard isActive, epoch == startEpoch else { return }
        let store = tokenStore
        let tokenResult = await Task.detached { Result { try store.read() } }.value
        let snapshot = await cache.load()
        guard isActive, epoch == startEpoch else { return }

        switch tokenResult {
        case .failure:
            state = .keychainUnavailable
            return
        case .success(nil):
            state = .noToken
            return
        case .success(let stored?):
            token = stored
            hasToken = true
        }
        if let snapshot, snapshot.listID == selectedListID {
            rows = snapshot.rows
            isShowingCachedItems = !snapshot.rows.isEmpty
        }
        await performRefresh()
    }

    private func deactivate() {
        cancelWork()
        pollTask?.cancel()
        pollTask = nil
        token = nil
        hasToken = false
        tokenRejected = false
        resetSession()
        lists = []
        hasLoadedLists = false
        listsLoadFailed = false
        tokenRemovalFailed = false
        state = .inactive
    }

    /// Cancels in-flight requests and makes their late results void.
    func cancelWork() {
        epoch += 1
        refreshSerial += 1
        setupTask?.cancel()
        setupTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        actionTasks.values.forEach { $0.cancel() }
        actionTasks = [:]
        isLoadingLists = false
    }

    /// Clears everything derived from one token and list.
    func resetSession() {
        rows = []
        isShowingCachedItems = false
        actionError = nil
        isListReadOnly = false
        canWrite = true
        inboxProjectID = nil
        pendingCompletions = []
        pendingNotes = [:]
        notesInFlight = []
        queuedNotes = [:]
        lastRefreshed = nil
        gate.reset()
    }

    private func startBackgroundPoll() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Self.backgroundPollInterval)
                } catch {
                    return
                }
                guard let self, self.isActive else { return }
                self.refresh(.background)
            }
        }
    }

    // MARK: Refresh

    /// Asks for a refresh. The gate drops requests that come too soon after
    /// the last one, during backoff, or while rate limited.
    func refresh(_ trigger: NookTodoRefreshTrigger) {
        guard isActive, hasToken else { return }
        // A rejected token stays rejected until the user pastes a new one.
        if tokenRejected, trigger != .manual { return }
        guard gate.shouldRun(trigger, now: now()) else { return }
        refreshTask?.cancel()
        refreshSerial += 1
        let serial = refreshSerial
        refreshTask = Task { [weak self] in
            await self?.runRefresh(serial: serial)
        }
    }

    /// Refreshes now and waits for the result. Skips the gate.
    func performRefresh() async {
        refreshSerial += 1
        await runRefresh(serial: refreshSerial)
    }

    /// True while a rate limit's wait is open. Nothing is sent.
    var isRateLimited: Bool { gate.isRateLimited(now: now()) }

    private func runRefresh(serial: Int) async {
        guard isActive, let client = makeClient() else { return }
        guard !isRateLimited else {
            isShowingCachedItems = !rows.isEmpty
            state = .rateLimited
            return
        }
        gate.recordAttempt(now: now())
        let result = await TickTickTodoLoader.load(
            client: client, listID: selectedListID, listName: displayName, limit: Self.taskLimit
        )
        // A newer refresh, a source switch or a disconnect makes this one void.
        guard isActive, serial == refreshSerial else { return }
        switch result {
        case .success(let load): apply(load)
        case .failure(let error): applyFailure(error)
        }
    }

    private func apply(_ load: TickTickTodoLoad) {
        if let name = load.listName, name != listName {
            listName = name
            defaults.set(name, forKey: Keys.listName)
        }
        if let inbox = load.inboxProjectID { inboxProjectID = inbox }
        // The token works: a rejection seen earlier no longer stands.
        tokenRejected = false
        // The list of lists says who may write, and the list's own answer
        // may say it too.
        isListReadOnly = load.isReadOnly || (lists.first { $0.id == selectedListID }?.isReadOnly ?? false)
        rows = load.rows.filter { !pendingCompletions.contains($0.item.id) }.map { row in
            guard let pending = pendingNotes[row.item.id] else { return row }
            var kept = row
            kept.item.notes = pending.isEmpty ? nil : pending
            return kept
        }
        isShowingCachedItems = false
        // A note that did not save stays reported until the next write.
        if actionError?.concernsNotes != true { actionError = nil }
        lastRefreshed = now()
        gate.recordSuccess()
        state = .ready
        saveCache()
    }

    /// Turns a failed request into the state the card and settings show.
    func applyFailure(_ error: TickTickAPIError) {
        switch error {
        case .cancelled:
            return
        case .unauthorized:
            dropRows()
            tokenRejected = hasToken
            state = .invalidToken
        case .forbidden:
            dropRows()
            state = .forbidden
        case .notFound:
            dropRows()
            state = .listUnavailable
        case .badRequest:
            dropRows()
            state = .rejected
        case .rateLimited(let retryAfter):
            gate.recordRateLimit(retryAfter: retryAfter, now: now())
            isShowingCachedItems = !rows.isEmpty
            state = .rateLimited
        case .offline:
            gate.recordFailure(now: now())
            isShowingCachedItems = !rows.isEmpty
            state = .offline
        case .server, .invalidResponse:
            gate.recordFailure(now: now())
            isShowingCachedItems = !rows.isEmpty
            state = .serverError
        }
    }

    private func dropRows() {
        rows = []
        isShowingCachedItems = false
    }

    // MARK: Helpers shared with the actions extension

    func makeClient() -> TickTickClient? {
        guard let token else { return nil }
        return TickTickClient(token: token, transport: resolvedTransport())
    }

    func resolvedTransport() -> any NookTodoTransport {
        if let transport { return transport }
        let created = NookTodoURLSessionTransport()
        transport = created
        return created
    }

    /// Writes the current rows to disk in the background.
    func saveCache() {
        let snapshot = TickTickTodoSnapshot(
            listID: selectedListID, listName: displayName, savedAt: now(), rows: rows
        )
        Task { [weak self, cache] in
            do {
                try await cache.save(snapshot)
                self?.cacheFailed = false
            } catch {
                self?.cacheFailed = true
            }
        }
    }

    func clearCache() async {
        do {
            try await cache.clear()
            cacheFailed = false
        } catch {
            cacheFailed = true
        }
    }

    private func loadPreferences() {
        selectedListID = defaults.string(forKey: Keys.listID).flatMap { $0.isEmpty ? nil : $0 } ?? TickTickClient.inboxID
        listName = defaults.string(forKey: Keys.listName)
    }

    func persistSelection() {
        if selectedListID == TickTickClient.inboxID {
            defaults.removeObject(forKey: Keys.listID)
        } else {
            defaults.set(selectedListID, forKey: Keys.listID)
        }
        if let listName {
            defaults.set(listName, forKey: Keys.listName)
        } else {
            defaults.removeObject(forKey: Keys.listName)
        }
    }
}
