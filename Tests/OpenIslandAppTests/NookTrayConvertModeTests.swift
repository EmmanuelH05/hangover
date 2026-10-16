import Foundation
import Testing
@testable import OpenIslandApp

/// The tray's Convert mode: the chip turns on picking, a click on a file
/// opens the Convert strip for it, and a choice in the strip starts the
/// conversion. Files come from `NookConvertFixtures` in a temp folder, and
/// the pasteboard and settings are fakes.
@MainActor @Suite(.serialized, .noNewWindows) struct NookTrayConvertModeStoreTests {
    private func addNotes(to fixture: NookTrayFixesFixture) async throws -> NookTrayItem {
        let notes = fixture.files.url("notes.txt")
        try Data("plain text".utf8).write(to: notes)
        return try await fixture.add(notes, named: "notes.txt")
    }

    // MARK: Picking

    @Test func pressingConvertStartsPickingAndPressingItAgainCancels() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        try await fixture.add(try fixture.files.png(width: 16, height: 16), named: "a.png")

        #expect(!fixture.store.isPickingToConvert)
        fixture.store.togglePickingToConvert()
        #expect(fixture.store.isPickingToConvert)
        fixture.store.togglePickingToConvert()
        #expect(!fixture.store.isPickingToConvert)
    }

    @Test func pickingNeedsFilesToPickFromAndTheFilesTab() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }

        fixture.store.beginPickingToConvert()
        #expect(!fixture.store.isPickingToConvert, "an empty tray has nothing to pick")

        try await fixture.add(try fixture.files.png(width: 16, height: 16), named: "a.png")
        fixture.store.tab = .clipboard
        fixture.store.beginPickingToConvert()
        #expect(!fixture.store.isPickingToConvert, "the clipboard tab shows no files")
    }

    @Test func pickingAConvertibleFileOpensTheStripAndEndsPicking() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.add(try fixture.files.png(width: 16, height: 16), named: "a.png")
        fixture.store.beginPickingToConvert()

        #expect(fixture.store.pickToConvert(item))

        #expect(fixture.store.convertSourceItem == item)
        #expect(!fixture.store.isPickingToConvert)
    }

    @Test func aFileWithNoConversionsCannotBePicked() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let notes = try await addNotes(to: fixture)
        fixture.store.beginPickingToConvert()

        #expect(!fixture.store.canPickToConvert(notes))
        #expect(!fixture.store.pickToConvert(notes))

        #expect(fixture.store.convertSourceItem == nil)
        #expect(fixture.store.isPickingToConvert, "a click on the wrong tile keeps looking")
    }

    @Test func aFileIsOnlyPickedWhilePicking() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.add(try fixture.files.png(width: 16, height: 16), named: "a.png")

        #expect(!fixture.store.pickToConvert(item))
        #expect(fixture.store.convertSourceItem == nil)
    }

    @Test func choosingTheClipboardTabEndsPicking() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        try await fixture.add(try fixture.files.png(width: 16, height: 16), named: "a.png")
        fixture.store.beginPickingToConvert()
        #expect(fixture.store.isPickingToConvert)

        fixture.store.tab = .clipboard

        #expect(!fixture.store.isPickingToConvert)
        fixture.store.tab = .files
        #expect(!fixture.store.isPickingToConvert, "coming back does not bring picking back")
    }

    @Test func removingTheLastFileEndsPickingButAnotherFileDoesNot() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let png = try fixture.files.png(width: 16, height: 16)
        let first = try await fixture.add(png, named: "a.png")
        let second = try await fixture.add(png, named: "b.png")
        fixture.store.beginPickingToConvert()

        fixture.store.remove(first)
        #expect(fixture.store.isPickingToConvert)

        fixture.store.remove(second)
        #expect(!fixture.store.isPickingToConvert)
    }

    @Test func cancellingPickingLeavesAnOpenStripAlone() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let png = try fixture.files.png(width: 16, height: 16)
        let first = try await fixture.add(png, named: "a.png")
        try await fixture.add(png, named: "b.png")
        fixture.store.beginPickingToConvert()
        fixture.store.pickToConvert(first)

        fixture.store.beginPickingToConvert()
        fixture.store.cancelPickingToConvert()

        #expect(fixture.store.convertSourceItem == first)
    }

    // MARK: The strip

    @Test func choosingAnActionStartsTheJobAndClosesTheStrip() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.add(try fixture.files.png(width: 16, height: 16), named: "a.png")
        fixture.store.beginPickingToConvert()
        fixture.store.pickToConvert(item)

        let job = fixture.store.chooseConversion(.image(.jpeg), for: item)

        #expect(job != nil)
        #expect(fixture.store.jobs[item.id] != nil, "the job is running as the strip closes")
        #expect(fixture.store.convertSourceItem == nil)
        await job?.value
        #expect(fixture.names == ["a.jpg", "a.png"])
    }

    @Test func choosingMakeGIFOpensTheGIFOptionsAndClosesTheStrip() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.add(try fixture.files.movie(seconds: 1), named: "clip.mov")
        fixture.store.beginPickingToConvert()
        fixture.store.pickToConvert(item)

        let job = fixture.store.chooseConversion(.makeGIF, for: item)

        #expect(job == nil, "the options come first, nothing runs yet")
        #expect(fixture.store.gifSourceItem?.id == item.id)
        #expect(fixture.store.convertSourceItem == nil)
        #expect(fixture.store.jobs.isEmpty)
    }

    @Test func anActionTheFileIsNotOfferedLeavesTheStripOpen() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.add(try fixture.files.png(width: 16, height: 16), named: "a.png")
        fixture.store.beginPickingToConvert()
        fixture.store.pickToConvert(item)

        #expect(fixture.store.chooseConversion(.video(.mp4), for: item) == nil)

        #expect(fixture.store.convertSourceItem == item)
        #expect(fixture.names == ["a.png"])
    }

    @Test func aFileThatIsBusyKeepsTheStripOpenAndNamesItself() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.add(try fixture.files.pdf(pages: 1), named: "doc.pdf")
        fixture.store.beginPickingToConvert()
        fixture.store.pickToConvert(item)
        #expect(fixture.store.convertBlocker == nil)

        let running = fixture.store.convert(item, action: .pdfPages(.png))
        #expect(fixture.store.convertBlocker?.id == item.id)
        #expect(fixture.store.chooseConversion(.pdfPages(.jpeg), for: item) == nil)

        #expect(fixture.store.convertSourceItem == item, "the buttons wait, the strip stays")
        await running?.value
        #expect(fixture.store.convertBlocker == nil)
    }

    @Test func removingTheFileClosesTheStrip() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let png = try fixture.files.png(width: 16, height: 16)
        let first = try await fixture.add(png, named: "a.png")
        let second = try await fixture.add(png, named: "b.png")
        fixture.store.beginPickingToConvert()
        fixture.store.pickToConvert(first)

        fixture.store.remove(second)
        #expect(fixture.store.convertSourceItem == first, "another file's removal leaves it open")

        fixture.store.remove(first)
        #expect(fixture.store.convertSourceItem == nil)
    }

    @Test func clearingTheTrayClosesEverything() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.add(try fixture.files.png(width: 16, height: 16), named: "a.png")
        fixture.store.beginPickingToConvert()
        fixture.store.pickToConvert(item)
        fixture.store.beginPickingToConvert()

        fixture.store.clear()

        #expect(fixture.store.convertSourceItem == nil)
        #expect(!fixture.store.isPickingToConvert)
    }

    @Test func cancellingTheStripClosesIt() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.add(try fixture.files.png(width: 16, height: 16), named: "a.png")
        fixture.store.beginPickingToConvert()
        fixture.store.pickToConvert(item)

        fixture.store.cancelConvertStrip()

        #expect(fixture.store.convertSourceItem == nil)
        #expect(fixture.names == ["a.png"], "nothing was made")
    }

    @Test func theConvertStripAndTheGIFOptionsNeverShowTogether() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let video = try await fixture.add(try fixture.files.movie(seconds: 1), named: "clip.mov")
        let picture = try await fixture.add(try fixture.files.png(width: 16, height: 16), named: "a.png")

        // The GIF options are open, then a file is picked.
        fixture.store.convert(video, action: .makeGIF)
        #expect(fixture.store.gifSourceItem?.id == video.id)
        fixture.store.beginPickingToConvert()
        fixture.store.pickToConvert(picture)
        #expect(fixture.store.convertSourceItem == picture)
        #expect(fixture.store.gifSourceItem == nil, "opening the Convert strip closes the GIF options")

        // The Convert strip is open, then Make GIF is asked for.
        fixture.store.convert(video, action: .makeGIF)
        #expect(fixture.store.gifSourceItem?.id == video.id)
        #expect(fixture.store.convertSourceItem == nil, "opening the GIF options closes the Convert strip")
    }
}
