import EventKit
import Foundation
import Testing
@testable import OpenIslandApp

// The features page of the welcome tour (D47): the page order, the walk
// through the widgets, the lines and the numbers in them, the "Try it"
// buttons and their doors, the ticks, the clean-up on every way out, and the
// permission rule. Nothing here opens a window, starts the camera, or reads
// or writes the real clipboard or the real defaults.

// MARK: - The page

struct OnboardingFeaturesFlowTests {
    @Test func theFeaturesPageSitsRightAfterWidgetsAndBeforeLayout() {
        #expect(OnboardingPage.widgets.next == .features)
        #expect(OnboardingPage.features.next == .layout)
        #expect(OnboardingPage.features.previous == .widgets)
        #expect(OnboardingPage.features.chapter == .yours)
        #expect(OnboardingPage.features.snapshotName == "07-features")
    }

    @Test func itIsALivePageAndEveryOtherLivePageStaysLive() {
        #expect(OnboardingPage.features.isLive)
        #expect(OnboardingPage.allCases.filter(\.isLive) == [
            .widgets, .features, .layout, .arrange, .todos, .notes, .weather, .opened,
        ])
    }

    @Test func noRunOfTheTourLeavesItOut() {
        #expect(OnboardingPage.shown(agentsEnabled: false, hasTodoWidget: false, hasNotesWidget: false, hasWeatherWidget: false)
            .contains(.features))
    }
}

// MARK: - The walk

struct OnboardingFeatureWalkTests {
    private static let kinds: [NookWidgetKind] = [.timer, .mirror, .media]

    @Test func theWalkIsTheWidgetsOnThePageInTheOrderTheySitThere() {
        let state = OnboardingState(
            enabledWidgets: Set(NookWidgetKind.allCases),
            nookPlacements: Self.kinds.map { NookWidgetPlacement(kind: $0, size: .medium) }
        )
        #expect(state.featureWalk.kinds == Self.kinds)
        #expect(state.featureWalk.current == .timer)
    }

    @Test func aWidgetSwitchedOffIsNotWalked() {
        let placements = [NookWidgetKind.media, .notes].map { NookWidgetPlacement(kind: $0, size: .medium) }
        let walk = OnboardingState(nookPlacements: placements).featureWalk
        #expect(walk.kinds == [.media, .notes])
        #expect(!walk.kinds.contains(.mirror))
    }

    @Test func nextAndPreviousMoveThroughTheListAndStopAtTheEnds() {
        let first = OnboardingFeatureWalk(kinds: Self.kinds, current: nil)
        #expect(first.current == .timer && first.previous == nil && first.next == .mirror)
        #expect(first.position == 1 && first.count == 3 && !first.isAtEnd)

        let middle = OnboardingFeatureWalk(kinds: Self.kinds, current: .mirror)
        #expect(middle.previous == .timer && middle.next == .media && middle.position == 2)

        let last = OnboardingFeatureWalk(kinds: Self.kinds, current: .media)
        #expect(last.next == nil && last.previous == .mirror && last.position == 3 && last.isAtEnd)
    }

    @Test func aCurrentWidgetOffThePageGivesWayToTheFirstOne() {
        let walk = OnboardingFeatureWalk(kinds: Self.kinds, current: .weather)
        #expect(walk.current == .timer && walk.position == 1)
    }

    @Test func noWidgetsIsAnEmptyWalkAtItsEnd() {
        let walk = OnboardingFeatureWalk(kinds: [], current: .mirror)
        #expect(walk.current == nil && walk.count == 0 && walk.position == 0)
        #expect(walk.next == nil && walk.previous == nil && walk.isAtEnd)
    }
}

// MARK: - The lines and the numbers in them

struct OnboardingFeatureNumbersTests {
    private static func english(_ ability: OnboardingAbility) throws -> String {
        try #require(try HangoverBrandTests.table("en")[ability.textKey])
    }

    /// The numbers a line says are counted from the code.
    @Test func theNumbersInTheMirrorLinesMatchTheCode() throws {
        let shots = NookPhotoStripLayout.Kind.allCases.map { NookPhotoStripLayout.layout($0).shots }
        #expect(Set(shots).count == 1, "one number of pictures for every layout")
        let pictures = try #require(shots.first)
        #expect(try Self.english(.mirrorBooth).contains("\(pictures) pictures"))

        let looks = try Self.english(.mirrorLooks)
        #expect(looks.contains("\(NookPhotoStripLayout.Kind.allCases.count) layouts"))
        #expect(looks.contains("\(NookPhotoStripTheme.all.count) themes"))

        let note = try #require(try HangoverBrandTests.table("en")["onboarding.features.try.photoBooth.note"])
        #expect(note.contains("\(pictures) pictures"))
    }

    @Test func theFolderTheLineNamesIsTheOneTheBoothWritesTo() throws {
        #expect(try Self.english(.mirrorSaved).contains(NookPhotoBoothStore.folderName))
        #expect(NookPhotoBoothStore.defaultFolder().deletingLastPathComponent().lastPathComponent == "Pictures")
    }

    @Test func theCalendarNoticesAreTenAndTwoMinutes() throws {
        let line = try Self.english(.calendarNext)
        #expect(line.contains("10 and 2 minutes"))
        #expect(NookMeetingPrompt.lead == TimeInterval(10 * 60))
    }

    /// The camera picture is shown and written to a file on this Mac.
    /// Nothing in the mirror's code sends it over a network.
    @Test func noMirrorCodeTouchesTheNetwork() throws {
        let folder = HangoverBrandTests.repoRoot.appendingPathComponent("Sources/OpenIslandApp/Nook/Widgets/Mirror", isDirectory: true)
        let files = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        #expect(files.count > 10)
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for word in ["URLSession", "URLRequest", "NWConnection", "CFNetwork", "upload"] {
                #expect(!source.contains(word), "\(file.lastPathComponent) mentions \(word)")
            }
        }
        let note = try #require(try HangoverBrandTests.table("en")["onboarding.features.try.mirrorOn.note"])
        #expect(note.contains("never sent anywhere"))
    }

    @Test func everyFeatureAndButtonStringIsInEveryLanguageWithNoDashAndNoSo() throws {
        let keys = OnboardingAbility.allCases.map(\.textKey) + OnboardingTry.allCases.filter { $0 != .notesLine }.flatMap { step in
            [step.titleKey] + [step.offTitleKey].compactMap { $0 }
        }
        for language in HangoverBrandTests.languages {
            let table = try HangoverBrandTests.table(language)
            for key in keys + Self.pageKeys {
                let value = try #require(table[key], "\(language) is missing \(key)")
                #expect(!value.isEmpty)
                #expect(!value.contains("\u{2014}") && !value.contains("\u{2013}"), "\(language) \(key) has a dash")
                if language == "en" {
                    #expect(!value.lowercased().split(whereSeparator: { !$0.isLetter }).contains("so"), "\(key) says so")
                    #expect(!value.lowercased().contains("the open island"), "\(key) says the open island")
                }
            }
        }
    }

    static let pageKeys: [String] = [
        "title", "body", "none", "note", "count", "previous", "next", "can", "try", "others",
        "connected.todo", "connected.weather", "sample", "needsMirror", "needsSong", "waitCamera", "timerBusy",
        "try.mirrorOn.note", "try.photoBooth.note", "try.trayCopy.note", "try.calendarShow.note",
        "try.calendarShow.refused",
    ].map { "onboarding.features.\($0)" }

    @Test func theChineseStringsAreChineseAndKeepTheirNumbers() throws {
        for language in ["zh-Hans", "zh-Hant"] {
            let table = try HangoverBrandTests.table(language)
            for ability in OnboardingAbility.allCases {
                let value = try #require(table[ability.textKey])
                let hasHan = value.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
                #expect(hasHan, "\(language) \(ability.textKey) is not Chinese")
            }
            #expect(try #require(table["onboarding.feature.mirrorLooks"]).contains("16"))
            #expect(try #require(table["onboarding.feature.mirrorBooth"]).contains("4"))
        }
    }
}

// MARK: - The buttons and their doors

@MainActor
struct OnboardingTryTests {
    /// Every door the features page can reach, recording its name.
    private static func recorder(_ calls: Calls) -> OnboardingActions {
        var actions = OnboardingActions()
        actions.setMirror = { calls.names.append("setMirror"); calls.flag = $0 }
        actions.setRingLight = { calls.names.append("setRingLight"); calls.flag = $0 }
        actions.openPhotoBooth = { calls.names.append("openPhotoBooth") }
        actions.playOrPause = { calls.names.append("playOrPause") }
        actions.nextTrack = { calls.names.append("nextTrack") }
        actions.startTimer = { calls.names.append("startTimer"); calls.length = $0 }
        actions.stopTimer = { calls.names.append("stopTimer") }
        actions.copySampleLine = { calls.names.append("copySampleLine"); calls.text = $0 }
        actions.showNotes = { calls.names.append("showNotes") }
        actions.showCalendar = { calls.names.append("showCalendar") }
        return actions
    }

    final class Calls {
        var names: [String] = []
        var flag: Bool?
        var length: TimeInterval?
        var text: String?
    }

    @Test(arguments: OnboardingTry.allCases)
    func eachButtonCallsItsOwnDoorOnceAndNoOther(step: OnboardingTry) {
        let calls = Calls()
        step.press(reading: OnboardingFeatureReading(), sample: "a line", actions: Self.recorder(calls))
        #expect(calls.names == [step.doorName])
    }

    @Test func theSwitchesPressTheOppositeOfWhatIsOn() {
        let calls = Calls()
        let actions = Self.recorder(calls)
        OnboardingTry.mirrorOn.press(reading: OnboardingFeatureReading(), sample: "", actions: actions)
        #expect(calls.flag == true)
        OnboardingTry.mirrorOn.press(reading: OnboardingFeatureReading(isMirrorOn: true), sample: "", actions: actions)
        #expect(calls.flag == false)
        OnboardingTry.ringLight.press(reading: OnboardingFeatureReading(isMirrorOn: true), sample: "", actions: actions)
        #expect(calls.flag == true)
        OnboardingTry.ringLight.press(reading: OnboardingFeatureReading(isMirrorOn: true, isRingLightOn: true), sample: "", actions: actions)
        #expect(calls.flag == false)
    }

    @Test func theTimerIsOneMinuteAndTheCopyIsTheSampleLine() {
        let calls = Calls()
        OnboardingTry.timerStart.press(reading: OnboardingFeatureReading(), sample: "", actions: Self.recorder(calls))
        #expect(calls.length == 60)
        OnboardingTry.trayCopy.press(reading: OnboardingFeatureReading(), sample: "the sample", actions: Self.recorder(calls))
        #expect(calls.text == "the sample")
    }

    @Test func theAppWiresEachDoorToTheCallTheWidgetsOwnButtonMakes() throws {
        let source = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/AppModel+Onboarding.swift")
        let calls = [
            "nook.isMirrorOn = isOn", "nook.isRingLightOn = $0", "nook.photoBooth.start()",
            "nook.media.togglePlayPause()", "nook.media.nextTrack()", "nook.timer.start(length: $0)",
            "nook.timer.reset()", "nook.tray.clipboard.copy(text: text)",
            "nook.askForAccess(for: .calendar, at: .requested)",
        ]
        for call in calls {
            #expect(source.contains(call), "the app no longer wires \(call)")
        }
        // The same calls are the ones the widgets' own buttons make.
        let mirror = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Nook/Widgets/Mirror/NookMirrorCard.swift")
        #expect(mirror.contains("nook.isMirrorOn.toggle()") && mirror.contains("nook.isRingLightOn.toggle()"))
        let booth = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Nook/Widgets/Mirror/PhotoBooth/NookPhotoBooth.swift")
        #expect(booth.contains("booth.start()"))
        let timer = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Nook/Widgets/Timer/NookTimerCard.swift")
        #expect(timer.contains("timer.reset()"))
    }

    // MARK: How a button looks

    @Test func theMirrorButtonNamesTheCameraPromptBeforeTheClickAndOnlyThen() {
        let progress = OnboardingFeatureProgress()
        let off = OnboardingTry.mirrorOn.button(OnboardingFeatureReading(), progress: progress)
        #expect(off.noteKey == "onboarding.features.try.mirrorOn.note")
        #expect(off.titleKey == "onboarding.features.try.mirrorOn")
        let on = OnboardingTry.mirrorOn.button(OnboardingFeatureReading(isMirrorOn: true), progress: progress)
        #expect(on.noteKey == nil)
        #expect(on.titleKey == "onboarding.features.try.mirrorOn.off")
    }

    @Test func everyButtonThatRaisesAPromptNamesItInANoteBeforeTheClick() throws {
        let english = try HangoverBrandTests.table("en")
        #expect(OnboardingTry.allCases.filter(\.asksMacOS) == [.mirrorOn, .calendarShow])
        for step in OnboardingTry.allCases {
            let button = step.button(OnboardingFeatureReading(), progress: OnboardingFeatureProgress())
            guard step.asksMacOS else {
                let note = button.noteKey.flatMap { english[$0] } ?? ""
                #expect(!note.contains("macOS will ask"), "\(step) names a prompt it does not raise")
                continue
            }
            let note = try #require(button.noteKey.flatMap { english[$0] }, "\(step) has no note before the click")
            #expect(note.contains("macOS will ask"))
            #expect(button.isEnabled)
        }
    }

    @Test func theRingLightAndTheBoothWaitForTheMirror() {
        let progress = OnboardingFeatureProgress()
        let ring = OnboardingTry.ringLight.button(OnboardingFeatureReading(), progress: progress)
        #expect(!ring.isEnabled && ring.noteKey == "onboarding.features.needsMirror")
        let booth = OnboardingTry.photoBooth.button(OnboardingFeatureReading(), progress: progress)
        #expect(!booth.isEnabled && booth.noteKey == "onboarding.features.needsMirror")
        let waiting = OnboardingTry.photoBooth.button(OnboardingFeatureReading(isMirrorOn: true), progress: progress)
        #expect(!waiting.isEnabled && waiting.noteKey == "onboarding.features.waitCamera")
        let ready = OnboardingTry.photoBooth.button(OnboardingFeatureReading(isMirrorOn: true, canStartBooth: true), progress: progress)
        #expect(ready.isEnabled)
        let lit = OnboardingTry.ringLight.button(OnboardingFeatureReading(isMirrorOn: true, isRingLightOn: true), progress: progress)
        #expect(lit.isEnabled && lit.titleKey == "onboarding.features.try.ringLight.off")
    }

    @Test func theCalendarButtonAsksOnlyWhileTheAnswerIsUndecided() {
        let progress = OnboardingFeatureProgress()
        func button(_ access: OnboardingCalendarAccess) -> OnboardingTryButton {
            OnboardingTry.calendarShow.button(OnboardingFeatureReading(calendar: access), progress: progress)
        }
        #expect(button(.undecided).isEnabled)
        #expect(!button(.allowed).isEnabled && button(.allowed).noteKey == nil)
        #expect(!button(.refused).isEnabled && button(.refused).noteKey == "onboarding.features.try.calendarShow.refused")
    }

    @Test func aTimerThatWasRunningBeforeIsNeverStartedOrStoppedOverByTheTour() {
        var progress = OnboardingFeatureProgress()
        progress.note(OnboardingFeatureReading(isTimerActive: true))
        #expect(progress.isUsersTimer)
        let start = OnboardingTry.timerStart.button(OnboardingFeatureReading(isTimerActive: true), progress: progress)
        let stop = OnboardingTry.timerStop.button(OnboardingFeatureReading(isTimerActive: true), progress: progress)
        #expect(!start.isEnabled && start.noteKey == "onboarding.features.timerBusy")
        #expect(!stop.isEnabled)
        #expect(!progress.done.contains(.timerStart), "the user's own timer is not the tour's tick")
    }

    @Test func theTimerStartsWhenIdleAndStopsOnlyWhileRunning() {
        let progress = OnboardingFeatureProgress()
        #expect(OnboardingTry.timerStart.button(OnboardingFeatureReading(), progress: progress).isEnabled)
        #expect(!OnboardingTry.timerStop.button(OnboardingFeatureReading(), progress: progress).isEnabled)
        #expect(!OnboardingTry.timerStart.button(OnboardingFeatureReading(isTimerActive: true), progress: progress).isEnabled)
        #expect(OnboardingTry.timerStop.button(OnboardingFeatureReading(isTimerActive: true), progress: progress).isEnabled)
    }

    @Test func theMusicButtonSaysWhenNothingPlaysAndTheTrayButtonWhenItsTabIsOff() {
        let progress = OnboardingFeatureProgress()
        #expect(OnboardingTry.musicPlay.button(OnboardingFeatureReading(), progress: progress).noteKey == "onboarding.features.needsSong")
        let playing = OnboardingFeatureReading(music: OnboardingMusicReading(isPlaying: true, track: "a"))
        #expect(OnboardingTry.musicPlay.button(playing, progress: progress).noteKey == nil)
        #expect(OnboardingTry.trayCopy.button(OnboardingFeatureReading(), progress: progress).noteKey != nil)
        #expect(OnboardingTry.trayCopy.button(OnboardingFeatureReading(isClipboardOn: true), progress: progress).noteKey == nil)
    }

    @Test func onlyTheseWidgetsHaveButtonsAndTheOthersAreExplainedOnly() {
        let withButtons = Set(OnboardingTry.allCases.map(\.widget))
        #expect(withButtons == [.mirror, .media, .timer, .tray, .notes, .calendar])
        #expect(OnboardingTry.tries(for: .todo).isEmpty && OnboardingTry.tries(for: .weather).isEmpty)
        #expect(OnboardingTry.tries(for: .mirror) == [.mirrorOn, .ringLight, .photoBooth])
    }

    // MARK: The ticks

    @Test func aButtonTicksFromWhatTheAppShowsAndNotFromTheClick() {
        var progress = OnboardingFeatureProgress()
        progress.note(OnboardingFeatureReading())
        #expect(progress.done.isEmpty, "nothing is ticked by being shown")

        progress.note(OnboardingFeatureReading(isMirrorOn: true))
        #expect(progress.done == [.mirrorOn])
        progress.note(OnboardingFeatureReading(isMirrorOn: true, isRingLightOn: true, isBoothShowing: true))
        #expect(progress.done == [.mirrorOn, .ringLight, .photoBooth])
        progress.note(OnboardingFeatureReading())
        #expect(progress.done.contains(.mirrorOn), "a tick stays once it was seen")
    }

    @Test func theRingLightSavedAsOnTicksOnlyOnceTheMirrorShowsIt() {
        var progress = OnboardingFeatureProgress()
        progress.note(OnboardingFeatureReading(isRingLightOn: true))
        #expect(!progress.done.contains(.ringLight))
        progress.note(OnboardingFeatureReading(isMirrorOn: true, isRingLightOn: true))
        #expect(progress.done.contains(.ringLight))
    }

    @Test func theMusicTicksWhenItsStateOrTrackChangesFromWhatThePageFirstSaw() {
        var progress = OnboardingFeatureProgress()
        progress.note(OnboardingFeatureReading(music: OnboardingMusicReading(isPlaying: true, track: "one")))
        #expect(progress.done.isEmpty)
        progress.note(OnboardingFeatureReading(music: OnboardingMusicReading(isPlaying: false, track: "one")))
        #expect(progress.done == [.musicPlay])
        progress.note(OnboardingFeatureReading(music: OnboardingMusicReading(isPlaying: false, track: "two")))
        #expect(progress.done == [.musicPlay, .musicNext])
    }

    @Test func theTimerTicksWhenItRanAndAgainWhenItStopped() {
        var progress = OnboardingFeatureProgress()
        progress.note(OnboardingFeatureReading())
        progress.note(OnboardingFeatureReading(isTimerActive: true))
        #expect(progress.done == [.timerStart])
        progress.note(OnboardingFeatureReading())
        #expect(progress.done == [.timerStart, .timerStop])
    }

    @Test func theTrayAndTheCalendarTickFromTheListAndTheAccess() {
        var progress = OnboardingFeatureProgress()
        progress.note(OnboardingFeatureReading(calendar: .refused))
        #expect(progress.done.isEmpty)
        progress.note(OnboardingFeatureReading(hasSampleLine: true, calendar: .allowed))
        #expect(progress.done == [.trayCopy, .calendarShow])
    }

    @Test func theNotesStepTicksFromTheSavedNoteTheNotesPageUses() {
        var state = OnboardingState()
        #expect(!state.isDone(.notesLine))
        state.hasSavedNote = true
        #expect(state.isDone(.notesLine))
    }
}

// MARK: - The tray's line

@MainActor
struct OnboardingTrayCopyTests {
    private static let line = "This line came from the Hangover tour."

    @Test func theCopyGoesThroughThePasteboardDoorAndTheListShowsItWhenTheTabIsOn() {
        let pasteboard = NookFakePasteboard()
        let monitor = NookClipboardMonitor(pasteboard: pasteboard, defaults: MemoryDefaults())
        monitor.setEnabled(true)

        #expect(monitor.copy(text: Self.line))

        #expect(pasteboard.content == .text(Self.line), "it went to the pasteboard the monitor was given")
        #expect(monitor.history.entries.first?.content == .text(Self.line))
    }

    @Test func withTheTabOffTheLineIsCopiedAndNotListed() {
        let pasteboard = NookFakePasteboard()
        let monitor = NookClipboardMonitor(pasteboard: pasteboard, defaults: MemoryDefaults())

        #expect(monitor.copy(text: Self.line))

        #expect(pasteboard.content == .text(Self.line))
        #expect(monitor.history.entries.isEmpty)
    }

    @Test func theSampleLineIsInTheStringTable() throws {
        #expect(try HangoverBrandTests.table("en")[OnboardingFeatureSample.clipboardKey] == Self.line)
    }
}

// MARK: - The clean-up as plain values

struct OnboardingTrialsTests {
    private static let everythingOn = OnboardingFeatureReading(isMirrorOn: true, isRingLightOn: true, isTimerActive: true)

    @Test func whatTheTourSwitchedOnIsSwitchedOffAndTheRingLightGoesFirst() {
        let trials = OnboardingTrials(mirror: true, ringLight: true, timer: true)
        #expect(trials.releases(leaving: nil, reading: Self.everythingOn) == [.ringLightOff, .mirrorOff, .timerOff])
    }

    @Test func aThingThatWasOnBeforeIsNeverNotedAndSoNeverSwitchedOff() {
        let none = OnboardingTrials()
        #expect(none.releases(leaving: nil, reading: Self.everythingOn).isEmpty)
        let ringOnly = OnboardingTrials(ringLight: true)
        #expect(ringOnly.releases(leaving: nil, reading: Self.everythingOn) == [.ringLightOff])
    }

    @Test func aThingThatIsAlreadyOffIsNotSwitchedAgain() {
        let trials = OnboardingTrials(mirror: true, ringLight: true, timer: true)
        #expect(trials.releases(leaving: nil, reading: OnboardingFeatureReading()).isEmpty)
    }

    @Test func leavingTheMirrorReleasesTheMirrorAndItsLightAndLeavesTheTimer() {
        let trials = OnboardingTrials(mirror: true, ringLight: true, timer: true)
        #expect(trials.releases(leaving: .mirror, reading: Self.everythingOn) == [.ringLightOff, .mirrorOff])
        #expect(trials.after(leaving: .mirror) == OnboardingTrials(timer: true))
        #expect(trials.releases(leaving: .timer, reading: Self.everythingOn) == [.timerOff])
        #expect(trials.releases(leaving: .media, reading: Self.everythingOn).isEmpty)
        #expect(trials.after(leaving: nil) == OnboardingTrials())
    }
}

// MARK: - The permission rule

struct NookAccessRequestedTests {
    @Test func aClickedButtonMayAskForTheCalendarOnlyWhileTheWidgetIsOn() {
        let on = NookAccessTiming.permissions(for: .calendar, at: .requested, isEnabled: true, todoSource: .reminders)
        let off = NookAccessTiming.permissions(for: .calendar, at: .requested, isEnabled: false, todoSource: .reminders)
        #expect(on == [.calendar])
        #expect(off.isEmpty)
    }

    @Test func aClickAsksForNothingForAWidgetThatNeedsNothing() {
        for kind in NookWidgetKind.allCases where kind != .calendar && kind != .todo {
            let asked = NookAccessTiming.permissions(for: kind, at: .requested, isEnabled: true, todoSource: .reminders)
            #expect(asked.isEmpty, "\(kind) asked for \(asked)")
        }
    }

    @Test func theLaunchStillAsksForNothingAndATourHoldStillPutsNoWidgetInView() {
        for kind in NookWidgetKind.allCases {
            #expect(NookAccessTiming.permissions(for: kind, at: .launch, isEnabled: true, todoSource: .reminders).isEmpty)
        }
        let held = NookAccessTiming.widgetsInView(
            status: .opened, reason: .click, showsNookPage: true, pageWidgets: NookWidgetKind.allCases, isHeldByTour: true
        )
        #expect(held.isEmpty, "the tour asks for nothing by itself, however long the page is up")
        let opened = NookAccessTiming.widgetsInView(
            status: .opened, reason: .click, showsNookPage: true, pageWidgets: [.calendar], isHeldByTour: false
        )
        #expect(opened == [.calendar])
    }

    @Test func onlyThePressedButtonAsksAndOnlyWhenNothingWasDecided() {
        #expect(NookAccessTiming.shouldRequest(status: .notDetermined, isAlreadyAsking: false))
        #expect(!NookAccessTiming.shouldRequest(status: .fullAccess, isAlreadyAsking: false))
        #expect(!NookAccessTiming.shouldRequest(status: .denied, isAlreadyAsking: false))
        #expect(!NookAccessTiming.shouldRequest(status: .notDetermined, isAlreadyAsking: true))
    }

    @Test func theTourItselfNeverCallsTheRequestDoor() throws {
        // Only the app's showCalendar door raises the request, and that door
        // is reached from one button. No other tour file asks.
        let folder = HangoverBrandTests.repoRoot.appendingPathComponent("Sources/OpenIslandApp/Onboarding")
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(!source.contains("askForAccess"), "\(file.lastPathComponent) asks macOS by itself")
            // The to-dos page's own button (D44) is the one older request.
            let isTodoConnector = file.lastPathComponent == "OnboardingTodoConnector.swift"
            #expect(isTodoConnector || !source.contains("requestAccess"), "\(file.lastPathComponent) asks macOS by itself")
        }
    }
}
