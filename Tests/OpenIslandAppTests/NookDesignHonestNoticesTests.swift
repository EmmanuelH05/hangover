import AppKit
import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import OpenIslandApp

private typealias Samples = NookDesignSamples

private func text(_ key: String, _ arguments: any CVarArg...) -> String {
    let format = LanguageManager.shared.t(key)
    return arguments.isEmpty ? format : String(format: format, arguments: arguments)
}

private func batch(_ parts: [(String, Int)]) -> String {
    parts.map { text($0.0, $0.1) }.joined(separator: ", ")
}

/// A kit on a started model, which is what lets it put a line on the closed island.
@MainActor
private func startedFixture(_ label: String = "honest") async throws -> (fixture: NookDesignFixture, nook: NookModel) {
    let fixture = try await NookDesignFixture(label)
    let nook = NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
    nook.setWidget(.design, enabled: true)
    fixture.kit.start(nook: nook)
    return (fixture, nook)
}

// MARK: - B7: the eyedropper says what happened

@MainActor
@Suite struct NookDesignPickTruthTests {
    @Test func aGoodPickShowsItsColorOnTheClosedIsland() async throws {
        let (fixture, nook) = try await startedFixture()
        defer { fixture.cleanUp() }

        fixture.kit.pickColor(from: .shortcut)
        fixture.sampler.finish(Samples.orange)

        #expect(nook.transient?.symbol == "eyedropper.halffull")
        #expect(nook.transient?.text == "#FF8800")
    }

    @Test func aPickWhoseCopyFailedShowsAWarningInWordsAndNotTheGoodPill() async throws {
        let (fixture, nook) = try await startedFixture()
        defer { fixture.cleanUp() }
        fixture.copies.succeeds = false

        fixture.kit.pickColor(from: .shortcut)
        fixture.sampler.finish(Samples.orange)

        #expect(nook.transient?.symbol == "exclamationmark.triangle")
        #expect(nook.transient?.text == text("nook.design.pill.notCopied"))
        #expect(fixture.kit.notice?.kind == .error)
    }

    @Test func aPickThatCouldNotBeSavedBecauseThePaletteIsFullShowsAWarningInWords() async throws {
        let (fixture, nook) = try await startedFixture()
        defer { fixture.cleanUp() }
        fixture.kit.savesPicksToPalette = true
        let colors = (0..<NookDesignLibrary.maxSwatchesPerPalette).map {
            NookDesignExchangePalette.Entry(name: "", color: NookDesignColor(red: UInt8($0 % 256), green: UInt8($0 / 256), blue: 9), isFavorite: false)
        }
        fixture.kit.palettes.importPalettes(NookDesignImport(palettes: [NookDesignExchangePalette(name: "Full", colors: colors)]), untitled: "U")

        fixture.kit.pickColor(from: .shortcut)
        fixture.sampler.finish(Samples.orange)

        #expect(nook.transient?.symbol == "exclamationmark.triangle")
        #expect(nook.transient?.text == text("nook.design.pill.paletteFull"))
        // It was copied, and the card says that and why it was not saved.
        #expect(fixture.copies.texts == ["#FF8800"])
    }

    @Test func aColorThatWillNotConvertSaysSoAndIsNotACancel() async throws {
        let (fixture, nook) = try await startedFixture()
        defer { fixture.cleanUp() }

        fixture.kit.pickColor(from: .shortcut)
        fixture.sampler.finishUnreadable()

        #expect(!fixture.kit.isSampling)
        #expect(fixture.kit.notice?.kind == .error)
        #expect(fixture.kit.notice?.text == text("nook.design.notice.pickUnreadable"))
        #expect(nook.transient?.symbol == "exclamationmark.triangle")
        #expect(fixture.kit.palettes.recents.isEmpty)
        #expect(fixture.copies.texts.isEmpty)
    }

    @Test func aCancelStillSaysNothing() async throws {
        let (fixture, nook) = try await startedFixture()
        defer { fixture.cleanUp() }

        fixture.kit.pickColor(from: .shortcut)
        fixture.sampler.finish(nil)

        #expect(fixture.kit.notice == nil)
        #expect(nook.transient == nil)
    }

    @Test func theLoupesAnswerIsToldApartByWhatItHolds() {
        #expect(NookDesignSystemColorSampler.result(for: nil) == .cancelled)
        #expect(NookDesignSystemColorSampler.result(for: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)) == .picked(NookDesignColor(red: 255, green: 0, blue: 0)))
        let pattern = NSColor(patternImage: NSImage(size: NSSize(width: 4, height: 4)))
        #expect(NookDesignSystemColorSampler.result(for: pattern) == .unreadable)
    }
}

// MARK: - B8, B11: one line for a batch, and bad news is not hidden

@MainActor
@Suite struct NookDesignBatchNoticeTests {
    private func pictures(_ count: Int, in folder: URL) throws -> [URL] {
        try (0..<count).map { try Samples.writePNG(named: "p\($0).png", in: folder) }
    }

    private func notPictures(_ count: Int, in folder: URL) throws -> [URL] {
        try (0..<count).map { index in
            let url = folder.appendingPathComponent("note\(index).txt")
            try Data("words".utf8).write(to: url)
            return url
        }
    }

    @Test func pastingSeveralFilesEndsInOneLineThatCountsBoth() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let sources = try Samples.temporaryFolder("batch")
        defer { try? FileManager.default.removeItem(at: sources) }
        fixture.clipboard.pictures = .files(try pictures(3, in: sources) + notPictures(2, in: sources))

        for task in fixture.kit.pasteReference() { await task.value }

        #expect(fixture.kit.notice?.text == batch([("nook.design.batch.added", 3), ("nook.design.batch.notAPicture", 2)]))
        #expect(fixture.kit.notice?.kind == .error)
        #expect(fixture.kit.references.items.count == 3)
    }

    @Test func severalFilesThatAllWentInEndInOneLineOfGoodNews() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let sources = try Samples.temporaryFolder("batch")
        defer { try? FileManager.default.removeItem(at: sources) }
        fixture.clipboard.pictures = .files(try pictures(3, in: sources))

        for task in fixture.kit.pasteReference() { await task.value }

        #expect(fixture.kit.notice?.text == text("nook.design.batch.added", 3))
        #expect(fixture.kit.notice?.kind == .done)
    }

    @Test func aSingleFileKeepsItsOwnLines() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let sources = try Samples.temporaryFolder("batch")
        defer { try? FileManager.default.removeItem(at: sources) }
        fixture.clipboard.pictures = .files(try notPictures(1, in: sources))

        for task in fixture.kit.pasteReference() { await task.value }

        #expect(fixture.kit.notice?.text == text("nook.design.notice.notAPicture"))
    }

    @Test func aFileDroppedWithAProviderThatFailsCountsTheOneThatDidNotArrive() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let sources = try Samples.temporaryFolder("batch")
        defer { try? FileManager.default.removeItem(at: sources) }
        let good = NSItemProvider(object: try Samples.writePNG(named: "ok.png", in: sources) as NSURL)
        let broken = NSItemProvider()
        broken.registerItem(forTypeIdentifier: UTType.fileURL.identifier) { completion, _, _ in
            completion?(nil, NSError(domain: "test", code: 1))
        }

        #expect(fixture.kit.handlePictureDrop([good, broken]))

        let said = await Samples.wait {
            fixture.kit.notice?.text == batch([("nook.design.batch.added", 1), ("nook.design.batch.dropFailed", 1)])
        }
        #expect(said, "the line was \(fixture.kit.notice?.text ?? "none")")
    }

    @Test func aDropWhoseOnlyProviderFailsSaysTheDropDidNotArrive() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let broken = NSItemProvider()
        broken.registerItem(forTypeIdentifier: UTType.fileURL.identifier) { completion, _, _ in
            completion?(nil, NSError(domain: "test", code: 1))
        }

        #expect(fixture.kit.handlePictureDrop([broken]))

        #expect(await Samples.wait { fixture.kit.notice?.text == text("nook.design.notice.dropFailed") })
        #expect(fixture.kit.notice?.kind == .error)
    }

    @Test func goodNewsDoesNotHideBadNewsAndWaitsForItsTurn() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        fixture.copies.succeeds = false
        fixture.kit.copy(Samples.orange)
        #expect(fixture.kit.notice?.kind == .error)

        fixture.copies.succeeds = true
        fixture.kit.copy(Samples.teal)
        #expect(fixture.kit.notice?.kind == .error, "the bad news was hidden by the good")

        // The good news is shown once the bad has had its time.
        #expect(await Samples.wait(seconds: 6) { fixture.kit.notice?.kind == .done })
        #expect(fixture.kit.notice?.text.contains("#2EC4B6") == true)
    }

    @Test func aLaterErrorReplacesAnEarlierOneAndInfoNeverHidesAnError() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        fixture.copies.succeeds = false
        fixture.kit.copy(Samples.orange)
        fixture.kit.addColor(text: "nope")
        #expect(fixture.kit.notice?.kind == .error)
        fixture.kit.addLink(text: "javascript:alert(1)")
        #expect(fixture.kit.notice?.kind == .error)
    }
}

// MARK: - B9: an import counts everything it leaves out

@MainActor
@Suite struct NookDesignImportCountTests {
    private func read(_ json: String) throws -> NookDesignImport {
        try NookDesignPaletteExchange.read(Data(json.utf8))
    }

    @Test func palettesPastTheLimitAreCounted() throws {
        let list = (0..<(NookDesignLibrary.maxPalettes + 5)).map { "{\"name\":\"P\($0)\",\"colors\":[\"#fff\"]}" }
        let imported = try read("{\"palettes\":[\(list.joined(separator: ","))]}")
        #expect(imported.palettes.count == NookDesignLibrary.maxPalettes)
        #expect(imported.skippedPalettes == 5)
    }

    @Test func entriesThatAreNotObjectsAndPalettesWithNoColorsAreCounted() throws {
        let imported = try read("""
        {"palettes":[ {"name":"Good","colors":["#fff"]}, 3, "x", null, {"name":"Empty","colors":[]}, {"name":"No key"}, {"colors":["nope"]} ]}
        """)
        #expect(imported.palettes.map(\.name) == ["Good"])
        #expect(imported.skippedPalettes == 6)
        #expect(imported.skippedColors == 1)
    }

    @Test func aSinglePaletteWithNoUsableColorIsAFileWithNoColors() throws {
        #expect(throws: NookDesignImportError.noColors) { try self.read("{\"colors\":[\"nope\"]}") }
    }

    @Test func theLineAfterAnImportCountsPalettesLeftOutToo() async throws {
        let (fixture, nook) = try await startedFixture("import")
        defer { fixture.cleanUp() }
        var imported = NookDesignImport(palettes: [NookDesignExchangePalette(name: "A", colors: [.init(name: "", color: Samples.orange, isFavorite: false)])])
        imported.skippedPalettes = 2
        imported.skippedColors = 1

        fixture.kit.finishImport(.success(imported))

        #expect(await Samples.wait { fixture.kit.notice != nil })
        #expect(fixture.kit.notice?.text == text("nook.design.notice.imported.leftOut", 1, 1, 3))
        // Something was left out, which reaches the closed island as a warning.
        #expect(fixture.kit.notice?.kind == .error)
        #expect(nook.transient?.symbol == "exclamationmark.triangle")
    }

    @Test func anImportThatLeftNothingOutIsGoodNewsOnly() async throws {
        let (fixture, nook) = try await startedFixture("import")
        defer { fixture.cleanUp() }
        let imported = NookDesignImport(palettes: [NookDesignExchangePalette(name: "A", colors: [.init(name: "", color: Samples.orange, isFavorite: false)])])

        fixture.kit.finishImport(.success(imported))

        #expect(await Samples.wait { fixture.kit.notice != nil })
        #expect(fixture.kit.notice?.kind == .done)
        #expect(nook.transient == nil)
    }

    @Test func aFileThatCouldNotBeReadSaysThatAndNotThatItIsNotAPaletteFile() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let unreadable = fixture.folder.appendingPathComponent("locked.json")
        try Data("{}".utf8).write(to: unreadable)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.path) }
        let broken = fixture.folder.appendingPathComponent("broken.json")
        try Data("{ nope".utf8).write(to: broken)

        await fixture.kit.importPalettes(fromFileAt: unreadable).value
        let couldNotRead = fixture.kit.notice?.text
        await fixture.kit.importPalettes(fromFileAt: broken).value
        let notJSON = fixture.kit.notice?.text

        #expect(couldNotRead == text("nook.design.notice.importUnreadable"))
        #expect(notJSON == text("nook.design.notice.importNotJSON"))
        #expect(couldNotRead != notJSON)
    }

    @Test func aFailedExportSaysWhy() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        fixture.kit.addColor(Samples.orange)
        let id = try #require(fixture.kit.palettes.activePalette?.id)

        await fixture.kit.exportPalettes([id], to: fixture.folder.appendingPathComponent("no/such/folder/out.json")).value

        let line = try #require(fixture.kit.notice?.text)
        #expect(fixture.kit.notice?.kind == .error)
        #expect(line.hasPrefix(String(text("nook.design.notice.exportWriteFailed", "").dropLast(0))))
        #expect(line != text("nook.design.notice.exportFailed"))
        #expect(line.count > text("nook.design.notice.exportWriteFailed", "").count, "the system's reason is in the line")

        await fixture.kit.exportPalettes([UUID()], to: fixture.folder.appendingPathComponent("x.json")).value
        #expect(fixture.kit.notice?.text == text("nook.design.notice.exportNothing"))
    }
}

// MARK: - B10: three different lines for three different troubles

@MainActor
@Suite struct NookDesignPictureTroubleTests {
    @Test func aFileThatCannotBeOpenedIsNotCalledANonPicture() async throws {
        let sources = try Samples.temporaryFolder("trouble")
        let target = try Samples.temporaryFolder("trouble-shelf")
        defer { try? FileManager.default.removeItem(at: sources); try? FileManager.default.removeItem(at: target) }
        let locked = try Samples.writePNG(named: "locked.png", in: sources)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }

        let result = NookDesignReferenceFiles.importFile(
            at: locked, into: target, id: UUID(), collectionID: NookDesignCollection.globalID, now: Samples.day
        )

        #expect(result == .unreadable)
    }

    @Test func aPictureWhoseHeaderReadsButWhosePreviewCannotBeWrittenIsTold() async throws {
        let sources = try Samples.temporaryFolder("trouble")
        let target = try Samples.temporaryFolder("trouble-shelf")
        defer { try? FileManager.default.removeItem(at: sources); try? FileManager.default.removeItem(at: target) }
        let picture = try Samples.writePNG(named: "fine.png", in: sources)
        let id = UUID()
        // A folder stands where the preview is written.
        let blocker = NookDesignReferenceFiles.thumbnailURL(for: id, in: target)
        try FileManager.default.createDirectory(at: blocker.appendingPathComponent("in-the-way"), withIntermediateDirectories: true)

        let result = NookDesignReferenceFiles.importFile(
            at: picture, into: target, id: id, collectionID: NookDesignCollection.globalID, now: Samples.day
        )

        #expect(result == .previewFailed)
        // A failed add leaves no copy of the picture behind.
        #expect(!FileManager.default.fileExists(atPath: NookDesignReferenceFiles.folderURL(for: id, in: target).path))
    }

    @Test func eachTroubleHasItsOwnLineOnTheCard() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let sources = try Samples.temporaryFolder("trouble")
        defer { try? FileManager.default.removeItem(at: sources) }
        let words = sources.appendingPathComponent("words.txt")
        try Data("words".utf8).write(to: words)
        let locked = try Samples.writePNG(named: "locked.png", in: sources)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }

        await fixture.kit.addReference(fileAt: words).value
        let notAPicture = fixture.kit.notice?.text
        await fixture.kit.addReference(fileAt: locked).value
        let unreadable = fixture.kit.notice?.text

        #expect(notAPicture == text("nook.design.notice.notAPicture"))
        #expect(unreadable == text("nook.design.notice.referenceUnreadable"))
        #expect(text("nook.design.notice.referencePreviewFailed") != notAPicture)
        #expect(text("nook.design.notice.referencePreviewFailed") != unreadable)
    }
}

// MARK: - B12: a shortcut that did not take is reported where the user is

@MainActor
@Suite struct NookDesignShortcutTruthTests {
    private static let combo = AgentHotkeyCombo(keyCode: 8, modifiers: [.control, .option])

    @Test func noShortcutAndAWorkingOneLeaveNothingStanding() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        #expect(fixture.kit.standingNotice == nil)
        fixture.kit.hotkey.setCombo(Self.combo)
        #expect(fixture.kit.hotkey.status == .ready)
        #expect(fixture.kit.standingNotice == nil)
    }

    @Test func aShortcutMacOSRefusedStandsInTheCardUntilItIsFixed() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        fixture.registrar.refusalCode = -9878

        fixture.kit.hotkey.setCombo(Self.combo)

        #expect(fixture.kit.standingNotice?.text == text("nook.design.standing.failed", -9878))
        #expect(fixture.kit.standingNotice?.opensSettings == true)
        fixture.kit.hotkey.clear()
        #expect(fixture.kit.standingNotice == nil)
    }

    @Test func aShortcutMacOSUsesItselfAndOneThatBreaksTheRulesStandToo() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        fixture.registrar.system = [Self.combo]
        fixture.kit.hotkey.setCombo(Self.combo)
        #expect(fixture.kit.standingNotice?.text == text("nook.design.standing.system"))

        let defaults = MemoryDefaults()
        defaults.set(AgentHotkeyCombo(keyCode: 8, modifiers: [.command, .shift]).storageValue, forKey: NookDesignHotkeyController.comboKey)
        let kit = NookDesignKit(folder: fixture.folder, defaults: defaults)
        #expect(kit.standingNotice?.text == text("nook.design.standing.invalid"))
    }

    @Test func switchingTheWidgetOnWithKeysThatAreTakenSaysSoAndOffersSettings() async throws {
        let (fixture, nook) = try await startedFixture("standing")
        defer { fixture.cleanUp() }
        fixture.kit.hotkey.agentShortcuts = { [Self.combo] }
        fixture.kit.hotkey.setLive(false)
        fixture.kit.setLive(false)
        // The shortcut was saved while the widget was off, and an agent shortcut now has the keys.
        fixture.kit.hotkey.setCombo(AgentHotkeyCombo(keyCode: 9, modifiers: [.control, .option]))
        fixture.kit.hotkey.agentShortcuts = { [AgentHotkeyCombo(keyCode: 9, modifiers: [.control, .option])] }

        fixture.kit.setLive(true)

        #expect(fixture.kit.standingNotice?.text == text("nook.design.standing.agent"))
        #expect(fixture.kit.standingNotice?.opensSettings == true)
        #expect(fixture.kit.notice?.kind == .error, "said at once, not only standing")
        #expect(nook.transient?.symbol == "exclamationmark.triangle")
        var opened = 0
        fixture.kit.openSettings = { opened += 1 }
        fixture.kit.openSettingsFromStandingNotice()
        #expect(opened == 1)
    }
}

// MARK: - B13: two steps before every picture goes

@Suite struct NookDesignTwoStepTests {
    @Test func theFirstPressAsksAndTheSecondDoesIt() {
        var ask = NookDesignTwoStepAsk()
        #expect(!ask.isAsking)
        let first = ask.press()
        #expect(!first)
        #expect(ask.isAsking)
        let second = ask.press()
        #expect(second)
        #expect(!ask.isAsking)
        // And it asks again the next time.
        let third = ask.press()
        #expect(!third)
    }

    @Test func givingUpPutsTheAskAway() {
        var ask = NookDesignTwoStepAsk()
        _ = ask.press()
        ask.cancel()
        #expect(!ask.isAsking)
        let next = ask.press()
        #expect(!next)
    }
}

// MARK: - B8: a success is said after its write worked

@MainActor
@Suite struct NookDesignSaidAfterTheWriteTests {
    private func lockFolder(_ fixture: NookDesignFixture) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.folder.path)
    }

    private func unlockFolder(_ fixture: NookDesignFixture) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.folder.path)
    }

    @Test func aColorIsSaidToBeAddedOnlyOnceItIsOnDisk() async throws {
        let fixture = try await NookDesignFixture()
        defer { unlockFolder(fixture); fixture.cleanUp() }

        fixture.kit.addColor(Samples.orange)
        #expect(fixture.kit.notice == nil, "said before the write")
        #expect(await Samples.wait { fixture.kit.notice?.kind == .done })
        #expect(fixture.kit.notice?.text == text("nook.design.notice.added", "#FF8800"))
        await fixture.kit.flush()
        let reader = NookDesignPaletteStore(folder: fixture.folder)
        await reader.load()
        #expect(reader.colorCount == 1)
    }

    @Test func aColorThatCouldNotBeSavedIsNeverSaidToBeAdded() async throws {
        let fixture = try await NookDesignFixture()
        defer { unlockFolder(fixture); fixture.cleanUp() }
        try lockFolder(fixture)

        fixture.kit.addColor(Samples.orange)

        #expect(await Samples.wait { fixture.kit.notice?.kind == .error })
        #expect(fixture.kit.notice?.text == text("nook.design.notice.saveFailed"))
        try await Task.sleep(for: .milliseconds(100))
        #expect(fixture.kit.notice?.text == text("nook.design.notice.saveFailed"), "a success took the place of the failure")
    }

    @Test func aLinkIsSaidToBeSavedOnlyOnceItIsOnDisk() async throws {
        let fixture = try await NookDesignFixture()
        defer { unlockFolder(fixture); fixture.cleanUp() }

        fixture.kit.addLink(text: "https://example.com/x")
        #expect(fixture.kit.notice == nil)
        #expect(await Samples.wait { fixture.kit.notice?.kind == .done })

        try lockFolder(fixture)
        fixture.kit.addLink(text: "https://example.com/y")
        #expect(await Samples.wait { fixture.kit.notice?.text == text("nook.design.notice.saveFailed") })
    }

    @Test func anImportIsSaidOnlyOnceItIsOnDisk() async throws {
        let fixture = try await NookDesignFixture()
        defer { unlockFolder(fixture); fixture.cleanUp() }
        let one = NookDesignImport(palettes: [NookDesignExchangePalette(name: "A", colors: [.init(name: "", color: Samples.orange, isFavorite: false)])])

        fixture.kit.finishImport(.success(one))
        #expect(fixture.kit.notice == nil)
        #expect(await Samples.wait { fixture.kit.notice?.text == text("nook.design.notice.imported", 1, 1) })

        try lockFolder(fixture)
        fixture.kit.finishImport(.success(one))
        #expect(await Samples.wait { fixture.kit.notice?.text == text("nook.design.notice.saveFailed") })
    }
}
