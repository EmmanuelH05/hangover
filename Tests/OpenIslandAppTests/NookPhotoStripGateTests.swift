import CoreGraphics
import Foundation
import Testing
@testable import OpenIslandApp

/// Counts the compositions going on inside the composer. It stands in for
/// `NookPhotoStripComposer`, and each composition takes a few milliseconds,
/// which gives two that overlap time to be seen overlapping.
private final class CompositionLog: @unchecked Sendable {
    enum Event: Equatable {
        case started(String)
        case finished(String)
    }

    private let lock = NSLock()
    private let holdTheFirst: Bool
    private let release = DispatchSemaphore(value: 0)
    private var hasHeldTheFirst = false
    private var inside = 0
    private var most = 0
    private var log: [Event] = []

    /// With `holdTheFirst` the first composition stays inside the composer
    /// until `letGo()`, which leaves everything else waiting at the gate.
    init(holdTheFirst: Bool = false) {
        self.holdTheFirst = holdTheFirst
    }

    var mostInsideAtOnce: Int { lock.withLock { most } }
    var events: [Event] { lock.withLock { log } }

    /// The captions in the order their first composition started.
    var startOrder: [String] {
        var seen: [String] = []
        for case let .started(caption) in events where !seen.contains(caption) {
            seen.append(caption)
        }
        return seen
    }

    func letGo() { release.signal() }

    var composing: NookPhotoStripComposing {
        NookPhotoStripComposing(
            pdf: { [self] input in compose(input.caption) { Data("%PDF-fake".utf8) } },
            bitmap: { [self] input, _ in compose(input.caption) { Self.dot } }
        )
    }

    private static let dot: CGImage = NookPhotoBoothImaging.bitmapContext(width: 1, height: 1)!.makeImage()!

    private func compose<T>(_ caption: String, _ make: () -> T) -> T {
        let shouldHold = lock.withLock { () -> Bool in
            inside += 1
            most = max(most, inside)
            log.append(.started(caption))
            defer { hasHeldTheFirst = true }
            return holdTheFirst && !hasHeldTheFirst
        }
        if shouldHold { release.wait() }
        Thread.sleep(forTimeInterval: 0.004)
        let made = make()
        lock.withLock {
            inside -= 1
            log.append(.finished(caption))
        }
        return made
    }
}

/// The gate every composition of a strip goes through: the strip that is
/// printed, and the previews in Settings.
@MainActor
struct NookPhotoStripGateTests {
    private static func input(_ caption: String) -> NookPhotoStripInput {
        NookPhotoStripInput(
            pictures: [],
            layout: .layout(.classic),
            theme: .theme(id: "gingham"),
            caption: caption,
            date: Date(timeIntervalSince1970: 1_791_600_420)
        )
    }

    private static func key(_ caption: String) -> NookPhotoBoothPreviewKey {
        NookPhotoBoothPreviewKey(layout: .classic, theme: .theme(id: "gingham"), typedCaption: caption, defaultLine: "")
    }

    /// Waits until a condition holds, or gives up after a few seconds.
    private static func wait(until isThere: () -> Bool) async -> Bool {
        for _ in 0..<1000 {
            if isThere() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return isThere()
    }

    // MARK: One at a time

    @Test func noTwoCompositionsAreEverInsideTheComposerAtOnce() async {
        let log = CompositionLog()
        let gate = NookPhotoStripGate(composing: log.composing)
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<12 {
                group.addTask {
                    if index % 4 == 0 {
                        _ = await gate.makeStrip(Self.input("print \(index)"), previewScale: 3)
                    } else {
                        _ = await gate.makePreview(Self.input("preview \(index)"), scale: 0.5)
                    }
                }
            }
        }
        // A print is two compositions, its PDF and its picture.
        let compositions = 3 * 2 + 9
        #expect(log.events.count == compositions * 2)
        #expect(log.mostInsideAtOnce == 1)
        #expect(gate.waiting == (0, 0))
    }

    @Test func aPrintAskedForLastRunsBeforeAPreviewAskedForFirst() async {
        let log = CompositionLog(holdTheFirst: true)
        let gate = NookPhotoStripGate(composing: log.composing)
        let held = Task { await gate.makePreview(Self.input("held"), scale: 0.5) }
        #expect(await Self.wait { !log.events.isEmpty })

        async let preview = gate.makePreview(Self.input("preview"), scale: 0.5)
        #expect(await Self.wait { gate.waiting.previews == 1 })
        async let print = gate.makeStrip(Self.input("print"), previewScale: 3)
        #expect(await Self.wait { gate.waiting.prints == 1 })

        log.letGo()
        _ = await held.value
        let made = await (preview, print)
        #expect(made.0 != nil && made.1 != nil)
        // The print was asked for second and ran second.
        #expect(log.startOrder == ["held", "print", "preview"])
        #expect(log.mostInsideAtOnce == 1)
    }

    // MARK: A print and the previews, together

    /// The booth prints while Settings is still drawing previews. The previews
    /// are made by the cache's own wiring and the strip by a whole session, and
    /// both are handed the same counting gate.
    @Test func aPrintFinishesAheadOfPreviewsThatHaveNotStartedAndNothingComposesTwice() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NookPhotoStripGateTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = ManualClock(Date(timeIntervalSince1970: 1_800_000_000))
        let log = CompositionLog(holdTheFirst: true)
        let gate = NookPhotoStripGate(composing: log.composing)

        let booth = NookPhotoBoothModel(
            defaults: MemoryDefaults(),
            camera: FakeBoothCamera(),
            store: NookPhotoBoothStore(trash: { try FileManager.default.removeItem(at: $0) }),
            defaultFolder: folder,
            now: { clock.now },
            advancesItself: false
        )
        booth.isMirrorOn = { true }
        booth.play = { _ in }
        booth.reveal = { _ in }
        booth.stripGate = gate
        booth.themeID = "gingham"
        booth.layoutKind = .classic
        booth.caption = "print"
        defer { booth.cancel() }

        // Six previews are asked for. One gets into the composer and is held
        // there, and the other five wait at the gate.
        let previews = NookPhotoBoothPreviews(gate: gate)
        let asks = (1...6).map { index in
            Task { await previews.request([Self.key("preview \(index)")]) }
        }
        #expect(await Self.wait { gate.waiting.previews == 5 })
        let first = try #require(log.startOrder.first)
        #expect(first.hasPrefix("preview"))

        // The session runs to its strip while the first preview is held.
        booth.start()
        let session = Task {
            var turns = 0
            while booth.result == nil, booth.failure == nil, turns < 400 {
                turns += 1
                clock.advance(1.3)
                await booth.tick(at: clock.now)
            }
        }
        #expect(await Self.wait { gate.waiting.prints == 1 })
        #expect(gate.waiting.previews == 5)

        log.letGo()
        await session.value
        for ask in asks { await ask.value }

        #expect(booth.failure == nil)
        #expect(booth.result != nil)
        #expect(log.mostInsideAtOnce == 1)

        // Second to start, and done before any waiting preview began.
        let order = log.startOrder
        #expect(order.count == 7)
        #expect(order[1] == "print")
        let events = log.events
        let lastOfThePrint = try #require(events.lastIndex(of: .finished("print")))
        let firstOfTheRest = try #require(events.firstIndex { event in
            if case let .started(caption) = event { return caption != first && caption != "print" }
            return false
        })
        #expect(lastOfThePrint < firstOfTheRest, "a waiting preview started before the print was done")
        #expect(previews.images.count == 6)
    }

    // MARK: No second way in

    /// Nothing but the gate calls the composer. The previews and the print
    /// both ask the gate, which is why they never overlap.
    @Test func onlyTheGateComposesAStrip() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/OpenIslandApp", isDirectory: true)
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let entries = ["NookPhotoStripComposer.pdf(", "NookPhotoStripComposer.bitmap(", "NookPhotoStripComposer.wordmark("]
        var callers: Set<String> = []
        for case let file as URL in files where file.pathExtension == "swift" {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for line in lines where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                if entries.contains(where: line.contains) { callers.insert(file.lastPathComponent) }
            }
        }
        #expect(callers == ["NookPhotoStripGate.swift"], "composing outside the gate: \(callers.sorted())")
    }
}
