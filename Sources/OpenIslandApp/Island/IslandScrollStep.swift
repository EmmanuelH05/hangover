import Foundation

/// What holds the open island against a swipe close: a session waiting on
/// a decision, a picker the island put up, the welcome tour. Read from the
/// model by `AppModel.swipeRefusals`, applied only while the island is open.
struct IslandSwipeRefusals: Equatable, Sendable {
    var blocksDismiss = false
    var hasOpenPicker = false
    var holdsOpenForTour = false
}

/// Everything the panel controller knows when a scroll event arrives.
struct IslandScrollFacts: Equatable, Sendable {
    var isEnabled: Bool
    var status: NotchStatus
    var isInClosedSurface: Bool
    /// The open island's area while it is open, the pill while it is closed.
    var isInExpandedArea: Bool
    /// The event was delivered to this app (local monitor) and not to
    /// another one (global monitor), which only observes.
    var isLocalEvent: Bool
    var refusals = IslandSwipeRefusals()
}

/// What the controller does with a scroll event.
struct IslandScrollOutcome: Equatable, Sendable {
    var action: IslandSwipeAction
    /// Whether the local monitor swallows the event.
    var swallows: Bool
    /// Fingers are on the closed pill: a hover-open that is waiting must
    /// not fire under them.
    var cancelsHoverOpen: Bool

    /// The pointer is still on the island after these actions close it, and
    /// hover mode would open it again under the pointer.
    var suppressesHover: Bool {
        action == .close || action == .closeAndToggleClosedContent
    }

    static let ignored = IslandScrollOutcome(action: .none, swallows: false, cancelsHoverOpen: false)
}

extension IslandPointerRules {
    /// Feeds one scroll event to the recognizer and says what to do. The
    /// panel controller gathers the facts and acts on the answer.
    /// `isOverScrollableContent` is asked only for a local event on the open
    /// island that made a swipe, because it walks the views under the pointer.
    static func scrollStep(
        recognizer: inout IslandSwipeRecognizer,
        sample: IslandScrollSample,
        facts: IslandScrollFacts,
        isOverScrollableContent: (IslandSwipeDirection) -> Bool
    ) -> IslandScrollOutcome {
        guard facts.isEnabled else { return .ignored }

        guard swipeListens(
            isEnabled: true,
            isInClosedSurface: facts.isInClosedSurface,
            isInExpandedArea: facts.isInExpandedArea
        ) else {
            // A gesture the island acted on is still its own, wherever the
            // pointer has gone, until the next gesture starts.
            let swallows = recognizer.feedOffIsland(sample) && facts.isLocalEvent
            return IslandScrollOutcome(action: .none, swallows: swallows, cancelsHoverOpen: false)
        }

        let isOpened = facts.status == .opened
        let cancelsHoverOpen = facts.status == .closed && facts.isInClosedSurface
        let direction = recognizer.feed(sample)
        let swallows = facts.isLocalEvent && recognizer.isConsumed
        guard let direction else {
            return IslandScrollOutcome(action: .none, swallows: swallows, cancelsHoverOpen: cancelsHoverOpen)
        }

        let context = IslandSwipeContext(
            status: facts.status,
            direction: direction,
            isInClosedSurface: facts.isInClosedSurface,
            isInExpandedArea: facts.isInExpandedArea,
            isOverScrollableContent: facts.isLocalEvent && isOpened && isOverScrollableContent(direction),
            blocksDismiss: isOpened && facts.refusals.blocksDismiss,
            hasOpenPicker: isOpened && facts.refusals.hasOpenPicker,
            holdsOpenForTour: isOpened && facts.refusals.holdsOpenForTour
        )
        let action = swipeAction(context)
        guard action != .none else {
            return IslandScrollOutcome(action: .none, swallows: swallows, cancelsHoverOpen: cancelsHoverOpen)
        }
        recognizer.markConsumed()
        return IslandScrollOutcome(action: action, swallows: facts.isLocalEvent, cancelsHoverOpen: cancelsHoverOpen)
    }

    /// Whether opening the island for `reason` brings back what a swipe
    /// hid (D46). A card has news to bring. Hover and click leave the
    /// swipe's hidden state alone.
    static func openingBringsBackHiddenContent(reason: NotchOpenReason) -> Bool {
        reason == .notification
    }
}
