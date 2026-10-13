import Foundation
import Testing
@testable import OpenIslandApp

private typealias Samples = NookDesignSamples

/// A library with one palette and its id.
private func libraryWithPalette(named name: String = "Brand") -> (NookDesignLibrary, UUID) {
    let made = NookDesignLibrary.empty.addingPalette(named: name, now: Samples.day)!
    return (made.library, made.palette.id)
}

private func added(_ outcome: NookDesignAddOutcome) -> (NookDesignLibrary, NookDesignSwatch)? {
    if case let .added(library, swatch) = outcome { return (library, swatch) }
    return nil
}

/// A library with the given colors in one palette.
private func makeLibrary(with colors: [NookDesignColor]) -> (NookDesignLibrary, UUID, [UUID]) {
    let made = libraryWithPalette()
    var library = made.0
    let paletteID = made.1
    var ids: [UUID] = []
    for color in colors {
        let step = added(library.addingColor(color, to: paletteID, now: Samples.day))!
        library = step.0
        ids.append(step.1.id)
    }
    return (library, paletteID, ids)
}

// MARK: - Editing rules

@Suite struct NookDesignPaletteRuleTests {
    @Test func aNewPaletteIsEmptyGlobalAndActive() {
        let (library, id) = libraryWithPalette(named: "  Brand  ")
        let palette = library.palette(id)

        #expect(palette?.name == "Brand")
        #expect(palette?.swatches.isEmpty == true)
        #expect(palette?.collectionID == NookDesignCollection.globalID)
        #expect(library.activePalette()?.id == id)
    }

    @Test func noMorePalettesThanTheLimit() {
        var library = NookDesignLibrary.empty
        for index in 0..<NookDesignLibrary.maxPalettes {
            library = library.addingPalette(named: "P\(index)")!.library
        }
        #expect(library.palettes.count == NookDesignLibrary.maxPalettes)
        #expect(library.addingPalette(named: "One too many") == nil)
    }

    @Test func addingAColorPutsItAtTheEnd() {
        let (library, paletteID, ids) = makeLibrary(with: [Samples.orange, Samples.teal])
        let swatches = library.palette(paletteID)?.swatches ?? []

        #expect(swatches.map(\.color) == [Samples.orange, Samples.teal])
        #expect(swatches.map(\.id) == ids)
        #expect(swatches.allSatisfy { !$0.isFavorite && $0.name.isEmpty })
    }

    @Test func theSameColorTwiceIsADuplicateAndIsNotAdded() {
        let (library, paletteID, ids) = makeLibrary(with: [Samples.orange])
        let again = library.addingColor(NookDesignColor(red: 255, green: 136, blue: 0), named: "Again", to: paletteID)

        guard case let .duplicate(existing) = again else {
            Issue.record("expected a duplicate, got \(again)")
            return
        }
        #expect(existing.id == ids[0])
        #expect(library.existingSwatch(Samples.orange, in: paletteID)?.id == ids[0])
    }

    @Test func theSameColorWithAnotherAlphaIsNotADuplicate() {
        let (library, paletteID, _) = makeLibrary(with: [NookDesignColor(red: 0, green: 0, blue: 0)])
        #expect(added(library.addingColor(Samples.scrim, to: paletteID)) != nil)
    }

    @Test func theSameColorMayLiveInTwoPalettes() {
        let (first, paletteID, _) = makeLibrary(with: [Samples.orange])
        let second = first.addingPalette(named: "Other")!
        #expect(added(second.library.addingColor(Samples.orange, to: second.palette.id)) != nil)
        #expect(second.library.existingSwatch(Samples.orange, in: paletteID) != nil)
    }

    @Test func aColorForAPaletteThatIsGoneIsRefused() {
        #expect(NookDesignLibrary.empty.addingColor(Samples.orange, to: UUID()) == .noPalette)
    }

    @Test func aFullPaletteTakesNoMore() {
        let made = libraryWithPalette()
        var library = made.0
        let paletteID = made.1
        for index in 0..<NookDesignLibrary.maxSwatchesPerPalette {
            let color = NookDesignColor(red: UInt8(index % 256), green: UInt8(index / 256), blue: 7)
            library = added(library.addingColor(color, to: paletteID))!.0
        }
        #expect(library.addingColor(NookDesignColor(red: 1, green: 2, blue: 250), to: paletteID) == .full)
    }

    @Test func aNameIsTrimmedCutAndKeptOnOneLine() {
        let (library, _, ids) = makeLibrary(with: [Samples.orange])
        let renamed = library.renamingSwatch(ids[0], to: "  Primary\naccent  ")
        #expect(renamed.palettes[0].swatches[0].name == "Primary accent")

        let long = String(repeating: "x", count: 200)
        let cut = library.renamingSwatch(ids[0], to: long)
        #expect(cut.palettes[0].swatches[0].name.count == NookDesignLibrary.maxNameLength)
    }

    @Test func favoriteTogglesAndComesFirstInTheCompactRow() {
        let (library, paletteID, ids) = makeLibrary(with: [Samples.orange, Samples.teal, Samples.ink])
        let marked = library.togglingFavorite(ids[2])
        let swatches = marked.palette(paletteID)?.swatches ?? []

        #expect(swatches.map(\.isFavorite) == [false, false, true])
        // The palette keeps its own order. Only the compact row moves it.
        #expect(swatches.map(\.id) == ids)
        #expect(NookDesignLibrary.compactOrder(swatches).map(\.id) == [ids[2], ids[0], ids[1]])
        #expect(marked.togglingFavorite(ids[2]) == library)
    }

    @Test func movingASwatchReordersAndClamps() {
        let (library, paletteID, ids) = makeLibrary(with: [Samples.orange, Samples.teal, Samples.ink])
        func order(_ library: NookDesignLibrary) -> [UUID] { library.palette(paletteID)?.swatches.map(\.id) ?? [] }

        #expect(order(library.movingSwatch(ids[0], to: 2)) == [ids[1], ids[2], ids[0]])
        #expect(order(library.movingSwatch(ids[2], to: 0)) == [ids[2], ids[0], ids[1]])
        #expect(order(library.movingSwatch(ids[0], to: 99)) == [ids[1], ids[2], ids[0]])
        #expect(order(library.movingSwatch(ids[1], to: -5)) == [ids[1], ids[0], ids[2]])
        #expect(order(library.nudgingSwatch(ids[1], by: 1)) == [ids[0], ids[2], ids[1]])
        #expect(order(library.nudgingSwatch(ids[0], by: -1)) == ids)
        #expect(library.movingSwatch(UUID(), to: 0) == library)
    }

    @Test func removingASwatchLeavesTheRest() {
        let (library, paletteID, ids) = makeLibrary(with: [Samples.orange, Samples.teal])
        let removed = library.removingSwatch(ids[0])
        #expect(removed.palette(paletteID)?.swatches.map(\.id) == [ids[1]])
        #expect(removed.removingSwatch(UUID()) == removed)
    }

    @Test func repeatsInAHandEditedPaletteAreFoundAndCanBeRemoved() {
        let made = libraryWithPalette()
        var library = made.0
        let paletteID = made.1
        let colors = [Samples.orange, Samples.teal, Samples.orange, Samples.ink, Samples.teal, Samples.orange]
        let swatches = colors.map {
            NookDesignSwatch(id: UUID(), color: $0, name: "", isFavorite: false, addedAt: Samples.day)
        }
        library.palettes[0].swatches = swatches

        // The first of each color stays. The later ones are the repeats.
        #expect(library.duplicateSwatchIDs(in: paletteID) == [swatches[2].id, swatches[4].id, swatches[5].id])
        let cleaned = library.removingDuplicates(in: paletteID)
        #expect(cleaned.palette(paletteID)?.swatches.map(\.id) == [swatches[0].id, swatches[1].id, swatches[3].id])
        #expect(cleaned.duplicateSwatchIDs(in: paletteID).isEmpty)
    }

    @Test func removingTheActivePaletteFallsBackToTheFirstLeft() {
        let first = NookDesignLibrary.empty.addingPalette(named: "One")!
        let second = first.library.addingPalette(named: "Two")!
        #expect(second.library.activePalette()?.id == second.palette.id)

        let removed = second.library.removingPalette(second.palette.id)
        #expect(removed.activePalette()?.id == first.palette.id)
        #expect(removed.removingPalette(first.palette.id).activePalette() == nil)

        let chosen = second.library.settingActivePalette(first.palette.id)
        #expect(chosen.activePalette()?.id == first.palette.id)
        #expect(chosen.renamingPalette(first.palette.id, to: " Uno ").palette(first.palette.id)?.name == "Uno")
    }

    @Test func aPaletteOfAnotherCollectionIsKeptApart() {
        let project = UUID()
        let global = NookDesignLibrary.empty.addingPalette(named: "Everywhere")!
        let both = global.library.addingPalette(named: "Project", in: project)!

        #expect(both.library.palettes().map(\.name) == ["Everywhere"])
        #expect(both.library.palettes(in: project).map(\.name) == ["Project"])
        // Each collection has its own active palette.
        #expect(both.library.activePalette()?.id == global.palette.id)
        #expect(both.library.activePalette(in: project)?.id == both.palette.id)
    }

    // MARK: Recent picks

    @Test func recentPicksAreNewestFirstAndNeverRepeat() {
        var library = NookDesignLibrary.empty
        library = library.recordingRecent(Samples.orange)
        library = library.recordingRecent(Samples.teal)
        let orangeID = library.recents[1].id
        library = library.recordingRecent(Samples.orange)

        #expect(library.recents().map(\.color) == [Samples.orange, Samples.teal])
        // A color picked again keeps its id, which keeps its row the same row.
        #expect(library.recents[0].id == orangeID)
    }

    @Test func onlyTheNewestRecentPicksAreKept() {
        var library = NookDesignLibrary.empty
        for index in 0..<(NookDesignLibrary.maxRecents + 5) {
            library = library.recordingRecent(NookDesignColor(red: UInt8(index), green: 0, blue: 0))
        }
        #expect(library.recents.count == NookDesignLibrary.maxRecents)
        #expect(library.recents.first?.color.red == UInt8(NookDesignLibrary.maxRecents + 4))
        #expect(library.recents.last?.color.red == 5)
    }

    @Test func recentPicksOfTwoCollectionsDoNotCrowdEachOtherOut() {
        let project = UUID()
        var library = NookDesignLibrary.empty.recordingRecent(Samples.orange, in: project)
        for index in 0..<NookDesignLibrary.maxRecents {
            library = library.recordingRecent(NookDesignColor(red: UInt8(index), green: 9, blue: 9))
        }
        #expect(library.recents().count == NookDesignLibrary.maxRecents)
        #expect(library.recents(in: project).map(\.color) == [Samples.orange])
        #expect(library.clearingRecents().recents.map(\.color) == [Samples.orange])
    }

    @Test func aRecentPickCanBeRemoved() {
        let library = NookDesignLibrary.empty.recordingRecent(Samples.orange).recordingRecent(Samples.teal)
        let removed = library.removingRecent(library.recents[0].id)
        #expect(removed.recents.map(\.color) == [Samples.orange])
    }

    // MARK: Cleaning up

    @Test func sanitizingKeepsEveryColorAndGivesRepeatedIdsNewOnes() {
        let sharedSwatch = UUID()
        let sharedPalette = UUID()
        func swatch(_ color: NookDesignColor, _ name: String) -> NookDesignSwatch {
            NookDesignSwatch(id: sharedSwatch, color: color, name: name, isFavorite: false, addedAt: Samples.day)
        }
        func palette(_ swatches: [NookDesignSwatch]) -> NookDesignPalette {
            NookDesignPalette(
                id: sharedPalette, collectionID: NookDesignCollection.globalID,
                name: "  Same  ", swatches: swatches, createdAt: Samples.day
            )
        }
        var damaged = NookDesignLibrary()
        damaged.palettes = [palette([swatch(Samples.orange, " a\nb ")]), palette([swatch(Samples.teal, "c")])]
        damaged.activePaletteIDs = [NookDesignCollection.globalID.uuidString: UUID()]

        let clean = damaged.sanitized()
        let swatches = clean.palettes.flatMap(\.swatches)

        #expect(clean.palettes.count == 2)
        #expect(Set(clean.palettes.map(\.id)).count == 2)
        #expect(clean.palettes[0].id == sharedPalette)
        #expect(swatches.map(\.color) == [Samples.orange, Samples.teal])
        #expect(Set(swatches.map(\.id)).count == 2)
        #expect(swatches[0].name == "a b")
        #expect(clean.palettes[0].name == "Same")
        // An active palette that does not exist is dropped, and the first
        // palette stands in.
        #expect(clean.activePaletteIDs.isEmpty)
        #expect(clean.activePalette()?.id == sharedPalette)
    }

    @Test func sanitizingCutsWhatIsOverALimit() {
        var library = NookDesignLibrary()
        let swatches = (0..<(NookDesignLibrary.maxSwatchesPerPalette + 10)).map { index in
            NookDesignSwatch(
                id: UUID(), color: NookDesignColor(red: UInt8(index % 256), green: UInt8(index / 256), blue: 0),
                name: "", isFavorite: false, addedAt: Samples.day
            )
        }
        library.palettes = [NookDesignPalette(
            id: UUID(), collectionID: NookDesignCollection.globalID, name: "Big", swatches: swatches, createdAt: Samples.day
        )]
        library.recents = (0..<40).map { index in
            NookDesignRecentColor(
                id: UUID(), collectionID: NookDesignCollection.globalID,
                color: NookDesignColor(red: UInt8(index / 2), green: 0, blue: 0), pickedAt: Samples.day
            )
        }

        let clean = library.sanitized()
        #expect(clean.palettes[0].swatches.count == NookDesignLibrary.maxSwatchesPerPalette)
        // Twenty colors, each twice: a repeat is dropped, then the limit cuts.
        #expect(clean.recents.count == NookDesignLibrary.maxRecents)
        #expect(Set(clean.recents.map(\.color)).count == NookDesignLibrary.maxRecents)
    }
}

// MARK: - The saved file

@Suite struct NookDesignPaletteFileTests {
    private func sampleLibrary() -> NookDesignLibrary {
        let made = makeLibrary(with: [Samples.orange, Samples.scrim])
        let ids = made.2
        return made.0
            .renamingSwatch(ids[0], to: "Primary")
            .togglingFavorite(ids[0])
            .recordingRecent(Samples.teal, now: Samples.day)
    }

    @Test func aLibraryWritesAndReadsBackTheSame() throws {
        let library = sampleLibrary()
        let read = try NookDesignLibraryFile.decode(NookDesignLibraryFile.encode(library))

        #expect(read.library == library)
        #expect(read.skipped == 0)
    }

    @Test func theFileIsVersionedAndKeepsColorsAsHexText() throws {
        let data = try NookDesignLibraryFile.encode(sampleLibrary())
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let palettes = try #require(json["palettes"] as? [[String: Any]])
        let swatches = try #require(palettes.first?["swatches"] as? [[String: Any]])
        let recents = try #require(json["recents"] as? [[String: Any]])

        #expect(json["version"] as? Int == NookDesignLibrary.currentVersion)
        #expect(swatches.map { $0["color"] as? String } == ["#FF8800", "#00000080"])
        #expect(swatches[0]["name"] as? String == "Primary")
        #expect(swatches[0]["isFavorite"] as? Bool == true)
        // Every saved item carries its own id, and the collection it is in.
        #expect(swatches.allSatisfy { UUID(uuidString: $0["id"] as? String ?? "") != nil })
        #expect(palettes[0]["collectionID"] as? String == NookDesignCollection.globalID.uuidString)
        #expect(recents[0]["collectionID"] as? String == NookDesignCollection.globalID.uuidString)
        #expect((json["activePaletteIDs"] as? [String: String])?[NookDesignCollection.globalID.uuidString] != nil)
    }

    @Test func oneBadColorCostsThatColorAlone() throws {
        let json = """
        {
          "version": 1,
          "palettes": [
            { "id": "\(UUID().uuidString)", "name": "Brand", "swatches": [
                { "color": "#FF8800", "name": "Good" },
                { "color": "not a color", "name": "Bad" },
                { "name": "No color at all" },
                "a string where a swatch should be",
                { "color": "rgb(46, 196, 182)" }
            ] },
            "a string where a palette should be"
          ],
          "recents": [ { "color": "#111111" }, { "color": 7 } ]
        }
        """
        let read = try NookDesignLibraryFile.decode(Data(json.utf8))
        let palette = try #require(read.library.palettes.first)

        #expect(read.library.palettes.count == 1)
        #expect(palette.swatches.map(\.color) == [Samples.orange, Samples.teal])
        #expect(palette.swatches[0].name == "Good")
        // What the file left out is filled in: the Global collection, no
        // favorite mark, and an id of its own.
        #expect(palette.collectionID == NookDesignCollection.globalID)
        #expect(palette.swatches.allSatisfy { !$0.isFavorite })
        #expect(Set(palette.swatches.map(\.id)).count == 2)
        #expect(read.library.recents.map(\.color) == [Samples.ink])
        // Three swatches, one palette and one recent color did not read.
        #expect(read.skipped == 5)
    }

    @Test(arguments: ["", "not json", "[1, 2, 3]", "\"just a string\"", "{ \"palettes\": ", "null"])
    func aFileThatIsNotALibraryThrows(text: String) {
        #expect(throws: (any Error).self) {
            try NookDesignLibraryFile.decode(Data(text.utf8))
        }
    }

    @Test func anEmptyObjectIsAnEmptyLibrary() throws {
        let read = try NookDesignLibraryFile.decode(Data("{}".utf8))
        #expect(read.library == .empty)
    }

    @Test func aMarkedFileSitsBesideTheOriginal() {
        let url = URL(fileURLWithPath: "/tmp/somewhere/palettes.json")
        #expect(NookDesignFiles.markedURL(for: url, marked: "unreadable").path == "/tmp/somewhere/palettes.unreadable.json")
    }
}

// MARK: - The store

@MainActor
@Suite struct NookDesignPaletteStoreTests {
    private func folder() throws -> URL { try Samples.temporaryFolder("palettes") }

    private func fileURL(_ folder: URL) -> URL {
        folder.appendingPathComponent(NookDesignLibraryFile.fileName)
    }

    @Test func aFirstLaunchStartsEmptyWithNothingWrong() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = NookDesignPaletteStore(folder: folder)

        #expect(!store.isLoaded)
        await store.load()

        #expect(store.isLoaded)
        #expect(store.library == .empty)
        #expect(store.loadProblem == nil)
        // Reading a shelf that is not there writes nothing.
        #expect(!FileManager.default.fileExists(atPath: fileURL(folder).path))
    }

    @Test func nothingChangesBeforeTheFirstRead() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = NookDesignPaletteStore(folder: folder)

        #expect(store.addPalette(named: "Too early") == nil)
        #expect(store.addColor(Samples.orange, defaultPaletteName: "Mine") == .noPalette)
        store.recordRecent(Samples.orange)
        await store.flush()

        #expect(store.library == .empty)
        #expect(!FileManager.default.fileExists(atPath: fileURL(folder).path))
    }

    @Test func whatIsSavedComesBackOnTheNextLaunch() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = NookDesignPaletteStore(folder: folder)
        await first.load()

        let palette = try #require(first.addPalette(named: "Brand"))
        first.addColor(Samples.orange, named: "Primary", to: palette.id, defaultPaletteName: "Mine")
        first.addColor(Samples.scrim, to: palette.id, defaultPaletteName: "Mine")
        let swatch = try #require(first.activePalette?.swatches.first)
        first.toggleFavorite(swatch.id)
        first.recordRecent(Samples.teal)
        await first.flush()

        let second = NookDesignPaletteStore(folder: folder)
        await second.load()

        #expect(second.loadProblem == nil)
        #expect(second.palettes.map(\.name) == ["Brand"])
        #expect(second.activePalette?.swatches.map(\.color) == [Samples.orange, Samples.scrim])
        #expect(second.activePalette?.swatches.map(\.id) == first.activePalette?.swatches.map(\.id))
        #expect(second.activePalette?.swatches.first?.isFavorite == true)
        #expect(second.activePalette?.swatches.first?.name == "Primary")
        #expect(second.recents.map(\.color) == [Samples.teal])
        #expect(second.colorCount == 2)
    }

    @Test func theFirstColorMakesAPaletteToHoldIt() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = NookDesignPaletteStore(folder: folder)
        await store.load()

        let outcome = store.addColor(Samples.orange, defaultPaletteName: "My colors")

        #expect(added(outcome) != nil)
        #expect(store.palettes.map(\.name) == ["My colors"])
        #expect(store.activePalette?.swatches.map(\.color) == [Samples.orange])
        // A duplicate changes nothing and writes nothing new.
        guard case .duplicate = store.addColor(Samples.orange, defaultPaletteName: "My colors") else {
            Issue.record("the second add should be a duplicate")
            return
        }
        #expect(store.colorCount == 1)
    }

    @Test func manyQuickChangesEndUpOnDiskInOrder() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = NookDesignPaletteStore(folder: folder)
        await store.load()
        let palette = try #require(store.addPalette(named: "0"))

        for index in 1...40 {
            store.renamePalette(palette.id, to: "\(index)")
        }
        await store.flush()

        let reloaded = NookDesignPaletteStore(folder: folder)
        await reloaded.load()
        #expect(reloaded.palettes.map(\.name) == ["40"])
    }

    @Test func steppingThroughPalettesWraps() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = NookDesignPaletteStore(folder: folder)
        await store.load()
        let one = try #require(store.addPalette(named: "One"))
        let two = try #require(store.addPalette(named: "Two"))

        #expect(store.activePalette?.id == two.id)
        store.selectNextPalette()
        #expect(store.activePalette?.id == one.id)
        store.selectNextPalette()
        #expect(store.activePalette?.id == two.id)
    }

    // MARK: Damaged files

    @Test func aFileThatIsNotJSONIsMovedAsideAndNeverCrashes() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let garbage = Data("{ this is not json at all".utf8)
        try garbage.write(to: fileURL(folder))

        let store = NookDesignPaletteStore(folder: folder)
        await store.load()

        #expect(store.isLoaded)
        #expect(store.library == .empty)
        #expect(store.loadProblem == .unreadable)
        // What the user had is still on disk, out of the way of the next save.
        let aside = NookDesignFiles.markedURL(for: fileURL(folder), marked: "unreadable")
        #expect(try Data(contentsOf: aside) == garbage)
        #expect(!FileManager.default.fileExists(atPath: fileURL(folder).path))

        store.addColor(Samples.orange, defaultPaletteName: "Mine")
        await store.flush()
        #expect(try Data(contentsOf: aside) == garbage)

        let next = NookDesignPaletteStore(folder: folder)
        await next.load()
        #expect(next.loadProblem == nil)
        #expect(next.colorCount == 1)
    }

    @Test func aPartlyDamagedFileLoadsTheRestAndKeepsACopy() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let json = """
        { "version": 1, "palettes": [ { "name": "Brand", "swatches": [
            { "color": "#FF8800" }, { "color": "???" }, { "color": "#2EC4B6" } ] } ] }
        """
        let original = Data(json.utf8)
        try original.write(to: fileURL(folder))

        let store = NookDesignPaletteStore(folder: folder)
        await store.load()

        #expect(store.loadProblem == .partlyRead(skipped: 1))
        #expect(store.activePalette?.swatches.map(\.color) == [Samples.orange, Samples.teal])
        let copy = NookDesignFiles.markedURL(for: fileURL(folder), marked: "before-repair")
        #expect(try Data(contentsOf: copy) == original)
    }

    @Test func aFileFromANewerBuildShowsNothingAndIsLeftExactlyAsItIs() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let json = """
        { "version": 9, "somethingNew": { "a": 1 }, "palettes": [ { "name": "Brand", "futureField": true,
            "swatches": [ { "color": "#FF8800", "gradientStops": [] } ] } ] }
        """
        let original = Data(json.utf8)
        try original.write(to: fileURL(folder))

        let store = NookDesignPaletteStore(folder: folder)
        await store.load()

        #expect(store.loadProblem == .newerVersion(9))
        #expect(store.activePalette == nil, "nothing in a newer file is shown")
        // No copy is made: nothing is written over the file or beside it.
        #expect(!FileManager.default.fileExists(atPath: NookDesignFiles.markedURL(for: fileURL(folder), marked: "v9").path))
        #expect(try Data(contentsOf: fileURL(folder)) == original)
    }

    @Test func aFailedSaveIsReported() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = NookDesignPaletteStore(folder: folder)
        await store.load()
        var failures = 0
        store.onSaveFailed = { failures += 1 }

        // A file where the folder should be: nothing can be written in it.
        try FileManager.default.removeItem(at: folder)
        try Data("in the way".utf8).write(to: folder)
        store.addPalette(named: "Lost")
        await store.flush()
        let reported = await Samples.wait { failures == 1 }

        #expect(reported)
        // The shelf in memory keeps the change. Only the disk missed it.
        #expect(store.palettes.map(\.name) == ["Lost"])
    }
}

// MARK: - Import and export

@Suite struct NookDesignPaletteExchangeTests {
    private func palette(named name: String, _ entries: [(String, NookDesignColor, Bool)]) -> NookDesignPalette {
        NookDesignPalette(
            id: UUID(),
            collectionID: NookDesignCollection.globalID,
            name: name,
            swatches: entries.map {
                NookDesignSwatch(id: UUID(), color: $0.1, name: $0.0, isFavorite: $0.2, addedAt: Samples.day)
            },
            createdAt: Samples.day
        )
    }

    private var brand: NookDesignPalette {
        palette(named: "Brand", [("Primary", Samples.orange, true), ("", Samples.teal, false), ("Scrim", Samples.scrim, false)])
    }

    @Test func onePaletteExportsInTheDocumentedShape() throws {
        let data = try NookDesignPaletteExchange.export([brand])
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let colors = try #require(json["colors"] as? [[String: Any]])

        #expect(json["format"] as? String == "open-island-palette")
        #expect(json["version"] as? Int == 1)
        #expect(json["name"] as? String == "Brand")
        #expect(json["palettes"] == nil)
        #expect(colors.map { $0["hex"] as? String } == ["#FF8800", "#2EC4B6", "#00000080"])
        #expect(colors[0]["name"] as? String == "Primary")
        #expect(colors[0]["favorite"] as? Bool == true)
        // What is not set is left out, which keeps a hand-made file short.
        #expect(colors[1]["name"] == nil)
        #expect(colors[1]["favorite"] == nil)
    }

    @Test func aPaletteSurvivesExportAndImport() throws {
        let imported = try NookDesignPaletteExchange.read(NookDesignPaletteExchange.export([brand]))

        #expect(imported.skippedColors == 0)
        #expect(imported.duplicateColors == 0)
        #expect(imported.palettes == [NookDesignExchangePalette(name: "Brand", colors: [
            .init(name: "Primary", color: Samples.orange, isFavorite: true),
            .init(name: "", color: Samples.teal, isFavorite: false),
            .init(name: "Scrim", color: Samples.scrim, isFavorite: false),
        ])])
    }

    @Test func severalPalettesSurviveExportAndImport() throws {
        let second = palette(named: "Grays", [("Ink", Samples.ink, false), ("Paper", Samples.white, true)])
        let data = try NookDesignPaletteExchange.export([brand, second])
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let imported = try NookDesignPaletteExchange.read(data)

        #expect((json["palettes"] as? [Any])?.count == 2)
        #expect(json["colors"] == nil)
        #expect(imported.palettes.map(\.name) == ["Brand", "Grays"])
        #expect(imported.palettes[1].colors.map(\.color) == [Samples.ink, Samples.white])
        #expect(imported.palettes[1].colors.map(\.isFavorite) == [false, true])
        #expect(imported.colorCount == 5)
    }

    @Test func importTakesAHandMadeFile() throws {
        let json = """
        { "name": "  By hand  ", "colors": [
            "#f80",
            { "color": "rgb(46, 196, 182)", "name": "Teal" },
            { "value": "hsl(0, 0%, 100%)", "favorite": true },
            { "hex": "nope" },
            42,
            "#FF8800",
            { "name": "No value" }
        ] }
        """
        let imported = try NookDesignPaletteExchange.read(Data(json.utf8))
        let palette = try #require(imported.palettes.first)

        #expect(palette.name == "By hand")
        #expect(palette.colors.map(\.color) == [Samples.orange, Samples.teal, Samples.white])
        #expect(palette.colors.map(\.name) == ["", "Teal", ""])
        #expect(palette.colors.map(\.isFavorite) == [false, false, true])
        #expect(imported.skippedColors == 3)
        #expect(imported.duplicateColors == 1)
    }

    @Test func aBareListOfColorsIsOnePaletteWithNoName() throws {
        let imported = try NookDesignPaletteExchange.read(Data("[\"#111\", \"2EC4B6\"]".utf8))

        #expect(imported.palettes.count == 1)
        #expect(imported.palettes[0].name.isEmpty)
        #expect(imported.palettes[0].colors.map(\.color) == [Samples.ink, Samples.teal])
    }

    @Test func aPaletteOverTheLimitIsCutAndCounted() throws {
        let colors = (0..<300).map { String(format: "\"#%02X%02X00\"", UInt8($0 % 256), UInt8($0 / 256)) }
        let json = "{ \"colors\": [\(colors.joined(separator: ","))] }"
        let imported = try NookDesignPaletteExchange.read(Data(json.utf8))

        #expect(imported.palettes[0].colors.count == NookDesignLibrary.maxSwatchesPerPalette)
        #expect(imported.skippedColors == 300 - NookDesignLibrary.maxSwatchesPerPalette)
    }

    @Test func aFileThatIsNotAPaletteSaysWhy() {
        #expect(throws: NookDesignImportError.notJSON) {
            try NookDesignPaletteExchange.read(Data("not json".utf8))
        }
        #expect(throws: NookDesignImportError.notJSON) {
            try NookDesignPaletteExchange.read(Data())
        }
        for text in ["{}", "[]", "7", "\"#FF8800\"", "{ \"colors\": [\"nope\"] }", "{ \"palettes\": [ {}, 3 ] }", "{ \"colors\": 5 }"] {
            #expect(throws: NookDesignImportError.noColors, "\(text)") {
                try NookDesignPaletteExchange.read(Data(text.utf8))
            }
        }
        let huge = Data(count: NookDesignPaletteExchange.maxFileBytes + 1)
        #expect(throws: NookDesignImportError.tooLarge) {
            try NookDesignPaletteExchange.read(huge)
        }
    }

    @Test func importedPalettesAreAddedAndTheFirstBecomesActive() throws {
        let (library, existingID, _) = makeLibrary(with: [Samples.ink])
        let imported = NookDesignImport(palettes: [
            NookDesignExchangePalette(name: "", colors: [.init(name: "A", color: Samples.orange, isFavorite: true)]),
            NookDesignExchangePalette(name: "Named", colors: [.init(name: "", color: Samples.teal, isFavorite: false)]),
        ])
        let result = library.importing(imported, untitled: "Untitled", now: Samples.day)

        #expect(result.added == 2)
        #expect(result.library.palettes.map(\.name) == ["Brand", "Untitled", "Named"])
        #expect(result.library.palettes[1].swatches.map(\.isFavorite) == [true])
        #expect(result.library.activePalette()?.id == result.library.palettes[1].id)
        // What was there is left as it was.
        #expect(result.library.palette(existingID) == library.palette(existingID))
        #expect(Set(result.library.palettes.map(\.id)).count == 3)
    }

    @Test func importStopsAtThePaletteLimit() {
        var library = NookDesignLibrary.empty
        for index in 0..<(NookDesignLibrary.maxPalettes - 1) {
            library = library.addingPalette(named: "P\(index)")!.library
        }
        let one = NookDesignExchangePalette(name: "X", colors: [.init(name: "", color: Samples.orange, isFavorite: false)])
        let result = library.importing(NookDesignImport(palettes: [one, one, one]), untitled: "U")

        #expect(result.added == 1)
        #expect(result.library.palettes.count == NookDesignLibrary.maxPalettes)
    }

    @Test func theExportedFileIsNamedAfterItsPalette() {
        #expect(NookDesignPaletteExchange.fileName(for: [brand], fallback: "Palettes") == "Brand.palette.json")
        #expect(NookDesignPaletteExchange.fileName(for: [brand, brand], fallback: "Palettes") == "Palettes.palette.json")
        let odd = palette(named: "a/b:c\\d", [])
        #expect(NookDesignPaletteExchange.fileName(for: [odd], fallback: "Palettes") == "a b c d.palette.json")
        let blank = palette(named: "", [])
        #expect(NookDesignPaletteExchange.fileName(for: [blank], fallback: "Palettes") == "Palettes.palette.json")
    }
}
