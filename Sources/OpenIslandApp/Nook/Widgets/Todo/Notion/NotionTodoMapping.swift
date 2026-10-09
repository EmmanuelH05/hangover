import Foundation

enum NotionDoneKind: String, Codable, Sendable {
    case status
    case select
    case checkbox
}

/// Which columns of the user's database play which role. Stored by property
/// ID, which survives a column being renamed in Notion.
struct NotionTodoMapping: Codable, Equatable, Sendable {
    var doneKind: NotionDoneKind?
    var donePropertyID: String?
    /// For a select column: the option that means done.
    var doneOptionName: String?
    var duePropertyID: String?
    var priorityPropertyID: String?
    var filterPropertyID: String?
    var filterValues: [String] = []
    /// A text column that holds each task's notes.
    var notesPropertyID: String?
}

/// Why a mapping cannot be used against the current schema.
enum NotionMappingIssue: String, Equatable, Sendable, Error {
    case titleMissing
    case doneNotChosen
    case doneMissing
    case doneOptionMissing
    case statusHasNoCompleteOption
    case dueMissing
    case priorityMissing
    case filterMissing
    case notesMissing
    /// Notion rejected the query built from the mapping.
    case queryRejected
}

/// A mapping checked against a schema and turned into property names, ready
/// to build requests and read pages.
struct NotionResolvedMapping: Equatable, Sendable {
    enum Done: Equatable, Sendable {
        case status(property: String, completeOptions: [String], defaultOption: String?)
        case select(property: String, doneOption: String, defaultOption: String?)
        case checkbox(property: String)
    }

    struct Filter: Equatable, Sendable {
        let property: String
        let isMultiSelect: Bool
        let values: [String]
    }

    let titleProperty: String
    let done: Done
    let dueProperty: String?
    let priorityProperty: String?
    /// Lower rank sorts first. Keyed by lowercased option name.
    let priorityRanks: [String: Int]
    let filter: Filter?
    let notesProperty: String?
}

enum NotionTodoMapper {
    static let completeGroupName = "complete"
    static let todoGroupName = "to-do"
    static let doneOptionNames = ["done", "complete", "completed"]
    static let donePropertyNames = ["status", "done", "complete", "completed", "state"]
    static let duePropertyNames = ["due", "due date", "deadline"]
    static let priorityPropertyName = "priority"
    static let notesPropertyNames = ["notes", "note", "description", "details"]
    /// Notion's limit for the content of one rich text object.
    static let maxRichTextLength = 2000
    /// Notion's limit for the number of objects in one rich text array.
    static let maxRichTextObjects = 100
    /// Known priority words, most urgent first.
    static let priorityTiers: [[String]] = [
        ["urgent", "critical", "highest", "p0"],
        ["high", "p1"],
        ["medium", "med", "normal", "p2"],
        ["low", "p3"],
        ["lowest", "none", "p4"],
    ]

    // MARK: Detection

    /// Best guess at the mapping for a schema the user just picked.
    static func detect(_ schema: NotionDataSource) -> NotionTodoMapping {
        let properties = schema.sortedProperties
        var mapping = NotionTodoMapping()

        if let status = preferred(properties.filter { $0.type == "status" }, names: donePropertyNames) {
            mapping.doneKind = .status
            mapping.donePropertyID = status.id
        } else if let checkbox = properties.first(where: { $0.type == "checkbox" && isNamed($0, donePropertyNames) }) {
            mapping.doneKind = .checkbox
            mapping.donePropertyID = checkbox.id
        } else if let select = preferred(
            properties.filter { $0.type == "select" && doneOption(in: $0) != nil }, names: donePropertyNames
        ) {
            mapping.doneKind = .select
            mapping.donePropertyID = select.id
            mapping.doneOptionName = doneOption(in: select)?.name
        } else if let checkbox = properties.first(where: { $0.type == "checkbox" }) {
            mapping.doneKind = .checkbox
            mapping.donePropertyID = checkbox.id
        }

        mapping.duePropertyID = preferred(properties.filter { $0.type == "date" }, names: duePropertyNames)?.id

        let selects = properties.filter { $0.type == "select" && $0.id != mapping.donePropertyID }
        let priority = selects.first { isNamed($0, [priorityPropertyName]) }
            ?? selects.first { property in property.options.contains { tier(of: $0.name) != nil } }
        mapping.priorityPropertyID = priority?.id
        mapping.notesPropertyID = detectNotesProperty(schema)?.id
        return mapping
    }

    /// The text column used for notes. By default only a column with a
    /// notes-like name counts: guessing another text column would let the
    /// first edit replace unrelated content.
    static func detectNotesProperty(_ schema: NotionDataSource, namedOnly: Bool = true) -> NotionPropertySchema? {
        let candidates = schema.sortedProperties.filter { $0.type == "rich_text" && !$0.id.isEmpty }
        let match = preferred(candidates, names: notesPropertyNames)
        if namedOnly, let match, !isNamed(match, notesPropertyNames) { return nil }
        return match
    }

    /// The option a select column most likely uses for finished tasks.
    static func doneOption(in property: NotionPropertySchema) -> NotionOption? {
        for name in doneOptionNames {
            if let match = property.options.first(where: { $0.name.lowercased() == name }) { return match }
        }
        return nil
    }

    private static func isNamed(_ property: NotionPropertySchema, _ names: [String]) -> Bool {
        names.contains(property.name.lowercased())
    }

    /// The candidate with the best-ranked name, or the first one.
    private static func preferred(_ candidates: [NotionPropertySchema], names: [String]) -> NotionPropertySchema? {
        for name in names {
            if let match = candidates.first(where: { $0.name.lowercased() == name }) { return match }
        }
        return candidates.first
    }

    private static func tier(of optionName: String) -> Int? {
        priorityTiers.firstIndex { $0.contains(optionName.lowercased()) }
    }

    // MARK: Resolution

    static func resolve(
        _ mapping: NotionTodoMapping,
        schema: NotionDataSource
    ) -> Result<NotionResolvedMapping, NotionMappingIssue> {
        guard let title = schema.properties.values.first(where: { $0.type == "title" }) else {
            return .failure(.titleMissing)
        }
        guard let kind = mapping.doneKind, mapping.donePropertyID != nil else {
            return .failure(.doneNotChosen)
        }
        guard let doneProperty = schema.property(id: mapping.donePropertyID), doneProperty.type == kind.rawValue else {
            return .failure(.doneMissing)
        }

        let done: NotionResolvedMapping.Done
        switch kind {
        case .status:
            let complete = options(of: doneProperty, inGroup: completeGroupName)
            guard !complete.isEmpty else { return .failure(.statusHasNoCompleteOption) }
            done = .status(
                property: doneProperty.name,
                completeOptions: complete,
                defaultOption: options(of: doneProperty, inGroup: todoGroupName).first
            )
        case .select:
            guard let wanted = mapping.doneOptionName,
                  let option = doneProperty.options.first(where: { $0.name == wanted }) else {
                return .failure(.doneOptionMissing)
            }
            done = .select(
                property: doneProperty.name,
                doneOption: option.name,
                defaultOption: doneProperty.options.first { $0.name != option.name }?.name
            )
        case .checkbox:
            done = .checkbox(property: doneProperty.name)
        }

        var dueName: String?
        if mapping.duePropertyID != nil {
            guard let due = schema.property(id: mapping.duePropertyID), due.type == "date" else {
                return .failure(.dueMissing)
            }
            dueName = due.name
        }

        var priorityName: String?
        var ranks: [String: Int] = [:]
        if mapping.priorityPropertyID != nil {
            guard let priority = schema.property(id: mapping.priorityPropertyID), priority.type == "select" else {
                return .failure(.priorityMissing)
            }
            priorityName = priority.name
            ranks = priorityRanks(for: priority.options)
        }

        var filter: NotionResolvedMapping.Filter?
        if mapping.filterPropertyID != nil {
            guard let property = schema.property(id: mapping.filterPropertyID),
                  property.type == "select" || property.type == "multi_select" else {
                return .failure(.filterMissing)
            }
            // Values removed from the column are dropped; an empty set means no filter.
            let known = Set(property.options.map(\.name))
            let values = mapping.filterValues.filter(known.contains)
            if !values.isEmpty {
                filter = .init(property: property.name, isMultiSelect: property.type == "multi_select", values: values)
            }
        }

        var notesName: String?
        if mapping.notesPropertyID != nil {
            guard let notes = schema.property(id: mapping.notesPropertyID), notes.type == "rich_text" else {
                return .failure(.notesMissing)
            }
            notesName = notes.name
        }

        return .success(NotionResolvedMapping(
            titleProperty: title.name,
            done: done,
            dueProperty: dueName,
            priorityProperty: priorityName,
            priorityRanks: ranks,
            filter: filter,
            notesProperty: notesName
        ))
    }

    private static func options(of property: NotionPropertySchema, inGroup groupName: String) -> [String] {
        guard let group = property.groups.first(where: { $0.name.lowercased() == groupName }) else { return [] }
        let ids = Set(group.optionIDs)
        return property.options.filter { option in option.id.map(ids.contains) ?? false }.map(\.name)
    }

    /// High/Medium/Low style names sort by meaning. Anything else keeps the
    /// order the options have in Notion.
    static func priorityRanks(for options: [NotionOption]) -> [String: Int] {
        let looksLikeTiers = options.contains { tier(of: $0.name) != nil }
        var ranks: [String: Int] = [:]
        for (index, option) in options.enumerated() {
            let key = option.name.lowercased()
            ranks[key] = looksLikeTiers ? (tier(of: option.name) ?? priorityTiers.count) : index
        }
        return ranks
    }

    // MARK: Requests

    /// Server-side filter for tasks that are not done, plus the optional
    /// category filter.
    static func queryFilter(_ resolved: NotionResolvedMapping) -> NotionJSONValue {
        var clauses: [NotionJSONValue] = []
        switch resolved.done {
        case .status(let property, let completeOptions, _):
            clauses += completeOptions.map {
                ["property": .string(property), "status": ["does_not_equal": .string($0)]]
            }
        case .select(let property, let doneOption, _):
            clauses.append(["property": .string(property), "select": ["does_not_equal": .string(doneOption)]])
        case .checkbox(let property):
            clauses.append(["property": .string(property), "checkbox": ["equals": false]])
        }
        if let filter = resolved.filter {
            let matches: [NotionJSONValue] = filter.values.map {
                filter.isMultiSelect
                    ? ["property": .string(filter.property), "multi_select": ["contains": .string($0)]]
                    : ["property": .string(filter.property), "select": ["equals": .string($0)]]
            }
            clauses.append(matches.count == 1 ? matches[0] : ["or": .array(matches)])
        }
        return clauses.count == 1 ? clauses[0] : ["and": .array(clauses)]
    }

    /// Due date ascending on the server, oldest first as the tie break.
    /// Priority order and "undated last" are applied locally in `items`,
    /// because Notion does not document where empty values sort.
    static func sorts(_ resolved: NotionResolvedMapping) -> [NotionJSONValue] {
        var sorts: [NotionJSONValue] = []
        if let due = resolved.dueProperty {
            sorts.append(["property": .string(due), "direction": "ascending"])
        }
        sorts.append(["timestamp": "created_time", "direction": "ascending"])
        return sorts
    }

    /// Property values that mark a page done.
    static func completionProperties(_ resolved: NotionResolvedMapping) -> NotionJSONValue? {
        switch resolved.done {
        case .status(let property, let completeOptions, _):
            guard let option = completeOptions.first else { return nil }
            return [property: ["status": ["name": .string(option)]]]
        case .select(let property, let doneOption, _):
            return [property: ["select": ["name": .string(doneOption)]]]
        case .checkbox(let property):
            return [property: ["checkbox": true]]
        }
    }

    /// Property values for a new, not-done task. A mapped filter gets its
    /// first value, which keeps the new task visible in the card.
    static func creationProperties(title: String, resolved: NotionResolvedMapping) -> NotionJSONValue {
        var properties: [String: NotionJSONValue] = [
            resolved.titleProperty: ["title": [["text": ["content": .string(title)]]]],
        ]
        switch resolved.done {
        case .status(let property, _, let defaultOption):
            // With no default, Notion applies the column's own default status.
            if let defaultOption { properties[property] = ["status": ["name": .string(defaultOption)]] }
        case .select(let property, _, let defaultOption):
            if let defaultOption { properties[property] = ["select": ["name": .string(defaultOption)]] }
        case .checkbox(let property):
            properties[property] = ["checkbox": false]
        }
        if let filter = resolved.filter, let value = filter.values.first {
            properties[filter.property] = filter.isMultiSelect
                ? ["multi_select": [["name": .string(value)]]]
                : ["select": ["name": .string(value)]]
        }
        return .object(properties)
    }

    /// Property values that replace a page's notes with plain text. Notion
    /// caps one text object at 2000 characters, which is why long notes are
    /// sent as several objects. Empty text clears the column.
    static func notesProperties(_ notes: String, resolved: NotionResolvedMapping) -> NotionJSONValue? {
        guard let property = resolved.notesProperty else { return nil }
        let objects: [NotionJSONValue] = richTextChunks(notes).map {
            ["type": "text", "text": ["content": .string($0)]]
        }
        return [property: ["rich_text": .array(objects)]]
    }

    /// Splits text into pieces Notion accepts, in order, without cutting a
    /// character in half. Lengths are counted in UTF-16 units, the stricter
    /// reading of Notion's limit. Text past 100 pieces is dropped.
    static func richTextChunks(
        _ text: String,
        maxLength: Int = maxRichTextLength,
        maxChunks: Int = maxRichTextObjects
    ) -> [String] {
        guard maxLength > 0, maxChunks > 0, !text.isEmpty else { return [] }
        var chunks: [String] = []
        var current = ""
        var currentLength = 0
        for character in text {
            let length = character.utf16.count
            if currentLength + length > maxLength, !current.isEmpty {
                chunks.append(current)
                if chunks.count == maxChunks { return chunks }
                current = ""
                currentLength = 0
            }
            current.append(character)
            currentLength += length
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// The longest notes text one write can carry.
    static func clampedNotes(_ text: String) -> String {
        richTextChunks(text).joined()
    }

    // MARK: Reading pages

    /// Open tasks in display order: priority (when mapped), then due date
    /// ascending with undated tasks last, then the order Notion returned.
    static func items(from pages: [NotionPage], resolved: NotionResolvedMapping, listName: String) -> [NookTodoItem] {
        struct Row {
            let item: NookTodoItem
            let rank: Int
            let index: Int
        }
        let rows: [Row] = pages.enumerated().compactMap { index, page in
            guard page.object == "page", !isDone(page, resolved: resolved) else { return nil }
            let title = page.properties[resolved.titleProperty]?.title?.plainText
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let due = resolved.dueProperty
                .flatMap { page.properties[$0]?.date?.start }
                .flatMap(parseDate)
            let rank = resolved.priorityProperty
                .flatMap { page.properties[$0]?.option?.name.lowercased() }
                .flatMap { resolved.priorityRanks[$0] } ?? Int.max
            let notes = resolved.notesProperty
                .flatMap { page.properties[$0]?.richText?.plainText }
                .flatMap { $0.isEmpty ? nil : $0 }
            let item = NookTodoItem(
                id: page.id, title: title, dueDate: due, isCompleted: false, listName: listName, notes: notes
            )
            return Row(item: item, rank: rank, index: index)
        }
        return rows.sorted { a, b in
            if a.rank != b.rank { return a.rank < b.rank }
            switch (a.item.dueDate, b.item.dueDate) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.index < b.index
            }
        }.map(\.item)
    }

    static func isDone(_ page: NotionPage, resolved: NotionResolvedMapping) -> Bool {
        switch resolved.done {
        case .status(let property, let completeOptions, _):
            guard let name = page.properties[property]?.option?.name else { return false }
            return completeOptions.contains(name)
        case .select(let property, let doneOption, _):
            return page.properties[property]?.option?.name == doneOption
        case .checkbox(let property):
            return page.properties[property]?.checkbox ?? false
        }
    }

    private static let dateOnlyLength = 10

    /// Notion sends either `2026-09-15` or a full ISO 8601 timestamp. A bare
    /// date becomes midnight in the user's time zone.
    static func parseDate(_ raw: String) -> Date? {
        if raw.count == dateOnlyLength {
            let parts = raw.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}
