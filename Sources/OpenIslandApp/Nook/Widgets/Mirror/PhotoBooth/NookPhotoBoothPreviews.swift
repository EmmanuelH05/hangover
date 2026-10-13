import CoreGraphics
import Foundation
import Observation

/// A finished preview on its way back to the main actor. Core Graphics
/// images do not change once made, which is why this may cross.
struct NookPhotoBoothPreviewImage: @unchecked Sendable {
    let image: CGImage
}

/// The previews Settings shows, drawn once each and kept. A view only reads
/// a picture from here. Asking for the ones it needs is `request`, which a
/// view calls from a task and never from its body.
@MainActor
@Observable
final class NookPhotoBoothPreviews {
    /// Draws one preview. The app's goes through the gate that every
    /// composition goes through, which draws one at a time and puts a print
    /// first. A test hands in one that only counts.
    typealias Draw = @Sendable (NookPhotoBoothPreviewKey) async -> NookPhotoBoothPreviewImage?

    /// The app's one cache, which keeps the previews while Settings is
    /// closed and opened again.
    static let shared = NookPhotoBoothPreviews()

    /// How long typing in the caption field has to pause before the
    /// previews follow it.
    nonisolated static let captionPause: Duration = .milliseconds(400)

    /// Most previews kept. A preview is 60 to 130 KB and a screenful of
    /// choices is 18 or 19, which leaves room for a few captions' worth.
    nonisolated static let defaultCapacity = 64

    private(set) var images: [NookPhotoBoothPreviewKey: CGImage] = [:]

    /// Keys in the order they were last asked for, oldest first.
    @ObservationIgnored private var recency: [NookPhotoBoothPreviewKey] = []
    /// The previews being drawn right now. A second ask for one waits for
    /// the first instead of drawing it again.
    @ObservationIgnored private var inFlight: [NookPhotoBoothPreviewKey: Task<Void, Never>] = [:]
    @ObservationIgnored private let draw: Draw
    @ObservationIgnored private let capacity: Int

    /// A test hands in its own drawing, to count how often it is asked, and
    /// a smaller capacity.
    init(capacity: Int = NookPhotoBoothPreviews.defaultCapacity, draw: @escaping Draw) {
        self.capacity = max(1, capacity)
        self.draw = draw
    }

    /// Draws through `gate`, which a test may swap for one of its own.
    convenience init(capacity: Int = NookPhotoBoothPreviews.defaultCapacity, gate: NookPhotoStripGate = .shared) {
        self.init(capacity: capacity) { key in
            await NookPhotoBoothPreviewDrawing.image(for: key, through: gate)
        }
    }

    /// The preview for a key, or nil while it is still being drawn.
    func image(for key: NookPhotoBoothPreviewKey) -> CGImage? {
        images[key]
    }

    /// Draws the previews that are not kept yet, in the order given, and
    /// returns when they are in. Cancelling stops before the next one; the
    /// one being drawn still lands.
    ///
    /// Every preview of the request that is already kept is marked as asked
    /// for before any other is drawn. Drawing evicts the oldest preview, and
    /// without this it would evict a kept one that the request reaches later
    /// and leave a blank tile where a picture was.
    func request(_ keys: [NookPhotoBoothPreviewKey]) async {
        for key in keys where images[key] != nil {
            touch(key)
        }
        for key in keys {
            if images[key] != nil { continue }
            if Task.isCancelled { return }
            let drawing = inFlight[key] ?? start(key)
            await drawing.value
        }
    }

    /// The caption once typing has paused for `pause`, or nil when typing
    /// went on and the task was cancelled first.
    nonisolated static func settled(_ caption: String, pause: Duration = captionPause) async -> String? {
        do {
            try await Task.sleep(for: pause)
        } catch {
            return nil
        }
        return caption
    }

    private func start(_ key: NookPhotoBoothPreviewKey) -> Task<Void, Never> {
        let task = Task { [draw] in
            let made = await draw(key)
            if let made { keep(made.image, for: key) }
            inFlight[key] = nil
        }
        inFlight[key] = task
        return task
    }

    private func keep(_ image: CGImage, for key: NookPhotoBoothPreviewKey) {
        images[key] = image
        touch(key)
        while recency.count > capacity {
            images[recency.removeFirst()] = nil
        }
    }

    private func touch(_ key: NookPhotoBoothPreviewKey) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }
}
