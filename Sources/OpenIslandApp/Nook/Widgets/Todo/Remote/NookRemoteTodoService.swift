import Foundation
import Observation

/// Asana as a task source: my open tasks in one workspace (D83).
typealias NookAsanaTodoService = NookRemoteTodoService<AsanaTodoBackend>
/// monday as a task source: items assigned to me on one board (D83).
typealias NookMondayTodoService = NookRemoteTodoService<MondayTodoBackend>
/// Canvas as a task source: assignments due in the next two weeks (T14).
typealias NookCanvasTodoService = NookRemoteTodoService<CanvasTodoBackend>

/// One task app reached over the network, as the card and Settings see it
/// (D83): the token file, the place picked, the refresh gate, the rows and
/// the writes. The requests themselves are the backend's.
///
/// Idle until `setActive(true)`: no token file, disk or network work
/// happens while the app is off in Settings. The Keychain is never read.
@MainActor
@Observable
final class NookRemoteTodoService<Backend: NookTodoBackend> {
    /// Most tasks loaded for the card.
    static var taskLimit: Int { 100 }
    /// Keeps a pasted page of text out of a task title.
    static var maxTitleLength: Int { 500 }
    /// Both tick a little slower than the gate spacing they must clear
    /// (60s open, 300s closed); an exact match would lose every other tick.
    static var foregroundRefreshInterval: Duration { .seconds(62) }
    static var backgroundPollInterval: Duration { .seconds(305) }

    static var kind: NookTodoSourceKind { Backend.kind }
    static var placeIDKey: String { "nook.todo.\(Backend.kind.rawValue).placeID" }
    static var placeNameKey: String { "nook.todo.\(Backend.kind.rawValue).placeName" }
    static var hostKey: String { "nook.todo.\(Backend.kind.rawValue).host" }
    /// The token file's name part, per D61: `todo-asana`, `todo-monday`,
    /// `todo-canvas`.
    static var tokenFileKind: String { "todo-\(Backend.kind.rawValue)" }

    // MARK: Observable state

    private(set) var isActive = false
    /// The card's rows.
    var items: [NookTodoItem] = []
    var state: NookTodoRemoteState = .inactive
    var actionError: NookTodoRemoteActionError? {
        // The next write, and a refresh that clears the line, clear this too.
        didSet { if actionError == nil { notesSaveFailed = false } }
    }
    /// A notes save failed and the row went back to the notes the app
    /// holds: the card keeps the person's draft.
    var notesSaveFailed = false
    /// False after the app answered 403 to a write.
    var canWrite = true
    var hasToken = false
    /// The app answered 401 for the stored token. Stays set until a new
    /// token connects, which keeps the token field on screen.
    var tokenRejected = false
    /// Disconnect could not remove the token file. It is still stored, and
    /// the session is as it was.
    var tokenRemovalFailed = false
    /// Why the token file could not be used. Set with `.tokenFileProblem`.
    var tokenProblem: NookTodoTokenFileError?
    /// The workspaces, boards or courses the token can read.
    var places: [NookTodoPlaceChoice] = []
    var hasLoadedPlaces = false
    var isLoadingPlaces = false
    /// The last try to load the places failed. The picker shows what it had.
    var placesLoadFailed = false
    /// The workspace or board picked. Nil until one is, for an app that
    /// needs one.
    var selectedPlaceID: String?
    /// The picked place's name, as the app had it.
    var placeName: String?
    /// The account's name, when the app says it at the token check.
    var accountName: String?
    /// The app's address, for an app that lives at one (Canvas). Saved.
    var host: String?
    var lastRefreshed: Date?

    // MARK: Internals

    @ObservationIgnored var token: String?
    @ObservationIgnored var gate = NookTodoRefreshGate()
    /// What the last load said a write needs to know (column ids, the
    /// account's id, an override's id). The backend fills it and reads it.
    @ObservationIgnored var context: [String: String] = [:]
    /// Rows removed optimistically whose request has not finished.
    @ObservationIgnored var pendingCompletions: Set<String> = []
    /// Notes written locally whose update has not finished, by task ID. An
    /// empty text means cleared. A load never overwrites these.
    @ObservationIgnored var pendingNotes: [String: String] = [:]
    /// Called when a notes write ends: task ID, the text, and whether the
    /// app took it. The hub keeps text that did not save.
    @ObservationIgnored var onNotesWriteFinished: ((_ id: String, _ text: String, _ saved: Bool) -> Void)?
    /// Bumped whenever in-flight work must be ignored: switch off,
    /// connect, disconnect, another place.
    @ObservationIgnored var epoch = 0
    @ObservationIgnored var refreshSerial = 0
    @ObservationIgnored var refreshTask: Task<Void, Never>?
    @ObservationIgnored var setupTask: Task<Void, Never>?
    @ObservationIgnored var pollTask: Task<Void, Never>?
    @ObservationIgnored var actionTasks: [UUID: Task<Void, Never>] = [:]

    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored let tokenStore: any NookTodoTokenStoring
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored private var transport: (any NookTodoTransport)?

    init(
        defaults: UserDefaults = .standard,
        transport: (any NookTodoTransport)? = nil,
        tokenStore: (any NookTodoTokenStoring)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.transport = transport
        self.tokenStore = tokenStore ?? NookTodoTokenFile(kind: Self.tokenFileKind)
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

    /// Reads the token file, then loads. Only the file is read: a missing
    /// token shows the "not connected" state.
    func finishActivation(epoch startEpoch: Int) async {
        guard isActive, epoch == startEpoch else { return }
        let store = tokenStore
        let tokenResult = await Task.detached { Result { try store.read() } }.value
        guard isActive, epoch == startEpoch else { return }

        switch tokenResult {
        case .failure(let error):
            tokenProblem = .describing(error, fallback: .unreadable)
            state = .tokenFileProblem
            return
        case .success(nil):
            tokenProblem = nil
            state = .noToken
            return
        case .success(let stored?):
            tokenProblem = nil
            token = stored
            hasToken = true
        }
        if Backend.needsHost, host == nil {
            state = .noHost
            return
        }
        if Backend.needsPlace, selectedPlaceID == nil {
            state = .noPlace
            await loadPlaces()
            return
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
        places = []
        hasLoadedPlaces = false
        placesLoadFailed = false
        tokenRemovalFailed = false
        tokenProblem = nil
        accountName = nil
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
        isLoadingPlaces = false
    }

    /// Clears everything derived from one token and place.
    func resetSession() {
        items = []
        context = [:]
        actionError = nil
        canWrite = true
        pendingCompletions = []
        pendingNotes = [:]
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
        guard isActive, let session = makeSession() else { return }
        if Backend.needsPlace, selectedPlaceID == nil {
            state = .noPlace
            return
        }
        guard !isRateLimited else {
            state = .rateLimited
            return
        }
        gate.recordAttempt(now: now())
        let result: Result<NookTodoRemoteLoad, NookTodoRemoteError>
        do {
            result = .success(try await Backend.load(session, placeID: selectedPlaceID, placeName: placeName))
        } catch {
            result = .failure(NookTodoRemoteError.classify(error))
        }
        // A newer refresh, a switch off or a disconnect makes this one void.
        guard isActive, serial == refreshSerial else { return }
        switch result {
        case .success(let load): apply(load)
        case .failure(let error): applyFailure(error)
        }
    }

    private func apply(_ load: NookTodoRemoteLoad) {
        if let name = load.placeName, name != placeName {
            placeName = name
            defaults.set(name, forKey: Self.placeNameKey)
        }
        // The token works: a rejection seen earlier no longer stands.
        tokenRejected = false
        context = load.context
        items = Array(load.items.prefix(Self.taskLimit))
            .filter { !pendingCompletions.contains($0.id) }
            .map { item in
                guard let pending = pendingNotes[item.id] else { return item }
                var kept = item
                kept.notes = pending.isEmpty ? nil : pending
                return kept
            }
        // A note that did not save stays reported until the next write.
        if actionError?.concernsNotes != true { actionError = nil }
        lastRefreshed = now()
        gate.recordSuccess()
        state = .ready
    }

    /// Turns a failed request into the state the card and settings show.
    func applyFailure(_ error: NookTodoRemoteError) {
        switch error {
        case .cancelled:
            return
        case .unauthorized:
            items = []
            tokenRejected = hasToken
            state = .invalidToken
        case .forbidden:
            items = []
            state = .forbidden
        case .notFound:
            items = []
            state = .placeUnavailable
        case .badRequest:
            items = []
            state = .rejected
        case .rateLimited(let retryAfter):
            gate.recordRateLimit(retryAfter: retryAfter, now: now())
            state = .rateLimited
        case .offline:
            gate.recordFailure(now: now())
            state = .offline
        case .server, .invalidResponse:
            gate.recordFailure(now: now())
            state = .serverError
        }
    }

    // MARK: Token and place

    /// Checks a pasted token against the app and, when it works, writes it
    /// to the token file. The token is never written anywhere else. An app
    /// that lives at an address takes it here too (`host`), and nothing is
    /// sent until the address is a host name.
    func connect(token raw: String, host rawHost: String? = nil) async {
        let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isActive, !candidate.isEmpty else { return }
        // A token is one unbroken run of characters. Anything else cannot be
        // sent as a header value.
        guard !candidate.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            state = .invalidToken
            return
        }
        var newHost = host
        if Backend.needsHost {
            guard let normalized = NookTodoRemoteHost.normalized(rawHost ?? host ?? "") else {
                state = .noHost
                return
            }
            newHost = normalized
        }
        cancelWork()
        let startEpoch = epoch
        tokenRemovalFailed = false
        state = .connecting

        let session = NookTodoRemoteSession(token: candidate, host: newHost, transport: resolvedTransport(), now: now())
        let check: NookTodoRemoteCheck
        do {
            check = try await Backend.check(session)
        } catch {
            guard epoch == startEpoch else { return }
            switch NookTodoRemoteError.classify(error) {
            case .cancelled:
                // Nothing was decided. Back to asking for a token.
                state = hasToken ? .invalidToken : .noToken
            case .unauthorized, .forbidden:
                // The pasted token is bad. That says nothing about a stored one.
                state = .invalidToken
            case .offline:
                state = .offline
            case .notFound where Backend.needsHost:
                // The address answers, but not as the app: a wrong host.
                state = .noHost
            case .rateLimited, .server, .invalidResponse, .notFound, .badRequest:
                // Nothing retries a connect, which rules out the messages
                // that promise another try.
                state = .connectFailed
            }
            return
        }
        guard isActive, epoch == startEpoch else { return }

        let store = tokenStore
        do {
            try await Task.detached { try store.save(candidate) }.value
        } catch {
            tokenProblem = .describing(error, fallback: .cannotSave)
            state = .tokenFileProblem
            return
        }
        guard isActive, epoch == startEpoch else { return }

        token = candidate
        hasToken = true
        tokenRejected = false
        tokenProblem = nil
        if Backend.needsHost, let newHost {
            host = newHost
            defaults.set(newHost, forKey: Self.hostKey)
        }
        resetSession()
        gate.reset(forgetRateLimit: true)
        adopt(check)
        if Backend.needsPlace {
            // A place saved for another account may not exist in this one;
            // the only place there is needs no picking.
            if let id = selectedPlaceID, !places.contains(where: { $0.id == id }) {
                selectedPlaceID = nil
                placeName = nil
            }
            if selectedPlaceID == nil, places.count == 1, let only = places.first {
                selectedPlaceID = only.id
                placeName = only.name
            }
            persistSelection()
            if selectedPlaceID == nil {
                state = .noPlace
                return
            }
        }
        await performRefresh()
    }

    /// A new address for an app that lives at one, with the token already
    /// stored: the same check as a connect, with that token.
    func changeHost(_ rawHost: String) async {
        guard Backend.needsHost, let token else { return }
        await connect(token: token, host: rawHost)
    }

    /// Deletes the token file and the saved setup. The token file goes
    /// first: when it cannot be removed the token is still stored, and the
    /// session stays as it was with Disconnect still on screen.
    func disconnect() async {
        tokenRemovalFailed = false
        let store = tokenStore
        let result = await Task.detached { Result { try store.delete() } }.value
        if case .failure = result {
            tokenRemovalFailed = true
            return
        }
        cancelWork()
        token = nil
        hasToken = false
        tokenRejected = false
        tokenProblem = nil
        accountName = nil
        resetSession()
        places = []
        hasLoadedPlaces = false
        placesLoadFailed = false
        selectedPlaceID = nil
        placeName = nil
        persistSelection()
        state = isActive ? .noToken : .inactive
    }

    /// Loads the places the token can read, for the picker. Also the token
    /// check, which is why a failure here can mean a bad token.
    func loadPlaces() async {
        guard isActive, let session = makeSession(), !isLoadingPlaces else { return }
        let startEpoch = epoch
        isLoadingPlaces = true
        defer { if epoch == startEpoch { isLoadingPlaces = false } }
        do {
            let check = try await Backend.check(session)
            guard isActive, epoch == startEpoch else { return }
            placesLoadFailed = false
            adopt(check)
        } catch {
            guard isActive, epoch == startEpoch else { return }
            let failure = NookTodoRemoteError.classify(error)
            if failure == .cancelled { return }
            placesLoadFailed = true
            if failure == .unauthorized { applyFailure(failure) }
        }
    }

    /// Picks the workspace or board, which loads its tasks.
    func selectPlace(_ id: String) async {
        guard isActive, id != selectedPlaceID else { return }
        cancelWork()
        selectedPlaceID = id
        placeName = places.first { $0.id == id }?.name
        persistSelection()
        resetSession()
        await performRefresh()
    }

    /// The refresh button: writes allowed again, the error line cleared.
    func recheck() {
        canWrite = true
        if !isRateLimited { actionError = nil }
        refresh(.manual)
    }

    private func adopt(_ check: NookTodoRemoteCheck) {
        places = check.places
        hasLoadedPlaces = true
        if let name = check.accountName { accountName = name }
        if let id = selectedPlaceID, let name = places.first(where: { $0.id == id })?.name, name != placeName {
            placeName = name
            defaults.set(name, forKey: Self.placeNameKey)
        }
    }

    // MARK: Writes

    func complete(_ id: String) {
        track { await $0.performComplete(id) }
    }

    func add(_ title: String, due: DateComponents?) {
        track { _ = await $0.performAdd(title, due: due) }
    }

    /// Waits for the app's answer: true once it has the task.
    func addConfirmed(_ title: String, due: DateComponents?) async -> Bool {
        await performAdd(title, due: due)
    }

    func setNotes(_ notes: String, for id: String) {
        track { await $0.performSetNotes(notes, for: id) }
    }

    private func track(_ work: @escaping @MainActor (NookRemoteTodoService) async -> Void) {
        let key = UUID()
        actionTasks[key] = Task { [weak self] in
            guard let self else { return }
            await work(self)
            self.actionTasks[key] = nil
        }
    }

    /// Removes the row at once, then tells the app. A failure puts the row
    /// back where it was and reports why.
    func performComplete(_ id: String) async {
        guard isActive, canComplete, let session = makeSession(),
              let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard !isRateLimited else {
            actionError = .rateLimited
            return
        }
        let startEpoch = epoch
        let item = items[index]
        items.remove(at: index)
        pendingCompletions.insert(id)
        actionError = nil
        do {
            try await Backend.complete(id, session: session, placeID: selectedPlaceID, context: context)
        } catch {
            guard epoch == startEpoch else { return }
            pendingCompletions.remove(id)
            if !items.contains(where: { $0.id == id }) {
                items.insert(item, at: min(index, items.count))
            }
            reportWriteFailure(NookTodoRemoteError.classify(error), fallback: .completeFailed)
            return
        }
        guard epoch == startEpoch else { return }
        pendingCompletions.remove(id)
        reloadAfterWrite()
    }

    /// Creates a task with this title. True once the app has it; the
    /// reload puts the row in place.
    @discardableResult
    func performAdd(_ title: String, due: DateComponents? = nil) async -> Bool {
        let trimmed = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxTitleLength))
        guard isActive, canAdd, !trimmed.isEmpty, let session = makeSession() else { return false }
        guard !isRateLimited else {
            actionError = .rateLimited
            return false
        }
        let startEpoch = epoch
        actionError = nil
        let day = canSetDue ? NookTodoDay.normalized(due) : nil
        do {
            try await Backend.add(trimmed, due: day, session: session, placeID: selectedPlaceID, context: context)
        } catch {
            guard epoch == startEpoch else { return false }
            reportWriteFailure(NookTodoRemoteError.classify(error), fallback: .addFailed)
            return false
        }
        // The app has the task even when the source changed meanwhile.
        guard epoch == startEpoch else { return true }
        await performRefresh()
        return true
    }

    /// Shows the new notes at once, then tells the app. A failure puts the
    /// last saved notes back, hands the unsaved text to
    /// `onNotesWriteFinished` and reports why.
    func performSetNotes(_ notes: String, for id: String) async {
        guard isActive, canEditNotes, let session = makeSession(),
              let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard !isRateLimited else {
            actionError = .rateLimited
            onNotesWriteFinished?(id, notes, false)
            return
        }
        let startEpoch = epoch
        let before = items[index].notes
        items[index].notes = notes.isEmpty ? nil : notes
        pendingNotes[id] = notes
        actionError = nil
        do {
            try await Backend.setNotes(notes, for: id, session: session, placeID: selectedPlaceID, context: context)
        } catch {
            guard epoch == startEpoch else { return }
            pendingNotes[id] = nil
            if let current = items.firstIndex(where: { $0.id == id }) { items[current].notes = before }
            reportWriteFailure(NookTodoRemoteError.classify(error), fallback: .notesFailed)
            notesSaveFailed = true
            onNotesWriteFinished?(id, notes, false)
            return
        }
        guard epoch == startEpoch else { return }
        pendingNotes[id] = nil
        onNotesWriteFinished?(id, notes, true)
        // A load that asked before the write landed would put the old
        // notes back; it is voided and the list read again.
        reloadAfterWrite()
    }

    /// A load that asked the app before the write landed would bring the
    /// old rows back. Void it and read again.
    private func reloadAfterWrite() {
        refreshSerial += 1
        refresh(.manual)
    }

    private func reportWriteFailure(_ error: NookTodoRemoteError, fallback: NookTodoRemoteActionError) {
        if error != .cancelled {
            nookTodoDueLog.error(
                "\(Backend.kind.rawValue, privacy: .public) write failed (\(String(describing: fallback), privacy: .public)): \(String(describing: error), privacy: .public)"
            )
        }
        switch error {
        case .cancelled:
            return
        case .forbidden:
            // The controls turn off and their label says why.
            canWrite = false
        case .unauthorized:
            applyFailure(.unauthorized)
        case .rateLimited(let retryAfter):
            gate.recordRateLimit(retryAfter: retryAfter, now: now())
            actionError = .rateLimited
        case .notFound, .badRequest, .server, .offline, .invalidResponse:
            actionError = fallback
        }
    }

    // MARK: Helpers

    func makeSession() -> NookTodoRemoteSession? {
        guard let token else { return nil }
        if Backend.needsHost, host == nil { return nil }
        return NookTodoRemoteSession(token: token, host: host, transport: resolvedTransport(), now: now())
    }

    func resolvedTransport() -> any NookTodoTransport {
        if let transport { return transport }
        let created = NookTodoURLSessionTransport()
        transport = created
        return created
    }

    private func loadPreferences() {
        selectedPlaceID = defaults.string(forKey: Self.placeIDKey).flatMap { $0.isEmpty ? nil : $0 }
        placeName = defaults.string(forKey: Self.placeNameKey)
        host = defaults.string(forKey: Self.hostKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    func persistSelection() {
        if let selectedPlaceID {
            defaults.set(selectedPlaceID, forKey: Self.placeIDKey)
        } else {
            defaults.removeObject(forKey: Self.placeIDKey)
        }
        if let placeName {
            defaults.set(placeName, forKey: Self.placeNameKey)
        } else {
            defaults.removeObject(forKey: Self.placeNameKey)
        }
    }
}

extension NookRemoteTodoService: NookTodoNotesWriting {}

// MARK: - What the card reads

extension NookRemoteTodoService: NookTodoSource {
    private var lang: LanguageManager { .shared }

    /// The app's name in the user's language.
    var appName: String { lang.t(Backend.kind.nameKey) }

    var displayName: String {
        if let placeName, !placeName.isEmpty { return placeName }
        if Backend.needsHost, let host { return host }
        return appName
    }

    var connection: NookTodoConnection {
        if state == .ready || (state.isTransientFailure && !items.isEmpty) {
            return .ready
        }
        return .unavailable(message: cardMessage)
    }

    /// Why the token file cannot be used, while that is the state.
    var tokenProblemText: String? {
        guard state == .tokenFileProblem, let tokenProblem else { return nil }
        return lang.t(tokenProblem.messageKey)
    }

    private var cardMessage: String {
        [state.message(app: appName, lang: lang), tokenProblemText].compactMap { $0 }.joined(separator: " ")
    }

    var errorMessage: String? {
        if let actionError { return lang.t(actionError.messageKey) }
        if !canWrite { return lang.t("nook.todo.remote.error.readOnly", appName) }
        return nil
    }

    var isShowingCachedItems: Bool { false }

    /// Writes need the last load to have worked. Offline or rate limited,
    /// the rows are shown and nothing more, which keeps a typed task from
    /// going nowhere.
    var canAdd: Bool { Backend.canAdd && canWrite && state == .ready }
    var canComplete: Bool { Backend.canComplete && canWrite && state == .ready }
    var canEditNotes: Bool { Backend.canEditNotes && canWrite && state == .ready }

    var notesUnavailableReason: String? {
        if canEditNotes { return nil }
        if !Backend.canEditNotes { return lang.t("nook.todo.remote.notes.never", appName) }
        if !canWrite { return lang.t("nook.todo.remote.error.readOnly", appName) }
        return lang.t("nook.todo.notes.unavailable")
    }

    var canSetDue: Bool { Backend.canSetDue && canAdd }

    var dueUnavailableReason: String? {
        canSetDue ? nil : lang.t("nook.todo.due.unavailable")
    }

    var addPlaceholder: String {
        if !Backend.canAdd { return lang.t("nook.todo.remote.add.never", appName) }
        if !canWrite { return lang.t("nook.todo.remote.error.readOnly", appName) }
        return lang.t(canAdd ? "nook.todo.remote.add" : "nook.todo.remote.addUnavailable")
    }

    var autoRefreshInterval: Duration? { Self.foregroundRefreshInterval }

    func refresh() {
        refresh(.opened)
    }

    func refreshOnTimer() {
        refresh(.timer)
    }
}
