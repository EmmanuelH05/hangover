import SwiftUI

/// Style C: one bar for today with a block per event.
struct NookCalendarTimelineView: View {
    var nook: NookModel
    /// Opens the card's add-event form on a day.
    var onAdd: (Date) -> Void = { _ in }

    static let height: CGFloat = 112

    private static let defaultWindow = (start: 8, end: 22)
    private static let minBlockWidth: CGFloat = 4
    private static let tickRowHeight: CGFloat = 11
    private static let trackHeight: CGFloat = 14
    private static let labelRowHeight: CGFloat = 12
    private static let nowOverhang: CGFloat = 3
    private static let barHeight: CGFloat = 44
    private static let labelCharWidth: CGFloat = 5.4
    private static let maxLabels = 4

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
    }

    // MARK: - Rendering

    private func content(now: Date) -> some View {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: now)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        let events = nook.calendarEvents(from: dayStart, to: dayEnd)
        let timed = events.filter { !$0.isAllDay && $0.end > dayStart && $0.start < dayEnd }
            .sorted { $0.start < $1.start }
        let allDay = events.filter(\.isAllDay)
        let spans = timed.map { (start: Self.hours($0.start, from: dayStart), end: Self.hours($0.end, from: dayStart)) }
        let window = Self.window(for: spans)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TODAY")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 8)
                Text(Self.statusText(timed: timed, now: now))
                    .font(.system(size: 11))
                    .foregroundStyle(.green.opacity(0.85))
                    .lineLimit(1)
                NookCalendarAddButton(isInline: true) { onAdd(now) }
            }
            bar(timed: timed, spans: spans, window: window, nowHour: Self.hours(now, from: dayStart))
                .frame(height: Self.barHeight)
            if !allDay.isEmpty {
                Text("\u{25CF} All day: " + allDay.map(\.title).joined(separator: ", "))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private func bar(
        timed: [NookCalendarEvent],
        spans: [(start: Double, end: Double)],
        window: (start: Int, end: Int),
        nowHour: Double
    ) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let trackY = Self.tickRowHeight + 2
            let frames = spans.map { Self.blockFrame(start: $0.start, end: $0.end, window: window, width: width) }
            let candidates = timed.indices.map { index in
                (x: frames[index].x, width: Self.labelWidth(for: timed[index].title))
            }
            let shown = Self.visibleLabels(candidates, maxCount: Self.maxLabels, trackWidth: width)

            ZStack(alignment: .topLeading) {
                ForEach(Self.tickHours(in: window), id: \.self) { hour in
                    Text(Self.tickLabel(hour))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                        .fixedSize()
                        .position(
                            x: Self.x(forHour: Double(hour), window: window, width: width),
                            y: Self.tickRowHeight / 2
                        )
                }
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.white.opacity(0.07))
                    .frame(width: width, height: Self.trackHeight)
                    .offset(y: trackY)
                ForEach(timed.indices, id: \.self) { index in
                    let frame = frames[index]
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(timed[index].calendarColor)
                        .frame(width: frame.width, height: Self.trackHeight)
                        .offset(x: frame.x, y: trackY)
                        .contentShape(Rectangle())
                        .onTapGesture { nook.startNote(for: timed[index]) }
                }
                ForEach(shown, id: \.self) { index in
                    Text(timed[index].title)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: min(candidates[index].width, max(width - frames[index].x, 0)), alignment: .leading)
                        .offset(x: frames[index].x, y: trackY + Self.trackHeight + 4)
                }
                if nowHour >= Double(window.start), nowHour <= Double(window.end) {
                    Capsule()
                        .fill(.white.opacity(0.9))
                        .frame(width: 2, height: Self.trackHeight + Self.nowOverhang * 2)
                        .offset(
                            x: Self.x(forHour: nowHour, window: window, width: width) - 1,
                            y: trackY - Self.nowOverhang
                        )
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - Pure layout math

    /// Hours since midnight, clamped to the day.
    static func hours(_ date: Date, from dayStart: Date) -> Double {
        min(max(date.timeIntervalSince(dayStart) / 3600, 0), 24)
    }

    /// Whole-hour window: 8 to 22 by default, widened to cover every span.
    static func window(for spans: [(start: Double, end: Double)]) -> (start: Int, end: Int) {
        var start = defaultWindow.start
        var end = defaultWindow.end
        for span in spans {
            start = min(start, Int(span.start.rounded(.down)))
            end = max(end, Int(span.end.rounded(.up)))
        }
        start = min(max(start, 0), 23)
        end = min(max(end, start + 1), 24)
        return (start, end)
    }

    static func x(forHour hour: Double, window: (start: Int, end: Int), width: CGFloat) -> CGFloat {
        let length = Double(window.end - window.start)
        guard length > 0, width > 0 else { return 0 }
        let fraction = min(max((hour - Double(window.start)) / length, 0), 1)
        return CGFloat(fraction) * width
    }

    /// Leading x and width for an event, clamped to the window, at least 4pt wide
    /// and never past the right edge of the track.
    static func blockFrame(
        start: Double,
        end: Double,
        window: (start: Int, end: Int),
        width: CGFloat
    ) -> (x: CGFloat, width: CGFloat) {
        let left = x(forHour: start, window: window, width: width)
        let right = x(forHour: end, window: window, width: width)
        let blockWidth = max(right - left, minBlockWidth)
        let clampedX = max(min(left, width - minBlockWidth), 0)
        return (clampedX, min(blockWidth, max(width - clampedX, minBlockWidth)))
    }

    /// Indexes of labels to draw, in order: at most `maxCount`, each starting
    /// at or after the end of the previous drawn label, and inside the track.
    static func visibleLabels(
        _ labels: [(x: CGFloat, width: CGFloat)],
        maxCount: Int,
        trackWidth: CGFloat
    ) -> [Int] {
        var result: [Int] = []
        var previousEnd = -CGFloat.infinity
        for (index, label) in labels.enumerated() {
            guard result.count < maxCount else { break }
            guard label.x >= previousEnd, label.x < trackWidth else { continue }
            result.append(index)
            previousEnd = label.x + label.width + 4
        }
        return result
    }

    static func labelWidth(for title: String) -> CGFloat {
        CGFloat(title.count) * labelCharWidth
    }

    static func tickHours(in window: (start: Int, end: Int)) -> [Int] {
        let first = window.start % 2 == 0 ? window.start : window.start + 1
        return Array(stride(from: first, through: window.end - 1, by: 2))
    }

    static func tickLabel(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h)" + (hour % 24 < 12 ? "a" : "p")
    }

    // MARK: - Status line

    static func statusText(timed: [NookCalendarEvent], now: Date) -> String {
        let time = Date.FormatStyle(date: .omitted, time: .shortened)
        if let current = timed.first(where: { $0.start <= now && $0.end > now }) {
            let title = current.title.count > 22 ? String(current.title.prefix(21)) + "..." : current.title
            return "in \(title) until \(current.end.formatted(time))"
        }
        if let next = timed.first(where: { $0.start > now }) {
            return "free until \(next.start.formatted(time))"
        }
        return "free for the rest of the day"
    }
}
