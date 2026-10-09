import Foundation

/// One pick for the right of the closed island, from either row of cards in
/// Personalization: the island's own three (count, agents, none) or the
/// Nook's extras (bars, date, battery, countdown).
///
/// The right side holds one thing. A pick sets both stores, which keeps the
/// other row from leaving something behind. Before this, picking an extra
/// left the island's own slot on count or agents, and the pill puts that
/// slot back whenever an agent waits. With an agent waiting most of the day
/// the extra never showed, unless the own slot happened to be on none.
///
/// A template may still set both on purpose: an extra that gives way to the
/// agent count while an agent waits.
enum IslandRightSideChoice: Equatable, Sendable {
    case own(IslandRightSlot)
    case extra(NookSideSlot)

    /// The island's own right slot after the pick.
    var ownSlot: IslandRightSlot {
        switch self {
        case .own(let slot): slot
        case .extra: .none
        }
    }

    /// The Nook's right slot after the pick. Nil leaves the island's own
    /// slot in charge.
    var nookSlot: NookSideSlot? {
        switch self {
        case .own: nil
        case .extra(let slot): slot
        }
    }
}

extension AppModel {
    /// Applies a pick for the right of the closed island on one display profile.
    func chooseRightSide(_ choice: IslandRightSideChoice, for profile: IslandAppearanceDisplayProfile) {
        nook.updateDisplayPreferences(for: profile) { $0.rightSlot = choice.nookSlot }
        updateAppearancePreferences(for: profile) { $0.rightSlot = choice.ownSlot }
    }
}
