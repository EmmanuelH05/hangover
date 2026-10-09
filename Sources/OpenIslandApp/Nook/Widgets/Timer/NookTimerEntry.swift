import Foundation
import Observation

/// Reads a typed timer length. Pure, so the card and the tests share it.
///
/// Accepted forms, ignoring case and any spaces:
/// - a plain number is minutes: `25`, `90`
/// - `h:mm` with minutes 0 to 59: `1:30`, `0:45`
/// - units in order hours, minutes, seconds, each at most once: `1h`, `45m`,
///   `90s`, `2h 15m`, `1h 5m 30s`. A bare number right after hours is
///   minutes 0 to 59: `1h30`.
///
/// Anything else, zero, or more than 24 hours is nil.
enum NookTimerEntry {
    static let minimum: TimeInterval = 1
    static let maximum: TimeInterval = 24 * 60 * 60

    /// Digit runs longer than this are out of range anyway; rejecting them
    /// keeps the arithmetic below from overflowing.
    private static let maxDigits = 6

    static func parse(_ text: String) -> TimeInterval? {
        let compact = text.filter { !$0.isWhitespace }.lowercased()
        guard !compact.isEmpty, compact.allSatisfy(\.isASCII) else { return nil }

        let seconds: Int?
        if compact.contains(":") {
            seconds = clockSeconds(compact)
        } else if compact.allSatisfy(isDigit) {
            seconds = number(compact[...]).map { $0 * 60 }
        } else {
            seconds = unitSeconds(compact)
        }
        guard let seconds else { return nil }
        let length = TimeInterval(seconds)
        guard length >= minimum, length <= maximum else { return nil }
        return length
    }

    /// Characters the entry field takes: digits, h, m, s, colon and space.
    static func accepts(_ character: Character) -> Bool {
        isDigit(character) || " :hmsHMS".contains(character)
    }

    static func isDigit(_ character: Character) -> Bool {
        ("0"..."9").contains(character)
    }

    // MARK: Forms

    /// `h:mm`, minutes 0 to 59.
    private static func clockSeconds(_ text: String) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[1].count <= 2,
              let hours = number(parts[0]),
              let minutes = number(parts[1]),
              minutes <= 59
        else { return nil }
        return hours * 3600 + minutes * 60
    }

    /// Hours, minutes and seconds in that order, each at most once.
    private static func unitSeconds(_ text: String) -> Int? {
        let units: [Character: (rank: Int, scale: Int)] = ["h": (0, 3600), "m": (1, 60), "s": (2, 1)]
        var rest = text[...]
        var total = 0
        var lastRank = -1
        while !rest.isEmpty {
            let digits = rest.prefix(while: isDigit)
            guard let value = number(digits) else { return nil }
            rest = rest.dropFirst(digits.count)
            guard let unitCharacter = rest.first else {
                // "1h30": a bare number straight after hours is minutes.
                guard lastRank == 0, value <= 59 else { return nil }
                return total + value * 60
            }
            guard let unit = units[unitCharacter], unit.rank > lastRank else { return nil }
            total += value * unit.scale
            lastRank = unit.rank
            rest = rest.dropFirst()
        }
        return lastRank >= 0 ? total : nil
    }

    private static func number(_ digits: Substring) -> Int? {
        guard !digits.isEmpty, digits.count <= maxDigits, digits.allSatisfy(isDigit) else { return nil }
        return Int(digits)
    }
}

/// What the card shows while a length is being typed. Nil text means no
/// entry is open. The card and the key monitor both drive it.
@MainActor
@Observable
final class NookTimerEntryState {
    static let maxLength = 10

    private(set) var text: String?
    /// True after a Return that could not be read; typing again clears it.
    private(set) var isInvalid = false

    var isActive: Bool { text != nil }

    /// Opens the entry, optionally with the first characters already typed.
    func begin(with seed: String = "") {
        text = String(seed.lowercased().filter(NookTimerEntry.accepts).prefix(Self.maxLength))
        isInvalid = false
    }

    func append(_ character: Character) {
        guard let current = text,
              NookTimerEntry.accepts(character),
              character.isWhitespace || current.filter({ !$0.isWhitespace }).count < Self.maxLength
        else { return }
        text = current + String(character).lowercased()
        isInvalid = false
    }

    func deleteLast() {
        guard let current = text else { return }
        text = String(current.dropLast())
        isInvalid = false
    }

    func cancel() {
        text = nil
        isInvalid = false
    }

    /// The typed length, closing the entry. Unreadable input stays open and
    /// turns red.
    func submit() -> TimeInterval? {
        guard let text else { return nil }
        guard let length = NookTimerEntry.parse(text) else {
            isInvalid = true
            return nil
        }
        cancel()
        return length
    }
}
