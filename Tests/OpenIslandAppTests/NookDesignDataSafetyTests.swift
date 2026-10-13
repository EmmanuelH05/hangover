import Foundation
import Testing
@testable import OpenIslandApp

private typealias Samples = NookDesignSamples

private func text(_ key: String, _ arguments: any CVarArg...) -> String {
    let format = LanguageManager.shared.t(key)
    return arguments.isEmpty ? format : String(format: format, arguments: arguments)
}

private func address(_ url: String) -> NookDesignLinkAddress {
    guard case let .success(address) = NookDesignLinkRules.address(from: url) else { fatalError("\(url) is not a link") }
    return address
}

// MARK: - A1: two copies of the app share one folder

/// The dev copy and the installed copy use one folder. Each store reads once
/// and writes whole snapshots, which lets the second to write undo the first.
/// A store looks at its file before it applies a change.
@MainActor
@Suite struct NookDesignSharedFolderTests {
    private func folder() throws -> URL { try Samples.temporaryFolder("shared") }

    @Test func twoCopiesOfTheColorShelfKeepEachOthersChanges() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let mine = NookDesignPaletteStore(folder: root)
        let other = NookDesignPaletteStore(folder: root)
        await mine.load()
        await other.load()

        mine.addColor(Samples.orange, defaultPaletteName: "Brand")
        await mine.flush()
        // The other copy never saw that. Its change must not wipe it.
        other.addColor(Samples.teal, defaultPaletteName: "Brand")
        await other.flush()

        let reader = NookDesignPaletteStore(folder: root)
        await reader.load()
        #expect(reader.colorCount == 2)
        #expect(other.colorCount == 2)
        #expect(reader.activePalette?.swatches.map(\.color) == [Samples.orange, Samples.teal])
    }

    @Test func twoCopiesOfTheLinkShelfKeepEachOthersChanges() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let mine = NookDesignLinkStore(folder: root)
        let other = NookDesignLinkStore(folder: root)
        await mine.load()
        await other.load()

        mine.addLink(address("https://a.example/1"))
        await mine.flush()
        other.addLink(address("https://b.example/2"))
        await other.flush()

        let reader = NookDesignLinkStore(folder: root)
        await reader.load()
        #expect(Set(reader.links.map(\.url)) == ["https://a.example/1", "https://b.example/2"])
        #expect(other.links.count == 2)
    }

    @Test func twoCopiesOfThePictureShelfKeepEachOthersPictures() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = try Samples.temporaryFolder("shared-sources")
        defer { try? FileManager.default.removeItem(at: sources) }
        let first = try Samples.writePNG(named: "one.png", in: sources)
        let second = try Samples.writePNG(named: "two.png", in: sources)
        let mine = NookDesignReferenceStore(folder: root)
        let other = NookDesignReferenceStore(folder: root)
        await mine.load()
        await other.load()

        _ = await mine.add(fileAt: first).value
        await mine.flush()
        _ = await other.add(fileAt: second).value
        await other.flush()

        let reader = NookDesignReferenceStore(folder: root)
        await reader.load()
        #expect(Set(reader.items.map(\.name)) == ["one", "two"])
        #expect(other.items.count == 2)
    }

    @Test func aChangeAppliesToWhatTheFileHoldsNowAndNotToWhatWasReadAtLaunch() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let mine = NookDesignPaletteStore(folder: root)
        let other = NookDesignPaletteStore(folder: root)
        await mine.load()
        await other.load()
        let palette = try #require(mine.addPalette(named: "Shared"))
        await mine.flush()

        // The other copy renames the palette. A change here lands on the renamed one.
        other.renamePalette(palette.id, to: "Renamed by the other copy")
        await other.flush()
        mine.addColor(Samples.orange, to: palette.id, defaultPaletteName: "Unused")
        await mine.flush()

        let reader = NookDesignPaletteStore(folder: root)
        await reader.load()
        #expect(reader.palettes.map(\.name) == ["Renamed by the other copy"])
        #expect(reader.colorCount == 1)
    }

    @Test func aRapidRunOfOwnChangesIsNeverTakenForAnotherCopysAndNeverFallsBack() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NookDesignPaletteStore(folder: root)
        await store.load()

        for index in 0..<40 {
            store.addColor(NookDesignColor(red: UInt8(index), green: 1, blue: 2), defaultPaletteName: "Brand")
        }
        await store.flush()

        #expect(store.colorCount == 40)
        let reader = NookDesignPaletteStore(folder: root)
        await reader.load()
        #expect(reader.colorCount == 40)
    }

    @Test func aFileThatWasDeletedOrDamagedOutsideTakesTheNextChangeAsTheFirstOfAFreshShelf() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NookDesignPaletteStore(folder: root)
        await store.load()
        store.addColor(Samples.orange, defaultPaletteName: "Brand")
        await store.flush()
        let file = root.appendingPathComponent(NookDesignLibraryFile.fileName)

        try FileManager.default.removeItem(at: file)
        store.addColor(Samples.teal, defaultPaletteName: "Brand")
        await store.flush()
        #expect(store.colorCount == 1)

        let garbage = Data("{ damaged".utf8)
        try garbage.write(to: file)
        store.addColor(Samples.ink, defaultPaletteName: "Brand")
        await store.flush()
        #expect(store.colorCount == 1)
        // The damaged file is kept beside it.
        #expect(try Data(contentsOf: NookDesignFiles.markedURL(for: file, marked: "unreadable")) == garbage)
        let reader = NookDesignPaletteStore(folder: root)
        await reader.load()
        #expect(reader.loadProblem == nil)
    }

    @Test func theIslandOpeningBringsWhatIsShownUpToDate() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let mine = NookDesignKit(folder: root, defaults: MemoryDefaults())
        let other = NookDesignKit(folder: root, defaults: MemoryDefaults())
        mine.setLive(true)
        other.setLive(true)
        await mine.load()
        await other.load()

        other.addLink(text: "https://a.example/1")
        other.addColor(Samples.orange)
        await other.flush()
        #expect(mine.links.links.isEmpty)

        mine.islandOpened()

        #expect(mine.links.links.map(\.url) == ["https://a.example/1"])
        #expect(mine.palettes.colorCount == 1)
        // Nothing changed since. A second look changes nothing.
        let before = mine.links.library
        mine.islandOpened()
        #expect(mine.links.library == before)
    }

    @Test func aStoreThatWasNotChangedAskedAboutItsFileSaysSoAndKeepsWhatItHas() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NookDesignLinkStore(folder: root)
        await store.load()
        store.addLink(address("https://a.example/1"))
        await store.flush()

        #expect(!store.refreshIfChanged())
        #expect(store.links.count == 1)

        let other = NookDesignLinkStore(folder: root)
        await other.load()
        other.addLink(address("https://b.example/2"))
        await other.flush()
        #expect(store.refreshIfChanged())
        #expect(store.links.count == 2)
        #expect(!store.refreshIfChanged())
    }
}

// MARK: - A2: a file from a newer version is left alone

@MainActor
@Suite struct NookDesignNewerVersionTests {
    private func folder() throws -> URL { try Samples.temporaryFolder("newer") }

    private func entries(_ folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    @Test func aNewerColorFileShowsNothingTakesNoChangeAndIsNeverWrittenOverOrBeside() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(NookDesignLibraryFile.fileName)
        let original = Data("""
        { "version": 9, "palettes": [ { "name": "Brand", "swatches": [ { "color": "#FF8800" } ] } ] }
        """.utf8)
        try original.write(to: file)
        let store = NookDesignPaletteStore(folder: root)
        var refused: [NookDesignStoreLock] = []
        store.onRefused = { refused.append($0) }

        await store.load()

        #expect(store.loadProblem == .newerVersion(9))
        #expect(store.lock == .newerVersion(9))
        #expect(store.palettes.isEmpty, "nothing in a newer file is shown")
        #expect(entries(root) == [NookDesignLibraryFile.fileName], "nothing was written beside it at load")

        #expect(store.addPalette(named: "Mine") == nil)
        store.addColor(Samples.teal, defaultPaletteName: "Mine")
        store.recordRecent(Samples.ink)
        store.removePalette(UUID())
        store.importPalettes(NookDesignImport(palettes: [NookDesignExchangePalette(name: "X", colors: [.init(name: "", color: Samples.orange, isFavorite: false)])]), untitled: "U")
        await store.flush()

        #expect(refused.count == 5)
        #expect(refused.allSatisfy { $0 == .newerVersion(9) })
        #expect(try Data(contentsOf: file) == original)
        #expect(entries(root) == [NookDesignLibraryFile.fileName])
    }

    @Test func aNewerLinkFileIsTreatedTheSame() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(NookDesignLinkFile.fileName)
        let original = Data("{ \"version\": 4, \"links\": [ { \"url\": \"https://example.com/a\" } ] }".utf8)
        try original.write(to: file)
        let store = NookDesignLinkStore(folder: root)
        var refused = 0
        store.onRefused = { _ in refused += 1 }
        await store.load()

        #expect(store.loadProblem == .newerVersion(4))
        #expect(store.links.isEmpty)
        #expect(store.addLink(address("https://example.com/b")) == .notLoaded || store.links.isEmpty)
        store.addCollection(named: "Work")
        store.removeLink(UUID())
        await store.flush()

        #expect(refused >= 2)
        #expect(try Data(contentsOf: file) == original)
        #expect(entries(root) == [NookDesignLinkFile.fileName])
    }

    @Test func aNewerPictureListIsNotRewrittenAtLoadAndTakesNoPicture() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = try Samples.temporaryFolder("newer-sources")
        defer { try? FileManager.default.removeItem(at: sources) }
        let picture = try Samples.writePNG(named: "in.png", in: sources)
        let first = NookDesignReferenceStore(folder: root)
        await first.load()
        _ = await first.add(fileAt: picture).value
        await first.flush()
        let index = NookDesignReferenceFiles.indexURL(in: root)
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: index)) as? [String: Any])
        json["version"] = 7
        let original = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        try original.write(to: index)
        let before = entries(root)

        let store = NookDesignReferenceStore(folder: root)
        var refused = 0
        store.onRefused = { _ in refused += 1 }
        await store.load()
        await store.flush()

        #expect(store.loadProblem == .newerVersion(7))
        #expect(store.items.isEmpty)
        #expect(try Data(contentsOf: index) == original, "the list was rewritten at load")
        #expect(entries(root) == before)

        let result = await store.add(fileAt: picture).value
        #expect(result == .locked)
        #expect(refused == 1)
        await store.flush()
        #expect(try Data(contentsOf: index) == original)
        #expect(entries(root) == before)
    }

    @Test func theKitSaysSoOnTheCardWhenAChangeIsRefused() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("{ \"version\": 9, \"palettes\": [] }".utf8).write(to: root.appendingPathComponent(NookDesignLibraryFile.fileName))
        let kit = NookDesignKit(folder: root, defaults: MemoryDefaults(), copyText: { _ in true })
        kit.setLive(true)
        await kit.load()

        _ = kit.addColor(NookDesignColor(red: 1, green: 2, blue: 3))

        #expect(kit.notice?.kind == .error)
        #expect(kit.notice?.text == text("nook.design.notice.lockedNewer"))
    }

    @Test func whenTheFileIsSavedAgainInAnOldFormatTheShelfOpensUp() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(NookDesignLibraryFile.fileName)
        try Data("{ \"version\": 9, \"palettes\": [] }".utf8).write(to: file)
        let store = NookDesignPaletteStore(folder: root)
        await store.load()
        #expect(store.lock == .newerVersion(9))

        let made = NookDesignLibrary.empty.addingPalette(named: "Back", now: Samples.day)!
        try NookDesignLibraryFile.encode(made.library).write(to: file)

        #expect(store.refreshIfChanged())
        #expect(store.lock == nil)
        #expect(store.palettes.map(\.name) == ["Back"])
        #expect(store.loadProblem == nil)
    }
}

// MARK: - A3: nothing is dropped at load without a copy and a report

@MainActor
@Suite struct NookDesignLeftOutAtLoadTests {
    private func folder() throws -> URL { try Samples.temporaryFolder("leftout") }

    private func copy(_ url: URL) -> URL { NookDesignFiles.markedURL(for: url, marked: "before-repair") }

    @Test func colorsOverTheLimitsAreCountedAndTheFileIsKept() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(NookDesignLibraryFile.fileName)
        func swatches(_ count: Int) -> String {
            (0..<count).map { "{ \"color\": \"#\(String(format: "%02X%02X00", $0 % 256, $0 / 256))\" }" }.joined(separator: ",")
        }
        let palettes = (0..<(NookDesignLibrary.maxPalettes + 1)).map { _ in "{ \"name\": \"P\", \"swatches\": [\(swatches(1))] }" }
        let big = "{ \"name\": \"Big\", \"swatches\": [\(swatches(NookDesignLibrary.maxSwatchesPerPalette + 2))] }"
        let recents = (0..<(NookDesignLibrary.maxRecents + 3)).map { "{ \"color\": \"#0000\(String(format: "%02X", $0))\" }" }
        let original = Data("""
        { "version": 1, "palettes": [ \(palettes.joined(separator: ",")), \(big) ], "recents": [ \(recents.joined(separator: ",")) ] }
        """.utf8)
        try original.write(to: file)
        let store = NookDesignPaletteStore(folder: root)

        await store.load()

        // 2 palettes over the limit (the big one is also past it), 2 colors over, 3 recents over.
        #expect(store.loadProblem == .partlyRead(skipped: 2 + 3))
        #expect(try Data(contentsOf: copy(file)) == original)
    }

    @Test func anExportedPaletteSavedAsTheShelfIsWrongShapeAndKept() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(NookDesignLibraryFile.fileName)
        let original = try NookDesignPaletteExchange.export([
            NookDesignLibrary.empty.addingPalette(named: "Brand", now: Samples.day)!.palette,
        ])
        try original.write(to: file)
        let store = NookDesignPaletteStore(folder: root)

        await store.load()

        #expect(store.palettes.isEmpty)
        #expect(store.loadProblem == .partlyRead(skipped: 1))
        #expect(try Data(contentsOf: copy(file)) == original)
    }

    @Test func aFileThatIsJustAVersionOrEmptyIsAnEmptyShelfWithNoProblem() async throws {
        for body in ["{}", "{ \"version\": 1 }"] {
            let root = try folder()
            defer { try? FileManager.default.removeItem(at: root) }
            try Data(body.utf8).write(to: root.appendingPathComponent(NookDesignLibraryFile.fileName))
            let store = NookDesignPaletteStore(folder: root)
            await store.load()
            #expect(store.loadProblem == nil, "\(body)")
        }
    }

    @Test func namesDatesAndFavoritesThatWillNotReadAreCountedAndTheFileIsKept() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(NookDesignLibraryFile.fileName)
        let original = Data("""
        { "version": 1, "palettes": [ { "name": 5, "createdAt": "yesterday", "swatches": [
            { "color": "#FFF", "isFavorite": "yes", "name": 7, "addedAt": "soon" } ] } ],
          "recents": [ { "color": "#000", "pickedAt": 3 } ] }
        """.utf8)
        try original.write(to: file)
        let store = NookDesignPaletteStore(folder: root)

        await store.load()

        #expect(store.colorCount == 1)
        #expect(store.loadProblem == .partlyRead(skipped: 6))
        #expect(try Data(contentsOf: copy(file)) == original)
    }

    @Test func linksWithNamesDatesAndFavoritesThatWillNotReadAreCountedToo() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(NookDesignLinkFile.fileName)
        let original = Data("""
        { "version": 1, "links": [ { "url": "https://a.example", "name": 5, "isFavorite": "x", "addedAt": "soon",
            "collectionID": "not an id", "lastOpenedAt": "never" } ] }
        """.utf8)
        try original.write(to: file)
        let store = NookDesignLinkStore(folder: root)

        await store.load()

        #expect(store.links.count == 1)
        #expect(store.loadProblem == .partlyRead(skipped: 5))
        #expect(try Data(contentsOf: copy(file)) == original)
    }

    @Test func anExportedPaletteSavedAsTheLinkFileIsWrongShapeAndKept() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(NookDesignLinkFile.fileName)
        let original = Data("{ \"format\": \"open-island-palette\", \"name\": \"Brand\", \"colors\": [] }".utf8)
        try original.write(to: file)
        let store = NookDesignLinkStore(folder: root)

        await store.load()

        #expect(store.loadProblem == .partlyRead(skipped: 1))
        #expect(try Data(contentsOf: copy(file)) == original)
    }

    // MARK: Pictures

    private func shelfWith(_ pictures: [String]) async throws -> (folder: URL, ids: [UUID], cleanUp: () -> Void) {
        let root = try folder()
        let sources = try Samples.temporaryFolder("leftout-sources")
        let store = NookDesignReferenceStore(folder: root)
        await store.load()
        var ids: [UUID] = []
        for name in pictures {
            let url = try Samples.writePNG(named: name, in: sources)
            if case let .added(item) = await store.add(fileAt: url).value { ids.append(item.id) }
        }
        await store.flush()
        return (root, ids, { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: sources) })
    }

    private func edit(_ index: URL, _ change: (inout [[String: Any]]) -> Void) throws -> Data {
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: index)) as? [String: Any])
        var entries = try #require(json["items"] as? [[String: Any]])
        change(&entries)
        json["items"] = entries
        let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        try data.write(to: index)
        return data
    }

    @Test func aPictureWhoseFileIsMissingIsCountedAndTheListIsKept() async throws {
        let shelf = try await shelfWith(["a.png", "b.png"])
        defer { shelf.cleanUp() }
        let index = NookDesignReferenceFiles.indexURL(in: shelf.folder)
        let original = try Data(contentsOf: index)
        try FileManager.default.removeItem(at: NookDesignReferenceFiles.folderURL(for: shelf.ids[0], in: shelf.folder))

        let store = NookDesignReferenceStore(folder: shelf.folder)
        await store.load()

        #expect(store.items.map(\.id) == [shelf.ids[1]])
        #expect(store.loadProblem == .partlyRead(skipped: 1))
        #expect(try Data(contentsOf: copy(index)) == original)
    }

    @Test func anUnsafeFileNameAnOverLongNameAndARepeatedIdAreCountedToo() async throws {
        let shelf = try await shelfWith(["a.png", "b.png", "c.png"])
        defer { shelf.cleanUp() }
        let index = NookDesignReferenceFiles.indexURL(in: shelf.folder)
        let edited = try edit(index) { entries in
            entries[0]["fileName"] = "../../etc/hosts"
            entries[1]["name"] = String(repeating: "n", count: 200)
            entries.append(entries[2])
        }

        let store = NookDesignReferenceStore(folder: shelf.folder)
        await store.load()

        #expect(store.loadProblem == .partlyRead(skipped: 3))
        #expect(store.items.count == 2)
        #expect(try Data(contentsOf: copy(index)) == edited)
    }

    @Test func entriesPastTheLimitAreCounted() async throws {
        let shelf = try await shelfWith(["a.png"])
        defer { shelf.cleanUp() }
        let index = NookDesignReferenceFiles.indexURL(in: shelf.folder)
        _ = try edit(index) { entries in
            let first = entries[0]
            for _ in 0..<NookDesignReferenceRules.maxReferences {
                var more = first
                more["id"] = UUID().uuidString
                entries.append(more)
            }
        }

        let store = NookDesignReferenceStore(folder: shelf.folder)
        await store.load()

        // Each extra entry points at a folder that is not there. It is left out for that.
        #expect(store.items.count == 1)
        guard case let .partlyRead(skipped)? = store.loadProblem else {
            Issue.record("expected partlyRead, got \(String(describing: store.loadProblem))")
            return
        }
        #expect(skipped == NookDesignReferenceRules.maxReferences)
    }

    @Test func namesDatesAndFavoritesOfPicturesThatWillNotReadAreCounted() async throws {
        let shelf = try await shelfWith(["a.png"])
        defer { shelf.cleanUp() }
        let index = NookDesignReferenceFiles.indexURL(in: shelf.folder)
        _ = try edit(index) { entries in
            entries[0]["name"] = 5
            entries[0]["isFavorite"] = "yes"
            entries[0]["addedAt"] = "soon"
        }

        let store = NookDesignReferenceStore(folder: shelf.folder)
        await store.load()

        #expect(store.items.count == 1)
        #expect(store.loadProblem == .partlyRead(skipped: 3))
    }
}
