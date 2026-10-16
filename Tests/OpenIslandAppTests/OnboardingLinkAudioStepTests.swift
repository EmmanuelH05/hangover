import AppKit
import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

// The Link to MP3 step of the widget walk (D59): what it can do, one button
// that switches the widget on, a note that names a missing program, and no
// download from the tour. It replaces the test that said the walk never lists
// the widget. Nothing here runs a program, reads a clipboard or writes a file.

struct OnboardingLinkAudioStepTests {
    private static func reading(isOn: Bool = false, missing: String? = nil) -> OnboardingFeatureReading {
        OnboardingFeatureReading(linkAudio: OnboardingLinkAudioReading(isOn: isOn, missingNoteKey: missing))
    }

    // MARK: The walk

    @Test func theWalkEndsOnLinkToMP3AfterTheKitWhetherItIsOnThePageOrNot() {
        for kinds in [[NookWidgetKind.media, .timer], [], [.media, .linkAudio]] {
            var state = OnboardingState(enabledWidgets: Set(kinds))
            state.nookPlacements = kinds.map { NookWidgetPlacement(kind: $0, size: .medium) }
            let expected = kinds.filter { $0 != .linkAudio } + [.record, .design, .linkAudio]
            #expect(state.featureWalk.kinds == expected, "\(kinds)")
            #expect(state.featureWalk.kinds.filter { $0 == .linkAudio }.count == 1)
        }
        #expect(OnboardingFeatureWalk.everyKind.last == .linkAudio)
        #expect(OnboardingFeatureWalk.everyKind.count == NookWidgetKind.allCases.count)
    }

    @Test func theStepIsOnlyInTheMainAndTheLongTour() {
        #expect(OnboardingPage.features.shortestLength == .medium)
        #expect(!OnboardingPage.shown(length: .short, agentsEnabled: true).contains(.features))
        #expect(OnboardingPage.shown(length: .medium, agentsEnabled: true).contains(.features))
        #expect(OnboardingPage.shown(length: .long, agentsEnabled: true).contains(.features))
    }

    @Test func theStepHasFourToSevenLinesAndOneButtonThatOnlySwitchesItOn() {
        #expect((4...7).contains(OnboardingAbility.lines(for: .linkAudio).count))
        #expect(OnboardingTry.tries(for: .linkAudio) == [.linkAudioOn])
        #expect(OnboardingTry.linkAudioOn.widget == .linkAudio)
        #expect(!OnboardingTry.linkAudioOn.asksMacOS)
    }

    // MARK: The button

    @Test func turnItOnIsEnabledOnlyWhileTheWidgetIsOff() {
        let progress = OnboardingFeatureProgress()
        #expect(OnboardingTry.linkAudioOn.button(Self.reading(), progress: progress).isEnabled)
        #expect(!OnboardingTry.linkAudioOn.button(Self.reading(isOn: true), progress: progress).isEnabled)
    }

    @Test func theNoteNamesWhatIsMissingInTheWidgetsOwnWords() {
        let progress = OnboardingFeatureProgress()
        #expect(OnboardingTry.linkAudioOn.button(Self.reading(), progress: progress).noteKey == nil)
        for key in ["nook.linkAudio.missing.ytDlp", "nook.linkAudio.missing.ffmpeg", "nook.linkAudio.missing.both"] {
            let button = OnboardingTry.linkAudioOn.button(Self.reading(missing: key), progress: progress)
            #expect(button.noteKey == key)
            #expect(button.isEnabled, "a missing program does not stop the switch")
        }
    }

    @Test func theNoteComesFromTheServicesOwnToolStatus() {
        let url = URL(fileURLWithPath: "/opt/homebrew/bin/x")
        #expect(NookLinkAudioToolStatus(ytDlp: url, ffmpeg: url).missingLineKey == nil)
        #expect(NookLinkAudioToolStatus(ytDlp: nil, ffmpeg: url).missingLineKey == "nook.linkAudio.missing.ytDlp")
        #expect(NookLinkAudioToolStatus(ytDlp: url, ffmpeg: nil).missingLineKey == "nook.linkAudio.missing.ffmpeg")
        #expect(NookLinkAudioToolStatus(ytDlp: nil, ffmpeg: nil).missingLineKey == "nook.linkAudio.missing.both")
    }

    @Test(arguments: HangoverBrandTests.languages)
    func theMissingLinesNameTheProgramAndHowToGetIt(language: String) throws {
        let table = try HangoverBrandTests.table(language)
        for key in ["nook.linkAudio.missing.ytDlp", "nook.linkAudio.missing.ffmpeg", "nook.linkAudio.missing.both"] {
            let line = try #require(table[key], "\(language) is missing \(key)")
            #expect(line.contains("brew install yt-dlp ffmpeg"), "\(language) \(key)")
        }
        #expect(try #require(table["nook.linkAudio.missing.ytDlp"]).contains("yt-dlp"))
        #expect(try #require(table["nook.linkAudio.missing.ffmpeg"]).contains("ffmpeg"))
    }

    // MARK: The tick and the door

    @Test func turnItOnTicksFromTheSwitchBeingOnAndNotFromAPress() {
        var progress = OnboardingFeatureProgress()
        progress.note(Self.reading())
        #expect(!progress.done.contains(.linkAudioOn))
        progress.note(Self.reading(isOn: true))
        #expect(progress.done.contains(.linkAudioOn))
    }

    @MainActor
    @Test func theButtonCallsTheWidgetSwitchAndNothingElse() {
        var calls: [String] = []
        var actions = OnboardingActions()
        actions.setWidget = { kind, isOn in calls.append("setWidget \(kind.rawValue) \(isOn)") }
        actions.pickDesignColor = { calls.append("pickDesignColor") }
        actions.showNotes = { calls.append("showNotes") }
        actions.copySampleLine = { _ in calls.append("copySampleLine"); return true }
        actions.showAllAgents = { calls.append("showAllAgents") }

        OnboardingTry.linkAudioOn.press(reading: OnboardingFeatureReading(), sample: "", actions: actions)

        #expect(calls == ["setWidget linkAudio true"], "no download, no paste, no folder")
    }

    // MARK: Left on, left off

    @MainActor
    @Test func aWidgetTurnedOnInTheTourIsNeverSwitchedOffByIt() {
        var calls: [String] = []
        var actions = OnboardingActions()
        actions.setWidget = { kind, isOn in calls.append("\(kind.rawValue) \(isOn)") }
        let tour = OnboardingTour(startingAt: .features, state: { OnboardingState() }, actions: actions)

        OnboardingTry.linkAudioOn.press(reading: OnboardingFeatureReading(), sample: "", actions: tour.actions)
        tour.next()
        tour.skip()

        #expect(calls == ["linkAudio true"])
    }

    @MainActor
    @Test func aWidgetThatWasOffAndNeverTouchedStaysOffThroughTheWholeWalk() {
        var calls: [String] = []
        var actions = OnboardingActions()
        actions.setWidget = { kind, isOn in calls.append("\(kind.rawValue) \(isOn)") }
        let tour = OnboardingTour(startingAt: .features, state: { OnboardingState() }, actions: actions)
        tour.syncIsland()

        for _ in 0..<12 { tour.actions.nextFeature() }
        #expect(tour.state.featureKind == .linkAudio)
        tour.next()
        tour.skip()

        #expect(calls.isEmpty)
    }

    // MARK: Read from the app

    @MainActor
    @Test func theTourReadsTheSwitchAndTheToolStatusFromTheService() {
        let fixture = LinkAudioFixture()
        let nook = NookModel(linkAudio: fixture.service, defaults: MemoryDefaults(), looksForImportedGIF: false)
        let model = AppModel(agentsDefaults: MemoryDefaults(), defaults: MemoryDefaults(), nookModel: nook)

        var reading = model.onboardingState.features.linkAudio
        #expect(!reading.isOn)
        #expect(reading.missingNoteKey == nil, "both programs were found")

        fixture.executables = [LinkAudioFixture.ffmpeg]
        fixture.service.refreshTools()
        reading = model.onboardingState.features.linkAudio
        #expect(reading.missingNoteKey == "nook.linkAudio.missing.ytDlp")

        model.setTourWidget(.linkAudio, enabled: true)
        #expect(model.onboardingState.features.linkAudio.isOn)
        #expect(fixture.runner.runs.isEmpty, "the tour starts no download")
    }

    @MainActor
    @Test func theTourWidgetDoorLooksForTheProgramsAgainAsTheWidgetComesOn() {
        let fixture = LinkAudioFixture()
        fixture.executables = []
        let nook = NookModel(linkAudio: fixture.service, defaults: MemoryDefaults(), looksForImportedGIF: false)
        let model = AppModel(agentsDefaults: MemoryDefaults(), defaults: MemoryDefaults(), nookModel: nook)
        fixture.service.refreshTools()
        #expect(model.onboardingState.features.linkAudio.missingNoteKey == "nook.linkAudio.missing.both")

        // The user installs them while the tour is up, then presses the button.
        fixture.executables = [LinkAudioFixture.ytDlp, LinkAudioFixture.ffmpeg]
        model.makeWelcomeTour(startingAt: .features).actions.setWidget(.linkAudio, true)

        #expect(model.onboardingState.features.linkAudio.missingNoteKey == nil)
        #expect(model.onboardingState.features.linkAudio.isOn)
    }

    // MARK: The strings

    @Test(arguments: HangoverBrandTests.languages)
    func theStepHasItsWordsInEveryLanguage(language: String) throws {
        let table = try HangoverBrandTests.table(language)
        var keys = ["onboarding.nook.widget.linkAudio", "onboarding.widgets.linkAudio"]
        keys += OnboardingAbility.lines(for: .linkAudio).map(\.textKey)
        keys += OnboardingTry.tries(for: .linkAudio).map(\.titleKey)
        for key in keys {
            #expect(!(table[key] ?? "").isEmpty, "\(language) is missing \(key)")
        }
    }

    @Test func theEnglishWordsSayWhatItNeedsAndAreWrittenPlainly() throws {
        let english = try HangoverBrandTests.table("en")
        let tools = try #require(english[OnboardingAbility.linkAudioTools.textKey])
        #expect(tools.contains("yt-dlp") && tools.contains("ffmpeg") && tools.contains("already on your Mac"))
        for key in OnboardingAbility.lines(for: .linkAudio).map(\.textKey) + ["onboarding.widgets.linkAudio"] {
            let value = try #require(english[key])
            #expect(value.range(of: "\\bso\\b", options: [.regularExpression, .caseInsensitive]) == nil, "\(key)")
            #expect(!value.contains("\u{2014}") && !value.contains("\u{2013}"), "\(key) has a dash")
        }
    }
}

// MARK: - Drawn

/// The step at the narrow window's width, with the programs found, with one
/// missing and with the widget on. Written to `output/render/onboarding/` when
/// `OPEN_ISLAND_RENDER_SNAPSHOTS=1`.
@MainActor
struct OnboardingLinkAudioRenderTests {
    private static let scale: CGFloat = 2

    private static func state(isOn: Bool, missing: String?) -> OnboardingState {
        var state = OnboardingState()
        state.length = .medium
        state.featureKind = .linkAudio
        state.features.linkAudio = OnboardingLinkAudioReading(isOn: isOn, missingNoteKey: missing)
        if isOn {
            var progress = OnboardingFeatureProgress()
            progress.note(state.features)
            state.featureProgress = progress
        }
        return state
    }

    @Test func theStepDrawsFoundMissingAndOn() throws {
        let found = try render("08-features-linkaudio-found-320", Self.state(isOn: false, missing: nil))
        let missing = try render("08-features-linkaudio-missing-320", Self.state(isOn: false, missing: "nook.linkAudio.missing.both"))
        let on = try render("08-features-linkaudio-on-320", Self.state(isOn: true, missing: nil))
        #expect(Set([found, missing, on]).count == 3, "the three states of the step should each draw")
    }

    private func render(_ name: String, _ state: OnboardingState) throws -> Data {
        let size = CGSize(width: 320, height: OnboardingWindowFrame.narrowMaxHeight)
        let view = OnboardingView(tour: OnboardingTour(startingAt: .features, state: { state }), lang: LanguageManager.shared)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view.environment(\.nookDrawsStill, true))
        renderer.scale = Self.scale
        let image = try #require(renderer.cgImage, "ImageRenderer returned no image")
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]), "PNG encoding failed")
        if ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_SNAPSHOTS"] == "1" {
            let directory = HangoverBrandTests.repoRoot.appendingPathComponent("output/render/onboarding", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return png
    }
}
