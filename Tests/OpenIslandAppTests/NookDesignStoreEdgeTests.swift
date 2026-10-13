import Foundation
import Testing
@testable import OpenIslandApp

private typealias Samples = NookDesignSamples

// MARK: - The store: the file is missing, damaged, newer, or cannot be written

@MainActor
@Suite struct NookDesignStoreEdgeTests {
    private func folder() throws -> URL { try Samples.temporaryFolder("store-edge") }

    private func fileURL(_ folder: URL) -> URL {
        folder.appendingPathComponent(NookDesignLibraryFile.fileName)
    }

    private func aside(_ folder: URL, _ mark: String) -> URL {
        NookDesignFiles.markedURL(for: fileURL(folder), marked: mark)
    }

    private func entries(_ folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    // MARK: A file that is not there

    @Test func aFolderThatDoesNotExistYetIsAnEmptyShelfAndStaysUncreated() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("never/made", isDirectory: true)
        let store = NookDesignPaletteStore(folder: missing)

        await store.load()

        #expect(store.isLoaded)
        #expect(store.library == .empty)
        #expect(store.loadProblem == nil)
        #expect(!FileManager.default.fileExists(atPath: missing.path))
        // The first change makes the folders it needs.
        store.addPalette(named: "First")
        await store.flush()
        #expect(FileManager.default.fileExists(atPath: fileURL(missing).path))
    }

    @Test func loadingTwiceReadsOnceAndNeverUndoesAChange() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NookDesignPaletteStore(folder: root)
        await store.load()
        store.addPalette(named: "Mine")
        await store.flush()

        // Something else rewrites the file. A second load does not read it.
        try Data("{}".utf8).write(to: fileURL(root))
        await store.load()

        #expect(store.palettes.map(\.name) == ["Mine"])
    }

    // MARK: A file that is damaged

    @Test func anEmptyFileIsDamagedAndMovedAside() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: fileURL(root))
        let store = NookDesignPaletteStore(folder: root)

        await store.load()

        #expect(store.loadProblem == .unreadable)
        #expect(store.library == .empty)
        #expect(entries(root) == [aside(root, "unreadable").lastPathComponent])
    }

    @Test func aFileOfBinaryNoiseIsDamagedAndMovedAside() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let noise = Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
        try noise.write(to: fileURL(root))
        let store = NookDesignPaletteStore(folder: root)

        await store.load()

        #expect(store.loadProblem == .unreadable)
        #expect(try Data(contentsOf: aside(root, "unreadable")) == noise)
    }

    @Test func aFileCutOffInTheMiddleIsDamagedAndKeptWhole() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let made = NookDesignLibrary.empty.addingPalette(named: "Brand", now: Samples.day)!
        let full = try NookDesignLibraryFile.encode(made.library)
        let cut = full.prefix(full.count / 2)
        try Data(cut).write(to: fileURL(root))
        let store = NookDesignPaletteStore(folder: root)

        await store.load()

        #expect(store.loadProblem == .unreadable)
        #expect(try Data(contentsOf: aside(root, "unreadable")) == Data(cut))
    }

    @Test func listsNestedAThousandDeepAreRefusedWithoutCrashing() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let deep = String(repeating: "[", count: 1000) + String(repeating: "]", count: 1000)
        try Data(deep.utf8).write(to: fileURL(root))
        let store = NookDesignPaletteStore(folder: root)

        await store.load()

        #expect(store.loadProblem == .unreadable)
        #expect(store.library == .empty)
    }

    @Test func aFolderStandingWhereTheFileShouldBeIsMovedAsideToo() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: fileURL(root), withIntermediateDirectories: true)
        let store = NookDesignPaletteStore(folder: root)

        await store.load()

        #expect(store.isLoaded)
        #expect(store.loadProblem == .unreadable)
        // The shelf works afterwards.
        store.addPalette(named: "Fresh")
        await store.flush()
        let next = NookDesignPaletteStore(folder: root)
        await next.load()
        #expect(next.palettes.map(\.name) == ["Fresh"])
        #expect(next.loadProblem == nil)
    }

    @Test func aSecondDamagedFileReplacesTheCopyOfTheFirst() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("first damage".utf8).write(to: fileURL(root))
        await NookDesignPaletteStore(folder: root).load()
        try Data("second damage".utf8).write(to: fileURL(root))
        await NookDesignPaletteStore(folder: root).load()

        #expect(try Data(contentsOf: aside(root, "unreadable")) == Data("second damage".utf8))
    }

    @Test func aFileWithAByteOrderMarkStillReads() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        // Some editors put these three bytes first when a file is saved by hand.
        let json = "{ \"palettes\": [ { \"name\": \"By hand\", \"swatches\": [ { \"color\": \"#FF8800\" } ] } ] }"
        try (Data([0xEF, 0xBB, 0xBF]) + Data(json.utf8)).write(to: fileURL(root))
        let store = NookDesignPaletteStore(folder: root)

        await store.load()

        #expect(store.loadProblem == nil)
        #expect(store.activePalette?.swatches.map(\.color) == [Samples.orange])
    }

    @Test func aShelfThatIsNotAListKeepsACopyBeforeTheNextSaveWritesOverIt() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = Data("{ \"version\": 1, \"palettes\": { \"oops\": 1 } }".utf8)
        try original.write(to: fileURL(root))
        let store = NookDesignPaletteStore(folder: root)

        await store.load()

        #expect(store.loadProblem == .partlyRead(skipped: 1))
        #expect(try Data(contentsOf: aside(root, "before-repair")) == original)
        // The save that follows rewrites the file, and the copy stays.
        store.addColor(Samples.orange, defaultPaletteName: "Mine")
        await store.flush()
        #expect(try Data(contentsOf: aside(root, "before-repair")) == original)
    }

    // MARK: A file from a newer build

    @Test func aNewerFileIsNeverWrittenOverAndNothingOfItIsShown() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = Data("""
        { "version": 3, "extra": [1, 2], "palettes": [ { "name": "Brand", "swatches": [ { "color": "#FF8800" } ] } ] }
        """.utf8)
        try original.write(to: fileURL(root))
        let store = NookDesignPaletteStore(folder: root)
        await store.load()
        #expect(store.loadProblem == .newerVersion(3))
        #expect(store.palettes.isEmpty)

        store.addColor(Samples.teal, defaultPaletteName: "Unused")
        await store.flush()

        #expect(try Data(contentsOf: fileURL(root)) == original)
        #expect(!FileManager.default.fileExists(atPath: aside(root, "v3").path))
        #expect(entries(root) == [NookDesignLibraryFile.fileName])
    }

    @Test func aNewerFileThatIsAlsoDamagedIsJustDamaged() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("{ \"version\": 3, \"palettes\": ".utf8).write(to: fileURL(root))
        let store = NookDesignPaletteStore(folder: root)

        await store.load()

        #expect(store.loadProblem == .unreadable)
        #expect(!FileManager.default.fileExists(atPath: aside(root, "v3").path))
    }

    @Test func versionsFromTheCurrentOneDownLoadWithoutAProblem() async throws {
        for version in [1, 0, -1] {
            let root = try folder()
            defer { try? FileManager.default.removeItem(at: root) }
            try Data("{ \"version\": \(version), \"palettes\": [ { \"name\": \"A\" } ] }".utf8).write(to: fileURL(root))
            let store = NookDesignPaletteStore(folder: root)
            await store.load()
            #expect(store.loadProblem == nil, "version \(version)")
            #expect(store.palettes.count == 1)
        }
    }

    // MARK: A write that fails

    @Test func aFailedWriteIsReportedAndTheNextWriteThatWorksCarriesEverything() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let shelf = root.appendingPathComponent("shelf", isDirectory: true)
        let store = NookDesignPaletteStore(folder: shelf)
        await store.load()
        var failures = 0
        store.onSaveFailed = { failures += 1 }

        // A file stands where the folder must be made.
        try Data("in the way".utf8).write(to: shelf)
        store.addPalette(named: "Lost for now")
        await store.flush()
        #expect(await Samples.wait { failures == 1 })

        // The obstacle goes. The next change writes the whole shelf.
        try FileManager.default.removeItem(at: shelf)
        store.addColor(Samples.orange, defaultPaletteName: "Unused")
        await store.flush()

        #expect(failures == 1)
        let next = NookDesignPaletteStore(folder: shelf)
        await next.load()
        #expect(next.palettes.map(\.name) == ["Lost for now"])
        #expect(next.colorCount == 1)
    }

    @Test func eachFailedWriteIsReportedOnceAndAGoodOneIsNotReported() async throws {
        let root = try folder()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        let store = NookDesignPaletteStore(folder: root)
        await store.load()
        var failures = 0
        store.onSaveFailed = { failures += 1 }

        store.addPalette(named: "Works")
        await store.flush()
        #expect(failures == 0)

        // The folder takes no more files. Reading it still works.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        store.addPalette(named: "Fails one")
        store.addPalette(named: "Fails two")
        store.addPalette(named: "Fails three")
        await store.flush()

        #expect(await Samples.wait { failures == 3 })
        #expect(store.palettes.count == 4, "every change stays in memory")
    }

    @Test func aFolderThatCannotBeWrittenInIsReported() async throws {
        let root = try folder()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        let store = NookDesignPaletteStore(folder: root)
        await store.load()
        var failures = 0
        store.onSaveFailed = { failures += 1 }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)

        store.addPalette(named: "Nowhere to go")
        await store.flush()

        #expect(await Samples.wait { failures == 1 })
        #expect(!FileManager.default.fileExists(atPath: fileURL(root).path))
        #expect(store.palettes.map(\.name) == ["Nowhere to go"])
    }

    @Test func aChangeThatChangesNothingWritesNothing() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let shelf = root.appendingPathComponent("shelf", isDirectory: true)
        let store = NookDesignPaletteStore(folder: shelf)
        await store.load()
        let palette = try #require(store.addPalette(named: "Same"))
        store.addColor(Samples.orange, defaultPaletteName: "Unused")
        store.addColor(Samples.teal, defaultPaletteName: "Unused")
        await store.flush()
        let swatches = try #require(store.activePalette?.swatches)

        // Every one of these changes nothing, and a write would now fail.
        try FileManager.default.removeItem(at: shelf)
        try Data("in the way".utf8).write(to: shelf)
        var failures = 0
        store.onSaveFailed = { failures += 1 }
        store.renamePalette(palette.id, to: "Same")
        store.renamePalette(UUID(), to: "Nobody")
        store.setActivePalette(palette.id)
        store.setActivePalette(UUID())
        store.removePalette(UUID())
        store.removeSwatch(UUID())
        store.toggleFavorite(UUID())
        store.nudgeSwatch(swatches[0].id, by: -1)
        store.nudgeSwatch(swatches[1].id, by: 1)
        store.moveSwatch(swatches[0].id, to: 0)
        store.removeRecent(UUID())
        store.clearRecents()
        store.removeDuplicates(in: palette.id)
        store.removeDuplicates(in: UUID())
        store.selectNextPalette()
        await store.flush()
        try await Task.sleep(for: .milliseconds(30))

        #expect(failures == 0)
    }

    // MARK: What the shelf keeps across a launch

    @Test func orderFavoritesNamesAndRecentsAllComeBack() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NookDesignPaletteStore(folder: root)
        await store.load()
        for color in [Samples.orange, Samples.teal, Samples.ink, Samples.white] {
            store.addColor(color, defaultPaletteName: "Brand")
        }
        let ids = try #require(store.activePalette?.swatches.map(\.id))
        store.moveSwatch(ids[3], to: 0)
        store.toggleFavorite(ids[1])
        store.renameSwatch(ids[2], to: "  Ink\nwell ")
        store.renamePalette(try #require(store.activePalette?.id), to: String(repeating: "N", count: 90))
        for index in 0..<15 { store.recordRecent(NookDesignColor(red: UInt8(index), green: 0, blue: 0)) }
        await store.flush()

        let next = NookDesignPaletteStore(folder: root)
        await next.load()

        #expect(next.library == store.library)
        #expect(next.activePalette?.swatches.map(\.id) == [ids[3], ids[0], ids[1], ids[2]])
        #expect(next.activePalette?.swatches.map(\.isFavorite) == [false, false, true, false])
        #expect(next.activePalette?.swatches[3].name == "Ink well")
        #expect(next.activePalette?.name.count == NookDesignLibrary.maxNameLength)
        #expect(next.recents.count == NookDesignLibrary.maxRecents)
        #expect(next.recents.first?.color.red == 14)
    }

    @Test func removingAPaletteAndAColorIsSavedToo() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NookDesignPaletteStore(folder: root)
        await store.load()
        store.addColor(Samples.orange, defaultPaletteName: "One")
        store.addColor(Samples.teal, defaultPaletteName: "One")
        let second = try #require(store.addPalette(named: "Two"))
        store.addColor(Samples.ink, to: second.id, defaultPaletteName: "Unused")
        let firstSwatch = try #require(store.palettes[0].swatches.first)
        store.removeSwatch(firstSwatch.id)
        store.removePalette(second.id)
        await store.flush()

        let next = NookDesignPaletteStore(folder: root)
        await next.load()

        #expect(next.palettes.count == 1)
        #expect(next.palettes[0].swatches.map(\.color) == [Samples.teal])
        #expect(next.activePalette?.id == next.palettes[0].id)
    }

    @Test func importingBeforeTheReadAddsNothingAndAtTheLimitAddsNothing() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let one = NookDesignExchangePalette(name: "X", colors: [.init(name: "", color: Samples.orange, isFavorite: false)])
        let imported = NookDesignImport(palettes: [one])

        let early = NookDesignPaletteStore(folder: root)
        #expect(early.importPalettes(imported, untitled: "U") == 0)
        #expect(early.library == .empty)

        let store = NookDesignPaletteStore(folder: root)
        await store.load()
        for index in 0..<NookDesignLibrary.maxPalettes { store.addPalette(named: "P\(index)") }
        let full = store.library
        #expect(store.importPalettes(imported, untitled: "U") == 0)
        #expect(store.library == full)
        #expect(store.activePalette?.name == "P99")
    }
}

// MARK: - Import and export: the odd files

@Suite struct NookDesignExchangeEdgeTests {
    private func palette(named name: String, _ colors: [NookDesignColor]) -> NookDesignPalette {
        NookDesignPalette(
            id: UUID(),
            collectionID: NookDesignCollection.globalID,
            name: name,
            swatches: colors.map { NookDesignSwatch(id: UUID(), color: $0, name: "", isFavorite: false, addedAt: Samples.day) },
            createdAt: Samples.day
        )
    }

    private func read(_ json: String) throws -> NookDesignImport {
        try NookDesignPaletteExchange.read(Data(json.utf8))
    }

    // MARK: Size

    @Test func aFileOfExactlyTheLimitIsReadAndOneByteMoreIsRefused() throws {
        let body = "{\"colors\":[\"#fff\"]}"
        let exact = Data(body.utf8) + Data(repeating: UInt8(ascii: " "), count: NookDesignPaletteExchange.maxFileBytes - body.utf8.count)
        #expect(exact.count == NookDesignPaletteExchange.maxFileBytes)
        #expect(try NookDesignPaletteExchange.read(exact).colorCount == 1)

        #expect(throws: NookDesignImportError.tooLarge) {
            try NookDesignPaletteExchange.read(exact + Data([UInt8(ascii: " ")]))
        }
    }

    @Test func aFileOfNothingButNoiseOrNestingSaysItIsNotJSON() {
        let noise = Data((0..<2048).map { UInt8(truncatingIfNeeded: $0 &* 13 &+ 5) })
        #expect(throws: NookDesignImportError.notJSON) { try NookDesignPaletteExchange.read(noise) }
        let deep = Data((String(repeating: "[", count: 1000) + String(repeating: "]", count: 1000)).utf8)
        #expect(throws: NookDesignImportError.notJSON) { try NookDesignPaletteExchange.read(deep) }
        for text in ["NaN", "[NaN]", "[Infinity]", "{'colors': ['#fff']}", "{\"colors\": ['#fff']}"] {
            #expect(throws: NookDesignImportError.notJSON, "\(text)") { try self.read(text) }
        }
    }

    @Test func aFileWithAByteOrderMarkStillReads() throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("{\"colors\":[\"#fff\"]}".utf8)
        #expect(try NookDesignPaletteExchange.read(data).colorCount == 1)
    }

    // MARK: What export writes

    @Test func anEmptyPaletteExportsButHasNothingToImportBack() throws {
        let empty = palette(named: "Empty", [])
        let data = try NookDesignPaletteExchange.export([empty])
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((json["colors"] as? [Any])?.isEmpty == true)
        #expect(throws: NookDesignImportError.noColors) { try NookDesignPaletteExchange.read(data) }

        let none = try NookDesignPaletteExchange.export([])
        #expect(throws: NookDesignImportError.noColors) { try NookDesignPaletteExchange.read(none) }
    }

    @Test func anEmptyPaletteAmongSeveralIsLeftBehindOnImport() throws {
        let data = try NookDesignPaletteExchange.export([
            palette(named: "Empty", []),
            palette(named: "Full", [Samples.orange]),
        ])
        let imported = try NookDesignPaletteExchange.read(data)
        #expect(imported.palettes.map(\.name) == ["Full"])
        #expect(imported.skippedColors == 0)
    }

    @Test func aFullPaletteWithEveryAlphaExportsAndComesBackExactly() throws {
        let colors = (0..<NookDesignLibrary.maxSwatchesPerPalette).map {
            NookDesignColor(red: UInt8($0), green: UInt8(255 - $0), blue: 7, alpha: UInt8($0))
        }
        let imported = try NookDesignPaletteExchange.read(NookDesignPaletteExchange.export([palette(named: "All", colors)]))
        #expect(imported.palettes[0].colors.map(\.color) == colors)
        #expect(imported.skippedColors == 0)
        #expect(imported.duplicateColors == 0)
    }

    @Test func namesWithQuotesBreaksAndEmojiTravelInAFile() throws {
        let name = "Say \"hi\" \\ \u{1F3A8} \u{4E2D}\u{6587}"
        let imported = try NookDesignPaletteExchange.read(NookDesignPaletteExchange.export([palette(named: name, [Samples.orange])]))
        #expect(imported.palettes[0].name == name)
    }

    // MARK: What import takes

    @Test func morePalettesThanTheLimitAreCutAtTheFirstHundred() throws {
        let list = (0..<(NookDesignLibrary.maxPalettes + 5)).map { "{\"name\":\"P\($0)\",\"colors\":[\"#fff\"]}" }
        let imported = try read("{\"palettes\":[\(list.joined(separator: ","))]}")
        #expect(imported.palettes.count == NookDesignLibrary.maxPalettes)
        #expect(imported.palettes.last?.name == "P99")
    }

    @Test func aShelfOfPalettesWinsOverAColorListBesideIt() throws {
        let both = try read("{\"palettes\":[{\"name\":\"Wins\",\"colors\":[\"#000\"]}],\"colors\":[\"#fff\"]}")
        #expect(both.palettes.map(\.name) == ["Wins"])
        // A shelf that is not a list does not hide the colors beside it.
        let wrong = try read("{\"palettes\":\"x\",\"colors\":[\"#fff\"]}")
        #expect(wrong.palettes[0].colors.map(\.color) == [Samples.white])
    }

    @Test func theValueIsLookedForUnderHexThenColorThenValue() throws {
        let imported = try read("""
        {"colors":[
            {"hex":"#111111","color":"#222222","value":"#333333"},
            {"color":"#444444","value":"#555555"},
            {"hex":7,"color":"#666666"},
            {"hex":"nonsense","color":"#777777"},
            {"value":"#888888"}
        ]}
        """)
        #expect(imported.palettes[0].colors.map { $0.color.hex() } == ["#111111", "#444444", "#666666", "#888888"])
        // A value that is there and is not a color is not replaced by another key's.
        #expect(imported.skippedColors == 1)
    }

    @Test func aFavoriteMarkIsOnlyTrueWhenItIsTrue() throws {
        let imported = try read("""
        {"colors":[
            {"hex":"#111","favorite":true}, {"hex":"#222","favorite":false}, {"hex":"#333","favorite":"true"},
            {"hex":"#444","favorite":null}, {"hex":"#555"}
        ]}
        """)
        #expect(imported.palettes[0].colors.map(\.isFavorite) == [true, false, false, false, false])
    }

    @Test func namesAreCleanedLikeEveryOtherName() throws {
        let long = String(repeating: "x", count: 100)
        let imported = try read("""
        {"name":"  Line one\\r\\nline two  ","colors":[
            {"hex":"#111","name":"\(long)"}, {"hex":"#222","name":7}, {"hex":"#333","name":"   "}, {"hex":"#444","name":"a\\n\\nb"}
        ]}
        """)
        #expect(imported.palettes[0].name == "Line one line two")
        #expect(imported.palettes[0].colors.map(\.name) == [String(repeating: "x", count: NookDesignLibrary.maxNameLength), "", "", "a b"])
    }

    @Test func aColorSpelledTwoWaysCountsAsOneAndTheSameColorInTwoPalettesCountsTwice() throws {
        let imported = try read("""
        {"palettes":[
            {"name":"A","colors":["#f80","rgb(255, 136, 0)","hsl(32, 100%, 50%)","#FF8800FF","#ff880080","#ff8801"]},
            {"name":"B","colors":["#ff8800"]}
        ]}
        """)
        #expect(imported.palettes[0].colors.map { $0.color.hex() } == ["#FF8800", "#FF880080", "#FF8801"])
        #expect(imported.duplicateColors == 3)
        #expect(imported.palettes[1].colors.map { $0.color.hex() } == ["#FF8800"])
    }

    @Test func aPaletteWhoseColorsAllFailIsDroppedAndCounted() throws {
        let imported = try read("""
        {"palettes":[ {"name":"Bad","colors":["no","nope",5]}, {"name":"Good","colors":["#fff"]} ]}
        """)
        #expect(imported.palettes.map(\.name) == ["Good"])
        #expect(imported.skippedColors == 3)
    }

    @Test func aThousandColorsWithDuplicatesAndBadOnesAreAllAccountedFor() throws {
        func hex(_ red: Int, _ green: Int, _ blue: Int) -> String {
            "\"#" + String(format: "%02X%02X%02X", UInt32(red), UInt32(green), UInt32(blue)) + "\""
        }
        var items: [String] = []
        for index in 0..<1000 {
            switch index % 4 {
            case 0: items.append(hex(index % 256, index / 256, 1))
            case 1: items.append(hex((index - 1) % 256, (index - 1) / 256, 1))
            case 2: items.append("\"not a color\"")
            default: items.append(hex(index % 256, index / 256, 2))
            }
        }
        let imported = try read("{\"colors\":[\(items.joined(separator: ","))]}")
        let kept = imported.palettes[0].colors.count
        #expect(kept == NookDesignLibrary.maxSwatchesPerPalette)
        #expect(imported.duplicateColors == 250)
        #expect(kept + imported.duplicateColors + imported.skippedColors == 1000)
    }

    // MARK: Adding what was imported

    @Test func importingTheSameFileTwiceMakesTwoPalettesAndTheLaterOneIsActive() {
        let one = NookDesignExchangePalette(name: "Brand", colors: [.init(name: "", color: Samples.orange, isFavorite: false)])
        let imported = NookDesignImport(palettes: [one])
        let first = NookDesignLibrary.empty.importing(imported, untitled: "U", now: Samples.day)
        let second = first.library.importing(imported, untitled: "U", now: Samples.day)

        #expect(second.library.palettes.map(\.name) == ["Brand", "Brand"])
        #expect(Set(second.library.palettes.map(\.id)).count == 2)
        #expect(second.library.activePalette()?.id == second.library.palettes[1].id)
    }

    @Test func anImportIntoAFullShelfLeavesEverythingAsItWas() {
        var library = NookDesignLibrary.empty
        for index in 0..<NookDesignLibrary.maxPalettes { library = library.addingPalette(named: "P\(index)")!.library }
        let one = NookDesignExchangePalette(name: "X", colors: [.init(name: "", color: Samples.orange, isFavorite: false)])

        let result = library.importing(NookDesignImport(palettes: [one]), untitled: "U")

        #expect(result.added == 0)
        #expect(result.library == library)
    }

    // MARK: The exported file's name

    @Test func theFileNameIsAlwaysUsableAndEndsAsExpected() {
        func name(_ palette: String) -> String {
            NookDesignPaletteExchange.fileName(for: [self.palette(named: palette, [])], fallback: "Palettes")
        }
        #expect(name("///") == "Palettes.palette.json")
        #expect(name(":::") == "Palettes.palette.json")
        #expect(name("\\") == "Palettes.palette.json")
        #expect(name("\t\n") == "Palettes.palette.json")
        #expect(name("a\tb") == "a b.palette.json")
        #expect(name("../up") == ".. up.palette.json")
        #expect(!name("../../etc/passwd").contains("/"))
        #expect(name(String(repeating: "n", count: 60)).hasSuffix(".palette.json"))
        #expect(name("\u{1F3A8} Art") == "\u{1F3A8} Art.palette.json")
        #expect(NookDesignPaletteExchange.fileName(for: [], fallback: "Palettes") == "Palettes.palette.json")
    }
}
