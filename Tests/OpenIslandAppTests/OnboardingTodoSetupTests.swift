import EventKit
import Foundation
import Testing
@testable import OpenIslandApp

// The to-dos page connects a source for real (D44). Nothing here touches the
// network, the Keychain, the real settings or macOS: the services get a
// stub transport, an in-memory token store and a `MemoryDefaults`, and the
// Reminders permission is a made-up one.

// MARK: - The checklist, a pure function of the setup

@MainActor
struct OnboardingTodoChecklistTests {
    private func steps(_ source: NookTodoSourceKind, _ setup: OnboardingTodoSetup) -> [OnboardingTodoStep] {
        OnboardingTodoChecklist.steps(source: source, setup: setup)
    }

    private func done(_ source: NookTodoSourceKind, _ setup: OnboardingTodoSetup) -> [Bool] {
        steps(source, setup).map(\.isDone)
    }

    private let database = OnboardingTodoChoice(id: "db1", title: "To-Do")

    // MARK: Notion

    @Test func notionStartsWithNothingTickedAndOpensTheIntegrationAndTheFieldTogether() {
        let list = steps(.notion, OnboardingTodoSetup())

        #expect(list.map(\.kind) == [.open, .connect, .share, .pick])
        #expect(list.map(\.isDone) == [false, false, false, false])
        // The page the first step opens and the field of the second are
        // used together. The later two wait.
        #expect(list.map(\.isActive) == [true, true, false, false])
    }

    @Test func notionTicksTheFirstTwoStepsTogetherWhenTheServiceIsConnected() {
        let setup = OnboardingTodoSetup(isConnected: true, accountName: "Nook")
        let list = steps(.notion, setup)

        #expect(list.map(\.isDone) == [true, true, false, false])
        #expect(list.map(\.isActive) == [false, false, true, false])
    }

    @Test func notionTicksSharingOnceADatabaseIsListed() {
        var setup = OnboardingTodoSetup(isConnected: true, accountName: "Nook")
        setup.hasLoadedChoices = true
        #expect(done(.notion, setup) == [true, true, false, false], "an empty list is not shared yet")

        setup.choices = [database]
        let list = steps(.notion, setup)
        #expect(list.map(\.isDone) == [true, true, true, false])
        #expect(list.map(\.isActive) == [false, false, false, true])
    }

    @Test func notionTicksThePickOnlyWhenTheChosenDatabaseHasLoadedItsTasks() {
        var setup = OnboardingTodoSetup(isConnected: true, choices: [database], hasLoadedChoices: true)
        setup.chosenID = database.id
        #expect(done(.notion, setup) == [true, true, true, false], "chosen but not loaded")

        setup.taskCount = 4
        let list = steps(.notion, setup)
        #expect(list.map(\.isDone) == [true, true, true, true])
        #expect(list.allSatisfy { !$0.isActive })
    }

    @Test func aZeroTaskLoadStillTicksThePick() {
        let setup = OnboardingTodoSetup(
            isConnected: true, choices: [database], hasLoadedChoices: true, chosenID: database.id, taskCount: 0
        )
        #expect(done(.notion, setup).last == true)
    }

    @Test func theMessageSitsUnderTheLastStepThatIsActive() {
        let message = OnboardingTodoMessage(text: "Notion rejected the token.", isProblem: true)
        let fresh = steps(.notion, OnboardingTodoSetup(message: message))
        #expect(fresh.map(\.showsMessage) == [false, true, false, false], "under the field")

        let connected = OnboardingTodoSetup(isConnected: true, message: message)
        #expect(steps(.notion, connected).map(\.showsMessage) == [false, false, true, false])

        let picked = OnboardingTodoSetup(
            isConnected: true, choices: [database], hasLoadedChoices: true, chosenID: database.id, taskCount: 2,
            message: message
        )
        #expect(steps(.notion, picked).map(\.showsMessage) == [false, false, false, true], "nothing is active")

        #expect(steps(.notion, OnboardingTodoSetup()).allSatisfy { !$0.showsMessage })
    }

    // MARK: TickTick

    @Test func tickTickHasItsOwnThreeSteps() {
        #expect(steps(.tickTick, OnboardingTodoSetup()).map(\.kind) == [.open, .connect, .pick])
        #expect(done(.tickTick, OnboardingTodoSetup()) == [false, false, false])

        let connected = OnboardingTodoSetup(isConnected: true, choices: [database], chosenID: database.id)
        #expect(done(.tickTick, connected) == [true, true, false], "the inbox is chosen, its tasks are not in yet")

        var loaded = connected
        loaded.taskCount = 7
        #expect(done(.tickTick, loaded) == [true, true, true])
    }

    @Test func tickTickNeedsNoShareStep() {
        #expect(!OnboardingTodoChecklist.kinds(for: .tickTick).contains(.share))
    }

    // MARK: Reminders

    @Test func remindersHasOneStepThatTicksWhenAccessIsGranted() {
        for (access, isDone) in [
            (OnboardingRemindersAccess.notAsked, false), (.refused, false), (.granted, true),
        ] {
            let list = steps(.reminders, OnboardingTodoSetup(remindersAccess: access))
            #expect(list.map(\.kind) == [.allow])
            #expect(list.map(\.isDone) == [isDone], "\(access)")
            #expect(list.map(\.isActive) == [!isDone])
        }
    }

    @Test func eachEventKitAnswerReadsAsAskedGrantedOrRefused() {
        #expect(OnboardingTodoConnector.access(for: .notDetermined) == .notAsked)
        #expect(OnboardingTodoConnector.access(for: .fullAccess) == .granted)
        for refused in [EKAuthorizationStatus.denied, .restricted, .writeOnly] {
            #expect(OnboardingTodoConnector.access(for: refused) == .refused)
        }
    }

    // MARK: The choices

    @Test func theChosenOneStaysInTheShortList() {
        let all = (1...10).map { OnboardingTodoChoice(id: "\($0)", title: "List \($0)") }
        var setup = OnboardingTodoSetup(choices: all, chosenID: "2")
        #expect(OnboardingTodoStepRow.visibleChoices(of: setup, limit: 4).map(\.id) == ["1", "2", "3", "4"])

        setup.chosenID = "9"
        #expect(OnboardingTodoStepRow.visibleChoices(of: setup, limit: 4).map(\.id) == ["1", "2", "3", "9"])

        setup.choices = Array(all.prefix(3))
        #expect(OnboardingTodoStepRow.visibleChoices(of: setup, limit: 4).map(\.id) == ["1", "2", "3"])
    }

    @Test func theLoadedLineHasAFormForNoneOneAndMany() {
        #expect(OnboardingTodoChecklist.loadedKey(count: 0) == "onboarding.todos.loaded.zero")
        #expect(OnboardingTodoChecklist.loadedKey(count: 1) == "onboarding.todos.loaded.one")
        #expect(OnboardingTodoChecklist.loadedKey(count: 12) == "onboarding.todos.loaded.other")
    }

    // MARK: The services' sentences

    @MainActor
    @Test func everyNotionStateHasASentenceOrIsPartOfTheChecklist() {
        let lang = LanguageManager.shared
        let quiet: [NotionTodoState] = [.inactive, .noToken, .noDatabase, .ready]
        let problems: [NotionTodoState] = [
            .keychainUnavailable, .invalidToken, .databaseUnavailable, .missingReadCapability,
            .rateLimited, .offline, .serverError, .needsAttention(.doneNotChosen),
        ]
        for state in quiet { #expect(OnboardingTodoMessage.notion(state, lang: lang) == nil, "\(state)") }
        for state in problems {
            let message = OnboardingTodoMessage.notion(state, lang: lang)
            #expect(message?.isProblem == true, "\(state)")
            #expect(message?.text == lang.t(state.messageKey))
            #expect(message?.text != state.messageKey, "\(state) has no sentence")
        }
        let connecting = OnboardingTodoMessage.notion(.connecting, lang: lang)
        #expect(connecting?.isProblem == false)
    }

    @MainActor
    @Test func everyTickTickStateHasASentenceOrIsPartOfTheChecklist() {
        let lang = LanguageManager.shared
        for state in [TickTickTodoState.inactive, .noToken, .ready] {
            #expect(OnboardingTodoMessage.tickTick(state, lang: lang) == nil, "\(state)")
        }
        let problems: [TickTickTodoState] = [
            .keychainUnavailable, .invalidToken, .connectFailed, .listUnavailable, .rejected,
            .forbidden, .rateLimited, .offline, .serverError,
        ]
        for state in problems {
            let message = OnboardingTodoMessage.tickTick(state, lang: lang)
            #expect(message?.isProblem == true, "\(state)")
            #expect(message?.text != state.messageKey, "\(state) has no sentence")
        }
        #expect(OnboardingTodoMessage.tickTick(.connecting, lang: lang)?.isProblem == false)
    }
}

// MARK: - A connect that drives the page's value

@MainActor
struct OnboardingTodoConnectorTests {
    private static let secret = "ntn_pasted_secret_value"

    private func connector(
        notion: NookNotionTodoService? = nil,
        tickTick: NookTickTickTodoService? = nil,
        reminders: NookRemindersService = NookRemindersService(
            access: FakeEventKitPermission(status: .notDetermined).access
        ),
        source: NookTodoSourceKind
    ) -> OnboardingTodoConnector {
        let hub = NookTodoHub(defaults: MemoryDefaults(), notion: notion, tickTick: tickTick)
        hub.selectedKind = source
        return OnboardingTodoConnector(hub: hub, reminders: reminders, lang: LanguageManager.shared)
    }

    // MARK: Notion

    @Test func aNotionConnectThatWorksTicksTheFirstTwoStepsAndNamesTheAccount() async throws {
        let harness = try NotionTodoServiceTests.Harness(token: nil, configured: false)
        harness.serve(pages: [])
        await harness.activate()
        let connector = connector(notion: harness.service, source: .notion)
        #expect(connector.setup().isConnected == false)

        await connector.connect(token: Self.secret)

        let setup = connector.setup()
        #expect(setup.isConnected)
        #expect(setup.accountName == "Nook · Home")
        #expect(setup.choices == [OnboardingTodoChoice(id: NotionFixtures.dataSourceID, title: "To-Do")])
        let list = OnboardingTodoChecklist.steps(source: .notion, setup: setup)
        #expect(list.map(\.isDone) == [true, true, true, false])
        // The secret went to the Keychain's store and nowhere else.
        #expect(harness.tokens.token == Self.secret)
    }

    @Test func aNotionConnectThatFailsKeepsTheFieldUpAndShowsTheServicesSentence() async throws {
        let harness = try NotionTodoServiceTests.Harness(token: nil, configured: false)
        harness.transport.setResponder { _, _ in .json("{\"code\":\"unauthorized\"}", status: 401) }
        await harness.activate()
        let connector = connector(notion: harness.service, source: .notion)

        await connector.connect(token: "ntn_wrong")

        let setup = connector.setup()
        #expect(setup.isConnected == false)
        #expect(setup.message?.isProblem == true)
        #expect(setup.message?.text == LanguageManager.shared.t(NotionTodoState.invalidToken.messageKey))
        let list = OnboardingTodoChecklist.steps(source: .notion, setup: setup)
        #expect(list.map(\.isDone) == [false, false, false, false])
        #expect(list.first { $0.kind == .connect }?.isActive == true)
        #expect(list.first { $0.kind == .connect }?.showsMessage == true)
        #expect(harness.tokens.token == nil)
    }

    @Test func pickingTheDatabaseLoadsItsTasksAndTicksTheLastStep() async throws {
        let harness = try NotionTodoServiceTests.Harness(token: nil, configured: false)
        harness.serve(pages: [
            NotionFixtures.page(id: "a", title: "Write essay"),
            NotionFixtures.page(id: "b", title: "Call mom"),
        ])
        await harness.activate()
        let connector = connector(notion: harness.service, source: .notion)
        await connector.connect(token: Self.secret)

        await connector.choose(NotionFixtures.dataSourceID)

        let setup = connector.setup()
        #expect(setup.chosenID == NotionFixtures.dataSourceID)
        #expect(setup.taskCount == 2)
        #expect(OnboardingTodoChecklist.steps(source: .notion, setup: setup).map(\.isDone) == [true, true, true, true])
    }

    @Test func aDatabaseWhoseColumnsNeedAttentionSaysSoAndOffersSettings() async throws {
        // A database with a title and nothing that could mark a task done.
        let bare = """
        {"object":"data_source","id":"\(NotionFixtures.dataSourceID)","title":[{"plain_text":"Notes"}],
         "properties":{"Name":{"id":"title","name":"Name","type":"title","title":{}}}}
        """
        let harness = try NotionTodoServiceTests.Harness(token: nil, configured: false)
        harness.serve(schema: bare, pages: [])
        await harness.activate()
        let connector = connector(notion: harness.service, source: .notion)
        await connector.connect(token: Self.secret)

        await connector.choose(NotionFixtures.dataSourceID)

        let setup = connector.setup()
        #expect(setup.needsColumns)
        #expect(setup.message?.isProblem == true)
        #expect(setup.message?.text == LanguageManager.shared.t("nook.todo.notion.issue.doneNotChosen"))
        #expect(setup.taskCount == nil)
        let list = OnboardingTodoChecklist.steps(source: .notion, setup: setup)
        #expect(list.last?.isDone == false)
        #expect(list.last?.showsMessage == true)
    }

    @Test func aConnectedNotionWithNothingSharedSaysSo() async throws {
        let harness = try NotionTodoServiceTests.Harness(token: nil, configured: false)
        harness.transport.setResponder { request, _ in
            switch request.route {
            case "GET /v1/users/me": .json("{\"object\":\"user\",\"name\":\"Nook\"}")
            default: .json(NotionFixtures.list([]))
            }
        }
        await harness.activate()
        let connector = connector(notion: harness.service, source: .notion)

        await connector.connect(token: Self.secret)

        let setup = connector.setup()
        #expect(setup.isConnected)
        #expect(setup.hasLoadedChoices)
        #expect(setup.choices.isEmpty)
        #expect(setup.message?.text == LanguageManager.shared.t("onboarding.todos.notion.noneShared"))
        #expect(setup.message?.isProblem == false)
        #expect(OnboardingTodoChecklist.steps(source: .notion, setup: setup).map(\.isDone) == [true, true, false, false])
    }

    // MARK: Check again

    @Test func checkAgainListsTheDatabasesAShareAddedSinceTheLastTime() async throws {
        let harness = try NotionTodoServiceTests.Harness(token: nil, configured: false)
        harness.transport.setResponder { request, _ in
            request.route == "GET /v1/users/me"
                ? .json("{\"object\":\"user\",\"name\":\"Nook\"}")
                : .json(NotionFixtures.list([]))
        }
        await harness.activate()
        let connector = connector(notion: harness.service, source: .notion)
        await connector.connect(token: Self.secret)
        #expect(connector.setup().choices.isEmpty)

        harness.serve(pages: [])
        await connector.checkAgain()

        #expect(connector.setup().choices.count == 1)
    }

    // MARK: TickTick

    @Test func aTickTickConnectThatWorksListsTheInboxFirstAndLoadsItsTasks() async {
        let harness = TickTickHarness(token: nil)
        harness.serve(
            inbox: [TickTickFixtures.task(id: "t1", title: "One"), TickTickFixtures.task(id: "t2", title: "Two")],
            projects: [TickTickFixtures.project(id: TickTickFixtures.workID, name: "Work")]
        )
        await harness.activate()
        let connector = connector(tickTick: harness.service, source: .tickTick)

        await connector.connect(token: "tt_pasted_secret_value")

        let setup = connector.setup()
        #expect(setup.isConnected)
        #expect(setup.accountName == nil)
        #expect(setup.choices.map(\.id) == [TickTickClient.inboxID, TickTickFixtures.workID])
        #expect(setup.chosenID == TickTickClient.inboxID)
        #expect(setup.taskCount == 2)
        #expect(OnboardingTodoChecklist.steps(source: .tickTick, setup: setup).map(\.isDone) == [true, true, true])
        #expect(harness.tokens.token == "tt_pasted_secret_value")
    }

    @Test func aTickTickConnectThatFailsShowsTheServicesSentence() async {
        let harness = TickTickHarness(token: nil)
        harness.transport.setResponder { _, _ in .json("{\"error\":\"invalid_token\"}", status: 401) }
        await harness.activate()
        let connector = connector(tickTick: harness.service, source: .tickTick)

        await connector.connect(token: "tt_wrong")

        let setup = connector.setup()
        #expect(setup.isConnected == false)
        #expect(setup.message?.text == LanguageManager.shared.t(TickTickTodoState.invalidToken.messageKey))
        #expect(OnboardingTodoChecklist.steps(source: .tickTick, setup: setup).allSatisfy { !$0.isDone })
    }

    @Test func choosingAnotherTickTickListLoadsItsTasks() async {
        let harness = TickTickHarness(token: nil)
        harness.serve(
            projects: [TickTickFixtures.project(id: TickTickFixtures.workID, name: "Work")],
            work: TickTickFixtures.projectData(
                project: TickTickFixtures.project(id: TickTickFixtures.workID, name: "Work"),
                tasks: [TickTickFixtures.task(id: "w1", title: "Ship it", projectID: TickTickFixtures.workID)]
            )
        )
        await harness.activate()
        let connector = connector(tickTick: harness.service, source: .tickTick)
        await connector.connect(token: "tt_pasted_secret_value")

        await connector.choose(TickTickFixtures.workID)

        let setup = connector.setup()
        #expect(setup.chosenID == TickTickFixtures.workID)
        #expect(setup.taskCount == 1)
    }

    // MARK: The secret

    /// The secret passes through the page's door and the service writes it
    /// to the Keychain's store. Neither the setup the page reads nor the
    /// state the tour keeps holds it, and nothing is saved in the settings.
    @Test func theSecretIsNotInTheToursStateOrTheSettingsAfterAConnect() async throws {
        let harness = try NotionTodoServiceTests.Harness(token: nil, configured: false)
        harness.serve(pages: [])
        await harness.activate()
        let connector = connector(notion: harness.service, source: .notion)
        let tour = OnboardingTour(
            startingAt: .todos,
            state: {
                var state = OnboardingState()
                state.todoSource = .notion
                state.todoSetup = connector.setup()
                return state
            },
            actions: OnboardingActions(connectTodo: { token in
                Task { @MainActor in await connector.connect(token: token) }
            })
        )

        tour.actions.connectTodo(Self.secret)
        // The connect runs in a task of its own, as it does in the app.
        for _ in 0..<200 where tour.state.todoSetup.accountName == nil { await Task.yield() }

        #expect(tour.state.todoSetup.isConnected)
        #expect(!"\(tour.state)".contains(Self.secret))
        #expect(!"\(tour.picks)".contains(Self.secret))
        #expect(!"\(connector.setup())".contains(Self.secret))
        let saved = harness.defaults.dictionaryRepresentation().map { "\($0.value)" }.joined()
        #expect(!saved.contains(Self.secret))
        #expect(harness.tokens.token == Self.secret)
    }

    @Test func theSetupTypeHasNoFieldThatCouldHoldASecret() {
        let fields = Mirror(reflecting: OnboardingTodoSetup()).children.compactMap(\.label)
        #expect(!fields.contains { $0.lowercased().contains("token") || $0.lowercased().contains("secret") })
    }

    // MARK: Reminders

    @Test func theRemindersButtonAsksOnceAndARefusalShowsWhereToChangeIt() async {
        let permission = FakeEventKitPermission(status: .notDetermined, answer: .denied)
        let reminders = NookRemindersService(access: permission.access)
        let connector = connector(reminders: reminders, source: .reminders)
        #expect(connector.setup().remindersAccess == .notAsked)
        #expect(connector.setup().message == nil)
        #expect(permission.requestCount == 0, "reading the setup asks nothing")

        await connector.allowReminders()

        #expect(permission.requestCount == 1)
        let setup = connector.setup()
        #expect(setup.remindersAccess == .refused)
        #expect(setup.message?.isProblem == true)
        #expect(setup.message?.text == LanguageManager.shared.t("onboarding.todos.reminders.refused"))
        #expect(OnboardingTodoChecklist.steps(source: .reminders, setup: setup).map(\.isDone) == [false])

        await connector.allowReminders()
        #expect(permission.requestCount == 1, "macOS is not asked a second time")
    }

    @Test func readingAnyConnectedSetupAsksNothingOfMacOS() {
        let permission = FakeEventKitPermission(status: .notDetermined)
        let reminders = NookRemindersService(access: permission.access)
        for source in NookTodoSourceKind.allCases {
            _ = connector(reminders: reminders, source: source).setup()
        }
        #expect(permission.requestCount == 0)
    }
}
