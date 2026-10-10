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

    /// The footnote names exactly what goes off again (D49). Music is left
    /// as the user left it, on purpose.
    @Test func theFootnoteNamesWhatGoesOffAndSaysMusicIsLeftAlone() throws {
        for language in HangoverBrandTests.languages {
            let note = try #require(try HangoverBrandTests.table(language)["onboarding.features.note"])
            if language == "en" {
                for word in ["mirror", "ring light", "photo booth", "timer"] {
                    #expect(note.contains(word), "the footnote does not say \(word) goes off")
                }
                #expect(note.contains("Music keeps doing what you left it doing"))
                #expect(!note.contains("Anything a button turns on"), "the old promise covered music")
            }
        }
        for language in ["zh-Hans", "zh-Hant"] {
            let note = try #require(try HangoverBrandTests.table(language)["onboarding.features.note"])
            #expect(note.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) })
            #expect(note.contains("音"), "\(language) says nothing of music")
        }
    }

    static let pageKeys: [String] = [
        "title", "body", "none", "note", "count", "previous", "next", "can", "try", "others",
        "connected.todo", "connected.weather", "sample", "needsMirror", "needsSong", "waitCamera", "timerBusy",
        "startingCamera", "camera.refused", "camera.none", "camera.open", "copyFailed",
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
        actions.copySampleLine = { calls.names.append("copySampleLine"); calls.text = $0; return true }
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
            "setMirror(isOn)", "nook.isRingLightOn = $0", "nook.photoBooth.start()", "nook.photoBooth.cancel()",
            "NookMirrorController.openCameraSettings()",
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

    @Test func theTourSwitchesTheMirrorThroughTheLinksOwnFunctionAndNotByWritingTheFlag() throws {
        let tour = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/AppModel+Onboarding.swift")
        #expect(!tour.contains("nook.isMirrorOn = isOn"), "the tour skips the checks the link makes")
        let links = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/AppModel+URLActions.swift")
        #expect(links.contains("return setMirror(change.applied(to: nook.isMirrorOn))"), "the link uses the shared function")
        #expect(links.contains("guard showPage(.nook) else { return false }"), "the shared function shows the widgets page")
        #expect(!links.contains("private func setMirror"), "the tour could not reach a private function")
    }

    @Test func theMirrorsSettingsButtonIsTheOnlyDoorToTheCameraList() throws {
        let card = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Nook/Widgets/Mirror/NookMirrorCard.swift")
        #expect(card.components(separatedBy: "Privacy_Camera").count == 2, "one URL for the camera list")
        #expect(card.contains("NookMirrorController.openCameraSettings()"))
        let tour = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/AppModel+Onboarding.swift")
        #expect(!tour.contains("Privacy_Camera"), "the tour does not write a second door")
    }

    // MARK: How a button looks

    @Test func theMirrorButtonNamesTheCameraPromptBeforeTheClickAndOnlyWhileNothingWasDecided() {
        let progress = OnboardingFeatureProgress()
        let off = OnboardingTry.mirrorOn.button(OnboardingFeatureReading(camera: .undecided), progress: progress)
        #expect(off.noteKey == "onboarding.features.try.mirrorOn.note")
        #expect(off.titleKey == "onboarding.features.try.mirrorOn")
        let on = OnboardingTry.mirrorOn.button(OnboardingFeatureReading(isMirrorOn: true, camera: .undecided), progress: progress)
        #expect(on.noteKey == nil)
        #expect(on.titleKey == "onboarding.features.try.mirrorOn.off")
        let allowed = OnboardingTry.mirrorOn.button(OnboardingFeatureReading(camera: .allowed), progress: progress)
        #expect(allowed.noteKey == nil && allowed.isEnabled, "an allowed camera says nothing about asking")
    }

    @Test func aRefusedCameraSaysWhereToChangeItAndOffersTheSettingsButton() throws {
        let progress = OnboardingFeatureProgress()
        let refused = OnboardingTry.mirrorOn.button(OnboardingFeatureReading(camera: .refused), progress: progress)
        #expect(!refused.isEnabled, "a switch that can show nothing is not offered")
        #expect(refused.noteKey == "onboarding.features.camera.refused")
        #expect(refused.offersCameraSettings)
        let note = try #require(try HangoverBrandTests.table("en")["onboarding.features.camera.refused"])
        #expect(note.contains("Camera") && note.contains("Privacy and Security") && !note.contains("will ask"))

        // A mirror that is already on can still be switched off.
        let on = OnboardingTry.mirrorOn.button(OnboardingFeatureReading(isMirrorOn: true, camera: .refused), progress: progress)
        #expect(on.isEnabled && on.titleKey == "onboarding.features.try.mirrorOn.off" && on.offersCameraSettings)
    }

    @Test func noCameraSaysSoAndOffersNoSettingsButton() {
        let progress = OnboardingFeatureProgress()
        let none = OnboardingTry.mirrorOn.button(OnboardingFeatureReading(camera: .unavailable), progress: progress)
        #expect(!none.isEnabled && none.noteKey == "onboarding.features.camera.none" && !none.offersCameraSettings)
    }

    @Test func theBoothButtonNoteFollowsTheCameraState() {
        let progress = OnboardingFeatureProgress()
        func booth(_ reading: OnboardingFeatureReading) -> OnboardingTryButton {
            OnboardingTry.photoBooth.button(reading, progress: progress)
        }
        #expect(booth(OnboardingFeatureReading(isMirrorOn: true, camera: .refused)).noteKey == "onboarding.features.camera.refused")
        #expect(booth(OnboardingFeatureReading(camera: .refused)).noteKey == "onboarding.features.camera.refused")
        #expect(booth(OnboardingFeatureReading(isMirrorOn: true, camera: .unavailable)).noteKey == "onboarding.features.camera.none")
        #expect(booth(OnboardingFeatureReading(isMirrorOn: true, camera: .undecided)).noteKey == "onboarding.features.waitCamera")
        #expect(booth(OnboardingFeatureReading(isMirrorOn: true, camera: .allowed)).noteKey == "onboarding.features.startingCamera")
        #expect(booth(OnboardingFeatureReading(camera: .allowed)).noteKey == "onboarding.features.needsMirror")
        #expect(booth(OnboardingFeatureReading(camera: .undecided)).noteKey == "onboarding.features.needsMirror")
        for reading in [
            OnboardingFeatureReading(isMirrorOn: true, camera: .refused),
            OnboardingFeatureReading(isMirrorOn: true, camera: .unavailable),
        ] {
            #expect(!booth(reading).isEnabled)
        }
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
        let ready = OnboardingTry.photoBooth.button(
            OnboardingFeatureReading(isMirrorOn: true, camera: .allowed, canStartBooth: true), progress: progress
        )
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

    @Test func macOSsCameraAnswerBecomesTheStateTheNotesFollow() {
        #expect(OnboardingCameraAccess(status: .notDetermined, hasCamera: true) == .undecided)
        #expect(OnboardingCameraAccess(status: .authorized, hasCamera: true) == .allowed)
        #expect(OnboardingCameraAccess(status: .denied, hasCamera: true) == .refused)
        #expect(OnboardingCameraAccess(status: .restricted, hasCamera: true) == .refused)
        #expect(OnboardingCameraAccess(status: .authorized, hasCamera: false) == .unavailable)
        #expect(OnboardingCameraAccess(status: .notDetermined, hasCamera: false) == .unavailable)
        #expect(OnboardingCameraAccess(status: .denied, hasCamera: false) == .refused, "a refusal is the one the user can fix")
    }

    // MARK: The timer

    private static let tourTimer = OnboardingFeatureReading(isTimerActive: true, timerOneOff: OnboardingTry.timerLength)
    private static let usersTimer = OnboardingFeatureReading(isTimerActive: true)
    private static let usersPomodoro = OnboardingFeatureReading(isTimerActive: true, timerOneOff: nil)

    @Test func aTimerThatIsNotTheToursOwnCountdownIsTheUsersAndLocksTheTimerStep() {
        let progress = OnboardingFeatureProgress()
        for users in [Self.usersTimer, Self.usersPomodoro] {
            #expect(users.isUsersTimer && !users.isTourTimer)
            let start = OnboardingTry.timerStart.button(users, progress: progress)
            let stop = OnboardingTry.timerStop.button(users, progress: progress)
            #expect(!start.isEnabled && start.noteKey == "onboarding.features.timerBusy")
            #expect(!stop.isEnabled, "the tour does not stop a timer it did not start")
        }
        var ticks = OnboardingFeatureProgress()
        ticks.note(Self.usersTimer)
        #expect(!ticks.done.contains(.timerStart), "the user's own timer is not the tour's tick")
    }

    @Test func theTimerStepUnlocksTheMomentTheUsersTimerIsStopped() {
        let progress = OnboardingFeatureProgress()
        #expect(!OnboardingTry.timerStart.button(Self.usersTimer, progress: progress).isEnabled)
        let stopped = OnboardingFeatureReading()
        let start = OnboardingTry.timerStart.button(stopped, progress: progress)
        #expect(start.isEnabled && start.noteKey == nil)
    }

    @Test func aTimerRunningWhenThePageCameUpDoesNotLockItAfterItIsStopped() {
        // The old page latched the first reading for good.
        var progress = OnboardingFeatureProgress()
        progress.note(Self.usersTimer)
        progress.note(OnboardingFeatureReading())
        #expect(OnboardingTry.timerStart.button(OnboardingFeatureReading(), progress: progress).isEnabled)
    }

    @Test func theTimerStartsWhenIdleAndStopsOnlyWhileTheToursOwnMinuteRuns() {
        let progress = OnboardingFeatureProgress()
        #expect(OnboardingTry.timerStart.button(OnboardingFeatureReading(), progress: progress).isEnabled)
        #expect(!OnboardingTry.timerStop.button(OnboardingFeatureReading(), progress: progress).isEnabled)
        #expect(!OnboardingTry.timerStart.button(Self.tourTimer, progress: progress).isEnabled)
        #expect(OnboardingTry.timerStop.button(Self.tourTimer, progress: progress).isEnabled)
    }

    @Test func theMusicButtonSaysWhenNothingPlaysAndTheTrayButtonWhenItsTabIsOff() {
        let progress = OnboardingFeatureProgress()
        #expect(OnboardingTry.musicPlay.button(OnboardingFeatureReading(), progress: progress).noteKey == "onboarding.features.needsSong")
        let playing = OnboardingFeatureReading(music: OnboardingMusicReading(isPlaying: true, track: "a"))
        #expect(OnboardingTry.musicPlay.button(playing, progress: progress).noteKey == nil)
        #expect(OnboardingTry.trayCopy.button(OnboardingFeatureReading(), progress: progress).noteKey != nil)
        #expect(OnboardingTry.trayCopy.button(OnboardingFeatureReading(isClipboardOn: true), progress: progress).noteKey == nil)
    }

    @Test func aCopyThePasteboardRefusedShowsANoteAndAGoodCopyClearsIt() {
        var progress = OnboardingFeatureProgress()
        progress.copyFailed = true
        let reading = OnboardingFeatureReading(isClipboardOn: true)
        #expect(OnboardingTry.trayCopy.button(reading, progress: progress).noteKey == "onboarding.features.copyFailed")
        progress.copyFailed = false
        #expect(OnboardingTry.trayCopy.button(reading, progress: progress).noteKey == nil)
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

        progress.note(OnboardingFeatureReading(isMirrorOn: true, camera: .allowed))
        #expect(progress.done == [.mirrorOn])
        progress.note(OnboardingFeatureReading(isMirrorOn: true, isRingLightOn: true, camera: .allowed, hasBoothStrip: true))
        #expect(progress.done == [.mirrorOn, .ringLight, .photoBooth])
        progress.note(OnboardingFeatureReading())
        #expect(progress.done.contains(.mirrorOn), "a tick stays once it was seen")
    }

    @Test func theMirrorTicksOnlyWithTheCameraAllowed() {
        for camera in [OnboardingCameraAccess.undecided, .refused, .unavailable] {
            var progress = OnboardingFeatureProgress()
            progress.note(OnboardingFeatureReading(isMirrorOn: true, camera: camera))
            #expect(!progress.done.contains(.mirrorOn), "\(camera) ticked a mirror that shows nothing")
        }
    }

    @Test func theBoothTicksWhenAStripCameOutAndNotForAFailedSession() {
        var progress = OnboardingFeatureProgress()
        // A failure leaves the booth showing, with no strip.
        progress.note(OnboardingFeatureReading(isMirrorOn: true, camera: .allowed, isBoothShowing: true, hasBoothStrip: false))
        #expect(!progress.done.contains(.photoBooth))
        progress.note(OnboardingFeatureReading(isMirrorOn: true, camera: .allowed, isBoothShowing: true, hasBoothStrip: true))
        #expect(progress.done.contains(.photoBooth))
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

    @Test func theTimerStartTicksFromTheToursCountdownAndTheStopOnlyFromTheStopButton() {
        var progress = OnboardingFeatureProgress()
        progress.note(OnboardingFeatureReading())
        progress.note(Self.tourTimer)
        #expect(progress.done == [.timerStart])

        // The minute ran out by itself: not a stop.
        progress.note(OnboardingFeatureReading())
        #expect(progress.done == [.timerStart], "a minute that ran out is not a press of Stop")

        // The button stopped a running minute.
        progress.noteTimerStop(before: Self.tourTimer, after: OnboardingFeatureReading())
        #expect(progress.done == [.timerStart, .timerStop])
    }

    @Test func aStopThatStoppedNothingOfTheToursDoesNotTick() {
        var progress = OnboardingFeatureProgress()
        progress.noteTimerStop(before: Self.usersTimer, after: OnboardingFeatureReading())
        progress.noteTimerStop(before: OnboardingFeatureReading(), after: OnboardingFeatureReading())
        progress.noteTimerStop(before: Self.tourTimer, after: Self.tourTimer)
        #expect(progress.done.isEmpty)
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

// MARK: - A camera start that comes late

struct NookMirrorLateStartTests {
    @Test func theCameraStartsOnlyWhenGrantedAttachedAndTheMirrorIsStillOn() {
        #expect(NookMirrorController.shouldStart(isAuthorized: true, attachedCards: 1, isMirrorWanted: true))
        #expect(NookMirrorController.shouldStart(isAuthorized: true, attachedCards: 3, isMirrorWanted: true))
    }

    @Test func aStartThatArrivesAfterTheMirrorWentOffIsRefused() {
        // The answer to the prompt after Stop: granted, the card still
        // attached while it fades, and the mirror no longer wanted.
        #expect(!NookMirrorController.shouldStart(isAuthorized: true, attachedCards: 1, isMirrorWanted: false))
    }

    @Test func noAccessOrNoCardIsNoStart() {
        #expect(!NookMirrorController.shouldStart(isAuthorized: false, attachedCards: 1, isMirrorWanted: true))
        #expect(!NookMirrorController.shouldStart(isAuthorized: true, attachedCards: 0, isMirrorWanted: true))
        #expect(!NookMirrorController.shouldStart(isAuthorized: false, attachedCards: 0, isMirrorWanted: false))
    }

    @Test func stoppingNowMarksTheMirrorUnwantedAndTurningItOnWantsItAgain() throws {
        let source = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Nook/Widgets/Mirror/NookMirrorCard.swift")
        let stop = try #require(source.range(of: "func stopNow()"))
        let resume = try #require(source.range(of: "func resumeIfAttached()"))
        #expect(source[stop.upperBound...].prefix(400).contains("isMirrorWanted = false"))
        #expect(source[resume.upperBound...].prefix(120).contains("isMirrorWanted = true"))
        // The prompt's answer goes through the same decision as every start.
        let callback = try #require(source.range(of: "AVCaptureDevice.requestAccess"))
        #expect(source[callback.upperBound...].prefix(500).contains("startIfWanted()"))
        #expect(!source[callback.upperBound...].prefix(500).contains("configureAndRun()"))
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

    @Test func aPasteboardThatRefusesTheWriteMakesTheDoorReportFailure() {
        let pasteboard = NookFakePasteboard()
        pasteboard.acceptsWrites = false
        let monitor = NookClipboardMonitor(pasteboard: pasteboard, defaults: MemoryDefaults())
        monitor.setEnabled(true)

        #expect(!monitor.copy(text: Self.line))
        #expect(monitor.history.entries.isEmpty)
    }

    @Test func theSampleLineIsInTheStringTable() throws {
        #expect(try HangoverBrandTests.table("en")[OnboardingFeatureSample.clipboardKey] == Self.line)
    }
}

// MARK: - The clean-up as plain values

struct OnboardingTrialsTests {
    private static func trials(
        mirror: Bool = false, ring: Bool = false, ringWritten: Bool? = nil, booth: Bool = false, timer: Bool = false
    ) -> OnboardingTrials {
        OnboardingTrials(
            baseline: OnboardingFeatureBaseline(isMirrorOn: mirror, isRingLightOn: ring),
            ringLight: ringWritten,
            booth: booth,
            timer: timer
        )
    }

    private static let everythingOn = OnboardingFeatureReading(
        isMirrorOn: true, isRingLightOn: true, camera: .allowed, isBoothShowing: true, isTimerActive: true,
        timerOneOff: OnboardingTry.timerLength
    )

    @Test func theOrderIsTheBoothTheRingLightTheMirrorThenTheTimer() {
        let trials = Self.trials(ringWritten: true, booth: true, timer: true)
        #expect(trials.releases(leaving: nil, reading: Self.everythingOn) == [.boothCancel, .ringLight(false), .mirrorOff, .timerOff])
    }

    @Test func aMirrorThatWasOnAtTheBaselineIsLeftExactlyAsItIs() {
        let trials = Self.trials(mirror: true, booth: true)
        #expect(trials.releases(leaving: nil, reading: Self.everythingOn) == [.boothCancel], "the booth goes, the mirror stays")
        let off = OnboardingFeatureReading(camera: .allowed)
        #expect(trials.releases(leaving: nil, reading: off).isEmpty, "and a mirror that is off is never switched on")
    }

    @Test func theRingLightGoesBackToItsBaselineValueWhateverTheButtonsLeftIt() {
        let wasOn = Self.trials(mirror: true, ring: true, ringWritten: false)
        #expect(wasOn.releases(leaving: nil, reading: OnboardingFeatureReading(isMirrorOn: true, isRingLightOn: false))
            == [.ringLight(true)])
        let wasOff = Self.trials(mirror: true, ring: false, ringWritten: true)
        #expect(wasOff.releases(leaving: nil, reading: OnboardingFeatureReading(isMirrorOn: true, isRingLightOn: true))
            == [.ringLight(false)])
    }

    @Test func aRingLightAlreadyAtItsBaselineValueIsNotWrittenAgain() {
        let trials = Self.trials(mirror: true, ring: true, ringWritten: true)
        #expect(trials.releases(leaving: nil, reading: OnboardingFeatureReading(isMirrorOn: true, isRingLightOn: true)).isEmpty)
    }

    @Test func aRingLightNoButtonChangedIsNeverWritten() {
        let trials = Self.trials(mirror: true, ring: false)
        #expect(trials.releases(leaving: nil, reading: OnboardingFeatureReading(isMirrorOn: true, isRingLightOn: true)).isEmpty)
    }

    @Test func nothingIsReleasedBeforeTheBaselineIsTaken() {
        #expect(OnboardingTrials(ringLight: true, booth: true, timer: true).releases(leaving: nil, reading: Self.everythingOn).isEmpty)
    }

    @Test func aTimerIsResetOnlyWhileItIsStillTheToursOwnMinute() {
        let trials = Self.trials(mirror: true, timer: true)
        let tours = OnboardingFeatureReading(isTimerActive: true, timerOneOff: OnboardingTry.timerLength)
        #expect(trials.releases(leaving: nil, reading: tours) == [.timerOff])
        #expect(trials.releases(leaving: nil, reading: OnboardingFeatureReading()).isEmpty, "the minute ended")
        #expect(trials.releases(leaving: nil, reading: OnboardingFeatureReading(isTimerActive: true)).isEmpty, "the user's own")
        let pomodoro = OnboardingFeatureReading(isTimerActive: true, timerOneOff: 25 * 60)
        #expect(trials.releases(leaving: nil, reading: pomodoro).isEmpty, "a run of another length")
    }

    @Test func leavingTheMirrorReleasesItsPartsAndLeavesTheTimer() {
        let trials = Self.trials(ringWritten: true, booth: true, timer: true)
        #expect(trials.releases(leaving: .mirror, reading: Self.everythingOn) == [.boothCancel, .ringLight(false), .mirrorOff])
        #expect(trials.after(leaving: .mirror) == Self.trials(timer: true))
        #expect(trials.releases(leaving: .timer, reading: Self.everythingOn) == [.timerOff])
        #expect(trials.releases(leaving: .media, reading: Self.everythingOn).isEmpty)
        #expect(trials.after(leaving: nil) == OnboardingTrials())
    }

    // MARK: Looking at the app

    @Test func theTrialEndsWhenTheTimerIsSeenNotRunningOrNotTheToursAnyMore() {
        let trials = Self.trials(timer: true)
        let tours = OnboardingFeatureReading(isTimerActive: true, timerOneOff: OnboardingTry.timerLength)
        #expect(trials.observing(tours).timer)
        #expect(!trials.observing(OnboardingFeatureReading()).timer, "the minute ended or was stopped")
        #expect(!trials.observing(OnboardingFeatureReading(isTimerActive: true)).timer, "a timer by hand")
        #expect(!trials.observing(OnboardingFeatureReading(isTimerActive: true, timerOneOff: nil)).timer, "a pomodoro")
    }

    @Test func aBoothSessionThatIsGoneIsNoLongerTheTours() {
        let trials = Self.trials(booth: true)
        #expect(trials.observing(OnboardingFeatureReading(isBoothShowing: true)).booth)
        #expect(!trials.observing(OnboardingFeatureReading()).booth)
    }

    @Test func aRingLightTheUserChangedByHandIsNoLongerTheTours() {
        let trials = Self.trials(ringWritten: true)
        #expect(trials.observing(OnboardingFeatureReading(isRingLightOn: true)).ringLight == true)
        #expect(trials.observing(OnboardingFeatureReading(isRingLightOn: false)).ringLight == nil)
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
