import Foundation
import Testing
@testable import OpenIslandApp

private typealias Samples = NookDesignSamples

/// Counts how often the app model would close the island.
@MainActor
private final class IslandCloseCounter {
    private(set) var count = 0
    func close() { count += 1 }
}

/// A color that differs for each number, for the runs that need many.
private func color(number: Int) -> NookDesignColor {
    NookDesignColor(red: UInt8(number % 256), green: UInt8(number / 256), blue: 7)
}

/// Waits until the sampler has been asked `count` times. The kit asks for
/// the next pick on the next turn of the main actor, and this lets those
/// turns go by.
@MainActor
private func waitUntilAsked(_ count: Int, _ sampler: FakeColorSampler) async -> Bool {
    for _ in 0..<500 where sampler.sampleCount < count {
        await Task.yield()
    }
    return await Samples.wait { sampler.sampleCount >= count }
}

/// Lets the main actor run for a while, to show that nothing more happens.
@MainActor
private func letTheMainActorRun() async {
    try? await Task.sleep(for: .milliseconds(60))
}

// MARK: - Keep picking until Escape

@MainActor
@Suite struct NookDesignKeepPickingTests {
    @Test(arguments: [NookDesignPickSource.island, .shortcut])
    func withTheSwitchOffOnePickEndsItAndTheSamplerIsNotAskedAgain(source: NookDesignPickSource) async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit

        #expect(kit.pickColor(from: source))
        fixture.sampler.finish(Samples.orange)
        await letTheMainActorRun()

        #expect(fixture.sampler.sampleCount == 1)
        #expect(!kit.isSampling)
        #expect(kit.palettes.recents.map(\.color) == [Samples.orange])
        #expect(fixture.copies.texts == ["#FF8800"])
    }

    @Test(arguments: [NookDesignPickSource.island, .shortcut])
    func withTheSwitchOnThreePicksAreKeptAndCopiedInOrderAndACancelEndsTheRun(source: NookDesignPickSource) async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit
        let closer = IslandCloseCounter()
        kit.willSampleFromIsland = { closer.close() }
        kit.keepsPicking = true

        #expect(kit.pickColor(from: source))
        for (index, picked) in [Samples.orange, Samples.teal, Samples.ink].enumerated() {
            #expect(await waitUntilAsked(index + 1, fixture.sampler))
            fixture.sampler.finish(picked)
        }
        #expect(await waitUntilAsked(4, fixture.sampler))
        #expect(fixture.sampler.sampleCount == 4)
        #expect(kit.isSampling)

        fixture.sampler.finish(nil)
        #expect(!kit.isSampling)
        await letTheMainActorRun()

        #expect(fixture.sampler.sampleCount == 4, "a cancel must end the run")
        #expect(kit.palettes.recents.map(\.color) == [Samples.ink, Samples.teal, Samples.orange])
        #expect(fixture.copies.texts == ["#FF8800", "#2EC4B6", "#111111"])
        #expect(kit.lastPick == Samples.ink)
        // The island is closed once, at the start, and only from the card.
        #expect(closer.count == (source == .island ? 1 : 0))
    }

    @Test func everyColorOfARunGoesToThePaletteWhenThatSwitchIsOn() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit
        kit.keepsPicking = true
        kit.savesPicksToPalette = true

        kit.pickColor(from: .shortcut)
        for (index, picked) in [Samples.orange, Samples.teal].enumerated() {
            #expect(await waitUntilAsked(index + 1, fixture.sampler))
            fixture.sampler.finish(picked)
        }
        #expect(await waitUntilAsked(3, fixture.sampler))
        fixture.sampler.finish(nil)

        #expect(kit.palettes.activePalette?.swatches.map(\.color) == [Samples.orange, Samples.teal])
        #expect(kit.palettes.recents.map(\.color) == [Samples.teal, Samples.orange])
    }

    @Test func isSamplingIsTrueAtEveryPointBetweenTheFirstRequestAndTheCancel() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit
        kit.keepsPicking = true
        #expect(!kit.isSampling)

        kit.pickColor(from: .shortcut)
        #expect(kit.isSampling)
        for count in 1...3 {
            #expect(await waitUntilAsked(count, fixture.sampler))
            #expect(kit.isSampling, "the loupe is up")
            fixture.sampler.finish(color(number: count))
            // Right after the pick ends there is no loupe and no gap.
            #expect(kit.isSampling, "a gap after pick \(count)")
            // A second request while the run waits for its next turn does nothing.
            #expect(!kit.pickColor(from: .shortcut))
            #expect(!kit.pickColor(from: .island))
            #expect(fixture.sampler.sampleCount == count)
        }
        #expect(await waitUntilAsked(4, fixture.sampler))
        #expect(kit.isSampling)
        // A second request with the loupe up does nothing either.
        #expect(!kit.pickColor(from: .shortcut))
        #expect(fixture.sampler.sampleCount == 4)

        fixture.sampler.finish(nil)
        #expect(!kit.isSampling)
        // Escape ended it: the next request is a new run.
        #expect(kit.pickColor(from: .shortcut))
        #expect(fixture.sampler.sampleCount == 5)
    }

    @Test func aColorTheKitCannotReadIsSaidAndTheRunGoesOn() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit
        kit.keepsPicking = true

        kit.pickColor(from: .shortcut)
        #expect(await waitUntilAsked(1, fixture.sampler))
        fixture.sampler.finish(Samples.orange)
        #expect(await waitUntilAsked(2, fixture.sampler))

        fixture.sampler.finishUnreadable()
        #expect(kit.isSampling, "the run ended on a color it could not read")
        #expect(kit.notice?.kind == .error)
        #expect(kit.notice?.text == LanguageManager.shared.t("nook.design.notice.pickUnreadable"))
        #expect(await waitUntilAsked(3, fixture.sampler))
        #expect(kit.isSampling)

        fixture.sampler.finish(Samples.teal)
        #expect(await waitUntilAsked(4, fixture.sampler))
        fixture.sampler.finish(nil)
        #expect(!kit.isSampling)
        // The unreadable color left nothing behind.
        #expect(kit.palettes.recents.map(\.color) == [Samples.teal, Samples.orange])
        #expect(fixture.copies.texts == ["#FF8800", "#2EC4B6"])
    }

    @Test func switchingTheWidgetOffBetweenTwoPicksEndsTheRun() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit
        kit.keepsPicking = true

        kit.pickColor(from: .shortcut)
        #expect(await waitUntilAsked(1, fixture.sampler))
        fixture.sampler.finish(Samples.orange)
        #expect(kit.isSampling)

        kit.setLive(false)

        #expect(!kit.isSampling, "no loupe is up, and nothing is left to wait for")
        await letTheMainActorRun()
        #expect(fixture.sampler.sampleCount == 1)

        // Switching it on again does not bring the run back.
        kit.setLive(true)
        await letTheMainActorRun()
        #expect(fixture.sampler.sampleCount == 1)
        #expect(!kit.isSampling)
    }

    @Test func switchingTheWidgetOffWhileTheLoupeIsUpEndsTheRunWhenTheLoupeAnswers() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit
        kit.keepsPicking = true

        kit.pickColor(from: .shortcut)
        #expect(await waitUntilAsked(1, fixture.sampler))
        fixture.sampler.finish(Samples.orange)
        #expect(await waitUntilAsked(2, fixture.sampler))

        kit.setLive(false)
        kit.setLive(true)
        fixture.sampler.finish(Samples.teal)
        await letTheMainActorRun()

        #expect(fixture.sampler.sampleCount == 2, "a run that was ended must not start again")
        #expect(!kit.isSampling)
    }

    @Test func aKitThatIsGoneAsksTheSamplerForNothingMore() async throws {
        let folder = try Samples.temporaryFolder("gone")
        defer { try? FileManager.default.removeItem(at: folder) }
        let sampler = FakeColorSampler()
        var kit: NookDesignKit? = NookDesignKit(folder: folder, defaults: MemoryDefaults(), copyText: { _ in true })
        weak var watched = kit
        kit?.activate(NookDesignServices(
            sampler: sampler,
            presenter: FakeReferencePresenter(),
            editor: FakeEditorPresenter(),
            pictureClipboard: FakePictureClipboard(),
            hotkeyRegistrar: FakeDesignHotkeyRegistrar(),
            linkOpener: FakeLinkOpener()
        ))
        kit?.setLive(true)
        await kit?.load()
        kit?.keepsPicking = true
        kit?.pickColor(from: .shortcut)
        sampler.finish(Samples.orange)

        kit = nil
        await letTheMainActorRun()

        #expect(watched == nil, "something still holds the kit")
        #expect(sampler.sampleCount == 1)
    }

    @Test func aRunEndsAfterTwoHundredPicksWhateverTheUserDoes() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit
        kit.keepsPicking = true
        #expect(NookDesignKit.maxPicksPerRun == 200)

        kit.pickColor(from: .shortcut)
        for number in 1...NookDesignKit.maxPicksPerRun {
            guard await waitUntilAsked(number, fixture.sampler) else {
                Issue.record("pick \(number) was never asked for")
                return
            }
            #expect(kit.isSampling, "the run ended early, at pick \(number)")
            fixture.sampler.finish(color(number: number))
        }

        #expect(!kit.isSampling, "the run did not end at the limit")
        await letTheMainActorRun()
        #expect(fixture.sampler.sampleCount == 200)
        #expect(fixture.copies.texts.count == 200)
        // The limit belongs to the run: a new request is a new run.
        #expect(kit.pickColor(from: .shortcut))
        #expect(fixture.sampler.sampleCount == 201)
        #expect(kit.isSampling)
    }
}

// MARK: - The setting

@MainActor
@Suite struct NookDesignKeepPickingSettingTests {
    @Test func theSettingIsOffToBeginWithAndKeepsItsValue() async throws {
        let defaults = MemoryDefaults()
        let first = try await NookDesignFixture(defaults: defaults)
        defer { first.cleanUp() }
        #expect(!first.kit.keepsPicking)
        #expect(defaults.all[NookDesignKit.keepsPickingKey] == nil, "reading the setting wrote it")

        first.kit.keepsPicking = true

        let second = try await NookDesignFixture(defaults: defaults)
        defer { second.cleanUp() }
        #expect(second.kit.keepsPicking)

        second.kit.keepsPicking = false
        let third = try await NookDesignFixture(defaults: defaults)
        defer { third.cleanUp() }
        #expect(!third.kit.keepsPicking)
    }

    @Test func settingsSavedBeforeThisOneExistedReadAsOff() async throws {
        let defaults = MemoryDefaults()
        defaults.set(NookDesignTab.references.rawValue, forKey: NookDesignKit.tabKey)
        defaults.set(NookDesignColorFormat.hsl.rawValue, forKey: NookDesignKit.formatKey)
        defaults.set(true, forKey: NookDesignKit.savesPicksKey)

        let fixture = try await NookDesignFixture(defaults: defaults)
        defer { fixture.cleanUp() }

        #expect(!fixture.kit.keepsPicking)
        #expect(fixture.kit.savesPicksToPalette)
        #expect(fixture.kit.copyFormat == .hsl)
    }
}

// MARK: - The pill on the card

@MainActor
@Suite struct NookDesignKeepPillTests {
    @Test func aPressOfThePillFlipsTheSettingTheSettingsSwitchWritesAndTheLabelFollows() async throws {
        let defaults = MemoryDefaults()
        let fixture = try await NookDesignFixture(defaults: defaults)
        defer { fixture.cleanUp() }
        let kit = fixture.kit
        let lang = LanguageManager.shared
        let asking = lang.t("nook.design.keepPill.off")
        let equipped = lang.t("nook.design.keepPill.on")
        #expect(asking != "nook.design.keepPill.off" && equipped != "nook.design.keepPill.on", "a label has no string")
        #expect(asking != equipped)

        #expect(!kit.keepsPicking)
        #expect(kit.keepPickingPillText == asking)

        kit.toggleKeepsPicking()
        #expect(kit.keepsPicking)
        #expect(kit.keepPickingPillText == equipped)
        #expect(defaults.bool(forKey: NookDesignKit.keepsPickingKey), "the press did not reach the saved setting")

        // The switch in Settings sets the same property, and the pill reads it.
        kit.keepsPicking = false
        #expect(kit.keepPickingPillText == asking)
        kit.keepsPicking = true
        #expect(kit.keepPickingPillText == equipped)

        kit.toggleKeepsPicking()
        #expect(!kit.keepsPicking)
        #expect(kit.keepPickingPillText == asking)
        #expect(!defaults.bool(forKey: NookDesignKit.keepsPickingKey))
    }

    @Test func aRunStartedAfterThePillWasPressedKeepsGoing() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit

        kit.toggleKeepsPicking()
        kit.pickColor(from: .island)
        fixture.sampler.finish(Samples.orange)

        #expect(await waitUntilAsked(2, fixture.sampler))
        #expect(kit.isSampling)
    }

    /// Reads a language's strings from the source tree, where the tests
    /// check the other languages too. The answer does not depend on the
    /// language this Mac is set to.
    private static func table(_ language: String) throws -> [String: String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
        return try #require(NSDictionary(contentsOf: url) as? [String: String], "\(language) did not load")
    }

    @Test func theOwnersWordsStandInEnglishAndTheOtherLanguagesTranslateTheMeaning() throws {
        let english = try Self.table("en")
        #expect(english["nook.design.keepPill.off"] == "Equip the switch?")
        #expect(english["nook.design.keepPill.on"] == "Switch equipped")
        #expect(english["nook.design.action.pickKeep"] == "Keep picking colors until Escape")
        #expect(english["nook.design.settings.keepPicking"] == "Keep picking until Escape")

        for language in ["zh-Hans", "zh-Hant"] {
            let table = try Self.table(language)
            for key in ["nook.design.keepPill.off", "nook.design.keepPill.on", "nook.design.action.pickKeep"] {
                let value = try #require(table[key], "\(language) is missing \(key)")
                #expect(!value.isEmpty && value != english[key], "\(language) \(key) is not translated")
            }
            #expect(table["nook.design.keepPill.off"] != table["nook.design.keepPill.on"])
        }
    }
}
