import Foundation
import Testing
@testable import OpenIslandApp

/// The glow colors the user picks (D31): the palette, the resolver that
/// draws with it, how it is saved, the themes, and what a template leaves
/// alone.
struct IslandHaloPaletteTests {
    // MARK: Review fixes

    @Test func turningAlbumArtOffAndOnLeavesAnUntouchedPaletteAsItWas() {
        var palette = IslandHaloPalette.standard

        palette.setFollowsSource(false, for: .music)
        #expect(palette.music == IslandHaloPalette.suggestedMusic)
        #expect(palette.musicUsesArtwork == false)

        palette.setFollowsSource(true, for: .music)
        #expect(palette == IslandHaloPalette.standard)
    }

    @Test func turningAlbumArtBackOnKeepsAMusicColorTheUserPicked() {
        var palette = IslandHaloPalette.standard
        palette.setFollowsSource(false, for: .music)
        palette.music = Self.ember

        palette.setFollowsSource(true, for: .music)

        #expect(palette.music == Self.ember)
        #expect(palette.musicUsesArtwork)
    }

    @Test func savedDataWithAlbumArtOffAndNoMusicColorGetsTheStarterColor() {
        let loaded = IslandHaloPalette(storageValue: ["musicUsesArtwork": false])

        #expect(loaded.musicUsesArtwork == false)
        #expect(loaded.music == IslandHaloPalette.suggestedMusic)
        #expect(loaded.musicColor(artwork: nil) == IslandHaloPalette.suggestedMusic)
    }

    @MainActor
    @Test func theRealHaloIsGivenTheDisplaysPalette() {
        let model = AppModel(defaults: MemoryDefaults())
        model.nook.presentRingLight = { _ in }
        let profile = model.activeAppearanceProfile
        let before = model.nook.displayPreferences(for: profile).haloColors
        defer { model.nook.updateDisplayPreferences(for: profile) { $0.haloColors = before } }

        model.nook.updateDisplayPreferences(for: profile) { $0.haloColors.palette = Self.custom }

        #expect(model.islandHaloInputs.palette == Self.custom)
    }

    @Test func aGlowColorChangeAloneDoesNotCountAsAChangedPage() {
        let old = NookDisplayPreferences()
        var glowOnly = old
        glowOnly.haloColors.palette = Self.custom
        var other = old
        other.showsNotices.toggle()
        var both = glowOnly
        both.showsNotices.toggle()

        #expect(glowOnly.changesThePage(from: old) == false)
        #expect(other.changesThePage(from: old))
        #expect(both.changesThePage(from: old))
    }

    // MARK: Helpers

    private static let rose = IslandHaloRGB(rgb: 0xFF2D55)
    private static let teal = IslandHaloRGB(rgb: 0x14C4A0)
    private static let gold = IslandHaloRGB(rgb: 0xFFD23F)
    private static let lilac = IslandHaloRGB(rgb: 0xB79CFF)
    private static let paper = IslandHaloRGB(rgb: 0xF5F5F0)
    private static let ember = IslandHaloRGB(rgb: 0xFF6B3D)
    /// What an album cover or a notice brings with it.
    private static let own = IslandHaloRGB(rgb: 0x0AC81E)

    /// A palette with a different color in every moment.
    private static var custom: IslandHaloPalette {
        IslandHaloPalette(
            approval: rose,
            question: teal,
            completed: gold,
            running: lilac,
            notice: paper,
            music: ember,
            musicUsesArtwork: true
        )
    }

    private func inputs(
        policy: IslandMotionPolicy = .full,
        isOpened: Bool = false,
        waiting: IslandWaitingKind? = nil,
        flashToken: UInt64? = nil,
        noticeTint: IslandHaloRGB? = nil,
        musicTint: IslandHaloRGB? = nil,
        isRunning: Bool = false,
        palette: IslandHaloPalette = IslandHaloPaletteTests.custom,
        isMusicPlaying: Bool = false
    ) -> IslandHaloInputs {
        IslandHaloInputs(
            style: .subtle,
            policy: policy,
            isOpened: isOpened,
            waiting: waiting,
            flashToken: flashToken,
            noticeTint: noticeTint,
            musicTint: musicTint,
            isRunning: isRunning,
            palette: palette,
            isMusicPlaying: isMusicPlaying
        )
    }

    private func color(_ inputs: IslandHaloInputs) -> IslandHaloRGB? {
        let state = IslandHaloState.resolve(inputs)
        return state.isVisible ? state.color : nil
    }

    // MARK: The standard palette

    @Test func theStandardPaletteIsTheColorsTheHaloAlwaysHad() {
        let standard = IslandHaloPalette.standard

        #expect(standard.approval == IslandHaloRGB.rgb255(231, 167, 98))
        #expect(standard.question == IslandHaloRGB.rgb255(255, 213, 138))
        #expect(standard.completed == IslandHaloRGB.rgb255(111, 185, 130))
        #expect(standard.running == IslandHaloRGB.rgb255(110, 167, 255))
        #expect(standard.notice == nil)
        #expect(standard.music == nil)
        #expect(standard.musicUsesArtwork)
        #expect(IslandHaloColors.standard.effectivePalette == standard)
        #expect(NookDisplayPreferences().haloColors == .standard)
    }

    @Test func inputsThatNameNoPaletteUseTheStandardOne() {
        let plain = IslandHaloInputs(
            style: .subtle,
            policy: .full,
            isOpened: false,
            waiting: .approval,
            flashToken: nil,
            noticeTint: nil,
            musicTint: nil,
            isRunning: false
        )

        #expect(plain.palette == .standard)
        #expect(!plain.isMusicPlaying)
        #expect(IslandHaloState.resolve(plain).color == IslandHaloRGB.approval)
    }

    // MARK: The resolver draws with the palette

    @Test func eachAgentMomentTakesItsColorFromThePalette() {
        #expect(color(inputs(waiting: .approval)) == Self.rose)
        #expect(color(inputs(waiting: .question)) == Self.teal)
        #expect(color(inputs(flashToken: 1)) == Self.gold)
        #expect(color(inputs(isRunning: true)) == Self.lilac)
    }

    @Test func theFlashOnAnOpenIslandAndTheLastResortGlowUseThePaletteToo() {
        #expect(color(inputs(isOpened: true, flashToken: 4)) == Self.gold)
        #expect(color(inputs(policy: .minimal, waiting: .approval)) == Self.rose)
        #expect(color(inputs(policy: .minimal, waiting: .question)) == Self.teal)
        #expect(color(inputs(policy: .reduced, waiting: .approval)) == Self.rose)
    }

    @Test func aNoticeTakesThePaletteColorOrKeepsItsOwn() {
        var keepsOwn = Self.custom
        keepsOwn.notice = nil

        #expect(color(inputs(noticeTint: Self.own)) == Self.paper)
        #expect(color(inputs(noticeTint: Self.own, palette: keepsOwn)) == Self.own)
        // No notice on screen shows no notice glow, whatever the palette holds.
        #expect(color(inputs()) == nil)
    }

    @Test func musicTakesTheAlbumArtFirstAndThePaletteColorWhenTheArtHasNone() {
        #expect(color(inputs(musicTint: Self.own, isMusicPlaying: true)) == Self.own)
        #expect(color(inputs(musicTint: nil, isMusicPlaying: true)) == Self.ember)
    }

    @Test func musicUsesOnlyThePaletteColorWhenTheArtIsSwitchedOff() {
        var fixed = Self.custom
        fixed.musicUsesArtwork = false

        #expect(color(inputs(musicTint: Self.own, palette: fixed, isMusicPlaying: true)) == Self.ember)
        #expect(color(inputs(musicTint: nil, palette: fixed, isMusicPlaying: true)) == Self.ember)
    }

    @Test func musicWithNoColorAnywhereShowsNoGlowAndLetsRunningThrough() {
        var bare = Self.custom
        bare.music = nil

        #expect(color(inputs(musicTint: nil, palette: bare, isMusicPlaying: true)) == nil)
        #expect(color(inputs(musicTint: nil, isRunning: true, palette: bare, isMusicPlaying: true)) == Self.lilac)

        bare.musicUsesArtwork = false
        #expect(color(inputs(musicTint: Self.own, palette: bare, isMusicPlaying: true)) == nil)
    }

    @Test func aPaletteMusicColorNeverGlowsWhileNoMusicGlowIsWanted() {
        let state = IslandHaloState.resolve(inputs(musicTint: nil, isMusicPlaying: false))

        #expect(state == .off)
    }

    @Test func thePaletteChangesColorsAndNothingElse() {
        let standard = IslandHaloState.resolve(inputs(waiting: .approval, palette: .standard))
        var recolored = IslandHaloState.resolve(inputs(waiting: .approval))

        #expect(recolored.color != standard.color)
        recolored.color = standard.color
        #expect(recolored == standard)
    }

    // MARK: One color for everything

    @Test func oneColorTakesEveryMomentNoticesAndMusicIncluded() {
        var colors = IslandHaloColors.standard
        colors.palette = Self.custom
        colors.singleColor = Self.teal
        colors.usesSingleColor = true
        let palette = colors.effectivePalette

        for moment in IslandHaloMoment.allCases {
            #expect(palette.color(for: moment) == Self.teal, "\(moment)")
        }
        #expect(color(inputs(waiting: .approval, palette: palette)) == Self.teal)
        #expect(color(inputs(flashToken: 2, palette: palette)) == Self.teal)
        #expect(color(inputs(noticeTint: Self.own, palette: palette)) == Self.teal)
        // The album art is not read: one color means one color.
        #expect(color(inputs(musicTint: Self.own, palette: palette, isMusicPlaying: true)) == Self.teal)
        #expect(color(inputs(isRunning: true, palette: palette)) == Self.teal)
    }

    @Test func switchingOneColorOffBringsThePaletteBack() {
        var colors = IslandHaloColors.standard
        colors.palette = Self.custom
        colors.usesSingleColor = true
        colors.usesSingleColor = false

        #expect(colors.effectivePalette == Self.custom)
    }

    // MARK: Hex

    @Test func hexRoundTripsAndReadsBothSpellings() {
        let color = IslandHaloRGB(rgb: 0xFFA51F)

        #expect(color.hex == "FFA51F")
        #expect(color == IslandHaloRGB.rgb255(255, 165, 31))
        #expect(IslandHaloRGB(hex: "FFA51F") == color)
        #expect(IslandHaloRGB(hex: "#ffa51f") == color)
        #expect(IslandHaloRGB(rgb: 0x000000).hex == "000000")
        #expect(IslandHaloRGB(rgb: 0xFFFFFF).hex == "FFFFFF")
    }

    @Test func hexRefusesAnythingThatIsNotSixHexDigits() {
        for bad in ["", "#", "FFF", "#12345", "1234567", "GGGGGG", "12 456", "ＦＦＦＦＦＦ", "0xFFAA", "#FFA51F00"] {
            #expect(IslandHaloRGB(hex: bad) == nil, "\(bad)")
        }
    }

    @Test func aPickedColorIsRoundedToWhatTheSettingsCanHold() {
        let picked = IslandHaloRGB(red: 0.33371, green: 0.90012, blue: 0.12345)
        let kept = picked.quantized

        #expect(kept == IslandHaloRGB(hex: picked.hex))
        #expect(kept.quantized == kept)
        // A color outside the range is clamped, never wrapped.
        #expect(IslandHaloRGB(red: 1.4, green: -0.2, blue: 0.5).hex == "FF0080")
    }

    // MARK: Saving

    @Test func theGlowColorsRoundTripThroughTheSettings() {
        let defaults = MemoryDefaults()
        var saved = NookDisplayPreferences()
        saved.haloColors.palette = Self.custom
        saved.haloColors.palette.musicUsesArtwork = false
        saved.haloColors.usesSingleColor = true
        saved.haloColors.singleColor = Self.teal

        saved.persist(for: .notch, defaults: defaults)

        #expect(NookDisplayPreferences.load(for: .notch, defaults: defaults).haloColors == saved.haloColors)
        // The other display kept its own.
        #expect(NookDisplayPreferences.load(for: .topBar, defaults: defaults).haloColors == .standard)
    }

    @Test func aPaletteThatLeavesNoticesAndMusicAloneRoundTrips() {
        let defaults = MemoryDefaults()
        var saved = NookDisplayPreferences()
        saved.haloColors.palette.approval = Self.rose

        saved.persist(for: .topBar, defaults: defaults)
        let loaded = NookDisplayPreferences.load(for: .topBar, defaults: defaults).haloColors.palette

        #expect(loaded == saved.haloColors.palette)
        #expect(loaded.notice == nil)
        #expect(loaded.music == nil)
    }

    @Test func nothingSavedLoadsTheStandardColors() {
        #expect(NookDisplayPreferences.load(for: .notch, defaults: MemoryDefaults()).haloColors == .standard)
    }

    /// The keys a change writes, with the edit's old value saved first.
    private static func keysWritten(
        _ change: (inout NookDisplayPreferences) -> Void
    ) -> Set<String> {
        let defaults = MemoryDefaults()
        let old = NookDisplayPreferences()
        old.persist(for: .notch, defaults: defaults)
        let before = defaults.all
        var new = old
        change(&new)

        new.persistChanges(from: old, for: .notch, defaults: defaults)

        let after = defaults.all
        return Set(before.keys).union(after.keys).filter { key in
            guard let was = before[key] as? NSObject, let now = after[key] as? NSObject else {
                return (before[key] == nil) != (after[key] == nil)
            }
            return !was.isEqual(now)
        }
    }

    @Test func eachGlowColorChangeWritesOnlyItsOwnKey() {
        #expect(Self.keysWritten { $0.haloColors.palette.approval = Self.rose } == ["nook.display.notch.haloPalette"])
        #expect(Self.keysWritten { $0.haloColors.palette.notice = Self.paper } == ["nook.display.notch.haloPalette"])
        #expect(Self.keysWritten { $0.haloColors.palette.musicUsesArtwork = false } == ["nook.display.notch.haloPalette"])
        #expect(Self.keysWritten { $0.haloColors.usesSingleColor = true } == ["nook.display.notch.haloSingleColorOn"])
        #expect(Self.keysWritten { $0.haloColors.singleColor = Self.teal } == ["nook.display.notch.haloSingleColor"])
        #expect(Self.keysWritten { $0.haloStyle = .vivid } == ["nook.display.notch.haloStyle"])
        #expect(Self.keysWritten { _ in }.isEmpty)
    }

    @Test func aDamagedPaletteEntryLosesOnlyWhatItGotWrong() {
        let damaged: [String: Any] = [
            "approval": "FF2D55",
            "question": "not a color",
            "completed": 42,
            "running": "#14C4A0",
            "notice": "",
            "music": "FFD23F",
            "musicUsesArtwork": "yes",
            "somethingElse": "FFFFFF",
        ]
        let palette = IslandHaloPalette(storageValue: damaged)

        #expect(palette.approval == Self.rose)
        #expect(palette.question == IslandHaloRGB.question)
        #expect(palette.completed == IslandHaloRGB.completed)
        #expect(palette.running == Self.teal)
        #expect(palette.notice == nil)
        #expect(palette.music == Self.gold)
        #expect(palette.musicUsesArtwork)
        #expect(IslandHaloPalette(storageValue: nil) == .standard)
        #expect(IslandHaloPalette(storageValue: [:]) == .standard)
    }

    @Test func aBadSingleColorOrPaletteInTheSettingsFallsBackQuietly() {
        let defaults = MemoryDefaults()
        defaults.set("zzzzzz", forKey: "nook.display.notch.haloSingleColor")
        defaults.set("a string, not a dictionary", forKey: "nook.display.notch.haloPalette")
        defaults.set("on", forKey: "nook.display.notch.haloSingleColorOn")

        #expect(NookDisplayPreferences.load(for: .notch, defaults: defaults).haloColors == .standard)
    }

    @Test func everyPaletteSurvivesItsOwnStorageForm() {
        for theme in IslandHaloTheme.all {
            #expect(IslandHaloPalette(storageValue: theme.palette.storageValue) == theme.palette, "\(theme.id)")
        }
    }

    // MARK: Themes

    @Test func theThemeTableIsWhole() {
        let themes = IslandHaloTheme.all
        let expectedCount = 11

        #expect(themes.count == expectedCount)
        #expect(Set(themes.map(\.id)).count == themes.count, "ids repeat")
        #expect(Set(themes.map(\.palette)).count == themes.count, "two themes share a palette")
        #expect(themes.first?.id == "default")
        #expect(themes.first?.palette == .standard)

        for theme in themes.dropFirst() {
            for moment in IslandHaloMoment.allCases {
                #expect(theme.palette.color(for: moment) != nil, "\(theme.id) has no \(moment) color")
            }
            #expect(theme.palette.musicUsesArtwork, "\(theme.id) should let the album art win")
            let swatchCount = IslandHaloMoment.allCases.count
            #expect(theme.swatches.count == swatchCount, "\(theme.id)")
            // Six colors that can be told apart at all.
            #expect(Set(theme.swatches).count == swatchCount, "\(theme.id) repeats a color")
        }
    }

    @Test func aDisplayIsOnAThemeWhileItsPaletteEqualsTheThemes() {
        #expect(IslandHaloTheme.matching(.standard)?.id == "default")
        #expect(IslandHaloTheme.matching(IslandHaloTheme.lagoon.palette)?.id == "lagoon")
        #expect(IslandHaloTheme.theme(id: "nightMarket") == IslandHaloTheme.nightMarket)
        #expect(IslandHaloTheme.theme(id: "nope") == nil)

        var edited = IslandHaloTheme.lagoon.palette
        edited.running = Self.rose
        #expect(IslandHaloTheme.matching(edited) == nil)
    }

    @Test func everyGlowAndRingLightStringExistsInEveryLanguage() throws {
        let prefix = "settings.appearance.nook.halo."
        let keys = IslandHaloTheme.all.map(\.titleKey)
            + IslandHaloMoment.allCases.map { "\(prefix)moment.\($0.rawValue)" }
            + ["single.title", "single.note", "single.color", "notice.own", "music.artwork", "reset", "note"].map { prefix + $0 }
            + ["nook.mirror.ringLight.tint"]
            + NookRingLightTint.allCases.map(\.titleKey)

        for language in ["en", "zh-Hans", "zh-Hant"] {
            let url = Self.repoRoot
                .appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String], "\(language) did not load")

            for key in keys {
                let value = table[key] ?? ""
                #expect(!value.isEmpty, "\(language) is missing \(key)")
            }
        }
    }

    // MARK: Templates leave the colors alone

    @Test func applyingATemplateKeepsTheUsersGlowColors() {
        var current = NookDisplayPreferences()
        current.haloColors.palette = Self.custom
        current.haloColors.usesSingleColor = true
        current.haloColors.singleColor = Self.teal

        for template in PersonalizationTemplate.all {
            let applied = template.applying(to: current)

            #expect(applied.haloColors == current.haloColors, "\(template.id)")
            #expect(applied.haloStyle == template.nook.haloStyle, "\(template.id)")
        }
    }

    @Test func aDisplayStaysOnItsTemplateWhenOnlyTheGlowColorsChange() {
        let template = PersonalizationTemplate.cockpit
        var setup = PersonalizationSetup(
            appearance: template.appearance,
            nook: template.applying(to: NookDisplayPreferences())
        )
        #expect(setup.appliedTemplateID == template.id)

        setup.nook.haloColors.palette = IslandHaloTheme.aurora.palette

        #expect(setup.appliedTemplateID == template.id)
    }

    @Test func undoingATemplateKeepsColorsPickedWhileOnIt() {
        let before = PersonalizationSetup(appearance: IslandAppearancePreferences(), nook: NookDisplayPreferences())
        var onTemplate = before.applying(.cockpit, keeping: nil).setup
        onTemplate.nook.haloColors.palette = IslandHaloTheme.bubblegum.palette

        let restored = onTemplate.undoing(before)

        #expect(restored.nook.haloColors.palette == IslandHaloTheme.bubblegum.palette)
        #expect(restored.nook.haloStyle == before.nook.haloStyle)
    }

    // MARK: Settings stage

    @Test func theSettingsStageFeedsTheResolverTheChosenColors() {
        var nook = NookDisplayPreferences()
        nook.haloColors.palette = Self.custom
        let setup = PersonalizationSetup(appearance: IslandAppearancePreferences(), nook: nook)

        let approval = PreviewScene.resolve(.approval, setup: setup, profile: .notch, policy: .full)
        let music = PreviewScene.resolve(.music, setup: setup, profile: .notch, policy: .full)
        let idle = PreviewScene.resolve(.idle, setup: setup, profile: .notch, policy: .full)

        #expect(approval.halo.palette == Self.custom)
        #expect(IslandHaloState.resolve(approval.halo).color == Self.rose)
        #expect(music.halo.isMusicPlaying)
        #expect(!idle.halo.isMusicPlaying)

        nook.haloColors.usesSingleColor = true
        nook.haloColors.singleColor = Self.teal
        let single = PreviewScene.resolve(
            .music,
            setup: PersonalizationSetup(appearance: IslandAppearancePreferences(), nook: nook),
            profile: .notch,
            policy: .full
        )
        #expect(IslandHaloState.resolve(single.halo).color == Self.teal)
    }

    // MARK: Harness

    @Test func theHarnessValuesKeepTheirColorsAndCanNameATheme() {
        let plain = IslandHaloState.forced(from: ["OPEN_ISLAND_HALO": "approval"])
        let themed = IslandHaloState.forced(from: ["OPEN_ISLAND_HALO": "approval", "OPEN_ISLAND_HALO_THEME": " signal "])
        let unknown = IslandHaloState.forced(from: ["OPEN_ISLAND_HALO": "running", "OPEN_ISLAND_HALO_THEME": "nope"])
        let notice = IslandHaloState.forced(from: ["OPEN_ISLAND_HALO": "notice:34C759"])
        let music = IslandHaloState.forced(from: ["OPEN_ISLAND_HALO": "music:FF2D55"])

        #expect(plain?.color == IslandHaloRGB.approval)
        #expect(themed?.color == IslandHaloTheme.signal.palette.approval)
        #expect(unknown?.color == IslandHaloRGB.running)
        #expect(notice?.color == IslandHaloRGB(hex: "34C759"))
        #expect(notice?.source == .notice)
        #expect(music?.color == IslandHaloRGB(hex: "FF2D55"))
        #expect(music?.source == .music)
    }

    /// `Tests/OpenIslandAppTests/<this file>` sits three levels below the root.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
