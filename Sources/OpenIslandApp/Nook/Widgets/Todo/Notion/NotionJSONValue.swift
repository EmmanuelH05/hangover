import Foundation

/// A small JSON tree for request bodies whose shape depends on the user's
/// database schema (filters, sorts, property writes).
enum NotionJSONValue: Equatable, Sendable, Encodable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case array([NotionJSONValue])
    case object([String: NotionJSONValue])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension NotionJSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByIntegerLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(integerLiteral value: Int) { self = .int(value) }
    init(arrayLiteral elements: NotionJSONValue...) { self = .array(elements) }
    init(dictionaryLiteral elements: (String, NotionJSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}
