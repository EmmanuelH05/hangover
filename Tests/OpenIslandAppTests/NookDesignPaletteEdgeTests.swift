import Foundation
import Testing
@testable import OpenIslandApp

private typealias Samples = NookDesignSamples

/// A library with one palette, its id, and the colors added in order.
private func shelf(_ colors: [NookDesignColor] = [], named name: String = "Brand") -> (library: NookDesignLibrary, paletteID: UUID, swatchIDs: [UUID]) {
    let made = NookDesignLibrary.empty.addingPalette(named: name, now: Samples.day)!
    var library = made.library
    var ids: [UUID] = []
    for color in colors {
        guard case let .added(next, swatch) = library.addingColor(color, to: made.palette.id, now: Samples.day) else {
            Issue.record("\(color.hex()) was not added")
            continue
        }
        library = next
        ids.append(swatch.id)
    }
    return (library, made.palette.id, ids)
}

/// `count` colors that differ from each other.
private func distinctColors(_ count: Int) -> [NookDesignColor] {
    (0..<count).map { NookDesignColor(red: UInt8($0 % 256), green: UInt8($0 / 256), blue: 9) }
}

// MARK: - Names

@Suite struct NookDesignNameEdgeTests {
    @Test(arguments: ["", " ", "   ", "\t", "\n", "\n\n\n", " \n \t \r\n "])
    func aNameOfNothingButBlanksIsEmpty(text: String) {
        #expect(NookDesignLibrary.cleanName(text).isEmpty)
        #expect(NookDesignReferenceRules.cleanName(text).isEmpty)
    }

    @Test func everyKindOfLineBreakBecomesOneSpace() {
        #expect(NookDesignLibrary.cleanName("a\nb") == "a b")
        #expect(NookDesignLibrary.cleanName("a\r\nb") == "a b")
        #expect(NookDesignLibrary.cleanName("a\rb") == "a b")
        #expect(NookDesignLibrary.cleanName("a\n\n\nb") == "a b")
        #expect(NookDesignLibrary.cleanName("a\u{2028}b") == "a b")
        #expect(NookDesignLibrary.cleanName("\nPrimary\n") == "Primary")
        #expect(NookDesignReferenceRules.cleanName("a\r\nb") == "a b")
        #expect(NookDesignReferenceRules.cleanName("a\n\nb") == "a b")
    }

    @Test func theCutNeverLeavesASpaceAtTheEnd() {
        let limit = NookDesignLibrary.maxNameLength
        let fallsOnASpace = String(repeating: "a", count: limit - 1) + " " + "bcd"
        let cut = NookDesignLibrary.cleanName(fallsOnASpace)
        #expect(cut == String(repeating: "a", count: limit - 1))
        #expect(!cut.hasSuffix(" "))

        let manySpaces = String(repeating: "a", count: limit - 1) + String(repeating: " ", count: 5) + "z"
        #expect(NookDesignLibrary.cleanName(manySpaces) == String(repeating: "a", count: limit - 1))

        let refLimit = NookDesignReferenceRules.maxNameLength
        let refCut = NookDesignReferenceRules.cleanName(String(repeating: "b", count: refLimit - 1) + "  tail")
        #expect(refCut == String(repeating: "b", count: refLimit - 1))
    }

    @Test func aNameAtTheLimitIsKeptAndOneOverIsCut() {
        let limit = NookDesignLibrary.maxNameLength
        let exact = String(repeating: "n", count: limit)
        #expect(NookDesignLibrary.cleanName(exact) == exact)
        #expect(NookDesignLibrary.cleanName(exact + "n") == exact)
        #expect(NookDesignLibrary.cleanName("   " + exact + "   ") == exact)
        #expect(NookDesignLibrary.cleanName("   " + exact + "n") == exact)
    }

    @Test func theCutNeverSplitsALetterFromItsAccentOrAnEmoji() {
        let limit = NookDesignLibrary.maxNameLength
        let accent = String(repeating: "a", count: limit - 1) + "e\u{0301}" + "xyz"
        let cutAccent = NookDesignLibrary.cleanName(accent)
        #expect(cutAccent.count == limit)
        #expect(cutAccent.hasSuffix("e\u{0301}"))

        let family = "\u{1F469}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
        let emoji = String(repeating: "a", count: limit - 1) + family + "tail"
        let cutEmoji = NookDesignLibrary.cleanName(emoji)
        #expect(cutEmoji.hasSuffix(family))
        #expect(cutEmoji.count == limit)
    }

    @Test func aPaletteAndAColorAreNamedTheSameWay() {
        let (library, paletteID, ids) = shelf([Samples.orange])
        let text = "  Line one\r\nline two " + String(repeating: "x", count: 100)
        let palette = library.renamingPalette(paletteID, to: text).palette(paletteID)?.name
        let swatch = library.renamingSwatch(ids[0], to: text).palettes[0].swatches[0].name
        #expect(palette == swatch)
        #expect(palette?.hasPrefix("Line one line two xxx") == true)
        #expect(palette?.count == NookDesignLibrary.maxNameLength)
    }
}

// MARK: - Palettes: limits, renames, removal

@Suite struct NookDesignPaletteListEdgeTests {
    @Test func theLimitIsExactAndALostSpotCanBeTakenAgain() {
        var library = NookDesignLibrary.empty
        for index in 0..<NookDesignLibrary.maxPalettes {
            let made = library.addingPalette(named: "P\(index)")
            #expect(made != nil, "palette \(index + 1)")
            library = made?.library ?? library
        }
        #expect(library.palettes.count == NookDesignLibrary.maxPalettes)
        #expect(library.addingPalette(named: "No room") == nil)

        let gone = library.removingPalette(library.palettes[50].id)
        #expect(gone.palettes.count == NookDesignLibrary.maxPalettes - 1)
        #expect(gone.addingPalette(named: "Room again") != nil)
    }

    @Test func aPaletteMayHaveNoNameAndTwoMayShareOne() {
        var library = NookDesignLibrary.empty
        library = library.addingPalette(named: "")!.library
        library = library.addingPalette(named: "   ")!.library
        library = library.addingPalette(named: "Same")!.library
        library = library.addingPalette(named: "Same")!.library
        #expect(library.palettes.map(\.name) == ["", "", "Same", "Same"])
        #expect(Set(library.palettes.map(\.id)).count == 4)
    }

    @Test func renamingTouchesOnlyThePaletteNamed() {
        let one = shelf([Samples.orange, Samples.teal], named: "One")
        let first = one.paletteID
        let second = one.library.addingPalette(named: "Two")!
        let library = second.library

        let renamed = library.renamingPalette(first, to: "  First \n palette  ")
        #expect(renamed.palette(first)?.name == "First   palette")
        #expect(renamed.palette(second.palette.id)?.name == "Two")
        #expect(renamed.palette(first)?.swatches == library.palette(first)?.swatches)
        #expect(renamed.renamingPalette(first, to: "").palette(first)?.name == "")
        #expect(library.renamingPalette(UUID(), to: "Nobody") == library)
    }

    @Test func removingAPaletteLeavesTheActiveOneAloneUnlessItWasTheActiveOne() {
        var library = NookDesignLibrary.empty
        var ids: [UUID] = []
        for name in ["A", "B", "C"] {
            let made = library.addingPalette(named: name)!
            library = made.library
            ids.append(made.palette.id)
        }
        // C was added last. It is the active one.
        #expect(library.activePalette()?.id == ids[2])

        #expect(library.removingPalette(ids[0]).activePalette()?.id == ids[2])
        #expect(library.removingPalette(ids[1]).activePalette()?.id == ids[2])
        // The active one goes, and the first palette left takes over.
        #expect(library.removingPalette(ids[2]).activePalette()?.id == ids[0])
        #expect(library.removingPalette(UUID()) == library)
    }

    @Test func removingTheLastPaletteLeavesNothingActive() {
        let (library, paletteID, _) = shelf([Samples.orange])
        let empty = library.removingPalette(paletteID)
        #expect(empty.palettes.isEmpty)
        #expect(empty.activePalette() == nil)
        #expect(empty.activePaletteIDs.isEmpty)
        // Colors added to a shelf with no palette are refused, not lost somewhere.
        #expect(empty.addingColor(Samples.orange, to: paletteID) == .noPalette)
    }

    @Test func removingAPaletteTakesItsColorsAndNobodyElses() {
        let one = shelf([Samples.orange, Samples.teal])
        let first = one.paletteID
        let second = one.library.addingPalette(named: "Two")!
        guard case let .added(library, _) = second.library.addingColor(Samples.orange, to: second.palette.id) else {
            Issue.record("not added")
            return
        }

        let without = library.removingPalette(first)
        #expect(without.palettes.map(\.id) == [second.palette.id])
        #expect(without.palettes[0].swatches.map(\.color) == [Samples.orange])
    }

    @Test func choosingAPaletteThatIsNotThereChangesNothing() {
        let (library, _, _) = shelf([Samples.orange])
        #expect(library.settingActivePalette(UUID()) == library)
    }

    @Test func theActivePaletteOfAnotherCollectionIsNotTheGlobalOne() {
        let other = UUID()
        var library = NookDesignLibrary.empty
        let global = library.addingPalette(named: "Global")!
        library = global.library
        let apart = library.addingPalette(named: "Apart", in: other)!
        library = apart.library

        #expect(library.activePalette()?.id == global.palette.id)
        #expect(library.activePalette(in: other)?.id == apart.palette.id)
        #expect(library.palettes().map(\.name) == ["Global"])
        #expect(library.removingPalette(global.palette.id).activePalette()?.id == nil)
        #expect(library.removingPalette(global.palette.id).activePalette(in: other)?.id == apart.palette.id)
    }
}

// MARK: - Colors: duplicates, limits, order, favorites

@Suite struct NookDesignColorListEdgeTests {
    @Test func aColorOneStepAwayInAnyChannelIsNotADuplicate() {
        let base = Samples.orange
        let near = [
            NookDesignColor(red: 254, green: 136, blue: 0),
            NookDesignColor(red: 255, green: 135, blue: 0),
            NookDesignColor(red: 255, green: 137, blue: 0),
            NookDesignColor(red: 255, green: 136, blue: 1),
            NookDesignColor(red: 255, green: 136, blue: 0, alpha: 254),
            NookDesignColor(red: 255, green: 136, blue: 0, alpha: 0),
        ]
        let start = shelf([base])
        var library = start.library
        let paletteID = start.paletteID
        for color in near {
            guard case let .added(next, _) = library.addingColor(color, to: paletteID) else {
                Issue.record("\(color.hex()) was taken for a duplicate of \(base.hex())")
                continue
            }
            library = next
        }
        #expect(library.palette(paletteID)?.swatches.count == 1 + near.count)
        #expect(library.duplicateSwatchIDs(in: paletteID).isEmpty)
    }

    @Test func theSameColorWrittenAnotherWayIsADuplicate() {
        let (library, paletteID, ids) = shelf([Samples.orange])
        for text in ["#f80", "#FF8800", "ff8800", "rgb(255, 136, 0)", "hsl(32, 100%, 50%)", "#ff8800ff", "rgba(255,136,0,1)", "#F80F"] {
            let color = NookDesignColorParser.parse(text)!
            guard case let .duplicate(existing) = library.addingColor(color, to: paletteID) else {
                Issue.record("\(text) was not seen as the same color")
                continue
            }
            #expect(existing.id == ids[0])
        }
    }

    @Test func aDuplicateDoesNotRenameOrChangeWhatIsThere() {
        let start = shelf([Samples.orange])
        let paletteID = start.paletteID
        let ids = start.swatchIDs
        let library = start.library.renamingSwatch(ids[0], to: "Primary").togglingFavorite(ids[0])
        let again = library.addingColor(Samples.orange, named: "Other name", to: paletteID)
        guard case let .duplicate(existing) = again else {
            Issue.record("expected a duplicate")
            return
        }
        #expect(existing.name == "Primary")
        #expect(existing.isFavorite)
        #expect(library.palette(paletteID)?.swatches.count == 1)
    }

    @Test func thePaletteTakesExactlyItsLimitAndTheNextOneIsFull() {
        let limit = NookDesignLibrary.maxSwatchesPerPalette
        let colors = distinctColors(limit + 1)
        let start = shelf()
        var library = start.library
        let paletteID = start.paletteID
        for (index, color) in colors.prefix(limit).enumerated() {
            guard case let .added(next, _) = library.addingColor(color, to: paletteID) else {
                Issue.record("color \(index + 1) of \(limit) was refused")
                return
            }
            library = next
        }
        #expect(library.palette(paletteID)?.swatches.count == limit)
        #expect(library.addingColor(colors[limit], to: paletteID) == .full)
        // The full palette is unchanged, and another palette still has room.
        #expect(library.palette(paletteID)?.swatches.count == limit)
        let other = library.addingPalette(named: "Spare")!
        #expect(other.library.addingColor(colors[limit], to: other.palette.id) != .full)
    }

    @Test func aColorAlreadyInAFullPaletteIsADuplicateAndNotTheMessageThatItIsFull() {
        let limit = NookDesignLibrary.maxSwatchesPerPalette
        let start = shelf()
        var library = start.library
        let paletteID = start.paletteID
        for color in distinctColors(limit) {
            if case let .added(next, _) = library.addingColor(color, to: paletteID) { library = next }
        }
        #expect(library.palette(paletteID)?.swatches.count == limit)
        guard case .duplicate = library.addingColor(distinctColors(limit)[7], to: paletteID) else {
            Issue.record("expected a duplicate")
            return
        }
        // Removing one makes room for exactly one.
        let ids = library.palette(paletteID)!.swatches.map(\.id)
        let roomy = library.removingSwatch(ids[0])
        let fresh = NookDesignColor(red: 1, green: 2, blue: 250)
        guard case let .added(refilled, _) = roomy.addingColor(fresh, to: paletteID) else {
            Issue.record("a freed spot was not given")
            return
        }
        #expect(refilled.addingColor(NookDesignColor(red: 2, green: 2, blue: 250), to: paletteID) == .full)
    }

    @Test func aNamedColorAddedToAPaletteThatIsNotTheActiveOneGoesWhereItWasSent() {
        let one = shelf([Samples.orange], named: "First")
        let first = one.paletteID
        let second = one.library.addingPalette(named: "Second")!
        let library = second.library
        #expect(library.activePalette()?.id == second.palette.id)

        guard case let .added(next, swatch) = library.addingColor(Samples.teal, named: "  Teal  ", to: first) else {
            Issue.record("not added")
            return
        }
        #expect(next.palette(first)?.swatches.map(\.color) == [Samples.orange, Samples.teal])
        #expect(next.palette(second.palette.id)?.swatches.isEmpty == true)
        #expect(swatch.name == "Teal")
    }

    @Test func repeatsAreRemovedFromTheBackAndTheFirstKeepsItsNameAndMark() throws {
        let json = """
        { "version": 1, "palettes": [ { "id": "\(UUID().uuidString)", "name": "Hand made", "swatches": [
            { "color": "#FF8800", "name": "First", "isFavorite": true },
            { "color": "#2EC4B6" },
            { "color": "#f80", "name": "Second copy" },
            { "color": "rgb(255, 136, 0)" },
            { "color": "#FF880080" }
        ] } ] }
        """
        let library = try NookDesignLibraryFile.decode(Data(json.utf8)).library
        let palette = library.palettes[0]
        let repeats = library.duplicateSwatchIDs(in: palette.id)
        #expect(repeats == [palette.swatches[2].id, palette.swatches[3].id])

        let cleaned = library.removingDuplicates(in: palette.id).palettes[0]
        #expect(cleaned.swatches.map(\.name) == ["First", "", ""])
        #expect(cleaned.swatches[0].isFavorite)
        #expect(cleaned.swatches.map(\.color.alpha) == [255, 255, 128])
        #expect(library.removingDuplicates(in: UUID()) == library)
        #expect(cleaned == library.removingDuplicates(in: palette.id).removingDuplicates(in: palette.id).palettes[0])
    }

    @Test func movingNeedsNoPaletteTheSwatchIsNotIn() {
        let one = shelf([Samples.orange, Samples.teal], named: "One")
        let first = one.paletteID
        let firstIDs = one.swatchIDs
        let second = one.library.addingPalette(named: "Two")!
        guard case let .added(library, swatch) = second.library.addingColor(Samples.ink, to: second.palette.id) else { return }

        // Moving a swatch of the second palette to the front touches that palette alone.
        let moved = library.movingSwatch(swatch.id, to: 0)
        #expect(moved.palette(first)?.swatches.map(\.id) == firstIDs)
        #expect(moved.palette(second.palette.id)?.swatches.map(\.id) == [swatch.id])
    }

    @Test func aLoneSwatchAndTheEndsOfTheListDoNotMove() {
        let (library, paletteID, ids) = shelf([Samples.orange, Samples.teal, Samples.ink])
        #expect(library.movingSwatch(ids[1], to: 1) == library)
        #expect(library.nudgingSwatch(ids[0], by: -1) == library)
        #expect(library.nudgingSwatch(ids[2], by: 1) == library)
        #expect(library.nudgingSwatch(ids[1], by: 0) == library)
        // A nudge farther than the list is long stops at the end.
        #expect(library.nudgingSwatch(ids[0], by: 50).palette(paletteID)?.swatches.map(\.id) == [ids[1], ids[2], ids[0]])
        #expect(library.nudgingSwatch(ids[2], by: -50).palette(paletteID)?.swatches.map(\.id) == [ids[2], ids[0], ids[1]])
        #expect(library.nudgingSwatch(UUID(), by: 1) == library)

        let (single, _, singleIDs) = shelf([Samples.orange])
        #expect(single.movingSwatch(singleIDs[0], to: 0) == single)
        #expect(single.movingSwatch(singleIDs[0], to: 99) == single)
        #expect(single.movingSwatch(singleIDs[0], to: Int.min) == single)
        #expect(single.movingSwatch(singleIDs[0], to: Int.max) == single)
    }

    @Test func favoritesComeFirstInTheOrderTheyAlreadyHadAndTheRestFollowInTheirs() {
        let (library, paletteID, ids) = shelf(distinctColors(6))
        let marked = library.togglingFavorite(ids[4]).togglingFavorite(ids[1]).togglingFavorite(ids[5])
        let swatches = marked.palette(paletteID)!.swatches

        #expect(NookDesignLibrary.compactOrder(swatches).map(\.id) == [ids[1], ids[4], ids[5], ids[0], ids[2], ids[3]])
        #expect(NookDesignLibrary.compactOrder([]).isEmpty)
        // With no favorite, or only favorites, the order is the palette's own.
        #expect(NookDesignLibrary.compactOrder(library.palette(paletteID)!.swatches).map(\.id) == ids)
        let all = ids.reduce(library) { $0.togglingFavorite($1) }
        #expect(NookDesignLibrary.compactOrder(all.palette(paletteID)!.swatches).map(\.id) == ids)
    }

    @Test func aFavoriteKeepsItsMarkThroughARenameAMoveAndAnotherColorsRemoval() {
        let start = shelf(distinctColors(4))
        let paletteID = start.paletteID
        let ids = start.swatchIDs
        var library = start.library.togglingFavorite(ids[2])
        library = library.renamingSwatch(ids[2], to: "Keep").movingSwatch(ids[2], to: 0).removingSwatch(ids[0])
        let swatch = library.palette(paletteID)!.swatches.first { $0.id == ids[2] }
        #expect(swatch?.isFavorite == true)
        #expect(swatch?.name == "Keep")
        #expect(library.togglingFavorite(UUID()) == library)
    }
}

// MARK: - Recent picks

@Suite struct NookDesignRecentEdgeTests {
    @Test func theTwelfthPickIsKeptAndThirteenthPushesOutTheOldest() {
        var library = NookDesignLibrary.empty
        let colors = distinctColors(NookDesignLibrary.maxRecents + 1)
        for color in colors.prefix(NookDesignLibrary.maxRecents) {
            library = library.recordingRecent(color, now: Samples.day)
        }
        #expect(library.recents().count == NookDesignLibrary.maxRecents)
        #expect(library.recents().last?.color == colors[0])

        library = library.recordingRecent(colors[NookDesignLibrary.maxRecents], now: Samples.day)
        #expect(library.recents().count == NookDesignLibrary.maxRecents)
        #expect(library.recents().first?.color == colors[NookDesignLibrary.maxRecents])
        #expect(library.recents().last?.color == colors[1])
        #expect(!library.recents().contains { $0.color == colors[0] })
    }

    @Test func pickingTheOldestColorAgainKeepsAllTwelveAndMovesItUp() {
        var library = NookDesignLibrary.empty
        let colors = distinctColors(NookDesignLibrary.maxRecents)
        for color in colors { library = library.recordingRecent(color, now: Samples.day) }
        let oldest = library.recents().last!

        let again = library.recordingRecent(colors[0], now: Samples.day)
        #expect(again.recents().count == NookDesignLibrary.maxRecents)
        #expect(again.recents().first?.id == oldest.id)
        #expect(again.recents().first?.color == colors[0])
        #expect(again.recents().map(\.color) == [colors[0]] + colors.dropFirst().reversed())
    }

    @Test func aColorThatDiffersInAlphaOrByOneStepIsAnotherRecentColor() {
        var library = NookDesignLibrary.empty
        library = library.recordingRecent(Samples.orange)
        library = library.recordingRecent(NookDesignColor(red: 255, green: 136, blue: 0, alpha: 254))
        library = library.recordingRecent(NookDesignColor(red: 255, green: 136, blue: 1))
        #expect(library.recents().count == 3)
        library = library.recordingRecent(Samples.orange)
        #expect(library.recents().count == 3)
        #expect(library.recents().first?.color == Samples.orange)
    }

    @Test func clearingAndRemovingTouchOnlyWhatTheyNameAndAnEmptyListStaysEmpty() {
        let other = UUID()
        var library = NookDesignLibrary.empty
        library = library.recordingRecent(Samples.orange)
        library = library.recordingRecent(Samples.teal, in: other)

        let cleared = library.clearingRecents()
        #expect(cleared.recents().isEmpty)
        #expect(cleared.recents(in: other).count == 1)
        #expect(NookDesignLibrary.empty.clearingRecents() == .empty)
        #expect(library.removingRecent(UUID()) == library)
        #expect(library.removingRecent(library.recents()[0].id).recents().isEmpty)
    }

    @Test func sanitizingKeepsExactlyTwelveAndCutsTheThirteenth() {
        var library = NookDesignLibrary.empty
        let colors = distinctColors(NookDesignLibrary.maxRecents + 1)
        library.recents = colors.map {
            NookDesignRecentColor(id: UUID(), collectionID: NookDesignCollection.globalID, color: $0, pickedAt: Samples.day)
        }
        let clean = library.sanitized()
        #expect(clean.recents.map(\.color) == Array(colors.prefix(NookDesignLibrary.maxRecents)))

        library.recents.removeLast()
        #expect(library.sanitized().recents.count == NookDesignLibrary.maxRecents)
    }

    @Test func sanitizingKeepsOneRecentPerColorAndNeverTheSameIdTwice() {
        let id = UUID()
        var library = NookDesignLibrary.empty
        let global = NookDesignCollection.globalID
        library.recents = [
            NookDesignRecentColor(id: id, collectionID: global, color: Samples.orange, pickedAt: Samples.day),
            NookDesignRecentColor(id: UUID(), collectionID: global, color: Samples.orange, pickedAt: Samples.day),
            NookDesignRecentColor(id: id, collectionID: global, color: Samples.teal, pickedAt: Samples.day),
            NookDesignRecentColor(id: UUID(), collectionID: UUID(), color: Samples.orange, pickedAt: Samples.day),
        ]
        let clean = library.sanitized().recents
        #expect(clean.count == 2)
        #expect(clean.map(\.color) == [Samples.orange, Samples.orange])
        #expect(Set(clean.map(\.id)).count == 2)
    }
}

// MARK: - Sanitizing at the limits

@Suite struct NookDesignSanitizeEdgeTests {
    @Test func theLimitsAreKeptExactlyAndOneOverIsCut() {
        func palette(swatches: Int) -> NookDesignPalette {
            NookDesignPalette(
                id: UUID(), collectionID: NookDesignCollection.globalID, name: "P",
                swatches: distinctColors(swatches).map {
                    NookDesignSwatch(id: UUID(), color: $0, name: "", isFavorite: false, addedAt: Samples.day)
                },
                createdAt: Samples.day
            )
        }
        var library = NookDesignLibrary.empty
        library.palettes = [palette(swatches: NookDesignLibrary.maxSwatchesPerPalette), palette(swatches: NookDesignLibrary.maxSwatchesPerPalette + 1)]
        let clean = library.sanitized()
        #expect(clean.palettes.map(\.swatches.count) == [NookDesignLibrary.maxSwatchesPerPalette, NookDesignLibrary.maxSwatchesPerPalette])

        library.palettes = (0..<NookDesignLibrary.maxPalettes).map { _ in palette(swatches: 1) }
        #expect(library.sanitized().palettes.count == NookDesignLibrary.maxPalettes)
        library.palettes.append(palette(swatches: 1))
        #expect(library.sanitized().palettes.count == NookDesignLibrary.maxPalettes)
    }

    @Test func anActivePaletteThatIsGoneOrBelongsToAnotherCollectionIsDropped() {
        let other = UUID()
        var library = NookDesignLibrary.empty
        let global = library.addingPalette(named: "Global")!
        library = global.library
        library.activePaletteIDs[NookDesignCollection.globalID.uuidString] = UUID()
        library.activePaletteIDs[other.uuidString] = global.palette.id

        let clean = library.sanitized()
        #expect(clean.activePaletteIDs.isEmpty)
        // With no usable choice the first palette of the collection is the active one.
        #expect(clean.activePalette()?.id == global.palette.id)
    }

    @Test func aRepeatedIdGetsAFreshOneOnEveryLevel() {
        let id = UUID()
        let swatchID = UUID()
        func swatch() -> NookDesignSwatch {
            NookDesignSwatch(id: swatchID, color: NookDesignColor(red: UInt8.random(in: 0...255), green: 1, blue: 1), name: "", isFavorite: false, addedAt: Samples.day)
        }
        var library = NookDesignLibrary.empty
        library.palettes = [
            NookDesignPalette(id: id, collectionID: NookDesignCollection.globalID, name: "A", swatches: [swatch()], createdAt: Samples.day),
            NookDesignPalette(id: id, collectionID: NookDesignCollection.globalID, name: "B", swatches: [swatch()], createdAt: Samples.day),
        ]
        let clean = library.sanitized()
        #expect(clean.palettes.count == 2)
        #expect(Set(clean.palettes.map(\.id)).count == 2)
        #expect(Set(clean.palettes.flatMap(\.swatches).map(\.id)).count == 2)
    }
}

// MARK: - The saved file: shapes the lenient reader must not lose silently

@Suite struct NookDesignFileEdgeTests {
    private func decode(_ json: String) throws -> (library: NookDesignLibrary, skipped: Int) {
        try NookDesignLibraryFile.decode(Data(json.utf8))
    }

    @Test(arguments: [
        "{ \"palettes\": \"oops\" }", "{ \"palettes\": 5 }", "{ \"palettes\": { \"a\": 1 } }", "{ \"palettes\": true }",
    ])
    func aShelfThatIsNotAListIsCountedAsLeftOutAndNeverSilentlyDropped(json: String) throws {
        let result = try decode(json)
        #expect(result.library.palettes.isEmpty)
        // The loader keeps a copy of the file when something was left out.
        #expect(result.skipped == 1, "\(json)")
    }

    @Test func aNullShelfIsAnEmptyShelf() throws {
        let result = try decode("{ \"palettes\": null, \"recents\": null }")
        #expect(result.library == .empty)
        #expect(result.skipped == 0)
    }

    @Test func swatchesAndRecentsThatAreNotListsAreCountedToo() throws {
        let swatches = try decode("{ \"palettes\": [ { \"name\": \"A\", \"swatches\": \"oops\" } ] }")
        #expect(swatches.library.palettes.count == 1)
        #expect(swatches.skipped == 1)
        let recents = try decode("{ \"recents\": { \"color\": \"#fff\" } }")
        #expect(recents.library.recents.isEmpty)
        #expect(recents.skipped == 1)
    }

    @Test func aKeyThatIsMissingIsNotLeftOut() throws {
        let bare = try decode("{ \"version\": 1 }")
        #expect(bare.skipped == 0)
        let palette = try decode("{ \"palettes\": [ { \"name\": \"A\" } ] }")
        #expect(palette.skipped == 0)
        #expect(palette.library.palettes.count == 1)
    }

    @Test func theVersionIsReadAsAWholeNumberOrTakenForTheCurrentOne() throws {
        #expect(try decode("{ }").library.version == NookDesignLibrary.currentVersion)
        #expect(try decode("{ \"version\": 7 }").library.version == 7)
        #expect(try decode("{ \"version\": 0 }").library.version == 0)
        #expect(try decode("{ \"version\": -3 }").library.version == -3)
        #expect(try decode("{ \"version\": \"7\" }").library.version == NookDesignLibrary.currentVersion)
        #expect(try decode("{ \"version\": 2.5 }").library.version == NookDesignLibrary.currentVersion)
        #expect(try decode("{ \"version\": 2000000000 }").library.version == 2_000_000_000)
    }

    @Test func aDateThatDoesNotReadIsTheEpochAndIsCountedAndNoItemIsLost() throws {
        let json = """
        { "palettes": [ { "name": "A", "createdAt": "yesterday", "swatches": [
            { "color": "#fff", "addedAt": "2026-10-09T12:00:00.5Z" }, { "color": "#000", "addedAt": 12 } ] } ] }
        """
        let result = try decode(json)
        // "yesterday" and the number 12 do not read. A fraction of a second does.
        #expect(result.skipped == 2)
        #expect(result.library.palettes[0].createdAt == Date(timeIntervalSince1970: 0))
        #expect(result.library.palettes[0].swatches.count == 2)
        #expect(result.library.palettes[0].swatches[0].addedAt == Date(timeIntervalSince1970: 1_791_547_200.5))
    }

    @Test func aSavedLibraryIsByteForByteTheSameEachTimeItIsWritten() throws {
        let start = shelf([Samples.orange, Samples.teal, Samples.scrim])
        let marked = start.library.togglingFavorite(start.swatchIDs[1]).recordingRecent(Samples.ink, now: Samples.day)
        #expect(try NookDesignLibraryFile.encode(marked) == NookDesignLibraryFile.encode(marked))
    }

    @Test func aLibraryAtEveryLimitWritesAndReadsBack() throws {
        var library = NookDesignLibrary.empty
        for index in 0..<NookDesignLibrary.maxPalettes {
            var made = library.addingPalette(named: "P\(index)", now: Samples.day)!
            if index == 0 {
                for color in distinctColors(NookDesignLibrary.maxSwatchesPerPalette) {
                    if case let .added(next, _) = made.library.addingColor(color, to: made.palette.id, now: Samples.day) {
                        made.library = next
                    }
                }
            }
            library = made.library
        }
        for color in distinctColors(NookDesignLibrary.maxRecents) { library = library.recordingRecent(color, now: Samples.day) }

        let read = try NookDesignLibraryFile.decode(NookDesignLibraryFile.encode(library))
        #expect(read.library == library)
        #expect(read.library.sanitized() == library)
        #expect(read.skipped == 0)
    }

    @Test func aNameWithQuotesNewlinesAndUnicodeSurvivesTheFile() throws {
        let start = shelf([Samples.orange])
        let paletteID = start.paletteID
        let ids = start.swatchIDs
        var library = start.library
        let tricky = "Say \"hi\" \\ / \u{1F3A8} \u{4E2D}\u{6587}"
        library = library.renamingPalette(paletteID, to: tricky).renamingSwatch(ids[0], to: tricky)
        let read = try NookDesignLibraryFile.decode(NookDesignLibraryFile.encode(library)).library
        #expect(read.palettes[0].name == tricky)
        #expect(read.palettes[0].swatches[0].name == tricky)
    }
}
