import Foundation
import Testing
@testable import OpenIslandApp

@Suite struct NotionTodoMappingTests {
    // MARK: Decoding

    @Test func unknownPropertyTypesAndMalformedEntriesDoNotBreakSchemaDecoding() throws {
        let schema = try NotionFixtures.decodeSchema(NotionFixtures.selectSchema)

        #expect(schema.title == "To-Do")
        #expect(schema.properties["Mystery"]?.type == "hologram")
        #expect(schema.properties["Mystery"]?.options.isEmpty == true)
        #expect(schema.properties["Broken"] == nil)
        #expect(schema.properties["Status"]?.options.map(\.name) == ["To Do", "In Progress", "Waiting", "Done"])
    }

    @Test func unknownPropertyValuesDoNotBreakPageDecoding() throws {
        let page = try NotionFixtures.decodePage(NotionFixtures.page(id: "p1", title: "Write essay", due: "2026-09-15"))

        #expect(page.properties["Mystery"]?.type == "hologram")
        #expect(page.properties["Total"]?.checkbox == nil)
        #expect(page.properties["Task"]?.title?.plainText == "Write essay")
        #expect(page.properties["Due"]?.date?.start == "2026-09-15")
    }

    @Test func listSkipsResultsItCannotDecode() throws {
        let json = NotionFixtures.list([NotionFixtures.page(id: "p1", title: "A"), "42", "{\"no_id\":true}"])

        let list = try JSONDecoder().decode(NotionList<NotionPage>.self, from: Data(json.utf8))

        #expect(list.results.map(\.id) == ["p1"])
        #expect(list.hasMore == false)
    }

    // MARK: Detection

    @Test func detectsSelectDatabaseWithDoneOption() throws {
        let schema = try NotionFixtures.decodeSchema(NotionFixtures.selectSchema)

        let mapping = NotionTodoMapper.detect(schema)

        #expect(mapping.doneKind == .select)
        #expect(mapping.donePropertyID == "st%3A1")
        #expect(mapping.doneOptionName == "Done")
        #expect(mapping.duePropertyID == "due1")
        #expect(mapping.priorityPropertyID == "pri1")
        #expect(mapping.filterPropertyID == nil)
    }

    @Test func detectsStatusDatabaseAndPrefersDeadlineOverOtherDates() throws {
        let schema = try NotionFixtures.decodeSchema(NotionFixtures.statusSchema)

        let mapping = NotionTodoMapper.detect(schema)

        #expect(mapping.doneKind == .status)
        #expect(mapping.donePropertyID == "st1")
        #expect(mapping.duePropertyID == "dl1")
        #expect(mapping.priorityPropertyID == nil)
    }

    @Test func detectsCheckboxDatabase() throws {
        let schema = try NotionFixtures.decodeSchema(NotionFixtures.checkboxSchema)

        let mapping = NotionTodoMapper.detect(schema)

        #expect(mapping.doneKind == .checkbox)
        #expect(mapping.donePropertyID == "cb1")
        #expect(mapping.duePropertyID == nil)
    }

    // MARK: Resolution

    @Test func statusResolvesToEveryOptionInTheCompleteGroup() throws {
        let schema = try NotionFixtures.decodeSchema(NotionFixtures.statusSchema)

        let resolved = try NotionTodoMapper.resolve(NotionTodoMapper.detect(schema), schema: schema).get()

        #expect(resolved.titleProperty == "Name")
        #expect(resolved.done == .status(property: "Status", completeOptions: ["Done", "Archived"], defaultOption: "Not started"))
        #expect(resolved.dueProperty == "Deadline")
    }

    @Test func missingMappedPropertiesSurfaceAsIssues() throws {
        let schema = try NotionFixtures.decodeSchema(NotionFixtures.selectSchema)
        var mapping = NotionTodoMapper.detect(schema)

        mapping.duePropertyID = "deleted"
        #expect(NotionTodoMapper.resolve(mapping, schema: schema) == .failure(.dueMissing))

        mapping = NotionTodoMapper.detect(schema)
        mapping.donePropertyID = "deleted"
        #expect(NotionTodoMapper.resolve(mapping, schema: schema) == .failure(.doneMissing))

        mapping = NotionTodoMapper.detect(schema)
        mapping.doneOptionName = "Shipped"
        #expect(NotionTodoMapper.resolve(mapping, schema: schema) == .failure(.doneOptionMissing))

        mapping = NotionTodoMapper.detect(schema)
        mapping.priorityPropertyID = "due1"
        #expect(NotionTodoMapper.resolve(mapping, schema: schema) == .failure(.priorityMissing))

        #expect(NotionTodoMapper.resolve(NotionTodoMapping(), schema: schema) == .failure(.doneNotChosen))
    }

    // MARK: Query construction

    @Test func selectFilterExcludesTheDoneOptionAndSortsByDue() throws {
        let schema = try NotionFixtures.decodeSchema(NotionFixtures.selectSchema)
        let resolved = try NotionTodoMapper.resolve(NotionTodoMapper.detect(schema), schema: schema).get()

        #expect(NotionTodoMapper.queryFilter(resolved) == [
            "property": "Status", "select": ["does_not_equal": "Done"],
        ])
        #expect(NotionTodoMapper.sorts(resolved) == [
            ["property": "Due", "direction": "ascending"],
            ["timestamp": "created_time", "direction": "ascending"],
        ])
    }

    @Test func statusFilterExcludesEachCompleteOption() throws {
        let schema = try NotionFixtures.decodeSchema(NotionFixtures.statusSchema)
        let resolved = try NotionTodoMapper.resolve(NotionTodoMapper.detect(schema), schema: schema).get()

        #expect(NotionTodoMapper.queryFilter(resolved) == ["and": [
            ["property": "Status", "status": ["does_not_equal": "Done"]],
            ["property": "Status", "status": ["does_not_equal": "Archived"]],
        ]])
    }

    @Test func checkboxFilterAndCategoryFilterCombine() throws {
        let schema = try NotionFixtures.decodeSchema(NotionFixtures.checkboxSchema)
        var mapping = NotionTodoMapper.detect(schema)
        mapping.filterPropertyID = "ai1"
        mapping.filterValues = ["Produce", "Removed option"]
        let resolved = try NotionTodoMapper.resolve(mapping, schema: schema).get()

        #expect(NotionTodoMapper.queryFilter(resolved) == ["and": [
            ["property": "Bought", "checkbox": ["equals": false]],
            ["property": "Aisle", "select": ["equals": "Produce"]],
        ]])
        #expect(NotionTodoMapper.sorts(resolved) == [["timestamp": "created_time", "direction": "ascending"]])
    }

    @Test func multiSelectFilterUsesContainsInsideOr() throws {
        let schema = try NotionFixtures.decodeSchema(NotionFixtures.statusSchema)
        var mapping = NotionTodoMapper.detect(schema)
        mapping.filterPropertyID = "tg1"
        mapping.filterValues = ["Home", "Errand"]
        let resolved = try NotionTodoMapper.resolve(mapping, schema: schema).get()

        guard case .object(let filter) = NotionTodoMapper.queryFilter(resolved),
              case .array(let clauses)? = filter["and"] else {
            Issue.record("expected an and filter")
            return
        }
        #expect(clauses.last == ["or": [
            ["property": "Tags", "multi_select": ["contains": "Home"]],
            ["property": "Tags", "multi_select": ["contains": "Errand"]],
        ]])
    }

    @Test func writesUseTheMappedDoneShape() throws {
        let select = try NotionFixtures.decodeSchema(NotionFixtures.selectSchema)
        let selectResolved = try NotionTodoMapper.resolve(NotionTodoMapper.detect(select), schema: select).get()
        #expect(NotionTodoMapper.completionProperties(selectResolved) == ["Status": ["select": ["name": "Done"]]])
        #expect(NotionTodoMapper.creationProperties(title: "Buy milk", resolved: selectResolved) == [
            "Task": ["title": [["text": ["content": "Buy milk"]]]],
            "Status": ["select": ["name": "To Do"]],
        ])

        let status = try NotionFixtures.decodeSchema(NotionFixtures.statusSchema)
        let statusResolved = try NotionTodoMapper.resolve(NotionTodoMapper.detect(status), schema: status).get()
        #expect(NotionTodoMapper.completionProperties(statusResolved) == ["Status": ["status": ["name": "Done"]]])

        let checkbox = try NotionFixtures.decodeSchema(NotionFixtures.checkboxSchema)
        let checkboxResolved = try NotionTodoMapper.resolve(NotionTodoMapper.detect(checkbox), schema: checkbox).get()
        #expect(NotionTodoMapper.completionProperties(checkboxResolved) == ["Bought": ["checkbox": true]])
    }

    // MARK: Pages to items

    @Test func pagesMapToItemsSortedByPriorityThenDueWithUndatedLast() throws {
        let schema = try NotionFixtures.decodeSchema(NotionFixtures.selectSchema)
        let resolved = try NotionTodoMapper.resolve(NotionTodoMapper.detect(schema), schema: schema).get()
        let pages = try [
            NotionFixtures.page(id: "low-early", title: "Low early", due: "2026-01-01", priority: "Low"),
            NotionFixtures.page(id: "high-undated", title: "High undated", priority: "High"),
            NotionFixtures.page(id: "none", title: "No priority", due: "2026-01-02"),
            NotionFixtures.page(id: "high-late", title: "  High late ", due: "2026-03-01T09:30:00.000-07:00", priority: "High"),
            NotionFixtures.page(id: "done", title: "Finished", status: "Done", priority: "High"),
            NotionFixtures.page(id: "medium", title: "Medium", status: nil, priority: "Medium"),
        ].map(NotionFixtures.decodePage)

        let items = NotionTodoMapper.items(from: pages, resolved: resolved, listName: "To-Do")

        #expect(items.map(\.id) == ["high-late", "high-undated", "medium", "low-early", "none"])
        #expect(items.first?.title == "High late")
        #expect(items.first?.listName == "To-Do")
        #expect(items.allSatisfy { !$0.isCompleted })
        #expect(items.first { $0.id == "high-undated" }?.dueDate == nil)
    }

    @Test func parsesDateOnlyAndTimestampForms() {
        let day = NotionTodoMapper.parseDate("2026-09-15")
        #expect(day.map { Calendar.current.dateComponents([.year, .month, .day, .hour], from: $0) }
            == DateComponents(year: 2026, month: 9, day: 15, hour: 0))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let tenUTC = utc.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 10))
        #expect(tenUTC != nil)
        #expect(NotionTodoMapper.parseDate("2026-09-15T10:00:00Z") == tenUTC)
        #expect(NotionTodoMapper.parseDate("2026-09-15T12:00:00.000+02:00") == tenUTC)
        #expect(NotionTodoMapper.parseDate("next tuesday") == nil)
        #expect(NotionTodoMapper.parseDate("") == nil)
    }

    @Test func priorityRanksFallBackToOptionOrderForUnknownNames() {
        let ranks = NotionTodoMapper.priorityRanks(for: [NotionOption(name: "Now"), NotionOption(name: "Later")])
        #expect(ranks == ["now": 0, "later": 1])

        let tiers = NotionTodoMapper.priorityRanks(for: [NotionOption(name: "Low"), NotionOption(name: "High")])
        #expect((tiers["high"] ?? 99) < (tiers["low"] ?? -1))
    }

    // MARK: Strings

    @Test(arguments: ["en", "zh-Hans", "zh-Hant"])
    func everyStateAndIssueHasAString(locale: String) throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/OpenIslandApp/Resources")
        let file = resources.appendingPathComponent("\(locale).lproj/Localizable.strings")
        let table = try #require(NSDictionary(contentsOf: file) as? [String: String])
        let states: [NotionTodoState] = [
            .inactive, .connecting, .noToken, .keychainUnavailable, .invalidToken, .noDatabase,
            .databaseUnavailable, .missingReadCapability, .rateLimited, .offline, .serverError, .ready,
        ]
        let issues: [NotionMappingIssue] = [
            .titleMissing, .doneNotChosen, .doneMissing, .doneOptionMissing, .statusHasNoCompleteOption,
            .dueMissing, .priorityMissing, .filterMissing, .queryRejected,
        ]
        let keys = states.map(\.messageKey)
            + issues.map { NotionTodoState.needsAttention($0).messageKey }
            + [NotionTodoActionError.addFailed, .completeFailed, .rateLimited].map(\.messageKey)
            + ["nook.todo.source", "nook.todo.offline", "nook.todo.notion.add",
               "nook.todo.notion.error.cannotInsert", "nook.todo.notion.error.cannotUpdate",
               "nook.todo.notion.database.empty", "nook.todo.notion.token.help"]
        for key in keys {
            #expect(table[key] != nil, "missing \(locale) string for \(key)")
        }
    }
}
