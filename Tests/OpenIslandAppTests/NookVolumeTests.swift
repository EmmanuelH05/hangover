import AppKit
import Foundation
import Testing
@testable import OpenIslandApp

/// The volume notice in the closed notch, and the optional takeover of the
/// volume and brightness keys. Hardware, the Accessibility grant and the
/// key filter are all fakes: nothing here changes the real volume, the real
/// brightness or a system permission.
@MainActor
@Suite struct NookVolumeTests {
    private static let device: UInt32 = 95

    private static func reading(_ volume: Float?, muted: Bool = false, device: UInt32 = device) -> NookVolumeReading {
        NookVolumeReading(deviceID: device, volume: volume, isMuted: muted)
    }

    // MARK: Notice rules

    @Test func theFirstReadingAndAnotherOutputTakingOverSayNothing() {
        #expect(NookVolumeNotice.content(from: nil, to: Self.reading(0.5)) == nil)
        #expect(NookVolumeNotice.content(from: Self.reading(0.5, device: 1), to: Self.reading(0.2, device: 2)) == nil)
    }

    @Test func aChangeTooSmallToShowSaysNothing() {
        #expect(NookVolumeNotice.content(from: Self.reading(0.5), to: Self.reading(0.501)) == nil)
        #expect(NookVolumeNotice.content(from: Self.reading(0.5), to: Self.reading(0.5)) == nil)
    }

    @Test func aVolumeChangeShowsThePercentWithAMatchingSpeaker() {
        let quiet = NookVolumeNotice.content(from: Self.reading(0.5), to: Self.reading(0.25))
        #expect(quiet == NookVolumeNoticeContent(symbol: "speaker.wave.1.fill", percent: 25, isMuted: false))
        let middle = NookVolumeNotice.content(from: Self.reading(0.25), to: Self.reading(0.5))
        #expect(middle == NookVolumeNoticeContent(symbol: "speaker.wave.2.fill", percent: 50, isMuted: false))
        let loud = NookVolumeNotice.content(from: Self.reading(0.5), to: Self.reading(1))
        #expect(loud == NookVolumeNoticeContent(symbol: "speaker.wave.3.fill", percent: 100, isMuted: false))
        let silent = NookVolumeNotice.content(from: Self.reading(0.5), to: Self.reading(0))
        #expect(silent == NookVolumeNoticeContent(symbol: "speaker.fill", percent: 0, isMuted: false))
    }

    @Test func muteShowsTheCrossedSpeakerAndNoPercent() {
        let muted = NookVolumeNotice.content(from: Self.reading(0.5), to: Self.reading(0.5, muted: true))
        #expect(muted == NookVolumeNoticeContent(symbol: "speaker.slash.fill", percent: nil, isMuted: true))
        let back = NookVolumeNotice.content(from: Self.reading(0.5, muted: true), to: Self.reading(0.5))
        #expect(back == NookVolumeNoticeContent(symbol: "speaker.wave.2.fill", percent: 50, isMuted: false))
        // An output with no volume of its own can still mute.
        let display = NookVolumeNotice.content(from: Self.reading(nil), to: Self.reading(nil, muted: true))
        #expect(display == NookVolumeNoticeContent(symbol: "speaker.slash.fill", percent: nil, isMuted: true))
    }

    // MARK: Key rules

    @Test func theSystemKeyCodesMapToTheKeysTheAppTakes() {
        #expect(NookMediaKey(keyCode: 0) == .volumeUp)
        #expect(NookMediaKey(keyCode: 1) == .volumeDown)
        #expect(NookMediaKey(keyCode: 7) == .mute)
        #expect(NookMediaKey(keyCode: 2) == .brightnessUp)
        #expect(NookMediaKey(keyCode: 3) == .brightnessDown)
        // Play, next and the keyboard backlight keys are left alone.
        #expect(NookMediaKey(keyCode: 16) == nil)
        #expect(NookMediaKey(keyCode: 21) == nil)
    }

    @Test func aKeyEventIsReadOutOfTheSystemEventData() {
        let volumeUpDown = (0 << 16) | (0x0A << 8)
        let volumeUpUp = (0 << 16) | (0x0B << 8)
        let muteDown = (7 << 16) | (0x0A << 8)
        let playDown = (16 << 16) | (0x0A << 8)

        #expect(NookEventTapKeyFilter.keyEvent(data1: volumeUpDown, flags: []) == NookMediaKeyEvent(key: .volumeUp, isDown: true))
        #expect(NookEventTapKeyFilter.keyEvent(data1: volumeUpUp, flags: []) == NookMediaKeyEvent(key: .volumeUp, isDown: false))
        #expect(NookEventTapKeyFilter.keyEvent(data1: playDown, flags: []) == nil)
        let fine = NookEventTapKeyFilter.keyEvent(data1: muteDown, flags: [.shift, .option])
        #expect(fine == NookMediaKeyEvent(
            key: .mute, isDown: true, modifiers: NookMediaKeyModifiers(shift: true, option: true)
        ))
    }

    @Test func keysMacOSGivesAnotherMeaningStayWithMacOS() {
        #expect(!NookMediaKeyRules.staysWithSystem(NookMediaKeyModifiers()))
        #expect(!NookMediaKeyRules.staysWithSystem(NookMediaKeyModifiers(shift: true)))
        #expect(!NookMediaKeyRules.staysWithSystem(NookMediaKeyModifiers(shift: true, option: true)))
        #expect(NookMediaKeyRules.staysWithSystem(NookMediaKeyModifiers(option: true)))
        #expect(NookMediaKeyRules.staysWithSystem(NookMediaKeyModifiers(control: true)))
        #expect(NookMediaKeyRules.staysWithSystem(NookMediaKeyModifiers(command: true)))
        #expect(NookMediaKeyRules.isFine(NookMediaKeyModifiers(shift: true, option: true)))
        #expect(!NookMediaKeyRules.isFine(NookMediaKeyModifiers(shift: true)))
    }

    @Test func aStepIsOneSixteenthAndAFineStepOneSixtyFourth() {
        let up: Float = 0.5625
        let down: Float = 0.4375
        let fineUp: Float = 0.515625
        let full: Float = 1
        let empty: Float = 0
        // 0.52 sits between two steps: it snaps to the grid and then moves.
        let snappedUp: Float = 0.5625
        #expect(NookMediaKeyRules.stepped(0.5, up: true, fine: false) == up)
        #expect(NookMediaKeyRules.stepped(0.5, up: false, fine: false) == down)
        #expect(NookMediaKeyRules.stepped(0.5, up: true, fine: true) == fineUp)
        #expect(NookMediaKeyRules.stepped(1, up: true, fine: false) == full)
        #expect(NookMediaKeyRules.stepped(0, up: false, fine: false) == empty)
        #expect(NookMediaKeyRules.stepped(0.52, up: true, fine: false) == snappedUp)
    }

    @Test func volumeKeysMoveTheVolumeAndEndMuteAndTheMuteKeyToggles() {
        let up = NookMediaKeyRules.volumeChange(for: .volumeUp, reading: Self.reading(0.5), fine: false)
        #expect(up == NookMediaKeyRules.VolumeChange(volume: 0.5625, isMuted: nil))
        let downWhileMuted = NookMediaKeyRules.volumeChange(for: .volumeDown, reading: Self.reading(0.5, muted: true), fine: false)
        #expect(downWhileMuted == NookMediaKeyRules.VolumeChange(volume: 0.4375, isMuted: false))
        let mute = NookMediaKeyRules.volumeChange(for: .mute, reading: Self.reading(0.5), fine: false)
        #expect(mute == NookMediaKeyRules.VolumeChange(volume: nil, isMuted: true))
        let unmute = NookMediaKeyRules.volumeChange(for: .mute, reading: Self.reading(0.5, muted: true), fine: false)
        #expect(unmute == NookMediaKeyRules.VolumeChange(volume: nil, isMuted: false))
        // No volume to move, and brightness is not a volume key.
        #expect(NookMediaKeyRules.volumeChange(for: .volumeUp, reading: Self.reading(nil), fine: false) == nil)
        #expect(NookMediaKeyRules.volumeChange(for: .brightnessUp, reading: Self.reading(0.5), fine: false) == nil)
    }

    // MARK: Taking the keys

    @MainActor private struct Rig {
        let hardware = FakeAudioHardware(
            devices: [NookMediaSamples.speakers],
            defaultID: NookVolumeTests.device,
            systemID: NookVolumeTests.device
        )
        let brightness = FakeBrightness(value: 0.5)
        let trust: FakeAccessibilityTrust
        let filter = FakeKeyFilter()
        let store = TestDefaults("volume")
        let keys: NookMediaKeys

        init(trusted: Bool) {
            trust = FakeAccessibilityTrust(trusted: trusted)
            hardware.volumes[NookVolumeTests.device] = 0.5
            hardware.mutes[NookVolumeTests.device] = false
            keys = NookMediaKeys(
                hardware: hardware, brightness: brightness, trust: trust, filter: filter, defaults: store.defaults
            )
        }
    }

    private static func press(_ key: NookMediaKey, _ modifiers: NookMediaKeyModifiers = NookMediaKeyModifiers()) -> NookMediaKeyEvent {
        NookMediaKeyEvent(key: key, isDown: true, modifiers: modifiers)
    }

    private static func release(_ key: NookMediaKey) -> NookMediaKeyEvent {
        NookMediaKeyEvent(key: key, isDown: false)
    }

    @Test func theTakeoverIsOffUntilTurnedOnAndLaunchNeverAsksForAnything() {
        let rig = Rig(trusted: false)
        defer { rig.store.remove() }

        rig.keys.start()
        #expect(rig.keys.status == .off)
        #expect(rig.trust.prompts == 0)
        #expect(rig.filter.installs == 0)

        // Switched on in an earlier run, with the grant still missing:
        // launch waits and does not ask.
        rig.store.defaults.set(true, forKey: NookMediaKeys.enabledKey)
        rig.keys.start()
        #expect(rig.keys.status == .waitingForAccess)
        #expect(rig.trust.prompts == 0)
        #expect(rig.filter.installs == 0)
        rig.keys.setEnabled(false)
    }

    @Test func turningItOnAsksForTheGrantOnceAndNeverAgain() {
        let rig = Rig(trusted: false)
        defer { rig.store.remove() }

        rig.keys.setEnabled(true)
        #expect(rig.trust.prompts == 1)
        #expect(rig.keys.status == .waitingForAccess)

        rig.keys.setEnabled(false)
        rig.keys.setEnabled(true)
        rig.keys.setEnabled(false)
        rig.keys.setEnabled(true)
        #expect(rig.trust.prompts == 1)
        rig.keys.setEnabled(false)
        #expect(rig.keys.status == .off)
    }

    @Test func theKeysAreTakenOnceTheGrantArrives() {
        let rig = Rig(trusted: false)
        defer { rig.store.remove() }
        rig.keys.setEnabled(true)

        rig.keys.checkAccess()
        #expect(rig.keys.status == .waitingForAccess)

        rig.trust.trusted = true
        rig.keys.checkAccess()
        #expect(rig.keys.status == .active)
        #expect(rig.filter.installs == 1)
        #expect(rig.trust.prompts == 1)
        rig.keys.setEnabled(false)
        #expect(rig.filter.handler == nil)
    }

    @Test func takingTheGrantAwayLetsGoOfTheKeysAndGivingItBackTakesThemAgain() {
        let rig = Rig(trusted: true)
        defer { rig.store.remove() }
        rig.keys.setEnabled(true)
        #expect(rig.keys.status == .active)

        rig.trust.trusted = false
        rig.keys.checkAccess()
        #expect(rig.keys.status == .waitingForAccess)
        #expect(rig.filter.handler == nil)
        #expect(!rig.keys.handle(Self.press(.volumeUp)))
        // Losing the grant is no reason to ask for it.
        #expect(rig.trust.prompts == 0)

        rig.trust.trusted = true
        rig.keys.checkAccess()
        #expect(rig.keys.status == .active)
        #expect(rig.filter.handler != nil)
        rig.keys.setEnabled(false)
    }

    @Test func withTheGrantAlreadyThereNothingIsAskedAndTheFilterGoesIn() {
        let rig = Rig(trusted: true)
        defer { rig.store.remove() }

        rig.keys.setEnabled(true)

        #expect(rig.trust.prompts == 0)
        #expect(rig.keys.status == .active)
        #expect(rig.keys.isEnabled)
        // Only its own switch was written, and only to its own store.
        #expect(Set(rig.store.ownValues.keys) == [NookMediaKeys.enabledKey])
        rig.keys.setEnabled(false)
    }

    @Test func aFilterMacOSRefusesIsReportedAndTakesNoKeys() {
        let rig = Rig(trusted: true)
        defer { rig.store.remove() }
        rig.filter.refuses = true

        rig.keys.setEnabled(true)

        #expect(rig.keys.status == .unavailable)
        #expect(!rig.keys.handle(Self.press(.volumeUp)))
        rig.keys.setEnabled(false)
    }

    @Test func aVolumeKeyMovesTheVolumeAndIsKeptFromMacOS() {
        let rig = Rig(trusted: true)
        defer { rig.store.remove() }
        rig.keys.setEnabled(true)

        let louder: Float = 0.5625
        #expect(rig.keys.handle(Self.press(.volumeUp)))
        #expect(rig.hardware.volumes[Self.device] == louder)
        // The release of a kept press is kept too.
        #expect(rig.keys.handle(Self.release(.volumeUp)))
        // A release with no kept press before it goes through.
        #expect(!rig.keys.handle(Self.release(.volumeUp)))

        #expect(rig.keys.handle(Self.press(.mute)))
        #expect(rig.hardware.mutes[Self.device] == true)
        #expect(rig.keys.handle(Self.press(.volumeDown)))
        #expect(rig.hardware.mutes[Self.device] == false)
        let back: Float = 0.5
        #expect(rig.hardware.volumes[Self.device] == back)
        rig.keys.setEnabled(false)
    }

    @Test func theFilterHandsItsEventsToTheSameRule() throws {
        let rig = Rig(trusted: true)
        defer { rig.store.remove() }
        rig.keys.setEnabled(true)

        let handler = try #require(rig.filter.handler)
        let louder: Float = 0.5625
        #expect(handler(Self.press(.volumeUp)))
        #expect(rig.hardware.volumes[Self.device] == louder)
        rig.keys.setEnabled(false)
    }

    @Test func keysGoBackToMacOSWhenTheNotchCannotShowThem() {
        let rig = Rig(trusted: true)
        defer { rig.store.remove() }
        rig.keys.setEnabled(true)
        rig.keys.canShowNotice = { false }

        let unchanged: Float = 0.5
        #expect(!rig.keys.handle(Self.press(.volumeUp)))
        #expect(!rig.keys.handle(Self.release(.volumeUp)))
        #expect(!rig.keys.handle(Self.press(.brightnessUp)))
        #expect(rig.hardware.volumes[Self.device] == unchanged)
        #expect(rig.brightness.sets.isEmpty)
        rig.keys.setEnabled(false)
    }

    @Test func optionAndControlLeaveTheKeyWithMacOS() {
        let rig = Rig(trusted: true)
        defer { rig.store.remove() }
        rig.keys.setEnabled(true)

        let unchanged: Float = 0.5
        #expect(!rig.keys.handle(Self.press(.volumeUp, NookMediaKeyModifiers(option: true))))
        #expect(!rig.keys.handle(Self.press(.brightnessUp, NookMediaKeyModifiers(control: true))))
        #expect(rig.hardware.volumes[Self.device] == unchanged)

        // Shift and Option together is the quarter step.
        let fine: Float = 0.515625
        #expect(rig.keys.handle(Self.press(.volumeUp, NookMediaKeyModifiers(shift: true, option: true))))
        #expect(rig.hardware.volumes[Self.device] == fine)
        rig.keys.setEnabled(false)
    }

    @Test func anOutputThatCannotChangeLeavesTheKeyWithMacOS() {
        let rig = Rig(trusted: true)
        defer { rig.store.remove() }
        rig.keys.setEnabled(true)

        // Refuses the change.
        rig.hardware.refusedLevels = [Self.device]
        #expect(!rig.keys.handle(Self.press(.volumeUp)))
        #expect(!rig.keys.handle(Self.press(.mute)))

        // Has no volume of its own.
        rig.hardware.refusedLevels = []
        rig.hardware.volumes[Self.device] = nil
        #expect(!rig.keys.handle(Self.press(.volumeDown)))

        // No output at all.
        rig.hardware.defaultID = nil
        #expect(!rig.keys.handle(Self.press(.mute)))
        rig.keys.setEnabled(false)
    }

    @Test func aBrightnessKeyMovesTheBuiltInDisplayAndReportsTheNewLevel() {
        let rig = Rig(trusted: true)
        defer { rig.store.remove() }
        rig.keys.setEnabled(true)
        var reported: [Float] = []
        rig.keys.onBrightness = { reported.append($0) }

        let brighter: Float = 0.5625
        #expect(rig.keys.handle(Self.press(.brightnessUp)))
        #expect(rig.brightness.sets == [brighter])
        #expect(reported == [brighter])
        #expect(rig.keys.handle(Self.release(.brightnessUp)))

        // No built-in display to move, or one that refuses: macOS keeps the key.
        rig.brightness.refuses = true
        #expect(!rig.keys.handle(Self.press(.brightnessDown)))
        rig.brightness.value = nil
        #expect(!rig.keys.handle(Self.press(.brightnessDown)))
        #expect(reported == [brighter])
        rig.keys.setEnabled(false)
    }

    @Test func turnedOffItTakesNoKeys() {
        let rig = Rig(trusted: true)
        defer { rig.store.remove() }
        rig.keys.setEnabled(true)
        rig.keys.setEnabled(false)

        let unchanged: Float = 0.5
        #expect(rig.filter.removes >= 1)
        #expect(!rig.keys.handle(Self.press(.volumeUp)))
        #expect(rig.hardware.volumes[Self.device] == unchanged)
        #expect(!rig.keys.isEnabled)
    }

    @Test func aKeyThatWaitedTooLongStaysWithMacOS() {
        let rig = Rig(trusted: true)
        defer { rig.store.remove() }
        rig.keys.setEnabled(true)

        // The main thread was busy, macOS gave up waiting and handled the
        // key. Acting on it now would move the volume a second time.
        var late = Self.press(.volumeUp)
        late.isStale = true
        let unchanged: Float = 0.5
        #expect(!rig.keys.handle(late))
        #expect(rig.hardware.volumes[Self.device] == unchanged)
        #expect(!rig.keys.handle(Self.release(.volumeUp)))

        #expect(!NookMediaKeyRules.isStale(eventUptime: 100, nowUptime: 100.1))
        #expect(!NookMediaKeyRules.isStale(eventUptime: 100, nowUptime: 100 + NookMediaKeyRules.staleAfter))
        #expect(NookMediaKeyRules.isStale(eventUptime: 100, nowUptime: 101))
        // No stamp, or a stamp from ahead of the clock: not stale.
        #expect(!NookMediaKeyRules.isStale(eventUptime: 0, nowUptime: 101))
        #expect(!NookMediaKeyRules.isStale(eventUptime: 102, nowUptime: 101))
        rig.keys.setEnabled(false)
    }

    @Test func aFilterMacOSSwitchedOffIsSwitchedBackOnByTheQuietCheck() {
        let rig = Rig(trusted: true)
        defer { rig.store.remove() }
        rig.keys.setEnabled(true)

        rig.keys.checkAccess()
        #expect(rig.filter.revivals == 0)

        rig.filter.isSwitchedOff = true
        rig.keys.checkAccess()
        rig.keys.checkAccess()
        #expect(rig.filter.revivals == 1)
        #expect(rig.keys.status == .active)
        #expect(rig.filter.installs == 1)
        rig.keys.setEnabled(false)
    }

    @Test func onAMutedOutputARefusalNeverComesAfterTheVolumeHasMoved() {
        let rig = Rig(trusted: true)
        defer { rig.store.remove() }
        rig.keys.setEnabled(true)
        let unchanged: Float = 0.5

        // Mute can be read and not set: macOS gets the key, and the volume
        // has not been touched.
        rig.hardware.mutes[Self.device] = true
        rig.hardware.refusedMutes = [Self.device]
        #expect(!rig.keys.handle(Self.press(.volumeUp)))
        #expect(rig.hardware.volumes[Self.device] == unchanged)
        #expect(rig.hardware.mutes[Self.device] == true)
        #expect(!rig.keys.handle(Self.release(.volumeUp)))

        // The volume refuses: the output is unmuted, the volume still has
        // not moved, and macOS makes the one step.
        rig.hardware.refusedMutes = []
        rig.hardware.refusedVolumes = [Self.device]
        #expect(!rig.keys.handle(Self.press(.volumeUp)))
        #expect(rig.hardware.volumes[Self.device] == unchanged)
        #expect(rig.hardware.mutes[Self.device] == false)
        rig.keys.setEnabled(false)
    }

    // MARK: The notice

    @MainActor private struct NoticeRig {
        let hardware = FakeAudioHardware(
            devices: [NookMediaSamples.speakers, NookMediaSamples.airPods],
            defaultID: NookVolumeTests.device,
            systemID: NookVolumeTests.device
        )
        let store = TestDefaults("volume-notice")
        let clock = ManualClock(NookMediaSamples.start)
        let trust = FakeAccessibilityTrust(trusted: true)
        let nook: NookModel
        let monitor: NookVolumeMonitor

        init() {
            hardware.volumes[NookVolumeTests.device] = 0.5
            hardware.mutes[NookVolumeTests.device] = false
            hardware.volumes[NookMediaSamples.airPods.id] = 0.2
            hardware.mutes[NookMediaSamples.airPods.id] = false
            let keys = NookMediaKeys(
                hardware: hardware,
                brightness: FakeBrightness(value: 0.5),
                trust: trust,
                filter: FakeKeyFilter(),
                defaults: store.defaults
            )
            nook = NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
            // A bare model lights nothing; this keeps it that way.
            nook.presentRingLight = { _ in }
            let clock = clock
            monitor = NookVolumeMonitor(hardware: hardware, keys: keys, defaults: store.defaults, now: { clock.now })
            monitor.start(nook: nook)
        }
    }

    @Test func aVolumeChangeFromAnywhereShowsInTheClosedNotch() {
        let rig = NoticeRig()
        defer { rig.store.remove() }
        #expect(rig.nook.transient == nil)

        // Not from the keys: the menu bar slider, say.
        rig.hardware.volumes[Self.device] = 0.75
        rig.hardware.emit(.level)

        #expect(rig.nook.transient == NookTransientActivity(symbol: "speaker.wave.3.fill", text: "75%"))

        rig.hardware.mutes[Self.device] = true
        rig.hardware.emit(.level)
        #expect(rig.nook.transient?.symbol == "speaker.slash.fill")
        #expect(rig.nook.transient?.text == LanguageManager.shared.t("nook.volume.muted"))
    }

    @Test func launchAndAnotherOutputTakingOverAnnounceNothing() {
        let rig = NoticeRig()
        defer { rig.store.remove() }

        // The same level reported again.
        rig.hardware.emit(.level)
        #expect(rig.nook.transient == nil)

        // The AirPods connect at their own volume.
        rig.hardware.defaultID = NookMediaSamples.airPods.id
        rig.hardware.emit(.defaultOutput)
        rig.hardware.emit(.level)
        #expect(rig.nook.transient == nil)

        // The new output settling its own volume right after is not news either.
        rig.clock.advance(0.5)
        rig.hardware.volumes[NookMediaSamples.airPods.id] = 0.4
        rig.hardware.emit(.level)
        #expect(rig.nook.transient == nil)

        // A change once it has settled does show.
        rig.clock.advance(NookVolumeMonitor.settleSeconds)
        rig.hardware.volumes[NookMediaSamples.airPods.id] = 0.3
        rig.hardware.emit(.level)
        #expect(rig.nook.transient?.text == "30%")
    }

    @Test func theNoticeCanBeSwitchedOffUnlessTheKeysAreTakenOver() {
        let rig = NoticeRig()
        defer { rig.store.remove() }
        rig.store.defaults.set(false, forKey: NookVolumeMonitor.noticeKey)

        rig.hardware.volumes[Self.device] = 0.25
        rig.hardware.emit(.level)
        #expect(rig.nook.transient == nil)

        // With Apple's popup gone, the notice is the only sign of a change.
        rig.monitor.keys.setEnabled(true)
        #expect(rig.monitor.keys.status == .active)
        rig.hardware.volumes[Self.device] = 0.75
        rig.hardware.emit(.level)
        #expect(rig.nook.transient?.text == "75%")
        rig.monitor.keys.setEnabled(false)
    }

    @Test func aHeldKeyPopsTheIslandOnceAndThenChangesTheTextInPlace() {
        let rig = NoticeRig()
        defer { rig.store.remove() }
        var pops = 0
        rig.nook.onTransient = { pops += 1 }

        for step in 1...4 {
            rig.hardware.volumes[Self.device] = 0.5 + Float(step) * 0.0625
            rig.hardware.emit(.level)
            rig.clock.advance(0.1)
        }
        #expect(pops == 1)
        #expect(rig.nook.transient?.text == "75%")

        // A new press after the notice has gone pops again.
        rig.clock.advance(NookVolumeMonitor.noticeSeconds + 1)
        rig.hardware.volumes[Self.device] = 0.25
        rig.hardware.emit(.level)
        #expect(pops == 2)
    }

    @Test func aBrightnessKeyShowsTheBrightnessInTheClosedNotch() {
        let rig = NoticeRig()
        defer { rig.store.remove() }
        rig.monitor.keys.setEnabled(true)

        #expect(rig.monitor.keys.handle(NookMediaKeyEvent(key: .brightnessUp, isDown: true)))
        #expect(rig.nook.transient == NookTransientActivity(symbol: "sun.max.fill", text: "56%"))
        rig.monitor.keys.setEnabled(false)
    }

    @Test func theSettingsTestButtonShowsASampleNotice() {
        let rig = NoticeRig()
        defer { rig.store.remove() }

        rig.monitor.showSample()

        #expect(rig.nook.transient == NookTransientActivity(symbol: "speaker.wave.2.fill", text: "62%"))
    }

    @Test func aKeptKeyThatChangesNothingStillShowsTheLevel() {
        let rig = NoticeRig()
        defer { rig.store.remove() }
        rig.monitor.keys.setEnabled(true)
        var pops = 0
        rig.nook.onTransient = { pops += 1 }

        // The volume is taken to the top from somewhere else.
        rig.hardware.volumes[Self.device] = 1
        rig.hardware.emit(.level)
        #expect(pops == 1)
        rig.clock.advance(NookVolumeMonitor.noticeSeconds + 1)

        // Volume up at the top: kept, nothing moves, and with Apple's popup
        // gone the level still shows.
        let top: Float = 1
        #expect(rig.monitor.keys.handle(NookMediaKeyEvent(key: .volumeUp, isDown: true)))
        #expect(rig.hardware.volumes[Self.device] == top)
        #expect(pops == 2)
        #expect(rig.nook.transient == NookTransientActivity(symbol: "speaker.wave.3.fill", text: "100%"))

        // A press that does move the level is announced by the key too.
        rig.clock.advance(NookVolumeMonitor.noticeSeconds + 1)
        #expect(rig.monitor.keys.handle(NookMediaKeyEvent(key: .volumeDown, isDown: true)))
        #expect(pops == 3)
        #expect(rig.nook.transient?.text == "94%")

        // The mute key the same way.
        rig.clock.advance(NookVolumeMonitor.noticeSeconds + 1)
        #expect(rig.monitor.keys.handle(NookMediaKeyEvent(key: .mute, isDown: true)))
        #expect(pops == 4)
        #expect(rig.nook.transient?.symbol == "speaker.slash.fill")
        rig.monitor.keys.setEnabled(false)
    }

    @Test func aKeptKeyRightAfterAnOutputSwitchStillShows() {
        let rig = NoticeRig()
        defer { rig.store.remove() }
        rig.monitor.keys.setEnabled(true)

        // The AirPods connect, and half a second later a volume key is pressed.
        rig.hardware.defaultID = NookMediaSamples.airPods.id
        rig.hardware.emit(.defaultOutput)
        rig.clock.advance(0.5)
        #expect(rig.nook.transient == nil)

        #expect(rig.monitor.keys.handle(NookMediaKeyEvent(key: .volumeDown, isDown: true)))
        #expect(rig.nook.transient?.text == "13%")

        // The output settling by itself in the same two seconds stays quiet.
        rig.clock.advance(0.5)
        rig.hardware.volumes[NookMediaSamples.airPods.id] = 0.4
        rig.hardware.emit(.level)
        #expect(rig.nook.transient?.text == "13%")
        rig.monitor.keys.setEnabled(false)
    }

    @Test func theNoticeForTheLevelAsItStandsReadsTheSameAsOneForAChange() {
        let level = NookVolumeReading(deviceID: Self.device, volume: 1, isMuted: false)
        #expect(NookVolumeNotice.content(for: level)
            == NookVolumeNoticeContent(symbol: "speaker.wave.3.fill", percent: 100, isMuted: false))

        let muted = NookVolumeReading(deviceID: Self.device, volume: 0.5, isMuted: true)
        #expect(NookVolumeNotice.content(for: muted)
            == NookVolumeNoticeContent(symbol: "speaker.slash.fill", percent: nil, isMuted: true))

        let noVolume = NookVolumeReading(deviceID: Self.device, volume: nil, isMuted: false)
        #expect(NookVolumeNotice.content(for: noVolume).percent == nil)
    }
}
