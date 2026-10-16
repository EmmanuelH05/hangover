import Foundation

/// The time shown in the notch while recording.
enum NookRecordClock {
    static func elapsed(_ phase: NookRecordPhase, now: Date) -> TimeInterval {
        switch phase {
        case let .recording(startedAt, pausedTotal):
            max(0, now.timeIntervalSince(startedAt) - pausedTotal)
        case let .paused(startedAt, pausedAt, pausedTotal):
            max(0, pausedAt.timeIntervalSince(startedAt) - pausedTotal)
        default:
            0
        }
    }

    /// "0:07", "12:34", "1:02:03".
    static func text(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}
