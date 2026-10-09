import Foundation
import Security
import Testing
@testable import OpenIslandApp

@Suite struct NotionClientTests {
    private func client(_ transport: StubTodoTransport) -> NotionClient {
        NotionClient(token: NotionFixtures.token, transport: transport)
    }

    // MARK: Requests

    @Test func requestsCarryTheTokenAndThePinnedVersion() async throws {
        let transport = StubTodoTransport { _, _ in
            .json("{\"object\":\"user\",\"name\":\"Nook\",\"type\":\"bot\",\"bot\":{\"workspace_name\":\"Home\"}}")
        }

        let user = try await client(transport).currentUser()

        let request = try #require(transport.requests.first)
        #expect(request.route == "GET /v1/users/me")
        #expect(request.url?.host == "api.notion.com")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(NotionFixtures.token)")
        #expect(request.value(forHTTPHeaderField: "Notion-Version") == NotionClient.apiVersion)
        #expect(NotionClient.apiVersion == "2026-03-11")
        #expect(user.displayName == "Nook · Home")
    }

    @Test func searchAsksForDataSources() async throws {
        let transport = StubTodoTransport { _, _ in
            .json(NotionFixtures.list([NotionFixtures.selectSchema, "{\"object\":\"page\"}"]))
        }

        let found = try await client(transport).searchDataSources(limit: 50)

        let request = try #require(transport.requests.first)
        #expect(request.route == "POST /v1/search")
        let filter = request.jsonBody["filter"] as? [String: String]
        #expect(filter == ["property": "object", "value": "data_source"])
        #expect(request.jsonBody["page_size"] as? Int == 50)
        #expect(found.map(\.title) == ["To-Do"])
    }

    @Test func idsStayInsideOnePathSegment() async throws {
        let transport = StubTodoTransport()

        await #expect(throws: NotionAPIError.self) {
            _ = try await client(transport).dataSource(id: "abc/../../users/me?x=1")
        }

        let url = try #require(transport.requests.first?.url)
        #expect(!url.absoluteString.contains("/users/me"))
        #expect(url.query == nil)
        #expect(url.absoluteString.hasPrefix("https://api.notion.com/v1/data_sources/abc%2F"))
    }

    // MARK: Pagination

    @Test func queryFollowsCursorsAndStopsAtTheLimit() async throws {
        let transport = StubTodoTransport { _, index in
            let ids = (0..<100).map { "page-\(index)-\($0)" }
            let pages = ids.map { NotionFixtures.page(id: $0, title: "T") }
            return .json(NotionFixtures.list(pages, hasMore: true, nextCursor: "cursor-\(index + 1)"))
        }

        let pages = try await client(transport).queryPages(
            dataSourceID: NotionFixtures.dataSourceID, filter: ["property": "Done", "checkbox": ["equals": false]],
            sorts: [["timestamp": "created_time", "direction": "ascending"]], limit: 150
        )

        #expect(pages.count == 150)
        #expect(transport.requests.count == 2)
        let first = transport.requests[0]
        let second = transport.requests[1]
        #expect(first.route == "POST /v1/data_sources/\(NotionFixtures.dataSourceID)/query")
        #expect(first.jsonBody["start_cursor"] == nil)
        #expect(first.jsonBody["page_size"] as? Int == 100)
        #expect(first.jsonBody["filter"] != nil)
        #expect((first.jsonBody["sorts"] as? [Any])?.count == 1)
        #expect(second.jsonBody["start_cursor"] as? String == "cursor-1")
        #expect(second.jsonBody["page_size"] as? Int == 50)
    }

    @Test func paginationIsBoundedEvenWhenTheServerNeverFinishes() async throws {
        let transport = StubTodoTransport { _, index in
            .json(NotionFixtures.list([NotionFixtures.page(id: "p\(index)", title: "T")], hasMore: true, nextCursor: "again"))
        }

        let pages = try await client(transport).queryPages(
            dataSourceID: NotionFixtures.dataSourceID, filter: nil, sorts: [], limit: 100
        )

        #expect(transport.requests.count == NotionClient.maxPagesPerCall)
        #expect(pages.count == NotionClient.maxPagesPerCall)
    }

    @Test func queryStopsWhenThereIsNoMore() async throws {
        let transport = StubTodoTransport { _, _ in
            .json(NotionFixtures.list([NotionFixtures.page(id: "only", title: "T")]))
        }

        let pages = try await client(transport).queryPages(
            dataSourceID: NotionFixtures.dataSourceID, filter: nil, sorts: [], limit: 100
        )

        #expect(pages.map(\.id) == ["only"])
        #expect(transport.requests.count == 1)
    }

    // MARK: Errors

    @Test(arguments: [
        (401, NotionAPIError.unauthorized),
        (403, NotionAPIError.forbidden),
        (404, NotionAPIError.notFound),
        (400, NotionAPIError.badRequest(code: "validation_error")),
        (500, NotionAPIError.server(status: 500)),
        (503, NotionAPIError.server(status: 503)),
    ])
    func statusCodesMapToTypedErrors(status: Int, expected: NotionAPIError) async {
        let transport = StubTodoTransport { _, _ in
            .json("{\"object\":\"error\",\"code\":\"validation_error\",\"message\":\"secret detail\"}", status: status)
        }

        await #expect(throws: expected) {
            _ = try await client(transport).dataSource(id: NotionFixtures.dataSourceID)
        }
    }

    @Test func rateLimitCarriesRetryAfter() async {
        let transport = StubTodoTransport { _, _ in .json("{}", status: 429, headers: ["Retry-After": "17"]) }

        await #expect(throws: NotionAPIError.rateLimited(retryAfter: 17)) {
            _ = try await client(transport).currentUser()
        }
    }

    @Test func rateLimitWithoutHeaderStillMaps() async {
        let transport = StubTodoTransport { _, _ in .json("{}", status: 429) }

        await #expect(throws: NotionAPIError.rateLimited(retryAfter: nil)) {
            _ = try await client(transport).currentUser()
        }
    }

    @Test func networkFailuresMapToOfflineAndCancellationStaysCancellation() async {
        let offline = StubTodoTransport { _, _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: NotionAPIError.offline) { _ = try await client(offline).currentUser() }

        let timeout = StubTodoTransport { _, _ in throw URLError(.timedOut) }
        await #expect(throws: NotionAPIError.offline) { _ = try await client(timeout).currentUser() }

        let cancelled = StubTodoTransport { _, _ in throw URLError(.cancelled) }
        await #expect(throws: NotionAPIError.cancelled) { _ = try await client(cancelled).currentUser() }
    }

    @Test func garbageBodyIsAnInvalidResponseNotACrash() async {
        let transport = StubTodoTransport { _, _ in .json("<html>gateway</html>") }

        await #expect(throws: NotionAPIError.invalidResponse) {
            _ = try await client(transport).dataSource(id: NotionFixtures.dataSourceID)
        }
    }

    // MARK: Writes

    @Test func createPageUsesADataSourceParent() async throws {
        let transport = StubTodoTransport { _, _ in .json(NotionFixtures.page(id: "new", title: "Buy milk")) }

        let page = try await client(transport).createPage(
            dataSourceID: NotionFixtures.dataSourceID,
            properties: ["Task": ["title": [["text": ["content": "Buy milk"]]]]]
        )

        let request = try #require(transport.requests.first)
        #expect(request.route == "POST /v1/pages")
        let parent = request.jsonBody["parent"] as? [String: String]
        #expect(parent == ["type": "data_source_id", "data_source_id": NotionFixtures.dataSourceID])
        #expect(page.id == "new")
    }

    @Test func updatePagePatchesProperties() async throws {
        let transport = StubTodoTransport { _, _ in .json(NotionFixtures.page(id: "p1", title: "T")) }

        try await client(transport).updatePage(id: "p1", properties: ["Done": ["checkbox": true]])

        let request = try #require(transport.requests.first)
        #expect(request.route == "PATCH /v1/pages/p1")
        let properties = request.jsonBody["properties"] as? [String: [String: Bool]]
        #expect(properties == ["Done": ["checkbox": true]])
    }
}

@Suite struct NotionRefreshGateTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func eachTriggerHasItsOwnSpacing() {
        var gate = NookTodoRefreshGate()
        #expect(gate.shouldRun(.background, now: start))
        gate.recordAttempt(now: start)
        gate.recordSuccess()

        #expect(!gate.shouldRun(.opened, now: start.addingTimeInterval(9)))
        #expect(gate.shouldRun(.opened, now: start.addingTimeInterval(10)))
        #expect(!gate.shouldRun(.timer, now: start.addingTimeInterval(59)))
        #expect(gate.shouldRun(.timer, now: start.addingTimeInterval(60)))
        #expect(!gate.shouldRun(.background, now: start.addingTimeInterval(299)))
        #expect(gate.shouldRun(.background, now: start.addingTimeInterval(300)))
        #expect(gate.shouldRun(.manual, now: start.addingTimeInterval(1)))
    }

    @Test func failuresBackOffExponentiallyUpToTheCap() {
        #expect(NookTodoRefreshGate.backoff(afterFailures: 1) == 5)
        #expect(NookTodoRefreshGate.backoff(afterFailures: 2) == 10)
        #expect(NookTodoRefreshGate.backoff(afterFailures: 3) == 20)
        #expect(NookTodoRefreshGate.backoff(afterFailures: 50) == NookTodoRefreshGate.backoffCap)

        var gate = NookTodoRefreshGate()
        gate.recordAttempt(now: start)
        gate.recordFailure(now: start)
        gate.recordFailure(now: start)
        gate.recordFailure(now: start)
        #expect(!gate.shouldRun(.opened, now: start.addingTimeInterval(19)))
        #expect(gate.shouldRun(.opened, now: start.addingTimeInterval(20)))
        // The user can always retry by hand during backoff.
        #expect(gate.shouldRun(.manual, now: start.addingTimeInterval(1)))

        gate.recordSuccess()
        #expect(gate.consecutiveFailures == 0)
    }

    @Test func rateLimitHoldsEveryTriggerForRetryAfter() {
        var gate = NookTodoRefreshGate()
        gate.recordAttempt(now: start)
        gate.recordRateLimit(retryAfter: 120, now: start)

        #expect(!gate.shouldRun(.manual, now: start.addingTimeInterval(119)))
        #expect(!gate.shouldRun(.opened, now: start.addingTimeInterval(119)))
        #expect(gate.shouldRun(.manual, now: start.addingTimeInterval(120)))

        gate.reset()
        gate.recordRateLimit(retryAfter: nil, now: start)
        #expect(!gate.shouldRun(.manual, now: start.addingTimeInterval(NookTodoRefreshGate.defaultRateLimitWait - 1)))
    }
}

@Suite struct NotionStorageTests {
    @Test func cacheRoundTripsAndClears() async throws {
        let directory = NotionFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = NotionTodoCache(directory: directory)
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let items = [
            NookTodoItem(id: "a", title: "Write essay", dueDate: due, isCompleted: false, listName: "To-Do"),
            NookTodoItem(id: "b", title: "Call mom", dueDate: nil, isCompleted: false, listName: "To-Do"),
        ]
        let snapshot = NotionTodoSnapshot(
            dataSourceID: NotionFixtures.dataSourceID, databaseTitle: "To-Do", savedAt: due, items: items
        )

        #expect(await cache.load() == nil)
        try await cache.save(snapshot)
        let loaded = await NotionTodoCache(directory: directory).load()

        #expect(loaded == snapshot)
        #expect(loaded?.items == items)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(NotionTodoCache.fileName).path))

        try await cache.clear()
        #expect(await cache.load() == nil)
        try await cache.clear()
    }

    @Test func corruptCacheReadsAsEmpty() async throws {
        let directory = NotionFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent(NotionTodoCache.fileName))

        #expect(await NotionTodoCache(directory: directory).load() == nil)
    }

    /// Writes to the real login keychain, which a test run does not do by
    /// default. `OPEN_ISLAND_KEYCHAIN_TESTS=1` turns it on.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OPEN_ISLAND_KEYCHAIN_TESTS"] == "1"))
    func keychainStoresReplacesAndDeletesTheToken() throws {
        let keychain = NookTodoKeychain(
            service: "app.openisland.tests.notion.\(UUID().uuidString)", account: "integration-token"
        )
        defer { try? keychain.delete() }

        do {
            #expect(try keychain.read() == nil)
            try keychain.save("ntn_first")
        } catch let error as NookTodoKeychainError where error.status == errSecInteractionNotAllowed
            || error.status == errSecNotAvailable || error.status == errSecNoDefaultKeychain {
            // No usable login keychain in this session (headless CI).
            return
        }
        #expect(try keychain.read() == "ntn_first")
        try keychain.save("ntn_second")
        #expect(try keychain.read() == "ntn_second")
        try keychain.delete()
        #expect(try keychain.read() == nil)
        try keychain.delete()
    }

    @Test func keychainServiceIsScopedToTheBundleIdentifier() {
        let keychain = NookTodoKeychain.notion
        #expect(keychain.service.hasSuffix(NookTodoKeychain.notionServiceSuffix))
        #expect(keychain.service.count > NookTodoKeychain.notionServiceSuffix.count)
        #expect(keychain.account == "integration-token")
    }
}
