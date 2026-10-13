import Foundation

/// What a store remembers of its file between one read or write and the
/// next: when it was changed, how big it was, and which file it was. Two
/// copies of the app (the dev copy and the installed one) share one folder,
/// and a file that is not as it was left means the other copy changed it.
/// Every write replaces the file, which gives it a new file number.
struct NookDesignFileSignature: Equatable, Sendable {
    var modified: Date?
    var size: UInt64
    var fileNumber: UInt64

    /// The file's signature, or nil when there is no file at `url`.
    static func of(_ url: URL) -> NookDesignFileSignature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return NookDesignFileSignature(
            modified: attributes[.modificationDate] as? Date,
            size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
            fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        )
    }
}

/// How the kit's dates are written and read: ISO 8601 to the second, which
/// is what the kit writes, and with a fraction of a second too, which a
/// file made by another tool may have.
enum NookDesignDates {
    static func parse(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle()) { return date }
        return try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    static func decoding(_ decoder: Decoder) throws -> Date {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let date = parse(text) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Not a date"))
        }
        return date
    }
}

extension KeyedDecodingContainer {
    /// A field read leniently. A key that is missing or null gives `fallback`
    /// and loses nothing. A key that is there and does not read gives
    /// `fallback` too, and is counted, which makes the loader keep a copy of
    /// the file before a save writes over what could not be read.
    func lenient<Value: Decodable>(
        _ type: Value.Type,
        forKey key: Key,
        fallback: @autoclosure () -> Value,
        counter: NookDesignSkipCounter?
    ) -> Value {
        guard contains(key), (try? decodeNil(forKey: key)) != true else { return fallback() }
        if let value = try? decode(Value.self, forKey: key) { return value }
        counter?.add()
        return fallback()
    }

    /// A field that may be absent. Absent and null are nil, and one that is
    /// there and does not read is nil and counted.
    func lenientOptional<Value: Decodable>(
        _ type: Value.Type,
        forKey key: Key,
        counter: NookDesignSkipCounter?
    ) -> Value? {
        guard contains(key), (try? decodeNil(forKey: key)) != true else { return nil }
        if let value = try? decode(Value.self, forKey: key) { return value }
        counter?.add()
        return nil
    }
}

/// Any key of an object, which tells what an object holds apart from what
/// a type expects of it.
struct NookDesignAnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension Decoder {
    /// True for an object that has keys and none of the ones a shelf of this
    /// kind keeps. An exported palette saved where the shelf belongs is one.
    /// `{}` and an object with only a version are an empty shelf.
    func isWrongShape(contentKeys: Set<String>) -> Bool {
        guard let container = try? container(keyedBy: NookDesignAnyKey.self) else { return false }
        let names = Set(container.allKeys.map(\.stringValue)).subtracting(["version"])
        return !names.isEmpty && names.isDisjoint(with: contentKeys)
    }
}
