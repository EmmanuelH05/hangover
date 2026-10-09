import Foundation

// Response models for the parts of the Notion API the todo widget reads.
// Every type decodes leniently: unknown fields are ignored, unknown property
// types decode to a value with no payload, and one malformed entry in a list
// or dictionary is dropped instead of failing the whole response.

/// Decodes to nil instead of throwing when the payload has an unexpected shape.
struct NotionLossy<Wrapped: Decodable & Sendable>: Decodable, Sendable {
    let value: Wrapped?

    init(from decoder: Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}

private struct NotionAnyKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private extension KeyedDecodingContainer where Key == NotionAnyKey {
    func lenient<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        try? decodeIfPresent(T.self, forKey: NotionAnyKey(key))
    }

    func lenientArray<T: Decodable & Sendable>(_ type: T.Type, _ key: String) -> [T] {
        (lenient([NotionLossy<T>].self, key) ?? []).compactMap(\.value)
    }

    func lenientDictionary<T: Decodable & Sendable>(_ type: T.Type, _ key: String) -> [String: T] {
        (lenient([String: NotionLossy<T>].self, key) ?? [:]).compactMapValues(\.value)
    }

    func nested(_ key: String) -> KeyedDecodingContainer<NotionAnyKey>? {
        try? nestedContainer(keyedBy: NotionAnyKey.self, forKey: NotionAnyKey(key))
    }
}

struct NotionRichText: Decodable, Equatable, Sendable {
    let plainText: String

    init(plainText: String) { self.plainText = plainText }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: NotionAnyKey.self)
        plainText = container.lenient(String.self, "plain_text") ?? ""
    }
}

extension Array where Element == NotionRichText {
    var plainText: String { map(\.plainText).joined() }
}

struct NotionOption: Decodable, Equatable, Sendable {
    let id: String?
    let name: String

    init(id: String? = nil, name: String) {
        self.id = id
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: NotionAnyKey.self)
        id = container.lenient(String.self, "id")
        name = try container.decode(String.self, forKey: NotionAnyKey("name"))
    }
}

struct NotionStatusGroup: Decodable, Equatable, Sendable {
    let name: String
    let optionIDs: [String]

    init(name: String, optionIDs: [String]) {
        self.name = name
        self.optionIDs = optionIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: NotionAnyKey.self)
        name = try container.decode(String.self, forKey: NotionAnyKey("name"))
        optionIDs = container.lenient([String].self, "option_ids") ?? []
    }
}

/// One column of a database, as described by its data source schema.
struct NotionPropertySchema: Decodable, Equatable, Sendable {
    let id: String
    let name: String
    /// Raw type string. Types the widget does not know stay usable as text.
    let type: String
    let options: [NotionOption]
    let groups: [NotionStatusGroup]

    init(id: String, name: String, type: String, options: [NotionOption] = [], groups: [NotionStatusGroup] = []) {
        self.id = id
        self.name = name
        self.type = type
        self.options = options
        self.groups = groups
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: NotionAnyKey.self)
        id = container.lenient(String.self, "id") ?? ""
        name = container.lenient(String.self, "name") ?? ""
        type = container.lenient(String.self, "type") ?? ""
        let config = container.nested(type)
        options = config?.lenientArray(NotionOption.self, "options") ?? []
        groups = config?.lenientArray(NotionStatusGroup.self, "groups") ?? []
    }

    func renamed(_ newName: String) -> NotionPropertySchema {
        NotionPropertySchema(id: id, name: newName, type: type, options: options, groups: groups)
    }
}

/// A data source: the table behind a Notion database, with its schema.
struct NotionDataSource: Decodable, Equatable, Sendable {
    let id: String
    let title: String
    /// Keyed by property name.
    let properties: [String: NotionPropertySchema]
    let isInTrash: Bool

    init(id: String, title: String, properties: [NotionPropertySchema], isInTrash: Bool = false) {
        self.id = id
        self.title = title
        self.properties = Dictionary(properties.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        self.isInTrash = isInTrash
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: NotionAnyKey.self)
        id = try container.decode(String.self, forKey: NotionAnyKey("id"))
        title = container.lenientArray(NotionRichText.self, "title").plainText
        isInTrash = container.lenient(Bool.self, "in_trash") ?? false
        let raw = container.lenientDictionary(NotionPropertySchema.self, "properties")
        // The dictionary key is the authoritative name.
        properties = Dictionary(
            raw.map { key, value in (key, value.name == key ? value : value.renamed(key)) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var sortedProperties: [NotionPropertySchema] {
        properties.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func property(id: String?) -> NotionPropertySchema? {
        guard let id, !id.isEmpty else { return nil }
        return properties.values.first { $0.id == id }
    }
}

struct NotionDateValue: Decodable, Equatable, Sendable {
    let start: String?

    init(start: String?) { self.start = start }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: NotionAnyKey.self)
        start = container.lenient(String.self, "start")
    }
}

/// The value of one property on a page. Only the shapes the widget reads
/// are kept; everything else decodes with all payload fields nil.
struct NotionPropertyValue: Decodable, Equatable, Sendable {
    let type: String
    let title: [NotionRichText]?
    let richText: [NotionRichText]?
    let option: NotionOption?
    let multiSelect: [NotionOption]?
    let checkbox: Bool?
    let date: NotionDateValue?

    init(
        type: String,
        title: [NotionRichText]? = nil,
        richText: [NotionRichText]? = nil,
        option: NotionOption? = nil,
        multiSelect: [NotionOption]? = nil,
        checkbox: Bool? = nil,
        date: NotionDateValue? = nil
    ) {
        self.type = type
        self.title = title
        self.richText = richText
        self.option = option
        self.multiSelect = multiSelect
        self.checkbox = checkbox
        self.date = date
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: NotionAnyKey.self)
        type = container.lenient(String.self, "type") ?? ""
        title = type == "title" ? container.lenientArray(NotionRichText.self, "title") : nil
        richText = type == "rich_text" ? container.lenientArray(NotionRichText.self, "rich_text") : nil
        switch type {
        case "status": option = container.lenient(NotionOption.self, "status")
        case "select": option = container.lenient(NotionOption.self, "select")
        default: option = nil
        }
        multiSelect = type == "multi_select" ? container.lenientArray(NotionOption.self, "multi_select") : nil
        checkbox = type == "checkbox" ? container.lenient(Bool.self, "checkbox") : nil
        date = type == "date" ? container.lenient(NotionDateValue.self, "date") : nil
    }
}

struct NotionPage: Decodable, Equatable, Sendable {
    let id: String
    /// "page" for rows. Wiki databases can also return nested data sources.
    let object: String
    let properties: [String: NotionPropertyValue]

    init(id: String, object: String = "page", properties: [String: NotionPropertyValue]) {
        self.id = id
        self.object = object
        self.properties = properties
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: NotionAnyKey.self)
        id = try container.decode(String.self, forKey: NotionAnyKey("id"))
        object = container.lenient(String.self, "object") ?? "page"
        properties = container.lenientDictionary(NotionPropertyValue.self, "properties")
    }
}

/// One page of a paginated list response.
struct NotionList<Element: Decodable & Sendable>: Decodable, Sendable {
    let results: [Element]
    let hasMore: Bool
    let nextCursor: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: NotionAnyKey.self)
        results = container.lenientArray(Element.self, "results")
        hasMore = container.lenient(Bool.self, "has_more") ?? false
        nextCursor = container.lenient(String.self, "next_cursor")
    }
}

/// The bot user behind an integration token.
struct NotionUser: Decodable, Equatable, Sendable {
    let name: String?
    let workspaceName: String?

    init(name: String?, workspaceName: String?) {
        self.name = name
        self.workspaceName = workspaceName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: NotionAnyKey.self)
        name = container.lenient(String.self, "name")
        workspaceName = container.nested("bot")?.lenient(String.self, "workspace_name")
    }

    var displayName: String? {
        let parts = [name, workspaceName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Error body. Only the machine-readable code is read; the message is never
/// shown or logged.
struct NotionErrorBody: Decodable, Sendable {
    let code: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: NotionAnyKey.self)
        code = container.lenient(String.self, "code")
    }
}
