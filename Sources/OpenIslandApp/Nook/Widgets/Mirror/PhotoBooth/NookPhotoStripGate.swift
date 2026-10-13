import CoreGraphics
import Foundation

/// A strip as it is kept and as it is shown: the PDF that is saved, and the
/// picture of it for the screen. Core Graphics images do not change once
/// made, which is why this may cross between tasks.
struct NookPhotoStripPrint: @unchecked Sendable {
    let pdf: Data
    let picture: CGImage
}

/// What composes a strip. The app uses the real composer. A test hands in
/// one that counts, to see how many compositions are going at once.
struct NookPhotoStripComposing: Sendable {
    var pdf: @Sendable (NookPhotoStripInput) -> Data?
    var bitmap: @Sendable (NookPhotoStripInput, CGFloat) -> CGImage?

    static let live = NookPhotoStripComposing(
        pdf: { NookPhotoStripComposer.pdf($0) },
        bitmap: { NookPhotoStripComposer.bitmap($0, scale: $1) }
    )
}

/// The one way into `NookPhotoStripComposer.pdf` and `.bitmap`: the strip
/// that is printed and the previews in Settings both go through here, and
/// nothing else in the app composes a strip.
///
/// Composing asks AppKit for fonts by name, and two compositions at once
/// once killed the test process with a recursive lock in `NSFont` (see
/// `OneStripAtATime`). The gate lets one composition in at a time, off the
/// main actor.
///
/// A print goes ahead of the previews that have not started. The user has
/// just taken the pictures and the strip cannot be late, while a preview can
/// be drawn again. The previews are not dropped: they wait behind the print
/// and run after it. A print never waits for more than the one composition
/// already going.
final class NookPhotoStripGate: @unchecked Sendable {
    /// The app's one gate.
    static let shared = NookPhotoStripGate()

    private let composing: NookPhotoStripComposing
    private let lock = NSLock()
    private var isHeld = false
    private var waitingPrints: [CheckedContinuation<Void, Never>] = []
    private var waitingPreviews: [CheckedContinuation<Void, Never>] = []

    init(composing: NookPhotoStripComposing = .live) {
        self.composing = composing
    }

    /// The strip the user took: its PDF and its picture for the screen, made
    /// as one job. Nil when either could not be drawn.
    @concurrent
    func makeStrip(_ input: NookPhotoStripInput, previewScale: CGFloat) async -> NookPhotoStripPrint? {
        await enter(isPrint: true)
        defer { leave() }
        guard let pdf = composing.pdf(input), let picture = composing.bitmap(input, previewScale) else {
            return nil
        }
        return NookPhotoStripPrint(pdf: pdf, picture: picture)
    }

    /// A small picture of a strip for Settings. Nil when it could not be drawn.
    @concurrent
    func makePreview(_ input: NookPhotoStripInput, scale: CGFloat) async -> NookPhotoBoothPreviewImage? {
        await enter(isPrint: false)
        defer { leave() }
        return composing.bitmap(input, scale).map(NookPhotoBoothPreviewImage.init)
    }

    /// How many prints and previews are waiting for their turn. A test reads
    /// this to know when a job has reached the gate.
    var waiting: (prints: Int, previews: Int) {
        lock.withLock { (waitingPrints.count, waitingPreviews.count) }
    }

    // MARK: Turns

    private func enter(isPrint: Bool) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let isFree = lock.withLock { () -> Bool in
                guard isHeld else {
                    isHeld = true
                    return true
                }
                if isPrint {
                    waitingPrints.append(continuation)
                } else {
                    waitingPreviews.append(continuation)
                }
                return false
            }
            if isFree { continuation.resume() }
        }
    }

    /// Hands the gate to the next job, a print before any preview, in the
    /// order they came. The gate stays held through the handover.
    private func leave() {
        let next = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            if !waitingPrints.isEmpty { return waitingPrints.removeFirst() }
            if !waitingPreviews.isEmpty { return waitingPreviews.removeFirst() }
            isHeld = false
            return nil
        }
        next?.resume()
    }
}
