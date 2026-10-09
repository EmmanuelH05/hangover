import Foundation
import Testing
@testable import OpenIslandApp

@MainActor
@Suite struct NotionTodoServiceTests {
    /// Everything one service needs, with nothing shared between tests.
    @MainActor
    final class Harness {
        let transport: StubTodoTransport
        let tokens: InMemoryTodoTokenStore
        let defaults = NotionFixtures.makeDefaults()
        let directory = NotionFixtures.makeTempDirectory()
        let clock = TestClock()
        let cache: NotionTodoCache
        let service: NookNotionTodoService

        init(token: String? = NotionFixtures.token, configured: Bool = true, schema: String = NotionFixtures.selectSchema) throws {
            transport = StubTodoTransport()
            tokens = InMemoryTodoTokenStore(token: token)
            cache = NotionTodoCache(directory: directory)
            if configured {
                let mapping = NotionTodoMapper.detect(try NotionFixtures.decodeSchema(schema))
                defaults.set(NotionFixtures.dataSourceID, forKey: NookNotionTodoService.Keys.dataSourceID)
                defaults.set(try JSONEncoder().encode(mapping), forKey: NookNotionTodoService.Keys.mapping)
            }
            let clock = clock
            service = NookNotionTodoService(
                defaults: defaults, transport: transport, tokenStore: tokens, cache: cache, now: { clock.now }
            )
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }

        /// Serves the schema and the given pages, like a healthy workspace.
        func serve(schema: String = NotionFixtures.selectSchema, pages: [String]) {
            transport.setResponder { request, _ in
                switch request.route {
                case "GET /v1/data_sources/\(NotionFixtures.dataSourceID)": .json(schema)
                case "POST /v1/data_sources/\(NotionFixtures.dataSourceID)/query": .json(NotionFixtures.list(pages))
                case "GET /v1/users/me": .json("{\"object\":\"user\",\"name\":\"Nook\",\"bot\":{\"workspace_name\":\"Home\"}}")
                case "POST /v1/search": .json(NotionFixtures.list([schema]))
                default: .json(NotionFixtures.page(id: "written", title: "Written"))
                }
            }
        }

        func activate() async {
            service.setActive(true)
            await service.setupTask?.value
        }

        /// Lets fire-and-forget cache writes land.
        func settle() async {
            for _ in 0..<20 { await Task.yield() }
            _ = await cache.load()
        }
    }

    private static let threePages = [
        NotionFixtures.page(id: "a", title: "Write essay", due: "2026-01-01", priority: "High"),
        NotionFixtures.page(id: "b", title: "Call mom", priority: "Medium"),
        NotionFixtures.page(id: "c", title: "Laundry", priority: "Low"),
    ]

    // MARK: Idle and activation

    @Test func doesNothingUntilActivated() async throws {
        let harness = try Harness()

        harness.service.refresh()
        harness.service.add("Buy milk")
        harness.service.complete("a")
        await harness.service.performRefresh()
        await harness.service.connect(token: "ntn_other")

        #expect(harness.service.state == .inactive)
        #expect(harness.transport.requests.isEmpty)
        #expect(harness.tokens.readCount == 0)
        #expect(harness.tokens.token == NotionFixtures.token)
    }

    @Test func hubDefaultsToRemindersAndLeavesNotionIdle() async throws {
        let harness = try Harness()
        let hub = NookTodoHub(defaults: harness.defaults, notion: harness.service)

        hub.start(nook: NookModel())
        await harness.settle()

        #expect(hub.selectedKind == .reminders)
        #expect(harness.service.isActive == false)
        #expect(harness.transport.requests.isEmpty)
        #expect(harness.tokens.readCount == 0)
    }

    @Test func hubPersistsTheChoiceAndSwitchesNotionOnAndOff() async throws {
        let harness = try Harness()
        harness.serve(pages: Self.threePages)
        let hub = NookTodoHub(defaults: harness.defaults, notion: harness.service)
        hub.start(nook: NookModel())

        hub.selectedKind = .notion
        await harness.service.setupTask?.value

        #expect(harness.defaults.string(forKey: NookTodoHub.sourceKey) == "notion")
        #expect(harness.service.state == .ready)
        #expect(hub.source(reminders: NookRemindersService()) === harness.service)

        hub.selectedKind = .reminders

        #expect(harness.service.state == .inactive)
        #expect(harness.service.items.isEmpty)
        #expect(harness.service.hasToken == false)
        #expect(NookTodoHub(defaults: harness.defaults, notion: harness.service).selectedKind == .reminders)
    }

    @Test func activationLoadsTasksInDisplayOrder() async throws {
        let harness = try Harness()
        harness.serve(pages: Self.threePages.reversed())

        await harness.activate()

        #expect(harness.service.state == .ready)
        #expect(harness.service.items.map(\.title) == ["Write essay", "Call mom", "Laundry"])
        #expect(harness.service.displayName == "To-Do")
        #expect(harness.service.connection == .ready)
        #expect(harness.service.isShowingCachedItems == false)
        #expect(harness.service.canAdd && harness.service.canComplete)
        let query = try #require(harness.transport.requests(endingWith: "/query").first)
        let filter = query.jsonBody["filter"] as? [String: Any]
        #expect(filter?["property"] as? String == "Status")
        #expect((filter?["select"] as? [String: String]) == ["does_not_equal": "Done"])
    }

    @Test func missingTokenAndMissingDatabaseAreDistinctStates() async throws {
        let noToken = try Harness(token: nil)
        await noToken.activate()
        #expect(noToken.service.state == .noToken)
        #expect(noToken.transport.requests.isEmpty)

        let noDatabase = try Harness(configured: false)
        await noDatabase.activate()
        #expect(noDatabase.service.state == .noDatabase)
        #expect(noDatabase.transport.requests.isEmpty)

        let lockedKeychain = try Harness()
        lockedKeychain.tokens.failure = NookTodoKeychainError(status: -25308)
        await lockedKeychain.activate()
        #expect(lockedKeychain.service.state == .keychainUnavailable)
    }

    // MARK: Failure states

    @Test(arguments: [
        (401, NotionTodoState.invalidToken),
        (403, NotionTodoState.missingReadCapability),
        (404, NotionTodoState.databaseUnavailable),
        (429, NotionTodoState.rateLimited),
        (500, NotionTodoState.serverError),
    ])
    func httpFailuresMapToUserFacingStates(status: Int, expected: NotionTodoState) async throws {
        let harness = try Harness()
        harness.transport.setResponder { _, _ in .json("{\"code\":\"x\"}", status: status, headers: ["Retry-After": "90"]) }

        await harness.activate()

        #expect(harness.service.state == expected)
        #expect(harness.service.items.isEmpty)
        guard case .unavailable(let message) = harness.service.connection else {
            Issue.record("expected an unavailable connection")
            return
        }
        #expect(!message.isEmpty)
        #expect(!message.contains(NotionFixtures.token))
    }

    @Test func rateLimitHoldsRefreshesForRetryAfter() async throws {
        let harness = try Harness()
        harness.transport.setResponder { _, _ in .json("{}", status: 429, headers: ["Retry-After": "90"]) }
        await harness.activate()
        let baseline = harness.transport.requests.count

        harness.clock.advance(89)
        harness.service.refresh(.manual)
        harness.service.refresh(.opened)
        await harness.service.refreshTask?.value
        #expect(harness.transport.requests.count == baseline)

        harness.serve(pages: Self.threePages)
        harness.clock.advance(2)
        harness.service.refresh(.opened)
        await harness.service.refreshTask?.value
        #expect(harness.service.state == .ready)
        #expect(harness.service.items.count == 3)
    }

    @Test func offlineKeepsTheLastTasksAndFlagsThem() async throws {
        let harness = try Harness()
        harness.serve(pages: Self.threePages)
        await harness.activate()
        await harness.settle()

        harness.transport.setResponder { _, _ in throw URLError(.notConnectedToInternet) }
        await harness.service.performRefresh()

        #expect(harness.service.state == .offline)
        #expect(harness.service.items.count == 3)
        #expect(harness.service.isShowingCachedItems)
        #expect(harness.service.connection == .ready)
        // Backoff: the card opening again a moment later does not retry.
        let attempts = harness.transport.requests.count
        harness.clock.advance(2)
        harness.service.refresh()
        await harness.service.refreshTask?.value
        #expect(harness.transport.requests.count == attempts)
    }

    @Test func offlineStartShowsTheDiskCache() async throws {
        let first = try Harness()
        first.serve(pages: Self.threePages)
        await first.activate()
        await first.settle()
        let saved = try #require(await first.cache.load())
        #expect(saved.tasks.map(\.id) == ["a", "b", "c"])

        // A second launch with the same cache folder and no network.
        let transport = StubTodoTransport { _, _ in throw URLError(.notConnectedToInternet) }
        let service = NookNotionTodoService(
            defaults: first.defaults, transport: transport, tokenStore: first.tokens,
            cache: NotionTodoCache(directory: first.directory)
        )
        service.setActive(true)
        await service.setupTask?.value

        #expect(service.state == .offline)
        #expect(service.items.map(\.title) == ["Write essay", "Call mom", "Laundry"])
        #expect(service.isShowingCachedItems)
        // Without a live schema the widget cannot write.
        #expect(service.canComplete == false)
        #expect(service.canAdd == false)
    }

    @Test func offlineWithNothingCachedSaysSo() async throws {
        let harness = try Harness()
        harness.transport.setResponder { _, _ in throw URLError(.timedOut) }

        await harness.activate()

        #expect(harness.service.state == .offline)
        #expect(harness.service.isShowingCachedItems == false)
        #expect(harness.service.connection != .ready)
    }

    @Test func changedSchemaNeedsAttentionInsteadOfFailingSilently() async throws {
        let harness = try Harness()
        harness.serve(pages: Self.threePages)
        await harness.activate()

        // The Due column was deleted in Notion.
        let withoutDue = NotionFixtures.selectSchema.replacingOccurrences(of: "\"Due\":{", with: "\"Later\":{\"gone\":1},\"X\":{")
            .replacingOccurrences(of: "\"id\":\"due1\",\"name\":\"Due\",\"type\":\"date\"", with: "\"id\":\"zz\",\"name\":\"X\",\"type\":\"number\"")
        harness.serve(schema: withoutDue, pages: Self.threePages)
        await harness.service.performRefresh()

        #expect(harness.service.state == .needsAttention(.dueMissing))
        #expect(harness.service.items.isEmpty)
        #expect(harness.service.schema != nil)
        #expect(harness.service.connection != .ready)

        harness.service.updateMapping { $0.duePropertyID = nil }
        await harness.service.refreshTask?.value
        #expect(harness.service.state == .ready)
        #expect(harness.service.items.count == 3)
    }

    @Test func rejectedQueryNeedsAttention() async throws {
        let harness = try Harness()
        harness.transport.setResponder { request, _ in
            request.httpMethod == "GET"
                ? .json(NotionFixtures.selectSchema)
                : .json("{\"code\":\"validation_error\"}", status: 400)
        }

        await harness.activate()

        #expect(harness.service.state == .needsAttention(.queryRejected))
    }

    @Test func staleRefreshResultsAreDiscardedAfterSwitchingAway() async throws {
        let harness = try Harness()
        harness.serve(pages: Self.threePages)
        harness.service.setActive(true)
        harness.service.setActive(false)
        await harness.settle()

        #expect(harness.service.state == .inactive)
        #expect(harness.service.items.isEmpty)
        #expect(harness.tokens.readCount == 0)
    }

    // MARK: Complete

    @Test func completeRemovesTheRowAndPatchesThePage() async throws {
        let harness = try Harness()
        harness.serve(pages: Self.threePages)
        await harness.activate()

        await harness.service.performComplete("b")

        #expect(harness.service.items.map(\.id) == ["a", "c"])
        #expect(harness.service.errorMessage == nil)
        let patch = try #require(harness.transport.requests.last { $0.httpMethod == "PATCH" })
        #expect(patch.route == "PATCH /v1/pages/b")
        let properties = patch.jsonBody["properties"] as? [String: [String: [String: String]]]
        #expect(properties == ["Status": ["select": ["name": "Done"]]])
    }

    @Test func failedCompleteRestoresTheRowInPlaceWithAVisibleError() async throws {
        let harness = try Harness()
        harness.serve(pages: Self.threePages)
        await harness.activate()
        harness.transport.setResponder { request, _ in
            if request.httpMethod == "PATCH" { return .json("{}", status: 500) }
            return .json("{}")
        }

        await harness.service.performComplete("b")

        #expect(harness.service.items.map(\.id) == ["a", "b", "c"])
        #expect(harness.service.actionError == .completeFailed)
        #expect(harness.service.errorMessage?.isEmpty == false)
        #expect(harness.service.canComplete)
    }

    @Test func completeIsOptimisticWhileTheRequestIsInFlight() async throws {
        let harness = try Harness()
        harness.serve(pages: Self.threePages)
        await harness.activate()
        let gate = AsyncStream<Void>.makeStream()
        let service = harness.service
        harness.transport.setResponder { _, _ in throw URLError(.networkConnectionLost) }

        let task = Task { @MainActor in
            await service.performComplete("a")
            gate.continuation.finish()
        }
        // Runs up to the first suspension: the row is already gone.
        await Task.yield()
        let duringRequest = service.items.map(\.id)
        for await _ in gate.stream {}
        await task.value

        #expect(duringRequest == ["b", "c"] || duringRequest == ["a", "b", "c"])
        #expect(service.items.map(\.id) == ["a", "b", "c"])
        #expect(service.actionError == .completeFailed)
    }

    @Test func forbiddenCompleteDisablesTheControlAndSaysWhy() async throws {
        let harness = try Harness()
        harness.serve(pages: Self.threePages)
        await harness.activate()
        harness.transport.setResponder { _, _ in .json("{\"code\":\"restricted_resource\"}", status: 403) }

        await harness.service.performComplete("a")
        let requestsAfterFirst = harness.transport.requests.count
        await harness.service.performComplete("b")

        #expect(harness.service.items.count == 3)
        #expect(harness.service.canUpdate == false)
        #expect(harness.service.canComplete == false)
        #expect(harness.service.errorMessage?.isEmpty == false)
        #expect(harness.transport.requests.count == requestsAfterFirst)
        // Reading still works: the source stays usable.
        #expect(harness.service.state == .ready)
    }

    // MARK: Add

    @Test func addCreatesANotDonePageAndShowsIt() async throws {
        let harness = try Harness()
        harness.serve(pages: Self.threePages)
        await harness.activate()

        await harness.service.performAdd("  Buy milk  ")

        let post = try #require(harness.transport.requests.first { $0.route == "POST /v1/pages" })
        let properties = post.jsonBody["properties"] as? [String: Any]
        let status = properties?["Status"] as? [String: [String: String]]
        #expect(status == ["select": ["name": "To Do"]])
        #expect(String(data: post.httpBody ?? Data(), encoding: .utf8)?.contains("\"Buy milk\"") == true)
        #expect(harness.service.items.contains { $0.id == "written" && $0.title == "Buy milk" })
    }

    @Test func forbiddenAddDisablesAddingAndSaysWhy() async throws {
        let harness = try Harness()
        harness.serve(pages: Self.threePages)
        await harness.activate()
        harness.transport.setResponder { _, _ in .json("{}", status: 403) }

        await harness.service.performAdd("Buy milk")

        #expect(harness.service.canInsert == false)
        #expect(harness.service.canAdd == false)
        #expect(harness.service.addPlaceholder == LanguageManager.shared.t("nook.todo.notion.error.cannotInsert"))
        #expect(harness.service.items.count == 3)
    }

    @Test func blankTitlesAreNotSent() async throws {
        let harness = try Harness()
        harness.serve(pages: Self.threePages)
        await harness.activate()
        let before = harness.transport.requests.count

        await harness.service.performAdd("   \n ")

        #expect(harness.transport.requests.count == before)
    }

    // MARK: Connect and disconnect

    @Test func connectValidatesStoresTheTokenInTheKeychainOnlyAndListsDatabases() async throws {
        let harness = try Harness(token: nil, configured: false)
        harness.serve(pages: Self.threePages)
        await harness.activate()

        await harness.service.connect(token: "  ntn_pasted_secret\n")

        #expect(harness.tokens.token == "ntn_pasted_secret")
        #expect(harness.service.hasToken)
        #expect(harness.service.state == .noDatabase)
        #expect(harness.service.accountName == "Nook · Home")
        #expect(harness.service.databases == [NotionDatabaseChoice(id: NotionFixtures.dataSourceID, title: "To-Do")])
        #expect(harness.transport.requests.first?.route == "GET /v1/users/me")
        let persisted = harness.defaults.dictionaryRepresentation()
            .filter { $0.key.hasPrefix("nook.") }
            .map { "\($0.value)" }
            .joined()
        #expect(!persisted.contains("ntn_pasted_secret"))
    }

    @Test func rejectedTokenIsNotStored() async throws {
        let harness = try Harness(token: nil, configured: false)
        harness.transport.setResponder { _, _ in .json("{\"code\":\"unauthorized\"}", status: 401) }
        await harness.activate()

        await harness.service.connect(token: "ntn_wrong")
        await harness.service.connect(token: "has spaces inside")

        #expect(harness.tokens.token == nil)
        #expect(harness.service.hasToken == false)
        #expect(harness.service.state == .invalidToken)
        #expect(harness.transport.requests.count == 1)
    }

    @Test func selectingADatabaseDetectsItsMappingAndLoadsTasks() async throws {
        let harness = try Harness(configured: false)
        harness.serve(pages: Self.threePages)
        await harness.activate()
        await harness.service.loadDatabases()

        await harness.service.selectDatabase(NotionFixtures.dataSourceID)

        #expect(harness.service.state == .ready)
        #expect(harness.service.mapping.doneKind == .select)
        #expect(harness.service.mapping.doneOptionName == "Done")
        #expect(harness.service.items.count == 3)
        #expect(harness.defaults.string(forKey: NookNotionTodoService.Keys.dataSourceID) == NotionFixtures.dataSourceID)
        #expect(harness.defaults.data(forKey: NookNotionTodoService.Keys.mapping) != nil)
    }

    @Test func disconnectDeletesTheTokenTheCacheAndTheSetup() async throws {
        let harness = try Harness()
        harness.serve(pages: Self.threePages)
        await harness.activate()
        await harness.settle()
        #expect(await harness.cache.load() != nil)

        await harness.service.disconnect()
        await harness.settle()

        #expect(harness.tokens.token == nil)
        #expect(await harness.cache.load() == nil)
        #expect(harness.service.items.isEmpty)
        #expect(harness.service.state == .noToken)
        #expect(harness.service.selectedDatabaseID == nil)
        #expect(harness.defaults.string(forKey: NookNotionTodoService.Keys.dataSourceID) == nil)
        let before = harness.transport.requests.count
        harness.service.refresh(.manual)
        await harness.service.refreshTask?.value
        #expect(harness.transport.requests.count == before)
    }
}

/// Regressions found in review.
@MainActor
@Suite struct NotionTodoServiceRegressionTests {
    typealias Harness = NotionTodoServiceTests.Harness

    private static let pages = [
        NotionFixtures.page(id: "a", title: "Write essay"),
        NotionFixtures.page(id: "b", title: "Call mom"),
    ]

    @Test func rateLimitSurvivesSwitchingSourcesAndBlocksWrites() async throws {
        let harness = try Harness()
        harness.serve(pages: Self.pages)
        await harness.activate()
        harness.transport.setResponder { _, _ in .json("{}", status: 429, headers: ["Retry-After": "120"]) }
        await harness.service.performRefresh()
        #expect(harness.service.state == .rateLimited)
        let sent = harness.transport.requests.count

        await harness.service.performRefresh()
        await harness.service.performComplete("a")
        await harness.service.performAdd("Buy milk")
        await harness.service.loadDatabases()
        harness.service.setActive(false)
        harness.service.setActive(true)
        await harness.service.setupTask?.value

        #expect(harness.transport.requests.count == sent)
        #expect(harness.service.state == .rateLimited)

        harness.serve(pages: Self.pages)
        harness.clock.advance(121)
        await harness.service.performRefresh()
        #expect(harness.service.state == .ready)
    }

    @Test func mappingIsDetectedLaterWhenTheSchemaFetchFailedAtSelection() async throws {
        let harness = try Harness(configured: false)
        harness.serve(pages: Self.pages)
        await harness.activate()
        await harness.service.loadDatabases()
        harness.transport.setResponder { _, _ in throw URLError(.notConnectedToInternet) }
        await harness.service.selectDatabase(NotionFixtures.dataSourceID)
        #expect(harness.service.state == .offline)
        #expect(harness.service.mapping == NotionTodoMapping())

        harness.serve(pages: Self.pages)
        await harness.service.performRefresh()

        #expect(harness.service.state == .ready)
        #expect(harness.service.mapping.doneKind == .select)
        #expect(harness.service.items.count == 2)
    }

    @Test func aDatabaseWithNoDoneColumnStillAsksTheUserOnce() async throws {
        let noDone = """
        {"object":"data_source","id":"\(NotionFixtures.dataSourceID)","title":[{"plain_text":"Notes"}],
         "properties":{"Name":{"id":"title","name":"Name","type":"title","title":{}}}}
        """
        let harness = try Harness(configured: false)
        harness.defaults.set(NotionFixtures.dataSourceID, forKey: NookNotionTodoService.Keys.dataSourceID)
        harness.serve(schema: noDone, pages: [])

        await harness.activate()

        #expect(harness.service.state == .needsAttention(.doneNotChosen))
        #expect(harness.transport.requests.count == 1)
    }

    @Test func completedRowDoesNotComeBackFromALoadThatStartedEarlier() async throws {
        let harness = try Harness()
        harness.serve(pages: Self.pages)
        await harness.activate()
        let serialBefore = harness.service.refreshSerial

        await harness.service.performComplete("a")

        // Any load in flight during the update is now void, and a new one is queued.
        #expect(harness.service.refreshSerial > serialBefore)
        #expect(harness.service.refreshTask != nil)
        harness.serve(pages: [Self.pages[1]])
        await harness.service.refreshTask?.value
        #expect(harness.service.items.map(\.id) == ["b"])
    }

    @Test func rejectedStoredTokenKeepsTheTokenFieldThroughAnOfflineRetry() async throws {
        let harness = try Harness()
        harness.transport.setResponder { _, _ in .json("{}", status: 401) }
        await harness.activate()
        #expect(harness.service.state == .invalidToken)
        #expect(harness.service.tokenRejected)

        harness.transport.setResponder { _, _ in throw URLError(.notConnectedToInternet) }
        await harness.service.connect(token: "ntn_new")

        #expect(harness.service.state == .offline)
        #expect(harness.service.tokenRejected)
        let sent = harness.transport.requests.count
        harness.clock.advance(600)
        harness.service.refresh()
        harness.service.refresh(.background)
        await harness.service.refreshTask?.value
        #expect(harness.transport.requests.count == sent)

        harness.serve(pages: Self.pages)
        await harness.service.connect(token: "ntn_new")
        #expect(harness.service.tokenRejected == false)
        #expect(harness.tokens.token == "ntn_new")
        #expect(harness.service.state == .ready)
    }
}
