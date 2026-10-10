import Foundation

// The tour's page for moving and resizing widgets (D44). The user picks one
// widget, the app puts the real island into editing with that widget
// outlined, and the page gives one instruction at a time, ticking each as
// the island shows it done. Each step names a gesture the app really has,
// and `proofs` ties it to the code that does it, the way the tips and the
// widget lines are tied (`OnboardingRearrangeProofTests` fails when that
// text is renamed or removed).

/// One step of the walk-through, in the order it is asked. The string keys
/// are `onboarding.arrange.<case>.title` and, for the steps that have one,
/// `onboarding.arrange.<case>.how`.
enum OnboardingRearrangeStep: String, CaseIterable, Identifiable, Sendable {
    /// `NookWidgetGrid` and `NookWidgetEditChrome`: a drag on a tile in edit
    /// mode reorders the page.
    case move
    /// `NookWidgetEditChrome`: the grip in a tile's corner snaps the tile to
    /// the next size, one step to each `resizeStep` of drag.
    case resize
    /// `NookWidgetEditChrome`: the orange button the island shows under the
    /// widgets, which the page names in the app's own word.
    case finish

    var id: String { rawValue }

    var titleKey: String { "onboarding.arrange.\(rawValue).title" }
    /// How to do it, in a second line. Finishing needs none.
    var howKey: String? { self == .finish ? nil : "onboarding.arrange.\(rawValue).how" }
    /// The one ticked line a done step collapses to.
    var doneKey: String { "onboarding.arrange.\(rawValue).done" }

    /// The code that does what the step says.
    var proofs: [OnboardingProof] {
        switch self {
        case .move: [
            .nook("Views/NookWidgetGrid.swift", "DragGesture(minimumDistance: 4, coordinateSpace: .nookWidgetEditing)"),
            .nook("Views/NookWidgetGrid.swift", "if let index = step.moveTo { onMove(kind, index) }"),
            .nook("Views/NookWidgetEditChrome.swift", ".gesture(reorder)"),
        ]
        case .resize: [
            .nook("Views/NookWidgetEditChrome.swift", "private var resizeGrip: some View"),
            .nook("Views/NookWidgetEditChrome.swift", "NookWidgetLayout.snappedSize(from: start, translation: value.translation)"),
            .nook("NookWidgetLayout.swift", "static let resizeStep: CGFloat = 60"),
            .nook("NookWidgetLayout.swift", "case .small: \"Small\""),
            .nook("NookWidgetLayout.swift", "case .medium: \"Medium\""),
            .nook("NookWidgetLayout.swift", "case .large: \"Large\""),
        ]
        case .finish: [
            .nook("Views/NookWidgetEditChrome.swift", "Text(\"Done\")"),
            .nook("Views/NookPanelView.swift", "onDone: { setEditing(false) }"),
        ]
        }
    }

    /// The tile's ring and the door that starts editing, which the page
    /// leans on from its first moment.
    static let outlineProofs: [OnboardingProof] = [
        .nook("Views/NookWidgetGrid.swift", ".overlay { if outlinedKind == kind { NookWidgetTourRing() } }"),
        .nook("Views/NookPanelView.swift", "outlinedKind: nook.tourOutlinedWidget"),
    ]
}

/// The widget the user picked, and what the tour knows about the moment it
/// was picked.
struct OnboardingArrangePick: Equatable, Sendable {
    var kind: NookWidgetKind
    /// The widget page when it was picked, which the moves are measured from.
    var atPick: [NookWidgetPlacement]
    /// True once editing, which the tour started, has ended. It stays true
    /// if the user starts editing again by hand.
    var hasEndedEditing = false
}

/// What the page shows, a pure function of the picked widget, the page when
/// it was picked, the page now, whether the island is editing, and whether
/// editing ended after the tour started it.
struct OnboardingArrangeProgress: Equatable, Sendable {
    var kind: NookWidgetKind
    /// False when the widget has left the page since it was picked.
    var isOnPage: Bool
    /// The widget sits in another place in the order.
    var moved: Bool
    /// The widget has another size.
    var resized: Bool
    /// Editing ended after the tour started it, and is not on again.
    var finished: Bool
    /// The widget's size now, nil when it is off the page.
    var size: NookWidgetSize?
    var isEditing: Bool

    static func reading(
        picked kind: NookWidgetKind,
        atPick: [NookWidgetPlacement],
        now: [NookWidgetPlacement],
        isEditing: Bool,
        editingEnded: Bool
    ) -> OnboardingArrangeProgress {
        let current = now.first { $0.kind == kind }
        let before = atPick.first { $0.kind == kind }
        // Place in the order among the widgets both pages have, which keeps
        // adding or taking off another widget from counting as a move.
        let shared = Set(atPick.map(\.kind)).intersection(now.map(\.kind))
        func place(_ page: [NookWidgetPlacement]) -> Int? {
            page.map(\.kind).filter(shared.contains).firstIndex(of: kind)
        }
        let isOnPage = current != nil
        return OnboardingArrangeProgress(
            kind: kind,
            isOnPage: isOnPage,
            moved: isOnPage && place(atPick) != place(now),
            resized: current.map { $0.size != before?.size } ?? false,
            finished: editingEnded && !isEditing,
            size: current?.size,
            isEditing: isEditing
        )
    }

    func isDone(_ step: OnboardingRearrangeStep) -> Bool {
        switch step {
        case .move: moved
        case .resize: resized
        case .finish: finished
        }
    }

    /// The step to ask for now: the first one not done. Nil when all three
    /// are, and a step done out of order counts as done.
    var current: OnboardingRearrangeStep? {
        OnboardingRearrangeStep.allCases.first { !isDone($0) }
    }

    /// The steps already done, in the order they are asked.
    var doneSteps: [OnboardingRearrangeStep] {
        OnboardingRearrangeStep.allCases.filter(isDone)
    }

    var isAllDone: Bool { current == nil }

    /// True when the widget is on the page, steps are left and the island is
    /// not editing: the page says how to start again.
    var needsEditing: Bool { isOnPage && !isEditing && current != nil }
}
