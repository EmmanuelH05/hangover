import AppKit
import Foundation
import OpenIslandCore
import SwiftUI
import Testing
@testable import OpenIslandApp

private typealias Samples = NookDesignSamples

/// An import of one palette holding `count` different colors.
private func importOf(colors count: Int, named name: String = "Full") -> NookDesignImport {
    let entries = (0..<count).map {
        NookDesignExchangePalette.Entry(
            name: "",
            color: NookDesignColor(red: UInt8($0 % 256), green: UInt8($0 / 256), blue: 9),
            isFavorite: false
        )
    }
    return NookDesignImport(palettes: [NookDesignExchangePalette(name: name, colors: entries)])
}

// MARK: - Typing a color into the card

@MainActor
@Suite struct NookDesignEntryEdgeTests {
    @Test(arguments: ["", "   ", "\n", "orange", "#12", "rgb(1, 2)", "#" + String(repeating: "f", count: 80)])
    func textThatIsNotAColorAddsNothingAndMakesNoPalette(text: String) async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }

        #expect(fixture.kit.addColor(text: text) == .notAColor)

        #expect(fixture.kit.palettes.palettes.isEmpty, "a palette was made for \(text.debugDescription)")
        #expect(fixture.kit.notice?.kind == .info)
        #expect(fixture.copies.texts.isEmpty)
    }

    @Test func aColorPastedWithTabsAndLineBreaksIsAdded() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }

        guard case .added = fixture.kit.addColor(text: "rgb(255,\n\t136,\n\t0)") else {
            Issue.record("not added")
            return
        }
        #expect(fixture.kit.palettes.activePalette?.swatches.map(\.color) == [Samples.orange])
    }

    @Test func theSameColorInAnotherSpellingIsOneColorAndOneStepAwayIsAnother() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit

        guard case let .added(first) = kit.addColor(text: "#FF8800") else {
            Issue.record("not added")
            return
        }
        for text in ["#f80", "ff8800", "rgb(255, 136, 0)", "hsl(32, 100%, 50%)", "rgba(255,136,0,1)", "#FF8800FF"] {
            #expect(kit.addColor(text: text) == .duplicate(first), "\(text)")
            #expect(kit.notice?.kind == .info)
        }
        #expect(kit.palettes.colorCount == 1)

        for text in ["#FF8801", "#FF880080", "#FE8800", "#FF8700", "#FF8800FE"] {
            guard case .added = kit.addColor(text: text) else {
                Issue.record("\(text) was taken for a duplicate")
                continue
            }
        }
        #expect(kit.palettes.colorCount == 6)
    }

    @Test func aColorForAPaletteThatIsGoneIsUnavailableAndMakesNoPalette() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }

        #expect(fixture.kit.addColor(Samples.orange, to: UUID()) == .unavailable)
        #expect(fixture.kit.palettes.palettes.isEmpty)
    }

    @Test func aFullPaletteSaysSoAndKeepsItsColors() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit
        kit.palettes.importPalettes(importOf(colors: NookDesignLibrary.maxSwatchesPerPalette), untitled: "U")
        #expect(kit.palettes.colorCount == NookDesignLibrary.maxSwatchesPerPalette)

        #expect(kit.addColor(text: "#010203") == .full)
        #expect(kit.notice?.kind == .error)
        // A color the palette already has is a duplicate, and a full palette does not say otherwise.
        let known = NookDesignColor(red: 5, green: 0, blue: 9)
        guard case .duplicate = kit.addColor(known) else {
            Issue.record("expected a duplicate")
            return
        }
        #expect(kit.palettes.colorCount == NookDesignLibrary.maxSwatchesPerPalette)
    }

    @Test func aNameIsCutAndAColorMayBeAddedToAnyPalette() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit
        let first = try #require(kit.palettes.addPalette(named: "First"))
        let second = try #require(kit.palettes.addPalette(named: "Second"))

        guard case let .added(swatch) = kit.addColor(text: "#0f0", name: String(repeating: "x", count: 100), to: first.id) else {
            Issue.record("not added")
            return
        }
        #expect(swatch.name.count == NookDesignLibrary.maxNameLength)
        #expect(kit.palettes.palettes.first { $0.id == first.id }?.swatches.count == 1)
        #expect(kit.palettes.palettes.first { $0.id == second.id }?.swatches.isEmpty == true)
    }
}

// MARK: - The eyedropper

@MainActor
@Suite struct NookDesignPickEdgeTests {
    @Test func cancellingWithNoPaletteAndSavingOnMakesNoPaletteAndNoRecentColor() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit
        kit.savesPicksToPalette = true

        kit.pickColor(from: .shortcut)
        fixture.sampler.finish(nil)

        #expect(kit.palettes.palettes.isEmpty)
        #expect(kit.palettes.recents.isEmpty)
        #expect(kit.notice == nil)
        #expect(kit.justCopiedID == nil)
        #expect(fixture.copies.texts.isEmpty)
        // The loupe can start again from either place.
        #expect(kit.pickColor(from: .island))
        #expect(fixture.sampler.sampleCount == 2)
    }

    @Test func aPickWithNoPaletteAndSavingOffKeepsOnlyARecentColor() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }

        fixture.kit.pickColor(from: .shortcut)
        fixture.sampler.finish(Samples.teal)

        #expect(fixture.kit.palettes.palettes.isEmpty)
        #expect(fixture.kit.palettes.recents.map(\.color) == [Samples.teal])
        #expect(fixture.copies.texts == ["#2EC4B6"])
    }

    @Test func aPickWithNoPaletteAndSavingOnMakesTheFirstPaletteToHoldIt() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit
        kit.savesPicksToPalette = true

        kit.pickColor(from: .shortcut)
        fixture.sampler.finish(Samples.teal)

        #expect(kit.palettes.palettes.count == 1)
        #expect(kit.palettes.activePalette?.name == LanguageManager.shared.t("nook.design.palette.default"))
        #expect(kit.palettes.activePalette?.swatches.map(\.color) == [Samples.teal])
        #expect(kit.palettes.recents.map(\.color) == [Samples.teal])
        #expect(kit.notice?.text == String(format: LanguageManager.shared.t("nook.design.notice.picked.saved"), "#2EC4B6"))
    }

    @Test func aPickAlreadyInThePaletteIsSaidToBeKnownAndAddsNoSecondCopy() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit
        kit.savesPicksToPalette = true
        kit.addColor(Samples.orange)

        kit.pickColor(from: .shortcut)
        fixture.sampler.finish(Samples.orange)

        #expect(kit.palettes.colorCount == 1)
        #expect(kit.notice?.text == String(format: LanguageManager.shared.t("nook.design.notice.picked.known"), "#FF8800"))
    }

    @Test func aPickForAFullPaletteIsCopiedAndTheCardSaysItWasNotSaved() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit
        kit.savesPicksToPalette = true
        kit.palettes.importPalettes(importOf(colors: NookDesignLibrary.maxSwatchesPerPalette), untitled: "U")

        kit.pickColor(from: .shortcut)
        fixture.sampler.finish(Samples.orange)

        #expect(kit.palettes.colorCount == NookDesignLibrary.maxSwatchesPerPalette)
        #expect(kit.palettes.recents.map(\.color) == [Samples.orange])
        #expect(fixture.copies.texts == ["#FF8800"])
        #expect(kit.notice?.kind == .done)
        #expect(kit.notice?.text == String(format: LanguageManager.shared.t("nook.design.notice.picked.full"), "#FF8800"))
    }

    @Test func afterThirteenPicksTheTwelveNewestAreKept() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit

        for index in 0..<(NookDesignLibrary.maxRecents + 1) {
            #expect(kit.pickColor(from: .shortcut))
            fixture.sampler.finish(NookDesignColor(red: UInt8(index), green: 1, blue: 2))
        }

        #expect(kit.palettes.recents.count == NookDesignLibrary.maxRecents)
        #expect(kit.palettes.recents.first?.color.red == 12)
        #expect(kit.palettes.recents.last?.color.red == 1)
        #expect(fixture.copies.texts.count == NookDesignLibrary.maxRecents + 1)
    }

    @Test func aSecondFinishForTheSamePickChangesNothing() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }

        fixture.kit.pickColor(from: .shortcut)
        fixture.sampler.finish(Samples.orange)
        fixture.sampler.finish(Samples.teal)

        #expect(fixture.kit.palettes.recents.map(\.color) == [Samples.orange])
        #expect(fixture.copies.texts == ["#FF8800"])
    }

    @Test func thePickIsCopiedInTheChosenFormatWhateverItsAlpha() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }

        for format in NookDesignColorFormat.allCases {
            fixture.kit.copyFormat = format
            fixture.kit.pickColor(from: .shortcut)
            fixture.sampler.finish(NookDesignColor(red: 255, green: 136, blue: 0, alpha: 3))
        }

        #expect(fixture.copies.texts == NookDesignColorFormat.allCases.map { $0.text(for: Samples.orange) })
    }

    @Test func aKitThatWasNeverGivenAClipboardKeepsThePickAndSaysItWasNotCopied() async throws {
        let folder = try Samples.temporaryFolder("noclip")
        defer { try? FileManager.default.removeItem(at: folder) }
        let kit = NookDesignKit(folder: folder, defaults: MemoryDefaults())
        let sampler = FakeColorSampler()
        kit.activate(NookDesignServices(
            sampler: sampler,
            presenter: FakeReferencePresenter(),
            editor: FakeEditorPresenter(),
            pictureClipboard: FakePictureClipboard(),
            hotkeyRegistrar: FakeDesignHotkeyRegistrar(),
            linkOpener: FakeLinkOpener()
        ))
        kit.setLive(true)
        await kit.load()

        kit.pickColor(from: .shortcut)
        sampler.finish(Samples.orange)

        #expect(kit.notice?.kind == .error)
        #expect(kit.notice?.text == String(format: LanguageManager.shared.t("nook.design.notice.picked.notCopied"), "#FF8800"))
        #expect(kit.palettes.recents.map(\.color) == [Samples.orange])
    }

    @Test func theLoupeCanStartAgainAfterTheWidgetWasSwitchedOffAndOn() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit

        kit.setLive(false)
        #expect(!kit.pickColor(from: .shortcut))
        kit.setLive(true)

        #expect(kit.pickColor(from: .shortcut))
        #expect(fixture.sampler.sampleCount == 1)
    }

    @Test func theClosedIslandNoticeFitsItsWingForEveryFormatOfEveryColor() {
        let colors = [Samples.orange, Samples.white, Samples.ink, NookDesignColor(red: 255, green: 255, blue: 255), NookDesignColor(red: 100, green: 200, blue: 150)]
        for color in colors {
            for format in NookDesignColorFormat.allCases {
                let text = NookDesignKit.noticeText(for: color, copied: format.text(for: color))
                #expect(text.count <= 18, "\(text) is wider than the wing")
            }
        }
    }
}

// MARK: - Import and export through the kit

@MainActor
@Suite struct NookDesignKitExchangeEdgeTests {
    @Test func exportingPalettesThatAreNotThereWritesNothingAndSaysItFailed() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let file = fixture.folder.appendingPathComponent("none.palette.json")

        await fixture.kit.exportPalettes([UUID()], to: file).value
        #expect(fixture.kit.notice?.kind == .error)
        #expect(!FileManager.default.fileExists(atPath: file.path))

        await fixture.kit.exportPalettes([], to: file).value
        #expect(fixture.kit.notice?.kind == .error)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func exportingToAFolderThatIsNotThereSaysItFailed() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        fixture.kit.addColor(Samples.orange)
        let id = try #require(fixture.kit.palettes.activePalette?.id)
        await fixture.kit.palettes.flush()

        await fixture.kit.exportPalettes([id], to: fixture.folder.appendingPathComponent("no/such/folder/out.json")).value

        #expect(fixture.kit.notice?.kind == .error)
        #expect(fixture.kit.notice?.text.hasPrefix(String(LanguageManager.shared.t("nook.design.notice.exportWriteFailed").dropLast(2))) == true)
    }

    @Test func importingAFileThatIsTooBigOrIsAFolderOrIsGoneSaysWhyAndChangesNothing() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let big = fixture.folder.appendingPathComponent("big.json")
        try Data(repeating: UInt8(ascii: " "), count: NookDesignPaletteExchange.maxFileBytes + 1).write(to: big)

        await fixture.kit.importPalettes(fromFileAt: big).value
        #expect(fixture.kit.notice?.text == LanguageManager.shared.t("nook.design.notice.importTooLarge"))

        await fixture.kit.importPalettes(fromFileAt: fixture.folder).value
        #expect(fixture.kit.notice?.kind == .error)

        await fixture.kit.importPalettes(fromFileAt: fixture.folder.appendingPathComponent("gone.json")).value
        #expect(fixture.kit.notice?.kind == .error)

        #expect(fixture.kit.palettes.palettes.isEmpty)
    }

    @Test func importingIntoAFullShelfSaysItIsFullAndChangesNothing() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        for index in 0..<NookDesignLibrary.maxPalettes { fixture.kit.palettes.addPalette(named: "P\(index)") }
        let before = fixture.kit.palettes.library

        fixture.kit.finishImport(.success(importOf(colors: 3)))

        #expect(fixture.kit.palettes.library == before)
        #expect(fixture.kit.notice?.kind == .error)
        #expect(fixture.kit.notice?.text == LanguageManager.shared.t("nook.design.notice.importFull"))
    }

    @Test func everyFailureOfAnImportHasItsOwnLine() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        var seen = Set<String>()
        for failure in [NookDesignImportError.tooLarge, .notJSON, .noColors] {
            fixture.kit.finishImport(.failure(failure))
            #expect(fixture.kit.notice?.kind == .error)
            seen.insert(fixture.kit.notice?.text ?? "")
        }
        #expect(seen.count == 3)
        #expect(!seen.contains(""))
    }

    @Test func aPartlyReadFileSaysHowMuchWasLeftOut() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        var imported = importOf(colors: 4)
        imported.skippedColors = 5
        imported.duplicateColors = 2

        fixture.kit.finishImport(.success(imported))

        #expect(fixture.kit.palettes.colorCount == 4)
        // Something was left out. That is a warning, said once the write is done.
        #expect(await Samples.wait { fixture.kit.notice != nil })
        #expect(fixture.kit.notice?.kind == .error)
        #expect(fixture.kit.notice?.text.contains("7") == true)
    }
}

// MARK: - The reference shelf shows favorites first

@MainActor
@Suite struct NookDesignReferenceOrderTests {
    private func reference(_ name: String, favorite: Bool) -> NookDesignReference {
        NookDesignReference(
            id: UUID(), collectionID: NookDesignCollection.globalID, name: name, fileName: "original.png",
            pixelWidth: 10, pixelHeight: 10, isFavorite: favorite, addedAt: Samples.day
        )
    }

    @Test func favoritesComeFirstAndKeepTheirOrderAndSoDoTheRest() {
        let items = [
            reference("a", favorite: false), reference("b", favorite: true), reference("c", favorite: false),
            reference("d", favorite: true), reference("e", favorite: false), reference("f", favorite: true),
        ]
        #expect(NookDesignReferenceRules.compactOrder(items).map(\.name) == ["b", "d", "f", "a", "c", "e"])
    }

    @Test func noFavoriteOnlyFavoritesOrNothingAtAllLeavesTheOrderAlone() {
        let plain = ["a", "b", "c"].map { reference($0, favorite: false) }
        let stars = ["a", "b", "c"].map { reference($0, favorite: true) }
        #expect(NookDesignReferenceRules.compactOrder(plain) == plain)
        #expect(NookDesignReferenceRules.compactOrder(stars) == stars)
        #expect(NookDesignReferenceRules.compactOrder([]).isEmpty)
        #expect(NookDesignReferenceRules.compactOrder([plain[0]]) == [plain[0]])
    }

    @Test func theShelfKeepsItsOwnOrderWhichTheMoveCommandsActOn() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let a = try await fixture.addPicture(named: "a.png")
        let b = try await fixture.addPicture(named: "b.png")
        let c = try await fixture.addPicture(named: "c.png")
        // Newest first: c, b, a.
        #expect(fixture.kit.references.items.map(\.id) == [c.id, b.id, a.id])

        fixture.kit.references.toggleFavorite(a.id)

        #expect(fixture.kit.references.items.map(\.id) == [c.id, b.id, a.id])
        #expect(NookDesignReferenceRules.compactOrder(fixture.kit.references.items).map(\.id) == [a.id, c.id, b.id])

        // Un-starring puts it back where the shelf had it.
        fixture.kit.references.toggleFavorite(a.id)
        #expect(NookDesignReferenceRules.compactOrder(fixture.kit.references.items).map(\.id) == [c.id, b.id, a.id])
    }

    @Test func aFavoriteMarkSurvivesALaunch() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.addPicture()
        fixture.kit.references.toggleFavorite(item.id)
        await fixture.kit.flush()

        let next = NookDesignKit(folder: fixture.folder, defaults: MemoryDefaults())
        await next.load()

        #expect(next.references.items.first?.isFavorite == true)
    }
}

