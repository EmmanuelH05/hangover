import Carbon.HIToolbox
import Foundation
import Testing
@testable import OpenIslandApp

// The Record step of the widget walk, the Record and Convert pages of the long
// tour, and the Convert tip (D67, D68). The step's one button switches the
// widget on and shows its card, and that is all: nothing here starts a
// recording, a picker or the face cam. What the button switched on goes off
// again when the step is left, and a Record that was on before is the user's.
// Nothing here opens a window, reads the real settings or touches the screen,
// the camera or the microphone.

// MARK: - The step and its button

struct OnboardingRecordStepTests {
    private static func reading(isOn: Bool = false) -> OnboardingFeatureReading {
        OnboardingFeatureReading(isRecordOn: isOn)
    }

    @Test func theStepHasItsLinesAndOneButtonThatOnlySwitchesItOn() {
        #expect((4...7).contains(OnboardingAbility.lines(for: .record).count))
        #expect(OnboardingTry.tries(for: .record) == [.recordOn])
        #expect(OnboardingTry.recordOn.widget == .record)
        #expect(!OnboardingTry.recordOn.asksMacOS, "the tour never raises the Screen Recording or microphone prompt")
    }

    @Test func turnRecordOnIsEnabledOnlyWhileTheWidgetIsOffAndItsNoteSaysNothingIsRecorded() {
        let progress = OnboardingFeatureProgress()
        let off = OnboardingTry.recordOn.button(Self.reading(), progress: progress)
        let on = OnboardingTry.recordOn.button(Self.reading(isOn: true), progress: progress)

        #expect(off.isEnabled && !on.isEnabled)
        #expect(off.noteKey == "onboarding.features.try.recordOn.note")
        #expect(on.noteKey == "onboarding.features.try.recordOn.note", "the note stays, it is what the user reads before pressing")
    }

    @Test func theTickComesFromTheSwitchBeingOnAndNotFromAPress() {
        var progress = OnboardingFeatureProgress()
        progress.note(Self.reading())
        #expect(!progress.done.contains(.recordOn))
        progress.note(Self.reading(isOn: true))
        #expect(progress.done.contains(.recordOn))
    }

    /// The tour's doors are the app's whole reach from a page. None of them
    /// is a recording, a capture, a picker or a bubble: the widget's switch is
    /// the only door that mentions the widget at all.
    @MainActor
    @Test func theTourHasNoDoorThatStartsARecording() {
        let labels = Mirror(reflecting: OnboardingActions()).children.compactMap(\.label)
        #expect(labels.contains("setWidget"))
        for label in labels {
            let name = label.lowercased()
            for word in ["record", "capture", "bubble", "facecam", "areapicker", "windowpicker"] {
                #expect(!name.contains(word), "the door \(label) could start a recording")
            }
        }
    }

    @MainActor
    @Test func theButtonCallsTheWidgetSwitchAndNothingElse() {
        var calls: [String] = []
        var actions = OnboardingActions()
        actions.setWidget = { kind, isOn in calls.append("setWidget \(kind.rawValue) \(isOn)") }
        actions.setMirror = { _ in calls.append("setMirror") }
        actions.openPhotoBooth = { calls.append("openPhotoBooth") }
        actions.pickDesignColor = { calls.append("pickDesignColor") }
        actions.showNotes = { calls.append("showNotes") }
        actions.showCalendar = { calls.append("showCalendar") }
        actions.copySampleLine = { _ in calls.append("copySampleLine"); return true }
        actions.openSettings = { _ in calls.append("openSettings") }
        actions.showAllAgents = { calls.append("showAllAgents") }

        OnboardingTry.recordOn.press(reading: OnboardingFeatureReading(), sample: "", actions: actions)

        #expect(calls == ["setWidget record true"], "no recording, no picker, no face cam, no prompt")
    }
}

// MARK: - Left on, left off

/// The app as the tour sees it: the page of widgets it reads, and the switch
/// calls it got, in order. The switch does to the page what the real one does.
@MainActor
private final class RecordWorld {
    var state = OnboardingState()
    var calls: [String] = []

    init(recordOn: Bool = false, kinds: [NookWidgetKind] = [.media, .notes]) {
        let shown = kinds + (recordOn ? [.record] : [])
        state.nookPlacements = shown.map { NookWidgetPlacement(kind: $0, size: .medium) }
        // Every switch is on but Record's, which starts off like the app's.
        state.enabledWidgets = Set(NookWidgetKind.allCases).subtracting(recordOn ? [] : [.record])
    }

    var actions: OnboardingActions {
        var actions = OnboardingActions()
        actions.setWidget = { [self] kind, isOn in
            calls.append("\(kind.rawValue) \(isOn)")
            var placements = (state.nookPlacements ?? []).filter { $0.kind != kind }
            if isOn { placements.append(NookWidgetPlacement(kind: kind, size: .medium)) }
            state.nookPlacements = placements
            if isOn { state.enabledWidgets.insert(kind) } else { state.enabledWidgets.remove(kind) }
        }
        return actions
    }

    var isRecordOn: Bool { state.enabledWidgets.contains(.record) }
}

/// Every way out of the Record step or of the features page.
enum OnboardingRecordExit: CaseIterable, Sendable, CustomTestStringConvertible {
    case nextWidget, previousWidget, nextPage, previousPage, skip, windowClosing

    var testDescription: String { "\(self)" }

    @MainActor
    func leave(_ tour: OnboardingTour) {
        switch self {
        case .nextWidget: tour.actions.nextFeature()
        case .previousWidget: tour.actions.previousFeature()
        case .nextPage: tour.next()
        case .previousPage: tour.back()
        case .skip: tour.skip()
        case .windowClosing: tour.releaseIsland()
        }
    }
}

@MainActor
struct OnboardingRecordWalkTests {
    private static func tour(_ world: RecordWorld) -> OnboardingTour {
        OnboardingTour(startingAt: .widgets, state: { world.state }, actions: world.actions)
    }

    /// A tour on the features page, on the Record step.
    private static func onRecordStep(_ world: RecordWorld) -> OnboardingTour {
        let tour = Self.tour(world)
        tour.next()
        tour.actions.nextFeature()
        tour.actions.nextFeature()
        return tour
    }

    @Test func theStepIsAfterTheWidgetsOnThePageAndBeforeTheKit() {
        let world = RecordWorld()
        let tour = Self.onRecordStep(world)

        #expect(tour.state.featureKind == .record)
        #expect(tour.state.featureWalk.kinds == [.media, .notes, .record, .design, .linkAudio].filter(\.isOffered))
    }

    @Test func aRecordTheToursButtonSwitchedOnIsSwitchedOffWhenTheStepIsLeft() {
        let world = RecordWorld()
        let tour = Self.onRecordStep(world)
        let progress = tour.state.featureProgress
        #expect(OnboardingTry.recordOn.button(tour.state.features, progress: progress).isEnabled)

        OnboardingTry.recordOn.press(reading: tour.state.features, sample: "", actions: tour.actions)

        #expect(world.calls == ["record true"])
        #expect(tour.state.features.isRecordOn, "the card is on the page the tour draws")
        #expect(tour.state.featureProgress.done.contains(.recordOn))
        #expect(!OnboardingTry.recordOn.button(tour.state.features, progress: tour.state.featureProgress).isEnabled)

        tour.actions.nextFeature()

        #expect(world.calls == ["record true", "record false"])
        #expect(!world.isRecordOn)
    }

    @Test(arguments: OnboardingRecordExit.allCases)
    func everyWayOutSwitchesOffARecordTheButtonSwitchedOn(exit: OnboardingRecordExit) {
        let world = RecordWorld()
        let tour = Self.onRecordStep(world)
        tour.actions.setWidget(.record, true)
        #expect(world.isRecordOn)

        exit.leave(tour)

        #expect(!world.isRecordOn, "\(exit) left Record on")
        #expect(world.calls.filter { $0 == "record false" }.count == 1, "\(exit): \(world.calls)")
    }

    @Test(arguments: OnboardingRecordExit.allCases)
    func aRecordTheUserHadOnBeforeIsLeftOnByEveryWayOut(exit: OnboardingRecordExit) {
        let world = RecordWorld(recordOn: true)
        let tour = Self.onRecordStep(world)
        #expect(!OnboardingTry.recordOn.button(tour.state.features, progress: tour.state.featureProgress).isEnabled)

        // Pressing a switch that is already on does not make it the tour's.
        tour.actions.setWidget(.record, true)
        exit.leave(tour)

        #expect(world.isRecordOn, "\(exit) switched off a Record that was the user's")
        #expect(!world.calls.contains("record false"), "\(exit): \(world.calls)")
    }

    @Test func aRecordSwitchedOnOnTheWidgetsPageIsTheUsersAndStaysOn() {
        let world = RecordWorld()
        let tour = Self.tour(world)
        tour.actions.setWidget(.record, true)
        tour.next()
        tour.actions.nextFeature()
        tour.actions.nextFeature()
        #expect(tour.state.featureKind == .record)
        tour.actions.nextFeature()
        tour.next()
        tour.releaseIsland()

        #expect(world.isRecordOn)
        #expect(world.calls == ["record true"])
    }

    @Test func aRecordThatWasNeverTouchedStaysOffThroughTheWholeWalk() {
        let world = RecordWorld()
        let tour = Self.tour(world)
        tour.next()
        for _ in 0..<12 { tour.actions.nextFeature() }
        tour.next()
        tour.skip()

        #expect(world.calls.isEmpty)
        #expect(!world.isRecordOn)
    }

    @Test func aRecordTheUserSwitchedOffByHandBeforeLeavingIsNotSwitchedOffAgain() {
        let world = RecordWorld()
        let tour = Self.onRecordStep(world)
        tour.actions.setWidget(.record, true)
        // The user turns it off in Settings, under the tour's feet.
        world.actions.setWidget(.record, false)
        _ = tour.state
        world.calls.removeAll()

        tour.actions.nextFeature()

        #expect(world.calls.isEmpty, "nothing is left of the tour's to put back")
    }

    // MARK: A layout

    @Test func aLayoutPutsBackARecordTheUserSwitchedOnAsItDoesForTheKit() {
        let world = RecordWorld()
        let tour = Self.tour(world)
        tour.actions.setWidget(.record, true)
        world.calls.removeAll()

        tour.actions.applyTemplate(PersonalizationTemplate.all[0])

        #expect(world.calls == ["record true"])
    }

    @Test func aLayoutDoesNotPutBackARecordTheWalkSwitchedOnAndLetGo() {
        let world = RecordWorld()
        let tour = Self.onRecordStep(world)
        OnboardingTry.recordOn.press(reading: tour.state.features, sample: "", actions: tour.actions)
        tour.actions.nextFeature()
        #expect(!world.isRecordOn)
        world.calls.removeAll()

        tour.actions.applyTemplate(PersonalizationTemplate.all[0])

        #expect(world.calls.isEmpty, "the tour's own try is no pick")
    }

    @Test func noTemplateListsRecord() {
        for template in PersonalizationTemplate.all {
            #expect(!template.widgets.contains { $0.kind == .record }, "\(template.id) lists Record")
        }
    }
}

// MARK: - Through the real models

@MainActor
struct OnboardingRecordInTheAppTests {
    private static func model() -> AppModel {
        let nook = NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
        let model = AppModel(agentsDefaults: MemoryDefaults(), defaults: MemoryDefaults(), nookModel: nook)
        nook.activeProfile = { [weak model] in model?.activeAppearanceProfile ?? .topBar }
        return model
    }

    /// The tour's own wiring over the app's real models, with the door to the
    /// overlay left out: only the widget's switch reaches the Nook.
    private static func tour(over model: AppModel) -> OnboardingTour {
        var actions = OnboardingActions()
        actions.setWidget = { [model] kind, isOn in model.setTourWidget(kind, enabled: isOn) }
        return OnboardingTour(startingAt: .widgets, state: { model.onboardingState }, actions: actions)
    }

    @Test func theButtonSwitchesTheRealWidgetOnAndLeavingSwitchesItOffWithNothingRecorded() {
        let model = Self.model()
        let tour = Self.tour(over: model)
        tour.next()
        for _ in 0..<12 where tour.state.featureKind != .record { tour.actions.nextFeature() }
        #expect(tour.state.featureKind == .record)
        #expect(!model.nook.isWidgetEnabled(.record), "Record starts off")
        #expect(!tour.state.features.isRecordOn)

        OnboardingTry.recordOn.press(reading: tour.state.features, sample: "", actions: tour.actions)

        #expect(model.nook.isWidgetEnabled(.record))
        #expect(model.nook.widgetPlacements(for: model.activeAppearanceProfile).contains { $0.kind == .record })
        #expect(tour.state.features.isRecordOn)
        #expect(model.nook.record.phase == .idle, "the tour started no recording")

        tour.actions.nextFeature()

        #expect(!model.nook.isWidgetEnabled(.record))
        #expect(!tour.state.features.isRecordOn)
        #expect(model.nook.record.phase == .idle)
    }

    @Test func aRecordTheUserSwitchedOnInSettingsBeforeTheTourSurvivesTheWholeWalk() {
        let model = Self.model()
        model.nook.setWidgetFromSettings(.record, enabled: true)
        let tour = Self.tour(over: model)
        tour.next()
        #expect(tour.state.features.isRecordOn)
        for _ in 0..<12 { tour.actions.nextFeature() }
        tour.next()
        tour.releaseIsland()

        #expect(model.nook.isWidgetEnabled(.record))
    }

    @Test func recordStartsOffAndIsAmongTheWidgetsThatDo() {
        let model = Self.model()
        #expect(!model.nook.isWidgetEnabled(.record))
        #expect(!model.onboardingState.showsWidget(.record))
        #expect(NookWidgetKind.startsOff.contains(.record))
    }
}

// MARK: - The words

struct OnboardingRecordStringsTests {
    /// Every line the Record step, its page, the Convert page and the tip add.
    private static var keys: [String] {
        var keys = [
            "onboarding.nook.widget.record", "onboarding.widgets.record",
            "onboarding.features.try.recordOn", "onboarding.features.try.recordOn.note",
            "onboarding.feature.trayConvert",
            "onboarding.tips.dropFiles.title", "onboarding.tips.dropFiles.text",
            "onboarding.features.note", "onboarding.features.note.release",
            "onboarding.permissions.record.title", "onboarding.permissions.record.when", "onboarding.permissions.record.note",
            "onboarding.permissions.camera.when", "onboarding.permissions.camera.note",
            "onboarding.widgets.note", "onboarding.widgets.note.release",
        ]
        keys += OnboardingAbility.lines(for: .record).map(\.textKey)
        for more in [OnboardingMore.record, .convert] {
            keys += [more.titleKey, more.textKey, more.whereKey]
            if more.hasNote { keys.append(more.noteKey) }
        }
        return keys
    }

    @Test(arguments: HangoverBrandTests.languages)
    func everyLineIsThereInEveryLanguage(language: String) throws {
        let table = try HangoverBrandTests.table(language)
        for key in Self.keys {
            #expect(!(table[key] ?? "").isEmpty, "\(language) is missing \(key)")
        }
    }

    /// A Chinese line is written in Chinese, not left in English.
    @Test(arguments: ["zh-Hans", "zh-Hant"])
    func theChineseLinesAreInChinese(language: String) throws {
        let table = try HangoverBrandTests.table(language)
        let english = try HangoverBrandTests.table("en")
        for key in Self.keys {
            let value = try #require(table[key])
            #expect(value != english[key], "\(language) \(key) is the English line")
            let hasChinese = value.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
            #expect(hasChinese, "\(language) \(key) has no Chinese in it")
        }
    }

    @Test func theEnglishLinesAreWrittenPlainly() throws {
        let english = try HangoverBrandTests.table("en")
        for key in Self.keys {
            let value = try #require(english[key])
            #expect(value.range(of: "\\bso\\b", options: [.regularExpression, .caseInsensitive]) == nil, "\(key) uses the banned word")
            #expect(!value.contains("\u{2014}") && !value.contains("\u{2013}"), "\(key) has a dash")
        }
    }

    /// The footnote and the button's note both say the tour starts no
    /// recording, in every language.
    @Test(arguments: HangoverBrandTests.languages)
    func theNotesSayTheTourNeverStartsARecording(language: String) throws {
        let table = try HangoverBrandTests.table(language)
        let phrase = ["en": "never starts a recording", "zh-Hans": "不会开始任何录制", "zh-Hant": "不會開始任何錄製"]
        let expected = try #require(phrase[language])
        for key in ["onboarding.features.note", "onboarding.features.note.release"] {
            #expect(try #require(table[key]).contains(expected), "\(language) \(key)")
        }
        let note = try #require(table["onboarding.features.try.recordOn.note"])
        let noteWords = ["en": "Nothing is recorded", "zh-Hans": "不会录任何内容", "zh-Hant": "不會錄任何內容"]
        #expect(note.contains(try #require(noteWords[language])), "\(language) \(note)")
    }

    /// The Record shortcut the line names is the one the code holds, and the
    /// folder is the one recordings are saved in.
    @Test func theLinesNameTheShortcutAndTheFolderTheCodeHolds() throws {
        let english = try HangoverBrandTests.table("en")
        let shortcut = try #require(english[OnboardingAbility.recordShortcut.textKey])
        let combo = NookRecordHotkeyRules.defaultCombo
        #expect(combo.modifiers == [.control, .option] && combo.keyCode == UInt16(kVK_ANSI_R))
        #expect(shortcut.contains("Control Option R"))
        let saved = try #require(english[OnboardingAbility.recordSaved.textKey])
        #expect(saved.contains("Movies") && saved.contains("Hangover") && saved.contains("tray"))
    }

    /// The tray tip names the Convert menu in every language, with no blank
    /// to fill: a list of the choices made the card too tall.
    @Test(arguments: HangoverBrandTests.languages)
    func theTrayTipNamesConvertAndHasNoBlanks(language: String) throws {
        let table = try HangoverBrandTests.table(language)
        let text = try #require(table["onboarding.tips.dropFiles.text"])
        let word = ["en": "Convert", "zh-Hans": "转换", "zh-Hant": "轉換"]
        #expect(text.contains(try #require(word[language])), "\(language) \(text)")
        #expect(!text.contains("%@"), "\(language) \(text)")
    }
}

// MARK: - The Convert tip and the Convert page

struct OnboardingConvertTests {
    @Test func everyTipReadsItsOwnString() {
        let lang = LanguageManager.shared
        for tip in OnboardingTip.allCases {
            let key = "onboarding.tips.\(tip.keyName(openTrigger: .click)).text"
            #expect(tip.text(openTrigger: .click, lang: lang) == lang.t(key), "\(tip)")
        }
    }

    @Test func theTipIsAboutTheTrayAndShowsOnlyWhileTheTrayIsOnThePage() {
        #expect(OnboardingTip.dropFiles.widget == .tray)
        let withTray = OnboardingTip.shown(agentsEnabled: false, widgets: [.tray])
        let without = OnboardingTip.shown(agentsEnabled: false, widgets: [.media])
        #expect(withTray.contains(.dropFiles))
        #expect(!without.contains(.dropFiles))
        // One tip for the tray. A second one, for Convert alone, pushed a
        // widget's tip off the page.
        #expect(!OnboardingTip.allCases.map(\.rawValue).contains("convertFiles"))
    }

    @Test func theLongTourHasAConvertPageAndTheShortAndMainOnesDoNot() {
        #expect(OnboardingPage.convert.shortestLength == .long)
        #expect(OnboardingPage.record.shortestLength == .long)
        for length in [OnboardingLength.short, .medium] {
            let pages = OnboardingPage.shown(length: length, agentsEnabled: true)
            #expect(!pages.contains(.convert) && !pages.contains(.record), "\(length)")
        }
        let long = OnboardingPage.shown(length: .long, agentsEnabled: true)
        #expect(long.firstIndex(of: .record).map { $0 + 1 } == long.firstIndex(of: .convert), "Convert follows Record")
    }

    @Test func theMainTourStillTeachesConvertThroughTheTipAndTheFeaturesStep() {
        let medium = OnboardingPage.shown(length: .medium, agentsEnabled: true)
        #expect(medium.contains(.features) && medium.contains(.tips))
        #expect(OnboardingAbility.lines(for: .tray).contains(.trayConvert))
        #expect(OnboardingAbility.lines(for: .record).count >= 4)
    }

    @Test func theConvertPageIsAboutTheRulesTheTrayHolds() {
        let proofs = OnboardingMore.convert.proofs
        #expect(proofs.contains { $0.file.hasSuffix("NookConvertRules.swift") })
        #expect(proofs.contains { $0.file.hasSuffix("NookTrayCard.swift") })
    }
}

// MARK: - What macOS asks

/// The permissions page names what Record makes macOS ask for, and the code
/// asks for exactly that.
struct OnboardingRecordPermissionTests {
    @Test func theRowIsListedWhetherOrNotRecordIsOnAndSitsAfterTheCalendar() {
        for agents in [true, false] {
            let grants = OnboardingGrant.shown(agentsEnabled: agents)
            #expect(grants.contains(.record), "agents \(agents)")
            #expect(grants.firstIndex(of: .calendar).map { $0 + 1 } == grants.firstIndex(of: .record))
        }
        #expect(OnboardingGrant.record.symbol == "record.circle")
        #expect(!OnboardingGrant.record.isAgentsOnly)
        #expect(OnboardingGrant.record.noteKey(agentsEnabled: true) == "onboarding.permissions.record.note")
    }

    /// The short tour walks the permissions page while a widget that makes
    /// macOS ask is on the page, and Record is one now.
    @MainActor
    @Test func theShortTourWalksThePermissionsPageWhileRecordIsOnThePage() {
        func pages(_ kinds: [NookWidgetKind]) -> [OnboardingPage] {
            var state = OnboardingState(agentsEnabled: false, enabledWidgets: Set(kinds))
            state.length = .short
            state.nookPlacements = kinds.map { NookWidgetPlacement(kind: $0, size: .medium) }
            return OnboardingTour.pages(for: state)
        }
        #expect(pages([.media, .timer, .record]).contains(.permissions))
        #expect(!pages([.media, .timer]).contains(.permissions))
        #expect(OnboardingGrant.widgetsAskingMacOS.contains(.record))
    }

    /// Each ask the page names is in the code that records: Screen Recording
    /// for the screen and an area but not a picked window, the microphone for
    /// Voice, and the camera for the face cam.
    @Test(arguments: [
        ("Sources/OpenIslandApp/Nook/Widgets/Record/NookScreenRecorder.swift", "if target != .pickedWindow { try requireScreenAccess() }"),
        ("Sources/OpenIslandApp/Nook/Widgets/Record/NookScreenRecorder.swift", "CGRequestScreenCaptureAccess()"),
        ("Sources/OpenIslandApp/Nook/Widgets/Record/NookScreenRecorder.swift", "AVCaptureDevice.requestAccess(for: .audio)"),
        ("Sources/OpenIslandApp/Nook/Widgets/Record/NookFaceCamBubble.swift", "AVCaptureDevice.requestAccess(for: .video)"),
    ])
    func theAskThePageNamesIsInTheCode(file: String, line: String) throws {
        let source = try HangoverBrandTests.text(of: file)
        #expect(source.contains(line), "\(file) no longer has: \(line)")
    }

    @Test(arguments: HangoverBrandTests.languages)
    func theCameraRowNamesTheFaceCamAndTheRecordRowNamesScreenAndMicrophone(language: String) throws {
        let table = try HangoverBrandTests.table(language)
        let faceCam = ["en": "face cam", "zh-Hans": "摄像头小圆窗", "zh-Hant": "鏡頭小圓窗"]
        let screen = ["en": "Screen Recording", "zh-Hans": "屏幕录制", "zh-Hant": "螢幕錄製"]
        let microphone = ["en": "microphone", "zh-Hans": "麦克风", "zh-Hant": "麥克風"]
        for key in ["onboarding.permissions.camera.when", "onboarding.permissions.camera.note"] {
            #expect(try #require(table[key]).contains(try #require(faceCam[language])), "\(language) \(key)")
        }
        let note = try #require(table["onboarding.permissions.record.note"])
        #expect(note.contains(try #require(screen[language])), "\(language) \(note)")
        #expect(note.contains(try #require(microphone[language])), "\(language) \(note)")
    }
}
