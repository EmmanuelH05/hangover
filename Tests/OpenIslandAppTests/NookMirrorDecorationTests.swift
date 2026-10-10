import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Frames and stickers on the mirror: the saved value, the placing rules,
/// the picker's sizes and the store. Nothing here starts the camera or
/// draws the live mirror.
@Suite struct NookMirrorDecorationTests {
    private typealias Layout = NookMirrorDecorationLayout

    private static let picture = CGSize(width: 432, height: 243)

    private static func sticker(
        _ design: String = NookMirrorDesigns.stickers[0].id,
        x: Double = 0.5,
        y: Double = 0.5,
        width: Double = 0.1,
        rotation: Double = 0
    ) -> NookMirrorSticker {
        NookMirrorSticker(designID: design, x: x, y: y, width: width, rotation: rotation)
    }

    // MARK: Saved data

    @Test func dataSavedByTheGroundworkBuildStillReads() throws {
        // The first shape of a sticker had no colorway.
        let old = """
        {"frameID":"\(NookMirrorDesigns.frames[0].id)","stickers":[
          {"id":"7B0E6E6E-3C6E-4B57-9E0A-0D0B9E3A8A11","designID":"\(NookMirrorDesigns.stickers[0].id)",
           "x":0.25,"y":0.75,"width":0.2,"rotation":15}
        ]}
        """
        let set = try JSONDecoder().decode(NookMirrorDecorationSet.self, from: Data(old.utf8))

        #expect(set.frameID == NookMirrorDesigns.frames[0].id)
        #expect(set.stickers.count == 1)
        let quarter: Double = 0.25
        let fifteen: Double = 15
        #expect(set.stickers[0].x == quarter)
        #expect(set.stickers[0].rotation == fifteen)
        #expect(set.stickers[0].variant == 0)
    }

    @Test func aStickerNeedsOnlyItsDesignAndTheRestFallsBackToTheMiddle() throws {
        let bare = #"{"stickers":[{"designID":"anything"}]}"#
        let set = try JSONDecoder().decode(NookMirrorDecorationSet.self, from: Data(bare.utf8))

        let half: Double = 0.5
        #expect(set.frameID == nil)
        #expect(set.stickers[0].x == half)
        #expect(set.stickers[0].y == half)
        #expect(set.stickers[0].width == Layout.defaultStickerWidth)
        #expect(set.stickers[0].rotation == 0)
    }

    @Test func aSetSurvivesARoundTripWithItsColorway() throws {
        var placed = Self.sticker(x: 0.2, y: 0.8, width: 0.3, rotation: -40)
        placed.variant = 2
        let set = NookMirrorDecorationSet(frameID: NookMirrorDesigns.frames[0].id, stickers: [placed])

        let back = try JSONDecoder().decode(NookMirrorDecorationSet.self, from: JSONEncoder().encode(set))

        #expect(back == set)
    }

    @Test func emptyDataIsAnEmptySet() throws {
        let set = try JSONDecoder().decode(NookMirrorDecorationSet.self, from: Data("{}".utf8))
        #expect(set == .none)
        #expect(set.isEmpty)
    }

    // MARK: Keeping stickers on the picture

    @Test func aStickerIsKeptOnThePictureAndInsideTheSizeLimits() {
        let wild = NookMirrorSticker(designID: "x", x: -3, y: 9, width: 40, rotation: 725, variant: -4)
        let fitted = Layout.clamped(wild)

        let five: Double = 5
        #expect(fitted.x == 0)
        #expect(fitted.y == 1)
        #expect(fitted.width == Layout.stickerWidthRange.upperBound)
        #expect(fitted.rotation == five)
        #expect(fitted.variant == 0)

        let tiny = Layout.clamped(NookMirrorSticker(designID: "x", x: 0.5, y: 0.5, width: 0.0001))
        #expect(tiny.width == Layout.stickerWidthRange.lowerBound)
    }

    @Test func numbersThatAreNotNumbersFallBackToTheMiddle() {
        let broken = NookMirrorSticker(designID: "x", x: .nan, y: .infinity, width: .nan, rotation: .nan)
        let fitted = Layout.clamped(broken)

        let half: Double = 0.5
        #expect(fitted.x == half)
        #expect(fitted.y == half)
        #expect(fitted.width == Layout.defaultStickerWidth)
        #expect(fitted.rotation == 0)
    }

    @Test(arguments: [
        (0.0, 0.0), (180.0, 180.0), (-180.0, 180.0), (190.0, -170.0), (-190.0, 170.0), (360.0, 0.0), (725.0, 5.0),
    ])
    func aTurnIsKeptWithinHalfATurnEachWay(given: Double, expected: Double) {
        #expect(abs(Layout.normalizedRotation(given) - expected) < 0.000_001)
    }

    @Test func aStickerIsASquareAsWideAsItsShareOfThePicture() {
        let rect = Layout.rect(of: Self.sticker(x: 0.5, y: 0.5, width: 0.25), in: Self.picture)
        // A quarter of the 432pt picture's width, centered in it.

        let side: CGFloat = 108
        let left: CGFloat = 162
        let top: CGFloat = 67.5
        #expect(rect.width == side)
        #expect(rect.height == side)
        #expect(rect.minX == left)
        #expect(rect.minY == top)
    }

    // MARK: Adding, moving, removing

    @Test func theMirrorHoldsAtMostTheCapAndTheNextOneIsRefused() {
        var set = NookMirrorDecorationSet.none
        for _ in 0..<Layout.maxStickers {
            guard let added = set.adding(designID: NookMirrorDesigns.stickers[0].id) else {
                Issue.record("the mirror refused a sticker before it was full")
                return
            }
            set = added.set
        }

        #expect(set.stickers.count == Layout.maxStickers)
        #expect(set.adding(designID: NookMirrorDesigns.stickers[0].id) == nil)
        #expect(Set(set.stickers.map(\.id)).count == Layout.maxStickers)
    }

    @Test func aNewStickerLandsOnThePictureAndNotOnTopOfTheLastOne() {
        var spots: [String] = []
        for count in 0..<Layout.maxStickers {
            let spot = Layout.dropPoint(count: count)
            #expect((0.1...0.9).contains(spot.x), "sticker \(count) lands off the picture")
            #expect((0.1...0.9).contains(spot.y), "sticker \(count) lands off the picture")
            spots.append("\(spot.x),\(spot.y)")
        }
        #expect(spots[0] != spots[1])
        #expect(Set(spots.prefix(6)).count == 6)
    }

    @Test func addingLeavesTheOldSetAsItWas() throws {
        let before = NookMirrorDecorationSet(frameID: "f", stickers: [Self.sticker()])
        let added = try #require(before.adding(designID: NookMirrorDesigns.stickers[0].id))

        #expect(before.stickers.count == 1)
        #expect(added.set.stickers.count == 2)
        #expect(added.set.frameID == "f")
        #expect(added.set.stickers.last == added.sticker)
    }

    @Test func aDragMovesAStickerByItsShareOfThePictureAndStopsAtTheEdge() {
        let start = Self.sticker(x: 0.5, y: 0.5)

        let moved = Layout.moved(start, by: CGSize(width: 43.2, height: -24.3), in: Self.picture)
        #expect(abs(moved.x - 0.6) < 0.000_001)
        #expect(abs(moved.y - 0.4) < 0.000_001)
        #expect(moved.id == start.id)

        let thrown = Layout.moved(start, by: CGSize(width: 5000, height: 5000), in: Self.picture)
        #expect(thrown.x == 1)
        #expect(thrown.y == 1)

        #expect(Layout.moved(start, by: CGSize(width: 10, height: 10), in: .zero) == start)
    }

    @Test func aPullPastTheBiggestSizeStopsThere() {
        let start = Self.sticker(width: 0.3)
        let corner = Layout.cornerOffset(of: start, corner: CGPoint(x: 1, y: 1), in: Self.picture)

        let grown = Layout.reshaped(start, handleTranslation: corner, in: Self.picture)
        let shrunk = Layout.reshaped(
            start, handleTranslation: CGSize(width: -corner.width * 0.99, height: -corner.height * 0.99), in: Self.picture
        )

        #expect(grown.width == Layout.stickerWidthRange.upperBound)
        #expect(shrunk.width == Layout.stickerWidthRange.lowerBound)
    }

    @Test func pullingTheCornerStraightOutMakesTheStickerBiggerWithoutTurningIt() {
        let start = Self.sticker(width: 0.1)
        let corner = Layout.cornerOffset(of: start, corner: CGPoint(x: 1, y: 1), in: Self.picture)

        // Twice as far from the center, along the same line.
        let grown = Layout.reshaped(start, handleTranslation: corner, in: Self.picture)

        #expect(abs(grown.width - 0.2) < 0.000_001)
        #expect(abs(grown.rotation) < 0.000_001)
        #expect(grown.x == start.x)
        #expect(grown.y == start.y)
    }

    @Test func swingingTheCornerAroundTheCenterTurnsTheStickerAndKeepsItsSize() {
        let start = Self.sticker(width: 0.1)
        let corner = Layout.cornerOffset(of: start, corner: CGPoint(x: 1, y: 1), in: Self.picture)
        // The corner a quarter turn clockwise from where it began.
        let target = CGSize(width: -corner.height, height: corner.width)
        let swing = CGSize(width: target.width - corner.width, height: target.height - corner.height)

        let turned = Layout.reshaped(start, handleTranslation: swing, in: Self.picture)

        #expect(abs(turned.rotation - 90) < 0.000_1)
        #expect(abs(turned.width - 0.1) < 0.000_001)
    }

    @Test func theCornerFollowsTheStickersTurn() {
        let flat = Layout.cornerOffset(of: Self.sticker(width: 0.2), corner: CGPoint(x: 1, y: 1), in: Self.picture)
        // Half of a sticker a fifth of the 432pt picture wide.
        let half: CGFloat = 43.2
        #expect(abs(flat.width - half) < 0.000_1)
        #expect(abs(flat.height - half) < 0.000_1)

        let turned = Layout.cornerOffset(
            of: Self.sticker(width: 0.2, rotation: 90), corner: CGPoint(x: 1, y: 1), in: Self.picture
        )
        #expect(abs(turned.width + half) < 0.000_1)
        #expect(abs(turned.height - half) < 0.000_1)
    }

    @Test func aHandleIsPulledBackInsideThePicture() {
        let inside = Layout.reachable(CGPoint(x: -20, y: 500), in: Self.picture, inset: 11)
        let eleven: CGFloat = 11
        let bottom: CGFloat = 232
        #expect(inside.x == eleven)
        #expect(inside.y == bottom)
    }

    @Test func replacingSwapsOnlyTheStickerWithThatIDAndFitsIt() {
        let first = Self.sticker(x: 0.2)
        let second = Self.sticker(x: 0.8)
        var changed = second
        changed.x = 7

        let set = NookMirrorDecorationSet(stickers: [first, second]).replacing(changed)

        #expect(set.stickers[0] == first)
        #expect(set.stickers[1].x == 1)
        #expect(set.stickers.count == 2)
    }

    @Test func removingTakesOneStickerAndKeepsTheFrame() {
        let first = Self.sticker()
        let second = Self.sticker()
        let set = NookMirrorDecorationSet(frameID: "f", stickers: [first, second]).removing(first.id)

        #expect(set.stickers == [second])
        #expect(set.frameID == "f")
    }

    // MARK: What saved data is allowed to show

    @Test func designsThisBuildDoesNotKnowAreSkipped() {
        let known = Self.sticker()
        let set = NookMirrorDecorationSet(
            frameID: "frame.from.a.newer.build",
            stickers: [known, Self.sticker("sticker.from.a.newer.build")]
        ).sanitized()

        #expect(set.frameID == nil)
        #expect(set.stickers == [known])
    }

    @Test func savedDataIsCutToTheCapFittedAndNeverShowsAnIDTwice() {
        let twin = Self.sticker(x: 4)
        let many = (0..<20).map { _ in Self.sticker() }
        let set = NookMirrorDecorationSet(stickers: [twin, twin] + many).sanitized()

        #expect(set.stickers.count == Layout.maxStickers)
        #expect(Set(set.stickers.map(\.id)).count == Layout.maxStickers)
        #expect(set.stickers[0].x == 1)
    }

    // MARK: The store

    @Test func decorationsComeBackAfterARelaunch() {
        let defaults = MemoryDefaults()
        let set = NookMirrorDecorationSet(
            frameID: NookMirrorDesigns.frames[0].id,
            stickers: [Self.sticker(x: 0.3, y: 0.6, width: 0.22, rotation: 12)]
        )

        NookMirrorDecorationStore.save(set, to: defaults)

        #expect(NookMirrorDecorationStore.load(from: defaults) == set)
    }

    @Test func clearingEverythingLeavesNothingSaved() {
        let defaults = MemoryDefaults()
        NookMirrorDecorationStore.save(NookMirrorDecorationSet(stickers: [Self.sticker()]), to: defaults)
        #expect(defaults.all[NookMirrorDecorationStore.key] != nil)

        NookMirrorDecorationStore.save(.none, to: defaults)

        #expect(defaults.all.isEmpty)
        #expect(NookMirrorDecorationStore.load(from: defaults) == .none)
    }

    @Test func dataThatCannotBeReadMeansNoDecorations() {
        let defaults = MemoryDefaults()
        defaults.set(Data("not json".utf8), forKey: NookMirrorDecorationStore.key)
        #expect(NookMirrorDecorationStore.load(from: defaults) == .none)

        defaults.set("a string, not data", forKey: NookMirrorDecorationStore.key)
        #expect(NookMirrorDecorationStore.load(from: defaults) == .none)

        // A sticker with no design is not a sticker.
        defaults.set(Data(#"{"stickers":[{"x":0.5}]}"#.utf8), forKey: NookMirrorDecorationStore.key)
        #expect(NookMirrorDecorationStore.load(from: defaults) == .none)
    }

    @Test func loadingSkipsWhatANewerBuildSaved() {
        let defaults = MemoryDefaults()
        let known = Self.sticker()
        let saved = NookMirrorDecorationSet(
            frameID: "frame.from.a.newer.build",
            stickers: [Self.sticker("sticker.from.a.newer.build"), known]
        )
        NookMirrorDecorationStore.save(saved, to: defaults)

        let loaded = NookMirrorDecorationStore.load(from: defaults)

        #expect(loaded.frameID == nil)
        #expect(loaded.stickers == [known])
    }

    // MARK: The model

    @Test @MainActor func theModelAddsSelectsRecolorsAndClears() {
        // The model saves to a store held in memory.
        let defaults = MemoryDefaults()
        let nook = NookModel(defaults: defaults, looksForImportedGIF: false)
        nook.presentRingLight = { _ in }
        nook.clearMirrorDecorations()
        let design = NookMirrorDesigns.stickers[0]

        #expect(nook.addMirrorSticker(design.id))
        #expect(!nook.addMirrorSticker("sticker.from.a.newer.build"))
        let placed = nook.mirrorDecorations.stickers
        #expect(placed.count == 1)
        #expect(nook.selectedMirrorStickerID == placed[0].id)
        #expect(defaults.data(forKey: NookMirrorDecorationStore.key) != nil)

        nook.cycleMirrorStickerVariant(placed[0].id)
        #expect(nook.mirrorDecorations.stickers[0].variant == 1)
        for _ in 1..<design.variants { nook.cycleMirrorStickerVariant(placed[0].id) }
        #expect(nook.mirrorDecorations.stickers[0].variant == 0)

        nook.setMirrorFrame(NookMirrorDesigns.frames[0].id)
        #expect(nook.mirrorDecorations.frameID == NookMirrorDesigns.frames[0].id)

        nook.removeMirrorSticker(placed[0].id)
        #expect(nook.mirrorDecorations.stickers.isEmpty)
        #expect(nook.selectedMirrorStickerID == nil)

        nook.isDecoratingMirror = true
        nook.stopDecoratingMirror()
        #expect(!nook.isDecoratingMirror)

        nook.clearMirrorDecorations()
        #expect(nook.mirrorDecorations == .none)
        #expect(defaults.object(forKey: NookMirrorDecorationStore.key) == nil)
    }

    @Test @MainActor func aFullMirrorRefusesOneMoreSticker() {
        let defaults = MemoryDefaults()
        let nook = NookModel(defaults: defaults, looksForImportedGIF: false)
        nook.presentRingLight = { _ in }
        nook.clearMirrorDecorations()

        for _ in 0..<Layout.maxStickers {
            #expect(nook.addMirrorSticker(NookMirrorDesigns.stickers[1].id))
        }
        let last = nook.selectedMirrorStickerID

        #expect(!nook.addMirrorSticker(NookMirrorDesigns.stickers[1].id))
        #expect(nook.mirrorDecorations.stickers.count == Layout.maxStickers)
        #expect(nook.selectedMirrorStickerID == last)
    }

    @Test func theNoteIsTheDayInTheAppsLanguage() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 12)) ?? .now

        #expect(NookMirrorDecorationNote.text(for: day, languageCode: "en") == "Oct 9, 2026")
        #expect(NookMirrorDecorationNote.text(for: day, languageCode: "zh-Hans") == "2026年10月9日")
        #expect(!NookMirrorDecorationNote.today().isEmpty)
    }

    // MARK: The picker's size

    @Test func thePickerShowsOnlyUnderAMirrorThatIsUp() {
        #expect(Layout.isPickerShown(isDecorating: true, mirrorHeight: 259))
        #expect(!Layout.isPickerShown(isDecorating: true, mirrorHeight: nil))
        #expect(!Layout.isPickerShown(isDecorating: false, mirrorHeight: 259))
    }

    @Test func thePickerIsItsPaddingItsHeaderAndTwoRowsOfTiles() {
        // 8 above and below, a 22pt header, a 6pt gap, two 40pt rows and
        // the 6pt gap between them.
        let height: CGFloat = 130
        #expect(Layout.pickerHeight == height)
        #expect(Layout.pickerPageHeight == height + NookWidgetLayout.rowSpacing)
        #expect(Layout.frameTileSize.height == Layout.stickerTileSide)
    }

    @Test func thePickerFitsNineStickersOrSixFramesAcrossTheNotchPage() {
        // The picker is as wide as the picture's card: the 448pt page.
        #expect(Layout.columns(tileWidth: Layout.stickerTileSide, pickerWidth: 448) == 9)
        #expect(Layout.columns(tileWidth: Layout.frameTileSize.width, pickerWidth: 448) == 6)
        #expect(Layout.columns(tileWidth: 0, pickerWidth: 448) == 1)
        #expect(Layout.columns(tileWidth: 40, pickerWidth: 10) == 1)
    }

    @Test @MainActor func thePickerAddsItsHeightAndOneRowGapToThePage() {
        let placements = [
            NookWidgetPlacement(kind: .mirror, size: .medium), NookWidgetPlacement(kind: .todo, size: .medium),
        ]
        let mirrorOnly = NookPanelView.preferredHeight(
            for: placements, calendarStyle: .strip, isEditing: false, extras: NookPageExtras(mirrorHeight: 259)
        )
        let withPicker = NookPanelView.preferredHeight(
            for: placements,
            calendarStyle: .strip,
            isEditing: false,
            extras: NookPageExtras(mirrorHeight: 259, showsMirrorDecorationPicker: true)
        )

        #expect(withPicker - mirrorOnly == Layout.pickerPageHeight)
    }

    @Test func theLineBesideTheTabsSaysHowToStartHowManyAndWhenItIsFull() {
        func text(_ tab: NookMirrorDecorationPicker.Tab, _ count: Int) -> String {
            NookMirrorDecorationPickerNote.text(tab: tab, stickerCount: count) { key, numbers in
                ([key] + numbers.map(String.init)).joined(separator: " ")
            }
        }

        #expect(text(.stickers, 0) == "nook.mirror.decorations.hint.stickers")
        #expect(text(.stickers, 3) == "nook.mirror.decorations.count 3 \(Layout.maxStickers)")
        #expect(text(.stickers, Layout.maxStickers) == "nook.mirror.decorations.full \(Layout.maxStickers)")
        #expect(text(.frames, 3) == "nook.mirror.decorations.hint.frames")
    }
}
