import Foundation
import Testing
@testable import OpenIslandApp

private typealias Samples = NookDesignSamples

private let day = Date(timeIntervalSince1970: 1_800_000_000)

private func address(_ url: String) -> NookDesignLinkAddress {
    guard case let .success(address) = NookDesignLinkRules.address(from: url) else {
        fatalError("\(url) is not a link")
    }
    return address
}

// MARK: - The file

/// The shape of `links.json`, and what a file that is wrong in some way costs.
@Suite struct NookDesignLinkFileTests {
    private func decode(_ json: String) throws -> (library: NookDesignLinkLibrary, skipped: Int) {
        try NookDesignLinkFile.decode(Data(json.utf8))
    }

    private func sample() throws -> NookDesignLinkLibrary {
        var library = NookDesignLinkLibrary.empty
        guard case let .done(withCollection, made) = library.addingCollection(named: "Client work", now: day) else { throw CancellationError() }
        library = withCollection
        for (url, collection) in [
            ("https://www.figma.com/design/KEY/Name?node-id=1-2&t=a#Frame", made.id as UUID?),
            ("https://example.com/a/b?c=d", nil),
        ] {
            guard case let .added(next, _) = library.addingLink(url: url, name: "Name \(url.count)", to: collection, now: day) else { throw CancellationError() }
            library = next
        }
        return library.togglingFavorite(library.links[0].id).markingOpened(library.links[1].id, now: day.addingTimeInterval(60))
    }

    @Test func aShelfWritesAndReadsBackTheSame() throws {
        let library = try sample()
        let read = try NookDesignLinkFile.decode(NookDesignLinkFile.encode(library))
        #expect(read.library == library)
        #expect(read.skipped == 0)
    }

    @Test func theFileIsVersionedAndKeepsEveryAddressWordForWord() throws {
        let data = try NookDesignLinkFile.encode(sample())
        let text = String(decoding: data, as: UTF8.self)
        // A slash is not written as `\/`, which would make a hand-made file hard to read.
        #expect(text.contains("\"url\" : \"https://www.figma.com/design/KEY/Name?node-id=1-2&t=a#Frame\""))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["version"] as? Int == NookDesignLinkLibrary.currentVersion)
        let links = try #require(json["links"] as? [[String: Any]])
        #expect(links.map { $0["url"] as? String } == ["https://example.com/a/b?c=d", "https://www.figma.com/design/KEY/Name?node-id=1-2&t=a#Frame"])
        #expect(links[0]["isFavorite"] as? Bool == true)
        #expect(links[0]["lastOpenedAt"] == nil, "a link never opened writes no moment")
        #expect(links[0]["collectionID"] == nil, "a link in no collection writes no collection")
        #expect(links[1]["lastOpenedAt"] != nil)
        #expect(links[1]["collectionID"] as? String != nil)
        #expect((json["collections"] as? [[String: Any]])?.first?["name"] as? String == "Client work")
        #expect(links.allSatisfy { UUID(uuidString: $0["id"] as? String ?? "") != nil })
    }

    @Test func aSavedShelfIsByteForByteTheSameEachTimeItIsWritten() throws {
        let library = try sample()
        #expect(try NookDesignLinkFile.encode(library) == NookDesignLinkFile.encode(library))
    }

    @Test func aLinkThatIsNotAWebLinkIsLeftOutAndCounted() throws {
        let json = """
        { "version": 1, "links": [
            { "url": "https://example.com/good", "name": "Good" },
            { "url": "javascript:alert(1)", "name": "Script" },
            { "url": "file:///etc/passwd" },
            { "url": "data:text/html,x" },
            { "url": "mailto:a@example.com" },
            { "url": "example.com/no-scheme" },
            { "url": " https://example.com/padded" },
            { "url": "https://example.com/with space" },
            { "url": "https://user:pass@example.com/" },
            { "url": "https://example.com/\(String(repeating: "a", count: 2_100))" },
            { "url": 7 },
            { "name": "No address at all" },
            "a string where a link should be",
            { "url": "http://localhost:3000/ok" }
        ] }
        """
        let read = try decode(json)
        #expect(read.library.links.map(\.url) == ["https://example.com/good", "http://localhost:3000/ok"])
        #expect(read.skipped == 12)
    }

    @Test func whatTheFileLeavesOutIsFilledIn() throws {
        let json = """
        { "links": [ { "url": "https://example.com/docs" } ], "collections": [ {}, { "name": "Named" } ] }
        """
        let read = try decode(json)
        let link = try #require(read.library.links.first)
        #expect(read.skipped == 0)
        #expect(link.isFavorite == false)
        #expect(link.collectionID == nil)
        #expect(link.lastOpenedAt == nil)
        #expect(link.addedAt == Date(timeIntervalSince1970: 0))
        #expect(read.library.collections.count == 2)
        #expect(Set(read.library.collections.map(\.id)).count == 2)
    }

    @Test(arguments: [
        "{ \"links\": \"oops\" }", "{ \"links\": 5 }", "{ \"links\": { \"a\": 1 } }", "{ \"links\": true }",
        "{ \"collections\": \"oops\" }", "{ \"collections\": [1, 2] }",
    ])
    func aShelfThatIsNotAListIsCountedAsLeftOutAndNeverSilentlyDropped(json: String) throws {
        let read = try decode(json)
        #expect(read.library.links.isEmpty)
        #expect(read.skipped >= 1, "\(json)")
    }

    @Test func aNullListAndAMissingListAreJustEmpty() throws {
        for json in ["{}", "{ \"links\": null, \"collections\": null }", "{ \"version\": 1 }"] {
            let read = try decode(json)
            #expect(read.library == .empty, "\(json)")
            #expect(read.skipped == 0)
        }
    }

    @Test(arguments: ["", "not json", "[1, 2, 3]", "\"just a string\"", "{ \"links\": ", "null", "7"])
    func aFileThatIsNotAShelfThrows(text: String) {
        #expect(throws: (any Error).self) { try NookDesignLinkFile.decode(Data(text.utf8)) }
    }

    @Test func theVersionIsReadAsAWholeNumberOrTakenForTheCurrentOne() throws {
        #expect(try decode("{ }").library.version == 1)
        #expect(try decode("{ \"version\": 4 }").library.version == 4)
        #expect(try decode("{ \"version\": 0 }").library.version == 0)
        #expect(try decode("{ \"version\": \"4\" }").library.version == 1)
        #expect(try decode("{ \"version\": 1.5 }").library.version == 1)
    }

    @Test func aLinkInACollectionThatIsGoneIsInNoCollectionOnceSanitized() throws {
        let json = """
        { "links": [ { "url": "https://example.com/x", "collectionID": "\(UUID().uuidString)", "isFavorite": true } ] }
        """
        let clean = try decode(json).library.sanitized()
        #expect(clean.links[0].collectionID == nil)
        #expect(clean.links[0].isFavorite)
    }
}

// MARK: - The store

@MainActor
@Suite struct NookDesignLinkStoreTests {
    private func folder() throws -> URL { try Samples.temporaryFolder("links") }

    private func fileURL(_ folder: URL) -> URL {
        folder.appendingPathComponent(NookDesignLinkFile.fileName)
    }

    private func aside(_ folder: URL, _ mark: String) -> URL {
        NookDesignFiles.markedURL(for: fileURL(folder), marked: mark)
    }

    private func entries(_ folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    // MARK: A file that is not there

    @Test func aFirstLaunchStartsEmptyAndWritesNothing() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NookDesignLinkStore(folder: root)

        #expect(!store.isLoaded)
        await store.load()

        #expect(store.isLoaded)
        #expect(store.library == .empty)
        #expect(store.loadProblem == nil)
        #expect(entries(root).isEmpty)
    }

    @Test func aFolderThatDoesNotExistYetIsAnEmptyShelfAndIsMadeByTheFirstChange() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("never/made", isDirectory: true)
        let store = NookDesignLinkStore(folder: missing)

        await store.load()
        #expect(store.loadProblem == nil)
        #expect(!FileManager.default.fileExists(atPath: missing.path))

        store.addLink(address("https://example.com/x"))
        await store.flush()
        #expect(FileManager.default.fileExists(atPath: fileURL(missing).path))
    }

    @Test func nothingChangesBeforeTheFirstRead() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NookDesignLinkStore(folder: root)

        #expect(store.addLink(address("https://example.com/x")) == .notLoaded)
        #expect(store.addCollection(named: "Early") == .unknown)
        store.removeLink(UUID())
        #expect(store.moveLink(UUID(), toCollectionNamed: "Early") == .unknownLink)
        await store.flush()

        #expect(store.library == .empty)
        #expect(entries(root).isEmpty, "a click before the read saved an empty shelf over what may be there")
    }

    @Test func loadingTwiceReadsOnceAndNeverUndoesAChange() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NookDesignLinkStore(folder: root)
        await store.load()
        store.addLink(address("https://example.com/mine"))
        await store.flush()

        try Data("{}".utf8).write(to: fileURL(root))
        await store.load()

        #expect(store.links.map(\.url) == ["https://example.com/mine"])
    }

    // MARK: A file that is damaged

    @Test func anEmptyFileIsDamagedAndMovedAside() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: fileURL(root))
        let store = NookDesignLinkStore(folder: root)

        await store.load()

        #expect(store.loadProblem == .unreadable)
        #expect(store.library == .empty)
        #expect(entries(root) == [aside(root, "unreadable").lastPathComponent])
    }

    @Test func aFileOfNoiseOrCutOffInTheMiddleIsKeptWholeAsideAndNeverCrashes() async throws {
        let noise = Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
        let made = NookDesignLinkLibrary.empty.addingCollection(named: "Work", now: day)
        guard case let .done(library, _) = made else { return }
        let full = try NookDesignLinkFile.encode(library)
        let deep = Data((String(repeating: "[", count: 1000) + String(repeating: "]", count: 1000)).utf8)

        for bytes in [noise, Data(full.prefix(full.count / 2)), deep, Data("{ this is not json".utf8)] {
            let root = try folder()
            defer { try? FileManager.default.removeItem(at: root) }
            try bytes.write(to: fileURL(root))
            let store = NookDesignLinkStore(folder: root)

            await store.load()

            #expect(store.isLoaded)
            #expect(store.loadProblem == .unreadable)
            #expect(try Data(contentsOf: aside(root, "unreadable")) == bytes)
            // The next save lands in a fresh file and the copy stays as it was.
            store.addLink(address("https://example.com/fresh"))
            await store.flush()
            #expect(try Data(contentsOf: aside(root, "unreadable")) == bytes)
            let next = NookDesignLinkStore(folder: root)
            await next.load()
            #expect(next.loadProblem == nil)
            #expect(next.links.count == 1)
        }
    }

    @Test func aFolderStandingWhereTheFileShouldBeIsMovedAsideToo() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: fileURL(root), withIntermediateDirectories: true)
        let store = NookDesignLinkStore(folder: root)

        await store.load()

        #expect(store.loadProblem == .unreadable)
        store.addLink(address("https://example.com/works"))
        await store.flush()
        let next = NookDesignLinkStore(folder: root)
        await next.load()
        #expect(next.links.map(\.url) == ["https://example.com/works"])
    }

    @Test func aFileWithAByteOrderMarkStillReads() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let json = "{ \"links\": [ { \"url\": \"https://example.com/by-hand\" } ] }"
        try (Data([0xEF, 0xBB, 0xBF]) + Data(json.utf8)).write(to: fileURL(root))
        let store = NookDesignLinkStore(folder: root)

        await store.load()

        #expect(store.loadProblem == nil)
        #expect(store.links.map(\.url) == ["https://example.com/by-hand"])
    }

    @Test func aFileOfTheWrongShapeKeepsACopyBeforeTheNextSaveWritesOverIt() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = Data("{ \"version\": 1, \"links\": { \"oops\": 1 }, \"collections\": [ { \"name\": \"Kept\" } ] }".utf8)
        try original.write(to: fileURL(root))
        let store = NookDesignLinkStore(folder: root)

        await store.load()

        #expect(store.loadProblem == .partlyRead(skipped: 1))
        #expect(store.collections.map(\.name) == ["Kept"])
        #expect(try Data(contentsOf: aside(root, "before-repair")) == original)
        store.addLink(address("https://example.com/x"))
        await store.flush()
        #expect(try Data(contentsOf: aside(root, "before-repair")) == original)
    }

    @Test func aPartlyDamagedFileLoadsTheRestAndKeepsACopy() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = Data("""
        { "version": 1, "links": [
            { "url": "https://example.com/a" }, { "url": "javascript:alert(1)" }, { "url": "https://example.com/b" } ] }
        """.utf8)
        try original.write(to: fileURL(root))
        let store = NookDesignLinkStore(folder: root)

        await store.load()

        #expect(store.loadProblem == .partlyRead(skipped: 1))
        #expect(store.links.map(\.url) == ["https://example.com/a", "https://example.com/b"])
        #expect(try Data(contentsOf: aside(root, "before-repair")) == original)
    }

    @Test func aFileWithMoreThanTheLimitKeepsACopyBeforeTheTailIsLeftOut() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let links = (0..<(NookDesignLinkLibrary.maxLinks + 3)).map { "{ \"url\": \"https://example.com/\($0)\" }" }
        let collections = (0..<(NookDesignLinkLibrary.maxCollections + 2)).map { "{ \"name\": \"C\($0)\" }" }
        let original = Data("{ \"version\": 1, \"links\": [\(links.joined(separator: ","))], \"collections\": [\(collections.joined(separator: ","))] }".utf8)
        try original.write(to: fileURL(root))
        let store = NookDesignLinkStore(folder: root)

        await store.load()

        #expect(store.links.count == NookDesignLinkLibrary.maxLinks)
        #expect(store.collections.count == NookDesignLinkLibrary.maxCollections)
        #expect(store.links.first?.url == "https://example.com/0", "the oldest are kept and the tail goes")
        // Nothing is left out without a word: the file is kept as it was and the problem is told.
        #expect(store.loadProblem == .partlyRead(skipped: 5))
        #expect(try Data(contentsOf: aside(root, "before-repair")) == original)
    }

    @Test func aFileAtTheLimitsLoadsWithNoProblem() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let links = (0..<NookDesignLinkLibrary.maxLinks).map { "{ \"url\": \"https://example.com/\($0)\" }" }
        let collections = (0..<NookDesignLinkLibrary.maxCollections).map { "{ \"name\": \"C\($0)\" }" }
        try Data("{ \"links\": [\(links.joined(separator: ","))], \"collections\": [\(collections.joined(separator: ","))] }".utf8).write(to: fileURL(root))
        let store = NookDesignLinkStore(folder: root)

        await store.load()

        #expect(store.loadProblem == nil)
        #expect(store.links.count == 200)
        #expect(store.collections.count == 24)
        #expect(entries(root) == [NookDesignLinkFile.fileName])
    }

    // MARK: A file from a newer build

    @Test func aNewerFileIsNeverWrittenOverAndNothingOfItIsShown() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = Data("""
        { "version": 3, "extra": [1, 2], "links": [ { "url": "https://example.com/a", "futureField": true } ] }
        """.utf8)
        try original.write(to: fileURL(root))
        let store = NookDesignLinkStore(folder: root)
        await store.load()
        #expect(store.loadProblem == .newerVersion(3))
        #expect(store.links.isEmpty)

        store.addLink(address("https://example.com/b"))
        await store.flush()

        #expect(try Data(contentsOf: fileURL(root)) == original)
        #expect(!FileManager.default.fileExists(atPath: aside(root, "v3").path))
        #expect(entries(root) == [NookDesignLinkFile.fileName])
    }

    @Test func aNewerFileThatIsAlsoDamagedIsJustDamaged() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("{ \"version\": 3, \"links\": ".utf8).write(to: fileURL(root))
        let store = NookDesignLinkStore(folder: root)

        await store.load()

        #expect(store.loadProblem == .unreadable)
        #expect(!FileManager.default.fileExists(atPath: aside(root, "v3").path))
    }

    @Test func versionsFromTheCurrentOneDownLoadWithoutAProblem() async throws {
        for version in [1, 0, -1] {
            let root = try folder()
            defer { try? FileManager.default.removeItem(at: root) }
            try Data("{ \"version\": \(version), \"links\": [ { \"url\": \"https://example.com/a\" } ] }".utf8).write(to: fileURL(root))
            let store = NookDesignLinkStore(folder: root)
            await store.load()
            #expect(store.loadProblem == nil, "version \(version)")
            #expect(store.links.count == 1)
        }
    }

    // MARK: A write that fails

    @Test func aFailedWriteIsReportedAndTheNextWriteThatWorksCarriesEverything() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let shelf = root.appendingPathComponent("shelf", isDirectory: true)
        let store = NookDesignLinkStore(folder: shelf)
        await store.load()
        var failures = 0
        store.onSaveFailed = { failures += 1 }

        try Data("in the way".utf8).write(to: shelf)
        store.addLink(address("https://example.com/lost-for-now"))
        await store.flush()
        #expect(await Samples.wait { failures == 1 })

        try FileManager.default.removeItem(at: shelf)
        store.addLink(address("https://example.com/second"))
        await store.flush()

        #expect(failures == 1)
        let next = NookDesignLinkStore(folder: shelf)
        await next.load()
        #expect(next.links.map(\.url) == ["https://example.com/second", "https://example.com/lost-for-now"])
    }

    @Test func aFolderThatCannotBeWrittenInIsReportedOnceForEachChange() async throws {
        let root = try folder()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        let store = NookDesignLinkStore(folder: root)
        await store.load()
        var failures = 0
        store.onSaveFailed = { failures += 1 }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)

        store.addLink(address("https://example.com/one"))
        store.addLink(address("https://example.com/two"))
        await store.flush()

        #expect(await Samples.wait { failures == 2 })
        #expect(store.links.count == 2, "every change stays in memory")
        #expect(!FileManager.default.fileExists(atPath: fileURL(root).path))
    }

    @Test func aChangeThatChangesNothingWritesNothing() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let shelf = root.appendingPathComponent("shelf", isDirectory: true)
        let store = NookDesignLinkStore(folder: shelf)
        await store.load()
        store.addCollection(named: "Work")
        store.addLink(address("https://example.com/x"), name: "X")
        await store.flush()
        let link = try #require(store.links.first)
        let collection = try #require(store.collections.first)

        try FileManager.default.removeItem(at: shelf)
        try Data("in the way".utf8).write(to: shelf)
        var failures = 0
        store.onSaveFailed = { failures += 1 }
        store.renameLink(link.id, to: "X")
        store.renameLink(UUID(), to: "Nobody")
        store.removeLink(UUID())
        store.toggleFavorite(UUID())
        store.markOpened(UUID())
        store.removeCollection(UUID())
        store.moveLink(link.id, to: nil)
        store.moveLink(UUID(), to: collection.id)
        store.moveLink(link.id, to: UUID())
        store.addCollection(named: "work")
        store.addCollection(named: "  ")
        store.renameCollection(collection.id, to: "Work")
        store.renameCollection(UUID(), to: "Nobody")
        await store.flush()
        try await Task.sleep(for: .milliseconds(30))

        #expect(failures == 0)
    }

    // MARK: What comes back on the next launch

    @Test func linksCollectionsFavoritesNamesAndOpeningsAllComeBack() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NookDesignLinkStore(folder: root)
        await store.load()
        for index in 0..<6 { store.addLink(address("https://example.com/\(index)")) }
        let ids = store.links.map(\.id)
        store.moveLink(ids[0], toCollectionNamed: "  Client\nwork ")
        store.moveLink(ids[1], toCollectionNamed: "client WORK")
        store.moveLink(ids[2], toCollectionNamed: "Home")
        store.toggleFavorite(ids[3])
        store.renameLink(ids[4], to: "  Renamed\r\nlink ")
        store.markOpened(ids[5], now: day)
        store.renameCollection(try #require(store.collections.first).id, to: "Clients")
        await store.flush()

        let next = NookDesignLinkStore(folder: root)
        await next.load()

        #expect(next.library == store.library)
        #expect(next.collections.map(\.name) == ["Clients", "Home"])
        #expect(next.link(ids[0])?.collectionID == next.collections[0].id)
        #expect(next.link(ids[1])?.collectionID == next.collections[0].id)
        #expect(next.link(ids[3])?.isFavorite == true)
        #expect(next.link(ids[4])?.name == "Renamed link")
        #expect(next.link(ids[5])?.lastOpenedAt == day)
        #expect(next.loadProblem == nil)
    }

    @Test func removingALinkAndACollectionIsSavedToo() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NookDesignLinkStore(folder: root)
        await store.load()
        store.addLink(address("https://example.com/a"))
        store.addLink(address("https://example.com/b"))
        let ids = store.links.map(\.id)
        store.moveLink(ids[0], toCollectionNamed: "Work")
        store.removeLink(ids[1])
        store.removeCollection(try #require(store.collections.first).id)
        await store.flush()

        let next = NookDesignLinkStore(folder: root)
        await next.load()

        #expect(next.links.map(\.id) == [ids[0]])
        #expect(next.link(ids[0])?.collectionID == nil)
        #expect(next.collections.isEmpty)
    }

    @Test func manyQuickChangesEndUpOnDiskInOrder() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NookDesignLinkStore(folder: root)
        await store.load()

        for index in 0..<60 { store.addLink(address("https://example.com/\(index)")) }
        await store.flush()

        let next = NookDesignLinkStore(folder: root)
        await next.load()
        #expect(next.links.count == 60)
        #expect(next.links.first?.url == "https://example.com/59")
        #expect(next.library == store.library)
    }

    @Test func theLimitsHoldAcrossALaunch() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NookDesignLinkStore(folder: root)
        await store.load()
        for index in 0..<NookDesignLinkLibrary.maxLinks { store.addLink(address("https://example.com/\(index)")) }
        for index in 0..<NookDesignLinkLibrary.maxCollections { store.addCollection(named: "C\(index)") }
        #expect(store.addLink(address("https://example.com/over")) == .full)
        #expect(store.addCollection(named: "Over") == .full)
        await store.flush()

        let next = NookDesignLinkStore(folder: root)
        await next.load()
        #expect(next.links.count == 200)
        #expect(next.collections.count == 24)
        #expect(next.loadProblem == nil)
        #expect(next.library == store.library)
    }
}
