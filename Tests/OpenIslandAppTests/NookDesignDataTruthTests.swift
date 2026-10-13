import AppKit
import Foundation
import Testing
@testable import OpenIslandApp

private typealias Samples = NookDesignSamples

private func text(_ key: String, _ arguments: any CVarArg...) -> String {
    let format = LanguageManager.shared.t(key)
    return arguments.isEmpty ? format : String(format: format, arguments: arguments)
}

// MARK: - A4: a problem reaches the user, and the words are true

@MainActor
@Suite struct NookDesignProblemReachTests {
    private func folder() throws -> URL { try Samples.temporaryFolder("truth") }

    private func readOnly(_ folder: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
    }

    private func writable(_ folder: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
    }

    @Test func aCopyThatCannotBeMadeSaysSoAndNothingIsWrittenOverTheFileForTheRestOfTheLaunch() async throws {
        let root = try folder()
        defer { writable(root); try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(NookDesignLibraryFile.fileName)
        let original = Data("{ \"palettes\": [ { \"name\": \"Brand\", \"swatches\": [ { \"color\": \"#FF8800\" }, { \"color\": \"nope\" } ] } ] }".utf8)
        try original.write(to: file)
        try readOnly(root)
        let store = NookDesignPaletteStore(folder: root)
        var refused: [NookDesignStoreLock] = []
        store.onRefused = { refused.append($0) }

        await store.load()

        #expect(store.loadProblem == .partlyReadNotKept(skipped: 1))
        #expect(store.lock == .copyNotKept)
        #expect(store.colorCount == 1, "what could be read is shown")
        // The folder takes files again. The store still takes no change this launch.
        writable(root)
        store.addColor(Samples.teal, defaultPaletteName: "Brand")
        await store.flush()
        #expect(refused == [.copyNotKept])
        #expect(try Data(contentsOf: file) == original)
        #expect(!FileManager.default.fileExists(atPath: NookDesignFiles.markedURL(for: file, marked: "before-repair").path))
    }

    @Test func aFileThatCannotBeMovedAsideStaysWhereItIsAndSaysSo() async throws {
        let root = try folder()
        defer { writable(root); try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(NookDesignLinkFile.fileName)
        let original = Data("{ damaged".utf8)
        try original.write(to: file)
        try readOnly(root)
        let store = NookDesignLinkStore(folder: root)

        await store.load()

        #expect(store.loadProblem == .unreadableNotKept)
        #expect(store.lock == .copyNotKept)
        writable(root)
        store.addCollection(named: "Work")
        await store.flush()
        #expect(try Data(contentsOf: file) == original)
    }

    @Test func aPictureListThatCannotBeKeptIsShownAndLeftAlone() async throws {
        let root = try folder()
        defer { writable(root); try? FileManager.default.removeItem(at: root) }
        let sources = try Samples.temporaryFolder("truth-sources")
        defer { try? FileManager.default.removeItem(at: sources) }
        let first = NookDesignReferenceStore(folder: root)
        await first.load()
        _ = await first.add(fileAt: try Samples.writePNG(named: "a.png", in: sources)).value
        _ = await first.add(fileAt: try Samples.writePNG(named: "b.png", in: sources)).value
        await first.flush()
        let index = NookDesignReferenceFiles.indexURL(in: root)
        try FileManager.default.removeItem(at: NookDesignReferenceFiles.folderURL(for: first.items[0].id, in: root))
        let original = try Data(contentsOf: index)
        try readOnly(root)

        let store = NookDesignReferenceStore(folder: root)
        await store.load()

        #expect(store.loadProblem == .partlyReadNotKept(skipped: 1))
        #expect(store.lock == .copyNotKept)
        #expect(store.items.count == 1)
        writable(root)
        await store.flush()
        #expect(try Data(contentsOf: index) == original, "the list was written over")
    }

    @Test func aMissingListIsNotSaidToHaveBeenMovedAside() async throws {
        let problem = NookDesignStoreProblem(tab: .references, problem: .indexMissing(recovered: 3))
        let moved = NookDesignStoreProblem(tab: .references, problem: .unreadable)
        for language in HangoverBrandTests.languages {
            let table = try HangoverBrandTests.table(language)
            #expect(table["nook.design.settings.problem.indexMissing"] != table["nook.design.settings.problem.unreadable"])
        }
        #expect(problem.settingsText() != moved.settingsText())
        #expect(!problem.settingsText().lowercased().contains("moved aside"))
        #expect(problem.settingsText().contains("3"))
    }

    @Test func everyShelfWithTroubleHasItsOwnCaptionForSettings() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("{ damaged".utf8).write(to: root.appendingPathComponent(NookDesignLibraryFile.fileName))
        try Data("{ \"format\": \"open-island-palette\", \"colors\": [] }".utf8).write(to: root.appendingPathComponent(NookDesignLinkFile.fileName))
        let pictures = root.appendingPathComponent("References", isDirectory: true)
        try FileManager.default.createDirectory(at: pictures, withIntermediateDirectories: true)
        try Data("not a list".utf8).write(to: NookDesignReferenceFiles.indexURL(in: pictures))
        let kit = NookDesignKit(folder: root, defaults: MemoryDefaults())
        kit.setLive(true)

        await kit.load()

        #expect(kit.storeProblems.map(\.tab) == [.colors, .links, .references])
        let lines = kit.storeProblems.map { $0.settingsLine() }
        #expect(lines.count == 3)
        #expect(Set(lines).count == 3)
        #expect(lines[0].hasPrefix(text("nook.design.settings.colors")))
        #expect(lines[1].hasPrefix(text("nook.design.settings.links")))
        #expect(lines[2].hasPrefix(text("nook.design.settings.references")))
    }

    @Test func theCardSaysOnceOnTheTabConcernedWhenTheIslandOpens() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("{ damaged".utf8).write(to: root.appendingPathComponent(NookDesignLinkFile.fileName))
        let kit = NookDesignKit(folder: root, defaults: MemoryDefaults())
        kit.setLive(true)
        await kit.load()
        let line = try #require(kit.storeProblems.first { $0.tab == .links }).cardLine()

        // On the colors tab the links shelf has nothing to say.
        kit.tab = .colors
        kit.islandOpened()
        #expect(kit.notice == nil)

        kit.tab = .links
        #expect(kit.notice?.text == line)
        #expect(kit.notice?.kind == .error)
        #expect(line.contains(text("nook.design.settings.links")))

        // Said once: coming back to the tab does not say it again.
        kit.tab = .colors
        kit.tab = .links
        kit.islandOpened()
        #expect(kit.notice?.text == line)
        #expect(kit.storeProblems.count == 1)
    }

    @Test func aNewerShelfIsToldAsAnotherKindOfLine() async throws {
        let newer = NookDesignStoreProblem(tab: .colors, problem: .newerVersion(9))
        let torn = NookDesignStoreProblem(tab: .colors, problem: .unreadable)
        #expect(newer.cardLine() != torn.cardLine())
        #expect(newer.settingsText().contains("newer"))
    }
}

// MARK: - A5: pictures that lose their place, and deletes that failed

@MainActor
@Suite struct NookDesignPictureKeepingTests {
    private func folder() throws -> URL { try Samples.temporaryFolder("keeping") }

    @Test func aPictureTheListDoesNotHaveIsTakenBackAndSaidOnce() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = try Samples.temporaryFolder("keeping-sources")
        defer { try? FileManager.default.removeItem(at: sources) }
        let first = NookDesignReferenceStore(folder: root)
        await first.load()
        guard case let .added(kept) = await first.add(fileAt: try Samples.writePNG(named: "kept.png", in: sources)).value,
              case let .added(lost) = await first.add(fileAt: try Samples.writePNG(named: "lost.png", in: sources)).value else {
            Issue.record("not added")
            return
        }
        await first.flush()
        // The list loses the second picture, as a crash between the copy and the write would.
        let index = NookDesignReferenceFiles.indexURL(in: root)
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: index)) as? [String: Any])
        json["items"] = (json["items"] as? [[String: Any]] ?? []).filter { $0["id"] as? String == kept.id.uuidString }
        try JSONSerialization.data(withJSONObject: json).write(to: index)

        let second = NookDesignReferenceStore(folder: root)
        await second.load()
        await second.flush()

        #expect(Set(second.items.map(\.id)) == [kept.id, lost.id])
        #expect(second.loadProblem == .picturesTakenBack(1))
        let third = NookDesignReferenceStore(folder: root)
        await third.load()
        #expect(Set(third.items.map(\.id)) == [kept.id, lost.id])
        #expect(third.loadProblem == nil, "it was said once")
    }

    @Test func addedIsSaidOnlyAfterTheListIsWritten() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = try Samples.temporaryFolder("keeping-sources")
        defer { try? FileManager.default.removeItem(at: sources) }
        let picture = try Samples.writePNG(named: "p.png", in: sources)
        let kit = NookDesignKit(folder: root, defaults: MemoryDefaults())
        kit.setLive(true)
        await kit.load()
        // The write of the list fails, as a full disk would make it.
        kit.references.writeList = { _, _, _ in false }

        await kit.addReference(fileAt: picture).value

        #expect(kit.notice?.kind == .error)
        #expect(kit.notice?.text == text("nook.design.notice.referenceNotSaved"))
        #expect(kit.notice?.text != text("nook.design.notice.referenceAdded"))
        // Nothing was said to be added.
        let result = await kit.references.add(fileAt: picture).value
        guard case .addedNotSaved = result else {
            Issue.record("expected addedNotSaved, got \(result)")
            return
        }
    }

    @Test func addedIsSaidWhenTheListWasWritten() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = try Samples.temporaryFolder("keeping-sources")
        defer { try? FileManager.default.removeItem(at: sources) }
        let kit = NookDesignKit(folder: root, defaults: MemoryDefaults())
        kit.setLive(true)
        await kit.load()

        await kit.addReference(fileAt: try Samples.writePNG(named: "p.png", in: sources)).value

        #expect(kit.notice?.kind == .done)
        #expect(kit.notice?.text == text("nook.design.notice.referenceAdded"))
        // And the list on disk has it by then.
        let reader = NookDesignReferenceStore(folder: kit.references.folderURL)
        await reader.load()
        #expect(reader.items.count == 1)
    }

    @Test func aDeleteThatFailedIsTriedAgainAtTheNextLoadAndThePictureDoesNotComeBack() async throws {
        let root = try folder()
        let sources = try Samples.temporaryFolder("keeping-sources")
        defer { try? FileManager.default.removeItem(at: sources) }
        let store = NookDesignReferenceStore(folder: root)
        await store.load()
        guard case let .added(item) = await store.add(fileAt: try Samples.writePNG(named: "p.png", in: sources)).value else {
            Issue.record("not added")
            return
        }
        await store.flush()
        let pictureFolder = NookDesignReferenceFiles.folderURL(for: item.id, in: root)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pictureFolder.path)
            try? FileManager.default.removeItem(at: root)
        }
        // Its folder cannot be emptied, which makes the delete fail.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: pictureFolder.path)

        await store.remove(item.id).value
        await store.flush()
        #expect(store.items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: pictureFolder.path), "the delete should have failed")

        // The next launch tries again, fails again, and does not show it as a lost picture.
        let again = NookDesignReferenceStore(folder: root)
        await again.load()
        await again.flush()
        #expect(again.items.isEmpty)
        #expect(again.loadProblem == nil)

        // Once the folder can be emptied the next load deletes it.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pictureFolder.path)
        let last = NookDesignReferenceStore(folder: root)
        await last.load()
        await last.flush()
        #expect(last.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: pictureFolder.path))
        let after = NookDesignReferenceStore(folder: root)
        await after.load()
        #expect(after.items.isEmpty)
    }
}

// MARK: - A6: a quit or a close right after a change loses nothing

@MainActor
@Suite struct NookDesignQuitTests {
    @Test func closingTheIslandWritesWhatIsStillWaiting() async throws {
        let root = try Samples.temporaryFolder("quit")
        defer { try? FileManager.default.removeItem(at: root) }
        let kit = NookDesignKit(folder: root, defaults: MemoryDefaults())
        kit.setLive(true)
        await kit.load()
        for index in 0..<30 { kit.addLink(text: "https://example.com/\(index)") }
        #expect(kit.hasPendingWrites)

        await kit.islandClosed().value

        #expect(!kit.hasPendingWrites)
        #expect(kit.closeFlushCount == 1)
        let reader = NookDesignLinkStore(folder: root)
        await reader.load()
        #expect(reader.links.count == 30)
    }

    @Test func theAppWaitsForTheWritesBeforeItQuits() async throws {
        let root = try Samples.temporaryFolder("quit")
        defer { try? FileManager.default.removeItem(at: root) }
        let kit = NookDesignKit(folder: root, defaults: MemoryDefaults())
        kit.setLive(true)
        await kit.load()
        let nook = NookModel(design: kit, defaults: MemoryDefaults(), looksForImportedGIF: false)
        let model = AppModel(defaults: MemoryDefaults(), nookModel: nook)
        #expect(model.designKitQuitDecision == .now)

        kit.addColor(Samples.orange)
        kit.addLink(text: "https://example.com/x")
        #expect(model.designKitQuitDecision == .afterWrites)

        await model.flushDesignKitBeforeQuit()

        #expect(model.designKitQuitDecision == .now)
        let colors = NookDesignPaletteStore(folder: root)
        await colors.load()
        #expect(colors.colorCount == 1)
    }

    @Test func theIslandOpeningAndClosingReachTheKit() async throws {
        guard !NSScreen.screens.isEmpty else { return }
        let root = try Samples.temporaryFolder("quit")
        defer { try? FileManager.default.removeItem(at: root) }
        let mine = NookDesignKit(folder: root, defaults: MemoryDefaults())
        let other = NookDesignKit(folder: root, defaults: MemoryDefaults())
        for kit in [mine, other] {
            kit.setLive(true)
            await kit.load()
        }
        let model = AppModel(defaults: MemoryDefaults(), nookModel: NookModel(design: mine, defaults: MemoryDefaults(), looksForImportedGIF: false))
        other.addLink(text: "https://example.com/other")
        await other.flush()
        #expect(mine.links.links.isEmpty)

        model.notchOpen(reason: .click)
        #expect(mine.links.links.map(\.url) == ["https://example.com/other"], "opening the island looks at the files")
        model.notchClose()
        #expect(mine.closeFlushCount == 1, "closing the island writes what waits")
    }
}
