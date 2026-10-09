import EventKit
import Foundation

/// One EventKit permission as a service sees it: how to read where it
/// stands and how to ask for it. The app hands in EventKit itself. A test
/// hands in closures of its own, which keeps a test from ever raising the
/// real macOS prompt.
struct NookEventKitAccess {
    /// Where the permission stands. Reading it never prompts.
    var status: @MainActor () -> EKAuthorizationStatus
    /// Asks macOS for full access. The one call that can raise the prompt.
    var request: @MainActor () async -> Void

    /// The calendar permission of a real event store.
    @MainActor
    static func events(in store: EKEventStore) -> NookEventKitAccess {
        NookEventKitAccess(
            status: { EKEventStore.authorizationStatus(for: .event) },
            request: { _ = try? await store.requestFullAccessToEvents() }
        )
    }

    /// The reminders permission of a real event store.
    @MainActor
    static func reminders(in store: EKEventStore) -> NookEventKitAccess {
        NookEventKitAccess(
            status: { EKEventStore.authorizationStatus(for: .reminder) },
            // A failed request shows in the status read afterwards.
            request: { _ = try? await store.requestFullAccessToReminders() }
        )
    }
}

/// A moment at which a widget's permission could be asked for.
enum NookAccessMoment: Equatable, Sendable {
    /// The app is starting. Nothing is ever asked for here: the user has
    /// done nothing yet, and on a fresh install the welcome tour is up.
    case launch
    /// The widget's tile came into view on the Nook page of an island the
    /// user opened.
    case shown
    /// The user switched the widget on in Settings, or picked Reminders as
    /// the to-do source there.
    case turnedOn
}

/// The EventKit permissions the Nook uses.
enum NookEventKitPermission: Hashable, Sendable {
    case calendar
    case reminders
}

/// When the calendar and reminders permissions are asked for. Pure: the
/// models gather the facts and act on the answer.
///
/// Before, both were asked for at launch, which on a fresh install put two
/// macOS prompts over the welcome tour before the user had done anything.
/// Now each waits until its widget is first shown or turned on. An install
/// that already answered is never asked again: macOS shows a prompt only
/// for a permission that was never decided.
enum NookAccessTiming {
    /// The permissions a widget needs asked for at a moment. Empty at
    /// launch, for a widget that is switched off, and for every widget
    /// that reads neither the calendar nor Reminders. The to-do widget
    /// needs Reminders only while Reminders is its source.
    static func permissions(
        for kind: NookWidgetKind,
        at moment: NookAccessMoment,
        isEnabled: Bool,
        todoSource: NookTodoSourceKind
    ) -> Set<NookEventKitPermission> {
        guard moment != .launch, isEnabled else { return [] }
        switch kind {
        case .calendar:
            return [.calendar]
        case .todo:
            return todoSource == .reminders ? [.reminders] : []
        case .media, .notes, .tray, .timer, .mirror, .weather:
            return []
        }
    }

    /// Whether macOS should be asked now: only for a permission that was
    /// never decided, and never while an earlier request is still up.
    static func shouldRequest(status: EKAuthorizationStatus, isAlreadyAsking: Bool) -> Bool {
        status == .notDetermined && !isAlreadyAsking
    }

    /// The widgets the user is looking at: the island is open on the Nook
    /// page, the user opened it, and the widget has a tile on that page.
    /// The boot animation also opens the island, a moment after launch and
    /// by itself, which is why an island it opened shows nothing "to the
    /// user" until a click or a link pins it.
    static func widgetsInView(
        status: NotchStatus,
        reason: NotchOpenReason?,
        showsNookPage: Bool,
        pageWidgets: [NookWidgetKind]
    ) -> Set<NookWidgetKind> {
        guard status == .opened, showsNookPage else { return [] }
        switch reason {
        case .click, .hover:
            return Set(pageWidgets)
        case .boot, .notification, nil:
            return []
        }
    }
}
