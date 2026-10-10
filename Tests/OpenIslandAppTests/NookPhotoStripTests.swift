import CoreGraphics
import CoreText
import Foundation
import PDFKit
import Testing
@testable import OpenIslandApp

/// The picture work, the strip drawing and the file naming, on pictures
/// drawn in code.
@Suite(.serialized, .oneStripAtATime)
struct NookPhotoStripTests {
    private static let date = Date(timeIntervalSince1970: 1_791_600_420)
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private static func solid(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, width: Int = 320, height: Int = 180) -> CGImage {
        let context = NookPhotoBoothImaging.bitmapContext(width: width, height: height)!
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private static func isClose(_ pixel: (red: Int, green: Int, blue: Int), _ red: Int, _ green: Int, _ blue: Int, within: Int = 12) -> Bool {
        abs(pixel.red - red) <= within && abs(pixel.green - green) <= within && abs(pixel.blue - blue) <= within
    }

    // MARK: Cutting and flipping

    @Test func cropKeepsTheMiddleAtTheSlotsShape() {
        let cases: [(width: Int, height: Int, aspect: CGFloat, expected: CGRect)] = [
            // Sixteen to nine down to three to two trims the sides.
            (1280, 720, 1.5, CGRect(x: 100, y: 0, width: 1080, height: 720)),
            // The camera's own shape keeps everything.
            (1280, 720, 16.0 / 9.0, CGRect(x: 0, y: 0, width: 1280, height: 720)),
            // A four to three camera into a wide slot trims top and bottom.
            (640, 480, 16.0 / 9.0, CGRect(x: 0, y: 60, width: 640, height: 360)),
            (1920, 1080, 1, CGRect(x: 420, y: 0, width: 1080, height: 1080)),
        ]
        for item in cases {
            let rect = NookPhotoBoothImaging.cropRect(imageWidth: item.width, imageHeight: item.height, aspect: item.aspect)
            #expect(rect == item.expected, "\(item.width)x\(item.height) at \(item.aspect)")
        }
        #expect(NookPhotoBoothImaging.cropRect(imageWidth: 0, imageHeight: 10, aspect: 1) == .zero)
        #expect(NookPhotoBoothImaging.cropRect(imageWidth: 10, imageHeight: 10, aspect: 0) == .zero)
        #expect(NookPhotoBoothImaging.cropRect(imageWidth: 10, imageHeight: 10, aspect: .infinity) == .zero)
    }

    @Test func aPreparedPictureIsFlippedLikeTheMirrorAndStaysUpright() throws {
        let camera = PhotoBoothTestPictures.lopsided()
        // As the camera gave it: red at the left, green band on top.
        #expect(Self.isClose(PhotoBoothTestPictures.pixel(camera, x: 100, y: 400), 255, 0, 0))
        #expect(Self.isClose(PhotoBoothTestPictures.pixel(camera, x: 100, y: 20), 0, 255, 0))

        let ready = try #require(NookPhotoBoothImaging.prepared(camera, aspect: 1.5))
        let width = 1080
        let height = 720
        #expect(ready.width == width)
        #expect(ready.height == height)
        // Flipped: blue is now at the left and red at the right.
        #expect(Self.isClose(PhotoBoothTestPictures.pixel(ready, x: 100, y: 400), 0, 0, 255))
        #expect(Self.isClose(PhotoBoothTestPictures.pixel(ready, x: 980, y: 400), 255, 0, 0))
        // Not turned over: the green band is still on top.
        #expect(Self.isClose(PhotoBoothTestPictures.pixel(ready, x: 540, y: 20), 0, 255, 0))
        #expect(!Self.isClose(PhotoBoothTestPictures.pixel(ready, x: 540, y: 700), 0, 255, 0))
    }

    @Test func aPreparedPictureIsNoWiderThanAPrintNeeds() throws {
        let big = PhotoBoothTestPictures.lopsided(width: 3840, height: 2160)
        let ready = try #require(NookPhotoBoothImaging.prepared(big, aspect: 16.0 / 9.0))
        #expect(ready.width == NookPhotoBoothImaging.maxPictureWidth)
        let height = 788
        #expect(abs(ready.height - height) <= 1)
        let small = try #require(NookPhotoBoothImaging.prepared(PhotoBoothTestPictures.lopsided(width: 640, height: 360), aspect: 16.0 / 9.0))
        let smallWidth = 640
        #expect(small.width == smallWidth)
    }

    // MARK: Decorations on a cut picture

    @Test func stickersStayOnTheSameSpotOfTheCameraPicture() {
        let kept = NookPhotoBoothImaging.keptFractions(imageWidth: 1280, imageHeight: 720, aspect: 1.5)
        #expect(abs(kept.x.lowerBound - 0.078125) < 0.0001)
        #expect(abs(kept.x.upperBound - 0.921875) < 0.0001)
        #expect(kept.y == 0...1)

        let middle = NookMirrorSticker(designID: "a", x: 0.5, y: 0.25, width: 0.2, rotation: 15)
        let nearEdge = NookMirrorSticker(designID: "b", x: 0.1, y: 0.9, width: 0.1)
        let cutOff = NookMirrorSticker(designID: "c", x: 0.03, y: 0.5, width: 0.1)
        let set = NookMirrorDecorationSet(frameID: "frame", stickers: [middle, nearEdge, cutOff])

        let moved = NookPhotoBoothImaging.decorations(set, keptX: kept.x, keptY: kept.y)

        #expect(moved.frameID == "frame")
        #expect(moved.stickers.map(\.designID) == ["a", "b"])
        let first = moved.stickers[0]
        #expect(abs(first.x - 0.5) < 0.0001)
        #expect(abs(first.y - 0.25) < 0.0001)
        // The same real size is a larger share of a narrower picture.
        #expect(abs(first.width - 0.2 / 0.84375) < 0.0001)
        let quarterTurn: Double = 15
        #expect(first.rotation == quarterTurn)
        #expect(first.id == middle.id)
        #expect(abs(moved.stickers[1].x - (0.1 - 0.078125) / 0.84375) < 0.0001)

        // A picture kept whole moves nothing.
        #expect(NookPhotoBoothImaging.decorations(set, keptX: 0...1, keptY: 0...1) == set)
    }

    @MainActor
    @Test func aMirrorWithNoDecorationsAddsNothingToAPicture() {
        #expect(NookPhotoBoothImaging.decorationImage(.none, pixelWidth: 600, pixelHeight: 400) == nil)
    }

    // MARK: Developing

    @Test func treatmentsChangeThePictureTheWayTheySay() throws {
        let orange = Self.solid(1, 0.5, 0)
        let untouched = try #require(NookPhotoBoothImaging.treated(orange, .color))
        #expect(Self.isClose(PhotoBoothTestPictures.pixel(untouched, x: 10, y: 10), 255, 128, 0))

        let gray = try #require(NookPhotoBoothImaging.treated(orange, .adjusted(saturation: 0, contrast: 1, brightness: 0, wash: nil)))
        let pixel = PhotoBoothTestPictures.pixel(gray, x: 10, y: 10)
        #expect(abs(pixel.red - pixel.green) <= 6 && abs(pixel.green - pixel.blue) <= 6)

        let ink = try #require(NookPhotoBoothImaging.treated(
            Self.solid(1, 1, 1),
            .duotone(dark: NookStripColor(0x06140B), light: NookStripColor(0x9DFFB8), contrast: 1)
        ))
        let lit = PhotoBoothTestPictures.pixel(ink, x: 10, y: 10)
        // White prints as the light ink: green well above red.
        #expect(lit.green > lit.red + 40)
        #expect(ink.width == orange.width)
        #expect(ink.height == orange.height)
    }

    // MARK: The strip

    private static func input(
        _ kind: NookPhotoStripLayout.Kind,
        themeID: String = "paperWhite",
        pictures: [CGImage]? = nil,
        caption: String = "Hello"
    ) -> NookPhotoStripInput {
        let layout = NookPhotoStripLayout.layout(kind)
        let colors: [(CGFloat, CGFloat, CGFloat)] = [(1, 0, 0), (0, 0.6, 0), (0, 0, 1), (1, 0, 1)]
        let cameras = pictures ?? colors.prefix(layout.shots).map { Self.solid($0.0, $0.1, $0.2) }
        return NookPhotoStripInput(
            pictures: cameras.enumerated().map { index, camera in
                NookPhotoBoothPicture(
                    camera: NookPhotoBoothImaging.prepared(camera, aspect: layout.aspect(ofSlot: index))!,
                    decorations: nil
                )
            },
            layout: layout,
            theme: NookPhotoStripTheme.theme(id: themeID),
            caption: caption,
            date: date,
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )
    }

    @Test func everySlotHoldsItsOwnPictureInOrder() throws {
        let scale = 2
        let expected = [(255, 0, 0), (0, 153, 0), (0, 0, 255), (255, 0, 255)]
        for kind in NookPhotoStripLayout.Kind.allCases {
            let input = Self.input(kind)
            let strip = try #require(NookPhotoStripComposer.bitmap(input, scale: CGFloat(scale)))
            #expect(strip.width == Int(input.layout.pageSize.width) * scale, "\(kind)")
            #expect(strip.height == Int(input.layout.pageSize.height) * scale, "\(kind)")
            for (index, slot) in input.layout.slots.enumerated() {
                let pixel = PhotoBoothTestPictures.pixel(strip, x: Int(slot.midX) * scale, y: Int(slot.midY) * scale)
                let want = expected[index]
                #expect(Self.isClose(pixel, want.0, want.1, want.2), "\(kind) slot \(index + 1) is \(pixel)")
            }
            // The margin is paper, not picture.
            let corner = PhotoBoothTestPictures.pixel(strip, x: 3, y: 3)
            #expect(Self.isClose(corner, 250, 250, 247), "\(kind) corner is \(corner)")
        }
    }

    @Test func theSavedPDFShowsThePicturesToo() throws {
        let input = Self.input(.classic)
        let data = try #require(NookPhotoStripComposer.pdf(input))
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        let one = 1
        #expect(document.numberOfPages == one)
        let page = try #require(document.page(at: 1))
        let box = page.getBoxRect(.mediaBox)
        #expect(box.size == input.layout.pageSize)

        let scale = 2
        let context = try #require(NookPhotoBoothImaging.bitmapContext(width: Int(box.width) * scale, height: Int(box.height) * scale))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        context.drawPDFPage(page)
        let drawn = try #require(context.makeImage())
        let first = input.layout.slots[0]
        let last = input.layout.slots[3]
        #expect(Self.isClose(PhotoBoothTestPictures.pixel(drawn, x: Int(first.midX) * scale, y: Int(first.midY) * scale), 255, 0, 0, within: 20))
        #expect(Self.isClose(PhotoBoothTestPictures.pixel(drawn, x: Int(last.midX) * scale, y: Int(last.midY) * scale), 255, 0, 255, within: 20))
        // Four pictures as JPEG: a strip is a small file.
        let limit = 1_500_000
        #expect(data.count < limit)
    }

    @Test func theStripShowsThePictureAsTheMirrorDid() throws {
        let cameras = Array(repeating: PhotoBoothTestPictures.lopsided(), count: 4)
        let scale = 2
        for kind in NookPhotoStripLayout.Kind.allCases {
            let input = Self.input(kind, pictures: cameras)
            let strip = try #require(NookPhotoStripComposer.bitmap(input, scale: CGFloat(scale)))
            let slot = input.layout.slots[0]
            let y = Int(slot.minY + slot.height * 0.6) * scale
            let left = PhotoBoothTestPictures.pixel(strip, x: Int(slot.minX + slot.width * 0.2) * scale, y: y)
            let right = PhotoBoothTestPictures.pixel(strip, x: Int(slot.minX + slot.width * 0.8) * scale, y: y)
            #expect(Self.isClose(left, 0, 0, 255), "\(kind): left is \(left)")
            #expect(Self.isClose(right, 255, 0, 0), "\(kind): right is \(right)")
            // The camera's top is the slot's top.
            let top = PhotoBoothTestPictures.pixel(strip, x: Int(slot.midX) * scale, y: Int(slot.minY + slot.height * 0.06) * scale)
            #expect(Self.isClose(top, 0, 255, 0), "\(kind): top is \(top)")
        }
    }

    @Test func aStripWithTooFewPicturesStillPrints() throws {
        var input = Self.input(.classic)
        input.pictures = Array(input.pictures.prefix(1))
        #expect(NookPhotoStripComposer.pdf(input) != nil)
    }

    @Test func theSameInputPrintsTheSameStrip() throws {
        // Scattered patterns are seeded, never random.
        let first = try #require(NookPhotoStripComposer.bitmap(Self.input(.classic, themeID: "confetti"), scale: 1))
        let second = try #require(NookPhotoStripComposer.bitmap(Self.input(.classic, themeID: "confetti"), scale: 1))
        #expect(NookPhotoBoothImaging.pngData(first) == NookPhotoBoothImaging.pngData(second))
    }

    // MARK: The name on every strip

    @Test func everyThemeAndLayoutPrintsTheAppNameInsideTheStripClearOfThePhotos() {
        for kind in NookPhotoStripLayout.Kind.allCases {
            let layout = NookPhotoStripLayout.layout(kind)
            let page = CGRect(origin: .zero, size: layout.pageSize)
            for theme in NookPhotoStripTheme.all {
                let mark = NookPhotoStripComposer.wordmark(layout: layout, theme: theme)
                let label = "\(kind) \(theme.id)"
                #expect(mark.text == AppBrand.name, "\(label)")
                #expect(page.contains(mark.rect), "\(label)")
                #expect(!mark.rect.intersects(layout.footer), "\(label)")
                for slot in layout.slots {
                    #expect(!mark.rect.intersects(slot), "\(label)")
                }
                if let plate = mark.plate {
                    #expect(mark.rect.contains(plate), "\(label)")
                }
            }
        }
    }

    @Test func theNameKeepsEightPointsOfPaperUnderItOnEveryLayout() {
        for kind in NookPhotoStripLayout.Kind.allCases {
            let layout = NookPhotoStripLayout.layout(kind)
            let mark = NookPhotoStripComposer.wordmark(layout: layout, theme: NookPhotoStripTheme.theme(id: "classic"))
            #expect(layout.pageSize.height - mark.rect.maxY >= NookPhotoStripLayout.wordmarkMargin, "\(kind)")
            #expect(mark.rect.minX >= NookPhotoStripLayout.wordmarkMargin, "\(kind)")
        }
    }

    @Test func theNamesInkReadsOnTheGroundUnderItOnEveryThemeAndLayout() {
        var lowest = Double.infinity
        for kind in NookPhotoStripLayout.Kind.allCases {
            let layout = NookPhotoStripLayout.layout(kind)
            for theme in NookPhotoStripTheme.all {
                let mark = NookPhotoStripComposer.wordmark(layout: layout, theme: theme)
                #expect(!mark.grounds.isEmpty, "\(kind) \(theme.id)")
                for ground in mark.grounds {
                    let ratio = NookStripColor.contrast(mark.color, ground)
                    lowest = min(lowest, ratio)
                    #expect(ratio >= NookPhotoStripComposer.wordmarkContrast, "\(kind) \(theme.id) \(ratio)")
                }
            }
        }
        #expect(lowest >= NookPhotoStripComposer.wordmarkContrast)
    }

    @Test func contrastFollowsTheWCAGFormula() {
        #expect(abs(NookStripColor.contrast(.black, .white) - 21) < 0.001)
        #expect(abs(NookStripColor.contrast(.white, .black) - 21) < 0.001)
        #expect(abs(NookStripColor.contrast(.white, .white) - 1) < 0.001)
        // Mid gray 777777 on white is the textbook 4.48.
        #expect(abs(NookStripColor.contrast(NookStripColor(0x777777), .white) - 4.48) < 0.01)
        // The old gingham ink on its paper was the failing case.
        #expect(NookStripColor.contrast(NookStripColor(0xFF4D8B), NookStripColor(0xFFE3F0)) < 4.5)
    }

    @Test func aWeakInkIsTakenDarkerOrLighterUntilItReads() {
        let pink = NookStripColor(0xFF4D8B)
        let paper = NookStripColor(0xFFE3F0)
        let ink = NookPhotoStripComposer.readableInk(from: [pink], on: [paper])
        #expect(NookStripColor.contrast(ink, paper) >= 4.5)
        // An ink that already reads is left alone.
        #expect(NookPhotoStripComposer.readableInk(from: [.black], on: [paper]) == .black)
        // The second of the theme's own inks is used before any is bent.
        #expect(NookPhotoStripComposer.readableInk(from: [pink, .black], on: [paper]) == .black)
    }

    @Test func theNamesFaceAndSizeAreTheSameOnEveryTheme() {
        #expect(NookPhotoStripComposer.wordmarkSize >= 7)
        #expect(NookPhotoStripComposer.wordmarkFont.name == "HelveticaNeue-Medium")
    }

    @Test func noPatternIsDrawnUnderTheName() throws {
        let scale = 2
        for kind in NookPhotoStripLayout.Kind.allCases {
            for theme in NookPhotoStripTheme.all {
                var bare = Self.input(kind, themeID: theme.id)
                bare.theme.patterns = theme.patterns.filter { if case .vignette = $0 { true } else { false } }
                let full = Self.input(kind, themeID: theme.id)
                let band = NookPhotoStripComposer.wordmark(layout: full.layout, theme: theme).clear
                let withPattern = try #require(NookPhotoStripComposer.bitmap(full, scale: CGFloat(scale)))
                let without = try #require(NookPhotoStripComposer.bitmap(bare, scale: CGFloat(scale)))
                // Every pixel of the clear rectangle is the same with and without the pattern.
                for y in Int((band.minY * CGFloat(scale)).rounded(.up))..<Int((band.maxY * CGFloat(scale)).rounded(.down)) {
                    for x in Int((band.minX * CGFloat(scale)).rounded(.up))..<Int((band.maxX * CGFloat(scale)).rounded(.down)) {
                        let a = PhotoBoothTestPictures.pixel(withPattern, x: x, y: y)
                        let b = PhotoBoothTestPictures.pixel(without, x: x, y: y)
                        if a != b {
                            Issue.record("\(kind) \(theme.id) differs at \(x),\(y)")
                            return
                        }
                    }
                }
            }
        }
    }

    @Test func theGridFooterHasItsFullHeightAndTheCaptionsKeepTheirSize() {
        let grid = NookPhotoStripLayout.layout(.grid)
        let twentyThree: CGFloat = 23
        #expect(grid.footer.height == twentyThree)
        // The one line the caption is set on is the footer less two points
        // above and below. A theme's caption fits it at the size it asks for.
        for id in ["ribbon", "chrome"] {
            let footer = NookPhotoStripTheme.theme(id: id).footer
            let size = footer.captionSize * grid.captionScale
            let font = footer.captionFont.font(size: size)
            let lineHeight = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
            #expect(lineHeight <= grid.footer.height - 4, "\(id) \(lineHeight)")
            #expect(abs(size - 13.5) < 0.001, "\(id)")
        }
    }

    @Test func theSavedPDFCarriesTheAppNameAsTextOnEveryLayout() throws {
        for kind in NookPhotoStripLayout.Kind.allCases {
            let data = try #require(NookPhotoStripComposer.pdf(Self.input(kind, caption: "")))
            // Letter spacing makes the text reader put a space between letters.
            let text = try #require(PDFDocument(data: data)?.string).filter { !$0.isWhitespace }
            #expect(text.contains(AppBrand.name), "\(kind)")
        }
    }

    @Test func aCaptionIsOneTrimmedLineOfLimitedLength() {
        let plain = NookPhotoStripTheme.theme(id: "notebook")
        #expect(NookPhotoStripComposer.printedCaption("  two\nlines  ", theme: plain) == "two lines")
        #expect(NookPhotoStripComposer.printedCaption("   ", theme: plain).isEmpty)
        let long = String(repeating: "a", count: 200)
        #expect(NookPhotoStripComposer.printedCaption(long, theme: plain).count == NookPhotoStripComposer.maxCaptionLength)
        #expect(NookPhotoStripComposer.printedCaption("Loud", theme: NookPhotoStripTheme.theme(id: "classic")) == "LOUD")
        #expect(NookPhotoStripComposer.printedCaption("Quiet", theme: NookPhotoStripTheme.theme(id: "paperWhite")) == "quiet")
    }

    @Test func aPictureCoversItsSlotWithoutStretching() {
        let wide = Self.solid(1, 1, 1, width: 400, height: 100)
        let rect = NookPhotoStripComposer.fillRect(for: wide, covering: CGRect(x: 10, y: 20, width: 100, height: 100))
        #expect(rect == CGRect(x: -140, y: 20, width: 400, height: 100))
    }

    // MARK: The tables

    @Test func layoutsAreTheRealPrintSizesWithEverythingOnThePage() {
        let sizes: [NookPhotoStripLayout.Kind: CGSize] = [
            .classic: CGSize(width: 144, height: 432),
            .grid: CGSize(width: 432, height: 288),
            .caption: CGSize(width: 144, height: 432),
        ]
        let aspects: [NookPhotoStripLayout.Kind: CGFloat] = [.classic: 1.5, .grid: 16.0 / 9.0, .caption: 16.0 / 9.0]
        let four = 4
        for kind in NookPhotoStripLayout.Kind.allCases {
            let layout = NookPhotoStripLayout.layout(kind)
            let page = CGRect(origin: .zero, size: layout.pageSize)
            #expect(layout.pageSize == sizes[kind], "\(kind)")
            #expect(layout.shots == four, "\(kind)")
            #expect(page.contains(layout.footer), "\(kind)")
            #expect(layout.footer.contains(layout.captionBox), "\(kind)")
            #expect(layout.footer.contains(layout.dateBox), "\(kind)")
            for (index, slot) in layout.slots.enumerated() {
                #expect(page.insetBy(dx: 7.9, dy: 7.9).contains(slot), "\(kind) slot \(index)")
                #expect(!slot.intersects(layout.footer), "\(kind) slot \(index)")
                #expect(abs(layout.aspect(ofSlot: index) - aspects[kind]!) < 0.001, "\(kind) slot \(index)")
                for other in layout.slots.dropFirst(index + 1) {
                    #expect(!slot.intersects(other), "\(kind) slot \(index)")
                }
            }
        }
        #expect(Set(NookPhotoStripLayout.Kind.allCases.map(\.rawValue)).count == NookPhotoStripLayout.Kind.allCases.count)
    }

    @Test func thereAreAtLeastTenThemesWithIdsOfTheirOwn() {
        let themes = NookPhotoStripTheme.all
        let ten = 10
        #expect(themes.count >= ten)
        #expect(Set(themes.map(\.id)).count == themes.count)
        #expect(themes.contains { $0.id == NookPhotoStripTheme.defaultID })
        #expect(NookPhotoStripTheme.theme(id: "no such theme").id == themes[0].id)
        // More than one way of developing a picture is on offer.
        #expect(themes.contains { $0.treatment.isUntouched })
        #expect(themes.contains { if case .sepia = $0.treatment { true } else { false } })
        #expect(themes.contains { if case .duotone = $0.treatment { true } else { false } })
        #expect(themes.contains { if case .adjusted(0, _, _, _) = $0.treatment { true } else { false } })
        for theme in themes {
            #expect(!theme.footer.dateFormat.isEmpty, "\(theme.id)")
            #expect(theme.footer.captionSize > 0 && theme.footer.dateSize > 0, "\(theme.id)")
        }
    }

    @Test func aMissingFontFallsBackToASystemFace() {
        let missing = NookStripFont.named("NoSuchFontAnywhere-Bold", fallback: .mono).font(size: 12)
        let twelve: CGFloat = 12
        #expect(CTFontGetSize(missing) == twelve)
        let system = NookStripFont.system(.rounded).font(size: 9)
        let nine: CGFloat = 9
        #expect(CTFontGetSize(system) == nine)
    }

    @Test func everyLayoutAndThemeHasItsWordsInAllThreeLanguages() throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/OpenIslandApp/Resources", isDirectory: true)
        var keys = NookPhotoStripLayout.Kind.allCases.map(\.nameKey)
        for theme in NookPhotoStripTheme.all {
            keys.append(theme.nameKey)
            keys.append(theme.defaultCaptionKey)
        }
        keys += [NookPhotoBoothFailure.camera.messageKey, NookPhotoBoothFailure.save.messageKey]
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let file = resources.appendingPathComponent("\(language).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: file) as? [String: String], "\(language) did not load")
            for key in keys {
                let value = table[key]
                #expect(value?.isEmpty == false, "\(language) lacks \(key)")
            }
        }
    }

    @Test func datesFollowTheThemesPattern() {
        let locale = Locale(identifier: "en_US")
        func text(_ id: String) -> String {
            NookPhotoStripTheme.theme(id: id).footer.dateText(for: Self.date, calendar: Self.calendar, locale: locale)
        }
        #expect(text("classic") == "OCT 09 2026")
        #expect(text("paperWhite") == "2026.10.09")
        #expect(text("arcade") == "2026-10-09")
        #expect(text("goldenHour") == "Oct 9, 2026")
        #expect(text("frontPage") == "Friday, October 9, 2026")
    }

    // MARK: Files

    @Test func stripsGetADatedNameThatNeverReplacesAFile() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NookPhotoStripTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(NookPhotoBoothStore.fileName(for: Self.date, calendar: Self.calendar, attempt: 1) == "Photo Strip 2026-10-09 at 19.47.00.pdf")
        #expect(NookPhotoBoothStore.fileName(for: Self.date, calendar: Self.calendar, attempt: 3) == "Photo Strip 2026-10-09 at 19.47.00 3.pdf")

        let store = NookPhotoBoothStore()
        // The folder is made on the first save.
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        let first = try store.save(Data("one".utf8), into: folder, at: Self.date, calendar: Self.calendar)
        let second = try store.save(Data("two".utf8), into: folder, at: Self.date, calendar: Self.calendar)
        let third = try store.save(Data("three".utf8), into: folder, at: Self.date, calendar: Self.calendar)

        #expect(first.lastPathComponent == "Photo Strip 2026-10-09 at 19.47.00.pdf")
        #expect(second.lastPathComponent == "Photo Strip 2026-10-09 at 19.47.00 2.pdf")
        #expect(third.lastPathComponent == "Photo Strip 2026-10-09 at 19.47.00 3.pdf")
        #expect(try Data(contentsOf: first) == Data("one".utf8))
        #expect(try Data(contentsOf: second) == Data("two".utf8))
        let three = 3
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == three)
    }

    @Test func theDefaultFolderIsInPicturesAndNotAFolderMacOSAsksAbout() {
        let folder = NookPhotoBoothStore.defaultFolder()
        #expect(folder.lastPathComponent == NookPhotoBoothStore.folderName)
        #expect(folder.deletingLastPathComponent().lastPathComponent == "Pictures")
        for asked in ["Desktop", "Documents", "Downloads"] {
            #expect(!folder.pathComponents.contains(asked))
        }
    }

    // MARK: The live picture

    @Test func theLiveCropMatchesWhatASlotKeeps() {
        let picture = CGSize(width: 480, height: 270)
        #expect(NookPhotoBoothLiveCrop.keptSize(pictureSize: picture, slotAspect: 1.5) == CGSize(width: 405, height: 270))
        #expect(NookPhotoBoothLiveCrop.keptSize(pictureSize: picture, slotAspect: 16.0 / 9.0) == picture)
        #expect(NookPhotoBoothLiveCrop.keptSize(pictureSize: CGSize(width: 400, height: 300), slotAspect: 2) == CGSize(width: 400, height: 200))
        #expect(NookPhotoBoothLiveCrop.keptSize(pictureSize: .zero, slotAspect: 1.5) == .zero)
    }

    @Test func glintsSitInTheGapsBetweenPictures() {
        let classic = NookPhotoStripPatterns.glintSpots(NookPhotoStripLayout.layout(.classic))
        // Two in the footer and one in each of the three gaps.
        let five = 5
        #expect(classic.count == five)
        let grid = NookPhotoStripPatterns.glintSpots(NookPhotoStripLayout.layout(.grid))
        // No footer glints on a one-line footer: two side gaps, two between rows.
        let four = 4
        #expect(grid.count == four)
        for spot in classic + grid {
            #expect(spot.radius > 0)
        }
    }
}
