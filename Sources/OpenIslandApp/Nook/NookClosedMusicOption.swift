import Foundation

/// The switches under the media style in Personalization's section "04 ·
/// While music plays". Settings draws them from this list, and the welcome
/// tour offers the same ones (D43), which keeps the two from drifting apart.
enum NookClosedMusicOption: CaseIterable, Identifiable, Hashable, Sendable {
    /// An agent that waits takes the right side back from the GIF.
    case reclaim
    /// The agent status dot on the album art.
    case dot
    /// External displays: the track title in the center label.
    case track
    /// External displays: the next event in the center label.
    case nextEvent
    /// Timer countdown and short notices.
    case notices

    var id: Self { self }

    var keyPath: WritableKeyPath<NookDisplayPreferences, Bool> {
        switch self {
        case .reclaim: \.agentsReclaimRightSide
        case .dot: \.showsAgentDotOnArt
        case .track: \.centerLabelShowsTrack
        case .nextEvent: \.centerLabelShowsNextEvent
        case .notices: \.showsNotices
        }
    }

    private var keyStem: String {
        switch self {
        case .reclaim: "reclaim"
        case .dot: "dot"
        case .track: "track"
        case .nextEvent: "nextEvent"
        case .notices: "notices"
        }
    }

    var titleKey: String { "settings.appearance.nook.\(keyStem).title" }

    /// Two of the notes have a wording that leaves the agents out.
    func noteKey(agentsEnabled: Bool) -> String {
        let key = "settings.appearance.nook.\(keyStem).note"
        let hasAgentFreeWording = self == .track || self == .nextEvent
        return hasAgentFreeWording && !agentsEnabled ? key + ".nookOnly" : key
    }

    /// Whether Settings lists the switch: the first two are about agents,
    /// the center label belongs to external displays.
    func isOffered(agentsEnabled: Bool, profile: IslandAppearanceDisplayProfile) -> Bool {
        switch self {
        case .reclaim, .dot: agentsEnabled
        case .track, .nextEvent: profile == .topBar
        case .notices: true
        }
    }

    /// False greys the switch out: it has nothing to act on with this style.
    func isEnabled(whenStyle style: NookClosedMediaStyle) -> Bool {
        switch self {
        case .reclaim: style == .artAndVisual
        case .dot, .track: style != .off
        case .nextEvent, .notices: true
        }
    }

    static func offered(agentsEnabled: Bool, profile: IslandAppearanceDisplayProfile) -> [NookClosedMusicOption] {
        allCases.filter { $0.isOffered(agentsEnabled: agentsEnabled, profile: profile) }
    }
}
