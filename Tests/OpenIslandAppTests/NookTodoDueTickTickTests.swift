import Foundation
import Testing
@testable import OpenIslandApp

/// A date on a new TickTick task: an all-day `dueDate`, and the row shown at once (D69).
@MainActor
@Suite struct NookTodoDueTickTickTests {
    private typealias F = NookTodoDueFixtures

    private func makeClient(_ transport: StubTodoTransport) -> TickTickClient {
        TickTickClient(token: TickTickFixtures.token, transport: transport)
    }

    private func body(_ data: Data?) throws -> [String: Any] {
        let data = try #require(data)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: The payload

    @Test func aDatedTaskIsAllDayAtMidnightOfItsDayInItsZone() throws {
        let calendar = TickTickFixtures.calendar("America/Los_Angeles")

        let sent = try body(TickTickClient.creationBody(
            title: "Call mom", projectID: "p1", due: F.day(2026, 10, 16), calendar: calendar
        ))

        // Midnight of the 16th in Los Angeles is 7 in the morning in UTC.
        #expect(sent["dueDate"] as? String == "2026-10-16T07:00:00+0000")
        #expect(sent["isAllDay"] as? Bool == true)
        #expect(sent["timeZone"] as? String == "America/Los_Angeles")
        #expect(sent["title"] as? String == "Call mom")
        #expect(sent["projectId"] as? String == "p1")
        #expect(Set(sent.keys) == ["title", "projectId", "dueDate", "isAllDay", "timeZone"])
    }

    @Test func midnightFollowsTheZoneThroughTheClockChange() throws {
        // Los Angeles is on standard time from November 1, 2026.
        let calendar = TickTickFixtures.calendar("America/Los_Angeles")

        let sent = try body(TickTickClient.creationBody(
            title: "Call mom", projectID: nil, due: F.day(2026, 11, 2), calendar: calendar
        ))

        #expect(sent["dueDate"] as? String == "2026-11-02T08:00:00+0000")
    }

    @Test func aTaskWithNoDayCarriesNoDateFields() throws {
        let calendar = TickTickFixtures.calendar("America/Los_Angeles")

        let sent = try body(TickTickClient.creationBody(title: "Call mom", projectID: "p1", due: nil, calendar: calendar))

        #expect(sent as? [String: String] == ["title": "Call mom", "projectId": "p1"])
    }

    @Test func somethingThatIsNotADayCarriesNoDateFields() throws {
        let calendar = TickTickFixtures.calendar("America/Los_Angeles")

        for notADay in [F.day(2026, 2, 30), DateComponents(year: 2026, month: 10), DateComponents()] {
            let sent = try body(TickTickClient.creationBody(title: "Call mom", projectID: nil, due: notADay, calendar: calendar))
            #expect(sent as? [String: String] == ["title": "Call mom"])
        }
    }

    @Test func theDayComesBackTheSameFromTheTaskTickTickHolds() throws {
        // What is written is what the mapper reads, from any zone.
        let written = TickTickFixtures.calendar("America/Los_Angeles")
        let sent = try body(TickTickClient.creationBody(title: "x", projectID: nil, due: F.day(2026, 10, 16), calendar: written))
        let task = TickTickTask(
            id: "t", title: "x", dueDate: sent["dueDate"] as? String, isAllDay: true, timeZone: sent["timeZone"] as? String
        )

        for zone in ["America/Los_Angeles", "Asia/Tokyo", "Pacific/Auckland", "Europe/London"] {
            let reader = TickTickFixtures.calendar(zone)
            let read = TickTickTaskMapper.dueDate(of: task, calendar: reader)
            #expect(read == reader.date(from: DateComponents(year: 2026, month: 10, day: 16)), "read in \(zone)")
        }
    }

    // MARK: The client

    @Test func theClientSendsTheDateFieldsWithTheNewTask() async throws {
        let transport = StubTodoTransport { _, _ in .json(TickTickFixtures.task(id: "n", title: "Call mom")) }
        let calendar = TickTickFixtures.calendar("Asia/Tokyo")

        let created = try await makeClient(transport).createTask(
            title: "Call mom", projectID: "p1", due: F.day(2026, 10, 16), calendar: calendar
        )

        #expect(created?.id == "n")
        let sent = try #require(transport.requests.first).jsonBody
        // Midnight of the 16th in Tokyo is 3 in the afternoon of the 15th in UTC.
        #expect(sent["dueDate"] as? String == "2026-10-15T15:00:00+0000")
        #expect(sent["isAllDay"] as? Bool == true)
        #expect(sent["timeZone"] as? String == "Asia/Tokyo")
    }

    @Test func theClientStillSendsOnlyTitleAndListWithoutADay() async throws {
        let transport = StubTodoTransport { _, _ in .json(TickTickFixtures.task(id: "n", title: "Call mom")) }

        _ = try await makeClient(transport).createTask(title: "Call mom", projectID: "p1")

        #expect(transport.requests.first?.jsonBody as? [String: String] == ["title": "Call mom", "projectId": "p1"])
    }

    // MARK: The service

    /// What TickTick answers a create with: the task, with the date it kept.
    private func stored(day: DateComponents?, id: String = "new") throws -> String {
        guard let day else { return TickTickFixtures.task(id: id, title: "Buy milk") }
        let sent = try body(TickTickClient.creationBody(title: "Buy milk", projectID: nil, due: day, calendar: .current))
        return TickTickFixtures.task(
            id: id, title: "Buy milk", due: sent["dueDate"] as? String, allDay: true,
            timeZone: Calendar.current.timeZone.identifier
        )
    }

    @Test func addingWithADaySendsItAndShowsWhatTickTickStoredAtOnce() async throws {
        let harness = TickTickHarness()
        harness.serve(inbox: [], written: try stored(day: F.day(2026, 10, 16)))
        await harness.activate()

        await harness.service.performAdd("Buy milk", due: F.day(2026, 10, 16))

        let request = try #require(harness.transport.requests(endingWith: "/open/v1/task").first)
        let expected = try body(TickTickClient.creationBody(
            title: "Buy milk", projectID: nil, due: F.day(2026, 10, 16), calendar: .current
        ))
        #expect(request.jsonBody["dueDate"] as? String == expected["dueDate"] as? String)
        #expect(request.jsonBody["isAllDay"] as? Bool == true)
        #expect(request.jsonBody["timeZone"] as? String == Calendar.current.timeZone.identifier)
        let row = try #require(harness.service.items.first { $0.id == "new" })
        #expect(row.dueDate == NookTodoDay.date(from: F.day(2026, 10, 16), calendar: .current))
    }

    // MARK: What TickTick stored (D4)

    @Test func theRowShowsTheDayTickTickKeptWhenItIsNotTheDaySent() async throws {
        let harness = TickTickHarness()
        // Sent for the 16th, stored for the 17th.
        harness.serve(inbox: [], written: try stored(day: F.day(2026, 10, 17)))
        await harness.activate()

        let added = await harness.service.performAdd("Buy milk", due: F.day(2026, 10, 16))

        #expect(added)
        let row = try #require(harness.service.items.first { $0.id == "new" })
        #expect(row.dueDate == NookTodoDay.date(from: F.day(2026, 10, 17), calendar: .current))
        #expect(harness.service.errorMessage == nil, "a date was kept and nothing is missing")
    }

    @Test func aDateTickTickDidNotKeepIsReportedAndTheRowShowsNone() async throws {
        let harness = TickTickHarness()
        harness.serve(inbox: [], written: try stored(day: nil))
        await harness.activate()

        let added = await harness.service.performAdd("Buy milk", due: F.day(2026, 10, 16))

        #expect(added, "the task itself was added")
        #expect(harness.service.items.first { $0.id == "new" }?.dueDate == nil)
        #expect(harness.service.errorMessage == LanguageManager.shared.t("nook.todo.ticktick.error.addedWithoutDate"))
    }

    @Test func theMissingDateStaysReportedThroughTheReloadTheAddStarts() async throws {
        let harness = TickTickHarness()
        harness.serve(inbox: [TickTickFixtures.task(id: "new", title: "Buy milk")], written: try stored(day: nil))
        await harness.activate()

        await harness.service.performAdd("Buy milk", due: F.day(2026, 10, 16))
        await harness.settle()

        #expect(harness.service.errorMessage == LanguageManager.shared.t("nook.todo.ticktick.error.addedWithoutDate"))
    }

    @Test func aMissingDateStaysReportedAndIsNotANotesProblem() async throws {
        let harness = TickTickHarness()
        harness.serve(inbox: [TickTickFixtures.task(id: "new", title: "Buy milk")], written: try stored(day: nil))
        await harness.activate()

        await harness.service.performAdd("Buy milk", due: F.day(2026, 10, 16))
        await harness.settle()

        #expect(harness.service.actionError == .addedWithoutDate, "it outlives the reload the add starts")
        #expect(harness.service.actionError?.concernsNotes == false)
        #expect(harness.service.actionError?.survivesRefresh == true)
        #expect(!harness.service.notesSaveFailed, "the notes page goes on following the source")
    }

    @Test func aTaskSentWithNoDayIsNeverReportedAsMissingOne() async throws {
        let harness = TickTickHarness()
        harness.serve(inbox: [], written: try stored(day: nil))
        await harness.activate()

        await harness.service.performAdd("Buy milk")

        #expect(harness.service.errorMessage == nil)
    }

    @Test func theNextWriteClearsTheMissingDateLine() async throws {
        let harness = TickTickHarness()
        harness.serve(inbox: [], written: try stored(day: nil))
        await harness.activate()
        await harness.service.performAdd("Buy milk", due: F.day(2026, 10, 16))
        #expect(harness.service.errorMessage != nil)

        await harness.service.performAdd("Call mom")

        #expect(harness.service.errorMessage == nil)
    }

    @Test(arguments: HangoverBrandTests.languages)
    func theMissingDateLineIsInEveryLanguage(language: String) throws {
        let table = try HangoverBrandTests.table(language)
        let line = try #require(table["nook.todo.ticktick.error.addedWithoutDate"])

        #expect(!line.isEmpty)
        #expect(line.range(of: "\\bso\\b", options: [.regularExpression, .caseInsensitive]) == nil)
        #expect(!line.contains("\u{2014}") && !line.contains("\u{2013}"))
        if language.hasPrefix("zh") {
            #expect(line.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) })
        }
    }

    @Test func addingWithNoDaySendsNoDateFieldsAndShowsNoDate() async throws {
        let harness = TickTickHarness()
        harness.serve(inbox: [])
        await harness.activate()

        await harness.service.performAdd("Buy milk")

        let request = try #require(harness.transport.requests(endingWith: "/open/v1/task").first)
        #expect(request.jsonBody["dueDate"] == nil && request.jsonBody["isAllDay"] == nil)
        #expect(harness.service.items.first { $0.id == "new" }?.dueDate == nil)
    }

    @Test func theProtocolAddTakesTheDayThroughTheSourceSurface() async throws {
        let harness = TickTickHarness()
        harness.serve(inbox: [])
        await harness.activate()
        let source: any NookTodoSource = harness.service

        source.add("Buy milk", due: F.day(2026, 10, 16))
        for _ in 0..<200 where harness.transport.requests(endingWith: "/open/v1/task").isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }

        let request = try #require(harness.transport.requests(endingWith: "/open/v1/task").first)
        #expect(request.jsonBody["isAllDay"] as? Bool == true)
    }

    // MARK: Whether a day can be set

    @Test func aDayCanBeSetWhenAddingWorks() async {
        let harness = TickTickHarness()
        harness.serve(inbox: [])
        await harness.activate()

        #expect(harness.service.canAdd && harness.service.canSetDue)
        #expect(harness.service.dueUnavailableReason == nil)
    }

    @Test func aDayCannotBeSetWhenAddingIsOff() async {
        let harness = TickTickHarness()
        harness.serve(inbox: [])
        await harness.activate()
        harness.transport.setResponder { _, _ in StubTodoResponse(status: 403) }
        await harness.service.performAdd("Buy milk")

        #expect(!harness.service.canAdd && !harness.service.canSetDue)
        #expect(harness.service.dueUnavailableReason == LanguageManager.shared.t("nook.todo.due.unavailable"))
    }
}
