import AppKit
import Foundation
import Observation
import os

let nookTodoDueLog = Logger(subsystem: "app.openisland", category: "nook.todo.due")

/// Says what is due on the closed notch (D69). It asks the rules in
/// `NookTodoDueNotice` what to say whenever something could have changed:
/// at launch, at 9 AM, when the Mac wakes, when the clock or the day changes,
/// when the list changes (a load or an add), when its switch is turned on, and
/// when a person becomes able to see the notch. A new time zone moves the
/// morning timer and then waits for the list: the due days in it are midnights
/// in the zone they were read in, and the hub has the source read them again.
///
/// A notice counts as shown only once a person could see it: the screen
/// unlocked, the island closed, the display's notices on and no recording
/// running (`NookTodoDueSight`). It is written to the saved record after it
/// stayed up its whole time without another notice replacing it. One that
/// was not seen is not recorded, which means the next look finds it again.
/// It never takes the closed notch from a notice another feature put there:
/// it waits until that one is gone.
@MainActor
@Observable
final class NookTodoDueReminder {
    /// The switch in the To-do settings. On until it is turned off.
    static let enabledKey = "nook.todo.remindOnDueDay"
    /// The days already shown, keyed by task ID and date.
    static let shownKey = "nook.todo.dueNoticesShown"
    /// How long one notice stays on the closed notch.
    static let noticeDuration: Duration = .seconds(6)
    /// The pause between two notices that come together: the first one's time on screen and a little more.
    static let noticeSpacing: Duration = noticeDuration + .milliseconds(500)
    /// Added to the wait for the next 9 AM, so the timer never lands a hair early.
    private static let timerPadding: TimeInterval = 1

    /// Asked once a notice has had its time. True when it stayed on the
    /// closed notch for the whole time and no other notice took its place.
    typealias Stayed = () -> Bool

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled {
                check()
            } else {
                dropQueuedNotices()
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let calendar: () -> Calendar
    @ObservationIgnored private let remindAt: NookTodoDueTime
    @ObservationIgnored private let spacing: Duration
    /// Where the system posts a time zone, clock or day change.
    @ObservationIgnored private let notifications: NotificationCenter
    @ObservationIgnored private var items: () -> [NookTodoItem] = { [] }
    @ObservationIgnored private var canShow: () -> Bool = { false }
    @ObservationIgnored private var whyHidden: () -> String? = { nil }
    @ObservationIgnored private var isOtherNoticeUp: () -> Bool = { false }
    @ObservationIgnored private var show: (NookTodoDueNotice) -> Stayed = { _ in { false } }
    @ObservationIgnored private var shown: NookTodoDueShown
    @ObservationIgnored private var queue: [NookTodoDueNotice] = []
    /// The notice on the closed notch now, and the question that says
    /// whether it stayed there.
    @ObservationIgnored private var presenting: NookTodoDueNotice?
    @ObservationIgnored private var stayed: Stayed = { false }
    /// Holds the wait for the presented notice's time, and then the wait
    /// before a notice that was not seen is tried again.
    @ObservationIgnored private var presenter: Task<Void, Never>?
    @ObservationIgnored private var morningTimer: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var timeObservers: [any NSObjectProtocol] = []
    @ObservationIgnored private var hasStarted = false
    /// How long the morning timer was last set to wait. Read by tests.
    @ObservationIgnored private(set) var scheduledMorningDelay: TimeInterval?

    /// `clock` and `calendar` are the only places the real time is read. A
    /// test hands in its own, a shorter `spacing` and a center of its own for
    /// the time, clock and day changes. The calendar is asked every time, and
    /// the default follows the Mac's time zone as it changes (D5):
    /// `Calendar.current` keeps the zone the app started in.
    init(
        defaults: UserDefaults = .standard,
        clock: @escaping () -> Date = { Date() },
        calendar: @escaping () -> Calendar = { .autoupdatingCurrent },
        remindAt: NookTodoDueTime = .morning,
        spacing: Duration = NookTodoDueReminder.noticeSpacing,
        notifications: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.clock = clock
        self.calendar = calendar
        self.remindAt = remindAt
        self.spacing = spacing
        self.notifications = notifications
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        shown = NookTodoDueShown(keys: defaults.stringArray(forKey: Self.shownKey) ?? [])
    }

    /// Joins the reminder to the to-do list and the closed notch, and looks
    /// once. `items` reads the list of the source in use. `canShow` says
    /// whether a person could see the closed notch right now; it is read
    /// where the observation can follow it, which makes a change in it look again.
    /// `whyHidden` says in words why nobody could see it, for the log.
    /// `isOtherNoticeUp` says whether a notice is on the closed notch now.
    /// It is read where the observation can follow it, which makes a notice
    /// that goes away look again. The reminder's own notice is gone by the
    /// time it asks (see `presentNext`). `show` puts a notice up and hands
    /// back the question of whether it stayed. Calling it again does nothing.
    func start(
        items: @escaping () -> [NookTodoItem],
        canShow: @escaping () -> Bool,
        whyHidden: @escaping () -> String? = { nil },
        isOtherNoticeUp: @escaping () -> Bool = { false },
        show: @escaping (NookTodoDueNotice) -> Stayed
    ) {
        guard !hasStarted else { return }
        hasStarted = true
        self.items = items
        self.canShow = canShow
        self.whyHidden = whyHidden
        self.isOtherNoticeUp = isOtherNoticeUp
        self.show = show
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.timeMoved(because: "the Mac woke", looksNow: true) }
        }
        // A moved time zone, a set clock or a new day all change when 9 AM
        // is, and what day it is. The timer was set for the old time (D5).
        // The list is read again after a new time zone (D3 of the third
        // review fixes). Looking before it lands would read the old midnights
        // in the new zone, and a task due today could look a day late.
        let changes: [(name: Notification.Name, reason: String, looksNow: Bool)] = [
            (.NSSystemTimeZoneDidChange, "the time zone changed", false),
            (.NSSystemClockDidChange, "the clock was set", true),
            (.NSCalendarDayChanged, "the day changed", true),
        ]
        timeObservers = changes.map { change in
            notifications.addObserver(forName: change.name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.timeMoved(because: change.reason, looksNow: change.looksNow) }
            }
        }
        scheduleMorning()
        observeInputs()
        check()
    }

    // MARK: Looking

    /// Works out what is new to say right now and shows it, when a person
    /// could see it. Remembers nothing until a notice has been seen.
    func check() {
        guard hasStarted else { return }
        guard isEnabled else {
            nookTodoDueLog.debug("Not looking: the due-day reminder is switched off")
            return
        }
        let now = clock()
        let calendar = calendar()
        trimRecord(now: now, calendar: calendar)
        guard canShow() else {
            let reason = whyHidden() ?? "nobody could see the closed notch"
            if presenting != nil || !queue.isEmpty {
                nookTodoDueLog.info("Holding the due-day reminder: \(reason, privacy: .public)")
            } else {
                nookTodoDueLog.debug("Not speaking: \(reason, privacy: .public)")
            }
            dropQueuedNotices()
            return
        }
        // What is on the notch now is spoken for, but not yet recorded.
        let spokenFor = presenting.map { shown.recording([$0]) } ?? shown
        let today = items()
        queue = NookTodoDueNotice.notices(
            items: today, now: now, calendar: calendar, shown: spokenFor, remindAt: remindAt
        )
        if queue.isEmpty {
            let silence = NookTodoDueNotice.silence(
                items: today, now: now, calendar: calendar, shown: spokenFor, remindAt: remindAt
            )
            nookTodoDueLog.debug("Nothing to say: \((silence ?? .nothingDue).logText, privacy: .public)")
        }
        presentNext()
    }

    /// The time under the timer moved: sets the morning timer again for the
    /// 9 AM that is next now, and looks, unless the list is about to change
    /// too. Then the list changing looks (`observeInputs`).
    private func timeMoved(because reason: String, looksNow: Bool) {
        scheduleMorning()
        guard looksNow else {
            nookTodoDueLog.info("Waiting for the list because \(reason, privacy: .public)")
            return
        }
        nookTodoDueLog.info("Looking again because \(reason, privacy: .public)")
        check()
    }

    /// Looks again when the list changes (a load, an add, another source),
    /// when a person becomes able, or unable, to see the notch, or when a
    /// notice on it comes or goes.
    /// `withObservationTracking` fires its `onChange` once per registration.
    private func observeInputs() {
        withObservationTracking {
            _ = items()
            _ = canShow()
            _ = isOtherNoticeUp()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeInputs()
                self.check()
            }
        }
    }

    // MARK: The record

    private func trimRecord(now: Date, calendar: Calendar) {
        let kept = shown.trimmed(now: now, calendar: calendar)
        guard kept != shown else { return }
        shown = kept
        defaults.set(kept.saved, forKey: Self.shownKey)
    }

    private func record(_ notice: NookTodoDueNotice) {
        shown = shown.recording([notice])
        defaults.set(shown.saved, forKey: Self.shownKey)
    }

    // MARK: The morning

    /// How long from `now` until the clock next reads `time`: today's, or
    /// tomorrow's once today's has gone by.
    static func delayUntilNext(_ time: NookTodoDueTime, after now: Date, calendar: Calendar) -> TimeInterval {
        let today = calendar.startOfDay(for: now)
        for dayOffset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today),
                  let moment = calendar.date(
                      bySettingHour: time.hour, minute: time.minute, second: 0, of: day, matchingPolicy: .nextTime
                  ),
                  moment > now else { continue }
            return moment.timeIntervalSince(now)
        }
        return 24 * 60 * 60
    }

    /// Looks again at the next 9 AM, and again after that, every day.
    private func scheduleMorning() {
        morningTimer?.cancel()
        let delay = Self.delayUntilNext(remindAt, after: clock(), calendar: calendar()) + Self.timerPadding
        scheduledMorningDelay = delay
        morningTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.check()
            self.scheduleMorning()
        }
    }

    // MARK: Showing

    /// Shows the first notice waiting, unless one is on the notch already or
    /// is being waited out. The rest follow one at a time: each is looked
    /// for again when the one before has had its time.
    ///
    /// A notice of another feature on the notch holds this one back, and
    /// that notice going away looks again (`observeInputs`). This reminder's
    /// own notice does not hold it back: this runs only while `presenter`
    /// is nil, `finish` clears that after the spacing, and the spacing is
    /// longer than the time a notice is shown for.
    private func presentNext() {
        guard presenter == nil, !queue.isEmpty else { return }
        guard !isOtherNoticeUp() else {
            nookTodoDueLog.debug("Holding the due-day reminder: another notice is on the closed notch")
            return
        }
        let notice = queue.removeFirst()
        presenting = notice
        stayed = show(notice)
        nookTodoDueLog.info(
            "Showing a due-day notice (\(notice.logKind, privacy: .public)) for \(notice.itemIDs.count, privacy: .public) to-do(s)"
        )
        let spacing = spacing
        presenter = Task { @MainActor [weak self] in
            try? await Task.sleep(for: spacing)
            guard !Task.isCancelled, let self else { return }
            self.finish(notice)
        }
    }

    /// The notice has had its time. It is recorded when it was seen to the
    /// end. Otherwise it is left out of the record, and tried again.
    private func finish(_ notice: NookTodoDueNotice) {
        presenter = nil
        presenting = nil
        guard canShow() else {
            // Nobody could see the last of it. A change in what hid it
            // looks again by itself.
            nookTodoDueLog.info("A due-day notice ended unseen; it will be shown again")
            return
        }
        guard stayed() else {
            // Another notice took its place. Give that one a notice's time,
            // then say this one again.
            nookTodoDueLog.info("A due-day notice was replaced by another; it will be shown again")
            let wait = spacing
            presenter = Task { @MainActor [weak self] in
                try? await Task.sleep(for: wait)
                guard !Task.isCancelled, let self else { return }
                self.presenter = nil
                self.check()
            }
            return
        }
        record(notice)
        check()
    }

    /// Puts away what is waiting and what is on the notch, without recording
    /// any of it.
    private func dropQueuedNotices() {
        queue.removeAll()
        presenter?.cancel()
        presenter = nil
        presenting = nil
    }
}
