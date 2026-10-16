import AppKit
import Foundation
import PDFKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// The store's conversion jobs, selection and Combine, on a tray folder, a
/// fake pasteboard and settings of its own. Files come from
/// `NookConvertFixtures`, and nothing leaves a temp folder.
@MainActor
private struct TrayConvertFixture {
    let store: NookTrayStore
    let folder: URL
    let files: NookConvertFixtures

    init() throws {
        files = try NookConvertFixtures()
        folder = files.url("tray")
        let defaults = MemoryDefaults()
        store = NookTrayStore(
            folder: folder,
            clipboard: NookClipboardMonitor(pasteboard: NookFakePasteboard(), defaults: defaults),
            defaults: defaults
        )
    }

    func cleanUp() {
        files.cleanUp()
    }

    /// Puts a file in the tray under `name` and waits for the copy.
    @discardableResult
    func add(_ source: URL, named name: String) async throws -> NookTrayItem {
        let renamed = files.url("incoming-\(UUID().uuidString)").appendingPathComponent(name)
        try FileManager.default.createDirectory(at: renamed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: renamed)
        await store.add(fileAt: renamed)?.value
        return try #require(store.items.first { $0.originalName == name })
    }

    var names: [String] { store.items.map(\.originalName) }

    /// How many job folders the tray holds. A failed or cancelled job must
    /// leave none behind.
    var subfolderCount: Int {
        let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.count
    }

    func text(_ key: String) -> String {
        LanguageManager.shared.t(key)
    }
}

@MainActor @Suite(.serialized, .noNewWindows) struct NookTrayConvertStoreTests {
    // MARK: Jobs

    @Test func aResultSitsBesideItsSourceAndTheSourceStays() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let png = try fixture.files.png(width: 16, height: 16)
        try await fixture.add(png, named: "a.png")
        let middle = try await fixture.add(png, named: "b.png")
        try await fixture.add(png, named: "c.png")
        let before = try Data(contentsOf: fixture.store.storedURL(for: middle))

        await fixture.store.convert(middle, action: .image(.jpeg))?.value

        // Newest first, so the new file takes the place just ahead of b.png.
        #expect(fixture.names == ["c.png", "b.jpg", "b.png", "a.png"])
        #expect(try Data(contentsOf: fixture.store.storedURL(for: middle)) == before)
        #expect(fixture.store.jobs.isEmpty)
        #expect(fixture.store.workingIDs.isEmpty)
        #expect(fixture.store.notice?.isError == false)
    }

    @Test func aTakenNameGetsANumber() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let png = try fixture.files.png(width: 16, height: 16)
        let item = try await fixture.add(png, named: "photo.png")
        try await fixture.add(png, named: "photo.jpg")

        await fixture.store.convert(item, action: .image(.jpeg))?.value

        #expect(fixture.names.contains("photo 2.jpg"))
        #expect(fixture.names.count == 3)
    }

    @Test func resizeAndSmallerFileAreNamedAfterTheirSource() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        // A photo, because a JPEG of a flat picture is bigger than its PNG and
        // would be thrown away as no smaller.
        let item = try await fixture.add(try fixture.files.photoPNG(width: 400, height: 200), named: "shot.png")

        await fixture.store.convert(item, action: .resize(.half))?.value
        await fixture.store.convert(item, action: .smallerImage)?.value

        #expect(Set(fixture.names) == ["shot.png", "shot (50%).png", "shot (smaller).jpg"])
        let half = try #require(fixture.store.items.first { $0.originalName == "shot (50%).png" })
        #expect(try fixture.files.pixelSize(fixture.store.storedURL(for: half)) == CGSize(width: 200, height: 100))
    }

    @Test func aFileGetsOnlyTheActionsItIsOffered() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.add(try fixture.files.png(width: 16, height: 16), named: "a.png")

        #expect(fixture.store.convert(item, action: .video(.mp4)) == nil)
        #expect(fixture.store.convert(item, action: .pdfPages(.png)) == nil)
        #expect(fixture.store.convert(item, action: .image(.png)) == nil, "a picture is not offered its own format")
        #expect(fixture.store.jobs.isEmpty)
        #expect(fixture.names == ["a.png"])
    }

    @Test func aFileBeingConvertedIsNotConvertedAgain() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.add(try fixture.files.movie(seconds: 1), named: "clip.mov")

        let first = fixture.store.convert(item, action: .video(.mp4))
        #expect(first != nil)
        #expect(fixture.store.jobs[item.id] != nil)
        #expect(fixture.store.convert(item, action: .smallerVideo(.p720)) == nil)

        await first?.value
        #expect(fixture.store.jobs.isEmpty)
        #expect(fixture.names == ["clip.mp4", "clip.mov"])
    }

    @Test func aFailureSaysSoOnceAndLeavesNothingBehind() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let fakeVideo = fixture.files.url("fake.mov")
        try Data("not a video".utf8).write(to: fakeVideo)
        let item = try await fixture.add(fakeVideo, named: "fake.mov")
        let foldersBefore = fixture.subfolderCount

        await fixture.store.convert(item, action: .video(.mp4))?.value

        #expect(fixture.names == ["fake.mov"])
        #expect(fixture.store.notice?.isError == true)
        #expect(fixture.store.notice?.text == fixture.text("nook.tray.convert.notice.videoFailed"))
        #expect(fixture.store.jobs.isEmpty)
        #expect(fixture.subfolderCount == foldersBefore)
    }

    @Test func aVideoWithNoSoundSaysSo() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.add(try fixture.files.movie(seconds: 1), named: "mute.mov")

        await fixture.store.convert(item, action: .soundOnly)?.value

        #expect(fixture.names == ["mute.mov"])
        #expect(fixture.store.notice?.text == fixture.text("nook.tray.convert.notice.noSound"))
    }

    @Test func soundOnlyAddsAnM4A() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.add(try fixture.files.movie(seconds: 1, withSound: true), named: "talk.mov")

        await fixture.store.convert(item, action: .soundOnly)?.value

        #expect(fixture.names == ["talk.m4a", "talk.mov"])
    }

    @Test func twoVideosInARowBothFinish() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let movie = try fixture.files.movie(seconds: 1)
        let one = try await fixture.add(movie, named: "one.mov")
        let two = try await fixture.add(movie, named: "two.mov")

        let first = fixture.store.convert(one, action: .video(.mp4))
        let second = fixture.store.convert(two, action: .video(.mp4))
        // Both are listed as running at once, one of them waiting its turn.
        #expect(fixture.store.jobs.count == 2)
        await second?.value
        await first?.value

        #expect(Set(fixture.names) == ["one.mov", "one.mp4", "two.mov", "two.mp4"])
        #expect(fixture.store.jobs.isEmpty)
    }

    @Test func aPDFBecomesAFolderOfPages() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.add(try fixture.files.pdf(pages: 3), named: "notes.pdf")

        await fixture.store.convert(item, action: .pdfPages(.png))?.value

        #expect(fixture.names == ["notes pages", "notes.pdf"])
        let folder = fixture.store.storedURL(for: try #require(fixture.store.items.first))
        var isFolder: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder) && isFolder.boolValue)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 3)
    }

    @Test func aPDFOverTheLimitSaysHowManyPagesAreAllowed() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let limit: Int = NookConvertRules.maxPDFPages
        let item = try await fixture.add(try fixture.files.pdf(pages: limit + 1, width: 20, height: 20), named: "long.pdf")

        await fixture.store.convert(item, action: .pdfPages(.png))?.value

        #expect(fixture.names == ["long.pdf"])
        #expect(fixture.store.notice?.isError == true)
        #expect(fixture.store.notice?.text == fixture.text("nook.tray.convert.notice.tooManyPages"))
    }

    // MARK: Make GIF

    @Test func makeGIFOpensTheOptionsInsteadOfStartingAJob() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.add(try fixture.files.movie(seconds: 1), named: "clip.mov")

        #expect(fixture.store.convert(item, action: .makeGIF) == nil)
        #expect(fixture.store.gifSourceItem == item)
        #expect(fixture.store.jobs.isEmpty)

        fixture.store.cancelGIF()
        #expect(fixture.store.gifSourceItem == nil)
        #expect(fixture.store.startGIF(options: NookGIFOptions()) == nil, "nothing is waiting for options")
    }

    @Test func aGIFFromSomethingUnreadableFailsWithItsOwnSentence() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let fakeVideo = fixture.files.url("fake.mov")
        try Data("not a video".utf8).write(to: fakeVideo)
        let item = try await fixture.add(fakeVideo, named: "fake.mov")
        fixture.store.convert(item, action: .makeGIF)

        await fixture.store.startGIF(options: NookGIFOptions())?.value

        #expect(fixture.store.gifSourceItem == nil)
        #expect(fixture.names == ["fake.mov"])
        #expect(fixture.store.notice?.text == fixture.text("nook.tray.convert.notice.gifFailed"))
        #expect(fixture.store.jobs.isEmpty)
    }

    @Test func removingTheFileTheGIFOptionsWaitOnClosesThem() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.add(try fixture.files.movie(seconds: 1), named: "clip.mov")
        fixture.store.convert(item, action: .makeGIF)

        fixture.store.remove(item)

        #expect(fixture.store.gifSourceItem == nil)
    }

    // MARK: Review focus 4: removing a file stops its job quietly

    @Test func removingAFileCancelsItsJobAndAddsNothing() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.add(try fixture.files.movie(seconds: 3), named: "clip.mov")

        let job = fixture.store.convert(item, action: .smallerVideo(.p720))
        #expect(job != nil)
        fixture.store.remove(item)
        await job?.value

        #expect(fixture.store.items.isEmpty)
        #expect(fixture.store.jobs.isEmpty)
        #expect(fixture.store.notice == nil || fixture.store.notice?.isError == false)
        #expect(fixture.subfolderCount == 0)
    }

    @Test func clearingTheTrayCancelsEveryJob() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let movie = try fixture.files.movie(seconds: 3)
        try await fixture.add(movie, named: "one.mov")
        try await fixture.add(movie, named: "two.mov")

        let jobs = fixture.store.items.compactMap { fixture.store.convert($0, action: .smallerVideo(.p720)) }
        #expect(jobs.count == 2)
        fixture.store.clear()
        for job in jobs { await job.value }

        #expect(fixture.store.items.isEmpty)
        #expect(fixture.store.jobs.isEmpty)
        #expect(fixture.store.notice == nil || fixture.store.notice?.isError == false)
        #expect(fixture.subfolderCount == 0)
    }

    @Test func cancellingAJobLeavesTheSourceAndSaysNothing() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.add(try fixture.files.movie(seconds: 3), named: "clip.mov")
        let foldersBefore = fixture.subfolderCount

        let job = fixture.store.convert(item, action: .smallerVideo(.p720))
        fixture.store.cancelJob(for: item)
        #expect(fixture.store.jobs.isEmpty, "the row stops showing progress at once")
        await job?.value

        #expect(fixture.names == ["clip.mov"])
        #expect(fixture.store.notice == nil)
        #expect(fixture.subfolderCount == foldersBefore)
    }

    @Test func aCancelledImageJobAddsNothingEither() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.add(try fixture.files.png(width: 64, height: 64), named: "a.png")

        let job = fixture.store.convert(item, action: .image(.jpeg))
        fixture.store.cancelJob(for: item)
        await job?.value

        #expect(fixture.names == ["a.png"])
        #expect(fixture.store.notice == nil)
    }

    // MARK: Selection and Combine

    @Test func commandClickTogglesAndShiftClickTakesARange() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let png = try fixture.files.png(width: 8, height: 8)
        var added: [NookTrayItem] = []
        for name in ["a.png", "b.png", "c.png", "d.png", "e.png"] {
            added.append(try await fixture.add(png, named: name))
        }
        // The list is newest first: e, d, c, b, a.
        let byName = Dictionary(uniqueKeysWithValues: added.map { ($0.originalName, $0) })

        fixture.store.toggleSelection(of: byName["d.png"]!)
        fixture.store.toggleSelection(of: byName["b.png"]!)
        #expect(fixture.store.selection == [byName["d.png"]!.id, byName["b.png"]!.id])

        fixture.store.toggleSelection(of: byName["b.png"]!)
        #expect(fixture.store.selection == [byName["d.png"]!.id])

        // From b (the last one clicked) down the list to a.
        fixture.store.toggleSelection(of: byName["c.png"]!)
        fixture.store.extendSelection(to: byName["a.png"]!)
        #expect(fixture.store.selectedItems.map(\.originalName) == ["d.png", "c.png", "b.png", "a.png"])

        fixture.store.clearSelection()
        #expect(fixture.store.selection.isEmpty)
    }

    @Test func shiftClickWithNothingBeforeItChoosesThatFile() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.add(try fixture.files.png(width: 8, height: 8), named: "a.png")

        fixture.store.extendSelection(to: item)

        #expect(fixture.store.selection == [item.id])
    }

    @Test func removingAFileDropsItFromTheSelection() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let png = try fixture.files.png(width: 8, height: 8)
        let one = try await fixture.add(png, named: "a.png")
        let two = try await fixture.add(png, named: "b.png")
        fixture.store.toggleSelection(of: one)
        fixture.store.toggleSelection(of: two)

        fixture.store.remove(one)
        #expect(fixture.store.selection == [two.id])

        fixture.store.clear()
        #expect(fixture.store.selection.isEmpty)
    }

    @Test func theCombineBarFollowsWhatIsChosen() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let png = try fixture.files.png(width: 8, height: 8)
        let pdf = try fixture.files.pdf(pages: 1)
        let a = try await fixture.add(png, named: "a.png")
        let b = try await fixture.add(png, named: "b.jpg")
        let c = try await fixture.add(pdf, named: "c.pdf")

        #expect(fixture.store.combineActions.isEmpty)
        fixture.store.toggleSelection(of: a)
        #expect(fixture.store.combineActions.isEmpty, "one file is nothing to combine")
        fixture.store.toggleSelection(of: b)
        #expect(fixture.store.combineActions == [.picturesToPDF])
        fixture.store.toggleSelection(of: c)
        #expect(fixture.store.combineActions.isEmpty, "a picture and a PDF do not combine")
    }

    @Test func joiningPDFsKeepsTheTrayOrderAndClearsTheSelection() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let small = try fixture.files.pdf(pages: 1, width: 100, height: 100)
        let large = try fixture.files.pdf(pages: 2, width: 200, height: 200)
        // The list reads: large, small. That is the order they join in.
        let first = try await fixture.add(small, named: "small.pdf")
        let second = try await fixture.add(large, named: "large.pdf")
        fixture.store.toggleSelection(of: first)
        fixture.store.toggleSelection(of: second)

        await fixture.store.combine(fixture.store.selectedItems, action: .joinPDFs)?.value

        #expect(fixture.names == ["Joined.pdf", "large.pdf", "small.pdf"])
        let joinedItem = try #require(fixture.store.items.first)
        let joined = try #require(PDFDocument(url: fixture.store.storedURL(for: joinedItem)))
        #expect(joined.pageCount == 3)
        #expect(joined.page(at: 0)?.bounds(for: .mediaBox).width == 200)
        #expect(joined.page(at: 2)?.bounds(for: .mediaBox).width == 100)
        #expect(fixture.store.selection.isEmpty)
        #expect(fixture.store.jobs.isEmpty)
        // The two PDFs it was made from are still there.
        #expect(PDFDocument(url: fixture.store.storedURL(for: first))?.pageCount == 1)
        #expect(PDFDocument(url: fixture.store.storedURL(for: second))?.pageCount == 2)
    }

    @Test func picturesBecomeOnePDF() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let png = try fixture.files.png(width: 30, height: 20)
        let one = try await fixture.add(png, named: "one.png")
        let two = try await fixture.add(png, named: "two.png")

        await fixture.store.combine([two, one], action: .picturesToPDF)?.value

        #expect(fixture.names.first == "Pictures.pdf")
        let made = try #require(fixture.store.items.first { $0.originalName == "Pictures.pdf" })
        #expect(PDFDocument(url: fixture.store.storedURL(for: made))?.pageCount == 2)
    }

    @Test func combiningSomethingThatDoesNotCombineDoesNothing() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let png = try fixture.files.png(width: 8, height: 8)
        let a = try await fixture.add(png, named: "a.png")
        let b = try await fixture.add(try fixture.files.pdf(pages: 1), named: "b.pdf")

        #expect(fixture.store.combine([a, b], action: .joinPDFs) == nil)
        #expect(fixture.store.combine([a], action: .picturesToPDF) == nil)
        #expect(fixture.names == ["b.pdf", "a.png"])
    }

    @Test func aBrokenPDFSaysTheJoinFailed() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let broken = fixture.files.url("broken.pdf")
        try Data("not a pdf".utf8).write(to: broken)
        let a = try await fixture.add(try fixture.files.pdf(pages: 1), named: "a.pdf")
        let b = try await fixture.add(broken, named: "b.pdf")

        await fixture.store.combine([b, a], action: .joinPDFs)?.value

        #expect(fixture.names == ["b.pdf", "a.pdf"])
        #expect(fixture.store.notice?.text == fixture.text("nook.tray.convert.notice.combineFailed"))
    }

    @Test func removingOneOfTheFilesBeingJoinedStopsTheJoinQuietly() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let pdf = try fixture.files.pdf(pages: 2)
        let a = try await fixture.add(pdf, named: "a.pdf")
        let b = try await fixture.add(pdf, named: "b.pdf")

        let job = fixture.store.combine([b, a], action: .joinPDFs)
        #expect(fixture.store.jobs.count == 2)
        fixture.store.remove(a)
        await job?.value

        #expect(fixture.names == ["b.pdf"])
        #expect(fixture.store.jobs.isEmpty)
        #expect(fixture.store.notice == nil || fixture.store.notice?.isError == false)
    }
}

@Suite struct NookProgressReporterTests {
    @Test func onlyAStepOfAHundredthIsPassedOn() {
        let seen = SeenValues()
        let reporter = NookProgressReporter { seen.add($0) }

        for value in [0.0, 0.001, 0.005, 0.02, 0.021, 0.5, 0.505, 0.52] {
            reporter.report(value)
        }

        #expect(seen.values == [0.0, 0.02, 0.5, 0.52])
    }

    @Test func theEndIsAlwaysPassedOn() {
        let seen = SeenValues()
        let reporter = NookProgressReporter { seen.add($0) }

        reporter.report(0.999)
        reporter.report(1)

        #expect(seen.values == [0.999, 1])
    }
}

private final class SeenValues: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Double] = []

    func add(_ value: Double) { lock.withLock { stored.append(value) } }
    var values: [Double] { lock.withLock { stored } }
}

// MARK: - The card

/// Draws the card with `ImageRenderer`, as the tray's other render tests do,
/// to see that a choice, the Combine bar and a running job each change what
/// is on screen. `ImageRenderer` cannot draw AppKit-backed views, which is
/// why the card is drawn with its drop target off. Set
/// `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to also write the PNGs to
/// `output/render/` under the repo root for a visual check.
@MainActor @Suite(.serialized, .noNewWindows) struct NookTrayConvertRenderTests {
    private func render(_ name: String, _ store: NookTrayStore, size: NookWidgetSize = .large) throws -> Data {
        let width: CGFloat = size == .small ? 204 : 416
        let framed = NookTrayCard(store: store, takesDrops: false)
            .environment(\.nookWidgetSize, size)
            .frame(width: width, height: NookTrayCard.height(for: size))
            .padding(8)
            .background(V6Palette.ink)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: framed.environment(\.nookDrawsStill, true))
        renderer.scale = 2
        let image = try #require(renderer.cgImage, "ImageRenderer returned no image")
        let encoded = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        let png = try #require(encoded)
        if ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_SNAPSHOTS"] == "1" {
            let directory = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("output/render", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return png
    }

    @Test func aChoiceTheCombineBarAndAJobEachChangeTheCard() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let pdf = try fixture.files.pdf(pages: 1)
        let one = try await fixture.add(pdf, named: "one.pdf")
        let two = try await fixture.add(pdf, named: "two.pdf")
        let plain = try render("tray-convert-plain", fixture.store)

        fixture.store.toggleSelection(of: one)
        let oneChosen = try render("tray-convert-one-chosen", fixture.store)
        #expect(plain != oneChosen, "a chosen file should look chosen")

        fixture.store.toggleSelection(of: two)
        let bothChosen = try render("tray-convert-combine-bar", fixture.store)
        #expect(oneChosen != bothChosen, "two PDFs chosen should bring up the Combine bar")

        // The smaller cards bring the bar up too.
        for size in [NookWidgetSize.small, .medium] {
            let withBar = try render("tray-convert-combine-bar-\(size.rawValue)", fixture.store, size: size)
            fixture.store.clearSelection()
            let without = try render("tray-convert-plain-\(size.rawValue)", fixture.store, size: size)
            #expect(without != withBar, "the \(size.rawValue) card should show the Combine bar")
            fixture.store.toggleSelection(of: one)
            fixture.store.toggleSelection(of: two)
        }

        fixture.store.clearSelection()
        let job = fixture.store.convert(one, action: .pdfPages(.png))
        let running = try render("tray-convert-running", fixture.store)
        #expect(plain != running, "a file being converted should show a job")
        await job?.value
    }

    @Test func theGIFOptionsOpenAboveTheCardsAndLeaveTheTilesInPlace() async throws {
        let fixture = try TrayConvertFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.add(try fixture.files.movie(seconds: 1), named: "clip.mov")
        let list = try render("tray-convert-list", fixture.store)

        fixture.store.convert(item, action: .makeGIF)
        #expect(fixture.store.gifSourceItem?.id == item.id)
        let withOptions = try render("tray-convert-gif-open", fixture.store)
        fixture.store.cancelGIF()
        #expect(fixture.store.gifSourceItem == nil)

        // The options sit in a strip above the cards (NookGIFStrip): a tray
        // card at any size is too short for them.
        #expect(list == withOptions)
    }

    @Test func theGIFStripAddsItsHeightToThePageAndHasRoomForTheWholeSheet() {
        let closed = NookPageExtras()
        var open = NookPageExtras()
        open.showsGIFOptions = true
        #expect(open.pinnedHeight - closed.pinnedHeight == NookGIFStripLayout.pageHeight)
        let roomForTheSheet = NookGIFStripLayout.height - NookGIFStripLayout.verticalPadding * 2
        let tallestSheet = NookGIFSheetLayout.wideHeight + NookGIFStripLayout.tooLongRow
        #expect(roomForTheSheet >= tallestSheet)
    }
}
