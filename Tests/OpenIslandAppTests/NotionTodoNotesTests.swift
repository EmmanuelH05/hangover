import Foundation
import Testing
@testable import OpenIslandApp

@Suite struct NotionTodoNotesMappingTests {
    private func resolvedSelect() throws -> NotionResolvedMapping {
        let schema = try NotionFixtures.decodeSchema(NotionFixtures.selectSchema)
        return try NotionTodoMapper.resolve(NotionTodoMapper.detect(schema), schema: schema).get()
    }

    private func richText(_ value: NotionJSONValue?, property: String = "Notes") -> [NotionJSONValue]? {
        guard case .object(let properties)? = value, case .object(let column)? = properties[property],
              case .array(let objects)? = column["rich_text"] else { return nil }
        return objects
    }

    private func contents(_ objects: [NotionJSONValue]) -> [String] {
        objects.compactMap { object in
            guard case .object(let fields) = object, case .object(let text)? = fields["text"],
                  case .string(let content)? = text["content"] else { return nil }
            return content
        }
    }

    // MARK: Detection

    @Test func detectsTheColumnNamedNotesOverOtherTextColumns() throws {
        let schema = try NotionFixtures.decodeSchema(NotionFixtures.selectSchema)

        #expect(NotionTodoMapper.detect(schema).notesPropertyID == "nt1")
        #expect(try resolvedSelect().notesProperty == "Notes")
    }

    @Test func onlyNotesLikeNamesAreAutoDetectedCaseInsensitively() {
        let first = NotionDataSource(id: "d", title: "T", properties: [
            NotionPropertySchema(id: "t", name: "Name", type: "title"),
            NotionPropertySchema(id: "b", name: "Blurb", type: "rich_text"),
            NotionPropertySchema(id: "a", name: "Aside", type: "rich_text"),
        ])
        #expect(NotionTodoMapper.detect(first).notesPropertyID == nil)

        let named = NotionDataSource(id: "d", title: "T", properties: [
            NotionPropertySchema(id: "a", name: "Aside", type: "rich_text"),
            NotionPropertySchema(id: "d", name: "DESCRIPTION", type: "rich_text"),
        ])
        #expect(NotionTodoMapper.detect(named).notesPropertyID == "d")
    }

    @Test func databasesWithoutATextColumnHaveNoNotesMapping() throws {
        let schema = try NotionFixtures.decodeSchema(NotionFixtures.statusSchema)
        let mapping = NotionTodoMapper.detect(schema)

        #expect(mapping.notesPropertyID == nil)
        let resolved = try NotionTodoMapper.resolve(mapping, schema: schema).get()
        #expect(resolved.notesProperty == nil)
        #expect(NotionTodoMapper.notesProperties("hello", resolved: resolved) == nil)
    }

    @Test func aDeletedOrRetypedNotesColumnNeedsAttention() throws {
        let schema = try NotionFixtures.decodeSchema(NotionFixtures.selectSchema)
        var mapping = NotionTodoMapper.detect(schema)

        mapping.notesPropertyID = "gone"
        #expect(NotionTodoMapper.resolve(mapping, schema: schema) == .failure(.notesMissing))
        mapping.notesPropertyID = "due1"
        #expect(NotionTodoMapper.resolve(mapping, schema: schema) == .failure(.notesMissing))
    }

    @Test func mappingSavedBeforeNotesExistedStillDecodes() throws {
        let old = #"{"doneKind":"select","donePropertyID":"st%3A1","doneOptionName":"Done","filterValues":[]}"#

        let mapping = try JSONDecoder().decode(NotionTodoMapping.self, from: Data(old.utf8))

        #expect(mapping.notesPropertyID == nil)
        #expect(mapping.doneKind == .select)
    }

    // MARK: Reading

    @Test func multiPartRichTextJoinsIntoOneNote() throws {
        let pages = try [
            NotionFixtures.page(id: "a", title: "Essay", notes: ["Outline first. ", "Then draft", " the intro."]),
            NotionFixtures.page(id: "b", title: "Plain"),
        ].map(NotionFixtures.decodePage)

        let items = NotionTodoMapper.items(from: pages, resolved: try resolvedSelect(), listName: "To-Do")

        #expect(items.first { $0.id == "a" }?.notes == "Outline first. Then draft the intro.")
        #expect(items.first { $0.id == "b" }?.notes == nil)
    }

    // MARK: Writing

    @Test func shortNotesWriteOneTextObject() throws {
        let body = NotionTodoMapper.notesProperties("Call before noon", resolved: try resolvedSelect())

        #expect(body == ["Notes": ["rich_text": [["type": "text", "text": ["content": "Call before noon"]]]]])
    }

    @Test func emptyNotesWriteAnEmptyArray() throws {
        let body = NotionTodoMapper.notesProperties("", resolved: try resolvedSelect())

        #expect(body == ["Notes": ["rich_text": []]])
    }

    @Test func longNotesSplitIntoOrderedChunksWithNothingLostOrRepeated() throws {
        let text = (0..<4500).map { String($0 % 10) }.joined() + "end"

        let objects = try #require(richText(NotionTodoMapper.notesProperties(text, resolved: try resolvedSelect())))
        let parts = contents(objects)

        #expect(parts.count == 3)
        #expect(parts.map(\.count) == [2000, 2000, 503])
        #expect(parts.joined() == text)
    }

    @Test func chunksNeverSplitACharacterAndCountInUTF16() {
        // Each family emoji is one character and eleven UTF-16 units.
        let family = "👨‍👩‍👧‍👦"
        let text = String(repeating: family, count: 400)

        let chunks = NotionTodoMapper.richTextChunks(text)

        #expect(chunks.joined() == text)
        #expect(chunks.allSatisfy { $0.utf16.count <= NotionTodoMapper.maxRichTextLength })
        #expect(chunks.allSatisfy { $0.count * family.utf16.count == $0.utf16.count })
        #expect(chunks.count == 3)
    }

    @Test func chunkingIsBoundedAndHandlesEdges() {
        #expect(NotionTodoMapper.richTextChunks("").isEmpty)
        #expect(NotionTodoMapper.richTextChunks("abc", maxLength: 0).isEmpty)
        #expect(NotionTodoMapper.richTextChunks("abcdef", maxLength: 2) == ["ab", "cd", "ef"])
        #expect(NotionTodoMapper.richTextChunks("abcdefg", maxLength: 2, maxChunks: 2) == ["ab", "cd"])
        #expect(NotionTodoMapper.richTextChunks(String(repeating: "x", count: 2000)).count == 1)
        #expect(NotionTodoMapper.maxRichTextLength == 2000)
        #expect(NotionTodoMapper.maxRichTextObjects == 100)
    }

    // MARK: Cache

    @Test func cacheKeepsNotesAndReadsFilesWrittenBeforeNotes() async throws {
        let directory = NotionFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = NotionTodoCache(directory: directory)
        let items = [
            NookTodoItem(id: "a", title: "Essay", dueDate: nil, isCompleted: false, listName: "To-Do", notes: "Outline"),
            NookTodoItem(id: "b", title: "Plain", dueDate: nil, isCompleted: false, listName: "To-Do"),
        ]
        try await cache.save(NotionTodoSnapshot(
            dataSourceID: "ds", databaseTitle: "To-Do", savedAt: Date(timeIntervalSince1970: 0), items: items
        ))
        #expect(await cache.load()?.items == items)

        let old = #"{"dataSourceID":"ds","databaseTitle":"To-Do","savedAt":0,"tasks":[{"id":"a","title":"Essay"}]}"#
        try Data(old.utf8).write(to: directory.appendingPathComponent(NotionTodoCache.fileName))

        let loaded = try #require(await cache.load())
        #expect(loaded.items.map(\.id) == ["a"])
        #expect(loaded.items.first?.notes == nil)
    }

    @Test(arguments: ["en", "zh-Hans", "zh-Hant"])
    func notesStringsExist(locale: String) throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/OpenIslandApp/Resources/\(locale).lproj/Localizable.strings")
        let table = try #require(NSDictionary(contentsOf: file) as? [String: String])
        let keys = [
            "nook.todo.notes.placeholder", "nook.todo.notes.empty", "nook.todo.notes.save", "nook.todo.notes.back",
            "nook.todo.notes.unavailable", "nook.todo.notes.remindersAccess", "nook.todo.notion.notes.pickColumn",
            "nook.todo.notion.mapping.notes", NotionTodoState.needsAttention(.notesMissing).messageKey,
            NotionTodoActionError.notesFailed.messageKey, NotionTodoActionError.notesTooLong.messageKey,
            "nook.todo.notes.conflict",
        ]
        for key in keys {
            #expect(table[key] != nil, "missing \(locale) string for \(key)")
        }
    }
}

private let notesTestPages = [
    NotionFixtures.page(id: "a", title: "Write essay", notes: ["Old outline"]),
    NotionFixtures.page(id: "b", title: "Call mom"),
]

@MainActor
@Suite struct NotionTodoNotesServiceTests {
    typealias Harness = NotionTodoServiceTests.Harness

    private func notes(_ harness: Harness, _ id: String) -> String? {
        harness.service.items.first { $0.id == id }?.notes
    }

    @Test func loadedTasksCarryNotesAndTheSourceCanEditThem() async throws {
        let harness = try Harness()
        harness.serve(pages: notesTestPages)

        await harness.activate()

        #expect(notes(harness, "a") == "Old outline")
        #expect(notes(harness, "b") == nil)
        #expect(harness.service.canEditNotes)
        #expect(harness.service.notesUnavailableReason == nil)
    }

    @Test func setNotesPatchesTheNotesColumnAndKeepsTheNewText() async throws {
        let harness = try Harness()
        harness.serve(pages: notesTestPages)
        await harness.activate()

        await harness.service.performSetNotes("Bring the charger", for: "b")

        #expect(notes(harness, "b") == "Bring the charger")
        #expect(harness.service.errorMessage == nil)
        let patch = try #require(harness.transport.requests.last { $0.httpMethod == "PATCH" })
        #expect(patch.route == "PATCH /v1/pages/b")
        let properties = patch.jsonBody["properties"] as? [String: Any]
        #expect(properties?.keys.sorted() == ["Notes"])
        let objects = (properties?["Notes"] as? [String: Any])?["rich_text"] as? [[String: Any]]
        #expect(objects?.count == 1)
        #expect((objects?.first?["text"] as? [String: String]) == ["content": "Bring the charger"])
    }

    @Test func clearingNotesSendsAnEmptyArray() async throws {
        let harness = try Harness()
        harness.serve(pages: notesTestPages)
        await harness.activate()

        await harness.service.performSetNotes("", for: "a")

        #expect(notes(harness, "a") == nil)
        let patch = try #require(harness.transport.requests.last { $0.httpMethod == "PATCH" })
        let properties = patch.jsonBody["properties"] as? [String: Any]
        let objects = (properties?["Notes"] as? [String: Any])?["rich_text"] as? [Any]
        #expect(objects?.isEmpty == true)
    }

    @Test func unchangedNotesSendNothing() async throws {
        let harness = try Harness()
        harness.serve(pages: notesTestPages)
        await harness.activate()
        let before = harness.transport.requests.count

        await harness.service.performSetNotes("Old outline", for: "a")
        await harness.service.performSetNotes("", for: "b")
        await harness.service.performSetNotes("x", for: "missing")

        #expect(harness.transport.requests.count == before)
    }

    @Test func failedSaveRestoresTheOldNotesWithAVisibleError() async throws {
        let harness = try Harness()
        harness.serve(pages: notesTestPages)
        await harness.activate()
        harness.transport.setResponder { _, _ in .json("{}", status: 500) }

        await harness.service.performSetNotes("New outline", for: "a")

        #expect(notes(harness, "a") == "Old outline")
        #expect(harness.service.actionError == .notesFailed)
        #expect(harness.service.errorMessage?.isEmpty == false)
        #expect(harness.service.pendingNotes.isEmpty)
        #expect(harness.service.canEditNotes)
    }

    @Test func forbiddenSaveTurnsEditingOffAndSaysWhy() async throws {
        let harness = try Harness()
        harness.serve(pages: notesTestPages)
        await harness.activate()
        harness.transport.setResponder { _, _ in .json("{\"code\":\"restricted_resource\"}", status: 403) }

        await harness.service.performSetNotes("New outline", for: "a")
        let sent = harness.transport.requests.count
        await harness.service.performSetNotes("Again", for: "a")

        #expect(notes(harness, "a") == "Old outline")
        #expect(harness.service.canEditNotes == false)
        #expect(harness.service.notesUnavailableReason == LanguageManager.shared.t("nook.todo.notion.error.cannotUpdate"))
        #expect(harness.transport.requests.count == sent)
    }

    @Test func noMappedColumnMeansReadOnlyWithAReason() async throws {
        let harness = try Harness()
        var mapping = NotionTodoMapper.detect(try NotionFixtures.decodeSchema(NotionFixtures.selectSchema))
        mapping.notesPropertyID = nil
        harness.defaults.set(try JSONEncoder().encode(mapping), forKey: NookNotionTodoService.Keys.mapping)
        // The user already chose "None" for the notes column.
        harness.defaults.set(true, forKey: NookNotionTodoService.Keys.notesColumnChecked)
        harness.serve(pages: notesTestPages)
        await harness.activate()
        let sent = harness.transport.requests.count

        await harness.service.performSetNotes("Hello", for: "a")

        #expect(harness.service.state == .ready)
        #expect(harness.service.canEditNotes == false)
        #expect(harness.service.notesUnavailableReason == LanguageManager.shared.t("nook.todo.notion.notes.pickColumn"))
        #expect(notes(harness, "a") == nil)
        #expect(harness.transport.requests.count == sent)
    }

    @Test func aSetupSavedBeforeNotesPicksUpTheNotesColumnOnce() async throws {
        let harness = try Harness()
        var mapping = NotionTodoMapper.detect(try NotionFixtures.decodeSchema(NotionFixtures.selectSchema))
        mapping.notesPropertyID = nil
        harness.defaults.set(try JSONEncoder().encode(mapping), forKey: NookNotionTodoService.Keys.mapping)
        harness.serve(pages: notesTestPages)

        await harness.activate()

        #expect(harness.service.mapping.notesPropertyID == "nt1")
        #expect(harness.service.canEditNotes)
        #expect(notes(harness, "a") == "Old outline")
        #expect(harness.defaults.bool(forKey: NookNotionTodoService.Keys.notesColumnChecked))

        // Choosing "None" afterwards sticks.
        harness.service.updateMapping { $0.notesPropertyID = nil }
        await harness.service.refreshTask?.value
        await harness.service.performRefresh()
        #expect(harness.service.mapping.notesPropertyID == nil)
        #expect(harness.service.canEditNotes == false)
    }

    @Test func offlineCacheIsReadOnly() async throws {
        let first = try Harness()
        first.serve(pages: notesTestPages)
        await first.activate()
        await first.settle()

        let transport = StubNotionTransport { _, _ in throw URLError(.notConnectedToInternet) }
        let service = NookNotionTodoService(
            defaults: first.defaults, transport: transport, tokenStore: first.tokens,
            cache: NotionTodoCache(directory: first.directory)
        )
        service.setActive(true)
        await service.setupTask?.value

        #expect(service.items.first { $0.id == "a" }?.notes == "Old outline")
        #expect(service.canEditNotes == false)
        #expect(service.notesUnavailableReason == LanguageManager.shared.t("nook.todo.notes.unavailable"))
    }

    /// Holds every update whose body mentions `marker` until the returned
    /// continuation finishes, like a slow request.
    private func holdUpdates(containing marker: String, on harness: Harness) -> AsyncStream<Void>.Continuation {
        let gate = AsyncStream<Void>.makeStream()
        harness.transport.setHold { request in
            guard request.httpMethod == "PATCH",
                  String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains(marker) == true else { return }
            for await _ in gate.stream {}
        }
        return gate.continuation
    }

    /// Waits until the stub has seen this many updates.
    private func waitForUpdates(_ count: Int, on harness: Harness) async {
        for _ in 0..<10_000 where harness.transport.requests.filter({ $0.httpMethod == "PATCH" }).count < count {
            await Task.yield()
        }
    }

    @Test func aLoadThatStartedBeforeTheWriteDoesNotOverwriteNewerNotes() async throws {
        let harness = try Harness()
        harness.serve(pages: notesTestPages)
        await harness.activate()
        let service = harness.service
        let release = holdUpdates(containing: "New outline", on: harness)

        let write = Task { @MainActor in await service.performSetNotes("New outline", for: "a") }
        await waitForUpdates(1, on: harness)
        #expect(service.pendingNotes["a"] == "New outline")
        // Notion has not applied the update yet: this load still reads the old text.
        await service.performRefresh()

        #expect(notes(harness, "a") == "New outline")
        #expect(service.state == .ready)

        let serialBefore = service.refreshSerial
        // From here on Notion has the new text.
        harness.serve(pages: [NotionFixtures.page(id: "a", title: "Write essay", notes: ["New outline"])])
        release.finish()
        await write.value

        #expect(notes(harness, "a") == "New outline")
        #expect(service.pendingNotes.isEmpty)
        // Loads still in flight are void, and a fresh one is queued.
        #expect(service.refreshSerial > serialBefore)
        await service.refreshTask?.value
        #expect(notes(harness, "a") == "New outline")
    }

    @Test func aSecondSaveWaitsForTheFirstAndGoesOutInOrder() async throws {
        let harness = try Harness()
        harness.serve(pages: notesTestPages)
        await harness.activate()
        let service = harness.service
        let release = holdUpdates(containing: "First", on: harness)

        let first = Task { @MainActor in await service.performSetNotes("First", for: "a") }
        await waitForUpdates(1, on: harness)
        await service.performSetNotes("Second", for: "a")

        // Only one update is on the wire. The newer text shows and waits.
        #expect(harness.transport.requests.filter { $0.httpMethod == "PATCH" }.count == 1)
        #expect(notes(harness, "a") == "Second")

        harness.serve(pages: [NotionFixtures.page(id: "a", title: "Write essay", notes: ["Second"])])
        release.finish()
        await first.value

        let bodies = harness.transport.requests.filter { $0.httpMethod == "PATCH" }
            .map { String(data: $0.httpBody ?? Data(), encoding: .utf8) ?? "" }
        #expect(bodies.count == 2)
        #expect(bodies.first?.contains("First") == true)
        #expect(bodies.last?.contains("Second") == true)
        #expect(notes(harness, "a") == "Second")
        #expect(service.pendingNotes.isEmpty && service.notesInFlight.isEmpty && service.queuedNotes.isEmpty)
        #expect(service.actionError == nil)
    }

    @Test func aFailedSaveHandsBackTheNewestTextAndRestoresWhatNotionHolds() async throws {
        let harness = try Harness()
        harness.serve(pages: notesTestPages)
        await harness.activate()
        let service = harness.service
        let hub = NookTodoHub(defaults: harness.defaults, notion: service)
        harness.transport.setResponder { _, _ in .json("{}", status: 500) }
        let release = holdUpdates(containing: "First", on: harness)

        let first = Task { @MainActor in await service.performSetNotes("First", for: "a") }
        await waitForUpdates(1, on: harness)
        await service.performSetNotes("Second", for: "a")
        release.finish()
        await first.value

        // Back to the last text Notion confirmed, never to the unsaved "First".
        #expect(notes(harness, "a") == "Old outline")
        #expect(service.actionError == .notesFailed)
        #expect(hub.noteDrafts["a"] == "Second")
        #expect(harness.transport.requests.filter { $0.httpMethod == "PATCH" }.count == 1)

        // The report outlives a refresh, and the kept text clears once it saves.
        harness.serve(pages: notesTestPages)
        await service.performRefresh()
        #expect(service.actionError == .notesFailed)
        await service.performSetNotes("Second", for: "a")
        #expect(service.actionError == nil)
        #expect(hub.noteDrafts["a"] == nil)
    }

    @Test func notesTooLongForNotionAreKeptNotCutShort() async throws {
        let harness = try Harness()
        harness.serve(pages: notesTestPages)
        await harness.activate()
        let hub = NookTodoHub(defaults: harness.defaults, notion: harness.service)
        let sent = harness.transport.requests.count
        let huge = String(repeating: "x", count: NotionTodoMapper.maxRichTextLength * NotionTodoMapper.maxRichTextObjects + 1)

        await harness.service.performSetNotes(huge, for: "a")

        #expect(harness.transport.requests.count == sent)
        #expect(harness.service.actionError == .notesTooLong)
        #expect(notes(harness, "a") == "Old outline")
        #expect(hub.noteDrafts["a"] == huge)
    }

    @Test func aSetupSavedBeforeNotesDoesNotAdoptAnUnnamedTextColumn() async throws {
        let schema = NotionFixtures.selectSchema.replacingOccurrences(of: "\"name\":\"Notes\"", with: "\"name\":\"Blurb\"")
            .replacingOccurrences(of: "\"Notes\":{", with: "\"Blurb\":{")
        let harness = try Harness()
        var mapping = NotionTodoMapper.detect(try NotionFixtures.decodeSchema(NotionFixtures.selectSchema))
        mapping.notesPropertyID = nil
        harness.defaults.set(try JSONEncoder().encode(mapping), forKey: NookNotionTodoService.Keys.mapping)
        harness.serve(schema: schema, pages: notesTestPages)

        await harness.activate()

        #expect(harness.service.state == .ready)
        #expect(harness.service.mapping.notesPropertyID == nil)
        #expect(harness.service.canEditNotes == false)
    }

    @Test func rateLimitBlocksNotesWrites() async throws {
        let harness = try Harness()
        harness.serve(pages: notesTestPages)
        await harness.activate()
        harness.transport.setResponder { _, _ in .json("{}", status: 429, headers: ["Retry-After": "120"]) }
        await harness.service.performSetNotes("One", for: "a")
        #expect(harness.service.actionError == .rateLimited)
        #expect(notes(harness, "a") == "Old outline")
        let sent = harness.transport.requests.count

        await harness.service.performSetNotes("Two", for: "a")

        #expect(harness.transport.requests.count == sent)
        #expect(notes(harness, "a") == "Old outline")
    }
}

@MainActor
@Suite struct NookTodoNotesCardTests {
    typealias Harness = NotionTodoServiceTests.Harness

    @Test func theNotesPageClosesWhenItsTaskLeavesTheList() async throws {
        let harness = try Harness()
        harness.serve(pages: [NotionFixtures.page(id: "a", title: "Write essay")])
        await harness.activate()

        #expect(NookTodoCard.openItem("a", in: harness.service)?.title == "Write essay")
        #expect(NookTodoCard.openItem(nil, in: harness.service) == nil)

        await harness.service.performComplete("a")

        #expect(NookTodoCard.openItem("a", in: harness.service) == nil)
    }

    @Test func itemsKeepCompilingWithoutNotes() {
        let item = NookTodoItem(id: "x", title: "T", dueDate: nil, isCompleted: false, listName: "L")
        #expect(item.notes == nil)
    }
}
