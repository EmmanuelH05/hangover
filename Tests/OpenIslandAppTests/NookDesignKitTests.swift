import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import OpenIslandApp

private typealias Samples = NookDesignSamples

// MARK: - The widget

@Suite struct NookDesignWidgetTests {
    @Test func theDesignKitIsOffUntilSwitchedOnAndNoTemplatePlacesIt() {
        #expect(NookWidgetKind.allCases.contains(.design))
        #expect(!NookWidgetKind.defaultEnabled.contains(.design))
        #expect(NookWidgetKind.design.systemImage == "paintpalette")
        for template in PersonalizationTemplate.all {
            #expect(!template.widgetKinds.contains(.design), "\(template.id)")
        }
    }

    /// The widgets page of the tour lists every widget, and says which four
    /// start switched off: the kit and Link to MP3 among them.
    @Test func theWelcomeTourOffersEveryWidgetAndFourStartSwitchedOff() {
        #expect(NookWidgetKind.allCases.count == 10)
        #expect(NookWidgetKind.allCases.suffix(2) == [.design, .linkAudio], "the new ones come last")
        #expect(NookWidgetKind.startsOff == [.mirror, .weather, .design, .linkAudio])
        #expect(NookWidgetKind.startsOff == NookWidgetKind.allCases.filter { !NookWidgetKind.defaultEnabled.contains($0) })
        #expect(NookWidgetKind.tools == [.design, .linkAudio])
    }

    @Test @MainActor func aModelThatWasNeverStartedReadsNothingAndOpensNothing() async {
        // A store of its own: the standard store is never written.
        let nook = NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)

        nook.setWidget(.design, enabled: true)
        try? await Task.sleep(for: .milliseconds(30))

        #expect(!nook.design.palettes.isLoaded)
        #expect(!nook.design.references.isLoaded)
        #expect(!nook.design.pickColor(from: .shortcut))
        #expect(nook.design.pasteReference().isEmpty)
        #expect(nook.design.hotkey.status == .none || nook.design.hotkey.status == .inactive)
    }
}

// MARK: - Copying and typing colors

@MainActor
@Suite struct NookDesignKitColorTests {
    @Test func aKitNobodyWiredDoesNothing() async throws {
        let folder = try Samples.temporaryFolder("bare")
        defer { try? FileManager.default.removeItem(at: folder) }
        let kit = NookDesignKit(folder: folder, defaults: MemoryDefaults())

        #expect(!kit.copy(Samples.orange))
        #expect(!kit.pickColor(from: .island))
        #expect(kit.openReference(UUID()) == nil)
        #expect(kit.pasteReference().isEmpty)
        #expect(kit.addColor(Samples.orange) == .unavailable)
        kit.showPaletteEditor()
        #expect(!kit.isSampling)
        #expect((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) == [])
    }

    @Test func aClickCopiesInTheChosenFormat() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit
        let id = UUID()

        #expect(kit.copyFormat == .hex)
        #expect(kit.copy(Samples.orange, from: id))
        kit.copyFormat = .rgb
        kit.copy(Samples.orange)
        kit.copyFormat = .hsl
        kit.copy(Samples.scrim)
        kit.copyFormat = .hexBare
        kit.copy(Samples.orange)
        // A format named in the menu wins over the chosen one.
        kit.copy(Samples.orange, as: .hex)

        #expect(fixture.copies.texts == [
            "#FF8800", "rgb(255, 136, 0)", "hsla(0, 0%, 0%, 0.5)", "FF8800", "#FF8800",
        ])
        #expect(kit.notice?.kind == .done)
        #expect(kit.notice?.swatch == Samples.orange)
    }

    @Test func theCopiedSwatchShowsATickAndACopyIsConfirmed() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let id = UUID()

        fixture.kit.copy(Samples.orange, from: id)

        #expect(fixture.kit.justCopiedID == id)
        #expect(fixture.kit.notice?.text.contains("#FF8800") == true)
    }

    @Test func aCopyThatDidNotTakeSaysSo() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        fixture.copies.succeeds = false

        #expect(!fixture.kit.copy(Samples.orange, from: UUID()))
        #expect(fixture.kit.notice?.kind == .error)
        #expect(fixture.kit.justCopiedID == nil)
        #expect(fixture.copies.texts.isEmpty)
    }

    @Test func theChoicesAreSavedAndReadBack() async throws {
        let defaults = MemoryDefaults()
        let first = try await NookDesignFixture(defaults: defaults)
        defer { first.cleanUp() }
        #expect(first.kit.tab == .colors)
        #expect(!first.kit.savesPicksToPalette)

        first.kit.tab = .references
        first.kit.copyFormat = .hsl
        first.kit.savesPicksToPalette = true

        #expect(Set(defaults.all.keys) == [NookDesignKit.tabKey, NookDesignKit.formatKey, NookDesignKit.savesPicksKey])
        let second = try await NookDesignFixture(defaults: defaults)
        defer { second.cleanUp() }
        #expect(second.kit.tab == .references)
        #expect(second.kit.copyFormat == .hsl)
        #expect(second.kit.savesPicksToPalette)
    }

    @Test func aTypedColorIsAddedOnceAndABadOneIsExplained() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit

        guard case let .added(swatch) = kit.addColor(text: "  rgb(255, 136, 0) ", name: "Primary") else {
            Issue.record("the color was not added")
            return
        }
        #expect(swatch.color == Samples.orange)
        #expect(swatch.name == "Primary")
        // The first color makes its own palette.
        #expect(kit.palettes.palettes.count == 1)

        #expect(kit.addColor(text: "#f80") == .duplicate(swatch))
        #expect(kit.notice?.kind == .info)
        #expect(kit.addColor(text: "orange-ish") == .notAColor)
        #expect(kit.palettes.colorCount == 1)
        #expect(fixture.copies.texts.isEmpty)
    }
}

// MARK: - The eyedropper

@MainActor
@Suite struct NookDesignEyedropperTests {
    @Test func aPickFromTheCardClosesTheIslandFirstAndAsksTheSamplerOnce() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        var islandCloses = 0
        fixture.kit.willSampleFromIsland = { islandCloses += 1 }

        #expect(fixture.kit.pickColor(from: .island))

        #expect(islandCloses == 1)
        #expect(fixture.sampler.sampleCount == 1)
        #expect(fixture.kit.isSampling)
        // A second press while the loupe is up starts nothing.
        #expect(!fixture.kit.pickColor(from: .island))
        #expect(!fixture.kit.pickColor(from: .shortcut))
        #expect(fixture.sampler.sampleCount == 1)
        #expect(islandCloses == 1)
    }

    @Test func aPickFromTheShortcutLeavesTheIslandAsItIs() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        var islandCloses = 0
        fixture.kit.willSampleFromIsland = { islandCloses += 1 }

        #expect(fixture.kit.pickColor(from: .shortcut))

        #expect(islandCloses == 0)
        #expect(fixture.sampler.sampleCount == 1)
    }

    @Test func cancellingAPickChangesNothing() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit
        kit.savesPicksToPalette = true
        kit.addColor(Samples.teal)
        let before = kit.palettes.library
        let noticeBefore = kit.notice

        kit.pickColor(from: .island)
        fixture.sampler.finish(nil)

        #expect(!kit.isSampling)
        #expect(kit.palettes.library == before)
        #expect(kit.palettes.recents.isEmpty)
        #expect(kit.lastPick == nil)
        #expect(fixture.copies.texts.isEmpty)
        #expect(kit.notice == noticeBefore)
        // The next pick starts as usual.
        #expect(kit.pickColor(from: .island))
    }

    @Test func aPickedColorIsCopiedAtOnceAndKeptUnderRecentColors() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit
        kit.copyFormat = .rgb

        kit.pickColor(from: .shortcut)
        fixture.sampler.finish(Samples.orange)

        #expect(!kit.isSampling)
        #expect(fixture.copies.texts == ["rgb(255, 136, 0)"])
        #expect(kit.lastPick == Samples.orange)
        #expect(kit.palettes.recents.map(\.color) == [Samples.orange])
        #expect(kit.justCopiedID == kit.palettes.recents.first?.id)
        #expect(kit.notice?.kind == .done)
        #expect(kit.notice?.swatch == Samples.orange)
        #expect(kit.notice?.text.contains("rgb(255, 136, 0)") == true)
        // Saving to the palette is off to begin with.
        #expect(kit.palettes.palettes.isEmpty)
    }

    @Test func aPickIsSavedToThePaletteOnlyWhenAskedAndOnlyOnce() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit
        kit.savesPicksToPalette = true

        kit.pickColor(from: .shortcut)
        fixture.sampler.finish(Samples.orange)
        kit.pickColor(from: .shortcut)
        fixture.sampler.finish(Samples.teal)
        kit.pickColor(from: .shortcut)
        fixture.sampler.finish(Samples.orange)

        #expect(kit.palettes.activePalette?.swatches.map(\.color) == [Samples.orange, Samples.teal])
        // The color picked again moved to the front of the recent colors.
        #expect(kit.palettes.recents.map(\.color) == [Samples.orange, Samples.teal])
        #expect(fixture.copies.texts == ["#FF8800", "#2EC4B6", "#FF8800"])
    }

    @Test func aPickedColorIsAlwaysOpaque() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }

        fixture.kit.pickColor(from: .shortcut)
        fixture.sampler.finish(NookDesignColor(red: 255, green: 136, blue: 0, alpha: 40))

        #expect(fixture.kit.lastPick == Samples.orange)
        #expect(fixture.copies.texts == ["#FF8800"])
    }

    @Test func aPickThatCouldNotBeCopiedIsStillKept() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        fixture.copies.succeeds = false

        fixture.kit.pickColor(from: .shortcut)
        fixture.sampler.finish(Samples.orange)

        #expect(fixture.kit.notice?.kind == .error)
        #expect(fixture.kit.palettes.recents.map(\.color) == [Samples.orange])
    }

    @Test func nothingIsPickedWhileTheWidgetIsOff() async throws {
        let fixture = try await NookDesignFixture(isLive: false)
        defer { fixture.cleanUp() }

        #expect(!fixture.kit.pickColor(from: .shortcut))
        #expect(fixture.sampler.sampleCount == 0)
    }

    @Test func recentPicksComeBackOnTheNextLaunch() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        fixture.kit.pickColor(from: .shortcut)
        fixture.sampler.finish(Samples.orange)
        await fixture.kit.flush()

        let next = NookDesignKit(folder: fixture.folder, defaults: MemoryDefaults())
        await next.load()

        #expect(next.palettes.recents.map(\.color) == [Samples.orange])
        // The last pick itself is this session's.
        #expect(next.lastPick == nil)
    }
}

// MARK: - Reference pictures and their panels

@MainActor
@Suite struct NookDesignKitReferenceTests {
    @Test func pastingWithNoPictureOnTheClipboardSaysSo() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }

        #expect(fixture.kit.pasteReference().isEmpty)

        #expect(fixture.clipboard.reads == 1)
        #expect(fixture.kit.notice?.kind == .info)
        #expect(fixture.kit.references.items.isEmpty)
    }

    @Test func aPastedPictureLandsOnTheShelf() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        fixture.clipboard.pictures = .data(Samples.pngData(width: 50, height: 50))

        for task in fixture.kit.pasteReference() { await task.value }

        #expect(fixture.kit.references.items.count == 1)
        #expect(fixture.kit.references.items.first?.pixelWidth == 50)
        #expect(fixture.kit.references.items.first?.name.isEmpty == false)
        #expect(fixture.kit.tab == .references)
        #expect(fixture.kit.notice?.kind == .done)
    }

    @Test func pictureFilesCopiedInFinderArePastedAsFiles() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let sources = try Samples.temporaryFolder("copied")
        defer { try? FileManager.default.removeItem(at: sources) }
        let first = try Samples.writePNG(named: "one.png", in: sources)
        let second = try Samples.writePNG(named: "two.png", in: sources)
        fixture.clipboard.pictures = .files([first, second])

        for task in fixture.kit.pasteReference() { await task.value }

        #expect(Set(fixture.kit.references.items.map(\.name)) == ["one", "two"])
    }

    @Test func aFileThatIsNotAPictureIsTurnedAwayWithAReason() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let sources = try Samples.temporaryFolder("text")
        defer { try? FileManager.default.removeItem(at: sources) }
        let text = sources.appendingPathComponent("notes.txt")
        try Data("words".utf8).write(to: text)

        await fixture.kit.addReference(fileAt: text).value

        #expect(fixture.kit.references.items.isEmpty)
        #expect(fixture.kit.notice?.kind == .error)
        #expect(fixture.kit.tab == .colors)
    }

    @Test func aDroppedPictureFileIsTaken() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let sources = try Samples.temporaryFolder("dropped")
        defer { try? FileManager.default.removeItem(at: sources) }
        let url = try Samples.writePNG(named: "dropped.png", in: sources)

        #expect(fixture.kit.handlePictureDrop([NSItemProvider(object: url as NSURL)]))
        let landed = await Samples.wait { fixture.kit.references.items.count == 1 }

        #expect(landed)
        #expect(fixture.kit.references.items.first?.name == "dropped")
        #expect(await Samples.wait { fixture.kit.tab == .references })
    }

    @Test func aDroppedPictureWithNoFileBehindItIsTakenAsData() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let provider = NSItemProvider(
            item: Samples.pngData(width: 24, height: 12) as NSData,
            typeIdentifier: UTType.png.identifier
        )

        #expect(fixture.kit.handlePictureDrop([provider]))
        let landed = await Samples.wait { fixture.kit.references.items.count == 1 }

        #expect(landed)
        #expect(fixture.kit.references.items.first?.pixelWidth == 24)
    }

    @Test func aDropThatHoldsNoPictureIsNotTaken() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let text = NSItemProvider(item: "just words" as NSString, typeIdentifier: UTType.plainText.identifier)

        #expect(!fixture.kit.handlePictureDrop([text]))
        #expect(!fixture.kit.handlePictureDrop([]))
        #expect(fixture.kit.tab == .colors)
    }

    @Test func aClickFloatsAPictureInThePanelItsShapeNeeds() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.addPicture(width: 300, height: 100)

        await fixture.kit.openReference(item.id)?.value

        #expect(fixture.presenter.presented == [.init(id: item.id, slot: 0, pixelWidth: 300)])
        #expect(fixture.kit.openPanels == [item.id: 0])
    }

    @Test func aSecondClickBringsThePanelForwardAndOpensNoSecondOne() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.addPicture()

        // Two clicks before the picture is even read.
        let first = fixture.kit.openReference(item.id)
        let second = fixture.kit.openReference(item.id)
        await first?.value
        #expect(second == nil)
        #expect(fixture.kit.openReference(item.id) == nil)

        #expect(fixture.presenter.presented.count == 1)
        #expect(fixture.presenter.focused == [item.id, item.id])
    }

    @Test func noMorePanelsOpenThanTheCapAndASlotIsUsedAgain() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        var items: [NookDesignReference] = []
        for index in 0...NookDesignPanelRules.maxOpenPanels {
            items.append(try await fixture.addPicture(named: "p\(index).png"))
        }

        for item in items.prefix(NookDesignPanelRules.maxOpenPanels) {
            await fixture.kit.openReference(item.id)?.value
        }
        #expect(fixture.presenter.presented.map(\.slot) == Array(0..<NookDesignPanelRules.maxOpenPanels))

        // One more than the cap is refused, and says why.
        let extra = try #require(items.last)
        #expect(fixture.kit.openReference(extra.id) == nil)
        #expect(fixture.presenter.presented.count == NookDesignPanelRules.maxOpenPanels)
        #expect(fixture.kit.notice?.kind == .info)

        // The user closes the third panel. The next one takes its place.
        fixture.presenter.userCloses(items[2].id)
        #expect(fixture.kit.openPanels[items[2].id] == nil)
        await fixture.kit.openReference(extra.id)?.value
        #expect(fixture.presenter.presented.last == .init(id: extra.id, slot: 2, pixelWidth: 60))
    }

    @Test func removingAPictureClosesItsPanelAndDeletesItsFiles() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.addPicture()
        let file = fixture.kit.references.fileURL(for: item)
        await fixture.kit.openReference(item.id)?.value
        fixture.kit.renamingReferenceID = item.id

        await fixture.kit.removeReference(item.id).value

        #expect(fixture.presenter.closed == [item.id])
        #expect(fixture.kit.openPanels.isEmpty)
        #expect(fixture.kit.renamingReferenceID == nil)
        #expect(fixture.kit.references.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func aPictureWhoseFileIsGoneOpensNothingAndFreesItsSlot() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.addPicture()
        try FileManager.default.removeItem(at: fixture.kit.references.fileURL(for: item))

        await fixture.kit.openReference(item.id)?.value

        #expect(fixture.presenter.presented.isEmpty)
        #expect(fixture.kit.openPanels.isEmpty)
        #expect(fixture.kit.notice?.kind == .error)
    }

    @Test func switchingTheWidgetOffClosesEveryPanelAndTheEditor() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.addPicture()
        await fixture.kit.openReference(item.id)?.value
        fixture.kit.showPaletteEditor()
        #expect(fixture.editor.showCount == 1)

        fixture.kit.setLive(false)

        #expect(fixture.presenter.closeAllCount == 1)
        #expect(fixture.kit.openPanels.isEmpty)
        #expect(fixture.editor.closeCount == 1)
        // While it is off a click opens nothing.
        #expect(fixture.kit.openReference(item.id) == nil)
        fixture.kit.showPaletteEditor()
        #expect(fixture.editor.showCount == 1)
    }

    @Test func closingAllPanelsFromTheCardClosesThemOnce() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.addPicture()
        await fixture.kit.openReference(item.id)?.value

        fixture.kit.closeAllReferencePanels()
        fixture.kit.closeAllReferencePanels()

        #expect(fixture.presenter.closeAllCount == 1)
        #expect(fixture.kit.openPanels.isEmpty)
    }
}

// MARK: - Import and export through the kit

@MainActor
@Suite struct NookDesignKitExchangeTests {
    @Test func aPaletteExportedToAFileImportsAsTheSameColors() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit
        kit.addColor(text: "#FF8800", name: "Primary")
        kit.addColor(text: "rgba(0, 0, 0, 0.5)", name: "Scrim")
        let palette = try #require(kit.palettes.activePalette)
        kit.palettes.toggleFavorite(palette.swatches[1].id)
        let file = fixture.folder.appendingPathComponent("out.palette.json")

        await kit.exportPalettes([palette.id], to: file).value
        #expect(kit.notice?.kind == .done)
        await kit.importPalettes(fromFileAt: file).value

        #expect(kit.palettes.palettes.count == 2)
        let imported = try #require(kit.palettes.palettes.last)
        #expect(imported.id != palette.id)
        #expect(imported.name == palette.name)
        #expect(imported.swatches.map(\.color) == [Samples.orange, Samples.scrim])
        #expect(imported.swatches.map(\.name) == ["Primary", "Scrim"])
        #expect(imported.swatches.map(\.isFavorite) == [false, true])
        // The imported palette is the one in front now.
        #expect(kit.palettes.activePalette?.id == imported.id)
        #expect(kit.notice?.kind == .done)
    }

    @Test func aFileThatIsNotAPaletteChangesNothingAndSaysWhy() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let file = fixture.folder.appendingPathComponent("broken.json")
        try Data("{ nope".utf8).write(to: file)

        await fixture.kit.importPalettes(fromFileAt: file).value
        #expect(fixture.kit.notice?.kind == .error)
        await fixture.kit.importPalettes(fromFileAt: fixture.folder.appendingPathComponent("missing.json")).value
        #expect(fixture.kit.notice?.kind == .error)

        #expect(fixture.kit.palettes.palettes.isEmpty)
    }

    @Test func importSaysHowMuchWasLeftOut() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let imported = NookDesignImport(
            palettes: [NookDesignExchangePalette(name: "A", colors: [.init(name: "", color: Samples.orange, isFavorite: false)])],
            skippedColors: 2,
            duplicateColors: 1
        )

        fixture.kit.finishImport(.success(imported))

        #expect(fixture.kit.palettes.colorCount == 1)
        #expect(await Samples.wait { fixture.kit.notice != nil })
        #expect(fixture.kit.notice?.text.contains("3") == true)
    }
}
