import Foundation
import ImageIO
import Testing
@testable import OpenIslandApp

@Suite struct NookConvertRulesTests {
    @Test func aPictureIsOfferedEveryOtherFormat() {
        let actions = NookConvertRules.actions(forFileNamed: "photo.PNG")
        #expect(!actions.contains(.image(.png)))
        for target in [NookImageTarget.jpeg, .heic, .tiff, .gif, .bmp] {
            #expect(actions.contains(.image(target)))
        }
        #expect(actions.contains(.resize(.half)))
        #expect(actions.contains(.resize(.longSide(1280))))
        #expect(actions.contains(.smallerImage))
    }

    @Test func jpgAndJpegAreTheSameFormat() {
        #expect(!NookConvertRules.actions(forFileNamed: "a.jpeg").contains(.image(.jpeg)))
        #expect(!NookConvertRules.actions(forFileNamed: "a.jpg").contains(.image(.jpeg)))
        #expect(!NookConvertRules.actions(forFileNamed: "a.HEIF").contains(.image(.heic)))
        #expect(!NookConvertRules.actions(forFileNamed: "a.tif").contains(.image(.tiff)))
    }

    @Test func aVideoGetsContainerSizeGIFAndSound() {
        let actions = NookConvertRules.actions(forFileNamed: "clip.mov")
        #expect(actions == [.video(.mp4), .smallerVideo(.p1080), .smallerVideo(.p720), .makeGIF, .soundOnly])
        #expect(NookConvertRules.actions(forFileNamed: "clip.mp4").first == .video(.mov))
        #expect(NookConvertRules.actions(forFileNamed: "clip.m4v").prefix(2) == [.video(.mp4), .video(.mov)])
    }

    @Test func aPDFGetsPagesOut() {
        #expect(NookConvertRules.actions(forFileNamed: "notes.pdf") == [.pdfPages(.png), .pdfPages(.jpeg)])
    }

    @Test func anythingElseGetsNothing() {
        #expect(NookConvertRules.actions(forFileNamed: "song.mp3").isEmpty)
        #expect(NookConvertRules.actions(forFileNamed: "README").isEmpty)
        #expect(NookConvertRules.actions(forFileNamed: ".png").isEmpty)
        #expect(NookConvertRules.actions(forFileNamed: "archive.zip").isEmpty)
        #expect(NookConvertRules.actions(forFileNamed: "").isEmpty)
    }

    @Test func resultNames() {
        #expect(NookConvertRules.resultName(for: "photo.heic", action: .image(.png), taken: []) == "photo.png")
        #expect(NookConvertRules.resultName(for: "photo.heic", action: .resize(.half), taken: []) == "photo (50%).heic")
        #expect(NookConvertRules.resultName(for: "photo.png", action: .resize(.longSide(640)), taken: []) == "photo (640 px).png")
        #expect(NookConvertRules.resultName(for: "photo.png", action: .smallerImage, taken: []) == "photo (smaller).jpg")
        #expect(NookConvertRules.resultName(for: "clip.mov", action: .smallerVideo(.p720), taken: []) == "clip (720p).mp4")
        #expect(NookConvertRules.resultName(for: "clip.mov", action: .makeGIF, taken: []) == "clip.gif")
        #expect(NookConvertRules.resultName(for: "clip.mov", action: .soundOnly, taken: []) == "clip.m4a")
        #expect(NookConvertRules.resultName(for: "notes.pdf", action: .pdfPages(.png), taken: []) == "notes pages")
    }

    @Test func aTakenResultNameGetsANumber() {
        #expect(NookConvertRules.resultName(for: "clip.mov", action: .makeGIF, taken: ["clip.gif", "clip 2.gif"]) == "clip 3.gif")
    }

    @Test func aFolderNameWithADotIsNumberedWhole() {
        // "v1.2 notes pages" has no extension, so the number goes on the end.
        let taken: Set<String> = ["v1.2 notes pages"]
        #expect(NookConvertRules.resultName(for: "v1.2 notes.pdf", action: .pdfPages(.png), taken: taken) == "v1.2 notes pages 2")
    }

    @Test func combineNeedsTwoOfOneKind() {
        #expect(NookConvertRules.combineActions(forFilesNamed: ["a.png", "b.jpg"]) == [.picturesToPDF])
        #expect(NookConvertRules.combineActions(forFilesNamed: ["a.pdf", "b.PDF"]) == [.joinPDFs])
        #expect(NookConvertRules.combineActions(forFilesNamed: ["a.pdf", "b.png"]).isEmpty)
        #expect(NookConvertRules.combineActions(forFilesNamed: ["a.pdf"]).isEmpty)
        #expect(NookConvertRules.combineActions(forFilesNamed: []).isEmpty)
    }

    @Test func combinedNamesAreNumberedWhenTaken() {
        #expect(NookConvertRules.combinedName(for: .picturesToPDF, taken: []) == "Pictures.pdf")
        #expect(NookConvertRules.combinedName(for: .joinPDFs, taken: ["Joined.pdf"]) == "Joined 2.pdf")
    }

    @Test func onlyVideoWorkWaitsItsTurn() {
        for action in NookConvertRules.actions(forFileNamed: "a.mov") {
            #expect(action.isQueued)
        }
        for name in ["a.png", "a.pdf"] {
            for action in NookConvertRules.actions(forFileNamed: name) {
                #expect(action.isQueued == false)
            }
        }
    }

    @Test func eachActionSitsInOneMenuGroup() {
        #expect(NookConvertAction.image(.jpeg).group == .format)
        #expect(NookConvertAction.video(.mov).group == .format)
        #expect(NookConvertAction.pdfPages(.png).group == .format)
        #expect(NookConvertAction.resize(.half).group == .size)
        #expect(NookConvertAction.smallerImage.group == .size)
        #expect(NookConvertAction.smallerVideo(.p720).group == .size)
        #expect(NookConvertAction.makeGIF.group == .other)
        #expect(NookConvertAction.soundOnly.group == .other)
    }

    @Test func onlyALongestSideTitleTakesANumber() {
        #expect(NookConvertAction.resize(.longSide(1280)).titleArgument == 1280)
        #expect(NookConvertAction.resize(.half).titleArgument == nil)
        #expect(NookConvertAction.image(.png).titleArgument == nil)
    }

    @Test func everyFailureHasASentenceOfItsOwnKind() {
        #expect(NookConvertRules.noticeKey(for: NookTrayFileActionError.writeFailed, action: .image(.png)) == "nook.tray.notice.convertFailed")
        #expect(NookConvertRules.noticeKey(for: NookTrayFileActionError.unreadable, action: .smallerVideo(.p720)) == "nook.tray.convert.notice.videoFailed")
        #expect(NookConvertRules.noticeKey(for: NookTrayFileActionError.unreadable, action: .pdfPages(.png)) == "nook.tray.convert.notice.pdfFailed")
        #expect(NookConvertRules.noticeKey(for: NookGIFError.writeFailed, action: .makeGIF) == "nook.tray.convert.notice.gifFailed")
        // The ones with a sentence of their own.
        #expect(NookConvertRules.noticeKey(for: NookGIFError.tooLong, action: .makeGIF) == "nook.tray.convert.notice.gifTooLong")
        #expect(NookConvertRules.noticeKey(for: NookTrayFileActionError.noSound, action: .soundOnly) == "nook.tray.convert.notice.noSound")
        // Too large is a picture over the pixel limit, or a PDF over the page limit.
        #expect(NookConvertRules.noticeKey(for: NookTrayFileActionError.tooLarge, action: .image(.jpeg)) == "nook.tray.notice.convertTooLarge")
        #expect(NookConvertRules.noticeKey(for: NookTrayFileActionError.tooLarge, action: .pdfPages(.png)) == "nook.tray.convert.notice.tooManyPages")
        #expect(NookConvertRules.noticeKey(forCombineFailure: NookTrayFileActionError.tooLarge) == "nook.tray.notice.convertTooLarge")
        #expect(NookConvertRules.noticeKey(forCombineFailure: NookTrayFileActionError.unreadable) == "nook.tray.convert.notice.combineFailed")
    }

    @Test func aGIFWithOneFrameIsNotAnimated() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NookConvertRulesTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = try NookConvertFixtureImage.make(width: 8, height: 8)

        let still = folder.appendingPathComponent("still.gif")
        let moving = folder.appendingPathComponent("moving.gif")
        try NookConvertFixtureImage.writeGIF([image], to: still)
        try NookConvertFixtureImage.writeGIF([image, image, image], to: moving)

        #expect(!NookConvertRules.isAnimatedGIF(at: still))
        #expect(NookConvertRules.isAnimatedGIF(at: moving))
        // Not a GIF by name, and not a file at all.
        #expect(!NookConvertRules.isAnimatedGIF(at: folder.appendingPathComponent("moving.png")))
        #expect(!NookConvertRules.isAnimatedGIF(at: folder.appendingPathComponent("gone.gif")))
    }
}

/// A picture and a GIF made in memory, for the tests that need a file.
enum NookConvertFixtureImage {
    static func make(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        return try #require(context.makeImage())
    }

    static func writeGIF(_ frames: [CGImage], to url: URL) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "com.compuserve.gif" as CFString, frames.count, nil))
        for frame in frames { CGImageDestinationAddImage(destination, frame, nil) }
        #expect(CGImageDestinationFinalize(destination))
    }
}

/// The notices name two limits in their words. The words are strings and the
/// limits are numbers, which could drift apart.
@Suite struct NookConvertNoticeLimitsTests {
    private static func table(_ language: String) throws -> [String: String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
        return try #require(NSDictionary(contentsOf: url) as? [String: String], "\(language) did not load")
    }

    @Test(arguments: ["en", "zh-Hans", "zh-Hant"])
    func theNoticesNameTheRealLimits(language: String) throws {
        let table = try Self.table(language)
        let pages = "\(NookConvertRules.maxPDFPages)"
        let minutes = "\(Int(NookGIFMaker.maxDuration / 60))"

        #expect(table["nook.tray.convert.notice.tooManyPages"]?.contains(pages) == true)
        #expect(table["nook.tray.convert.notice.gifTooLong"]?.contains(minutes) == true)
    }
}
