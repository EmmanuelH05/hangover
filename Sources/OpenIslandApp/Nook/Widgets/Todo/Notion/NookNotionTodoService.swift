import Foundation
import Observation

/// Notion as a task source for the todo card. Reads open tasks from one
/// database the user picked, marks them done and adds new ones.
///
/// Idle until `setActive(true)`: no Keychain, disk or network work happens
/// while Reminders is the selected source.
@MainActor
@Observable
final class NookNotionTodoService {
    enum Keys {
        static let dataSourceID = "nook.todo.notion.dataSourceID"
        static let databaseTitle = "nook.todo.notion.databaseTitle"
        static let mapping = "nook.todo.notion.mapping"
        static let account = "nook.todo.notion.account"
        /// Set once the notes column was looked for, which lets a setup
        /// saved before notes existed pick one up without overriding "None".
        static let notesColumnChecked = "nook.todo.notion.notesColumnChecked"
    }

    /// Most tasks loaded for the card.
    static let taskLimit = 100
    /// Most databases listed in the picker.
    static let databaseLimit = 200
    /// Notion's limit for one rich text item.
    static let maxTitleLength = 2000
    static let mappingDebounce: Duration = .milliseconds(400)
    /// Both tick a little slower than the gate spacing they must clear
    /// (60s open, 300s closed); an exact match would lose every other tick.
    static let foregroundRefreshInterval: Duration = .seconds(62)
    static let backgroundPollInterval: Duration = .seconds(305)

    // MARK: Observable state

    private(set) var isActive = false
    var items: [NookTodoItem] = []
    var state: NotionTodoState = .inactive
    var isShowingCachedItems = false
    var actionError: NotionTodoActionError?
    /// False after Notion answered 403 to creating a page.
    var canInsert = true
    /// False after Notion answered 403 to updating a page.
    var canUpdate = true
    var hasToken = false
    /// Notion answered 401 for the stored token. Stays set until a new
    /// token connects, which keeps the token field on screen.
    var tokenRejected = false
    var accountName: String?
    var databases: [NotionDatabaseChoice] = []
    var hasLoadedDatabases = false
    var isLoadingDatabases = false
    var selectedDatabaseID: String?
    var databaseTitle: String?
    var schema: NotionDataSource?
    var mapping = NotionTodoMapping()
    /// The mapping checked against the schema by the last good load.
    var resolved: NotionResolvedMapping?
    var lastRefreshed: Date?
    /// The offline copy could not be written or removed.
    var cacheFailed = false

    // MARK: Internals

    @ObservationIgnored var token: String?
    @ObservationIgnored var gate = NotionRefreshGate()
    /// Rows removed optimistically whose update has not finished.
    @ObservationIgnored var pendingCompletions: Set<String> = []
    /// Notes written locally whose update has not finished, by task ID. An
    /// empty text means cleared. A load never overwrites these.
    @ObservationIgnored var pendingNotes: [String: String] = [:]
    /// Tasks with a notes update on the wire, and the newest text waiting
    /// behind each one.
    @ObservationIgnored var notesInFlight: Set<String> = []
    @ObservationIgnored var queuedNotes: [String: String] = [:]
    /// Called when a notes write ends: task ID, the text, and whether Notion
    /// took it. The hub keeps text that did not save.
    @ObservationIgnored var onNotesWriteFinished: ((_ id: String, _ text: String, _ saved: Bool) -> Void)?
    /// Bumped whenever in-flight work must be ignored: source switch,
    /// connect, disconnect.
    @ObservationIgnored var epoch = 0
    @ObservationIgnored var refreshSerial = 0
    @ObservationIgnored var refreshTask: Task<Void, Never>?
    @ObservationIgnored var setupTask: Task<Void, Never>?
    @ObservationIgnored var pollTask: Task<Void, Never>?
    @ObservationIgnored var actionTasks: [UUID: Task<Void, Never>] = [:]

    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored let tokenStore: any NotionTokenStoring
    @ObservationIgnored let cache: NotionTodoCache
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored private var transport: (any NotionTransport)?

    init(
        defaults: UserDefaults = .standard,
        transport: (any NotionTransport)? = nil,
        tokenStore: any NotionTokenStoring = NotionKeychain(),
        cache: NotionTodoCache = NotionTodoCache(),
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
        guard let selectedDatabaseID else {
            state = .noDatabase
            return
        }
        if let snapshot, snapshot.dataSourceID == selectedDatabaseID {
            items = snapshot.items
            isShowingCachedItems = !snapshot.items.isEmpty
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
        databases = []
        hasLoadedDatabases = false
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
        isLoadingDatabases = false
    }

    /// Clears everything derived from one token and database.
    func resetSession() {
        items = []
        isShowingCachedItems = false
        actionError = nil
        canInsert = true
        canUpdate = true
        schema = nil
        resolved = nil
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
    func refresh(_ trigger: NotionRefreshTrigger, debounce: Duration? = nil) {
        guard isActive, hasToken, selectedDatabaseID != nil else { return }
        // A rejected token stays rejected until the user pastes a new one.
        if tokenRejected, trigger != .manual { return }
        guard gate.shouldRun(trigger, now: now()) else { return }
        refreshTask?.cancel()
        refreshSerial += 1
        let serial = refreshSerial
        refreshTask = Task { [weak self] in
            if let debounce {
                do {
                    try await Task.sleep(for: debounce)
                } catch {
                    return
                }
            }
            await self?.runRefresh(serial: serial)
        }
    }

    /// Refreshes now and waits for the result. Skips the gate.
    func performRefresh() async {
        refreshSerial += 1
        await runRefresh(serial: refreshSerial)
    }

    /// True while Notion's Retry-After window is open. Nothing is sent.
    var isRateLimited: Bool { gate.isRateLimited(now: now()) }

    private func runRefresh(serial: Int, mayDetect: Bool = true) async {
        guard isActive, let client = makeClient(), let dataSourceID = selectedDatabaseID else { return }
        guard !isRateLimited else {
            isShowingCachedItems = !items.isEmpty
            state = .rateLimited
            return
        }
        gate.recordAttempt(now: now())
        let result = await NotionTodoLoader.load(
            client: client, dataSourceID: dataSourceID, mapping: mapping, limit: Self.taskLimit
        )
        // A newer refresh, a source switch or a disconnect makes this one void.
        guard isActive, serial == refreshSerial else { return }
        switch result {
        case .success(let load):
            if mayDetect, adoptNotesColumnOnce(from: load.schema) {
                await runRefresh(serial: serial, mayDetect: false)
                return
            }
            apply(load)
        case .failure(.mapping(let issue, let latestSchema)):
            // Picking the database could not read its schema (offline, for
            // one), which left the mapping empty. Guess it now, once.
            let detected = NotionTodoMapper.detect(latestSchema)
            if mayDetect, issue == .doneNotChosen, mapping == NotionTodoMapping(), detected != mapping {
                schema = latestSchema
                mapping = detected
                persistSelection()
                await runRefresh(serial: serial, mayDetect: false)
                return
            }
            schema = latestSchema
            resolved = nil
            items = []
            isShowingCachedItems = false
            gate.recordSuccess()
            state = .needsAttention(issue)
        case .failure(.api(let error)):
            applyFailure(error)
        }
    }

    /// A setup saved before notes existed has no notes column. Guess one
    /// the first time the schema is seen. Returns true when the mapping changed.
    private func adoptNotesColumnOnce(from schema: NotionDataSource) -> Bool {
        guard !defaults.bool(forKey: Keys.notesColumnChecked) else { return false }
        defaults.set(true, forKey: Keys.notesColumnChecked)
        // Nobody is looking at the pickers here: only a column whose name
        // says notes is taken, never just the first text column.
        guard mapping.notesPropertyID == nil,
              let detected = NotionTodoMapper.detectNotesProperty(schema, namedOnly: true) else { return false }
        mapping.notesPropertyID = detected.id
        persistSelection()
        return true
    }

    private func apply(_ load: NotionTodoLoad) {
        schema = load.schema
        resolved = load.resolved
        if !load.schema.title.isEmpty {
            databaseTitle = load.schema.title
            defaults.set(load.schema.title, forKey: Keys.databaseTitle)
        }
        items = load.items.filter { !pendingCompletions.contains($0.id) }.map { item in
            guard let pending = pendingNotes[item.id] else { return item }
            var kept = item
            kept.notes = pending.isEmpty ? nil : pending
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
    func applyFailure(_ error: NotionAPIError) {
        switch error {
        case .cancelled:
            return
        case .unauthorized:
            dropItems()
            tokenRejected = hasToken
            state = .invalidToken
        case .forbidden:
            dropItems()
            state = .missingReadCapability
        case .notFound:
            dropItems()
            state = .databaseUnavailable
        case .badRequest:
            dropItems()
            state = .needsAttention(.queryRejected)
        case .rateLimited(let retryAfter):
            gate.recordRateLimit(retryAfter: retryAfter, now: now())
            isShowingCachedItems = !items.isEmpty
            state = .rateLimited
        case .offline:
            gate.recordFailure(now: now())
            isShowingCachedItems = !items.isEmpty
            state = .offline
        case .server, .invalidResponse:
            gate.recordFailure(now: now())
            isShowingCachedItems = !items.isEmpty
            state = .serverError
        }
    }

    private func dropItems() {
        items = []
        isShowingCachedItems = false
        resolved = nil
    }

    // MARK: Helpers shared with the actions extension

    func makeClient() -> NotionClient? {
        guard let token else { return nil }
        return NotionClient(token: token, transport: resolvedTransport())
    }

    func resolvedTransport() -> any NotionTransport {
        if let transport { return transport }
        let created = NotionURLSessionTransport()
        transport = created
        return created
    }

    /// Writes the current rows to disk in the background.
    func saveCache() {
        guard let selectedDatabaseID else { return }
        let snapshot = NotionTodoSnapshot(
            dataSourceID: selectedDatabaseID,
            databaseTitle: databaseTitle ?? "",
            savedAt: now(),
            items: items
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
        selectedDatabaseID = defaults.string(forKey: Keys.dataSourceID)
        databaseTitle = defaults.string(forKey: Keys.databaseTitle)
        accountName = defaults.string(forKey: Keys.account)
        if let data = defaults.data(forKey: Keys.mapping),
           let stored = try? JSONDecoder().decode(NotionTodoMapping.self, from: data) {
            mapping = stored
        } else {
            // Missing or unreadable: resolving an empty mapping reports
            // "pick how tasks are marked done" in the card and settings.
            mapping = NotionTodoMapping()
        }
    }

    func persistSelection() {
        setOrRemove(selectedDatabaseID, Keys.dataSourceID)
        setOrRemove(databaseTitle, Keys.databaseTitle)
        setOrRemove(accountName, Keys.account)
        if let data = try? JSONEncoder().encode(mapping) {
            defaults.set(data, forKey: Keys.mapping)
        }
    }

    private func setOrRemove(_ value: String?, _ key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
