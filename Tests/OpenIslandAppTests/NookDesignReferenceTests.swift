import CoreGraphics
import Foundation
import Testing
@testable import OpenIslandApp

private typealias Samples = NookDesignSamples

// MARK: - Rules

@Suite struct NookDesignReferenceRuleTests {
    @Test func aPictureIsNamedAfterItsFile() {
        #expect(NookDesignReferenceRules.displayName(forFileNamed: "Home screen.png") == "Home screen")
        #expect(NookDesignReferenceRules.displayName(forFileNamed: "/Users/x/Desktop/shot.final.JPG") == "shot.final")
        #expect(NookDesignReferenceRules.displayName(forFileNamed: "") == "")
        #expect(NookDesignReferenceRules.cleanName("  two\nlines  ") == "two lines")
        #expect(NookDesignReferenceRules.cleanName(String(repeating: "n", count: 300)).count == NookDesignReferenceRules.maxNameLength)
    }

    @Test func theCopyOnDiskIsNamedByItsTypeAlone() {
        #expect(NookDesignReferenceRules.storedFileName(typeIdentifier: "public.png") == "original.png")
        #expect(NookDesignReferenceRules.storedFileName(typeIdentifier: "public.heic") == "original.heic")
        #expect(NookDesignReferenceRules.storedFileName(typeIdentifier: "no.such.type") == "original.img")
        // Nothing a file was called can reach the path.
        #expect(!NookDesignReferenceRules.storedFileName(typeIdentifier: "../../evil").contains("/"))
    }

    @Test func theTrayOffersPicturesByTheirEnding() {
        for name in ["a.png", "b.JPG", "c.jpeg", "d.heic", "e.gif", "f.tiff", "g.webp", "h.bmp"] {
            #expect(NookDesignReferenceRules.isPictureFileName(name), "\(name)")
        }
        for name in ["notes.txt", "archive.zip", "vector.svg", "doc.pdf", "png", ""] {
            #expect(!NookDesignReferenceRules.isPictureFileName(name), "\(name)")
        }
    }

    @Test func aThumbnailKeepsThePicturesShapeAndNeverGrowsIt() {
        let limit = NookDesignReferenceRules.thumbnailMaxPixel
        #expect(limit == 256)

        let wide = NookDesignReferenceRules.thumbnailSize(forPixelWidth: 4000, pixelHeight: 2000)
        #expect(wide == CGSize(width: 256, height: 128))
        let tall = NookDesignReferenceRules.thumbnailSize(forPixelWidth: 1000, pixelHeight: 3000)
        #expect(tall == CGSize(width: 85, height: 256))
        let small = NookDesignReferenceRules.thumbnailSize(forPixelWidth: 100, pixelHeight: 50)
        #expect(small == CGSize(width: 100, height: 50))
        let exact = NookDesignReferenceRules.thumbnailSize(forPixelWidth: 256, pixelHeight: 256)
        #expect(exact == CGSize(width: 256, height: 256))
        // A sliver keeps at least one pixel across.
        let sliver = NookDesignReferenceRules.thumbnailSize(forPixelWidth: 2, pixelHeight: 6000)
        #expect(sliver == CGSize(width: 1, height: 256))
        #expect(NookDesignReferenceRules.thumbnailSize(forPixelWidth: 0, pixelHeight: 10) == .zero)
    }

    @Test func aPictureIsDrawnWholeInsideItsTile() {
        let side: CGFloat = 60
        #expect(NookDesignReferenceRules.fittedSize(aspectRatio: 2, in: side) == CGSize(width: 60, height: 30))
        #expect(NookDesignReferenceRules.fittedSize(aspectRatio: 0.5, in: side) == CGSize(width: 30, height: 60))
        #expect(NookDesignReferenceRules.fittedSize(aspectRatio: 1, in: side) == CGSize(width: 60, height: 60))
        #expect(NookDesignReferenceRules.fittedSize(aspectRatio: 0, in: side) == .zero)
    }

    @Test func aStoredFileNameIsOneNameWithNoFolderInIt() {
        #expect(NookDesignReferenceFiles.isSafeFileName("original.png"))
        for name in ["", ".", "..", "../../secrets.png", "a/b.png", "a\\b.png"] {
            #expect(!NookDesignReferenceFiles.isSafeFileName(name), "\(name)")
        }
    }

    @Test func aPictureFileSaysItsTypeAndSizeFromItsHeader() {
        let info = NookDesignPictures.inspect(Samples.pngData(width: 40, height: 20))
        #expect(info == NookDesignPictureInfo(typeIdentifier: "public.png", pixelWidth: 40, pixelHeight: 20))
        #expect(info?.pixelCount == 800)
        #expect(NookDesignPictures.inspect(Data("plain text, not a picture".utf8)) == nil)
        #expect(NookDesignPictures.inspect(Data()) == nil)
    }

    @Test func onlyAPictureThatCanBeSeeThroughGetsTheCheckerboard() {
        for opaque: CGImageAlphaInfo in [.none, .noneSkipFirst, .noneSkipLast] {
            #expect(!NookDesignPictures.carriesAlpha(opaque))
        }
        for clear: CGImageAlphaInfo in [.premultipliedLast, .premultipliedFirst, .last, .first, .alphaOnly] {
            #expect(NookDesignPictures.carriesAlpha(clear))
        }
    }
}

// MARK: - The shelf

@MainActor
@Suite struct NookDesignReferenceStoreTests {
    private struct Shelf {
        let root: URL
        let folder: URL
        let sources: URL
        let store: NookDesignReferenceStore

        @MainActor
        init(loads: Bool = true) async throws {
            root = try Samples.temporaryFolder("references")
            folder = root.appendingPathComponent("References", isDirectory: true)
            sources = root.appendingPathComponent("Sources", isDirectory: true)
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            store = NookDesignReferenceStore(folder: folder)
            if loads { await store.load() }
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }

        @MainActor
        func add(_ name: String, width: Int = 60, height: Int = 40) async throws -> NookDesignReference {
            let url = try Samples.writePNG(named: name, in: sources, width: width, height: height)
            let result = await store.add(fileAt: url).value
            guard case let .added(item) = result else { throw NookDesignFixtureError.notAdded("\(result)") }
            return item
        }

        /// The picture folders on disk, by name.
        func folders() -> [String] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            return names.filter { UUID(uuidString: $0) != nil }.sorted()
        }

        @MainActor
        func reopened() async -> NookDesignReferenceStore {
            let next = NookDesignReferenceStore(folder: folder)
            await next.load()
            return next
        }
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    @Test func anEmptyShelfLoadsWithNothingWrongAndWritesNothing() async throws {
        let shelf = try await Shelf()
        defer { shelf.cleanUp() }

        #expect(shelf.store.isLoaded)
        #expect(shelf.store.items.isEmpty)
        #expect(shelf.store.loadProblem == nil)
        #expect(!exists(shelf.folder))
    }

    @Test func aPictureIsCopiedInWithItsNameSizeAndThumbnail() async throws {
        let shelf = try await Shelf()
        defer { shelf.cleanUp() }

        let item = try await shelf.add("Home screen.png", width: 1200, height: 800)

        #expect(shelf.store.items == [item])
        #expect(item.name == "Home screen")
        #expect(item.fileName == "original.png")
        #expect(item.collectionID == NookDesignCollection.globalID)
        #expect(item.pixelWidth == 1200)
        #expect(item.pixelHeight == 800)
        let expectedAspect: CGFloat = 1.5
        #expect(item.aspectRatio == expectedAspect)
        #expect(exists(shelf.store.fileURL(for: item)))
        // The thumbnail is drawn once, at the size the rules give.
        let thumbnail = Samples.pixelSize(ofPictureAt: shelf.store.thumbnailURL(for: item))
        #expect(thumbnail == NookDesignReferenceRules.thumbnailSize(forPixelWidth: 1200, pixelHeight: 800))
        #expect(shelf.folders() == [item.id.uuidString])
    }

    @Test func aReferenceSurvivesItsSourceFileBeingDeleted() async throws {
        let shelf = try await Shelf()
        defer { shelf.cleanUp() }
        let source = try Samples.writePNG(named: "inspiration.png", in: shelf.sources, width: 90, height: 30)
        let original = try Data(contentsOf: source)

        let result = await shelf.store.add(fileAt: source).value
        guard case let .added(item) = result else {
            Issue.record("the picture was not added: \(result)")
            return
        }
        try FileManager.default.removeItem(at: shelf.sources)
        await shelf.store.flush()

        #expect(!exists(source))
        // The copy is the same bytes, and it still opens.
        #expect(try Data(contentsOf: shelf.store.fileURL(for: item)) == original)
        let image = NookDesignPictures.image(fileAt: shelf.store.fileURL(for: item), maxPixel: 4096)
        #expect(image?.width == 90)
        #expect(image?.height == 30)
        // And it is still there after a relaunch.
        let next = await shelf.reopened()
        #expect(next.items == [item])
    }

    @Test func deletingAReferenceRemovesItsFiles() async throws {
        let shelf = try await Shelf()
        defer { shelf.cleanUp() }
        let kept = try await shelf.add("keep.png")
        let gone = try await shelf.add("gone.png")
        let goneFile = shelf.store.fileURL(for: gone)
        let goneThumbnail = shelf.store.thumbnailURL(for: gone)
        #expect(exists(goneFile) && exists(goneThumbnail))

        await shelf.store.remove(gone.id).value
        await shelf.store.flush()

        #expect(shelf.store.items == [kept])
        #expect(!exists(goneFile))
        #expect(!exists(goneThumbnail))
        #expect(!exists(goneFile.deletingLastPathComponent()))
        #expect(shelf.folders() == [kept.id.uuidString])
        #expect(await shelf.reopened().items == [kept])
    }

    @Test func clearingTheShelfDeletesEveryCopy() async throws {
        let shelf = try await Shelf()
        defer { shelf.cleanUp() }
        _ = try await shelf.add("a.png")
        _ = try await shelf.add("b.png")

        await shelf.store.clear().value
        await shelf.store.flush()

        #expect(shelf.store.items.isEmpty)
        #expect(shelf.folders().isEmpty)
        #expect(await shelf.reopened().items.isEmpty)
    }

    @Test func aFileThatIsNotAPictureIsRefusedAndLeavesNothingBehind() async throws {
        let shelf = try await Shelf()
        defer { shelf.cleanUp() }
        let text = shelf.sources.appendingPathComponent("notes.png")
        try Data("this is text with a picture's name".utf8).write(to: text)

        #expect(await shelf.store.add(fileAt: text).value == .notAPicture)
        #expect(await shelf.store.add(imageData: Data("nope".utf8), named: "x").value == .notAPicture)
        // A file that is not there cannot be read, which is not the same as not being a picture.
        #expect(await shelf.store.add(fileAt: shelf.sources.appendingPathComponent("missing.png")).value == .unreadable)

        #expect(shelf.store.items.isEmpty)
        #expect(shelf.folders().isEmpty)
        #expect(shelf.store.addingCount == 0)
    }

    @Test func aFileOverTheSizeLimitIsRefusedBeforeItIsOpened() async throws {
        let shelf = try await Shelf()
        defer { shelf.cleanUp() }
        // A sparse file: it reports its length and takes no room on disk.
        let huge = shelf.sources.appendingPathComponent("huge.png")
        FileManager.default.createFile(atPath: huge.path, contents: nil)
        let handle = try FileHandle(forWritingTo: huge)
        try handle.truncate(atOffset: UInt64(NookDesignReferenceRules.maxFileBytes) + 1)
        try handle.close()

        #expect(await shelf.store.add(fileAt: huge).value == .tooLarge)
        #expect(shelf.folders().isEmpty)
    }

    @Test func aPastedPictureIsKeptUnderTheNameItIsGiven() async throws {
        let shelf = try await Shelf()
        defer { shelf.cleanUp() }

        let result = await shelf.store.add(imageData: Samples.pngData(width: 30, height: 30), named: "  Pasted picture ").value

        guard case let .added(item) = result else {
            Issue.record("the pasted picture was not added: \(result)")
            return
        }
        #expect(item.name == "Pasted picture")
        #expect(item.pixelWidth == 30)
        #expect(exists(shelf.store.fileURL(for: item)))
        #expect(exists(shelf.store.thumbnailURL(for: item)))
    }

    @Test func aTileDroppedBackOnTheShelfIsNotCopiedAgain() async throws {
        let shelf = try await Shelf()
        defer { shelf.cleanUp() }
        let item = try await shelf.add("a.png")

        #expect(await shelf.store.add(fileAt: shelf.store.fileURL(for: item)).value == .alreadyHere)
        #expect(shelf.store.items == [item])
    }

    @Test func nothingIsAddedBeforeTheFirstRead() async throws {
        let shelf = try await Shelf(loads: false)
        defer { shelf.cleanUp() }
        let url = try Samples.writePNG(named: "early.png", in: shelf.sources)

        #expect(await shelf.store.add(fileAt: url).value == .failed)
        #expect(shelf.folders().isEmpty)
    }

    @Test func namesFavoritesAndOrderAreKeptAcrossALaunch() async throws {
        let shelf = try await Shelf()
        defer { shelf.cleanUp() }
        let first = try await shelf.add("first.png")
        let second = try await shelf.add("second.png")
        let third = try await shelf.add("third.png")
        // The newest picture is in front.
        #expect(shelf.store.items.map(\.id) == [third.id, second.id, first.id])

        shelf.store.rename(first.id, to: "  Landing page\nhero ")
        shelf.store.toggleFavorite(second.id)
        shelf.store.move(first.id, to: 0)
        shelf.store.nudge(third.id, by: 1)
        shelf.store.move(UUID(), to: 0)
        await shelf.store.flush()

        let order = [first.id, second.id, third.id]
        #expect(shelf.store.items.map(\.id) == order)
        let next = await shelf.reopened()
        #expect(next.items.map(\.id) == order)
        #expect(next.item(first.id)?.name == "Landing page hero")
        #expect(next.item(second.id)?.isFavorite == true)
        #expect(next.item(third.id)?.isFavorite == false)
        #expect(next.loadProblem == nil)
    }

    @Test func theShelfTakesNoMoreThanItsLimit() async throws {
        let shelf = try await Shelf(loads: false)
        defer { shelf.cleanUp() }
        // A full shelf, written straight to disk: one tiny picture each.
        let picture = Samples.pngData(width: 4, height: 4)
        var items: [NookDesignReference] = []
        for _ in 0..<NookDesignReferenceRules.maxReferences {
            let id = UUID()
            let subfolder = shelf.folder.appendingPathComponent(id.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
            try picture.write(to: subfolder.appendingPathComponent("original.png"))
            items.append(NookDesignReference(
                id: id, collectionID: NookDesignCollection.globalID, name: "", fileName: "original.png",
                pixelWidth: 4, pixelHeight: 4, isFavorite: false, addedAt: Samples.day
            ))
        }
        #expect(NookDesignReferenceFiles.write(items, to: shelf.folder))
        await shelf.store.load()
        #expect(shelf.store.items.count == NookDesignReferenceRules.maxReferences)

        let url = try Samples.writePNG(named: "one-more.png", in: shelf.sources)
        #expect(await shelf.store.add(fileAt: url).value == .full)
        #expect(shelf.store.items.count == NookDesignReferenceRules.maxReferences)
    }

    // MARK: Thumbnails

    @Test func aThumbnailIsDecodedOnceForItsTile() async throws {
        let shelf = try await Shelf()
        defer { shelf.cleanUp() }
        let item = try await shelf.add("wide.png", width: 800, height: 200)
        #expect(shelf.store.thumbnails[item.id] == nil)

        shelf.store.requestThumbnail(for: item)
        shelf.store.requestThumbnail(for: item)
        let decoded = await Samples.wait { shelf.store.thumbnails[item.id] != nil }

        #expect(decoded)
        #expect(shelf.store.thumbnails[item.id]?.width == 256)
        #expect(shelf.store.thumbnails[item.id]?.height == 64)
    }

    @Test func aMissingThumbnailIsDrawnAgainFromThePicture() async throws {
        let shelf = try await Shelf()
        defer { shelf.cleanUp() }
        let item = try await shelf.add("wide.png", width: 400, height: 100)
        try FileManager.default.removeItem(at: shelf.store.thumbnailURL(for: item))

        shelf.store.requestThumbnail(for: item)
        let decoded = await Samples.wait { shelf.store.thumbnails[item.id] != nil }

        #expect(decoded)
        #expect(exists(shelf.store.thumbnailURL(for: item)))
    }

    @Test func aRemovedPictureLetsGoOfItsThumbnail() async throws {
        let shelf = try await Shelf()
        defer { shelf.cleanUp() }
        let item = try await shelf.add("a.png")
        shelf.store.requestThumbnail(for: item)
        _ = await Samples.wait { shelf.store.thumbnails[item.id] != nil }

        await shelf.store.remove(item.id).value

        #expect(shelf.store.thumbnails.isEmpty)
    }

    // MARK: Damaged lists

    @Test func aDamagedListIsBuiltAgainFromThePictures() async throws {
        let shelf = try await Shelf()
        defer { shelf.cleanUp() }
        let first = try await shelf.add("first.png", width: 50, height: 20)
        let second = try await shelf.add("second.png")
        await shelf.store.flush()
        let index = NookDesignReferenceFiles.indexURL(in: shelf.folder)
        let garbage = Data("]]] not a list".utf8)
        try garbage.write(to: index)

        let next = await shelf.reopened()
        await next.flush()

        // Names and order are lost with the list. No picture is.
        #expect(next.loadProblem == .unreadable)
        #expect(Set(next.items.map(\.id)) == [first.id, second.id])
        #expect(next.item(first.id)?.pixelWidth == 50)
        #expect(next.item(first.id)?.fileName == "original.png")
        #expect(next.items.allSatisfy { exists(next.fileURL(for: $0)) })
        // The damaged list is kept aside, and a good one is saved in its place.
        let aside = NookDesignFiles.markedURL(for: index, marked: "unreadable")
        #expect(try Data(contentsOf: aside) == garbage)
        let after = await shelf.reopened()
        #expect(after.loadProblem == nil)
        #expect(Set(after.items.map(\.id)) == [first.id, second.id])
    }

    @Test func aMissingListIsBuiltAgainFromThePictures() async throws {
        let shelf = try await Shelf()
        defer { shelf.cleanUp() }
        let item = try await shelf.add("only.png")
        await shelf.store.flush()
        try FileManager.default.removeItem(at: NookDesignReferenceFiles.indexURL(in: shelf.folder))

        let next = await shelf.reopened()

        #expect(next.items.map(\.id) == [item.id])
        // The list was gone. Nothing was moved aside, and the problem says that.
        #expect(next.loadProblem == .indexMissing(recovered: 1))
        #expect(!exists(NookDesignFiles.markedURL(for: NookDesignReferenceFiles.indexURL(in: shelf.folder), marked: "unreadable")))
    }

    @Test func entriesThatCannotBeShownAreLeftOutAndTheRestLoad() async throws {
        let shelf = try await Shelf()
        defer { shelf.cleanUp() }
        let good = try await shelf.add("good.png")
        let lost = try await shelf.add("lost.png")
        await shelf.store.flush()
        try FileManager.default.removeItem(at: shelf.store.fileURL(for: lost))

        // A list edited by hand: one entry without an id, one that points
        // outside the shelf, one that is not an entry at all.
        let index = NookDesignReferenceFiles.indexURL(in: shelf.folder)
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: index)) as? [String: Any])
        var entries = try #require(json["items"] as? [[String: Any]])
        entries.append(["fileName": "original.png", "name": "No id"])
        entries.append(["id": UUID().uuidString, "fileName": "../../../../etc/hosts", "name": "Escapes"])
        var mixed: [Any] = entries
        mixed.append("not an entry")
        json["items"] = mixed
        try JSONSerialization.data(withJSONObject: json).write(to: index)

        let next = await shelf.reopened()

        #expect(next.items.map(\.id) == [good.id])
        // No id and not an entry, plus a missing picture and a file name that escapes.
        #expect(next.loadProblem == .partlyRead(skipped: 4))
        #expect(exists(NookDesignFiles.markedURL(for: index, marked: "before-repair")))
    }

    @Test func theListOnDiskIsVersionedAndCarriesEachPicturesCollection() async throws {
        let shelf = try await Shelf()
        defer { shelf.cleanUp() }
        let item = try await shelf.add("a.png")
        await shelf.store.flush()

        let data = try Data(contentsOf: NookDesignReferenceFiles.indexURL(in: shelf.folder))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try #require(json["items"] as? [[String: Any]])

        #expect(json["version"] as? Int == NookDesignReferenceFiles.currentVersion)
        #expect(entries.count == 1)
        #expect(entries[0]["id"] as? String == item.id.uuidString)
        #expect(entries[0]["collectionID"] as? String == NookDesignCollection.globalID.uuidString)
        #expect(entries[0]["fileName"] as? String == "original.png")
    }
}
