import Foundation

/// How the lasers follow a song (D56). The user picks one in Settings.
enum IslandLaserMode: String, CaseIterable, Identifiable, Sendable {
    /// Every hit decides for itself: a low hit shoots the beams in the
    /// next color, and a mid hit moves to the next arrangement.
    case reactive
    /// A show: one look at a time in two colors, and the hits only move
    /// what the look already shows (`IslandLaserDirector`).
    case show

    static let titleKey = "settings.appearance.nook.halo.beat.mode"

    var id: String { rawValue }

    var titleKey: String { "\(Self.titleKey).\(rawValue)" }

    /// What a saved value reads as. Settings from before the choice, and
    /// anything that is not one of the two, are reactive.
    init(storageValue: String?) {
        self = storageValue.flatMap(IslandLaserMode.init(rawValue:)) ?? .reactive
    }
}

/// The number a song's show is made from (D56). The same title and artist
/// give the same number on every launch, which Swift's own hashing does
/// not: it is seeded anew for each run.
enum IslandLaserSeed {
    /// The seed for a song. With no title and no artist it comes from the
    /// art's color, and with none of the three it is one fixed number.
    static func seed(title: String?, artist: String?, tint: IslandHaloRGB?) -> UInt64 {
        let title = folded(title)
        let artist = folded(artist)
        if !title.isEmpty || !artist.isEmpty {
            // A byte no name holds keeps "ab" by "c" apart from "a" by "bc".
            return hash(Array(title.utf8) + [0x1F] + Array(artist.utf8))
        }
        guard let tint else { return hash([]) }
        return hash([tint.red, tint.green, tint.blue].map { UInt8(min(max($0, 0), 1) * 255) })
    }

    /// FNV-1a, 64 bits.
    static func hash(_ bytes: [UInt8]) -> UInt64 {
        bytes.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
    }

    private static func folded(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Numbers that follow from a seed and from nothing else: the same seed
/// gives the same numbers in the same order (SplitMix64).
struct IslandLaserSequence: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    /// A number from 0 up to, and not counting, `bound`.
    mutating func below(_ bound: Int) -> Int {
        bound > 1 ? Int(next() % UInt64(bound)) : 0
    }

    /// The same items in another order.
    mutating func shuffled<Item>(_ items: [Item]) -> [Item] {
        var result = items
        for index in stride(from: result.count - 1, to: 0, by: -1) {
            result.swapAt(index, below(index + 1))
        }
        return result
    }
}

/// One look of a show (D56): an arrangement, and what the beams do in it.
struct IslandLaserLook: Hashable, Sendable {
    enum Kind: String, Sendable {
        /// Every beam on and still. A low hit pushes them out a little.
        case still
        /// Every other beam in one color and the rest in the other, one
        /// group lit at a time. A low hit lights the other group.
        case oddEven
        /// Every beam on, and the fan slowly narrows and opens.
        case breathe
        /// Every beam on and dim, and a slow wave runs along their
        /// lengths.
        case wave
    }

    var kind: Kind
    var arrangement: IslandLaserArrangement

    var name: String { "\(kind.rawValue) \(arrangement.name)" }

    /// How large the look reads on the screen. The largest in a song's
    /// order is where a drop lands.
    var size: Int {
        let order: [IslandLaserArrangement] = [
            .curtain, .crossed, .wings, .comb, .split, .fan, .wideCurtain,
            IslandLaserArrangement.crossed.forward, IslandLaserArrangement.wings.forward,
            IslandLaserArrangement.fan.forward,
        ]
        return order.firstIndex(of: arrangement) ?? 0
    }

    /// The arrangements a groove's looks are made of: the fan shapes flat
    /// and toward the viewer, and the beams that come straight down.
    static let grooveArrangements: [IslandLaserArrangement] = [
        .fan, .wings, .comb, .crossed,
        IslandLaserArrangement.fan.forward, IslandLaserArrangement.wings.forward,
        IslandLaserArrangement.crossed.forward,
        .curtain, .wideCurtain, .split,
    ]

    /// The looks of a stretch with no bass.
    static let lulls: [IslandLaserLook] = [
        IslandLaserLook(kind: .wave, arrangement: .fan),
        IslandLaserLook(kind: .breathe, arrangement: .fan),
    ]
}

/// A song's show (D56): the order of its looks and of its colors, made
/// from the song's seed and from nothing else. The same song gets the
/// same show every time it plays.
struct IslandLaserProgram: Equatable, Sendable {
    /// The fewest and the most looks a song's groove walks through.
    static let lookCounts = 4...6

    let seed: UInt64
    /// The groove's looks in the order the phrases walk through them.
    /// Each is another arrangement, and one of them is the Odd Even.
    let looks: [IslandLaserLook]
    /// The looks of a stretch with no bass, in order.
    let lulls: [IslandLaserLook]
    /// The four hues around the art's color, in the order this song's
    /// palettes take them up.
    let hueOrder: [Int]

    init(seed: UInt64) {
        self.seed = seed
        var sequence = IslandLaserSequence(seed: seed)
        hueOrder = sequence.shuffled(Array(IslandBeatHues.offsets.indices))
        let count = Self.lookCounts.lowerBound + sequence.below(Self.lookCounts.count)
        let arrangements = sequence.shuffled(IslandLaserLook.grooveArrangements).prefix(count)
        let oddEven = sequence.below(count)
        looks = arrangements.enumerated().map { index, arrangement in
            IslandLaserLook(kind: index == oddEven ? .oddEven : .still, arrangement: arrangement)
        }
        lulls = sequence.shuffled(IslandLaserLook.lulls)
    }

    /// The palette at a place in the song: a base and an accent, as
    /// places among the four hues. Each palette keeps one color of the
    /// one before it: the old accent is the new base.
    func palette(_ index: Int) -> (base: Int, accent: Int) {
        let count = hueOrder.count
        let place = ((index % count) + count) % count
        return (base: hueOrder[place], accent: hueOrder[(place + 1) % count])
    }

    /// Where in `looks` the largest look is: a drop lands there.
    var biggest: Int {
        looks.indices.max { looks[$0].size < looks[$1].size } ?? 0
    }
}
