import Foundation

/// Setup steps driven from settings, and the two writes driven from the card.
extension NookNotionTodoService {
    // MARK: Token

    /// Checks a pasted token against Notion and, when it works, writes it to
    /// the token file. The token is never written anywhere else, and the
    /// Keychain is not touched. While an older token is being brought over a
    /// connect does nothing: the move would write the file after it and put
    /// the old token over the new one.
    func connect(token raw: String) async {
        let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isActive, !isMovingToken, !candidate.isEmpty else { return }
        // A token is one unbroken run of characters. Anything else cannot be
        // sent as a header value.
        guard !candidate.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            state = .invalidToken
            return
        }
        cancelWork()
        let startEpoch = epoch
        state = .connecting

        let client = NotionClient(token: candidate, transport: resolvedTransport())
        let user: NotionUser
        do {
            user = try await client.currentUser()
        } catch {
            guard epoch == startEpoch else { return }
            let failure = NotionClient.classify(error)
            if failure == .unauthorized {
                // The pasted token is bad. That says nothing about a stored one.
                state = .invalidToken
            } else {
                applyFailure(failure)
            }
            return
        }
        guard isActive, epoch == startEpoch else { return }

        let store = tokenStore
        do {
            try await Task.detached { try store.save(candidate) }.value
        } catch {
            tokenProblem = .describing(error, fallback: .cannotSave)
            state = .keychainUnavailable
            return
        }
        guard isActive, epoch == startEpoch else { return }

        token = candidate
        hasToken = true
        tokenRejected = false
        tokenProblem = nil
        moveFailed = false
        accountName = user.displayName
        resetSession()
        gate.reset(forgetRateLimit: true)
        persistSelection()
        await loadDatabases()
        guard isActive, epoch == startEpoch, state == .connecting else { return }
        if selectedDatabaseID == nil {
            state = .noDatabase
        } else {
            await performRefresh()
        }
    }

    /// Deletes the token file, the offline copy and the saved setup. While an
    /// older build's Keychain item may still be there, it goes too: a delete
    /// does not raise macOS's prompt.
    func disconnect() async {
        cancelWork()
        token = nil
        hasToken = false
        tokenRejected = false
        tokenProblem = nil
        moveFailed = false
        resetSession()
        gate.reset(forgetRateLimit: true)
        databases = []
        hasLoadedDatabases = false
        selectedDatabaseID = nil
        databaseTitle = nil
        accountName = nil
        mapping = NotionTodoMapping()
        persistSelection()
        state = .noToken

        let store = tokenStore
        let move = tokenMove
        let removesOldItem = !isKeychainSettled
        let fileResult = await Task.detached { Result { try store.delete() } }.value
        if case .failure(let error) = fileResult {
            tokenProblem = .describing(error, fallback: .cannotRemove)
            state = .keychainUnavailable
        } else if removesOldItem {
            let oldResult = await Task.detached { Result { try move.removeOldItem() } }.value
            if case .failure = oldResult {
                tokenProblem = NookTodoTokenFileError(.oldItemRemains)
                state = .keychainUnavailable
            } else {
                settleKeychain()
            }
        }
        await clearCache()
    }

    // MARK: Bringing an older token over

    /// What Settings reads to decide on the "Bring my saved token over"
    /// button. Built from what the app already saved: no Keychain query.
    var tokenMoveOffer: NookTodoTokenMoveOffer {
        NookTodoTokenMoveOffer(
            isNotConnected: isActive && !hasToken,
            hasSavedAccountSign: accountName != nil || selectedDatabaseID != nil || hasOfflineCopy,
            isKeychainSettled: isKeychainSettled,
            canMove: tokenMove.hasOldStore
        )
    }

    /// Reads the Keychain item once, writes the token file and deletes the
    /// item. macOS may ask for permission, which is fine: the user asked.
    /// A second press, or a press while this runs or while a pasted token is
    /// being checked, does nothing.
    func bringTokenOver() async {
        guard tokenMoveOffer.isShown, !isMovingToken, state != .connecting else { return }
        isMovingToken = true
        moveFailed = false
        let startEpoch = epoch
        let store = tokenStore
        let move = tokenMove
        let result = await Task.detached { Result { try move.bringOver(to: store) } }.value
        isMovingToken = false

        let outcome: NookTodoTokenMove.Outcome
        switch result {
        case .success(let done):
            outcome = done
        case .failure(let error):
            guard isActive, epoch == startEpoch else { return }
            if let fileError = error as? NookTodoTokenFileError {
                tokenProblem = fileError
                state = .keychainUnavailable
            } else {
                // The Keychain would not give the token up. The button stays.
                moveFailed = true
            }
            return
        }
        // The Keychain is dealt with even when the user has moved on.
        if outcome != .movedButItemRemains { settleKeychain() }
        guard isActive, outcome != .nothingSaved else { return }
        // A source switch during the prompt began an activation of its own,
        // which may have read the file before the token was in it. Starting
        // over on a new epoch voids that one.
        cancelWork()
        state = .connecting
        await finishActivation(epoch: epoch)
    }

    func settleKeychain() {
        isKeychainSettled = true
        defaults.set(true, forKey: Keys.keychainSettled)
    }

    // MARK: Database

    /// Lists the databases shared with the integration.
    func loadDatabases() async {
        guard isActive, !isRateLimited, let client = makeClient() else { return }
        let startEpoch = epoch
        isLoadingDatabases = true
        do {
            let found = try await client.searchDataSources(limit: Self.databaseLimit)
            guard epoch == startEpoch else { return }
            let untitled = LanguageManager.shared.t("nook.todo.notion.untitled")
            databases = found
                .filter { !$0.isInTrash }
                .map { NotionDatabaseChoice(id: $0.id, title: $0.title.isEmpty ? untitled : $0.title) }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            hasLoadedDatabases = true
        } catch {
            guard epoch == startEpoch else { return }
            applyFailure(NotionClient.classify(error))
        }
        isLoadingDatabases = false
    }

    /// Switches to another database and guesses its mapping from the schema.
    func selectDatabase(_ id: String?) async {
        guard isActive, id != selectedDatabaseID else { return }
        cancelWork()
        let startEpoch = epoch
        resetSession()
        selectedDatabaseID = id
        databaseTitle = databases.first { $0.id == id }?.title
        mapping = NotionTodoMapping()
        persistSelection()
        await clearCache()
        guard isActive, epoch == startEpoch else { return }
        guard let id, let client = makeClient() else {
            state = hasToken ? .noDatabase : .noToken
            return
        }
        state = .connecting
        do {
            let fetched = try await client.dataSource(id: id)
            guard isActive, epoch == startEpoch else { return }
            schema = fetched
            mapping = NotionTodoMapper.detect(fetched)
            defaults.set(true, forKey: Keys.notesColumnChecked)
            persistSelection()
        } catch {
            guard epoch == startEpoch else { return }
            applyFailure(NotionClient.classify(error))
            return
        }
        await performRefresh()
    }

    // MARK: Mapping

    /// Applies a change from the settings pickers and reloads shortly after.
    func updateMapping(_ change: (inout NotionTodoMapping) -> Void) {
        var next = mapping
        change(&next)
        guard next != mapping else { return }
        mapping = next
        // The user has seen the pickers: their choice stands, "None" included.
        defaults.set(true, forKey: Keys.notesColumnChecked)
        persistSelection()
        refresh(.manual, debounce: Self.mappingDebounce)
    }

    /// Picks the column that marks a task done. Its type decides the kind.
    func setDoneProperty(id: String?) {
        let property = schema?.property(id: id)
        updateMapping { mapping in
            mapping.donePropertyID = property?.id
            mapping.doneKind = property.flatMap { NotionDoneKind(rawValue: $0.type) }
            mapping.doneOptionName = property.flatMap { $0.type == "select" ? NotionTodoMapper.doneOption(in: $0)?.name : nil }
        }
    }

    /// Clears a "missing capability" flag and reloads. For use after the
    /// user changed the integration in Notion.
    func recheck() {
        canInsert = true
        canUpdate = true
        actionError = nil
        refresh(.manual)
    }

    // MARK: Writes

    func complete(_ id: String) {
        track { await $0.performComplete(id) }
    }

    func add(_ title: String, due: DateComponents?) {
        track { _ = await $0.performAdd(title, due: due) }
    }

    /// Waits for Notion's answer: true once the page was created.
    func addConfirmed(_ title: String, due: DateComponents?) async -> Bool {
        await performAdd(title, due: due)
    }

    func setNotes(_ notes: String, for id: String) {
        track { await $0.performSetNotes(notes, for: id) }
    }

    private func track(_ work: @escaping @MainActor (NookNotionTodoService) async -> Void) {
        let key = UUID()
        actionTasks[key] = Task { [weak self] in
            guard let self else { return }
            await work(self)
            self.actionTasks[key] = nil
        }
    }

    /// Removes the row at once, then tells Notion. A failure puts the row
    /// back where it was and reports why.
    func performComplete(_ id: String) async {
        guard isActive, canUpdate, let client = makeClient(), let resolved,
              let properties = NotionTodoMapper.completionProperties(resolved),
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
            try await client.updatePage(id: id, properties: properties)
            guard epoch == startEpoch else { return }
            pendingCompletions.remove(id)
            saveCache()
            // A load that asked Notion before the update landed would bring
            // the row back. Void it and read again.
            refreshSerial += 1
            refresh(.manual)
        } catch {
            guard epoch == startEpoch else { return }
            pendingCompletions.remove(id)
            if !items.contains(where: { $0.id == id }) {
                items.insert(item, at: min(index, items.count))
            }
            reportWriteFailure(NotionClient.classify(error), fallback: .completeFailed) { canUpdate = false }
        }
    }

    /// Shows the new notes at once, then tells Notion. A failure puts the
    /// last saved notes back, hands the unsaved text to `onNotesWriteFinished`
    /// and reports why. The whole column is replaced with plain text.
    ///
    /// One update per task is in flight at a time. Text saved meanwhile
    /// waits and goes out next, which keeps Notion from applying two
    /// updates out of order.
    func performSetNotes(_ notes: String, for id: String) async {
        guard isActive, canEditNotes, let client = makeClient(), let resolved,
              let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard NotionTodoMapper.clampedNotes(notes) == notes else {
            // Longer than Notion can hold. Nothing is sent or cut short.
            actionError = .notesTooLong
            onNotesWriteFinished?(id, notes, false)
            return
        }
        let previous = items[index].notes
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
        items[index].notes = notes.isEmpty ? nil : notes
        pendingNotes[id] = notes
        if notesInFlight.contains(id) {
            queuedNotes[id] = notes
            return
        }
        notesInFlight.insert(id)
        let startEpoch = epoch
        // What Notion is known to hold. A failure goes back to this.
        var confirmed = previous
        var sending = notes
        // Ends when nothing newer was queued during the last request.
        while let properties = NotionTodoMapper.notesProperties(sending, resolved: resolved) {
            do {
                try await client.updatePage(id: id, properties: properties)
            } catch {
                guard epoch == startEpoch else { return }
                let unsaved = queuedNotes.removeValue(forKey: id) ?? sending
                notesInFlight.remove(id)
                pendingNotes[id] = nil
                if let current = items.firstIndex(where: { $0.id == id }) {
                    items[current].notes = confirmed
                }
                reportWriteFailure(NotionClient.classify(error), fallback: .notesFailed) { canUpdate = false }
                notesSaveFailed = true
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
        saveCache()
        // A load that asked Notion before the update landed carries the old
        // notes. Void it and read again.
        refreshSerial += 1
        refresh(.manual)
    }

    /// Creates a not-done task with this title. `due` is a whole day for the
    /// Due column (D69). The row shown at once carries it too, so the date is
    /// there before the reload.
    @discardableResult
    func performAdd(_ title: String, due: DateComponents? = nil) async -> Bool {
        let trimmed = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxTitleLength))
        guard isActive, canInsert, !trimmed.isEmpty, let client = makeClient(), let resolved,
              let dataSourceID = selectedDatabaseID else { return false }
        guard !isRateLimited else {
            actionError = .rateLimited
            return false
        }
        let startEpoch = epoch
        actionError = nil
        // With no Due column mapped nothing is sent, so the row has no date.
        let day = resolved.dueProperty == nil ? nil : NookTodoDay.normalized(due)
        do {
            let page = try await client.createPage(
                dataSourceID: dataSourceID,
                properties: NotionTodoMapper.creationProperties(title: trimmed, resolved: resolved, due: day)
            )
            // The page exists in Notion even when the source changed meanwhile.
            guard epoch == startEpoch else { return true }
            if !items.contains(where: { $0.id == page.id }) {
                items.append(NookTodoItem(
                    id: page.id, title: trimmed,
                    dueDate: day.flatMap { NookTodoDay.date(from: $0, calendar: .current) },
                    isCompleted: false, listName: databaseTitle ?? ""
                ))
            }
            saveCache()
            // Puts the new row in its sorted place.
            refresh(.manual)
            return true
        } catch {
            guard epoch == startEpoch else { return false }
            reportWriteFailure(NotionClient.classify(error), fallback: .addFailed) { canInsert = false }
            return false
        }
    }

    private func reportWriteFailure(
        _ error: NotionAPIError,
        fallback: NotionTodoActionError,
        onForbidden: () -> Void
    ) {
        if error != .cancelled {
            nookTodoDueLog.error(
                "Notion write failed (\(String(describing: fallback), privacy: .public)): \(String(describing: error), privacy: .public)"
            )
        }
        switch error {
        case .cancelled:
            return
        case .forbidden:
            // The control turns off and its label says why.
            onForbidden()
        case .unauthorized:
            applyFailure(.unauthorized)
        case .rateLimited(let retryAfter):
            gate.recordRateLimit(retryAfter: retryAfter, now: now())
            actionError = .rateLimited
        default:
            actionError = fallback
        }
    }
}

// MARK: - Todo source

extension NookNotionTodoService: NookTodoSource {
    private var lang: LanguageManager { .shared }

    var displayName: String {
        if let databaseTitle, !databaseTitle.isEmpty { return databaseTitle }
        return "Notion"
    }

    var connection: NookTodoConnection {
        if state.allowsItems, state == .ready || !items.isEmpty {
            return .ready
        }
        return .unavailable(message: cardMessage)
    }

    /// Why the token file cannot be used, while that is the state.
    var tokenProblemText: String? {
        guard state == .keychainUnavailable, let tokenProblem else { return nil }
        return lang.t(tokenProblem.messageKey)
    }

    /// The card's line for the state. A token waiting to come over from an
    /// older build points at Settings, where the button is.
    private var cardMessage: String {
        if state == .noToken, tokenMoveOffer.isShown { return lang.t("nook.todo.token.state.movePending") }
        return [lang.t(state.messageKey), tokenProblemText].compactMap { $0 }.joined(separator: " ")
    }

    var errorMessage: String? {
        if let actionError { return lang.t(actionError.messageKey) }
        if !canUpdate { return lang.t("nook.todo.notion.error.cannotUpdate") }
        return nil
    }

    var canAdd: Bool { canInsert && resolved != nil && state.allowsItems }
    var canComplete: Bool { canUpdate && resolved != nil && state.allowsItems }

    /// Needs a mapped notes column, one live load and update capability.
    var canEditNotes: Bool { canComplete && resolved?.notesProperty != nil }

    var notesUnavailableReason: String? {
        if canEditNotes { return nil }
        if !canUpdate { return lang.t("nook.todo.notion.error.cannotUpdate") }
        if mapping.notesPropertyID == nil { return lang.t("nook.todo.notion.notes.pickColumn") }
        return lang.t("nook.todo.notes.unavailable")
    }

    /// Needs adding to work and a Due column picked in Settings.
    var canSetDue: Bool { canAdd && resolved?.dueProperty != nil }

    var dueUnavailableReason: String? {
        if canSetDue { return nil }
        if canAdd { return lang.t("nook.todo.due.pickColumn") }
        return lang.t("nook.todo.due.unavailable")
    }

    var addPlaceholder: String {
        if !canInsert { return lang.t("nook.todo.notion.error.cannotInsert") }
        return lang.t(canAdd ? "nook.todo.notion.add" : "nook.todo.notion.addUnavailable")
    }

    var autoRefreshInterval: Duration? { Self.foregroundRefreshInterval }

    func refresh() {
        refresh(.opened)
    }

    func refreshOnTimer() {
        refresh(.timer)
    }
}
