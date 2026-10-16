import Darwin
import Foundation
import Testing
@testable import OpenIslandApp

// MARK: - X1: the sweep never deletes a real tray file

/// The tray used to clear out every folder the index did not list. After an
/// index that failed to read, that was every file the person had kept.
@MainActor @Suite(.serialized, .noNewWindows) struct NookTrayOrphanSweepTests {
    private let garbage = Data("this is not json {".utf8)

    private func makeOrphan(in fixture: NookTrayFixesFixture, named name: String = UUID().uuidString, marked: Bool) throws -> URL {
        let orphan = fixture.folder.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 256).write(to: orphan.appendingPathComponent("half.mp4"))
        if marked { NookTrayPartialMarker.write(in: orphan) }
        return orphan
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: The sequence that lost files

    @Test func filesAnUnreadableIndexNamedSurviveTheNextLaunchAfterAnAdd() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        // Files that live only in the tray: a picture, and a zip made from it.
        let picture = try await fixture.add(try fixture.files.png(width: 8, height: 8), named: "photo.png")
        await fixture.store.compress(picture).value
        let zip = try #require(fixture.store.items.first { $0.originalName == "photo.png.zip" })
        let oldFiles = [fixture.store.storedURL(for: picture), fixture.store.storedURL(for: zip)]
        #expect(oldFiles.allSatisfy(exists))

        // Launch 1: the index will not read. It is moved aside and the tray
        // starts empty, and the person adds a file, which saves a new index.
        try garbage.write(to: fixture.indexURL)
        let first = fixture.relaunched()
        #expect(first.loadFromDisk() == .failed)
        #expect(first.items.isEmpty)
        try await fixture.add(try fixture.files.png(width: 8, height: 8), named: "new.png", to: first)

        // Launch 2: the new index loads, and lists only the new file.
        let second = fixture.relaunched()
        #expect(second.loadFromDisk() == .loaded)
        #expect(second.items.map(\.originalName) == ["new.png"])

        #expect(oldFiles.allSatisfy(exists), "the folders the unreadable index named are still there")
        #expect(try Data(contentsOf: fixture.badIndexURL) == garbage, "and so is the unreadable index")
    }

    @Test func nothingIsSweptWhileABadIndexIsKeptEvenForAFolderMarkedUnfinished() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        try await fixture.add(try fixture.files.png(width: 8, height: 8), named: "kept.png")
        let orphan = try makeOrphan(in: fixture, marked: true)
        try garbage.write(to: fixture.badIndexURL)

        let reopened = fixture.relaunched()
        #expect(reopened.loadFromDisk() == .loaded)

        #expect(exists(orphan))
        #expect(reopened.removeOrphanedFolders().isEmpty)
        #expect(exists(orphan))
    }

    // MARK: Only marked folders are leftover work

    @Test func aFolderWithNoMarkerSurvivesTheSweepHoweverMuchItLooksLikeAnOrphan() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        try await fixture.add(try fixture.files.png(width: 8, height: 8), named: "kept.png")
        let unmarked = try makeOrphan(in: fixture, marked: false)

        #expect(fixture.store.removeOrphanedFolders().isEmpty)
        let reopened = fixture.relaunched()
        #expect(reopened.loadFromDisk() == .loaded)

        #expect(exists(unmarked))
        #expect(exists(unmarked.appendingPathComponent("half.mp4")))
    }

    @Test func aMarkedFolderAndAnUnmarkedOneSideBySideLoseOnlyTheMarkedOne() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        try await fixture.add(try fixture.files.png(width: 8, height: 8), named: "kept.png")
        let marked = try makeOrphan(in: fixture, named: "MARKED", marked: true)
        let unmarked = try makeOrphan(in: fixture, named: "UNMARKED", marked: false)

        #expect(fixture.store.removeOrphanedFolders() == ["MARKED"])

        #expect(!exists(marked))
        #expect(exists(unmarked))
    }

    @Test func aMarkedFolderTheIndexListsIsKept() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let kept = try await fixture.add(try fixture.files.png(width: 8, height: 8), named: "kept.png")
        // A marker that outlived its job, as after a quit between the save and
        // the clean up. The index lists the file, so it stays.
        NookTrayPartialMarker.write(in: fixture.store.storedURL(for: kept).deletingLastPathComponent())

        let reopened = fixture.relaunched()
        reopened.loadFromDisk()

        #expect(exists(reopened.storedURL(for: kept)))
        #expect(reopened.items.map(\.originalName) == ["kept.png"])
    }

    // MARK: Another copy of the app

    @Test func aMarkedFolderOfAnotherRunningCopyIsLeftAloneBecauseItsWorkIsNotOver() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        try await fixture.add(try fixture.files.png(width: 8, height: 8), named: "kept.png")
        let inFlight = try makeOrphan(in: fixture, marked: false)
        // The parent of this test process is another process that is running.
        NookTrayPartialMarker.write(in: inFlight, processID: getppid())

        #expect(fixture.store.removeOrphanedFolders().isEmpty)

        #expect(exists(inFlight))
    }

    @Test func aMarkedFolderOfACopyThatIsGoneIsClearedOut() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        try await fixture.add(try fixture.files.png(width: 8, height: 8), named: "kept.png")
        // No process has a number this large.
        let abandoned = try makeOrphan(in: fixture, named: "GONE", marked: false)
        NookTrayPartialMarker.write(in: abandoned, processID: Int32.max)

        #expect(fixture.store.removeOrphanedFolders() == ["GONE"])

        #expect(!exists(abandoned))
    }

    @Test func aMarkerWithNoNumberBelongsToNobodyAndIsClearedOut() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        try await fixture.add(try fixture.files.png(width: 8, height: 8), named: "kept.png")
        let orphan = try makeOrphan(in: fixture, named: "EMPTY", marked: false)
        try Data().write(to: NookTrayPartialMarker.url(in: orphan))

        #expect(fixture.store.removeOrphanedFolders() == ["EMPTY"])
    }

    @Test func aMarkerThatVanishesBeforeItIsReadKeepsTheFolder() throws {
        // Another copy of the app finished and cleared its marker between the
        // sweep's listing and its read. That folder holds a finished file.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(!NookTrayPartialMarker.mayRemove(folder, isRunning: { _ in false }))
        try Data().write(to: NookTrayPartialMarker.url(in: folder))
        #expect(NookTrayPartialMarker.mayRemove(folder, isRunning: { _ in true }), "an empty marker belongs to nobody")
        try Data("4242".utf8).write(to: NookTrayPartialMarker.url(in: folder))
        #expect(!NookTrayPartialMarker.mayRemove(folder, ownProcessID: 1, isRunning: { $0 == 4242 }), "a running owner keeps it")
        #expect(NookTrayPartialMarker.mayRemove(folder, ownProcessID: 1, isRunning: { _ in false }), "a gone owner does not")
    }

    @Test func aProcessThatIsRunningIsToldFromOneThatIsNot() {
        #expect(NookTrayPartialMarker.isProcessRunning(getpid()))
        #expect(!NookTrayPartialMarker.isProcessRunning(Int32.max))
        #expect(!NookTrayPartialMarker.isProcessRunning(0))
        #expect(!NookTrayPartialMarker.isProcessRunning(-1))
    }

    // MARK: Marked while the file is made, clear once it is listed

    /// Holds the main actor, without a single await, until the file has landed in
    /// its folder, and answers with that folder. The job cannot be listed in the
    /// meantime, because listing it needs the main actor, so the folder is seen
    /// as the job leaves it between the copy and the index.
    private func folderOnceLanded(named name: String, in fixture: NookTrayFixesFixture) throws -> URL {
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            let folders = fixture.subfolders.map { fixture.folder.appendingPathComponent($0, isDirectory: true) }
            if let found = folders.first(where: { exists($0.appendingPathComponent(name)) }) { return found }
            usleep(1_000)
        }
        throw NookTrayOrphanSweepTimeout()
    }

    @Test func aFileBeingAddedIsMarkedUnfinishedUntilItIsInTheIndex() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let source = try fixture.files.png(width: 8, height: 8)

        let task = try #require(fixture.store.add(fileAt: source))
        let folder = try folderOnceLanded(named: source.lastPathComponent, in: fixture)

        #expect(NookTrayPartialMarker.isMarked(folder), "marked before the copy, so a quit now leaves a folder the next launch clears")
        #expect(fixture.store.items.isEmpty)

        await task.value

        #expect(fixture.store.items.count == 1)
        #expect(!NookTrayPartialMarker.isMarked(folder), "listed, so nothing is unfinished any more")
        #expect(exists(fixture.indexURL))
    }

    @Test func aConversionIsMarkedUnfinishedUntilItsResultIsInTheIndex() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let picture = try await fixture.add(try fixture.files.png(width: 8, height: 8), named: "photo.png")

        let task = fixture.store.compress(picture)
        let folder = try folderOnceLanded(named: "photo.png.zip", in: fixture)

        #expect(NookTrayPartialMarker.isMarked(folder))
        #expect(fixture.store.items.map(\.originalName) == ["photo.png"], "not listed yet")

        await task.value

        #expect(Set(fixture.store.items.map(\.originalName)) == ["photo.png", "photo.png.zip"])
        #expect(!NookTrayPartialMarker.isMarked(folder))
    }

    @Test func aQuitMidConversionLeavesAFolderTheNextLaunchClearsOut() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let kept = try await fixture.add(try fixture.files.png(width: 8, height: 8), named: "kept.png")
        // The state a quit leaves: the marker is there, the index never heard of it.
        let task = fixture.store.compress(kept)
        let folder = try folderOnceLanded(named: "kept.png.zip", in: fixture)
        #expect(NookTrayPartialMarker.isMarked(folder))
        // Hold the index as it was before the job finished, then let the job end.
        let indexBefore = try Data(contentsOf: fixture.indexURL)
        await task.value
        try indexBefore.write(to: fixture.indexURL)
        NookTrayPartialMarker.write(in: folder)

        let reopened = fixture.relaunched()
        #expect(reopened.loadFromDisk() == .loaded)

        #expect(!exists(folder))
        #expect(reopened.items.map(\.originalName) == ["kept.png"])
        #expect(exists(reopened.storedURL(for: kept)))
    }
}

private struct NookTrayOrphanSweepTimeout: Error {}
