import EventKit
import Foundation
import Observation

/// Where the todo card gets its tasks.
enum NookTodoSourceKind: String, CaseIterable, Identifiable, Sendable {
    case reminders
    case notion
    case tickTick = "ticktick"

    var id: String { rawValue }
}

/// Whether a source can show tasks right now.
enum NookTodoConnection: Equatable, Sendable {
    case ready
    /// Not usable yet. The message says why, in words for the user.
    case unavailable(message: String)
}

/// The surface the todo card needs from a task source.
@MainActor
protocol NookTodoSource: AnyObject {
    var items: [NookTodoItem] { get }
    /// Shown in the card header: the list or database name.
    var displayName: String { get }
    var connection: NookTodoConnection { get }
    /// A problem with the last action or refresh, shown under the rows.
    var errorMessage: String? { get }
    /// True while the last notes save is the thing that failed. The notes
    /// page keeps its draft then, because the row went back to the old
    /// notes. Any other problem in `errorMessage` says nothing about the
    /// notes, and the page goes on following the source.
    var notesSaveFailed: Bool { get }
    /// True while the rows come from the last good load, not a live one.
    var isShowingCachedItems: Bool { get }
    var canAdd: Bool { get }
    var canComplete: Bool { get }
    /// Whether a task's notes can be written back right now.
    var canEditNotes: Bool { get }
    /// Why notes are read-only, in words for the user. Nil while editable.
    var notesUnavailableReason: String? { get }
    /// Whether a due date can be saved with a new task right now.
    var canSetDue: Bool { get }
    /// Why dates cannot be set, in words for the user. Nil while they can.
    var dueUnavailableReason: String? { get }
    var addPlaceholder: String { get }
    /// How often the card should ask for a refresh while it is on screen.
    /// Nil for sources that push their own changes.
    var autoRefreshInterval: Duration? { get }

    /// Called when the card appears.
    func refresh()
    /// Called by the card's repeating timer.
    func refreshOnTimer()
    /// Adds a task. `due` is a whole day (year, month and day) or nil for no
    /// date. A source that cannot set a date ignores it.
    func add(_ title: String, due: DateComponents?)
    /// Adds a task and answers whether the source took it. The card keeps the
    /// typed title and the picked day until this says yes. A failed add
    /// loses neither (D2). Why a source said no is its `errorMessage`.
    func addConfirmed(_ title: String, due: DateComponents?) async -> Bool
    func complete(_ id: String)
    /// Saves a task's notes. Empty text clears them.
    func setNotes(_ notes: String, for id: String)
}

extension NookTodoSource {
    var notesSaveFailed: Bool { false }

    /// For a source that cannot tell: hands the task to `add` and says yes.
    func addConfirmed(_ title: String, due: DateComponents?) async -> Bool {
        add(title, due: due)
        return true
    }

    /// A task with no date. The demo's scripted adds and the small card call
    /// this; the medium and large cards pass the picked day to `add(_:due:)`.
    func add(_ title: String) {
        add(title, due: nil)
    }
}

extension NookRemindersService: NookTodoSource {
    var displayName: String { currentListName }

    var connection: NookTodoConnection {
        if hasAccess { return .ready }
        return .unavailable(
            message: authorization == .notDetermined ? "Waiting for Reminders access" : "Reminders access needed"
        )
    }

    var errorMessage: String? { lastWriteError.map { LanguageManager.shared.t($0.messageKey) } }
    var notesSaveFailed: Bool { lastWriteError == .notesFailed }
    var isShowingCachedItems: Bool { false }
    var canAdd: Bool { hasAccess }
    var canComplete: Bool { hasAccess }
    var canEditNotes: Bool { hasAccess }
    var notesUnavailableReason: String? {
        hasAccess ? nil : LanguageManager.shared.t("nook.todo.notes.remindersAccess")
    }
    var canSetDue: Bool { hasAccess }
    var dueUnavailableReason: String? {
        hasAccess ? nil : LanguageManager.shared.t("nook.todo.due.unavailable")
    }
    var addPlaceholder: String { "Add a reminder" }
    /// EventKit posts change notifications, which the service already observes.
    var autoRefreshInterval: Duration? { nil }

    func refreshOnTimer() {}
}

/// Owns the choice of task source and the two services that read tasks from
/// the network. `NookModel` holds one; the Reminders service stays where it
/// always was, on `nook.reminders`.
@MainActor
@Observable
final class NookTodoHub {
    static let sourceKey = "nook.todo.source"

    let notion: NookNotionTodoService
    let tickTick: NookTickTickTodoService
    /// Says what is due on the closed notch (D69).
    let dueReminder: NookTodoDueReminder

    /// Notes text that has not reached its source, by task ID: a save that
    /// failed, or a draft left when its task went away. The notes page
    /// opens with it, and the list marks the task. Lives as long as the app.
    var noteDrafts: [String: String] = [:]

    /// The date picker's popover is up. It is a window of its own. A click
    /// in it lands outside the island's area and would close the island and
    /// the task typed in it. The click rule reads this like the tray's share
    /// picker (D7). The card sets it and clears it when it goes away.
    var isPickingDate = false

    var selectedKind: NookTodoSourceKind {
        didSet {
            guard selectedKind != oldValue else { return }
            defaults.set(selectedKind.rawValue, forKey: Self.sourceKey)
            applySelection()
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    /// Tells whether the screen is on and unlocked, for the due-day reminder.
    @ObservationIgnored private let presence: IslandScreenPresence
    /// Where the system posts a time zone change. A test has a center of its own.
    @ObservationIgnored private let notifications: NotificationCenter
    @ObservationIgnored private var timeZoneObserver: (any NSObjectProtocol)?
    @ObservationIgnored private(set) weak var nook: NookModel?
    @ObservationIgnored private var hasStarted = false

    init(
        defaults: UserDefaults = .standard,
        notion: NookNotionTodoService? = nil,
        tickTick: NookTickTickTodoService? = nil,
        tokenMoves: NookTodoTokenMoves = .forThisRun,
        dueReminder: NookTodoDueReminder? = nil,
        presence: IslandScreenPresence = .shared,
        notifications: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.presence = presence
        self.notifications = notifications
        // The real services are the only ones that can reach the Keychain,
        // and only to bring an older token over when the user asks. A test
        // run gets no way to reach it, whatever the test builds.
        self.notion = notion ?? NookNotionTodoService(defaults: defaults, tokenMove: tokenMoves.notion)
        self.tickTick = tickTick ?? NookTickTickTodoService(defaults: defaults, tokenMove: tokenMoves.tickTick)
        self.dueReminder = dueReminder ?? NookTodoDueReminder(defaults: defaults)
        selectedKind = defaults.string(forKey: Self.sourceKey).flatMap(NookTodoSourceKind.init(rawValue:)) ?? .reminders
        self.notion.onNotesWriteFinished = { [weak self] id, text, saved in
            self?.notesWriteFinished(id: id, text: text, saved: saved)
        }
        self.tickTick.onNotesWriteFinished = { [weak self] id, text, saved in
            self?.notesWriteFinished(id: id, text: text, saved: saved)
        }
    }

    /// Keeps text that failed to save. Drops a kept draft once that same
    /// text is saved.
    func notesWriteFinished(id: String, text: String, saved: Bool) {
        if !saved {
            noteDrafts[id] = text
        } else if noteDrafts[id] == text {
            noteDrafts[id] = nil
        }
    }

    func start(nook: NookModel) {
        self.nook = nook
        hasStarted = true
        applySelection()
        // Added before the reminder starts, which runs this first: the
        // reminder sets its morning timer from the zone this has read again.
        if timeZoneObserver == nil {
            timeZoneObserver = notifications.addObserver(
                forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.timeZoneChanged() }
            }
        }
        startDueReminder(nook: nook)
    }

    /// The Mac is in a new time zone. A due day is kept as midnight in the
    /// zone it was read in, which makes the list held now read a day off in
    /// the new zone: a task due today can look overdue. The source in use reads its
    /// list again, which builds the days in the new zone, and the reminder
    /// looks once the new list lands (`NookTodoDueReminder`). The refresh is
    /// a manual one, which the spacing between refreshes does not skip.
    private func timeZoneChanged() {
        // Foundation can go on handing out the zone it first read.
        NSTimeZone.resetSystemTimeZone()
        guard let nook else { return }
        switch selectedKind {
        case .reminders: nook.reminders.refresh()
        case .notion: notion.refresh(.manual)
        case .tickTick: tickTick.refresh(.manual)
        }
    }

    /// What could hide a closed-notch notice right now. Each input is read,
    /// which lets an observation around it follow all of them.
    private static func sight(of nook: NookModel, presence: IslandScreenPresence) -> NookTodoDueSight {
        NookTodoDueSight(
            isScreenOn: presence.isOn,
            isIslandOpen: nook.isIslandOpen(),
            showsNotices: nook.activeDisplay.showsNotices,
            isRecording: nook.record.phase.isBusy
        )
    }

    /// The due-day reminder reads the list of the source in use, and shows
    /// its notices on the closed notch, only while a person could see them.
    private func startDueReminder(nook: NookModel) {
        let presence = presence
        dueReminder.start(
            items: { [weak self, weak nook] in
                guard let self, let nook else { return [] }
                return self.source(reminders: nook.reminders).items
            },
            // Every input is read before they are combined, which lets the
            // observation follow all of them.
            canShow: { [weak nook] in
                guard let nook else { return false }
                return Self.sight(of: nook, presence: presence).canSee
            },
            whyHidden: { [weak nook] in
                guard let nook else { return "the island is gone" }
                return Self.sight(of: nook, presence: presence).reasonHidden
            },
            isOtherNoticeUp: { [weak nook] in nook?.transient != nil },
            show: { [weak nook] notice in
                guard let nook else { return { false } }
                let serial = nook.showTransient(
                    symbol: NookTodoDueNotice.symbol,
                    text: notice.text(lang: .shared),
                    duration: NookTodoDueReminder.noticeDuration
                )
                return { [weak nook] in nook?.transientRanItsTime(serial) ?? false }
            }
        )
    }

    /// The source the card and settings should read.
    func source(reminders: NookRemindersService) -> any NookTodoSource {
        switch selectedKind {
        case .reminders: reminders
        case .notion: notion
        case .tickTick: tickTick
        }
    }

    /// A network source does no token file, disk or network work unless it
    /// is the selected one.
    private func applySelection() {
        guard hasStarted else { return }
        notion.setActive(selectedKind == .notion)
        tickTick.setActive(selectedKind == .tickTick)
    }
}

/// The pages a task source's token is made on. The rows in Settings and
/// the welcome tour link to the same ones.
enum NookTodoSetupLink {
    /// Where an internal integration is created in Notion.
    static let notionIntegrations = URL(string: "https://www.notion.so/my-integrations")
    /// The TickTick web app. The API token is made there, under Settings,
    /// Account.
    static let tickTickWebApp = URL(string: "https://ticktick.com/webapp/")

    /// Nil for Reminders, which needs no token.
    static func url(for kind: NookTodoSourceKind) -> URL? {
        switch kind {
        case .reminders: nil
        case .notion: notionIntegrations
        case .tickTick: tickTickWebApp
        }
    }
}
