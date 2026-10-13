import Foundation

/// The slider under "Pulse with the beat" that sets how far the light goes.
enum IslandBeatReachSlider: Hashable, Sendable {
    /// "How far it reaches", the glow's.
    case glow
    /// "How far the lasers reach".
    case lasers

    var titleKey: String {
        switch self {
        case .glow: "settings.appearance.nook.halo.beat.reach"
        case .lasers: "settings.appearance.nook.halo.beat.laserReach"
        }
    }
}

/// How the beat is drawn around the closed island (D56): the glow that
/// grows and changes color, or beams that fan out from under the notch.
enum IslandBeatLook: String, CaseIterable, Identifiable, Sendable {
    case glow
    case lasers

    var id: String { rawValue }

    var titleKey: String { "settings.appearance.nook.halo.beat.look.\(rawValue)" }

    /// Which "how far" slider Settings shows for this look. One at a
    /// time: each look has a reach of its own, and the lasers' is a far
    /// longer one.
    var reachSlider: IslandBeatReachSlider {
        switch self {
        case .glow: .glow
        case .lasers: .lasers
        }
    }

    /// What a saved value reads as. Settings from before the choice, and
    /// anything that is not one of the two, are the glow.
    init(storageValue: String?) {
        self = storageValue.flatMap(IslandBeatLook.init(rawValue:)) ?? .glow
    }
}
