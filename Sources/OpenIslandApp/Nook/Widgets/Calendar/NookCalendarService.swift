import AppKit
import EventKit
import Foundation
import Observation
import SwiftUI

/// One upcoming calendar event, copied out of EventKit as plain values.
struct NookCalendarEvent: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarColor: Color
    let location: String?
    var calendarID: String = ""
    /// Video-meeting link found in the event, if any.
    var meetingURL: URL? = nil
}

@MainActor
@Observable
final class NookCalendarService {
    @ObservationIgnored private(set) weak var nook: NookModel?

    private(set) var events: [NookCalendarEvent] = []
    private(set) var calendars: [NookCalendarInfo] = []
    /// The calendar a new event lands in unless the editor picks another.
    private(set) var defaultCalendarID: String?
    /// Goes up whenever the store may have changed. Views that query a
    /// range read it, which makes them query again.
    private(set) var revision = 0
    /// The last minute tick, for countdowns outside a TimelineView.
    private(set) var lastTick = Date()
    private(set) var authorization: EKAuthorizationStatus = .notDetermined

    static let nextUpEnabledKey = "nook.calendar.nextUpEnabled"
    private static let lookAheadDays = 7
    private static let refreshEveryTicks = 5
    private static let thresholdsMinutes = [10, 2]

    /// Made on first use. The demo mode (D51) never makes one.
    @ObservationIgnored private var madeStore: EKEventStore?
    private var store: EKEventStore {
        if let madeStore { return madeStore }
        let made = EKEventStore()
        madeStore = made
        return made
    }
    /// The settings the next-up switch is kept in.
    @ObservationIgnored private let defaults: UserDefaults
    /// The demo mode's events (D51). When it is set the service reads and
    /// writes these, and EventKit is never touched.
    @ObservationIgnored private let sample: DemoCalendarSource?
    /// The calendar permission: its status and the one way to ask for it.
    @ObservationIgnored private let access: NookEventKitAccess
    /// True while a request is up, which keeps a second one from going out.
    @ObservationIgnored private var isAskingForAccess = false
    /// True when the permission is EventKit's own and not one a test made up.
    @ObservationIgnored private let asksRealEventKit: Bool
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var tickTimer: Timer?
    @ObservationIgnored private var changeObserver: NSObjectProtocol?
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private var firedKeys: Set<String> = []
    /// Range query results, kept until the store changes. Views ask for
    /// the same week or month on every render, including each keystroke.
    @ObservationIgnored private var rangeCache: [ClosedRange<Date>: [NookCalendarEvent]] = [:]
    private static let rangeCacheLimit = 12

    var isNextUpEnabled: Bool {
        get {
            defaults.object(forKey: Self.nextUpEnabledKey) as? Bool ?? true
        }
        set {
            defaults.set(newValue, forKey: Self.nextUpEnabledKey)
        }
    }

    var hasAccess: Bool { authorization == .fullAccess }

    /// `access` is EventKit itself unless a test hands in its own. The demo
    /// mode hands in `sample` and no store is ever made (D51).
    init(access: NookEventKitAccess? = nil, sample: DemoCalendarSource? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.sample = sample
        if sample != nil {
            self.access = NookEventKitAccess(status: { .fullAccess }, request: {})
            asksRealEventKit = false
        } else {
            let store = EKEventStore()
            madeStore = store
            self.access = access ?? .events(in: store)
            asksRealEventKit = access == nil
        }
        authorization = self.access.status()
    }

    /// Starts the minute tick and the change observer, and loads events
    /// when access was granted on an earlier run. Asks macOS for nothing:
    /// a permission that was never decided waits for `requestAccess()`.
    func start(nook: NookModel) {
        self.nook = nook
        hasStarted = true
        guard tickTimer == nil else { return }

        // The demo's sample has no store to change.
        if sample == nil {
            changeObserver = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }

        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer

        refresh()
    }

    /// Asks macOS for full access if that was never decided, then loads
    /// events. Called when the calendar tile first comes into view, when
    /// the widget is turned on in Settings, and by "Allow Access" there.
    /// Never at launch.
    func requestAccess() {
        Task { @MainActor in await requestAccessIfUndecided() }
    }

    /// The same, awaited. True when macOS was asked.
    ///
    /// The real EventKit request goes out only from a service that was
    /// started, which the app does at launch and no test does. A service a
    /// test built with a permission of its own may be asked at any time.
    @discardableResult
    func requestAccessIfUndecided() async -> Bool {
        guard hasStarted || !asksRealEventKit else { return false }
        let status = access.status()
        guard NookAccessTiming.shouldRequest(status: status, isAlreadyAsking: isAskingForAccess) else {
            // Answered already, or a request is up. Events are loaded again
            // only when the answer changed behind the app's back, in System
            // Settings: a tile coming into view must not cost a fetch.
            if status != authorization { refresh() }
            return false
        }
        authorization = status
        isAskingForAccess = true
        await access.request()
        isAskingForAccess = false
        refresh()
        return true
    }

    func refresh() {
        // Whatever the events turn out to be, the Join bar follows them.
        defer { nook?.refreshMeetingPrompt(now: Date()) }
        authorization = access.status()
        revision += 1
        rangeCache.removeAll()
        guard hasAccess else {
            events = []
            calendars = []
            defaultCalendarID = nil
            return
        }
        if let sample {
            calendars = sample.calendars
            defaultCalendarID = sample.defaultCalendarID
            let startOfToday = Calendar.current.startOfDay(for: Date())
            guard let end = Calendar.current.date(byAdding: .day, value: Self.lookAheadDays, to: startOfToday) else { return }
            events = sample.events(from: startOfToday, to: end)
            return
        }
        calendars = store.calendars(for: .event)
            .map {
                NookCalendarInfo(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    color: Color(nsColor: $0.color),
                    allowsChanges: $0.allowsContentModifications
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        defaultCalendarID = store.defaultCalendarForNewEvents?.calendarIdentifier
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: Self.lookAheadDays, to: startOfToday) else { return }

        let predicate = store.predicateForEvents(withStart: startOfToday, end: end, calendars: nil)
        events = store.events(matching: predicate)
            .filter { !Self.isDeclined($0) }
            .map { Self.makeEvent($0) }
            .sorted { $0.start < $1.start }
    }

    /// Events in any range, for the styles that step through days. Empty
    /// without access or when the range is backwards.
    func events(from start: Date, to end: Date) -> [NookCalendarEvent] {
        _ = revision
        guard hasAccess, start < end else { return [] }
        let key = start...end
        if let cached = rangeCache[key] { return cached }
        if let sample {
            let result = sample.events(from: start, to: end)
            rangeCache[key] = result
            return result
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let result = store.events(matching: predicate)
            .filter { !Self.isDeclined($0) }
            .map { Self.makeEvent($0) }
            .sorted { $0.start < $1.start }
        if rangeCache.count >= Self.rangeCacheLimit { rangeCache.removeAll() }
        rangeCache[key] = result
        return result
    }

    /// Saves a new event to the draft's calendar, or to the default one when
    /// the draft names none or names one that cannot take events.
    func addEvent(_ draft: NookEventDraft) throws(NookCalendarError) {
        guard hasAccess else { throw .noAccess }
        if let sample {
            sample.add(draft)
            refresh()
            return
        }
        let chosen = draft.calendarID
            .flatMap { store.calendar(withIdentifier: $0) }
            .flatMap { $0.allowsContentModifications ? $0 : nil }
        guard let calendar = chosen
            ?? store.defaultCalendarForNewEvents
            ?? store.calendars(for: .event).first(where: \.allowsContentModifications) else {
            throw .noWritableCalendar
        }
        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.startDate = draft.start
        // A draft's all-day end is the start of the next day. EventKit counts
        // an all-day event's end as its last day, so step back inside it.
        event.endDate = draft.isAllDay ? max(draft.start, draft.end.addingTimeInterval(-1)) : draft.end
        event.isAllDay = draft.isAllDay
        event.calendar = calendar
        if !draft.location.isEmpty { event.location = draft.location }
        if !draft.notes.isEmpty { event.notes = draft.notes }
        if let offset = draft.alert.offset(isAllDay: draft.isAllDay) {
            event.addAlarm(EKAlarm(relativeOffset: offset))
        }
        if let frequency = Self.frequency(for: draft.repeats) {
            event.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: frequency, interval: 1, end: nil))
        }
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw .saveFailed(error.localizedDescription)
        }
        refresh()
    }

    private static func frequency(for repeats: NookEventRepeat) -> EKRecurrenceFrequency? {
        switch repeats {
        case .never: nil
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Timer

    private func tick() {
        ticks += 1
        lastTick = Date()
        if ticks % Self.refreshEveryTicks == 0 {
            refresh()
        }
        checkNextUp(now: Date())
        nook?.refreshMeetingPrompt(now: Date())
    }

    /// Shows the "in 10 min" and "in 2 min" notices for events that start
    /// then. The minute tick calls it; the demo script calls it with a
    /// moment of its own.
    func checkNextUp(now: Date) {
        guard isNextUpEnabled, hasAccess, let nook else { return }
        for event in events where !event.isAllDay {
            let remaining = event.start.timeIntervalSince(now)
            for minutes in Self.thresholdsMinutes {
                let upper = TimeInterval(minutes * 60)
                // One-minute window per threshold; the timer ticks once a minute.
                guard remaining > upper - 60, remaining <= upper else { continue }
                let key = "\(event.id)|\(minutes)"
                guard firedKeys.insert(key).inserted else { continue }
                nook.showTransient(
                    // A camera says this one can be joined: open the island
                    // and the Join bar is at the top.
                    symbol: event.meetingURL == nil ? "calendar" : "video.fill",
                    text: "\(Self.shortTitle(event.title)) in \(minutes) min",
                    tint: event.calendarColor,
                    duration: .seconds(6)
                )
            }
        }
    }

    // MARK: - Mapping

    private static func isDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
    }

    private static func makeEvent(_ event: EKEvent) -> NookCalendarEvent {
        let title = (event.title?.isEmpty == false ? event.title : nil) ?? "Untitled"
        let start = event.startDate ?? Date()
        let color = event.calendar?.color.map { Color(nsColor: $0) } ?? .accentColor
        let location = event.location?.isEmpty == false ? event.location : nil
        return NookCalendarEvent(
            id: "\(event.eventIdentifier ?? title)|\(start.timeIntervalSince1970)",
            title: title,
            start: start,
            end: event.endDate ?? start,
            isAllDay: event.isAllDay,
            calendarColor: color,
            location: location,
            calendarID: event.calendar?.calendarIdentifier ?? "",
            meetingURL: NookMeetingLink.find(in: [event.url?.absoluteString, event.location, event.notes])
        )
    }

    /// Keep closed-notch text short (about 18 characters in total).
    private static func shortTitle(_ title: String) -> String {
        title.count > 8 ? String(title.prefix(7)) + "…" : title
    }
}
