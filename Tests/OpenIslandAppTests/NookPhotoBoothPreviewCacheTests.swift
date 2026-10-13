import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Which previews are drawn and when, and the tiles as plain values. The
/// cache is handed a drawing that only counts and no strip is drawn here.
@MainActor
struct NookPhotoBoothPreviewCacheTests {
    /// Remembers every key the cache asked to have drawn.
    private final class DrawLog: @unchecked Sendable {
        private let lock = NSLock()
        private var drawn: [NookPhotoBoothPreviewKey] = []

        var keys: [NookPhotoBoothPreviewKey] { lock.withLock { drawn } }

        var draw: NookPhotoBoothPreviews.Draw {
            { [self] key in
                lock.withLock { drawn.append(key) }
                return NookPhotoBoothPreviewImage(image: NookPhotoBoothImaging.bitmapContext(width: 1, height: 1)!.makeImage()!)
            }
        }
    }

    private static func set(
        _ layout: NookPhotoStripLayout.Kind,
        _ themeID: String,
        typed: String = ""
    ) -> NookPhotoBoothPreviewSet {
        NookPhotoBoothPreviewSet(
            layout: layout,
            theme: .theme(id: themeID),
            typedCaption: typed,
            defaultLine: { "line of \($0.id)" }
        )
    }

    private static func key(_ kind: NookPhotoStripLayout.Kind, _ themeID: String) -> NookPhotoBoothPreviewKey {
        NookPhotoBoothPreviewKey(layout: kind, theme: .theme(id: themeID), typedCaption: "", defaultLine: "line of \(themeID)")
    }

    // MARK: What is on screen

    @Test func settingsShowsThreeLayoutsAndEveryThemeWithTheChosenPairOnce() {
        let set = Self.set(.classic, "classic")
        #expect(set.keys.count == NookPhotoStripLayout.Kind.allCases.count + NookPhotoStripTheme.all.count)
        #expect(Set(set.keys).count == set.keys.count - 1)
        #expect(set.layoutTile(.classic) == set.themeTile(.theme(id: "classic")))
        // A layout's tile is in the chosen theme, and a theme's in the chosen layout.
        #expect(set.layoutTile(.grid) == Self.key(.grid, "classic"))
        #expect(set.themeTile(.theme(id: "film")) == Self.key(.classic, "film"))
    }

    // MARK: The cache

    @Test func theSameKeyIsDrawnOnce() async {
        let log = DrawLog()
        let previews = NookPhotoBoothPreviews(draw: log.draw)
        let key = Self.key(.classic, "gingham")
        #expect(previews.image(for: key) == nil)
        await previews.request([key])
        await previews.request([key, key])
        await previews.request([key])
        #expect(log.keys == [key])
        #expect(previews.image(for: key) != nil)
    }

    @Test func twoAsksAtOnceDrawEachPreviewOnce() async {
        let log = DrawLog()
        let previews = NookPhotoBoothPreviews(draw: log.draw)
        let keys = Self.set(.classic, "classic").keys
        async let first: Void = previews.request(keys)
        async let second: Void = previews.request(keys)
        _ = await (first, second)
        #expect(log.keys.count == Set(keys).count)
        #expect(Set(log.keys) == Set(keys))
        #expect(keys.allSatisfy { previews.image(for: $0) != nil })
    }

    @Test func aNewThemeDrawsOnlyWhatDependsOnIt() async {
        let log = DrawLog()
        let previews = NookPhotoBoothPreviews(draw: log.draw)
        await previews.request(Self.set(.classic, "classic").keys)
        #expect(log.keys.count == 18)

        let gingham = Self.set(.classic, "gingham")
        await previews.request(gingham.keys)
        // The grid and the caption strip in the new theme. The classic strip in
        // it was already drawn as that theme's own tile, and no other tile moved.
        #expect(log.keys.count == 20)
        #expect(Set(log.keys.suffix(2)) == [gingham.layoutTile(.grid), gingham.layoutTile(.caption)])
    }

    @Test func aNewLayoutDrawsOnlyTheThemesInIt() async {
        let log = DrawLog()
        let previews = NookPhotoBoothPreviews(draw: log.draw)
        await previews.request(Self.set(.classic, "classic").keys)

        let grid = Self.set(.grid, "classic")
        await previews.request(grid.keys)
        // Fifteen themes in the new layout. The sixteenth, the chosen theme, was
        // drawn as that layout's tile, and the three layout tiles are unchanged.
        #expect(log.keys.count == 18 + 15)
        #expect(log.keys.suffix(15).allSatisfy { $0.layout == .grid && $0.themeID != "classic" })
    }

    @Test func goingBackToAThemeDrawsNothing() async {
        let log = DrawLog()
        let previews = NookPhotoBoothPreviews(draw: log.draw)
        await previews.request(Self.set(.classic, "classic").keys)
        await previews.request(Self.set(.classic, "gingham").keys)
        let before = log.keys.count
        await previews.request(Self.set(.classic, "classic").keys)
        await previews.request(Self.set(.classic, "gingham").keys)
        #expect(log.keys.count == before)
    }

    @Test func aNewCaptionDrawsEverythingAgain() async {
        let log = DrawLog()
        let previews = NookPhotoBoothPreviews(draw: log.draw)
        await previews.request(Self.set(.classic, "classic").keys)
        await previews.request(Self.set(.classic, "classic", typed: "Friday night").keys)
        #expect(log.keys.count == 36)
    }

    @Test func aCaptionThatPrintsTheSameDrawsNothingNew() async {
        let log = DrawLog()
        let previews = NookPhotoBoothPreviews(draw: log.draw)
        await previews.request(Self.set(.classic, "classic").keys)
        // Spaces at the ends do not print, and a theme's own line typed out
        // prints like the empty field does.
        await previews.request(Self.set(.classic, "classic", typed: "   ").keys)
        let own = NookPhotoBoothPreviewSet(
            layout: .classic,
            theme: .theme(id: "classic"),
            typedCaption: "line of classic",
            defaultLine: { "line of \($0.id)" }
        )
        await previews.request([own.themeTile(.theme(id: "classic"))])
        #expect(log.keys.count == 18)
    }

    @Test func theCacheKeepsNoMoreThanItsCapacityAndDropsTheOldest() async {
        let log = DrawLog()
        let previews = NookPhotoBoothPreviews(capacity: 3, draw: log.draw)
        let keys = ["classic", "sepia", "film", "gingham", "ribbon"].map { Self.key(.classic, $0) }
        await previews.request(keys)
        #expect(previews.images.count == 3)
        #expect(keys.prefix(2).allSatisfy { previews.image(for: $0) == nil })
        #expect(keys.suffix(3).allSatisfy { previews.image(for: $0) != nil })
        // A dropped preview is drawn again when it is asked for.
        await previews.request([keys[0]])
        #expect(log.keys.count == 6)
    }

    @Test func aPreviewThatIsAskedForStaysOverOlderOnes() async {
        let log = DrawLog()
        let previews = NookPhotoBoothPreviews(capacity: 3, draw: log.draw)
        let keys = ["classic", "sepia", "film", "gingham"].map { Self.key(.classic, $0) }
        await previews.request(Array(keys.prefix(3)))
        // Asking for the first again makes the second the oldest.
        await previews.request([keys[0]])
        await previews.request([keys[3]])
        #expect(previews.image(for: keys[0]) != nil)
        #expect(previews.image(for: keys[1]) == nil)
        #expect(log.keys.count == 4)
    }

    @Test func askingAgainForAPartlyKeptSetEvictsNothingTheAskNeeds() async {
        let log = DrawLog()
        let previews = NookPhotoBoothPreviews(draw: log.draw)
        let first = Self.set(.classic, "classic", typed: "one").keys
        await previews.request(first)
        for typed in ["two", "three", "four"] {
            await previews.request(Self.set(.classic, "classic", typed: typed).keys)
        }
        // Four screens of 18 are 72 previews, more than the cache keeps. The
        // oldest of the first screen are gone and the rest of it is still there.
        #expect(previews.images.count == NookPhotoBoothPreviews.defaultCapacity)
        let wanted = Set(first)
        let missing = wanted.filter { previews.image(for: $0) == nil }
        #expect(!missing.isEmpty && missing.count < wanted.count, "the first screen should be partly kept")

        let drawnBefore = log.keys.count
        await previews.request(first)
        #expect(wanted.allSatisfy { previews.image(for: $0) != nil }, "a preview of the ask was evicted by the ask")
        let drawn = Array(log.keys.dropFirst(drawnBefore))
        #expect(Set(drawn) == missing, "only the missing previews are drawn")
        #expect(drawn.count == missing.count, "each is drawn once")
    }

    @Test func aCancelledAskDrawsNothingMore() async {
        let log = DrawLog()
        let previews = NookPhotoBoothPreviews(draw: log.draw)
        let ask = Task { await previews.request(Self.set(.classic, "classic").keys) }
        ask.cancel()
        await ask.value
        #expect(log.keys.isEmpty)
        // Nothing was left half done: the next ask draws the lot.
        await previews.request(Self.set(.classic, "classic").keys)
        #expect(log.keys.count == 18)
    }

    // MARK: Typing in the caption field

    @Test func aCaptionSettlesWhenTypingPauses() async {
        let settled = await NookPhotoBoothPreviews.settled("Friday night", pause: .milliseconds(20))
        #expect(settled == "Friday night")
    }

    @Test func aCaptionDoesNotSettleWhileTypingGoesOn() async {
        // Each key press starts a new wait and cancels the one before, which is
        // what the field's task does when its caption changes.
        var waits: [Task<String?, Never>] = []
        for typed in ["F", "Fr", "Fri"] {
            waits.last?.cancel()
            waits.append(Task { await NookPhotoBoothPreviews.settled(typed, pause: .seconds(30)) })
        }
        let last = Task { await NookPhotoBoothPreviews.settled("Fri", pause: .milliseconds(20)) }
        waits.last?.cancel()
        for wait in waits {
            #expect(await wait.value == nil)
        }
        #expect(await last.value == "Fri")
    }

    // MARK: Tiles as plain values

    @Test func theLayoutTilesListTheLayoutsAndMarkTheChosenOne() {
        func tiles(chosen: NookPhotoStripLayout.Kind) -> [NookPhotoBoothChoice] {
            NookPhotoStripLayout.Kind.allCases.map { .layout($0, chosen: chosen, name: "name of \($0.rawValue)") }
        }
        for chosen in NookPhotoStripLayout.Kind.allCases {
            let list = tiles(chosen: chosen)
            #expect(list.map(\.id) == ["classic", "grid", "caption"])
            #expect(list.map(\.name) == ["name of classic", "name of grid", "name of caption"])
            #expect(list.filter(\.isChosen).map(\.id) == [chosen.rawValue])
        }
    }

    @Test func theThemeTilesListEveryThemeAndMarkTheChosenOne() {
        func tiles(chosen: String) -> [NookPhotoBoothChoice] {
            NookPhotoStripTheme.all.map { .theme($0, chosen: chosen, name: "name of \($0.id)") }
        }
        for chosen in ["classic", "film", "scrapbook"] {
            let list = tiles(chosen: chosen)
            #expect(list.map(\.id) == NookPhotoStripTheme.all.map(\.id))
            #expect(list.map(\.name) == NookPhotoStripTheme.all.map { "name of \($0.id)" })
            #expect(list.filter(\.isChosen).map(\.id) == [chosen])
        }
        // An id the catalog does not have marks none, which is not a state the
        // booth is ever in: it falls back to the default theme when it loads.
        #expect(tiles(chosen: "nope").allSatisfy { !$0.isChosen })
    }

    @Test func theTilesTakeTheirNamesFromTheStringsInEveryLanguage() throws {
        let languages = ["en", "zh-Hans", "zh-Hant"]
        let keys = NookPhotoStripLayout.Kind.allCases.map(\.nameKey) + NookPhotoStripTheme.all.map(\.nameKey)
        for language in languages {
            let path = try #require(Bundle.appResources.path(forResource: language, ofType: "lproj")
                ?? Bundle.appResources.path(forResource: language.lowercased(), ofType: "lproj"), "no \(language) strings")
            let bundle = try #require(Bundle(path: path))
            for key in keys {
                let name = bundle.localizedString(forKey: key, value: "<missing>", table: nil)
                #expect(name != "<missing>" && !name.isEmpty, "\(language) has no \(key)")
            }
        }
    }

    // MARK: The grid

    @Test func aTileIsWideEnoughForItsPicture() {
        // Standing strips take the usual width. The grid card is a wide picture.
        #expect(NookPhotoBoothTile.minimumWidth(showing: .classic) == NookPhotoBoothTile.minimumWidth)
        #expect(NookPhotoBoothTile.minimumWidth(showing: .caption) == NookPhotoBoothTile.minimumWidth)
        #expect(NookPhotoBoothTile.minimumWidth(showing: .grid) == 110 + NookPhotoBoothTile.cardPadding)
    }

    @Test func theGridWrapsToTheWidthItIsGiven() {
        let flow = NookPhotoBoothTileFlow(minimumWidth: 96, spacing: 8)
        // 5 fit across 520 points. Sixteen in 5 columns is four rows with one
        // tile alone on the last, and the grid takes four columns of four.
        #expect(flow.columns(fitting: 520, count: 16) == 4)
        #expect(flow.columns(fitting: 300, count: 16) == 2)
        #expect(flow.columns(fitting: 96, count: 16) == 1)
        #expect(flow.columns(fitting: 20, count: 16) == 1)
        #expect(flow.columns(fitting: 2000, count: 16) == 16)
        #expect(flow.columns(fitting: 2000, count: 3) == 3)
        #expect(flow.columns(fitting: 2000, count: 0) == 1)
        // Never more columns than fit, and always enough to show every tile.
        for width in stride(from: CGFloat(96), through: 1200, by: 37) {
            for count in 1...16 {
                let columns = flow.columns(fitting: width, count: count)
                let fits = max(1, Int(((width + 8) / (96 + 8)).rounded(.down)))
                #expect(columns >= 1 && columns <= fits, "width \(width), \(count) tiles")
                #expect(columns * ((count + columns - 1) / columns) >= count)
            }
        }
    }

    @Test func aWidthThatIsNotFiniteTakesOneRowAndNeverTraps() {
        let flow = NookPhotoBoothTileFlow(minimumWidth: 96, spacing: 8)
        let oneRow: CGFloat = 16 * 96 + 15 * 8
        #expect(flow.columns(fitting: .infinity, count: 16) == 16)
        #expect(flow.columns(fitting: .nan, count: 16) == 16)
        #expect(flow.columns(fitting: -.infinity, count: 16) == 16)
        #expect(flow.layoutWidth(nil, count: 16) == oneRow)
        #expect(flow.layoutWidth(.infinity, count: 16) == oneRow)
        #expect(flow.layoutWidth(.nan, count: 16) == oneRow)
        #expect(flow.layoutWidth(520, count: 16) == 520)
        #expect(flow.layoutWidth(-10, count: 16) == 0)
        #expect(flow.layoutWidth(nil, count: 0) == 0)
    }

    @Test func aGridWithNoWidthGivenIsOneRow() {
        // A bare hosting view proposes no width at all.
        let flow = NookPhotoBoothTileFlow(minimumWidth: 96, spacing: 8)
        let themes = NookPhotoStripTheme.all
        let renderer = ImageRenderer(content: flow { ForEach(themes) { _ in Color.clear.frame(height: 150) } })
        renderer.scale = 1
        #expect(renderer.cgImage?.width == 16 * 96 + 15 * 8)
        #expect(renderer.cgImage?.height == 150)
    }

    @Test func theGridMakesEveryThemeVisibleInRows() {
        let flow = NookPhotoBoothTileFlow(minimumWidth: 96, spacing: 8)
        let themes = NookPhotoStripTheme.all
        let renderer = ImageRenderer(
            content: flow {
                ForEach(themes) { _ in Color.clear.frame(height: 150) }
            }
            .frame(width: 520, alignment: .topLeading)
        )
        renderer.scale = 1
        // 16 tiles in 4 columns are 4 rows of 150 with 3 gaps of 8 between.
        #expect(renderer.cgImage?.width == 520)
        #expect(renderer.cgImage?.height == 4 * 150 + 3 * 8)
    }
}
