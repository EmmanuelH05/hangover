import CoreGraphics
import Foundation

/// How the closed island opens. Chosen in Settings → General.
enum IslandOpenTrigger: String, CaseIterable, Identifiable, Sendable {
    /// Resting the pointer on the island opens it, and it closes when the
    /// pointer leaves.
    case hover
    /// Only a click opens it, and it stays open until a click outside.
    case click

    var id: String { rawValue }

    /// Localizable keys for the choice in Settings.
    static let settingTitleKey = "settings.general.openTrigger"
    /// One line shown under the choice in both modes: files open the island
    /// either way.
    static let filesNoteKey = "settings.general.openTrigger.files"
    var titleKey: String { "settings.general.openTrigger.\(rawValue)" }
    var noteKey: String { "settings.general.openTrigger.note.\(rawValue)" }
}

/// What one mouse-down means for the island.
enum IslandClickAction: Equatable, Sendable {
    /// A click on the closed island opens it.
    case open
    /// A click outside the open island closes it.
    case dismiss
    /// A click outside while a decision is pending. The island stays.
    case holdForDecision
    /// A click inside a hover-opened island keeps it open after the pointer
    /// leaves.
    case pin
    /// A second click on the notch of an island that is held open closes it.
    case closeFromNotch
    case none
}

/// What the island does when dragged files reach it.
enum IslandFileDragArrival: Equatable, Sendable {
    /// Open the closed island on the Nook page, where the tray is.
    case openOnNook
    /// The island is open on the agents page: turn to the Nook page.
    case turnToNook
    /// No tray on this display's page. Stay closed and let the pill take
    /// the drop.
    case acceptOnClosedPill
    /// The open island takes the drop where it is.
    case none
}

/// Where a click landed and what the island was doing.
struct IslandClickContext: Equatable, Sendable {
    var status: NotchStatus
    var reason: NotchOpenReason?
    var isInClosedSurface: Bool
    var isInExpandedArea: Bool
    /// On the notch itself, clear of the header buttons beside it.
    var isOnNotch: Bool
    /// A session waits for approval or an answer and the user asked to keep
    /// the island open for it.
    var blocksDismiss: Bool
    /// A picker the island put up is still open, such as the tray's share
    /// picker. A click outside the island belongs to that picker.
    var hasOpenPicker = false
    /// The welcome tour holds the island open (D44). No click closes it.
    var holdsOpenForTour = false
}

/// What a two-finger swipe means for the island (D46).
enum IslandSwipeAction: Equatable, Sendable {
    /// Swipe up on the open island.
    case close
    /// Swipe sideways on the closed island: hide what it shows, or bring
    /// it back.
    case toggleClosedContent
    /// Swipe sideways on the closed pill's rectangle while the island is
    /// open (hover opens it before a swipe can be made): close it, then hide
    /// what the pill shows or bring it back.
    case closeAndToggleClosedContent
    case none
}

/// Where a swipe landed and what the island was doing.
struct IslandSwipeContext: Equatable, Sendable {
    var status: NotchStatus
    var direction: IslandSwipeDirection
    var isInClosedSurface: Bool
    var isInExpandedArea: Bool
    /// The pointer is over a scroll view with more to scroll. The swipe is
    /// that list's, not the island's.
    var isOverScrollableContent = false
    /// A session waits for approval or an answer and the user asked to keep
    /// the island open for it.
    var blocksDismiss = false
    /// A picker the island put up is still open.
    var hasOpenPicker = false
    /// The welcome tour holds the island open (D44).
    var holdsOpenForTour = false
}

/// Pure rules for what the pointer does to the island. The panel controller
/// gathers the facts and acts on the answer.
enum IslandPointerRules {
    /// How far the notch rect is pulled in before a click counts as "on the
    /// notch". The opened header's lanes start at the notch's edges.
    static let notchToggleInset: CGFloat = 6
    /// How far past the closed island a dragged file already counts as
    /// arriving: to each side and below it.
    static let fileDragSidePadding: CGFloat = 24
    static let fileDragBottomPadding: CGFloat = 20

    /// Whether the pointer resting on the closed island opens it.
    /// `isSuppressed` is true right after a click on the notch closed the
    /// island, until the pointer has left it once. Without that the island
    /// would open again under the pointer that just closed it.
    /// `isScrolling` is true while a scroll gesture is under way over the
    /// pill: a swipe is being made there, and an island that opens under the
    /// fingers would take it.
    static func hoverOpens(trigger: IslandOpenTrigger, isSuppressed: Bool, isScrolling: Bool = false) -> Bool {
        trigger == .hover && !isSuppressed && !isScrolling
    }

    /// Whether the pointer leaving the open island closes it, given what
    /// the other rules say. The tour's hold (D44) keeps it open whatever
    /// they say; with the hold off the answer is theirs, unchanged.
    static func pointerLeaveCloses(otherRules wouldClose: Bool, holdsOpenForTour: Bool) -> Bool {
        wouldClose && !holdsOpenForTour
    }

    static func clickAction(_ context: IslandClickContext) -> IslandClickAction {
        switch context.status {
        case .closed:
            return context.isInClosedSurface ? .open : .none
        case .popping:
            return .none
        case .opened:
            // The tour's hold outranks every other rule below: a click on
            // the island, on the notch or anywhere else leaves it open.
            if context.holdsOpenForTour { return .none }
            guard context.isInExpandedArea else {
                // The click is the picker's. The island neither closes nor
                // passes it on. A click on the notch still closes it.
                if context.hasOpenPicker { return .none }
                return context.blocksDismiss ? .holdForDecision : .dismiss
            }
            switch context.reason {
            case .hover:
                return .pin
            case .click:
                return context.isOnNotch && !context.blocksDismiss ? .closeFromNotch : .none
            case .notification, .boot, nil:
                // Cards and the boot animation keep their own rules.
                return .none
            }
        }
    }

    /// Whether a scroll event is worth following: the swipe is switched on
    /// and the pointer is on the island.
    static func swipeListens(isEnabled: Bool, isInClosedSurface: Bool, isInExpandedArea: Bool) -> Bool {
        isEnabled && (isInClosedSurface || isInExpandedArea)
    }

    /// What a swipe does. Every refusal a click close has applies to a swipe
    /// close too, and a swipe on a list that can still scroll is the list's.
    static func swipeAction(_ context: IslandSwipeContext) -> IslandSwipeAction {
        switch context.status {
        case .opened:
            // The tour's hold, a pending decision and an open picker refuse
            // every close, whichever way the swipe goes.
            if context.holdsOpenForTour || context.blocksDismiss || context.hasOpenPicker {
                return .none
            }
            let sideways = context.direction == .left || context.direction == .right
            if sideways {
                return context.isInClosedSurface ? .closeAndToggleClosedContent : .none
            }
            guard context.direction == .up, context.isInExpandedArea,
                  !context.isOverScrollableContent else { return .none }
            return .close
        case .closed:
            let sideways = context.direction == .left || context.direction == .right
            return sideways && context.isInClosedSurface ? .toggleClosedContent : .none
        case .popping:
            return .none
        }
    }

    /// What dragged files arriving over the island should do. The island
    /// only opens to show the tray, and a notification card is never
    /// pushed aside for it.
    static func fileDragArrival(
        status: NotchStatus,
        reason: NotchOpenReason?,
        showsNookPage: Bool,
        trayIsOnPage: Bool
    ) -> IslandFileDragArrival {
        if status == .opened {
            return trayIsOnPage && reason != .notification && !showsNookPage ? .turnToNook : .none
        }
        return trayIsOnPage ? .openOnNook : .acceptOnClosedPill
    }

    /// The part of the notch a second click closes the island from: pulled
    /// in from the lanes beside it and no taller than the opened header,
    /// because on an external display the notch reaches below the header
    /// into the content. Screen coordinates, with the top edge at `maxY`.
    static func notchToggleRect(notchRect: CGRect, headerHeight: CGFloat) -> CGRect {
        let inset = min(notchToggleInset, notchRect.width / 4)
        let height = min(notchRect.height, max(0, headerHeight))
        return CGRect(
            x: notchRect.minX + inset,
            y: notchRect.maxY - height,
            width: notchRect.width - inset * 2,
            height: height
        )
    }

    /// Where a dragged file counts as having reached the closed island: the
    /// closed surface with room to each side and below it.
    static func fileDragZone(closedSurface: CGRect) -> CGRect {
        CGRect(
            x: closedSurface.minX - fileDragSidePadding,
            y: closedSurface.minY - fileDragBottomPadding,
            width: closedSurface.width + fileDragSidePadding * 2,
            height: closedSurface.height + fileDragBottomPadding
        )
    }
}

/// The closed pill's rectangle, worked out when the placement is refreshed or
/// the screens change and tested against once for each scroll event. Working
/// it out asks the screen several questions (the safe area, the auxiliary
/// areas), which a scroll event, many a second, must not do.
struct IslandPillBounds: Equatable, Sendable {
    private(set) var rect: CGRect = .zero

    /// Works the rectangle out again. `compute` is where the screen is asked.
    mutating func refresh(_ compute: () -> CGRect) {
        rect = compute()
    }

    /// Edges count as inside, as they do for a click.
    func contains(_ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX
            && point.y >= rect.minY && point.y <= rect.maxY
    }
}

/// Follows one press of the mouse button to tell a file drag from any other
/// drag, and says when it reaches or leaves the island.
///
/// Mouse-moved events stop while a button is held, which leaves the island's
/// hover rules blind to drags. The drag pasteboard fills that in: a press
/// that starts a real drag writes to it, which bumps its change count, and
/// its types say whether files are on it. Only the count and the types are
/// read, never the contents.
struct IslandFileDragTracker: Equatable, Sendable {
    /// Pasteboard types that mean files on disk are being dragged. Promised
    /// files (a photo dragged out of Photos) are left out: the tray cannot
    /// take them.
    static let fileTypes: Set<String> = ["public.file-url", "NSFilenamesPboardType"]

    enum Step: Equatable, Sendable {
        /// A file drag arrived over the island.
        case entered
        /// It moved off the island with the button still down.
        case left
        /// The button came up after a file drag had reached the island.
        case ended
        case none
    }

    /// The drag pasteboard's change count when the button went down.
    private(set) var baselineChangeCount: Int?
    /// The press began on the open island: a tray file being dragged out,
    /// or a widget being moved. Never a file coming in.
    private(set) var startedInsideIsland = false
    private(set) var isOverIsland = false
    private(set) var hasReachedIsland = false

    static func carriesFiles(_ types: [String]) -> Bool {
        types.contains(where: fileTypes.contains)
    }

    mutating func mouseDown(changeCount: Int, insideIsland: Bool) {
        self = IslandFileDragTracker()
        baselineChangeCount = changeCount
        startedInsideIsland = insideIsland
    }

    /// The pasteboard is asked only while the pointer is over the island,
    /// and its types only once it has changed since the press. Ordinary
    /// drags elsewhere on screen cost nothing.
    mutating func dragged(
        isPointerOverIsland: Bool,
        changeCount: () -> Int,
        types: () -> [String]
    ) -> Step {
        guard let baselineChangeCount, !startedInsideIsland else { return .none }

        let isFileDragOverIsland = isPointerOverIsland
            && changeCount() != baselineChangeCount
            && Self.carriesFiles(types())

        if isFileDragOverIsland, !isOverIsland {
            isOverIsland = true
            hasReachedIsland = true
            return .entered
        }
        if !isFileDragOverIsland, isOverIsland {
            isOverIsland = false
            return .left
        }
        return .none
    }

    mutating func mouseUp() -> Step {
        let reached = hasReachedIsland
        self = IslandFileDragTracker()
        return reached ? .ended : .none
    }
}
