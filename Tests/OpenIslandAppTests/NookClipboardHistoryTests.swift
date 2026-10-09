import Foundation
import Testing
@testable import OpenIslandApp

// MARK: - The list

@Suite struct NookClipboardHistoryTests {
    private static func text(_ value: String) -> NookClipboardContent { .text(value) }

    private static func image(bytes: Int, fill: UInt8 = 1) -> NookClipboardContent {
        .image(data: Data(repeating: fill, count: bytes), typeIdentifier: "public.png", thumbnail: nil)
    }

    @Test func newestCopyGoesOnTop() {
        var history = NookClipboardHistory()
        history.record(Self.text("first"))
        history.record(Self.text("second"))

        #expect(history.entries.map(\.content) == [Self.text("second"), Self.text("first")])
    }

    @Test func keepsOnlyTheLastTwenty() {
        var history = NookClipboardHistory()
        for index in 1...25 {
            history.record(Self.text("copy \(index)"))
        }

        let expectedCount: Int = 20
        #expect(history.entries.count == expectedCount)
        #expect(history.entries.first?.content == Self.text("copy 25"))
        #expect(history.entries.last?.content == Self.text("copy 6"))
    }

    @Test func aRepeatedCopyMovesUpAndAddsNoRow() {
        var history = NookClipboardHistory()
        history.record(Self.text("a"))
        history.record(Self.text("b"))
        history.record(Self.text("a"))

        #expect(history.entries.map(\.content) == [Self.text("a"), Self.text("b")])
    }

    @Test func aRepeatedPictureIsToldByItsDataNotItsThumbnail() {
        var history = NookClipboardHistory()
        let data = Data(repeating: 7, count: 64)
        history.record(.image(data: data, typeIdentifier: "public.png", thumbnail: nil))
        history.record(.image(data: data, typeIdentifier: "public.png", thumbnail: Data([1, 2, 3])))

        let expectedCount: Int = 1
        #expect(history.entries.count == expectedCount)
    }

    @Test func emptyAndOversizedCopiesAreLeftOut() {
        var history = NookClipboardHistory()

        let leftOut: [NookClipboardContent] = [
            Self.text(""),
            Self.text("  \n\t "),
            Self.text(String(repeating: "x", count: NookClipboardHistory.maxTextBytes + 1)),
            Self.image(bytes: NookClipboardHistory.maxImageBytes + 1),
            Self.image(bytes: 0),
        ]
        for content in leftOut {
            #expect(!NookClipboardHistory.accepts(content))
            let entry = history.record(content)
            #expect(entry == nil)
        }
        #expect(history.entries.isEmpty)

        let largestText = history.record(Self.text(String(repeating: "x", count: NookClipboardHistory.maxTextBytes)))
        #expect(largestText != nil)
    }

    @Test func oldPicturesGoFirstWhenTheyTakeTooMuchRoom() {
        var history = NookClipboardHistory()
        let big = NookClipboardHistory.maxImageBytes
        history.record(Self.text("kept text"))
        // Four pictures of the largest size are one too many for the budget.
        for fill in UInt8(1)...UInt8(4) {
            history.record(Self.image(bytes: big, fill: fill))
        }

        let pictures = history.entries.filter { $0.content.imageByteCount > 0 }
        let expectedPictures: Int = 3
        #expect(pictures.count == expectedPictures)
        #expect(pictures.first?.content == Self.image(bytes: big, fill: 4))
        #expect(!history.entries.contains { $0.content == Self.image(bytes: big, fill: 1) })
        #expect(history.entries.contains { $0.content == Self.text("kept text") })
    }

    @Test func movingToTopKeepsTheRowAndItsID() throws {
        var history = NookClipboardHistory()
        let recorded = history.record(Self.text("first"))
        let first = try #require(recorded)
        history.record(Self.text("second"))

        history.moveToTop(first.id)

        #expect(history.entries.map(\.content) == [Self.text("first"), Self.text("second")])
        #expect(history.entries.first?.id == first.id)
    }

    @Test func aKeptPictureTakesItsThumbnailLater() throws {
        var history = NookClipboardHistory()
        let small = Data([7, 7, 7])
        let recorded = history.record(Self.image(bytes: 64))
        let picture = try #require(recorded)
        let recordedText = history.record(Self.text("words"))
        let text = try #require(recordedText)

        history.setThumbnail(small, for: picture.id)

        let kept = try #require(history.entries.first { $0.id == picture.id })
        #expect(kept.content == .image(data: Data(repeating: 1, count: 64), typeIdentifier: "public.png", thumbnail: small))
        #expect(kept.date == picture.date)
        // Order and the other rows are untouched.
        #expect(history.entries.map(\.id) == [text.id, picture.id])

        // Nothing to set, a row of text, and a row that has gone.
        let before = history
        history.setThumbnail(nil, for: picture.id)
        history.setThumbnail(small, for: text.id)
        history.setThumbnail(small, for: UUID())
        #expect(history == before)
    }

    @Test func removeAndClear() throws {
        var history = NookClipboardHistory()
        let recorded = history.record(Self.text("first"))
        let first = try #require(recorded)
        history.record(Self.text("second"))

        history.remove(first.id)
        #expect(history.entries.map(\.content) == [Self.text("second")])

        history.clear()
        #expect(history.entries.isEmpty)
    }

    // MARK: Skip rule

    @Test(arguments: [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
        "public.file-url",
        "NSFilenamesPboardType",
    ])
    func markedOrFileCopiesAreSkipped(marker: String) {
        #expect(NookClipboardHistory.shouldSkip(types: ["public.utf8-plain-text", marker]))
    }

    @Test func plainCopiesAreRead() {
        #expect(!NookClipboardHistory.shouldSkip(types: ["public.utf8-plain-text", "public.html"]))
        #expect(!NookClipboardHistory.shouldSkip(types: ["public.png", "public.tiff"]))
        #expect(!NookClipboardHistory.shouldSkip(types: []))
    }

    // MARK: Preview

    @Test func previewIsOneLine() {
        #expect(NookClipboardHistory.preview(of: "  two\n\n  lines\there ") == "two lines here")
    }

    @Test func previewCutsALongCopy() {
        let long = String(repeating: "a", count: NookClipboardHistory.previewLength + 50)
        let preview = NookClipboardHistory.preview(of: long)

        let expectedLength: Int = NookClipboardHistory.previewLength + 1
        #expect(preview.count == expectedLength)
        #expect(preview.hasSuffix("…"))
    }
}

// MARK: - The monitor

/// A pasteboard that lives in the test. It counts every look at it, which
/// is how the tests prove what was not read.
@MainActor
final class NookFakePasteboard: NookPasteboardAccess {
    var content: NookClipboardContent?
    var typeList: [String] = ["public.utf8-plain-text"]
    var accessValue: NookClipboardAccess = .allowed
    var acceptsWrites = true

    private(set) var changeCountReads = 0
    private(set) var typeReads = 0
    private(set) var contentReads = 0
    private var count = 0

    var changeCount: Int {
        changeCountReads += 1
        return count
    }

    var access: NookClipboardAccess { accessValue }

    func types() -> [String] {
        typeReads += 1
        return typeList
    }

    /// Runs once, in the middle of the next read: the moment another app
    /// copies something new while the old copy is being read.
    var duringNextRead: (() -> Void)?

    func read() -> NookClipboardContent? {
        contentReads += 1
        if let landed = duringNextRead {
            duringNextRead = nil
            landed()
        }
        return content
    }

    func write(_ content: NookClipboardContent) -> Bool {
        guard acceptsWrites else { return false }
        self.content = content
        typeList = ["public.utf8-plain-text"]
        count += 1
        return true
    }

    /// Another app copied something.
    func simulateCopy(_ content: NookClipboardContent, types: [String] = ["public.utf8-plain-text"]) {
        self.content = content
        typeList = types
        count += 1
    }
}

@MainActor
@Suite struct NookClipboardMonitorTests {
    private static func makeDefaults() -> (UserDefaults, String) {
        (MemoryDefaults(), "NookClipboardMonitorTests")
    }

    private static func makeMonitor(
        enabled: Bool = false,
        makeThumbnail: @escaping @Sendable (Data) -> Data? = { _ in nil }
    ) -> (NookClipboardMonitor, NookFakePasteboard, UserDefaults, String) {
        let (defaults, name) = makeDefaults()
        if enabled { defaults.set(true, forKey: NookClipboardMonitor.enabledKey) }
        let pasteboard = NookFakePasteboard()
        let monitor = NookClipboardMonitor(pasteboard: pasteboard, defaults: defaults, makeThumbnail: makeThumbnail)
        return (monitor, pasteboard, defaults, name)
    }

    /// Counts the pictures handed over to be drawn, from whatever thread
    /// draws them.
    private final class DrawCount: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        func note() {
            lock.lock()
            count += 1
            lock.unlock()
        }

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
    }

    @Test func aPictureOverTheCapIsNeverDrawn() async {
        let drawn = DrawCount()
        let (monitor, pasteboard, defaults, name) = Self.makeMonitor(enabled: true) { _ in
            drawn.note()
            return Data([1])
        }
        defer { defaults.removePersistentDomain(forName: name) }
        monitor.start()
        let tooBig = Data(repeating: 3, count: NookClipboardHistory.maxImageBytes + 1)

        pasteboard.simulateCopy(.image(data: tooBig, typeIdentifier: "public.tiff", thumbnail: nil), types: ["public.tiff"])
        monitor.poll()
        await monitor.thumbnailTask?.value

        let none: Int = 0
        #expect(drawn.value == none)
        #expect(monitor.thumbnailTask == nil)
        #expect(monitor.history.entries.isEmpty)
    }

    @Test func aKeptPictureIsRecordedFirstAndDrawnAfter() async throws {
        let drawn = DrawCount()
        let small = Data([9, 9])
        let (monitor, pasteboard, defaults, name) = Self.makeMonitor(enabled: true) { _ in
            drawn.note()
            return small
        }
        defer { defaults.removePersistentDomain(forName: name) }
        monitor.start()
        let picture = Data(repeating: 5, count: 2048)

        pasteboard.simulateCopy(.image(data: picture, typeIdentifier: "public.png", thumbnail: nil), types: ["public.png"])
        monitor.poll()

        // The row is there at once, before its small picture.
        let row = try #require(monitor.history.entries.first)
        #expect(row.content.isSameCopy(as: .image(data: picture, typeIdentifier: "public.png", thumbnail: nil)))

        await monitor.thumbnailTask?.value

        let once: Int = 1
        #expect(drawn.value == once)
        #expect(monitor.history.entries.first?.content
            == .image(data: picture, typeIdentifier: "public.png", thumbnail: small))
        #expect(monitor.history.entries.first?.id == row.id)
    }

    @Test func textIsNeverHandedOverToBeDrawn() async {
        let drawn = DrawCount()
        let (monitor, pasteboard, defaults, name) = Self.makeMonitor(enabled: true) { _ in
            drawn.note()
            return nil
        }
        defer { defaults.removePersistentDomain(forName: name) }
        monitor.start()

        pasteboard.simulateCopy(.text("words"))
        monitor.poll()
        await monitor.thumbnailTask?.value

        let none: Int = 0
        #expect(drawn.value == none)
    }

    @Test func aCopyThatLandsDuringTheReadIsThrownAway() {
        let (monitor, pasteboard, defaults, name) = Self.makeMonitor(enabled: true)
        defer { defaults.removePersistentDomain(forName: name) }
        monitor.start()

        // The types said plain text. By the time the read came back, a
        // password manager had put a secret there.
        pasteboard.simulateCopy(.text("plain"))
        pasteboard.duringNextRead = {
            pasteboard.simulateCopy(
                .text("hunter2"),
                types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]
            )
        }
        monitor.poll()

        #expect(monitor.history.entries.isEmpty)

        // The next look sees the secret for what it is and leaves it.
        let readsBefore = pasteboard.contentReads
        monitor.poll()
        #expect(pasteboard.contentReads == readsBefore)
        #expect(monitor.history.entries.isEmpty)
    }

    @Test func anOrdinaryCopyThatLandsDuringTheReadIsPickedUpNext() {
        let (monitor, pasteboard, defaults, name) = Self.makeMonitor(enabled: true)
        defer { defaults.removePersistentDomain(forName: name) }
        monitor.start()

        pasteboard.simulateCopy(.text("first"))
        pasteboard.duringNextRead = { pasteboard.simulateCopy(.text("second")) }
        monitor.poll()
        #expect(monitor.history.entries.isEmpty)

        monitor.poll()
        #expect(monitor.history.entries.map(\.content) == [.text("second")])
    }

    @Test func askingForACopyThatMovedDuringTheReadSaysNothing() {
        let (monitor, pasteboard, defaults, name) = Self.makeMonitor(enabled: true)
        defer { defaults.removePersistentDomain(forName: name) }
        monitor.start()
        pasteboard.simulateCopy(.text("plain"))
        pasteboard.duringNextRead = {
            pasteboard.simulateCopy(.text("hunter2"), types: ["org.nspasteboard.ConcealedType"])
        }

        #expect(monitor.captureNow() == .nothing)
        #expect(monitor.history.entries.isEmpty)
    }

    @Test func isOffUntilTheUserTurnsItOn() {
        let (monitor, _, defaults, name) = Self.makeMonitor()
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(!monitor.isEnabled)
    }

    @Test func nothingIsReadWhileItIsOff() {
        let (monitor, pasteboard, defaults, name) = Self.makeMonitor()
        defer { defaults.removePersistentDomain(forName: name) }
        pasteboard.simulateCopy(.text("secret"))

        monitor.start()
        monitor.poll()
        _ = monitor.captureNow()

        let none: Int = 0
        #expect(pasteboard.changeCountReads == none)
        #expect(pasteboard.typeReads == none)
        #expect(pasteboard.contentReads == none)
        #expect(monitor.history.entries.isEmpty)
    }

    @Test func turningItOnSavesTheChoiceAndShowsTheCurrentCopy() {
        let (monitor, pasteboard, defaults, name) = Self.makeMonitor()
        defer { defaults.removePersistentDomain(forName: name) }
        pasteboard.simulateCopy(.text("already there"))

        monitor.setEnabled(true)

        #expect(monitor.isEnabled)
        #expect(monitor.history.entries.map(\.content) == [.text("already there")])
        let saved = defaults.persistentDomain(forName: name) ?? [:]
        #expect(saved[NookClipboardMonitor.enabledKey] as? Bool == true)
        let expectedKeys: Int = 1
        #expect(saved.count == expectedKeys)
    }

    @Test func launchingWithItOnDoesNotReadWhatIsAlreadyThere() {
        let (monitor, pasteboard, defaults, name) = Self.makeMonitor(enabled: true)
        defer { defaults.removePersistentDomain(forName: name) }
        pasteboard.simulateCopy(.text("copied before launch"))

        monitor.start()
        monitor.poll()

        let none: Int = 0
        #expect(pasteboard.contentReads == none)
        #expect(pasteboard.typeReads == none)
        #expect(monitor.history.entries.isEmpty)
    }

    @Test func aPollReadsOnlyWhenTheCountMoved() {
        let (monitor, pasteboard, defaults, name) = Self.makeMonitor(enabled: true)
        defer { defaults.removePersistentDomain(forName: name) }
        monitor.start()

        monitor.poll()
        monitor.poll()
        let none: Int = 0
        #expect(pasteboard.contentReads == none)

        pasteboard.simulateCopy(.text("new"))
        monitor.poll()
        monitor.poll()

        let once: Int = 1
        #expect(pasteboard.contentReads == once)
        #expect(monitor.history.entries.map(\.content) == [.text("new")])
    }

    @Test func aPasswordManagerCopyIsNeverRead() {
        let (monitor, pasteboard, defaults, name) = Self.makeMonitor(enabled: true)
        defer { defaults.removePersistentDomain(forName: name) }
        monitor.start()

        pasteboard.simulateCopy(
            .text("hunter2"),
            types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]
        )
        monitor.poll()

        let none: Int = 0
        #expect(pasteboard.contentReads == none)
        #expect(monitor.history.entries.isEmpty)
    }

    @Test func whileMacOSAsksNothingIsReadUntilTheUserAsks() {
        let (monitor, pasteboard, defaults, name) = Self.makeMonitor(enabled: true)
        defer { defaults.removePersistentDomain(forName: name) }
        pasteboard.accessValue = .asks
        monitor.start()

        pasteboard.simulateCopy(.text("waiting"))
        monitor.poll()

        let none: Int = 0
        #expect(pasteboard.contentReads == none)
        #expect(pasteboard.typeReads == none)
        #expect(monitor.access == .asks)

        #expect(monitor.captureNow() == .added)
        let once: Int = 1
        #expect(pasteboard.contentReads == once)
        #expect(monitor.history.entries.map(\.content) == [.text("waiting")])
    }

    @Test func theNewestCopyIsPickedUpOnceReadsAreAllowed() {
        let (monitor, pasteboard, defaults, name) = Self.makeMonitor(enabled: true)
        defer { defaults.removePersistentDomain(forName: name) }
        pasteboard.accessValue = .asks
        monitor.start()
        pasteboard.simulateCopy(.text("made while asking"))
        monitor.poll()
        #expect(monitor.history.entries.isEmpty)

        pasteboard.accessValue = .allowed
        monitor.poll()

        #expect(monitor.access == .allowed)
        #expect(monitor.history.entries.map(\.content) == [.text("made while asking")])
    }

    @Test func whenReadsAreRefusedNothingIsRead() {
        let (monitor, pasteboard, defaults, name) = Self.makeMonitor(enabled: true)
        defer { defaults.removePersistentDomain(forName: name) }
        pasteboard.accessValue = .denied
        monitor.start()

        pasteboard.simulateCopy(.text("blocked"))
        monitor.poll()

        #expect(monitor.captureNow() == .nothing)
        let none: Int = 0
        #expect(pasteboard.contentReads == none)
        #expect(monitor.access == .denied)
    }

    @Test func askingForAPrivateCopySaysItWasSkipped() {
        let (monitor, pasteboard, defaults, name) = Self.makeMonitor(enabled: true)
        defer { defaults.removePersistentDomain(forName: name) }
        monitor.start()
        pasteboard.simulateCopy(.text("x"), types: ["org.nspasteboard.TransientType"])

        #expect(monitor.captureNow() == .skipped)
        #expect(monitor.history.entries.isEmpty)
    }

    @Test func askingWithNothingReadableSaysNothing() {
        let (monitor, pasteboard, defaults, name) = Self.makeMonitor(enabled: true)
        defer { defaults.removePersistentDomain(forName: name) }
        monitor.start()
        pasteboard.content = nil

        #expect(monitor.captureNow() == .nothing)
    }

    @Test func copyingARowAgainWritesItAndMovesItUpWithoutReadingBack() {
        let (monitor, pasteboard, defaults, name) = Self.makeMonitor(enabled: true)
        defer { defaults.removePersistentDomain(forName: name) }
        monitor.start()
        pasteboard.simulateCopy(.text("old"))
        monitor.poll()
        pasteboard.simulateCopy(.text("new"))
        monitor.poll()
        let old = monitor.history.entries[1]
        let readsBefore = pasteboard.contentReads

        #expect(monitor.copyAgain(old))
        monitor.poll()

        #expect(pasteboard.content == .text("old"))
        #expect(monitor.history.entries.map(\.content) == [.text("old"), .text("new")])
        #expect(pasteboard.contentReads == readsBefore)
        #expect(monitor.justCopiedID == old.id)
    }

    @Test func aRefusedWriteIsReported() {
        let (monitor, pasteboard, defaults, name) = Self.makeMonitor(enabled: true)
        defer { defaults.removePersistentDomain(forName: name) }
        monitor.start()
        pasteboard.simulateCopy(.text("one"))
        monitor.poll()
        pasteboard.acceptsWrites = false

        #expect(!monitor.copyAgain(monitor.history.entries[0]))
        #expect(!monitor.copy(text: "path"))
    }

    @Test func textTheTrayCopiesLandsInTheHistoryWithoutARead() {
        let (monitor, pasteboard, defaults, name) = Self.makeMonitor(enabled: true)
        defer { defaults.removePersistentDomain(forName: name) }
        monitor.start()

        #expect(monitor.copy(text: "/tmp/file.txt"))
        monitor.poll()

        let none: Int = 0
        #expect(pasteboard.contentReads == none)
        #expect(monitor.history.entries.map(\.content) == [.text("/tmp/file.txt")])
    }

    @Test func textTheTrayCopiesIsNotKeptWhileTheHistoryIsOff() {
        let (monitor, pasteboard, defaults, name) = Self.makeMonitor()
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(monitor.copy(text: "/tmp/file.txt"))

        #expect(pasteboard.content == .text("/tmp/file.txt"))
        #expect(monitor.history.entries.isEmpty)
        let none: Int = 0
        #expect(pasteboard.changeCountReads == none)
    }

    @Test func turningItOffForgetsEverythingAndStopsReading() {
        let (monitor, pasteboard, defaults, name) = Self.makeMonitor(enabled: true)
        defer { defaults.removePersistentDomain(forName: name) }
        monitor.start()
        pasteboard.simulateCopy(.text("kept for now"))
        monitor.poll()
        let readsBefore = pasteboard.contentReads

        monitor.setEnabled(false)
        pasteboard.simulateCopy(.text("after off"))
        monitor.poll()

        #expect(monitor.history.entries.isEmpty)
        #expect(pasteboard.contentReads == readsBefore)
        let saved = defaults.persistentDomain(forName: name) ?? [:]
        #expect(saved[NookClipboardMonitor.enabledKey] as? Bool == false)
    }

    @Test func removingARowAndClearing() {
        let (monitor, pasteboard, defaults, name) = Self.makeMonitor(enabled: true)
        defer { defaults.removePersistentDomain(forName: name) }
        monitor.start()
        pasteboard.simulateCopy(.text("one"))
        monitor.poll()
        pasteboard.simulateCopy(.text("two"))
        monitor.poll()

        monitor.remove(monitor.history.entries[0])
        #expect(monitor.history.entries.map(\.content) == [.text("one")])

        monitor.clear()
        #expect(monitor.history.entries.isEmpty)
    }
}
