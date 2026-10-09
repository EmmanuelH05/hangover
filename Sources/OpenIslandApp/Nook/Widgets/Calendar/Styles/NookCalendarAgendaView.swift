import SwiftUI

/// Style B: a short list of what is coming up.
struct NookCalendarAgendaView: View {
    var nook: NookModel
    /// Opens the card's add-event form on a day.
    var onAdd: (Date) -> Void = { _ in }

    static let height: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                NookCardHeader(
                    title: "Calendar",
                    systemImage: "calendar",
                    trailing: Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                )
                NookCalendarAddButton(isInline: true) { onAdd(Date()) }
            }
            // Re-evaluate every 30s so "in N min" and ended events stay current.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                rows(now: context.date)
            }
        }
    }

    @ViewBuilder
    private func rows(now: Date) -> some View {
        let shown = NookCalendarCard.visibleEvents(nook.upcomingEvents, now: now)
        if shown.isEmpty {
            Spacer(minLength: 0)
            Text("Nothing coming up")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.35))
            Spacer(minLength: 0)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(shown) { event in
                    NookCalendarRow(event: event, now: now) { nook.startNote(for: event) } onJoin: { nook.joinMeeting(event) }
                }
            }
            Spacer(minLength: 0)
        }
    }
}
