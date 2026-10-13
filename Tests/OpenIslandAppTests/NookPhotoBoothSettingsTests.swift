import Foundation
import Testing
@testable import OpenIslandApp

/// What a click in the photo booth's Settings does, and which previews the
/// section asks for. The tiles' buttons call `choose`, and the section builds
/// its previews with `previewSet`, which is what is tested here. Nothing
/// opens a window or touches the standard settings.
@MainActor
struct NookPhotoBoothSettingsTests {
    private static func booth(_ defaults: MemoryDefaults = MemoryDefaults()) -> NookPhotoBoothModel {
        NookModel(defaults: defaults, looksForImportedGIF: false).photoBooth
    }

    // MARK: Choosing

    @Test func choosingALayoutTileWritesTheLayoutAndNothingElse() {
        let defaults = MemoryDefaults()
        let booth = Self.booth(defaults)
        booth.themeID = "film"
        booth.caption = "Friday night"
        for kind in NookPhotoStripLayout.Kind.allCases.reversed() {
            NookPhotoBoothSettings.choose(kind, on: booth)
            #expect(booth.layoutKind == kind)
            #expect(defaults.string(forKey: NookPhotoBoothModel.layoutKey) == kind.rawValue)
            #expect(booth.themeID == "film")
            #expect(booth.caption == "Friday night")
        }
    }

    @Test func choosingAThemeTileWritesTheThemeAndNothingElse() {
        let defaults = MemoryDefaults()
        let booth = Self.booth(defaults)
        booth.layoutKind = .grid
        booth.caption = "Friday night"
        // Starting off the default theme makes choosing it a change too.
        booth.themeID = "film"
        for theme in NookPhotoStripTheme.all {
            NookPhotoBoothSettings.choose(theme, on: booth)
            #expect(booth.themeID == theme.id)
            #expect(booth.theme == theme)
            #expect(defaults.string(forKey: NookPhotoBoothModel.themeKey) == theme.id)
            #expect(booth.layoutKind == .grid)
            #expect(booth.caption == "Friday night")
        }
    }

    @Test func aChosenTileIsTheOneTheModelNowHolds() {
        let booth = Self.booth()
        NookPhotoBoothSettings.choose(.caption, on: booth)
        NookPhotoBoothSettings.choose(.theme(id: "scrapbook"), on: booth)
        let layouts = NookPhotoStripLayout.Kind.allCases.map { NookPhotoBoothChoice.layout($0, chosen: booth.layoutKind, name: $0.rawValue) }
        let themes = NookPhotoStripTheme.all.map { NookPhotoBoothChoice.theme($0, chosen: booth.themeID, name: $0.id) }
        #expect(layouts.filter(\.isChosen).map(\.id) == ["caption"])
        #expect(themes.filter(\.isChosen).map(\.id) == ["scrapbook"])
    }

    // MARK: The previews follow the settled caption

    @Test func theTilesKeyStaysPutWhileTheCaptionIsTypedAndMovesWhenItSettles() async {
        let booth = Self.booth()
        booth.themeID = "gingham"
        booth.caption = "Fri"
        var settled: String? = "Fri"
        func keys() -> (layout: NookPhotoBoothPreviewKey, theme: NookPhotoBoothPreviewKey) {
            let set = NookPhotoBoothSettings.previewSet(for: booth, settledCaption: settled)
            return (set.layoutTile(.grid), set.themeTile(.theme(id: "film")))
        }
        let before = keys()
        #expect(before.layout.caption == "Fri")

        // Each key press moves the field and starts a wait that the next press
        // cancels. None of them reaches the tiles.
        var wait: Task<String?, Never>?
        for typed in ["Frid", "Frida", "Friday"] {
            wait?.cancel()
            if let cancelled = await wait?.value { settled = cancelled }
            booth.caption = typed
            #expect(keys().layout == before.layout, "the key moved on a key press: \(typed)")
            #expect(keys().theme == before.theme, "the key moved on a key press: \(typed)")
            wait = Task { await NookPhotoBoothPreviews.settled(typed, pause: .milliseconds(30)) }
        }
        #expect(settled == "Fri", "a cancelled wait settled the caption")

        // Typing stops, the last wait runs out, and the tiles follow.
        settled = await wait?.value ?? nil
        #expect(settled == "Friday")
        let after = keys()
        #expect(after.layout != before.layout)
        #expect(after.layout.caption == "Friday")
        #expect(after.theme.caption == "FRIDAY", "the film theme prints in capitals")
    }

    @Test func untilTheCaptionHasSettledTheTilesUseTheFieldsText() {
        let booth = Self.booth()
        booth.themeID = "gingham"
        booth.caption = "best day"
        let unsettled = NookPhotoBoothSettings.previewSet(for: booth, settledCaption: nil)
        #expect(unsettled.layoutTile(.classic).caption == "best day")
        let settled = NookPhotoBoothSettings.previewSet(for: booth, settledCaption: "best day")
        #expect(settled.keys == unsettled.keys)
    }

    @Test func theTilesAreInTheChosenLayoutAndTheme() {
        let booth = Self.booth()
        NookPhotoBoothSettings.choose(.grid, on: booth)
        NookPhotoBoothSettings.choose(.theme(id: "film"), on: booth)
        let set = NookPhotoBoothSettings.previewSet(for: booth, settledCaption: "")
        // A layout's tile is in the chosen theme, and a theme's in the chosen layout.
        #expect(set.layoutTile(.caption).themeID == "film")
        #expect(set.themeTile(.theme(id: "sepia")).layout == .grid)
        #expect(set.layoutTile(.grid) == set.themeTile(.theme(id: "film")))
    }
}
