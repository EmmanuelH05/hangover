import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import OpenIslandApp

/// The Convert strip: the room it takes on the page, how it groups what a
/// file can become, that its rows fit the tray card's width in every
/// language, and how it draws. Files come from `NookConvertFixtures` in a
/// temp folder, and nothing leaves it.
@MainActor @Suite(.serialized, .noNewWindows) struct NookTrayConvertStripTests {
    /// The width of a tray card's content, which the GIF render tests use.
    private static let contentWidth: CGFloat = 388

    // MARK: Layout

    @Test func theStripAddsItsHeightToThePage() {
        let closed = NookPageExtras()
        var open = NookPageExtras()
        open.showsConvertOptions = true
        #expect(open.pinnedHeight - closed.pinnedHeight == NookConvertStripLayout.pageHeight)
        #expect(NookConvertStripLayout.pageHeight == NookConvertStripLayout.height + NookWidgetLayout.rowSpacing)
    }

    @Test func theStripAndTheGIFOptionsAddUpWhenBothAreAskedForAlthoughTheStoreNeverDoes() {
        var both = NookPageExtras()
        both.showsConvertOptions = true
        both.showsGIFOptions = true
        #expect(both.pinnedHeight == NookConvertStripLayout.pageHeight + NookGIFStripLayout.pageHeight)
    }

    @Test func theHeightIsTheTitleTheExplainLineAndRoomForTheRowsPlusPadding() {
        let layout = NookConvertStripLayout.self
        #expect(layout.height == layout.verticalPadding * 2 + layout.titleRowHeight + layout.explainHeight
            + layout.headerGap + layout.rowsHeight)
        #expect(layout.contentHeight == layout.height - layout.verticalPadding * 2)
        // Three group rows of one line each always fit.
        let threeRows = CGFloat(layout.maxGroupRows) * layout.buttonHeight
            + CGFloat(layout.maxGroupRows - 1) * layout.groupSpacing
        #expect(layout.rowsHeight >= threeRows)
    }

    // MARK: Groups

    @Test func aPictureGetsAFormatRowAndASizeRow() {
        let actions = NookConvertRules.actions(forFileNamed: "photo.png", pixelLongSide: 4000)
        let groups = NookConvertStripRules.groups(for: actions)
        #expect(groups.map(\.group) == [.format, .size])
        #expect(groups[0].actions.count == 5, "every format but its own")
        #expect(groups[1].actions.count == NookResize.all.count + 1, "every resize and Smaller file")
    }

    @Test func aVideoGetsAllThreeRows() {
        let groups = NookConvertStripRules.groups(for: NookConvertRules.actions(forFileNamed: "clip.mov"))
        #expect(groups.map(\.group) == [.format, .size, .other])
        #expect(groups[2].actions == [.makeGIF, .soundOnly])
    }

    @Test func aPDFGetsOneRowAndAFileWithNothingToConvertGetsNone() {
        #expect(NookConvertStripRules.groups(for: NookConvertRules.actions(forFileNamed: "a.pdf")).map(\.group) == [.format])
        #expect(NookConvertStripRules.groups(for: NookConvertRules.actions(forFileNamed: "notes.txt")).isEmpty)
    }

    @Test func everyActionIsInTheRowOfItsGroupAndNoneIsLost() {
        for name in ["photo.png", "clip.mov", "clip.m4v", "a.pdf"] {
            let actions = NookConvertRules.actions(forFileNamed: name, pixelLongSide: 4000)
            let grouped = NookConvertStripRules.groups(for: actions)
            #expect(grouped.flatMap(\.actions).count == actions.count, "\(name) lost an action")
            for entry in grouped {
                #expect(entry.actions.allSatisfy { $0.group == entry.group })
            }
        }
    }

    // MARK: Titles

    @Test func theStripNamesTheButtonsTheWayTheRightClickMenuDoes() {
        let lang = LanguageManager.shared
        #expect(NookConvertAction.image(.png).menuTitle == lang.t("nook.tray.convert.image.png"))
        #expect(NookConvertAction.smallerImage.menuTitle == lang.t("nook.tray.convert.smallerImage"))
        #expect(NookConvertAction.resize(.half).menuTitle == lang.t("nook.tray.convert.resize.half"))
        #expect(NookConvertAction.resize(.longSide(1920)).menuTitle == lang.t("nook.tray.convert.resize.longSide", 1920))
        #expect(NookConvertAction.resize(.longSide(1920)).menuTitle.contains("1920"))
        for action in NookConvertRules.actions(forFileNamed: "clip.mov") {
            #expect(!action.menuTitle.hasPrefix("nook."), "\(action) has no words")
        }
    }

    // MARK: Fit

    nonisolated private static let languages = ["en", "zh-Hans", "zh-Hant"]

    private static func bundle(_ language: String) throws -> Bundle {
        let path = try #require(
            Bundle.appResources.path(forResource: language, ofType: "lproj")
                ?? Bundle.appResources.path(forResource: language.lowercased(), ofType: "lproj"),
            "no \(language) strings"
        )
        return try #require(Bundle(path: path))
    }

    private func content(
        _ name: String,
        longSide: Int? = nil,
        usesFirstFrame: Bool = false,
        bundle: Bundle = LanguageManager.shared.bundle,
        waitingOn: String? = nil
    ) -> NookConvertStripContent {
        NookConvertStripContent(
            sourceName: name,
            actions: NookConvertRules.actions(forFileNamed: name, pixelLongSide: longSide),
            usesFirstFrame: usesFirstFrame,
            waitingOn: waitingOn,
            bundle: bundle,
            onChoose: { _ in },
            onCancel: {}
        )
    }

    /// The widest real cases: a big picture, with five formats, five resizes
    /// and Smaller file, a picture that is an animated GIF, a video that
    /// keeps its three rows, and a PDF.
    @Test(arguments: languages)
    func theWidestCasesFitTheStripAtTheTrayCardWidth(language: String) throws {
        let bundle = try Self.bundle(language)
        let cases: [(label: String, slug: String, view: NookConvertStripContent)] = [
            ("a big picture", "picture", content("Lecture 5 whiteboard photo.png", longSide: 4000, bundle: bundle)),
            ("a big JPEG", "jpeg", content("IMG_20261015_142233.jpg", longSide: 6000, bundle: bundle)),
            ("an animated GIF", "gif", content("reaction loop.gif", longSide: 800, usesFirstFrame: true, bundle: bundle)),
            ("a video", "video", content("Screen Recording 2026-10-15 at 2.22.33 PM.mov", bundle: bundle)),
            ("an M4V", "m4v", content("trailer.m4v", bundle: bundle)),
            ("a PDF", "pdf", content("Syllabus and reading list.pdf", bundle: bundle)),
        ]
        for entry in cases {
            let height = try NookConvertModeSnapshot.naturalHeight(of: entry.view, width: Self.contentWidth)
            #expect(
                height <= NookConvertStripLayout.contentHeight,
                "\(language): \(entry.label) needs \(height) points, the strip gives \(NookConvertStripLayout.contentHeight)"
            )
            // Drawn in exactly the room the strip gives, so a row that was
            // cut off would show in the picture.
            let drawn = entry.view
                .frame(width: Self.contentWidth, height: NookConvertStripLayout.contentHeight, alignment: .topLeading)
                .padding(NookConvertStripLayout.horizontalPadding)
            _ = try NookConvertModeSnapshot.render("tray-convert-strip-fit-\(language)-\(entry.slug)", drawn)
        }
    }

    @Test func aRowWrapsInsteadOfRunningOffTheEdgeAtTheTrayCardWidth() throws {
        // Longest side 1920 px and its two neighbours cannot share one line
        // with the other resizes in a card this narrow.
        let picture = content("photo.png", longSide: 4000)
        let height = try NookConvertModeSnapshot.naturalHeight(of: picture, width: Self.contentWidth)
        let oneLinePerRow = NookConvertStripLayout.titleRowHeight + NookConvertStripLayout.explainHeight
            + NookConvertStripLayout.headerGap + NookConvertStripLayout.buttonHeight * 2 + NookConvertStripLayout.groupSpacing
        #expect(height > oneLinePerRow, "the size row should have wrapped onto a second line")
    }

    // MARK: Drawing

    private func strip(_ store: NookTrayStore, _ item: NookTrayItem) -> some View {
        NookConvertStrip(tray: store, source: item)
            .frame(width: Self.contentWidth + NookConvertStripLayout.horizontalPadding * 2, height: NookConvertStripLayout.height)
            .padding(8)
    }

    private func animatedGIF(in files: NookConvertFixtures) throws -> URL {
        let file = files.url("\(UUID().uuidString).gif")
        let destination = try #require(CGImageDestinationCreateWithURL(file as CFURL, UTType.gif.identifier as CFString, 2, nil))
        for shade in [0.2, 0.8] {
            let context = try #require(CGContext(
                data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.setFillColor(CGColor(red: shade, green: 0.4, blue: 0.6, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        }
        #expect(CGImageDestinationFinalize(destination))
        return file
    }

    @Test func theStripDrawsForAPictureAVideoAndAPDF() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let picture = try await fixture.add(try fixture.files.png(width: 2000, height: 1000), named: "Lecture 5 whiteboard.png")
        let video = try await fixture.add(try fixture.files.movie(seconds: 1), named: "Screen Recording.mov")
        let pdf = try await fixture.add(try fixture.files.pdf(pages: 2), named: "Syllabus.pdf")

        let picturePNG = try NookConvertModeSnapshot.render("tray-convert-strip-picture", strip(fixture.store, picture))
        let videoPNG = try NookConvertModeSnapshot.render("tray-convert-strip-video", strip(fixture.store, video))
        let pdfPNG = try NookConvertModeSnapshot.render("tray-convert-strip-pdf", strip(fixture.store, pdf))

        #expect(picturePNG != videoPNG)
        #expect(videoPNG != pdfPNG)
        #expect(picturePNG != pdfPNG)
    }

    @Test func anAnimatedGIFSaysItUsesTheFirstFrame() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let animated = try await fixture.add(try animatedGIF(in: fixture.files), named: "loop.gif")
        let still = try await fixture.add(try fixture.files.png(width: 8, height: 8), named: "loop.png")

        _ = try NookConvertModeSnapshot.render("tray-convert-strip-animated-gif", strip(fixture.store, animated))
        _ = try NookConvertModeSnapshot.render("tray-convert-strip-still", strip(fixture.store, still))
        // The same name and the same buttons: only the note can tell them apart.
        let withNote = try NookConvertModeSnapshot.render(
            "tray-convert-strip-note-on", content("loop.gif", usesFirstFrame: true).frame(width: 388).padding(14)
        )
        let without = try NookConvertModeSnapshot.render(
            "tray-convert-strip-note-off", content("loop.gif", usesFirstFrame: false).frame(width: 388).padding(14)
        )

        #expect(NookConvertRules.isAnimatedGIF(at: fixture.store.storedURL(for: animated)))
        #expect(!NookConvertRules.isAnimatedGIF(at: fixture.store.storedURL(for: still)))
        #expect(withNote != without, "the strip says only the first frame is converted")
    }

    @Test func aFileBeingConvertedDimsTheButtonsAndTheStripStaysUp() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let pdf = try await fixture.add(try fixture.files.pdf(pages: 1), named: "Syllabus.pdf")
        fixture.store.beginPickingToConvert()
        fixture.store.pickToConvert(pdf)
        let idle = try NookConvertModeSnapshot.render("tray-convert-strip-idle", strip(fixture.store, pdf))

        let running = fixture.store.convert(pdf, action: .pdfPages(.png))
        let busy = try NookConvertModeSnapshot.render("tray-convert-strip-busy", strip(fixture.store, pdf))
        await running?.value

        #expect(idle != busy, "the buttons should go dim while the file is being converted")
        #expect(fixture.store.convertSourceItem == pdf)
    }
}
