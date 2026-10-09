import Foundation
import Security
import Testing
@testable import OpenIslandApp

@MainActor
@Suite struct TickTickTodoServiceTests {
    private static let inbox = [
        TickTickFixtures.task(id: "a", title: "Write essay", due: "2026-10-10T17:00:00+0000", content: "five pages"),
        TickTickFixtures.task(id: "b", title: "Call mom", sortOrder: 1),
        TickTickFixtures.task(id: "c", title: "Laundry", sortOrder: 2),
    ]
    private static let projects = [
        TickTickFixtures.project(id: TickTickFixtures.workID, name: "Work"),
        TickTickFixtures.project(id: "old", name: "Archived", closed: true),
        TickTickFixtures.project(id: "notes", name: "Journal", kind: "NOTE"),
        TickTickFixtures.project(id: "home", name: "apartment"),
    ]
    private static let workData = TickTickFixtures.projectData(
        project: TickTickFixtures.project(id: TickTickFixtures.workID, name: "Work"),
        tasks: [TickTickFixtures.task(id: "w1", title: "Ship it", projectID: TickTickFixtures.workID)]
    )

    private var inboxName: String { LanguageManager.shared.t("nook.todo.ticktick.inbox") }

    // MARK: Idle and activation

    @Test func doesNothingUntilActivated() async {
        let harness = TickTickHarness()

        harness.service.refresh()
        harness.service.add("Buy milk")
        harness.service.complete("a")
        await harness.service.performRefresh()
        await harness.service.connect(token: "tt_other")
        await harness.service.selectList(TickTickFixtures.workID)

        #expect(harness.service.state == .inactive)
        #expect(harness.transport.requests.isEmpty)
        #expect(harness.tokens.readCount == 0)
        #expect(harness.tokens.token == TickTickFixtures.token)
    }

    @Test func withNoTokenItAsksForOneAndSendsNothing() async {
        let harness = TickTickHarness(token: nil)

        await harness.activate()

        #expect(harness.service.state == .noToken)
        #expect(harness.service.hasToken == false)
        #expect(harness.transport.requests.isEmpty)
        #expect(harness.service.connection == .unavailable(
            message: LanguageManager.shared.t("nook.todo.ticktick.state.noToken")
        ))
    }

    @Test func aKeychainThatRefusesIsReported() async {
        let harness = TickTickHarness()
        harness.tokens.failure = NookTodoKeychainError(status: errSecInteractionNotAllowed)

        await harness.activate()

        #expect(harness.service.state == .keychainUnavailable)
        #expect(harness.transport.requests.isEmpty)
    }

    @Test func activationLoadsTheInboxByDefault() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox)

        await harness.activate()

        #expect(harness.routes == ["GET /open/v1/project/inbox/data"])
        #expect(harness.service.state == .ready)
        #expect(harness.service.items.map(\.id) == ["a", "b", "c"])
        #expect(harness.service.items.first?.notes == "five pages")
        #expect(harness.service.displayName == inboxName)
        #expect(harness.service.connection == .ready)
        #expect(harness.service.canAdd && harness.service.canComplete && harness.service.canEditNotes)
        #expect(harness.service.inboxProjectID == TickTickFixtures.inboxRealID)
    }

    @Test func aSavedListIsLoadedInPlaceOfTheInbox() async {
        let harness = TickTickHarness(listID: TickTickFixtures.workID)
        harness.serve(inbox: Self.inbox, work: Self.workData)

        await harness.activate()

        #expect(harness.routes == ["GET /open/v1/project/\(TickTickFixtures.workID)/data"])
        #expect(harness.service.items.map(\.id) == ["w1"])
        #expect(harness.service.displayName == "Work")
        #expect(harness.defaults.string(forKey: NookTickTickTodoService.Keys.listName) == "Work")
    }

    @Test func turningItOffForgetsTheTokenAndTheRows() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox)
        await harness.activate()

        harness.service.setActive(false)

        #expect(harness.service.state == .inactive)
        #expect(harness.service.items.isEmpty)
        #expect(harness.service.hasToken == false)
        #expect(harness.service.token == nil)
        // The Keychain item itself stays for the next time.
        #expect(harness.tokens.token == TickTickFixtures.token)
    }

    // MARK: Hub

    @Test func theHubSwitchesTickTickOnAndNotionStaysIdle() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox)
        let notionTokens = InMemoryTodoTokenStore(token: "ntn_x")
        let notion = NookNotionTodoService(
            defaults: harness.defaults, transport: StubTodoTransport(), tokenStore: notionTokens,
            cache: NotionTodoCache(directory: harness.directory)
        )
        let hub = NookTodoHub(defaults: harness.defaults, notion: notion, tickTick: harness.service)
        hub.start(nook: NookModel())
        #expect(harness.service.isActive == false)

        hub.selectedKind = .tickTick
        await harness.service.setupTask?.value

        #expect(harness.defaults.string(forKey: NookTodoHub.sourceKey) == "ticktick")
        #expect(harness.service.state == .ready)
        #expect(hub.source(reminders: NookRemindersService()) === harness.service)
        #expect(notion.isActive == false)
        #expect(notionTokens.readCount == 0)

        hub.selectedKind = .reminders

        #expect(harness.service.isActive == false)
        #expect(harness.service.state == .inactive)
    }

    @Test func aSavedChoiceOfTickTickComesBack() {
        let defaults = MemoryDefaults()
        defaults.set("ticktick", forKey: NookTodoHub.sourceKey)

        #expect(NookTodoHub(defaults: defaults).selectedKind == .tickTick)
    }

    @Test func aFailedNoteReachesTheHubAsADraft() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox)
        let hub = NookTodoHub(defaults: harness.defaults, tickTick: harness.service)
        hub.start(nook: NookModel())
        hub.selectedKind = .tickTick
        await harness.service.setupTask?.value
        harness.transport.setResponder { _, _ in StubTodoResponse(status: 500) }

        await harness.service.performSetNotes("ten pages", for: "a")

        #expect(hub.noteDrafts["a"] == "ten pages")
        #expect(harness.service.items.first { $0.id == "a" }?.notes == "five pages")
        #expect(harness.service.actionError == .notesFailed)
    }

    // MARK: Connecting

    @Test func connectingChecksTheTokenStoresItAndLoads() async {
        let harness = TickTickHarness(token: nil)
        harness.serve(inbox: Self.inbox, projects: Self.projects)
        await harness.activate()

        await harness.service.connect(token: "  tt_fresh\n")

        #expect(harness.routes == ["GET /open/v1/project", "GET /open/v1/project/inbox/data"])
        #expect(harness.transport.requests.allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") == "Bearer tt_fresh"
        })
        #expect(harness.tokens.token == "tt_fresh")
        #expect(harness.service.hasToken)
        #expect(harness.service.state == .ready)
        #expect(harness.service.items.count == 3)
        // Archived lists and lists of notes are left out. Sorted by name.
        #expect(harness.service.lists == [
            TickTickListChoice(id: "home", name: "apartment"),
            TickTickListChoice(id: TickTickFixtures.workID, name: "Work"),
        ])
        #expect(harness.service.hasLoadedLists)
    }

    @Test func aRejectedTokenIsNotStored() async {
        let harness = TickTickHarness(token: nil)
        harness.transport.setResponder { _, _ in .json("{\"error\":\"invalid_token\"}", status: 401) }
        await harness.activate()

        await harness.service.connect(token: "tt_wrong")

        #expect(harness.service.state == .invalidToken)
        #expect(harness.tokens.token == nil)
        #expect(harness.service.hasToken == false)
        #expect(harness.routes == ["GET /open/v1/project"])
    }

    @Test func aTokenWithASpaceInItIsNeverSent() async {
        let harness = TickTickHarness(token: nil)
        await harness.activate()

        await harness.service.connect(token: "tt two words")

        #expect(harness.service.state == .invalidToken)
        #expect(harness.transport.requests.isEmpty)
    }

    @Test func connectingOfflineKeepsTheTokenOut() async {
        let harness = TickTickHarness(token: nil)
        harness.transport.setResponder { _, _ in throw URLError(.notConnectedToInternet) }
        await harness.activate()

        await harness.service.connect(token: "tt_fresh")

        #expect(harness.service.state == .offline)
        #expect(harness.tokens.token == nil)
        #expect(harness.service.hasToken == false)
    }

    @Test(arguments: [500, 429, 404, 400])
    func aConnectTickTickCannotAnswerPromisesNoRetry(status: Int) async {
        let harness = TickTickHarness(token: nil)
        harness.transport.setResponder { _, _ in StubTodoResponse(status: status) }
        await harness.activate()

        await harness.service.connect(token: "tt_fresh")

        #expect(harness.service.state == .connectFailed)
        #expect(harness.tokens.token == nil)
        #expect(harness.service.hasToken == false)
    }

    @Test func aListFromAnotherAccountFallsBackToTheInbox() async {
        let harness = TickTickHarness(token: nil, listID: "gone")
        harness.defaults.set("Old list", forKey: NookTickTickTodoService.Keys.listName)
        harness.serve(inbox: Self.inbox, projects: Self.projects)
        await harness.activate()

        await harness.service.connect(token: "tt_fresh")

        #expect(harness.service.selectedListID == TickTickClient.inboxID)
        #expect(harness.defaults.string(forKey: NookTickTickTodoService.Keys.listID) == nil)
        #expect(harness.defaults.string(forKey: NookTickTickTodoService.Keys.listName) == nil)
        #expect(harness.routes.last == "GET /open/v1/project/inbox/data")
    }

    @Test func disconnectingRemovesTheTokenTheCopyAndTheSetup() async {
        let harness = TickTickHarness(listID: TickTickFixtures.workID)
        harness.serve(inbox: Self.inbox, work: Self.workData)
        await harness.activate()
        await harness.settle()
        #expect(await harness.cache.load() != nil)

        await harness.service.disconnect()

        #expect(harness.tokens.token == nil)
        #expect(harness.service.state == .noToken)
        #expect(harness.service.items.isEmpty)
        #expect(harness.service.selectedListID == TickTickClient.inboxID)
        #expect(harness.defaults.string(forKey: NookTickTickTodoService.Keys.listID) == nil)
        #expect(await harness.cache.load() == nil)
        #expect(harness.service.tokenRemovalFailed == false)
    }

    @Test func aKeychainThatWillNotLetGoKeepsTheSessionAndSaysSo() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox)
        await harness.activate()
        harness.tokens.failure = NookTodoKeychainError(status: errSecInteractionNotAllowed)

        await harness.service.disconnect()

        // The token is still stored, which is why Disconnect stays on screen.
        #expect(harness.service.tokenRemovalFailed)
        #expect(harness.service.hasToken)
        #expect(harness.service.state == .ready)
        #expect(harness.service.items.count == 3)
        #expect(harness.tokens.token == TickTickFixtures.token)

        harness.tokens.failure = nil
        await harness.service.disconnect()

        #expect(harness.service.tokenRemovalFailed == false)
        #expect(harness.service.hasToken == false)
        #expect(harness.tokens.token == nil)
    }

    // MARK: Lists

    @Test func pickingAListLoadsItAndRemembersIt() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox, projects: Self.projects, work: Self.workData)
        await harness.activate()
        await harness.service.loadLists()

        await harness.service.selectList(TickTickFixtures.workID)

        #expect(harness.service.items.map(\.id) == ["w1"])
        #expect(harness.service.displayName == "Work")
        #expect(harness.service.state == .ready)
        #expect(harness.defaults.string(forKey: NookTickTickTodoService.Keys.listID) == TickTickFixtures.workID)

        await harness.service.selectList(TickTickClient.inboxID)

        #expect(harness.service.items.map(\.id) == ["a", "b", "c"])
        #expect(harness.service.displayName == inboxName)
        #expect(harness.defaults.string(forKey: NookTickTickTodoService.Keys.listID) == nil)
    }

    @Test func aListThatIsGoneSaysSo() async {
        let harness = TickTickHarness(listID: TickTickFixtures.workID)
        harness.serve(inbox: Self.inbox, work: nil)

        await harness.activate()

        #expect(harness.service.state == .listUnavailable)
        #expect(harness.service.items.isEmpty)
        #expect(harness.service.canAdd == false)
    }

    @Test func aRequestTickTickWillNotTakeIsNotCalledAMissingList() async {
        let harness = TickTickHarness()
        harness.transport.setResponder { _, _ in StubTodoResponse(status: 400) }

        await harness.activate()

        #expect(harness.service.state == .rejected)
        #expect(harness.service.items.isEmpty)
    }

    @Test func aListMarkedReadOnlyInTheListOfListsTurnsTheWritesOff() async {
        let harness = TickTickHarness()
        // The list's own answer says nothing about who may write.
        harness.serve(
            inbox: Self.inbox,
            projects: [TickTickFixtures.project(id: TickTickFixtures.workID, name: "Team", permission: "comment")],
            work: TickTickFixtures.projectData(tasks: [
                TickTickFixtures.task(id: "w1", title: "Ship it", projectID: TickTickFixtures.workID),
            ])
        )
        await harness.activate()
        await harness.service.loadLists()

        await harness.service.selectList(TickTickFixtures.workID)

        #expect(harness.service.state == .ready)
        #expect(harness.service.isListReadOnly)
        #expect(harness.service.canComplete == false)
    }

    @Test func aListSharedReadOnlyTurnsTheWritesOff() async {
        let harness = TickTickHarness(listID: TickTickFixtures.workID)
        harness.serve(work: TickTickFixtures.projectData(
            project: TickTickFixtures.project(id: TickTickFixtures.workID, name: "Team", permission: "read"),
            tasks: [TickTickFixtures.task(id: "w1", title: "Ship it", projectID: TickTickFixtures.workID)]
        ))
        await harness.activate()
        let readOnly = LanguageManager.shared.t("nook.todo.ticktick.error.readOnly")

        #expect(harness.service.state == .ready)
        #expect(harness.service.items.count == 1)
        #expect(harness.service.canAdd == false)
        #expect(harness.service.canComplete == false)
        #expect(harness.service.canEditNotes == false)
        #expect(harness.service.errorMessage == readOnly)
        #expect(harness.service.addPlaceholder == readOnly)
        #expect(harness.service.notesUnavailableReason == readOnly)

        await harness.service.performComplete("w1")
        await harness.service.performAdd("New")

        #expect(harness.routes.count == 1)
        #expect(harness.service.items.count == 1)
    }

    @Test func aFailedReloadOfTheListsLeavesTheTasksAloneAndSaysSo() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox, projects: Self.projects)
        await harness.activate()
        await harness.service.loadLists()
        #expect(harness.service.lists.count == 2)
        #expect(harness.service.listsLoadFailed == false)
        harness.transport.setResponder { _, _ in StubTodoResponse(status: 403) }

        await harness.service.loadLists()

        #expect(harness.service.state == .ready)
        #expect(harness.service.items.count == 3)
        #expect(harness.service.isLoadingLists == false)
        #expect(harness.service.listsLoadFailed)
        #expect(harness.service.lists.count == 2)

        harness.serve(inbox: Self.inbox, projects: Self.projects)
        await harness.service.loadLists()
        #expect(harness.service.listsLoadFailed == false)
    }

    // MARK: Failures

    @Test func aTokenThatStoppedWorkingDropsTheRows() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox)
        await harness.activate()
        harness.transport.setResponder { _, _ in StubTodoResponse(status: 401) }

        await harness.service.performRefresh()

        #expect(harness.service.state == .invalidToken)
        #expect(harness.service.tokenRejected)
        #expect(harness.service.items.isEmpty)

        // Nothing but a manual refresh is sent until a new token connects.
        let sent = harness.transport.requests.count
        harness.clock.advance(3600)
        harness.service.refresh()
        harness.service.refreshOnTimer()
        await harness.settle()
        #expect(harness.transport.requests.count == sent)
    }

    @Test func aGoodLoadClearsARejectionThatDidNotLast() async {
        let harness = TickTickHarness()
        harness.transport.setResponder { _, _ in StubTodoResponse(status: 401) }
        await harness.activate()
        #expect(harness.service.tokenRejected)

        harness.serve(inbox: Self.inbox)
        harness.service.recheck()
        await harness.settle()

        #expect(harness.service.state == .ready)
        #expect(harness.service.tokenRejected == false)
        // Automatic refreshes run again.
        let sent = harness.transport.requests.count
        harness.clock.advance(NookTodoRefreshGate.timerSpacing + 1)
        harness.service.refreshOnTimer()
        await harness.settle()
        #expect(harness.transport.requests.count == sent + 1)
    }

    @Test func offlineKeepsTheLastRowsOnScreen() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox)
        await harness.activate()
        harness.transport.setResponder { _, _ in throw URLError(.notConnectedToInternet) }

        await harness.service.performRefresh()

        #expect(harness.service.state == .offline)
        #expect(harness.service.items.count == 3)
        #expect(harness.service.isShowingCachedItems)
        #expect(harness.service.connection == .ready)
    }

    @Test func aRateLimitStopsEveryRequestUntilItPasses() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox)
        await harness.activate()
        harness.transport.setResponder { _, _ in StubTodoResponse(status: 429, headers: ["Retry-After": "120"]) }
        await harness.service.performRefresh()
        #expect(harness.service.state == .rateLimited)
        #expect(harness.service.items.count == 3)
        // The rows stay and the writes are off, which keeps a typed task
        // from going nowhere.
        #expect(harness.service.canAdd == false)
        #expect(harness.service.canComplete == false)
        let sent = harness.transport.requests.count

        harness.clock.advance(60)
        harness.service.refresh(.manual)
        await harness.settle()
        await harness.service.performComplete("a")
        await harness.service.performAdd("New")
        await harness.service.loadLists()

        #expect(harness.transport.requests.count == sent)
        #expect(harness.service.items.count == 3)
        #expect(harness.service.listsLoadFailed)

        harness.serve(inbox: Self.inbox)
        harness.clock.advance(61)
        harness.service.refresh(.manual)
        await harness.settle()

        #expect(harness.service.state == .ready)
        #expect(harness.service.canAdd)
    }

    @Test func aWriteThatHitsTheRateLimitTurnsTheWritesOff() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox)
        await harness.activate()
        let all = TickTickFixtures.projectData(tasks: Self.inbox)
        harness.transport.setResponder { request, _ in
            request.httpMethod == "POST" ? StubTodoResponse(status: 429, headers: ["Retry-After": "90"]) : .json(all)
        }

        await harness.service.performAdd("Buy milk")

        #expect(harness.service.actionError == .rateLimited)
        #expect(harness.service.state == .rateLimited)
        #expect(harness.service.canAdd == false)

        // "Refresh now" sends nothing while the wait is open and keeps the notice.
        harness.service.recheck()
        await harness.settle()
        #expect(harness.service.actionError == .rateLimited)
    }

    @Test func anOfflineStartShowsTheSavedCopyAndNoWrites() async {
        let first = TickTickHarness()
        first.serve(inbox: Self.inbox)
        await first.activate()
        await first.settle()

        let tokens = InMemoryTodoTokenStore(token: TickTickFixtures.token)
        let transport = StubTodoTransport { _, _ in throw URLError(.notConnectedToInternet) }
        let service = NookTickTickTodoService(
            defaults: first.defaults, transport: transport, tokenStore: tokens,
            cache: TickTickTodoCache(directory: first.directory)
        )
        service.setActive(true)
        await service.setupTask?.value

        #expect(service.state == .offline)
        #expect(service.items.map(\.id) == ["a", "b", "c"])
        #expect(service.isShowingCachedItems)
        #expect(service.canAdd == false)
        #expect(service.canComplete == false)
        #expect(service.canEditNotes == false)
        #expect(service.notesUnavailableReason == LanguageManager.shared.t("nook.todo.notes.unavailable"))
    }

    @Test func theSavedCopyOfAnotherListIsNotShown() async {
        let first = TickTickHarness()
        first.serve(inbox: Self.inbox)
        await first.activate()
        await first.settle()

        first.defaults.set(TickTickFixtures.workID, forKey: NookTickTickTodoService.Keys.listID)
        let service = NookTickTickTodoService(
            defaults: first.defaults,
            transport: StubTodoTransport { _, _ in throw URLError(.notConnectedToInternet) },
            tokenStore: InMemoryTodoTokenStore(token: TickTickFixtures.token),
            cache: TickTickTodoCache(directory: first.directory)
        )
        service.setActive(true)
        await service.setupTask?.value

        #expect(service.items.isEmpty)
        #expect(service.connection != .ready)
    }

    // MARK: Completing

    @Test func completingRemovesTheRowAndNamesTheTasksOwnList() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox)
        await harness.activate()
        harness.serve(inbox: Array(Self.inbox.dropFirst()))

        await harness.service.performComplete("a")
        await harness.settle()

        #expect(harness.routes.contains("POST /open/v1/project/\(TickTickFixtures.inboxRealID)/task/a/complete"))
        #expect(harness.service.items.map(\.id) == ["b", "c"])
        #expect(harness.service.actionError == nil)
        #expect(await harness.cache.load()?.tasks.map(\.id) == ["b", "c"])
    }

    @Test func aFailedCompletionPutsTheRowBack() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox)
        await harness.activate()
        harness.transport.setResponder { _, _ in StubTodoResponse(status: 500) }

        await harness.service.performComplete("b")

        #expect(harness.service.items.map(\.id) == ["a", "b", "c"])
        #expect(harness.service.actionError == .completeFailed)
        #expect(harness.service.errorMessage == LanguageManager.shared.t("nook.todo.ticktick.error.completeFailed"))
    }

    @Test func aTaskTickTickCannotFindIsNotCalledDone() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox)
        await harness.activate()
        let all = TickTickFixtures.projectData(tasks: Self.inbox)
        harness.transport.setResponder { request, _ in
            request.httpMethod == "POST" ? StubTodoResponse(status: 404) : .json(all)
        }

        await harness.service.performComplete("a")

        // It may have moved to another list, still open.
        #expect(harness.service.items.map(\.id) == ["a", "b", "c"])
        #expect(harness.service.actionError == .completeFailed)
    }

    @Test func aRefusedWriteTurnsTheWritesOffUntilRechecked() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox)
        await harness.activate()
        let all = TickTickFixtures.projectData(tasks: Self.inbox)
        harness.transport.setResponder { request, _ in
            request.httpMethod == "POST" ? StubTodoResponse(status: 403) : .json(all)
        }

        await harness.service.performComplete("a")

        #expect(harness.service.canWrite == false)
        #expect(harness.service.canComplete == false)
        #expect(harness.service.items.count == 3)
        #expect(harness.service.errorMessage == LanguageManager.shared.t("nook.todo.ticktick.error.readOnly"))

        harness.service.recheck()
        await harness.settle()

        #expect(harness.service.canWrite)
        #expect(harness.service.canComplete)
    }

    @Test func aRepeatingTaskComesBackWithItsNextDate() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox)
        await harness.activate()
        // TickTick answers a completed repeating task by moving it forward.
        harness.serve(inbox: [
            TickTickFixtures.task(id: "a", title: "Write essay", due: "2026-10-17T17:00:00+0000"),
        ] + Self.inbox.dropFirst())

        await harness.service.performComplete("a")
        await harness.settle()

        #expect(harness.service.items.map(\.id).contains("a"))
        #expect(harness.service.pendingCompletions.isEmpty)
    }

    // MARK: Adding

    @Test func addingToTheInboxNamesItsRealIDOnceKnown() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox)
        await harness.activate()

        await harness.service.performAdd("  Buy milk  ")
        await harness.settle()

        let request = harness.transport.requests(endingWith: "/open/v1/task").first
        #expect(request?.jsonBody as? [String: String]
            == ["title": "Buy milk", "projectId": TickTickFixtures.inboxRealID])
    }

    @Test func addingToAnEmptyInboxNamesNoList() async {
        let harness = TickTickHarness()
        harness.serve(inbox: [], written: TickTickFixtures.task(id: "new", title: "Buy milk"))
        await harness.activate()
        #expect(harness.service.inboxProjectID == nil)

        await harness.service.performAdd("Buy milk")

        let request = harness.transport.requests(endingWith: "/open/v1/task").first
        #expect(request?.jsonBody as? [String: String] == ["title": "Buy milk"])
        // The answer says what the inbox is called.
        #expect(harness.service.inboxProjectID == TickTickFixtures.inboxRealID)
        #expect(harness.service.rows.first { $0.item.id == "new" }?.projectID == TickTickFixtures.inboxRealID)
    }

    @Test func addingToAListNamesThatList() async {
        let harness = TickTickHarness(listID: TickTickFixtures.workID)
        harness.serve(work: Self.workData)
        await harness.activate()

        await harness.service.performAdd("Review PR")

        let request = harness.transport.requests(endingWith: "/open/v1/task").first
        #expect(request?.jsonBody as? [String: String]
            == ["title": "Review PR", "projectId": TickTickFixtures.workID])
        #expect(harness.service.items.map(\.id).contains("new"))
    }

    @Test func aFailedAddIsReportedAndAddsNoRow() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox)
        await harness.activate()
        harness.transport.setResponder { _, _ in StubTodoResponse(status: 500) }

        await harness.service.performAdd("Buy milk")

        #expect(harness.service.items.count == 3)
        #expect(harness.service.actionError == .addFailed)
    }

    @Test func aYesThatCannotBeReadIsCheckedAgainstTheList() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox, written: "")
        await harness.activate()

        // The task is not in the list afterwards: it was not added.
        await harness.service.performAdd("Buy milk")
        #expect(harness.service.actionError == .addFailed)
        #expect(harness.service.items.count == 3)

        // The task is in the list afterwards: it was.
        harness.serve(inbox: Self.inbox + [TickTickFixtures.task(id: "d", title: "Buy milk", sortOrder: 3)], written: "")
        await harness.service.performAdd("Buy milk")
        #expect(harness.service.actionError == nil)
        #expect(harness.service.items.map(\.id).contains("d"))
    }

    @Test func anEmptyTitleIsNotSentAndALongOneIsCut() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox)
        await harness.activate()
        let sent = harness.transport.requests.count

        await harness.service.performAdd("   \n ")
        #expect(harness.transport.requests.count == sent)

        await harness.service.performAdd(String(repeating: "x", count: 900))
        let title = (harness.transport.requests(endingWith: "/open/v1/task").first?.jsonBody["title"] as? String) ?? ""
        #expect(title.count == NookTickTickTodoService.maxTitleLength)
    }

    // MARK: Notes

    @Test func savingNotesSendsTheNoteAndKeepsItOnTheRow() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox)
        await harness.activate()
        var finished: [(String, String, Bool)] = []
        harness.service.onNotesWriteFinished = { id, text, saved in finished.append((id, text, saved)) }
        harness.serve(inbox: [
            TickTickFixtures.task(id: "a", title: "Write essay", due: "2026-10-10T17:00:00+0000", content: "ten pages"),
        ] + Self.inbox.dropFirst())

        await harness.service.performSetNotes("ten pages", for: "a")
        await harness.settle()

        // The task is read from its own list, then sent back whole.
        #expect(harness.routes.contains("GET /open/v1/project/\(TickTickFixtures.inboxRealID)/task/a"))
        let sent = harness.noteUpdates(for: "a").first ?? [:]
        #expect(sent["content"] as? String == "ten pages")
        #expect(sent["title"] as? String == "Kept title")
        #expect(sent["repeatFlag"] as? String == "RRULE:FREQ=MONTHLY;INTERVAL=1")
        #expect(harness.service.items.first { $0.id == "a" }?.notes == "ten pages")
        #expect(finished.count == 1)
        #expect(finished.first?.2 == true)
        #expect(harness.service.pendingNotes.isEmpty)
    }

    @Test func aChecklistTasksNoteGoesToDesc() async {
        let harness = TickTickHarness()
        harness.serve(inbox: [TickTickFixtures.task(id: "k", title: "Pack", kind: "CHECKLIST", desc: "for the trip")])
        await harness.activate()

        await harness.service.performSetNotes("", for: "k")

        let sent = harness.noteUpdates(for: "k").first ?? [:]
        #expect(sent["desc"] as? String == "")
        #expect(sent["content"] as? String == "old note")
    }

    @Test func unchangedNotesSendNothing() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox)
        await harness.activate()
        let sent = harness.transport.requests.count
        var saved: Bool?
        harness.service.onNotesWriteFinished = { _, _, result in saved = result }

        await harness.service.performSetNotes("five pages", for: "a")

        #expect(harness.transport.requests.count == sent)
        #expect(saved == true)
    }

    @Test func aFailedNoteGoesBackToWhatWasSaved() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox)
        await harness.activate()
        var finished: [(String, String, Bool)] = []
        harness.service.onNotesWriteFinished = { id, text, saved in finished.append((id, text, saved)) }
        harness.transport.setResponder { _, _ in throw URLError(.timedOut) }

        await harness.service.performSetNotes("ten pages", for: "a")

        #expect(harness.service.items.first { $0.id == "a" }?.notes == "five pages")
        #expect(harness.service.actionError == .notesFailed)
        #expect(finished.first?.1 == "ten pages")
        #expect(finished.first?.2 == false)
        #expect(harness.service.pendingNotes.isEmpty)
        #expect(harness.service.notesInFlight.isEmpty)
    }

    @Test func aNoteSavedWhileAnotherIsOnTheWireGoesOutNext() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox)
        await harness.activate()
        let gate = AsyncStream<Void>.makeStream()
        harness.transport.setHold { request in
            guard request.route == "POST /open/v1/task/a",
                  (request.jsonBody["content"] as? String) == "first" else { return }
            for await _ in gate.stream { break }
        }

        let first = Task { await harness.service.performSetNotes("first", for: "a") }
        while harness.noteUpdates(for: "a").isEmpty { await Task.yield() }
        await harness.service.performSetNotes("second", for: "a")
        #expect(harness.service.queuedNotes["a"] == "second")
        gate.continuation.yield()
        await first.value
        await harness.settle()

        let bodies = harness.noteUpdates(for: "a").compactMap { $0["content"] as? String }
        #expect(bodies == ["first", "second"])
        #expect(harness.service.queuedNotes.isEmpty)
        #expect(harness.service.notesInFlight.isEmpty)
    }

    // MARK: Refresh pacing

    @Test func openingTheCardAgainRightAwaySendsNothing() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox)
        await harness.activate()
        let sent = harness.transport.requests.count

        harness.service.refresh()
        await harness.settle()
        #expect(harness.transport.requests.count == sent)

        harness.clock.advance(NookTodoRefreshGate.openedSpacing + 1)
        harness.service.refresh()
        await harness.settle()
        #expect(harness.transport.requests.count == sent + 1)
    }

    @Test func aLoadThatLandsAfterASwitchOfListIsIgnored() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox, projects: Self.projects, work: Self.workData)
        await harness.activate()
        let gate = AsyncStream<Void>.makeStream()
        harness.transport.setHold { request in
            guard request.url?.path.hasSuffix("/project/inbox/data") == true else { return }
            for await _ in gate.stream { break }
        }

        let stale = Task { await harness.service.performRefresh() }
        while harness.transport.requests(endingWith: "/project/inbox/data").count < 2 { await Task.yield() }
        await harness.service.selectList(TickTickFixtures.workID)
        gate.continuation.yield()
        await stale.value

        #expect(harness.service.items.map(\.id) == ["w1"])
        #expect(harness.service.displayName == "Work")
    }
}
