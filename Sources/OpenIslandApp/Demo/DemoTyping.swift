import Foundation

/// A field a demo script types into (D65).
enum DemoTypingField: String, CaseIterable, Sendable {
    /// The notes card's field.
    case note
    /// The to-do card's add field.
    case todo
    /// The design kit's field for a typed color, on the large card.
    case designColor
}

/// One typing step: the field, the text and whether it ends with Return.
struct DemoTypingRun: Equatable, Sendable {
    let field: DemoTypingField
    let text: String
    let pressesReturn: Bool

    /// The text after each key press, one entry per character.
    var prefixes: [String] {
        let characters = Array(text)
        return characters.indices.map { String(characters[...$0]) }
    }

    /// The wait before each key press, then before Return when there is one.
    var gaps: [TimeInterval] {
        DemoTyping.gaps(for: text) + (pressesReturn ? [DemoTyping.beforeReturn] : [])
    }

    /// The whole time the typing takes.
    var duration: TimeInterval {
        gaps.reduce(0, +)
    }
}

/// How fast a person types in a recording (D65): one character every 55 to
/// 120 milliseconds, a little uneven. The unevenness comes from the text
/// itself, which makes every run of a script type at the same pace and
/// keeps two takes alike.
enum DemoTyping {
    static let fastest: TimeInterval = 0.055
    static let slowest: TimeInterval = 0.120
    /// The beat between the last character and Return.
    static let beforeReturn: TimeInterval = 0.35

    /// The wait before each character of `text`.
    static func gaps(for text: String) -> [TimeInterval] {
        var generator = SplitMix(seed: fnv1a(text))
        return text.map { _ in
            let share = Double(generator.next() >> 11) / Double(1 << 53)
            return fastest + (slowest - fastest) * share
        }
    }

    /// FNV-1a over the text's bytes. Swift's own hashing is seeded anew in
    /// every process, which would give each run a different pace.
    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// A small generator with a fixed seed.
    struct SplitMix {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9e37_79b9_7f4a_7c15
            var value = state
            value = (value ^ (value >> 30)) &* 0xbf58_476d_1ce4_e5b9
            value = (value ^ (value >> 27)) &* 0x94d0_49bb_1331_11eb
            return value ^ (value >> 31)
        }
    }
}
