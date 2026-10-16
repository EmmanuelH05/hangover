import Foundation

/// One link on its way to a file.
struct NookLinkAudioJob: Identifiable, Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        /// In line behind the job that is running.
        case waiting
        /// Being fetched. The fraction is nil while no size is known.
        case downloading(fraction: Double?)
        /// Fetched, and `ffmpeg` is making the MP3.
        case converting
        /// Asked to stop. The process has not ended yet.
        case cancelling
        /// Finished. The path is nil when `yt-dlp` did not say where.
        case done(URL?)
        case failed(NookLinkAudioFailure)

        var isFinished: Bool {
            switch self {
            case .done, .failed: true
            case .waiting, .downloading, .converting, .cancelling: false
            }
        }

        var isRunning: Bool {
            switch self {
            case .downloading, .converting, .cancelling: true
            case .waiting, .done, .failed: false
            }
        }
    }

    let id: UUID
    let link: NookLinkAudioLink
    var title: String?
    var phase: Phase = .waiting
    /// The key and tempo, once they are found. A finished row shows them.
    var findings: NookLinkAudioFindings?
    /// When the process started. Nothing older than this is ever removed.
    var startedAt: Date?
    /// The file `yt-dlp` said it was writing, for the clean-up after a cancel.
    var writingFileName: String?
}

/// The jobs of one session: one running, up to five waiting in the order
/// they were added, and the last five that finished. Pure value logic. The
/// service starts the processes.
struct NookLinkAudioQueue: Equatable, Sendable {
    static let maxWaiting = 5
    static let maxFinished = 5

    private(set) var running: NookLinkAudioJob?
    private(set) var waiting: [NookLinkAudioJob] = []
    /// Newest first.
    private(set) var finished: [NookLinkAudioJob] = []

    /// Every job in the order the card lists them: the running one, those
    /// in line, then those that finished, newest first.
    var all: [NookLinkAudioJob] {
        (running.map { [$0] } ?? []) + waiting + finished
    }

    var isEmpty: Bool { running == nil && waiting.isEmpty && finished.isEmpty }
    var hasActiveJob: Bool { running != nil || !waiting.isEmpty }

    func job(_ id: UUID) -> NookLinkAudioJob? {
        all.first { $0.id == id }
    }

    // MARK: Adding and starting

    /// Puts a link at the back of the line. False, and nothing added, when
    /// five are already waiting.
    @discardableResult
    mutating func add(_ job: NookLinkAudioJob) -> Bool {
        guard waiting.count < Self.maxWaiting else { return false }
        waiting.append(job)
        return true
    }

    /// Starts the first in line when nothing is running.
    mutating func startNext(now: Date) -> NookLinkAudioJob? {
        guard running == nil, !waiting.isEmpty else { return nil }
        var job = waiting.removeFirst()
        job.phase = .downloading(fraction: nil)
        job.startedAt = now
        running = job
        return job
    }

    // MARK: Changes to the running job

    mutating func updateRunning(_ id: UUID, _ change: (inout NookLinkAudioJob) -> Void) {
        guard var job = running, job.id == id else { return }
        change(&job)
        running = job
    }

    /// Ends the running job. A finished job goes to the front of the
    /// finished list, and the list keeps the last five.
    mutating func finishRunning(_ id: UUID, as phase: NookLinkAudioJob.Phase) {
        guard var job = running, job.id == id else { return }
        job.phase = phase
        running = nil
        finished.insert(job, at: 0)
        if finished.count > Self.maxFinished { finished.removeLast(finished.count - Self.maxFinished) }
    }

    /// Changes a job that has finished, such as when its key and tempo come
    /// in after the file was saved. Nothing happens when it is no longer listed.
    mutating func updateFinished(_ id: UUID, _ change: (inout NookLinkAudioJob) -> Void) {
        guard let index = finished.firstIndex(where: { $0.id == id }) else { return }
        change(&finished[index])
    }

    /// Takes the running job off the list without keeping it, as a cancel
    /// does.
    mutating func dropRunning(_ id: UUID) {
        guard running?.id == id else { return }
        running = nil
    }

    // MARK: Cancelling

    /// Takes a job in line out of it. False when there is none by that id.
    @discardableResult
    mutating func removeWaiting(_ id: UUID) -> Bool {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return false }
        waiting.remove(at: index)
        return true
    }

    /// Everything that is waiting, taken out of the line.
    mutating func removeAllWaiting() {
        waiting.removeAll()
    }

    mutating func clearFinished() {
        finished.removeAll()
    }
}
