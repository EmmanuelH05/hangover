import Foundation

/// A ready-made set of glow colors (D31). Picking one copies its palette
/// into the display's preferences; nothing remembers which theme it came
/// from, and a display is "on" a theme while its palette equals the
/// theme's.
struct IslandHaloTheme: Identifiable, Equatable, Sendable {
    let id: String
    let palette: IslandHaloPalette

    /// The key of the name Settings shows.
    var titleKey: String { "settings.appearance.nook.halo.theme.\(id)" }

    /// The moments a theme card draws as dots, in order.
    var swatches: [IslandHaloRGB] {
        IslandHaloMoment.allCases.compactMap { palette.color(for: $0) }
    }
}

extension IslandHaloTheme {
    /// The standard colors first, then the themes.
    static let all: [IslandHaloTheme] = [
        standard, signal, daybreak, neonArcade, terminal, bubblegum,
        sorbet, campfire, lagoon, aurora, nightMarket,
    ]

    static func theme(id: String) -> IslandHaloTheme? {
        all.first { $0.id == id }
    }

    /// The theme a palette equals, if any.
    static func matching(_ palette: IslandHaloPalette) -> IslandHaloTheme? {
        all.first { $0.palette == palette }
    }

    /// Today's colors. Notices keep their own color and music follows the
    /// album art, with no color of its own.
    static let standard = IslandHaloTheme(id: "default", palette: .standard)

    /// A theme colors every moment. The album art still wins while music
    /// plays; the theme's music color fills in when the art has no clear
    /// color.
    private static func themed(
        _ id: String,
        approval: UInt32,
        question: UInt32,
        completed: UInt32,
        running: UInt32,
        notice: UInt32,
        music: UInt32
    ) -> IslandHaloTheme {
        IslandHaloTheme(
            id: id,
            palette: IslandHaloPalette(
                approval: IslandHaloRGB(rgb: approval),
                question: IslandHaloRGB(rgb: question),
                completed: IslandHaloRGB(rgb: completed),
                running: IslandHaloRGB(rgb: running),
                notice: IslandHaloRGB(rgb: notice),
                music: IslandHaloRGB(rgb: music),
                musicUsesArtwork: true
            )
        )
    }

    // Amber asks, green finishes.
    static let signal = themed(
        "signal",
        approval: 0xFFA51F, question: 0x8E7CFF, completed: 0x2FE39B,
        running: 0x45C4FF, notice: 0xF4F1FF, music: 0xFF5FA8
    )
    // Blue and orange carry the load.
    static let daybreak = themed(
        "daybreak",
        approval: 0xFF8A1F, question: 0x6B8AFF, completed: 0xFFFFFF,
        running: 0x8ADCFF, notice: 0xFFE94A, music: 0xFF4F93
    )
    // Loud and saturated.
    static let neonArcade = themed(
        "neonArcade",
        approval: 0xFF5C85, question: 0xB07CFF, completed: 0xA6FF2E,
        running: 0x19E3FF, notice: 0xFFFFFF, music: 0xFF9A1F
    )
    // Green while the agent works, paper white when the prompt comes back.
    static let terminal = themed(
        "terminal",
        approval: 0xFFA200, question: 0x2FCBFF, completed: 0xF5F5F0,
        running: 0x4DFF7A, notice: 0x8A7CFF, music: 0xFF5C8A
    )
    // Candy colors.
    static let bubblegum = themed(
        "bubblegum",
        approval: 0xFF5C8A, question: 0xA56BFF, completed: 0x5FF5A8,
        running: 0x7DD6FF, notice: 0xFFE83D, music: 0xFF9A5C
    )
    // Soft pastels, the least contrast between moments.
    static let sorbet = themed(
        "sorbet",
        approval: 0xFFB07A, question: 0x9F7CFF, completed: 0x86F5C9,
        running: 0x6FC3FF, notice: 0xFFFFFF, music: 0xFF7FC0
    )
    // Warm, with one cool blue for work in progress.
    static let campfire = themed(
        "campfire",
        approval: 0xFF6B3D, question: 0x9B7CFF, completed: 0xFFD23F,
        running: 0x5CC0FF, notice: 0xFFF3D6, music: 0xFF9CCB
    )
    // Cool water tones with a sunny approval.
    static let lagoon = themed(
        "lagoon",
        approval: 0xFFE066, question: 0x7078FF, completed: 0x14C4A0,
        running: 0x6FD6FF, notice: 0xF2FBFF, music: 0xFF8A3D
    )
    // Green, cyan and violet.
    static let aurora = themed(
        "aurora",
        approval: 0xFF6FB8, question: 0x8577FF, completed: 0x39D975,
        running: 0x6FE0FA, notice: 0xF4FAFF, music: 0xFFEA6B
    )
    // Lantern red, jade and gold.
    static let nightMarket = themed(
        "nightMarket",
        approval: 0xFF5A47, question: 0x6B7CFF, completed: 0x19CFA5,
        running: 0xFFD23F, notice: 0xFFF8E7, music: 0xC9A0FF
    )
}

extension IslandHaloColors {
    /// Colors that read well by themselves, offered beside the one-color
    /// well.
    static let singleColorSuggestions: [IslandHaloRGB] = [
        IslandHaloRGB(rgb: 0xFFFFFF),
        IslandHaloRGB(rgb: 0xFFE9C7),
        IslandHaloRGB(rgb: 0x5EF2B0),
        IslandHaloRGB(rgb: 0xFFB020),
        IslandHaloRGB(rgb: 0x5CC8FF),
        IslandHaloRGB(rgb: 0xB79CFF),
        IslandHaloRGB(rgb: 0xFF7AC6),
    ]
}
