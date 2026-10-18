import Foundation
import Observation

/// One app on the card with the service that reads it, in the order the
/// card shows them (T3).
struct NookTodoSection: Identifiable {
    let kind: NookTodoSourceKind
    let source: any NookTodoSource

    var id: NookTodoSourceKind { kind }
}

/// Owns which task apps are on, which one a typed task goes to, and the
/// services that read tasks from the network (D83, replacing D13). The
/// Reminders service stays where it always was, on `nook.reminders`.
///
/// Every reader of tasks (the card, the calendar's marks, the 9 AM notice,
/// the closed island's count) reads the merged list of the apps that are
/// on, through `sections(reminders:)` or `items(reminders:)`.
@MainActor
@Observable
final class NookTodoHub {
    /// The app a typed task goes to. Before D83 this was the one app the
    /// card read, and the tour still writes it that way (`selectedKind`).
    static let sourceKey = "nook.todo.source"
    /// The apps that are on, as their raw names, in no particular order.
    /// Absent on a copy from before D83, which had one app: the one
    /// `sourceKey` names.
    static let sourcesKey = "nook.todo.sources"

    let notion: NookNotionTodoService
    let tickTick: NookTickTickTodoService
    let asana: NookAsanaTodoService
    let monday: NookMondayTodoService
    let canvas: NookCanvasTodoService
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

    /// The apps that are on, in the order Settings and the card show them
    /// (T3). Empty leaves the card with nothing to read.
    private(set) var enabledKinds: [NookTodoSourceKind] {
        didSet {
            guard enabledKinds != oldValue else { return }
            defaults.set(enabledKinds.map(\.rawValue), forKey: Self.sourcesKey)
            applySelection()
        }
    }

    /// The app a typed task goes to: the add box's chip (T6). One that is
    /// on and takes tasks whenever there is one.
    private(set) var addKind: NookTodoSourceKind {
        didSet {
            guard addKind != oldValue else { return }
            defaults.set(addKind.rawValue, forKey: Self.sourceKey)
        }
    }

    /// The one app, the way the tour and Settings before D83 picked it:
    /// setting it turns that app on alone and sends typed tasks to it.
    /// Reading it gives the app typed tasks go to.
    var selectedKind: NookTodoSourceKind {
        get { addKind }
        set { setOnlyKind(newValue) }
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
        asana: NookAsanaTodoService? = nil,
        monday: NookMondayTodoService? = nil,
        canvas: NookCanvasTodoService? = nil,
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
        self.asana = asana ?? NookAsanaTodoService(defaults: defaults)
        self.monday = monday ?? NookMondayTodoService(defaults: defaults)
        self.canvas = canvas ?? NookCanvasTodoService(defaults: defaults)
        self.dueReminder = dueReminder ?? NookTodoDueReminder(defaults: defaults)
        let legacy = defaults.string(forKey: Self.sourceKey).flatMap(NookTodoSourceKind.init(rawValue:)) ?? .reminders
        let saved = defaults.stringArray(forKey: Self.sourcesKey)?.compactMap(NookTodoSourceKind.init(rawValue:))
        let enabled = Self.ordered(saved.map(Set.init) ?? [legacy])
        enabledKinds = enabled
        addKind = Self.addTarget(preferred: legacy, among: enabled)
        for service in [self.notion as any NookTodoNotesWriting, self.tickTick, self.asana, self.monday, self.canvas] {
            service.onNotesWriteFinished = { [weak self] id, text, saved in
                self?.notesWriteFinished(id: id, text: text, saved: saved)
            }
        }
    }

    // MARK: - Which apps are on

    func isEnabled(_ kind: NookTodoSourceKind) -> Bool {
        enabledKinds.contains(kind)
    }

    /// True with two or more apps on: the card then shows sections, dots
    /// and the add chip (T12).
    var hasManyEnabled: Bool { enabledKinds.count > 1 }

    /// The apps the add chip offers: the ones on that take tasks (T14).
    var addableKinds: [NookTodoSourceKind] { enabledKinds.filter(\.takesNewTasks) }

    /// The toggle in Settings. Turning the add target off moves typed
    /// tasks to the first app left that takes them. The last app on stays
    /// on: a card with nothing to read is the widget's switch, not an
    /// empty list.
    func setEnabled(_ kind: NookTodoSourceKind, _ isOn: Bool) {
        var kinds = Set(enabledKinds)
        if isOn { kinds.insert(kind) } else { kinds.remove(kind) }
        guard !kinds.isEmpty else { return }
        enabledKinds = Self.ordered(kinds)
        addKind = Self.addTarget(preferred: addKind, among: enabledKinds)
    }

    /// The tour's pick (D43). On a copy with one app on it is that app in
    /// place of the old one; on a copy that already reads several apps it
    /// turns the picked one on and sends typed tasks there, and the others
    /// stay as they were.
    func pick(_ kind: NookTodoSourceKind) {
        if hasManyEnabled {
            setEnabled(kind, true)
            setAddKind(kind)
        } else {
            setOnlyKind(kind)
        }
    }

    /// The chip's pick: where typed tasks go (T6). Only an app that is on
    /// and takes tasks.
    func setAddKind(_ kind: NookTodoSourceKind) {
        guard addableKinds.contains(kind) else { return }
        addKind = kind
    }

    /// One app on, alone, taking typed tasks: the tour's pick (D43).
    func setOnlyKind(_ kind: NookTodoSourceKind) {
        enabledKinds = [kind]
        addKind = Self.addTarget(preferred: kind, among: enabledKinds)
    }

    /// The apps in the order Settings and the card show them (T3).
    static func ordered(_ kinds: Set<NookTodoSourceKind>) -> [NookTodoSourceKind] {
        NookTodoSourceKind.allCases.filter { kinds.contains($0) }
    }

    /// Where typed tasks go: `preferred` when it is on and takes tasks, else
    /// the first app on that does, else the first app on, else Reminders.
    static func addTarget(preferred: NookTodoSourceKind, among kinds: [NookTodoSourceKind]) -> NookTodoSourceKind {
        if kinds.contains(preferred), preferred.takesNewTasks { return preferred }
        return kinds.first(where: \.takesNewTasks) ?? kinds.first ?? .reminders
    }

    // MARK: - The sources

    /// The service behind one app.
    func source(for kind: NookTodoSourceKind, reminders: NookRemindersService) -> any NookTodoSource {
        switch kind {
        case .reminders: reminders
        case .notion: notion
        case .tickTick: tickTick
        case .asana: asana
        case .monday: monday
        case .canvas: canvas
        }
    }

    /// The source a typed task goes to: the add target's. The tour and the
    /// demo read this one; the card and every other reader take the
    /// merged list.
    func source(reminders: NookRemindersService) -> any NookTodoSource {
        source(for: addKind, reminders: reminders)
    }

    /// Every app that is on with its service, in order (T3).
    func sections(reminders: NookRemindersService) -> [NookTodoSection] {
        enabledKinds.map { NookTodoSection(kind: $0, source: source(for: $0, reminders: reminders)) }
    }

    /// The open tasks of every app that is on and can show them, in
    /// section order. What the calendar's marks, the 9 AM notice and the
    /// closed island's count read.
    func items(reminders: NookRemindersService) -> [NookTodoItem] {
        sections(reminders: reminders).flatMap { $0.source.connection == .ready ? $0.source.items : [] }
    }

    /// The source that holds a task, by the task's id.
    func source(holding id: String, reminders: NookRemindersService) -> (any NookTodoSource)? {
        sections(reminders: reminders).first { $0.source.items.contains { $0.id == id } }?.source
    }

    // MARK: - Notes drafts

    /// Keeps text that failed to save. Drops a kept draft once that same
    /// text is saved.
    func notesWriteFinished(id: String, text: String, saved: Bool) {
        if !saved {
            noteDrafts[id] = text
        } else if noteDrafts[id] == text {
            noteDrafts[id] = nil
        }
    }

    // MARK: - Lifecycle

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
    /// the new zone: a task due today can look overdue. Every app that is
    /// on reads its list again, which builds the days in the new zone, and
    /// the reminder looks once the new lists land (`NookTodoDueReminder`).
    /// The refresh is a manual one, which the spacing between refreshes
    /// does not skip.
    private func timeZoneChanged() {
        // Foundation can go on handing out the zone it first read.
        NSTimeZone.resetSystemTimeZone()
        guard let nook else { return }
        for kind in enabledKinds {
            switch kind {
            case .reminders: nook.reminders.refresh()
            case .notion: notion.refresh(.manual)
            case .tickTick: tickTick.refresh(.manual)
            case .asana: asana.refresh(.manual)
            case .monday: monday.refresh(.manual)
            case .canvas: canvas.refresh(.manual)
            }
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

    /// The due-day reminder reads the merged list of the apps that are on,
    /// and shows its notices on the closed notch, only while a person
    /// could see them.
    private func startDueReminder(nook: NookModel) {
        let presence = presence
        dueReminder.start(
            items: { [weak self, weak nook] in
                guard let self, let nook else { return [] }
                return self.items(reminders: nook.reminders)
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

    /// A network app does no token file, disk or network work unless it is
    /// on (D37, D83).
    private func applySelection() {
        guard hasStarted else { return }
        notion.setActive(isEnabled(.notion))
        tickTick.setActive(isEnabled(.tickTick))
        asana.setActive(isEnabled(.asana))
        monday.setActive(isEnabled(.monday))
        canvas.setActive(isEnabled(.canvas))
    }
}

/// A service whose notes writes finish in the background and report back
/// to the hub.
@MainActor
protocol NookTodoNotesWriting: AnyObject {
    var onNotesWriteFinished: ((_ id: String, _ text: String, _ saved: Bool) -> Void)? { get set }
}

extension NookNotionTodoService: NookTodoNotesWriting {}
extension NookTickTickTodoService: NookTodoNotesWriting {}
