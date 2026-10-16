import Foundation
import Testing
@testable import OpenIslandApp

/// A date on a new Notion task: the Due column, and the row shown at once (D69).
@MainActor
@Suite struct NookTodoDueNotionTests {
    private typealias F = NookTodoDueFixtures

    private func resolved(_ json: String, mapping change: (inout NotionTodoMapping) -> Void = { _ in }) throws -> NotionResolvedMapping {
        let schema = try NotionFixtures.decodeSchema(json)
        var mapping = NotionTodoMapper.detect(schema)
        change(&mapping)
        return try NotionTodoMapper.resolve(mapping, schema: schema).get()
    }

    private func properties(of request: URLRequest) -> [String: Any] {
        request.jsonBody["properties"] as? [String: Any] ?? [:]
    }

    // MARK: The properties

    @Test func aDayGoesToTheDueColumnAsADateWithNoTime() throws {
        let resolved = try resolved(NotionFixtures.selectSchema)

        let properties = NotionTodoMapper.creationProperties(title: "Buy milk", resolved: resolved, due: F.day(2026, 10, 16))

        #expect(properties == [
            "Task": ["title": [["text": ["content": "Buy milk"]]]],
            "Status": ["select": ["name": "To Do"]],
            "Due": ["date": ["start": "2026-10-16"]],
        ])
    }

    @Test func noDayLeavesTheDueColumnOut() throws {
        let resolved = try resolved(NotionFixtures.selectSchema)

        let plain = NotionTodoMapper.creationProperties(title: "Buy milk", resolved: resolved)
        let explicit = NotionTodoMapper.creationProperties(title: "Buy milk", resolved: resolved, due: nil)

        #expect(plain == explicit)
        #expect(plain == [
            "Task": ["title": [["text": ["content": "Buy milk"]]]],
            "Status": ["select": ["name": "To Do"]],
        ])
    }

    @Test func aTimeIsNeverSent() throws {
        let resolved = try resolved(NotionFixtures.selectSchema)
        let withTime = DateComponents(year: 2026, month: 3, day: 5, hour: 17, minute: 45)

        let properties = NotionTodoMapper.creationProperties(title: "Buy milk", resolved: resolved, due: withTime)

        #expect(properties == [
            "Task": ["title": [["text": ["content": "Buy milk"]]]],
            "Status": ["select": ["name": "To Do"]],
            "Due": ["date": ["start": "2026-03-05"]],
        ])
    }

    @Test func somethingThatIsNotADayIsLeftOut() throws {
        let resolved = try resolved(NotionFixtures.selectSchema)

        for notADay in [F.day(2026, 2, 30), DateComponents(year: 2026, month: 10), DateComponents()] {
            let properties = NotionTodoMapper.creationProperties(title: "Buy milk", resolved: resolved, due: notADay)
            #expect(properties == NotionTodoMapper.creationProperties(title: "Buy milk", resolved: resolved))
        }
    }

    @Test func withNoDueColumnPickedADayHasNowhereToGo() throws {
        let resolved = try resolved(NotionFixtures.selectSchema) { $0.duePropertyID = nil }

        let properties = NotionTodoMapper.creationProperties(title: "Buy milk", resolved: resolved, due: F.day(2026, 10, 16))

        #expect(resolved.dueProperty == nil)
        #expect(properties == NotionTodoMapper.creationProperties(title: "Buy milk", resolved: resolved))
    }

    // MARK: The service

    @Test func addingWithADaySendsItAndShowsItAtOnce() async throws {
        let harness = try NotionTodoServiceTests.Harness()
        harness.serve(pages: [NotionFixtures.page(id: "a", title: "Write essay")])
        await harness.activate()

        await harness.service.performAdd("Buy milk", due: F.day(2026, 10, 16))

        let post = try #require(harness.transport.requests.first { $0.route == "POST /v1/pages" })
        let due = properties(of: post)["Due"] as? [String: [String: String]]
        #expect(due == ["date": ["start": "2026-10-16"]])
        let row = try #require(harness.service.items.first { $0.id == "written" })
        #expect(row.title == "Buy milk")
        #expect(row.dueDate == NookTodoDay.date(from: F.day(2026, 10, 16), calendar: .current))
    }

    @Test func addingWithNoDaySendsNoDueColumnAndShowsNoDate() async throws {
        let harness = try NotionTodoServiceTests.Harness()
        harness.serve(pages: [NotionFixtures.page(id: "a", title: "Write essay")])
        await harness.activate()

        await harness.service.performAdd("Buy milk")

        let post = try #require(harness.transport.requests.first { $0.route == "POST /v1/pages" })
        #expect(properties(of: post)["Due"] == nil)
        #expect(harness.service.items.first { $0.id == "written" }?.dueDate == nil)
    }

    @Test func theProtocolAddTakesTheDayThroughTheSourceSurface() async throws {
        let harness = try NotionTodoServiceTests.Harness()
        harness.serve(pages: [])
        await harness.activate()
        let source: any NookTodoSource = harness.service

        source.add("Buy milk", due: F.day(2026, 10, 16))
        for _ in 0..<200 where harness.transport.requests.first(where: { $0.route == "POST /v1/pages" }) == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }

        let post = try #require(harness.transport.requests.first { $0.route == "POST /v1/pages" })
        #expect((properties(of: post)["Due"] as? [String: [String: String]]) == ["date": ["start": "2026-10-16"]])
    }

    @Test func withNoDueColumnMappedNothingIsSentAndTheRowHasNoDate() async throws {
        let harness = try NotionTodoServiceTests.Harness(schema: NotionFixtures.checkboxSchema)
        harness.serve(schema: NotionFixtures.checkboxSchema, pages: [])
        await harness.activate()

        await harness.service.performAdd("Buy milk", due: F.day(2026, 10, 16))

        let post = try #require(harness.transport.requests.first { $0.route == "POST /v1/pages" })
        #expect(properties(of: post)["Due"] == nil)
        #expect(harness.service.items.first { $0.id == "written" }?.dueDate == nil)
    }

    // MARK: Whether a day can be set

    @Test func theButtonWorksWithADueColumnPicked() async throws {
        let harness = try NotionTodoServiceTests.Harness()
        harness.serve(pages: [])
        await harness.activate()

        #expect(harness.service.canAdd)
        #expect(harness.service.canSetDue)
        #expect(harness.service.dueUnavailableReason == nil)
    }

    @Test func withNoDueColumnTheButtonIsOffAndSaysWhatToDo() async throws {
        let harness = try NotionTodoServiceTests.Harness(schema: NotionFixtures.checkboxSchema)
        harness.serve(schema: NotionFixtures.checkboxSchema, pages: [])
        await harness.activate()

        #expect(harness.service.canAdd)
        #expect(!harness.service.canSetDue)
        #expect(harness.service.dueUnavailableReason == LanguageManager.shared.t("nook.todo.due.pickColumn"))
        #expect(
            try HangoverBrandTests.table("en")["nook.todo.due.pickColumn"] == "Pick a Due column in Settings to add dates."
        )
    }

    @Test func whenAddingIsOffTheButtonIsOffWithTheGeneralReason() async throws {
        let harness = try NotionTodoServiceTests.Harness()
        harness.serve(pages: [])
        await harness.activate()
        harness.transport.setResponder { _, _ in .json("{}", status: 403) }
        await harness.service.performAdd("Buy milk")

        #expect(!harness.service.canAdd)
        #expect(!harness.service.canSetDue)
        #expect(harness.service.dueUnavailableReason == LanguageManager.shared.t("nook.todo.due.unavailable"))
    }
}
