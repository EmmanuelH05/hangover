import AppKit
import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

// MARK: - T7: the buttons on a recording's tile

@MainActor @Suite(.serialized, .noNewWindows) struct NookTrayRecordingTilesTests {
    /// A recording as the Record widget hands it over: a video hard linked in
    /// from Movies/Hangover.
    private func addRecording(_ fixture: NookTrayFixesFixture, named name: String = "Recording.mp4") async throws -> (item: NookTrayItem, original: URL) {
        let movies = fixture.files.url("Movies")
        try FileManager.default.createDirectory(at: movies, withIntermediateDirectories: true)
        let original = movies.appendingPathComponent(name)
        try FileManager.default.copyItem(at: try fixture.files.movie(seconds: 1), to: original)
        await fixture.store.add(fileAt: original, linking: true)?.value
        return (try #require(fixture.store.items.first), original)
    }

    @Test func aRecordingGetsTheButtonsOnTheMediumAndLargeCards() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let (recording, _) = try await addRecording(fixture)

        for size in [NookWidgetSize.medium, .large] {
            #expect(NookTrayRecordingAction.offered(for: recording, size: size) == [.smaller, .showInFinder])
        }
    }

    @Test func theSmallCardKeepsTheRightClickMenuAlone() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let (recording, _) = try await addRecording(fixture)

        #expect(NookTrayRecordingAction.offered(for: recording, size: .small).isEmpty)
    }

    /// A GIF is made from the Convert chip or the right click menu. The tile
    /// itself carries no GIF button, recording or not (the owner took it off).
    @Test func aDroppedVideoGetsNoButtons() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let dropped = try await fixture.add(try fixture.files.movie(seconds: 1), named: "dropped.mov")

        #expect(dropped.linkedFrom == nil)
        for size in [NookWidgetSize.small, .medium, .large] {
            #expect(NookTrayRecordingAction.offered(for: dropped, size: size).isEmpty)
        }
    }

    @Test func aFileThatIsNotAVideoGetsNoButtons() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let picture = try await fixture.add(try fixture.files.png(width: 8, height: 8), named: "a.png")

        for size in [NookWidgetSize.small, .medium, .large] {
            #expect(NookTrayRecordingAction.offered(for: picture, size: size).isEmpty)
        }
    }


    @Test func thereAreTwoButtonsInTheOrderOfTheSpec() {
        #expect(NookTrayRecordingAction.allCases == [.smaller, .showInFinder])
        let symbols = NookTrayRecordingAction.allCases.map(\.symbol)
        #expect(Set(symbols).count == 2)
    }

    @Test func eachButtonHasHelpTextInEveryLanguage() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let url = root.appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
            for action in NookTrayRecordingAction.allCases {
                #expect(table[action.helpKey]?.isEmpty == false, "\(language) is missing \(action.helpKey)")
            }
        }
    }

    @Test func smallerStartsTheFullHDCopy() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let (recording, _) = try await addRecording(fixture)

        fixture.store.perform(.smaller, on: recording)

        let job = try #require(fixture.store.jobs[recording.id])
        let task = job.task
        fixture.store.cancelJob(for: recording)
        await task.value
        #expect(fixture.store.items.map(\.originalName) == ["Recording.mp4"], "cancelled, so nothing was added")
    }

    @Test func smallerNamesTheCopyAfterThe1080pAction() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let (recording, _) = try await addRecording(fixture)

        fixture.store.perform(.smaller, on: recording)
        let task = try #require(fixture.store.jobs[recording.id]).task
        await task.value

        // Either the copy is smaller and is named for 1080p, or it was not
        // smaller and the tray said so. Never a copy that is not smaller.
        if let copy = fixture.store.items.first(where: { $0.originalName == "Recording (1080p).mp4" }) {
            let before = try #require(NookConvertJobs.fileSize(of: fixture.store.storedURL(for: recording)))
            let after = try #require(NookConvertJobs.fileSize(of: fixture.store.storedURL(for: copy)))
            #expect(after < before)
        } else {
            #expect(fixture.store.notice?.text == fixture.text("nook.tray.convert.notice.alreadySmall"))
        }
    }

    @Test func showInFinderGoesToTheRecordingWhereItWasSaved() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let (recording, original) = try await addRecording(fixture)

        #expect(fixture.store.revealTarget(for: recording) == URL(fileURLWithPath: original.path))
    }

    @Test func showInFinderFallsBackToTheTraysCopyWhenTheRecordingWasMoved() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let (recording, original) = try await addRecording(fixture)
        try FileManager.default.removeItem(at: original)

        #expect(fixture.store.revealTarget(for: recording) == fixture.store.storedURL(for: recording))
    }

    @Test func aDroppedFileRevealsTheTraysCopy() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let dropped = try await fixture.add(try fixture.files.png(width: 8, height: 8), named: "a.png")

        #expect(fixture.store.revealTarget(for: dropped) == fixture.store.storedURL(for: dropped))
    }

    @Test func theButtonsDrawTheirIconsOnAnOtherwiseEmptyTile() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let (recording, _) = try await addRecording(fixture)
        let width: CGFloat = 60
        let height: CGFloat = 20

        let framed = NookTrayRecordingButtons(store: fixture.store, item: recording, actions: NookTrayRecordingAction.allCases)
            .frame(width: width, height: height)
            .background(Color.gray)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: framed.environment(\.nookDrawsStill, true))
        renderer.scale = 4
        let image = try #require(renderer.cgImage, "ImageRenderer returned no image")
        let plain = ImageRenderer(content: Color.gray.frame(width: width, height: height))
        plain.scale = 4
        let blank = try #require(plain.cgImage)

        let drawn = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        let empty = NSBitmapImageRep(cgImage: blank).representation(using: .png, properties: [:])
        #expect(drawn != empty, "the buttons should be on screen")
        // Set OPEN_ISLAND_RENDER_SNAPSHOTS=1 to write the PNG to output/render/ for a look.
        if ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_SNAPSHOTS"] == "1", let drawn {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let directory = root.appendingPathComponent("output/render", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try drawn.write(to: directory.appendingPathComponent("tray-tile-buttons.png"))
        }
    }
}

// MARK: - T4: a bar or a button that would do nothing says why

@MainActor @Suite(.serialized, .noNewWindows) struct NookTrayWaitTests {
    @Test func theCombineBarIsFreeWhileNothingIsRunning() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let pdf = try fixture.files.pdf(pages: 1)
        let a = try await fixture.add(pdf, named: "a.pdf")
        let b = try await fixture.add(pdf, named: "b.pdf")
        fixture.store.toggleSelection(of: a)
        fixture.store.toggleSelection(of: b)

        #expect(fixture.store.combineBlocker == nil)
    }

    @Test func aJobOnAChosenFileBlocksCombineAndNamesIt() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let pdf = try fixture.files.pdf(pages: 1)
        let a = try await fixture.add(pdf, named: "a.pdf")
        let b = try await fixture.add(pdf, named: "b.pdf")
        fixture.store.toggleSelection(of: a)
        fixture.store.toggleSelection(of: b)

        let job = fixture.store.convert(a, action: .pdfPages(.png))

        #expect(fixture.store.combineBlocker?.id == a.id)
        // The click would have done nothing: this is why the button is off.
        #expect(fixture.store.combine(fixture.store.selectedItems, action: .joinPDFs) == nil)
        #expect(!fixture.store.combineActions.isEmpty, "the bar itself stays up")

        await job?.value
        #expect(fixture.store.combineBlocker == nil)
        #expect(fixture.store.combine(fixture.store.selectedItems, action: .joinPDFs) != nil)
    }

    @Test func aJobOnAFileThatIsNotChosenBlocksNothing() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let pdf = try fixture.files.pdf(pages: 1)
        let a = try await fixture.add(pdf, named: "a.pdf")
        let b = try await fixture.add(pdf, named: "b.pdf")
        let c = try await fixture.add(pdf, named: "c.pdf")
        fixture.store.toggleSelection(of: a)
        fixture.store.toggleSelection(of: b)

        let job = fixture.store.convert(c, action: .pdfPages(.png))

        #expect(fixture.store.combineBlocker == nil)
        await job?.value
    }

    @Test func theWaitSentenceNamesTheFile() {
        let text = NookConvertRules.waitText(forBusyFileNamed: "clip.mov")
        #expect(text.contains("clip.mov"))
        #expect(!text.contains("%@"))
    }

    @Test func theGIFOptionsWaitForAJobOnTheirVideo() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let video = try await fixture.add(try fixture.files.movie(seconds: 1), named: "clip.mov")
        fixture.store.convert(video, action: .makeGIF)
        #expect(fixture.store.gifBlocker == nil)

        // Another conversion starts on the same video while the options are open.
        let job = fixture.store.convert(video, action: .video(.mp4))
        #expect(fixture.store.gifBlocker?.id == video.id)

        // Make does nothing, and leaves the options open instead of closing them silently.
        #expect(fixture.store.startGIF(options: NookGIFOptions()) == nil)
        #expect(fixture.store.gifSourceItem?.id == video.id)

        await job?.value
        #expect(fixture.store.gifBlocker == nil)
        #expect(fixture.store.startGIF(options: NookGIFOptions()) != nil)
    }

    @Test func theSheetTurnsMakeOffWhileItWaits() {
        let ready = NookGIFSheetRules.Status.ready(estimatedBytes: 1_000)
        #expect(NookGIFSheetRules.canMake(ready))
        #expect(NookGIFSheetRules.canMake(ready, isWaiting: false))
        #expect(!NookGIFSheetRules.canMake(ready, isWaiting: true))
    }
}
