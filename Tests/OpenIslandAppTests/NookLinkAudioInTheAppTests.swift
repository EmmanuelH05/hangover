import Foundation
import OpenIslandCore
import Testing
@testable import OpenIslandApp

// Link to MP3 in today's app: off until switched on in Settings, left out
// of the welcome tour, no macOS permission, a draft that holds the island
// open, and nothing real reached from a model on a store of its own.

@MainActor
@Suite struct NookLinkAudioInTheAppTests {
    private typealias Fixture = LinkAudioFixture

    private func nook(_ fixture: Fixture? = nil) -> NookModel {
        let nook = NookModel(linkAudio: fixture?.service, defaults: MemoryDefaults(), looksForImportedGIF: false)
        nook.activeProfile = { .notch }
        return nook
    }

    // MARK: Off, and out of the tour

    @Test func theWidgetIsOffUntilSwitchedOnAndNoTemplatePlacesIt() {
        #expect(NookWidgetKind.allCases.contains(.linkAudio))
        #expect(!NookWidgetKind.defaultEnabled.contains(.linkAudio))
        #expect(NookWidgetKind.linkAudio.systemImage == "arrow.down.circle")
        for template in PersonalizationTemplate.all {
            #expect(!template.widgetKinds.contains(.linkAudio), "\(template.id)")
        }
        let nook = nook()
        #expect(!nook.isWidgetEnabled(.linkAudio))
        #expect(!nook.widgetPlacements(for: .notch).map(\.kind).contains(.linkAudio))
        #expect(!NookDisplayPreferences().placements(enabled: NookWidgetKind.defaultEnabled).map(\.kind).contains(.linkAudio))
    }

    @Test func theWidgetHasANameInEveryLanguage() {
        #expect(NookWidgetKind.linkAudio.title == LanguageManager.shared.t("nook.linkAudio.title"))
        #expect(NookWidgetKind.linkAudio.title != "nook.linkAudio.title")
    }

    /// The tour offers it on its widgets page, switched off to begin with.
    @Test func theWelcomeTourOffersItSwitchedOff() {
        #expect(NookWidgetKind.allCases.contains(.linkAudio))
        #expect(NookWidgetKind.startsOff.contains(.linkAudio))
        #expect(NookWidgetKind.tools.contains(.linkAudio))
        #expect(!NookWidgetKind.defaultEnabled.contains(.linkAudio))
        #expect(NookWidgetKind.allCases.count == 10)
    }

    /// It is drawn once it is on the page, and its step ends the widget walk
    /// whether it is on or not.
    @Test func theTourDrawsItOnceItIsOnThePageAndWalksItLast() {
        var state = OnboardingState()
        state.enabledWidgets = Set(NookWidgetKind.allCases)
        state.nookPlacements = NookWidgetKind.allCases.map { NookWidgetPlacement(kind: $0, size: .medium) }

        #expect(state.shownPlacements.contains { $0.kind == .linkAudio })
        #expect(state.showsWidget(.linkAudio))
        #expect(state.featureWalk.kinds == NookWidgetKind.allCases)
        #expect(state.featureWalk.kinds.last == .linkAudio)
        #expect(state.featureWalk.kinds.filter { $0 == .linkAudio }.count == 1)

        state.nookPlacements = NookWidgetKind.allCases.filter { $0 != .linkAudio }.map { NookWidgetPlacement(kind: $0, size: .medium) }
        #expect(!state.showsWidget(.linkAudio))
        #expect(state.featureWalk.kinds.last == .linkAudio, "the step is there while the widget is off")
    }

    // MARK: The switch in Settings

    @Test func switchingItOnInSettingsGivesItACardEvenAfterALayoutHidIt() {
        let nook = nook()
        for template in PersonalizationTemplate.all.prefix(3) {
            nook.updateDisplayPreferences(for: .notch) { $0 = template.applying(to: $0) }
            #expect(nook.displayPreferences(for: .notch).hiddenWidgets.contains(.linkAudio))
        }

        nook.setWidgetFromSettings(.linkAudio, enabled: true)

        #expect(nook.isWidgetEnabled(.linkAudio))
        #expect(nook.widgetPlacements(for: .notch).map(\.kind).contains(.linkAudio))
    }

    @Test func theOtherDisplaysHiddenListIsLeftAloneAndOtherWidgetsAreUnchanged() {
        let nook = nook()
        nook.updateDisplayPreferences(for: .topBar) { $0.hiddenWidgets.insert(.linkAudio) }
        nook.updateDisplayPreferences(for: .notch) { $0.hiddenWidgets.formUnion([.linkAudio, .weather]) }
        nook.setWidgetFromSettings(.linkAudio, enabled: true)
        #expect(!nook.displayPreferences(for: .notch).hiddenWidgets.contains(.linkAudio))
        #expect(nook.displayPreferences(for: .notch).hiddenWidgets.contains(.weather))
        #expect(nook.displayPreferences(for: .topBar).hiddenWidgets.contains(.linkAudio))
    }

    @Test func noMacOSPermissionIsEverAskedForIt() {
        for moment in [NookAccessMoment.launch, .shown, .turnedOn, .requested] {
            for source in NookTodoSourceKind.allCases {
                #expect(NookAccessTiming.permissions(for: .linkAudio, at: moment, isEnabled: true, todoSource: source).isEmpty)
            }
        }
    }

    @Test func theCardHasAHeightAtEverySizeAndTheSettingsPreviewDrawsIt() {
        for size in NookWidgetSize.allCases {
            let height = NookPanelView.cardHeight(NookWidgetPlacement(kind: .linkAudio, size: size), calendarStyle: .strip)
            #expect(height == NookLinkAudioCard.height(for: size))
            #expect(height > 0)
        }
        #expect(NookLinkAudioCard.height(for: .small) == NookWidgetLayout.smallHeight)
        let stage = PreviewStageMetrics.areaHeight(
            setup: PersonalizationSetup(appearance: IslandAppearancePreferences(), nook: NookDisplayPreferences()),
            enabledWidgets: NookWidgetKind.allCases
        )
        #expect(stage > 0)
    }

    @Test func theRowsThatFitFollowTheHeightAndAreNeverFewerThanOne() {
        #expect(NookLinkAudioCardLayout.rowCapacity(height: 0) == 1)
        #expect(NookLinkAudioCardLayout.rowCapacity(height: -5) == 1)
        #expect(NookLinkAudioCardLayout.rowCapacity(height: 29) == 1)
        #expect(NookLinkAudioCardLayout.rowCapacity(height: 30) == 1)
        #expect(NookLinkAudioCardLayout.rowCapacity(height: 64) == 2)
        #expect(NookLinkAudioCardLayout.rowCapacity(height: 166) == 5)
        #expect(NookLinkAudioCardLayout.rowCapacity(height: 400) == 11)
    }

    // MARK: The typed line

    @Test func aLinkTypedAndNotSavedHoldsTheIslandOpenAndAnEmptyFieldDoesNot() {
        let nook = nook()
        #expect(!nook.holdsUnsavedDraft)
        nook.setDraft(.linkAudio, isUnsaved: NookDraft.isUnsaved("https://exam"))
        #expect(nook.holdsUnsavedDraft)
        nook.setDraft(.linkAudio, isUnsaved: NookDraft.isUnsaved("   "))
        #expect(!nook.holdsUnsavedDraft)
        nook.setDraft(.linkAudio, isUnsaved: true)
        nook.forgetDrafts()
        #expect(!nook.holdsUnsavedDraft, "forgotten like the others")
    }

    @Test func theLineUnderTheFieldIsForgottenWithTheDrafts() {
        let fixture = Fixture()
        let nook = nook(fixture)
        fixture.service.submit("nonsense")
        #expect(fixture.service.problem != nil)
        nook.forgetDrafts()
        #expect(fixture.service.problem == nil)
    }

    // MARK: Switching it off

    @Test func switchingTheWidgetOffStopsWhatIsRunning() throws {
        let fixture = Fixture()
        let nook = nook(fixture)
        nook.setWidget(.linkAudio, enabled: true)
        fixture.submit(2)
        let run = try #require(fixture.runner.last)

        nook.setWidget(.weather, enabled: true)
        #expect(run.cancelCount == 0, "another widget's switch leaves it alone")

        nook.setWidget(.linkAudio, enabled: false)
        #expect(run.cancelCount == 1)
        #expect(fixture.service.queue.waiting.isEmpty)
    }

    // MARK: Nothing real is reached

    @Test func aModelOnAStoreOfItsOwnCannotStartAProgramOrReachTheUsersMusic() {
        let nook = NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
        let service = nook.linkAudio
        #expect(service.runner is NookLinkAudioRefusingRunner)
        #expect(service.toolStatus.tools == nil, "it finds no program, whatever this Mac has")
        #expect(service.submit(Fixture.link(1)) == .toolsMissing)
        #expect(!service.folder.path.contains("/Music/"))
        #expect(service.folder.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    }

    @Test func theDemoModeGivesItAServiceThatStartsNothingAndKeepsItsFolderInTheSession() {
        let demo = DemoFixture()
        defer { demo.remove() }
        let service = demo.nook.linkAudio
        #expect(!demo.nook.isWidgetEnabled(.linkAudio))
        #expect(service.runner is NookLinkAudioRefusingRunner)
        #expect(service.submit(Fixture.link(1)) == .toolsMissing)
        #expect(service.folder.path.hasPrefix(demo.root.path))
        #expect(!FileManager.default.fileExists(atPath: service.folder.path))
    }
}

// MARK: - Strings

@Suite struct NookLinkAudioStringsTests {
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private static let languages = ["en", "zh-Hans", "zh-Hant"]

    private static func table(_ language: String) throws -> [String: String] {
        let url = repoRoot.appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
        return try #require(NSDictionary(contentsOf: url) as? [String: String], "\(language) did not load")
    }

    private static var widgetFolder: URL {
        repoRoot.appendingPathComponent("Sources/OpenIslandApp/Nook/Widgets/LinkAudio")
    }

    private static func widgetSources() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: widgetFolder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
    }

    /// Every "nook.linkAudio." key written out in the widget's files.
    @MainActor
    private static func usedKeys() throws -> Set<String> {
        let pattern = try NSRegularExpression(pattern: "\"(nook\\.linkAudio\\.[A-Za-z0-9.]+)\"")
        var keys = Set<String>()
        for file in try widgetSources() {
            let source = try String(contentsOf: file, encoding: .utf8)
            for match in pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                guard let range = Range(match.range(at: 1), in: source) else { continue }
                keys.insert(String(source[range]))
            }
        }
        // A settings key is not a string to show.
        keys.remove(NookLinkAudioFolderRule.defaultsKey)
        return keys
    }

    @Test @MainActor func everyStringExistsInEveryLanguageAndHasNoDash() throws {
        let keys = try Self.usedKeys()
        #expect(keys.count > 40)
        for language in Self.languages {
            let table = try Self.table(language)
            for key in keys.sorted() {
                let value = table[key] ?? ""
                #expect(!value.isEmpty, "\(language) is missing \(key)")
                #expect(!value.contains("\u{2014}") && !value.contains("\u{2013}"), "\(language) \(key) has a dash")
            }
        }
    }

    @Test @MainActor func theTablesHoldNoKeyOfTheWidgetThatIsNotUsed() throws {
        let used = try Self.usedKeys()
        for language in Self.languages {
            let unused = try Self.table(language).keys.filter { $0.hasPrefix("nook.linkAudio.") && !used.contains($0) }
            #expect(unused.isEmpty, "\(language) has unused keys: \(unused.sorted())")
        }
    }

    @Test @MainActor func theSameArgumentsAreAskedForInEveryLanguage() throws {
        let keys = try Self.usedKeys()
        let english = try Self.table("en")
        let pattern = try NSRegularExpression(pattern: "%(lld|@)")
        func arguments(_ text: String) -> [String] {
            pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
                Range($0.range, in: text).map { String(text[$0]) }
            }
        }
        for language in Self.languages.dropFirst() {
            let table = try Self.table(language)
            for key in keys.sorted() {
                #expect(arguments(table[key] ?? "") == arguments(english[key] ?? ""), "\(language) \(key)")
            }
        }
    }

    @Test @MainActor func theEnglishStringsFollowTheHouseWording() throws {
        let english = try Self.table("en")
        let word = try NSRegularExpression(pattern: "\\bso\\b", options: [.caseInsensitive])
        for key in try Self.usedKeys().sorted() {
            let value = english[key] ?? ""
            #expect(word.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) == nil, "\(key)")
        }
    }

    @Test func theSettingsCaptionIsTheOneThatWasAskedFor() throws {
        let english = try Self.table("en")
        #expect(
            english["nook.linkAudio.settings.caption"]
                == "Hangover hands the link to yt-dlp on your Mac, which fetches it from the site. Only save what you have the right to."
        )
    }

    @Test func theMissingLinesNameTheCommandInEveryLanguage() throws {
        for language in Self.languages {
            let table = try Self.table(language)
            for key in ["ytDlp", "ffmpeg", "both"] {
                let line = table["nook.linkAudio.missing.\(key)"] ?? ""
                #expect(line.contains("brew install yt-dlp ffmpeg"), "\(language) \(key)")
            }
        }
    }

    @Test func theWidgetsFilesAndTestsHaveNoDashAndNoSoInTheirWords() throws {
        let word = try NSRegularExpression(pattern: "\\bso\\b", options: [.caseInsensitive])
        let tests = Self.repoRoot.appendingPathComponent("Tests/OpenIslandAppTests")
        let testFiles = try FileManager.default.contentsOfDirectory(at: tests, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("NookLinkAudio") && $0.pathExtension == "swift" }
        for file in try Self.widgetSources() + testFiles {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"), "\(file.lastPathComponent) has a dash")
            let hit = word.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
            #expect(hit == nil, "\(file.lastPathComponent) uses a word the house rules leave out")
        }
    }
}
