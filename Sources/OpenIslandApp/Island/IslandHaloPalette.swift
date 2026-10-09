import Foundation

/// The moments of the halo the user can color, in the order Settings lists
/// them.
enum IslandHaloMoment: String, CaseIterable, Identifiable, Sendable {
    case approval
    case question
    case completed
    case running
    case notice
    case music

    var id: String { rawValue }
}

/// The halo's color for each moment on one display (D31).
struct IslandHaloPalette: Equatable, Hashable, Sendable {
    var approval: IslandHaloRGB = .approval
    var question: IslandHaloRGB = .question
    var completed: IslandHaloRGB = .completed
    var running: IslandHaloRGB = .running
    /// Nil leaves each notice the color it comes with: orange for a timer,
    /// green for the charger, the calendar's color for an event.
    var notice: IslandHaloRGB?
    /// The glow while music plays when the album art is not used or has no
    /// clear color. Nil shows no glow then.
    var music: IslandHaloRGB?
    /// The album art's color wins while music plays.
    var musicUsesArtwork = true

    /// The colors the halo had before they could be chosen.
    static let standard = IslandHaloPalette()

    /// Shown in a color well while the palette holds no color for a moment.
    static let suggestedNotice = IslandHaloRGB.rgb255(255, 159, 10)
    static let suggestedMusic = IslandHaloRGB.rgb255(255, 55, 95)

    /// Every moment in one color. Notices and music take it too, and the
    /// album art is not read.
    static func single(_ color: IslandHaloRGB) -> IslandHaloPalette {
        IslandHaloPalette(
            approval: color,
            question: color,
            completed: color,
            running: color,
            notice: color,
            music: color,
            musicUsesArtwork: false
        )
    }

    /// The glow for a notice that arrives in the color `own`.
    func noticeColor(own: IslandHaloRGB) -> IslandHaloRGB {
        notice ?? own
    }

    /// The glow while music plays. `artwork` is the album art's color, nil
    /// when the art has none. Nil shows no glow.
    func musicColor(artwork: IslandHaloRGB?) -> IslandHaloRGB? {
        musicUsesArtwork ? (artwork ?? music) : music
    }

    /// Sets whether a notice keeps the color it comes with, or music takes
    /// the album art's. Turning a source off gives the moment a color to
    /// start from, and turning it back on takes that starter color away
    /// again, which leaves a palette nobody edited exactly as it was.
    mutating func setFollowsSource(_ follows: Bool, for moment: IslandHaloMoment) {
        switch moment {
        case .notice:
            notice = follows ? nil : Self.suggestedNotice
        case .music:
            musicUsesArtwork = follows
            if follows {
                if music == Self.suggestedMusic { music = nil }
            } else if music == nil {
                music = Self.suggestedMusic
            }
        default:
            break
        }
    }

    /// The palette's own color for a moment. Nil for a notice that keeps
    /// its own color and for music with no color set.
    func color(for moment: IslandHaloMoment) -> IslandHaloRGB? {
        switch moment {
        case .approval: approval
        case .question: question
        case .completed: completed
        case .running: running
        case .notice: notice
        case .music: music
        }
    }

    mutating func setColor(_ color: IslandHaloRGB, for moment: IslandHaloMoment) {
        switch moment {
        case .approval: approval = color
        case .question: question = color
        case .completed: completed = color
        case .running: running = color
        case .notice: notice = color
        case .music: music = color
        }
    }
}

// MARK: - Saving

extension IslandHaloPalette {
    private enum StorageKey {
        static let musicUsesArtwork = "musicUsesArtwork"
    }

    /// A property list form: "RRGGBB" per moment, with a notice or music
    /// color left out when there is none.
    var storageValue: [String: Any] {
        var value: [String: Any] = [StorageKey.musicUsesArtwork: musicUsesArtwork]
        for moment in IslandHaloMoment.allCases {
            if let color = color(for: moment) { value[moment.rawValue] = color.hex }
        }
        return value
    }

    /// Reads `storageValue` back. A moment that is missing or is not a
    /// color keeps its standard color, which makes a damaged or older
    /// entry lose only what it got wrong.
    init(storageValue: [String: Any]?) {
        self.init()
        guard let storageValue else { return }
        for moment in IslandHaloMoment.allCases {
            guard let raw = storageValue[moment.rawValue] as? String, let color = IslandHaloRGB(hex: raw) else { continue }
            setColor(color, for: moment)
        }
        if let usesArtwork = storageValue[StorageKey.musicUsesArtwork] as? Bool {
            musicUsesArtwork = usesArtwork
        }
        // Album art off with no color of its own would glow nothing while
        // Settings shows a color well: the starter color fills the gap.
        if !musicUsesArtwork, music == nil { music = Self.suggestedMusic }
    }
}

/// The glow colors the user chose for one display: a color per moment, and
/// the one color that can stand in for all of them. Kept apart from the
/// palette, which lets the switch go off again without losing the colors
/// under it.
struct IslandHaloColors: Equatable, Hashable, Sendable {
    var palette = IslandHaloPalette.standard
    var usesSingleColor = false
    var singleColor = IslandHaloColors.defaultSingleColor

    /// What the one-color well holds before the user picks.
    static let defaultSingleColor = IslandHaloRGB.running
    static let standard = IslandHaloColors()

    /// What the halo draws with.
    var effectivePalette: IslandHaloPalette {
        usesSingleColor ? .single(singleColor) : palette
    }
}
