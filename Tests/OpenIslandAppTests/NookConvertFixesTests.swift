import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import OpenIslandApp

// MARK: - T1: smaller and resized are checked

@Suite struct NookConvertSmallerRulesTests {
    private func write(_ bytes: Int, to url: URL) throws {
        try Data(repeating: 1, count: bytes).write(to: url)
    }

    @Test func aCopyThatIsSmallerIsKept() throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let source = fixtures.url("big.bin")
        let result = fixtures.url("small.bin")
        try write(1_000, to: source)
        try write(999, to: result)

        try NookConvertJobs.requireSmaller(result, than: source)

        #expect(FileManager.default.fileExists(atPath: result.path))
    }

    @Test(arguments: [1_000, 1_500])
    func aCopyThatIsTheSameSizeOrBiggerIsRemovedAndSaysSo(copyBytes: Int) throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let source = fixtures.url("file.bin")
        let result = fixtures.url("copy.bin")
        try write(1_000, to: source)
        try write(copyBytes, to: result)

        #expect(throws: NookTrayFileActionError.notSmaller) {
            try NookConvertJobs.requireSmaller(result, than: source)
        }
        #expect(!FileManager.default.fileExists(atPath: result.path))
        #expect(FileManager.default.fileExists(atPath: source.path), "the original is never touched")
    }

    @Test func aCopyThatCannotBeMeasuredIsNotReportedAsDone() throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let source = fixtures.url("file.bin")
        try write(1_000, to: source)

        #expect(throws: NookTrayFileActionError.unreadable) {
            try NookConvertJobs.requireSmaller(fixtures.url("never-made.bin"), than: source)
        }
    }

    @Test func notSmallerHasItsOwnSentenceAndIsNotShownAsAnError() {
        #expect(NookConvertRules.noticeKey(for: NookTrayFileActionError.notSmaller, action: .smallerImage) == "nook.tray.convert.notice.alreadySmall")
        #expect(NookConvertRules.noticeKey(for: NookTrayFileActionError.notSmaller, action: .smallerVideo(.p720)) == "nook.tray.convert.notice.alreadySmall")
        #expect(NookConvertRules.noticeKind(for: NookTrayFileActionError.notSmaller) == .info)
        #expect(NookConvertRules.noticeKind(for: NookTrayFileActionError.writeFailed) == .error)
        #expect(NookConvertRules.noticeKind(for: NookGIFError.decodeFailed) == .error)
    }
}

@Suite struct NookConvertResizeRulesTests {
    @Test func aLongSideAtOrAboveThePicturesOwnIsNotOffered() {
        let at1280 = NookConvertRules.actions(forFileNamed: "a.png", pixelLongSide: 1280)
        #expect(!at1280.contains(.resize(.longSide(1920))))
        #expect(!at1280.contains(.resize(.longSide(1280))), "the same size is no resize")
        #expect(at1280.contains(.resize(.longSide(640))))
        #expect(at1280.contains(.resize(.half)))
        #expect(at1280.contains(.resize(.quarter)))
    }

    @Test func oneLongSideBelowThePicturesOwnIsOffered() {
        let at1281 = NookConvertRules.actions(forFileNamed: "a.png", pixelLongSide: 1281)
        #expect(at1281.contains(.resize(.longSide(1280))))
        #expect(!at1281.contains(.resize(.longSide(1920))))
    }

    @Test func aPictureNotKnownToBeSmallGetsEveryResize() {
        let unknown = NookConvertRules.actions(forFileNamed: "a.png", pixelLongSide: nil)
        #expect(unknown == NookConvertRules.actions(forFileNamed: "a.png"))
        for resize in NookResize.all { #expect(unknown.contains(.resize(resize))) }
    }

    @Test func aPictureOnePixelWideCannotBeResizedAtAll() {
        let tiny = NookConvertRules.actions(forFileNamed: "a.png", pixelLongSide: 1)
        let resizes = tiny.filter { if case .resize = $0 { true } else { false } }
        #expect(resizes.isEmpty)
        #expect(tiny.contains(.smallerImage), "the other choices stay")
    }

    @Test func whatIsNotAPictureIsNotChangedByASize() {
        let video = NookConvertRules.actions(forFileNamed: "a.mov", pixelLongSide: 10)
        #expect(video == NookConvertRules.actions(forFileNamed: "a.mov"))
    }

    @Test func halfAndQuarterNeedAtLeastTwoPixels() {
        #expect(NookResize.half.shrinks(longSide: 2))
        #expect(NookResize.quarter.shrinks(longSide: 2))
        #expect(!NookResize.half.shrinks(longSide: 1))
        #expect(!NookResize.quarter.shrinks(longSide: 1))
        #expect(!NookResize.longSide(640).shrinks(longSide: 640))
        #expect(NookResize.longSide(640).shrinks(longSide: 641))
    }

    @Test func theMenuReadsThePictureSizeFromTheFileHeader() throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let png = try fixtures.png(width: 1000, height: 400)

        let actions = NookConvertRules.actions(forFileNamed: "wide.png", at: png)

        #expect(!actions.contains(.resize(.longSide(1920))))
        #expect(!actions.contains(.resize(.longSide(1280))))
        #expect(actions.contains(.resize(.longSide(640))))
    }

    @Test func aPictureThatCannotBeReadKeepsTheWholeMenu() throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }

        let actions = NookConvertRules.actions(forFileNamed: "gone.png", at: fixtures.url("gone.png"))

        #expect(actions == NookConvertRules.actions(forFileNamed: "gone.png"))
    }
}

// MARK: - T1 in the tray

@MainActor @Suite(.serialized, .noNewWindows) struct NookTraySmallerStoreTests {
    @Test func aSmallerPictureThatIsNotSmallerIsThrownAwayWithAnInfoNotice() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        // A flat 16 pixel PNG is a few dozen bytes. Its JPEG is bigger.
        let item = try await fixture.add(try fixture.files.png(width: 16, height: 16), named: "tiny.png")
        let foldersBefore = fixture.subfolders

        await fixture.store.convert(item, action: .smallerImage)?.value

        #expect(fixture.names == ["tiny.png"])
        #expect(fixture.store.notice?.text == fixture.text("nook.tray.convert.notice.alreadySmall"))
        #expect(fixture.store.notice?.kind == .info)
        #expect(fixture.subfolders == foldersBefore, "the thrown away copy leaves no folder")
        #expect(fixture.store.jobs.isEmpty)
    }

    @Test func aSmallerPictureThatIsSmallerIsKept() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.add(try fixture.files.photoPNG(width: 600, height: 600), named: "grain.png")

        await fixture.store.convert(item, action: .smallerImage)?.value

        #expect(Set(fixture.names) == ["grain.png", "grain (smaller).jpg"])
        let made = try #require(fixture.store.items.first { $0.originalName == "grain (smaller).jpg" })
        let before = try #require(NookConvertJobs.fileSize(of: fixture.store.storedURL(for: item)))
        let after = try #require(NookConvertJobs.fileSize(of: fixture.store.storedURL(for: made)))
        #expect(after < before)
        #expect(fixture.store.notice?.kind == .done)
    }

    @Test func aSmallerVideoIsOnlyKeptWhenItIsSmaller() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let first = try await fixture.add(try fixture.files.movie(seconds: 1), named: "clip.mov")
        await fixture.store.convert(first, action: .smallerVideo(.p720))?.value
        // Squeezing a copy that is already squeezed is where it stops.
        guard let second = fixture.store.items.first(where: { $0.originalName == "clip (720p).mp4" }) else {
            #expect(fixture.store.notice?.text == fixture.text("nook.tray.convert.notice.alreadySmall"))
            return
        }
        await fixture.store.convert(second, action: .smallerVideo(.p720))?.value

        let again = fixture.store.items.first { $0.originalName == "clip (720p) (720p).mp4" }
        if let again {
            let before = try #require(NookConvertJobs.fileSize(of: fixture.store.storedURL(for: second)))
            let after = try #require(NookConvertJobs.fileSize(of: fixture.store.storedURL(for: again)))
            #expect(after < before, "a copy that is no smaller must not be kept")
        } else {
            #expect(fixture.store.notice?.text == fixture.text("nook.tray.convert.notice.alreadySmall"))
        }
    }

    @Test func aResizeThatWouldGiveThePictureBackIsNotStarted() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.add(try fixture.files.png(width: 700, height: 350), named: "wide.png")
        let sameSize = try await fixture.add(try fixture.files.png(width: 640, height: 320), named: "exact.png")

        #expect(fixture.store.convert(item, action: .resize(.longSide(1920))) == nil)
        #expect(fixture.store.convert(item, action: .resize(.longSide(1280))) == nil)
        #expect(fixture.store.convert(sameSize, action: .resize(.longSide(640))) == nil, "640 is the size it already is")
        #expect(Set(fixture.names) == ["wide.png", "exact.png"])
        #expect(fixture.store.jobs.isEmpty)

        // A long side below the picture's own is a real resize.
        await fixture.store.convert(item, action: .resize(.longSide(640)))?.value
        #expect(fixture.names.contains("wide (640 px).png"))
    }
}

// MARK: - The thumbnail fallback

@Suite struct NookTrayThumbnailFallbackTests {
    private func imageSource(_ url: URL) throws -> CGImageSource {
        try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    }

    @Test func noThumbnailWithASizeAskedForThrowsInsteadOfReturningTheFullPicture() throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let source = try imageSource(try fixtures.png(width: 400, height: 200))

        #expect(throws: NookTrayFileActionError.unreadable) {
            try NookTrayFileActions.uprightImage(from: source, maxLongSide: 100) { _, _ in nil }
        }
    }

    @Test func noThumbnailWithNoSizeAskedForStillReturnsThePicture() throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let source = try imageSource(try fixtures.png(width: 400, height: 200))

        let image = try NookTrayFileActions.uprightImage(from: source, maxLongSide: nil) { _, _ in nil }

        #expect(image.width == 400)
    }

    @Test func aThumbnailThatWorksIsTheSizeAskedFor() throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let source = try imageSource(try fixtures.png(width: 400, height: 200))

        let image = try NookTrayFileActions.uprightImage(from: source, maxLongSide: 100)

        #expect(image.width == 100)
        #expect(image.height == 50)
    }
}

// MARK: - T2: errors keep their cause

@Suite struct NookConvertCauseTests {
    private struct LoadFailed: Error {}

    @Test func soundThatFailedToLoadIsUnreadableAndNotSilence() async {
        await #expect(throws: NookTrayFileActionError.unreadable) {
            try await NookConvertJobs.requireSound { throw LoadFailed() }
        }
    }

    @Test func soundTracksThatLoadedEmptyAreNoSound() async {
        await #expect(throws: NookTrayFileActionError.noSound) {
            try await NookConvertJobs.requireSound { 0 }
        }
    }

    @Test func soundTracksThatLoadedPass() async throws {
        try await NookConvertJobs.requireSound { 2 }
    }

    @Test func aCancelledLoadStaysACancel() async {
        await #expect(throws: CancellationError.self) {
            try await NookConvertJobs.requireSound { throw CancellationError() }
        }
    }

    @Test func aVideoThatCannotBeOpenedIsUnreadableEvenWhenItWantsSound() async throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let fake = fixtures.url("fake.mov")
        try Data("not a video".utf8).write(to: fake)

        await #expect(throws: NookTrayFileActionError.unreadable) {
            try await NookConvertJobs.exportVideo(at: fake, to: fixtures.url("fake.m4a"), action: .soundOnly) { _ in }
        }
    }

    @Test func theLogNamesTheDomainAndCodeOfAnError() {
        let error = NSError(domain: "AVFoundationErrorDomain", code: -11800)
        #expect(NookTrayLog.cause(error) == "AVFoundationErrorDomain -11800")
    }

    @Test func theLogNeverCarriesAFilePath() {
        let error = CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "/Users/someone/secret.mov"])
        #expect(!NookTrayLog.cause(error).contains("secret"))
        #expect(NookTrayLog.cause(error) == "NSCocoaErrorDomain 4")
    }
}
