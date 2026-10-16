import CoreMedia

/// Pause and resume for a file that is written as it is captured. A pause
/// is a gap on the host clock. Samples inside a gap are dropped, even ones
/// that arrive after the resume, and samples after it move back by every
/// gap before them. Every track goes through the same timeline, which keeps
/// the voice and the picture together.
struct NookRecordTimeline: Sendable {
    private struct Gap: Sendable {
        var start: CMTime
        var end: CMTime?
    }

    private var gaps: [Gap] = []

    var isPaused: Bool { gaps.last.map { $0.end == nil } ?? false }

    mutating func pause(at time: CMTime) {
        guard !isPaused else { return }
        gaps.append(Gap(start: time, end: nil))
    }

    mutating func resume(at time: CMTime) {
        guard isPaused, let last = gaps.indices.last else { return }
        gaps[last].end = time < gaps[last].start ? gaps[last].start : time
    }

    /// The time a sample is written at. Nil for a sample to drop.
    func adjusted(_ time: CMTime) -> CMTime? {
        var shift = CMTime.zero
        for gap in gaps {
            guard time >= gap.start else { break }
            guard let end = gap.end, time >= end else { return nil }
            shift = shift + (end - gap.start)
        }
        return time - shift
    }
}
