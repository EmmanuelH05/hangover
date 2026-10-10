import Foundation
import SwiftUI

/// The sample calendar (D51): events placed relative to a moment handed in,
/// which gives the island one coming up at any hour. It stands where EventKit stands
/// for the calendar service and is held in memory only.
@MainActor
final class DemoCalendarSource {
    static let workID = "demo-work"
    static let personalID = "demo-personal"
    static let schoolID = "demo-school"

    /// The link the "in 20 minutes" event carries. It points nowhere, and
    /// the demo island opens no link at all.
    static let meetingURL = URL(string: "https://meet.example.com/standup")

    let calendars = [
        NookCalendarInfo(id: workID, title: "Work", color: .blue),
        NookCalendarInfo(id: personalID, title: "Personal", color: .green),
        NookCalendarInfo(id: schoolID, title: "School", color: .purple),
    ]
    var defaultCalendarID: String? { Self.personalID }

    private(set) var events: [NookCalendarEvent]
    private let calendar: Calendar

    init(now: Date, calendar: Calendar = .current) {
        self.calendar = calendar
        events = Self.makeEvents(now: now, calendar: calendar)
    }

    /// The events that overlap the range, soonest first.
    func events(from start: Date, to end: Date) -> [NookCalendarEvent] {
        events
            .filter { $0.start < end && $0.end > start }
            .sorted { $0.start < $1.start }
    }

    /// Saves a draft the way the event editor and the quick add hand it in.
    func add(_ draft: NookEventDraft) {
        let color = calendars.first { $0.id == draft.calendarID }?.color ?? .green
        events.append(NookCalendarEvent(
            id: "demo-added-\(events.count)",
            title: draft.title,
            start: draft.start,
            end: draft.end,
            isAllDay: draft.isAllDay,
            calendarColor: color,
            location: draft.location.isEmpty ? nil : draft.location,
            calendarID: draft.calendarID ?? Self.personalID,
            meetingURL: nil
        ))
    }

    /// One in 20 minutes with a join link, two later today, and a few on
    /// the days after.
    private static func makeEvents(now: Date, calendar: Calendar) -> [NookCalendarEvent] {
        let minute: TimeInterval = 60
        let hour: TimeInterval = 3600
        let startOfToday = calendar.startOfDay(for: now)
        func day(_ offset: Int, hour: Int, minute: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: offset, to: startOfToday) ?? startOfToday
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }
        func event(
            _ index: Int, _ title: String, _ start: Date, minutes: Int,
            calendarID: String, color: Color, location: String? = nil, link: URL? = nil
        ) -> NookCalendarEvent {
            NookCalendarEvent(
                id: "demo-event-\(index)",
                title: title,
                start: start,
                end: start.addingTimeInterval(TimeInterval(minutes) * minute),
                isAllDay: false,
                calendarColor: color,
                location: location,
                calendarID: calendarID,
                meetingURL: link
            )
        }
        return [
            event(0, "Standup", now.addingTimeInterval(20 * minute), minutes: 15,
                  calendarID: workID, color: .blue, link: meetingURL),
            event(1, "Design review", now.addingTimeInterval(2 * hour), minutes: 60,
                  calendarID: workID, color: .blue, location: "Room 204"),
            event(2, "Gym", now.addingTimeInterval(5 * hour), minutes: 60,
                  calendarID: personalID, color: .green),
            event(3, "Office hours", day(1, hour: 10), minutes: 60,
                  calendarID: schoolID, color: .purple, location: "Room 301"),
            event(4, "Dentist", day(2, hour: 9, minute: 30), minutes: 45,
                  calendarID: personalID, color: .green),
            event(5, "Midterm review", day(3, hour: 16), minutes: 90,
                  calendarID: schoolID, color: .purple),
            event(6, "Dinner with family", day(4, hour: 18, minute: 30), minutes: 120,
                  calendarID: personalID, color: .green, location: "Home"),
        ]
    }
}
