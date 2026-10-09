import EventKit
import SwiftUI

/// The calendar card. It owns the background, the padding and the no-access
/// state; the look inside comes from the style picked for this display, and
/// the size from the grid cell it sits in.
struct NookCalendarCard: View {
    var nook: NookModel

    @Environment(\.nookWidgetSize) private var size

    private static let maxAgendaRows = 3
    private static let horizontalPadding: CGFloat = 14
    private static let verticalPadding: CGFloat = 12

    /// Height at each size. Small rows always use the grid's shared
    /// height; large adds the "Up next" list under the chosen look.
    static func height(for size: NookWidgetSize, style: NookCalendarStyle) -> CGFloat {
        switch size {
        case .small: NookWidgetLayout.smallHeight
        case .medium: height(for: style)
        case .large: height(for: style) + NookCalendarUpNextView.height
        }
    }

    static func height(for style: NookCalendarStyle) -> CGFloat {
        switch style {
        case .strip: NookCalendarStripView.height
        case .agenda: NookCalendarAgendaView.height
        case .timeline: NookCalendarTimelineView.height
        case .hero: NookCalendarHeroView.height
        case .month: NookCalendarMonthView.height
        }
    }

    var body: some View {
        let service = nook.calendar
        Group {
            if service.hasAccess {
                content
            } else {
                noAccess(service.authorization)
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, Self.verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NookCardBackground())
        // Calendar access is asked for here, the first time the tile is in
        // the user's view, and not at launch.
        .onAppear { nook.widgetsCameIntoView() }
    }

    @ViewBuilder
    private var content: some View {
        let style = nook.activeDisplay.calendarStyle
        switch size {
        case .small:
            NookCalendarCompactView(nook: nook, onAdd: setAdding)
        case .medium:
            look(style)
        case .large:
            VStack(alignment: .leading, spacing: 0) {
                // The look gets the room it has at medium; the list sits under it.
                look(style)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: lookHeight(style),
                        maxHeight: lookHeight(style),
                        alignment: .topLeading
                    )
                NookCalendarUpNextView(nook: nook, style: style)
            }
        }
    }

    /// Opens the event editor at the top of the page. Every look and size
    /// has a "+" that leads here, with the day picked in that look.
    private func setAdding(_ day: Date) {
        // A long press enters edit mode before the button lets go.
        guard !nook.isEditingLayout else { return }
        withMotion(Motion.reflow) { nook.beginAddingEvent(on: day) }
    }

    /// Room the look has: its normal height, plus the rows "+N more" added.
    private func lookHeight(_ style: NookCalendarStyle) -> CGFloat {
        Self.height(for: style) - 2 * Self.verticalPadding
            + NookCalendarExpansion.height(extraRows: nook.calendarExtraRows)
    }

    @ViewBuilder
    private func look(_ style: NookCalendarStyle) -> some View {
        switch style {
        case .strip: NookCalendarStripView(nook: nook, onAdd: setAdding)
        case .agenda: NookCalendarAgendaView(nook: nook, onAdd: setAdding)
        case .timeline: NookCalendarTimelineView(nook: nook, onAdd: setAdding)
        case .hero: NookCalendarHeroView(nook: nook, onAdd: setAdding)
        case .month: NookCalendarMonthView(nook: nook, onAdd: setAdding)
        }
    }

    private func noAccess(_ status: EKAuthorizationStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NookCardHeader(title: "Calendar", systemImage: "calendar")
            Spacer(minLength: 0)
            Text(Self.accessMessage(status))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.35))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    /// Unfinished events today; if none, the first event of the next day that has one.
    static func visibleEvents(_ events: [NookCalendarEvent], now: Date) -> [NookCalendarEvent] {
        let cal = Calendar.current
        let unfinished = events.filter { $0.end > now }
        let today = unfinished.filter { cal.isDate($0.start, inSameDayAs: now) || $0.start <= now }
        if !today.isEmpty {
            return Array(today.prefix(maxAgendaRows))
        }
        guard let first = unfinished.first else { return [] }
        return [first]
    }

    private static func accessMessage(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "Waiting for calendar access"
        case .denied: "Calendar access denied"
        case .restricted: "Calendar access restricted"
        case .writeOnly: "Full calendar access needed"
        default: "Calendar unavailable"
        }
    }
}
