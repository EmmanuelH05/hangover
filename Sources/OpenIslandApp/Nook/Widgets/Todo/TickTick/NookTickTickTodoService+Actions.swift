import Foundation

/// Setup steps driven from settings, and the three writes driven from the card.
extension NookTickTickTodoService {
    // MARK: Token

    /// Checks a pasted token against TickTick and, when it works, stores it
    /// in the Keychain. The token is never written anywhere else.
    func connect(token raw: String) async {
        let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isActive, !candidate.isEmpty else { return }
        // A token is one unbroken run of characters. Anything else cannot be
        // sent as a header value.
        guard !candidate.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            state = .invalidToken
            return
        }
        cancelWork()
        let startEpoch = epoch
        tokenRemovalFailed = false
        state = .connecting

        // TickTick has no "who am I" request. Listing the lists is the
        // check, and its answer fills the picker.
        let client = TickTickClient(token: candidate, transport: resolvedTransport())
        let projects: [TickTickProject]
        do {
            projects = try await client.projects()
        } catch {
            guard epoch == startEpoch else { return }
            switch TickTickClient.classify(error) {
            case .cancelled:
                // Nothing was decided. Back to asking for a token.
                state = hasToken ? .invalidToken : .noToken
            case .unauthorized, .forbidden:
                // The pasted token is bad. That says nothing about a stored one.
                state = .invalidToken
            case .offline:
                state = .offline
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
            state = .keychainUnavailable
            return
        }
        guard isActive, epoch == startEpoch else { return }

        token = candidate
        hasToken = true
        tokenRejected = false
        resetSession()
        gate.reset(forgetRateLimit: true)
        adopt(projects)
        // A list saved for another account does not exist in this one.
        if selectedListID != TickTickClient.inboxID, !lists.contains(where: { $0.id == selectedListID }) {
            selectedListID = TickTickClient.inboxID
            listName = nil
        }
        persistSelection()
        // The offline copy may hold another account's tasks.
        await clearCache()
        guard isActive, epoch == startEpoch else { return }
        await performRefresh()
    }

    /// Deletes the Keychain item, the offline copy and the saved setup. The
    /// Keychain goes first: when it refuses, the token is still stored, and
    /// the session stays as it was with Disconnect still on screen.
    func disconnect() async {
        tokenRemovalFailed = false
        let store = tokenStore
        do {
            try await Task.detached { try store.delete() }.value
        } catch {
            tokenRemovalFailed = true
            return
        }
        cancelWork()
        token = nil
        hasToken = false
        tokenRejected = false
        resetSession()
        gate.reset(forgetRateLimit: true)
        lists = []
        hasLoadedLists = false
        listsLoadFailed = false
        selectedListID = TickTickClient.inboxID
        listName = nil
        persistSelection()
        if isActive { state = .noToken }
        await clearCache()
    }

    // MARK: Lists

    /// Lists the user's lists. The inbox is not among them: the picker
    /// always offers it.
    func loadLists() async {
        guard isActive, let client = makeClient() else { return }
        guard !isRateLimited else {
            listsLoadFailed = true
            return
        }
        let startEpoch = epoch
        isLoadingLists = true
        do {
            let found = try await client.projects()
            guard epoch == startEpoch else { return }
            adopt(found)
        } catch {
            guard epoch == startEpoch else { return }
            let failure = TickTickClient.classify(error)
            // The picker keeps what it had, and Settings says the load failed.
            if failure != .cancelled { listsLoadFailed = true }
            switch failure {
            case .unauthorized, .rateLimited:
                // These are about the token, which the task list shares.
                applyFailure(failure)
            default:
                // Says nothing about the selected list.
                break
            }
        }
        isLoadingLists = false
    }

    private func adopt(_ projects: [TickTickProject]) {
        let untitled = LanguageManager.shared.t("nook.todo.ticktick.untitled")
        lists = projects
            .filter { !$0.isClosed && $0.holdsTasks }
            .map {
                TickTickListChoice(id: $0.id, name: $0.name.isEmpty ? untitled : $0.name, isReadOnly: $0.isReadOnly)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        hasLoadedLists = true
        listsLoadFailed = false
    }

    /// Switches to another list. Pass `TickTickClient.inboxID` for the inbox.
    func selectList(_ id: String) async {
        guard isActive, !id.isEmpty, id != selectedListID else { return }
        cancelWork()
        let startEpoch = epoch
        resetSession()
        selectedListID = id
        let choice = lists.first { $0.id == id }
        listName = id == TickTickClient.inboxID ? nil : choice?.name
        isListReadOnly = choice?.isReadOnly ?? false
        persistSelection()
        await clearCache()
        guard isActive, epoch == startEpoch else { return }
        guard hasToken else {
            state = .noToken
            return
        }
        state = .connecting
        await performRefresh()
    }

    /// Clears a "cannot write" flag and reloads. For use after the list's
    /// sharing changed in TickTick.
    func recheck() {
        canWrite = true
        // While a rate limit is open nothing is sent, and its notice stays.
        if !isRateLimited { actionError = nil }
        refresh(.manual)
    }

    // MARK: Writes

    func complete(_ id: String) {
        track { await $0.performComplete(id) }
    }

    func add(_ title: String) {
        track { await $0.performAdd(title) }
    }

    func setNotes(_ notes: String, for id: String) {
        track { await $0.performSetNotes(notes, for: id) }
    }

    private func track(_ work: @escaping @MainActor (NookTickTickTodoService) async -> Void) {
        let key = UUID()
        actionTasks[key] = Task { [weak self] in
            guard let self else { return }
            await work(self)
            self.actionTasks[key] = nil
        }
    }

    /// Removes the row at once, then tells TickTick. A failure puts the row
    /// back where it was and reports why.
    func performComplete(_ id: String) async {
        guard isActive, canComplete, let client = makeClient(),
              let index = rows.firstIndex(where: { $0.item.id == id }) else { return }
        guard !isRateLimited else {
            actionError = .rateLimited
            return
        }
        let startEpoch = epoch
        let row = rows[index]
        rows.remove(at: index)
        pendingCompletions.insert(id)
        actionError = nil
        do {
            try await client.completeTask(id: id, projectID: row.projectID)
        } catch {
            guard epoch == startEpoch else { return }
            pendingCompletions.remove(id)
            // A 404 is a failure like any other: the task may have moved to
            // another list, still open. The next load drops the row when the
            // task is really gone.
            if !rows.contains(where: { $0.item.id == id }) {
                rows.insert(row, at: min(index, rows.count))
            }
            reportWriteFailure(TickTickClient.classify(error), fallback: .completeFailed)
            return
        }
        guard epoch == startEpoch else { return }
        pendingCompletions.remove(id)
        reloadAfterWrite()
    }

    /// Shows the new notes at once, then tells TickTick. A failure puts the
    /// last saved notes back, hands the unsaved text to
    /// `onNotesWriteFinished` and reports why.
    ///
    /// One update per task is in flight at a time. Text saved meanwhile
    /// waits and goes out next, which keeps TickTick from applying two
    /// updates out of order.
    func performSetNotes(_ notes: String, for id: String) async {
        guard isActive, canEditNotes, let client = makeClient(),
              let index = rows.firstIndex(where: { $0.item.id == id }) else { return }
        let row = rows[index]
        let previous = row.item.notes
        guard (previous ?? "") != notes else {
            onNotesWriteFinished?(id, notes, true)
            return
        }
        guard !isRateLimited else {
            actionError = .rateLimited
            onNotesWriteFinished?(id, notes, false)
            return
        }
        actionError = nil
        rows[index].item.notes = notes.isEmpty ? nil : notes
        pendingNotes[id] = notes
        if notesInFlight.contains(id) {
            queuedNotes[id] = notes
            return
        }
        notesInFlight.insert(id)
        let startEpoch = epoch
        // What TickTick is known to hold. A failure goes back to this.
        var confirmed = previous
        var sending = notes
        // Ends when nothing newer was queued during the last request.
        while true {
            do {
                try await client.setNotes(sending, taskID: id, projectID: row.projectID, field: row.notesField)
            } catch {
                guard epoch == startEpoch else { return }
                let unsaved = queuedNotes.removeValue(forKey: id) ?? sending
                notesInFlight.remove(id)
                pendingNotes[id] = nil
                if let current = rows.firstIndex(where: { $0.item.id == id }) {
                    rows[current].item.notes = confirmed
                }
                reportWriteFailure(TickTickClient.classify(error), fallback: .notesFailed)
                onNotesWriteFinished?(id, unsaved, false)
                return
            }
            guard epoch == startEpoch else { return }
            confirmed = sending.isEmpty ? nil : sending
            onNotesWriteFinished?(id, sending, true)
            guard let next = queuedNotes.removeValue(forKey: id) else { break }
            sending = next
        }
        notesInFlight.remove(id)
        pendingNotes[id] = nil
        reloadAfterWrite()
    }

    /// Creates an open task with this title in the selected list.
    func performAdd(_ title: String) async {
        let trimmed = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxTitleLength))
        guard isActive, canAdd, !trimmed.isEmpty, let client = makeClient() else { return }
        guard !isRateLimited else {
            actionError = .rateLimited
            return
        }
        let startEpoch = epoch
        actionError = nil
        // The inbox goes by its real ID once a load has shown it. Before
        // that no list is named, and TickTick files the task in the inbox.
        let isInbox = selectedListID == TickTickClient.inboxID
        let projectID = isInbox ? inboxProjectID : selectedListID
        let created: TickTickTask?
        do {
            created = try await client.createTask(title: trimmed, projectID: projectID)
        } catch {
            guard epoch == startEpoch else { return }
            reportWriteFailure(TickTickClient.classify(error), fallback: .addFailed)
            return
        }
        guard epoch == startEpoch else { return }
        guard let created else {
            // TickTick said yes and its answer could not be read. Look for
            // the task before calling it added.
            let known = Set(rows.map(\.item.id))
            await performRefresh()
            guard epoch == startEpoch else { return }
            if Set(rows.map(\.item.id)).isSubset(of: known) { actionError = .addFailed }
            return
        }
        if !rows.contains(where: { $0.item.id == created.id }) {
            if isInbox, inboxProjectID == nil { inboxProjectID = created.projectID }
            rows.append(TickTickRow(
                item: NookTodoItem(
                    id: created.id, title: trimmed, dueDate: nil, isCompleted: false, listName: displayName
                ),
                projectID: created.projectID ?? projectID ?? selectedListID,
                notesField: TickTickTaskMapper.notesField(of: created)
            ))
        }
        // Puts the new row in its sorted place.
        reloadAfterWrite()
    }

    /// A load that asked TickTick before the write landed would bring the
    /// old rows back. Void it, keep the offline copy current, read again.
    private func reloadAfterWrite() {
        saveCache()
        refreshSerial += 1
        refresh(.manual)
    }

    private func reportWriteFailure(_ error: TickTickAPIError, fallback: TickTickTodoActionError) {
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
            // Turns the writes off until a load gets through again.
            state = .rateLimited
        default:
            actionError = fallback
        }
    }
}

// MARK: - Todo source

extension NookTickTickTodoService: NookTodoSource {
    private var lang: LanguageManager { .shared }

    var displayName: String {
        if selectedListID == TickTickClient.inboxID { return lang.t("nook.todo.ticktick.inbox") }
        if let listName, !listName.isEmpty { return listName }
        return "TickTick"
    }

    var connection: NookTodoConnection {
        if state.allowsItems, state == .ready || !rows.isEmpty {
            return .ready
        }
        return .unavailable(message: lang.t(state.messageKey))
    }

    var errorMessage: String? {
        if let actionError { return lang.t(actionError.messageKey) }
        if !mayWrite { return lang.t("nook.todo.ticktick.error.readOnly") }
        return nil
    }

    /// The list takes changes: it is not shared read-only, and no write was
    /// refused.
    private var mayWrite: Bool { canWrite && !isListReadOnly }

    /// Writes need the last load to have worked. Offline, rate limited, or
    /// showing the offline copy, the rows are shown and nothing more, which
    /// keeps a typed task from going nowhere.
    var canAdd: Bool { mayWrite && state == .ready }
    var canComplete: Bool { canAdd }
    var canEditNotes: Bool { canAdd }

    var notesUnavailableReason: String? {
        if canEditNotes { return nil }
        if !mayWrite { return lang.t("nook.todo.ticktick.error.readOnly") }
        return lang.t("nook.todo.notes.unavailable")
    }

    var addPlaceholder: String {
        if !mayWrite { return lang.t("nook.todo.ticktick.error.readOnly") }
        return lang.t(canAdd ? "nook.todo.ticktick.add" : "nook.todo.ticktick.addUnavailable")
    }

    var autoRefreshInterval: Duration? { Self.foregroundRefreshInterval }

    func refresh() {
        refresh(.opened)
    }

    func refreshOnTimer() {
        refresh(.timer)
    }
}
