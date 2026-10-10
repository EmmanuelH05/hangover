import Foundation

/// What the line under the opening page's choices asks for, or answers.
/// The island is opened first. With the swipe on (D46) a swipe is asked for
/// next, and the line is answered once the island acted on one.
enum OnboardingOpeningStep: Equatable, Sendable {
    /// Open the island, by the way that is picked.
    case open(IslandOpenTrigger)
    /// The island was opened, and with the swipe off that is all.
    case opened
    /// The swipe is on and the island was opened: close it with a swipe.
    /// The words differ with the island open or closed again.
    case swipe(isIslandOpen: Bool)
    /// The island acted on a swipe.
    case swiped

    static func reading(_ state: OnboardingState) -> OnboardingOpeningStep {
        if state.swipeEnabled, state.hasSwiped { return .swiped }
        guard state.hasOpenedIsland || state.isIslandOpen else { return .open(state.openTrigger) }
        return state.swipeEnabled ? .swipe(isIslandOpen: state.isIslandOpen) : .opened
    }

    /// True once nothing is left to try.
    var isDone: Bool { self == .opened || self == .swiped }

    var textKey: String {
        switch self {
        case .open(let trigger):
            trigger == .hover ? "onboarding.opening.try.hover" : "onboarding.opening.try.click"
        case .opened: "onboarding.opening.tried"
        case .swipe(let isIslandOpen):
            isIslandOpen ? "onboarding.opening.swipe.try.open" : "onboarding.opening.swipe.try.closed"
        case .swiped: "onboarding.opening.swipe.tried"
        }
    }
}
