import Foundation
import Testing
@testable import OpenIslandApp

/// Stands in for the Notes app. Records what it was asked to add.
final class StubAppleNotesWriter: NookAppleNotesWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(line: String, title: String)] = []
    private var failure: NookAppleNotesError?
    private var isSlow = false
    private var running = 0
    private var peak = 0

    /// The most sends that were ever in flight together.
    var mostAtOnce: Int { lock.withLock { peak } }

    /// Makes each send take a moment, which lets sends overlap if they can.
    func slowDown() {
        lock.withLock { isSlow = true }
    }

    var lines: [String] { lock.withLock { recorded.map(\.line) } }
    var titles: [String] { lock.withLock { recorded.map(\.title) } }

    func fail(with error: NookAppleNotesError?) {
        lock.withLock { failure = error }
    }

    func append(lineHTML: String, toNoteTitled title: String) async throws {
        let (error, slow): (NookAppleNotesError?, Bool) = lock.withLock {
            recorded.append((lineHTML, title))
            running += 1
            peak = max(peak, running)
            return (failure, isSlow)
        }
        if slow { try? await Task.sleep(for: .milliseconds(20)) }
        lock.withLock { running -= 1 }
        if let error { throw error }
    }
}

@MainActor
@Suite struct NookAppleNotesTests {
    @MainActor
    final class Harness {
        let defaults: UserDefaults = MemoryDefaults()
        let writer = StubAppleNotesWriter()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NookAppleNotesTests-\(UUID().uuidString)", isDirectory: true)
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        var fileURL: URL { directory.appendingPathComponent("Quick Notes.md") }

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }

        func makeService() -> NookNotesService {
            let date = date
            return NookNotesService(defaults: defaults, appleNotes: writer, fileURL: fileURL, now: { date })
        }

        func fileText() -> String {
            (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        }

        func settle(_ service: NookNotesService) async {
            await service.lastSend?.value
        }
    }

    // MARK: The line

    @Test func typedTextIsNeverReadAsMarkup() {
        let line = NookAppleNotesLine.html(text: "a <b>bold</b> & <script>x</script>", stamp: "2026-10-09 09:41")

        #expect(line == "<div><b>2026-10-09 09:41</b> a &lt;b&gt;bold&lt;/b&gt; &amp; &lt;script&gt;x&lt;/script&gt;</div>")
        #expect(NookAppleNotesLine.escape("&lt;") == "&amp;lt;")
    }

    @Test func theScriptTakesTheTextAsAnArgument() {
        let script = NookAppleNotesScriptWriter.appendScript

        // Nothing typed is ever pasted into the script's own text.
        #expect(script.contains("item 3 of argv"))
        #expect(script.contains("default folder of default account"))
        #expect(!script.contains("\\("))
    }

    @Test func aRefusalByMacOSIsToldApartFromOtherFailures() {
        let denied = "execution error: Not authorized to send Apple events to Notes. (-1743)"

        #expect(NookAppleNotesScriptWriter.error(forStandardError: denied) == .notPermitted)
        #expect(NookAppleNotesScriptWriter.error(forStandardError: "execution error: Notes got an error (-10000)") == .failed)
        #expect(NookAppleNotesScriptWriter.error(forStandardError: "") == .failed)
    }

    // MARK: The service

    @Test func aNewInstallSavesToTheFile() {
        let harness = Harness()
        let service = harness.makeService()

        service.append("Buy milk")

        #expect(service.destination == .file)
        #expect(harness.writer.lines.isEmpty)
        #expect(harness.fileText().contains("Buy milk"))
        #expect(service.entries.map(\.text) == ["Buy milk"])
        #expect(service.canDelete)
    }

    @Test func withAppleNotesPickedTheLineGoesToNotesAndNotToTheFile() async {
        let harness = Harness()
        let service = harness.makeService()
        service.setDestination(.appleNotes)

        service.append("  Call   mom\nat six ")
        await harness.settle(service)

        #expect(harness.writer.titles == [NookAppleNotesLine.noteTitle])
        #expect(harness.writer.lines.count == 1)
        #expect(harness.writer.lines.first?.hasSuffix("</b> Call   mom at six</div>") == true)
        #expect(!harness.fileText().contains("Call"))
        #expect(service.entries.map(\.text) == ["Call   mom at six"])
        #expect(service.canDelete == false)
        #expect(harness.defaults.string(forKey: NookNotesService.destinationDefaultsKey) == "appleNotes")
    }

    @Test func theChoiceAndTheListComeBackOnTheNextStart() async {
        let harness = Harness()
        let first = harness.makeService()
        first.setDestination(.appleNotes)
        first.append("One")
        first.append("Two")
        await harness.settle(first)

        let second = harness.makeService()

        #expect(second.destination == .appleNotes)
        #expect(second.entries.map(\.text) == ["Two", "One"])
    }

    @Test func aNoteNotesWillNotTakeGoesToTheFile() async {
        let harness = Harness()
        let service = harness.makeService()
        service.setDestination(.appleNotes)
        harness.writer.fail(with: .notPermitted)

        service.append("Do not lose me")
        await harness.settle(service)

        // Out of the Apple Notes list, into the file.
        #expect(service.appleNotesEntries.isEmpty)
        #expect(harness.fileText().contains("Do not lose me"))
        #expect(service.fileEntries.map(\.text) == ["Do not lose me"])
    }

    @Test func sendsGoOutOneAtATimeAndInOrder() async {
        let harness = Harness()
        let service = harness.makeService()
        service.setDestination(.appleNotes)
        harness.writer.slowDown()

        service.append("First")
        service.append("Second")
        service.append("Third")
        await harness.settle(service)

        // The script reads the note and writes it back. Two at once would
        // lose a line.
        #expect(harness.writer.mostAtOnce == 1)
        #expect(harness.writer.lines.map { $0.contains("First") ? 1 : $0.contains("Second") ? 2 : 3 } == [1, 2, 3])
    }

    @Test func aNoteNeitherPlaceTakesStaysInTheCardsList() async {
        let harness = Harness()
        // A file that cannot be written: its folder is a file.
        try? FileManager.default.createDirectory(at: harness.directory, withIntermediateDirectories: true)
        let blocker = harness.directory.appendingPathComponent("blocked")
        try? Data("x".utf8).write(to: blocker)
        let service = NookNotesService(
            defaults: harness.defaults, appleNotes: harness.writer,
            fileURL: blocker.appendingPathComponent("Quick Notes.md")
        )
        service.setDestination(.appleNotes)
        harness.writer.fail(with: .failed)

        service.append("Still here")
        await service.lastSend?.value

        #expect(service.appleNotesEntries.map(\.text) == ["Still here"])
    }

    @Test func emptyTextIsNotSent() async {
        let harness = Harness()
        let service = harness.makeService()
        service.setDestination(.appleNotes)

        service.append("   \n ")
        await harness.settle(service)

        #expect(harness.writer.lines.isEmpty)
        #expect(service.entries.isEmpty)
    }

    @Test func theListKeepsTheLastTwenty() async {
        let harness = Harness()
        let service = harness.makeService()
        service.setDestination(.appleNotes)

        for index in 1...25 { service.append("Note \(index)") }
        await harness.settle(service)

        #expect(service.entries.count == 20)
        #expect(service.entries.first?.text == "Note 25")
        #expect(harness.writer.lines.count == 25)
    }

    @Test func aLineOfAnAppleNoteCannotBeDeletedFromTheCard() async {
        let harness = Harness()
        let service = harness.makeService()
        service.append("In the file")
        service.setDestination(.appleNotes)
        service.append("In Notes")
        await harness.settle(service)
        let id = service.entries.first?.id ?? ""

        service.delete(id)

        #expect(service.entries.map(\.text) == ["In Notes"])
        #expect(harness.fileText().contains("In the file"))
    }

    @Test func theCardSaysWhereNotesGo() {
        let harness = Harness()
        let service = harness.makeService()

        #expect(NookNotesCard.destinationName(service) == "Quick Notes.md")
        service.setDestination(.appleNotes)
        #expect(NookNotesCard.destinationName(service) == "Apple Notes")
        #expect(NookNotesCard.destinationLine(service) == "Saves to Apple Notes, in Quick Notes")
    }
}
