import Foundation
import Testing
@testable import OpenIslandApp

// MARK: - T8: the index

@MainActor @Suite(.serialized, .noNewWindows) struct NookTrayIndexTests {
    private let garbage = Data("this is not json {".utf8)

    private func makeFolder(_ fixture: NookTrayFixesFixture) throws {
        try FileManager.default.createDirectory(at: fixture.folder, withIntermediateDirectories: true)
    }

    @Test func aTrayWithNoIndexYetIsNotAFailure() throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }

        #expect(fixture.store.loadFromDisk() == .missing)
        #expect(fixture.store.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.badIndexURL.path))
    }

    @Test func anIndexThatCannotBeUnderstoodIsMovedAsideAndNotLost() throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        try makeFolder(fixture)
        try garbage.write(to: fixture.indexURL)

        let load = fixture.store.loadFromDisk()

        #expect(load == .failed)
        #expect(fixture.store.items.isEmpty)
        #expect(try Data(contentsOf: fixture.badIndexURL) == garbage, "the unreadable index is kept for a look")
        #expect(!FileManager.default.fileExists(atPath: fixture.indexURL.path))
    }

    @Test func savingAfterABadIndexNeverTouchesTheBadCopy() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        try makeFolder(fixture)
        try garbage.write(to: fixture.indexURL)
        fixture.store.loadFromDisk()

        try await fixture.add(try fixture.files.png(width: 8, height: 8), named: "new.png")

        #expect(try Data(contentsOf: fixture.badIndexURL) == garbage)
        let reopened = fixture.relaunched()
        #expect(reopened.loadFromDisk() == .loaded)
        #expect(reopened.items.map(\.originalName) == ["new.png"])
    }

    @Test func aNewBadIndexTakesTheOlderBadCopysPlace() throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        try makeFolder(fixture)
        try Data("older".utf8).write(to: fixture.badIndexURL)
        try garbage.write(to: fixture.indexURL)

        #expect(fixture.store.loadFromDisk() == .failed)

        #expect(try Data(contentsOf: fixture.badIndexURL) == garbage)
    }

    @Test func anIndexThatCannotBeMovedAsideIsNeverWrittenOver() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        try makeFolder(fixture)
        try garbage.write(to: fixture.indexURL)
        // An older bad copy that cannot be removed: a folder with a file in
        // it that is read only.
        try FileManager.default.createDirectory(at: fixture.badIndexURL, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: fixture.badIndexURL.appendingPathComponent("held"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.badIndexURL.path)

        #expect(fixture.store.loadFromDisk() == .failed)
        try await fixture.add(try fixture.files.png(width: 8, height: 8), named: "new.png")

        #expect(try Data(contentsOf: fixture.indexURL) == garbage, "a save would have destroyed the only copy")
        #expect(fixture.store.saveIndex() == false)
    }

    @Test func aGoodIndexLoadsAndKeepsItsFiles() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        try await fixture.add(try fixture.files.png(width: 8, height: 8), named: "kept.png")

        let reopened = fixture.relaunched()

        #expect(reopened.loadFromDisk() == .loaded)
        #expect(reopened.items.map(\.originalName) == ["kept.png"])
    }

    @Test func aSaveThatFailsSaysSo() throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        try makeFolder(fixture)
        // A folder where the index should be, with something in it, cannot
        // be replaced by a file.
        try FileManager.default.createDirectory(at: fixture.indexURL, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: fixture.indexURL.appendingPathComponent("held"))

        #expect(fixture.store.saveIndex() == false)
    }

    @Test func aSaveThatWorksSaysSo() throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        try makeFolder(fixture)

        #expect(fixture.store.saveIndex() == true)
        #expect(FileManager.default.fileExists(atPath: fixture.indexURL.path))
    }

    // MARK: T6: leftovers of a quit mid conversion

    @Test func aFolderNoFileLivesInIsRemovedWhenTheTrayStarts() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let kept = try await fixture.add(try fixture.files.png(width: 8, height: 8), named: "kept.png")
        // What a quit leaves in the middle of a conversion: a folder with half
        // a result in it, still marked as unfinished.
        let leftover = fixture.folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        try Data(repeating: 3, count: 512).write(to: leftover.appendingPathComponent("clip (720p).mp4"))
        NookTrayPartialMarker.write(in: leftover)

        let reopened = fixture.relaunched()
        reopened.loadFromDisk()

        #expect(!FileManager.default.fileExists(atPath: leftover.path))
        #expect(FileManager.default.fileExists(atPath: reopened.storedURL(for: kept).path), "a file in the index stays")
        #expect(reopened.items.map(\.originalName) == ["kept.png"])
    }

    @Test func removingLeftoversNamesWhatItRemoved() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        try await fixture.add(try fixture.files.png(width: 8, height: 8), named: "kept.png")
        let leftover = fixture.folder.appendingPathComponent("LEFTOVER", isDirectory: true)
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        NookTrayPartialMarker.write(in: leftover)

        #expect(fixture.store.removeOrphanedFolders() == ["LEFTOVER"])
        #expect(fixture.store.removeOrphanedFolders().isEmpty)
    }

    @Test func looseFilesInTheTrayFolderAreLeftAlone() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        try await fixture.add(try fixture.files.png(width: 8, height: 8), named: "kept.png")
        let loose = fixture.folder.appendingPathComponent("notes.txt")
        try Data("mine".utf8).write(to: loose)

        fixture.relaunched().loadFromDisk()

        #expect(FileManager.default.fileExists(atPath: loose.path))
        #expect(FileManager.default.fileExists(atPath: fixture.indexURL.path))
    }

    @Test func nothingIsSweptWhenTheIndexCouldNotBeRead() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.add(try fixture.files.png(width: 8, height: 8), named: "precious.png")
        try garbage.write(to: fixture.indexURL)

        let reopened = fixture.relaunched()
        #expect(reopened.loadFromDisk() == .failed)

        // With no index to say which folders matter, every one looks like a
        // leftover. None of them may be removed.
        #expect(FileManager.default.fileExists(atPath: fixture.store.storedURL(for: item).path))
    }

    @Test func nothingIsSweptWhenThereIsNoIndexYet() throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let folder = fixture.folder.appendingPathComponent("SOMETHING", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        #expect(fixture.store.loadFromDisk() == .missing)

        #expect(FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func aPDFPagesFolderInsideAKeptFolderStays() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let pdf = try await fixture.add(try fixture.files.pdf(pages: 2), named: "notes.pdf")
        await fixture.store.convert(pdf, action: .pdfPages(.png))?.value
        let before = fixture.store.items.map(\.originalName)

        let reopened = fixture.relaunched()
        reopened.loadFromDisk()

        #expect(reopened.items.map(\.originalName) == before)
        #expect(reopened.items.count == 2)
    }
}

// MARK: - T5: a recording that cannot reach the tray

@MainActor @Suite(.serialized, .noNewWindows) struct NookTrayLinkedAddTests {
    @Test func aRecordingThatCannotBeAddedSaysTheRecordingIsSafe() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let missing = fixture.files.url("Recording gone.mp4")

        await fixture.store.add(fileAt: missing, linking: true)?.value

        #expect(fixture.store.items.isEmpty)
        #expect(fixture.store.notice?.text == fixture.text("nook.tray.notice.recordingNotAdded"))
        #expect(fixture.store.notice?.isError == true)
        #expect(fixture.subfolders.isEmpty, "a failed add leaves no folder behind")
    }

    @Test func anOrdinaryFileThatCannotBeAddedStillSaysFileNotAdded() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let missing = fixture.files.url("photo.png")

        await fixture.store.add(fileAt: missing)?.value

        #expect(fixture.store.items.isEmpty)
        #expect(fixture.store.notice?.text == fixture.text("nook.tray.notice.addFailed"))
    }

    @Test func theTwoSentencesAreDifferent() {
        #expect(LanguageManager.shared.t("nook.tray.notice.recordingNotAdded") != LanguageManager.shared.t("nook.tray.notice.addFailed"))
    }

    @Test func whenNoLinkCanBeMadeTheFileIsCopiedInstead() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        // A folder cannot be hard linked, and can be copied.
        let source = fixture.files.url("Recording folder")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("frames".utf8).write(to: source.appendingPathComponent("a.bin"))

        await fixture.store.add(fileAt: source, linking: true)?.value

        let item = try #require(fixture.store.items.first)
        #expect(item.originalName == "Recording folder")
        #expect(FileManager.default.fileExists(atPath: fixture.store.storedURL(for: item).appendingPathComponent("a.bin").path))
        #expect(fixture.store.notice?.isError != true)
    }
}
