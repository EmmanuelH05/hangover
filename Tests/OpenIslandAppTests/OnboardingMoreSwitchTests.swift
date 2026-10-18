import AppKit
import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

// The switches on the long tour's Good to know pages. Each row shows the
// model's state, a flip writes what the switch in Settings writes, and leaving
// the tour keeps what was flipped. Nothing here asks macOS for a permission,
// registers a login item, touches the updater or the Dock, opens System
// Settings, or writes the real settings: every service is a fake and every
// store is in memory.

@MainActor
private final class FakeLoginItem: LaunchAtLoginControlling {
    var isEnabled = false
    private(set) var calls: [Bool] = []
    func setEnabled(_ enabled: Bool) throws {
        calls.append(enabled)
        isEnabled = enabled
    }
}

@MainActor
private final class Recorder {
    var dock: [Bool] = []
    var opened: [URL] = []
}

/// An app model on stores of its own, with the login item, the Dock, the
/// Accessibility grant, the key filter and System Settings all fakes.
@MainActor
private struct MoreRig {
    let defaults = MemoryDefaults()
    let login = FakeLoginItem()
    let recorder = Recorder()
    let trust = FakeAccessibilityTrust(trusted: false)
    let filter = FakeKeyFilter()
    let model: AppModel

    init(defaults: MemoryDefaults? = nil) {
        let store = defaults ?? self.defaults
        let hardware = FakeAudioHardware(devices: [NookMediaSamples.speakers], defaultID: 95, systemID: 95)
        let keys = NookMediaKeys(
            hardware: hardware, brightness: FakeBrightness(value: 0.5), trust: trust, filter: filter, defaults: store
        )
        let volume = NookVolumeMonitor(hardware: hardware, keys: keys, defaults: store)
        let nook = NookModel(volume: volume, defaults: store, looksForImportedGIF: false)
        model = AppModel(agentsDefaults: MemoryDefaults(), defaults: store, nookModel: nook)
        nook.activeProfile = { [weak model] in model?.activeAppearanceProfile ?? .topBar }
        model.launchAtLogin = login
        let recorder = recorder
        model.applyDockIcon = { recorder.dock.append($0) }
        model.openSystemURL = { recorder.opened.append($0) }
    }

    var reading: OnboardingMoreReading { model.onboardingState.more }

    /// A second app model on the same store, which is what a later launch reads.
    func relaunched() -> AppModel {
        let rig = MoreRig(defaults: defaults)
        return rig.model
    }
}

// MARK: - The switches

@MainActor
struct OnboardingMoreSwitchTests {
    @Test func everyGoodToKnowPageHasItsSwitchesInTheOrderSettingsListsThem() {
        #expect(OnboardingMore.power.switches == [.powerNotices])
        #expect(OnboardingMore.volume.switches == [.volumeNotice, .volumeKeys])
        #expect(OnboardingMore.usage.switches == [.usageMeter])
        #expect(OnboardingMore.quiet.switches == [.focusQuiet, .meetingQuiet])
        #expect(OnboardingMore.sounds.switches == [.mute])
        #expect(OnboardingMore.links.switches == [.links])
        #expect(OnboardingMore.startup.switches == [.launchAtLogin, .dockIcon])
        #expect(OnboardingMore.updates.switches == [.autoUpdates])
        // The lights have the beat switch of the glow page, and the phone relay
        // and the screen are setup, not a switch.
        for more: OnboardingMore in [.lights, .phone, .screens, .accent] { #expect(more.switches.isEmpty) }
        #expect(OnboardingMore.phone.settingsTab == .watch)
        #expect(OnboardingMore.screens.settingsTab == .general)
        #expect(OnboardingMore.usage.opensSettings)
        #expect(OnboardingMoreSwitch.allCases.count == 13)
        // The mirror, its photo booth and the weather carry the widget's switch.
        #expect(OnboardingMore.mirror.switches == [.mirrorWidget])
        #expect(OnboardingMore.booth.switches == [.mirrorWidget])
        #expect(OnboardingMore.weather.switches == [.weatherWidget])
        #expect(OnboardingMore.accent.switches.isEmpty && OnboardingMore.accent.settingsTab == .appearance)
    }

    /// A fresh app: each row reads what the app starts with.
    @Test(arguments: OnboardingMoreSwitch.allCases)
    func aRowShowsWhatTheModelSaysBeforeAnyFlip(item: OnboardingMoreSwitch) {
        let rig = MoreRig()
        #expect(rig.reading.isOn(item) == item.startsOn, "\(item)")
    }

    /// A flip changes the model, the row reads the change back, and a second
    /// launch on the same store finds it saved: the same write Settings makes.
    @Test(arguments: OnboardingMoreSwitch.allCases.filter { $0 != .autoUpdates && $0 != .volumeKeys })
    func aFlipWritesWhatSettingsWritesAndTheRowReadsItBack(item: OnboardingMoreSwitch) {
        let rig = MoreRig()
        let target = !item.startsOn

        rig.model.setTourMore(item, enabled: target)

        #expect(rig.reading.isOn(item) == target, "\(item)")
        let later = rig.relaunched()
        switch item {
        case .powerNotices: #expect(rig.defaults.object(forKey: NookPowerMonitor.enabledKey) as? Bool == target)
        case .volumeNotice: #expect(rig.defaults.object(forKey: NookVolumeMonitor.noticeKey) as? Bool == target)
        case .usageMeter: #expect((later.islandUsageDisplay == .compact) == target)
        case .focusQuiet: #expect(later.nook.focusSuppressesCompletions == target)
        case .meetingQuiet: #expect(later.nook.meetingSuppressesCompletions == target)
        case .mute: #expect(later.isSoundMuted == target)
        case .links: #expect(later.allowsLinksFromOtherApps == target)
        case .launchAtLogin:
            #expect(rig.login.calls == [target], "the login item was asked once, through the fake")
        case .dockIcon:
            #expect(rig.recorder.dock == [target], "the Dock was told once, through the recorder")
            #expect(later.showDockIcon == target)
        case .mirrorWidget: #expect(later.nook.isWidgetEnabled(.mirror) == target)
        case .weatherWidget: #expect(later.nook.isWidgetEnabled(.weather) == target)
        case .volumeKeys, .autoUpdates: break
        }

        rig.model.setTourMore(item, enabled: item.startsOn)
        #expect(rig.reading.isOn(item) == item.startsOn, "off again means off, on again means on")
    }

    /// The updater runs only in the downloaded app. Settings dims its switch
    /// where it does not, and the tour does the same: the flip changes nothing.
    @Test func theUpdatesSwitchIsDimmedAndDoesNothingWhereTheUpdaterDoesNotRun() {
        let rig = MoreRig()
        #expect(!rig.reading.canCheckForUpdates)
        #expect(!rig.reading.isEnabled(.autoUpdates))
        #expect(rig.reading.isEnabled(.mute))

        let before = rig.model.updateChecker.installsAutomatically
        rig.model.setTourMore(.autoUpdates, enabled: !before)

        #expect(rig.model.updateChecker.installsAutomatically == before, "the flip changes nothing")
        #expect(!rig.reading.isOn(.autoUpdates))
    }

    /// The switch's name is the name Settings gives its own, and every switch
    /// has its line in every language.
    @Test(arguments: HangoverBrandTests.languages)
    func everySwitchHasItsNameAndItsLineInEveryLanguage(language: String) throws {
        let table = try HangoverBrandTests.table(language)
        for item in OnboardingMoreSwitch.allCases {
            #expect(!(table[item.titleKey] ?? "").isEmpty, "\(language) \(item.titleKey)")
            #expect(!(table[item.lineKey] ?? "").isEmpty, "\(language) \(item.lineKey)")
            #expect(!(table["onboarding.more.\(item.more.rawValue).title"] ?? "").isEmpty)
            #expect(!(table["onboarding.done.recap.more.\(item.rawValue)"] ?? "").isEmpty)
        }
        #expect(!(table["onboarding.done.recap.goodToKnow"] ?? "").isEmpty)
    }

    /// Only the keys make macOS ask, the line says what before the flip, and
    /// no page says the tour does not ask.
    @Test(arguments: HangoverBrandTests.languages)
    func theKeysSwitchSaysWhatMacOSAsksBeforeTheFlipAndNoPageSaysTheTourDoesNotAsk(language: String) throws {
        let table = try HangoverBrandTests.table(language)
        #expect(OnboardingMoreSwitch.allCases.filter(\.asksMacOS) == [.volumeKeys])
        let line = try #require(table[OnboardingMoreSwitch.volumeKeys.lineKey])
        let waiting = try #require(table["nook.volume.settings.keys.waiting"])
        #expect(line.contains(language == "en" ? "Accessibility" : (language == "zh-Hans" ? "辅助功能" : "輔助使用")))
        #expect(!waiting.isEmpty)
        let note = try #require(table["onboarding.more.volume.note"])
        for gone in ["does not ask", "不会询问，", "這次導覽不會詢問", "这次导览不会询问"] {
            #expect(!note.contains(gone), "\(language): \(note)")
        }
        let english = try HangoverBrandTests.table("en")
        for (key, value) in english where key.hasPrefix("onboarding.more.") {
            #expect(!value.contains("this tour does not ask"), "\(key)")
        }
    }

    // MARK: Volume keys

    /// Flipping the keys on is what raises the request, once. Without the grant
    /// the row shows Settings' "waiting" state, and the grant moves it on.
    @Test func flippingTheKeysOnAsksOnceAndShowsWaitingUntilMacOSSaysYes() {
        let rig = MoreRig()
        #expect(rig.trust.prompts == 0, "reading the page asks for nothing")
        #expect(rig.reading.keys == .off)

        rig.model.setTourMore(.volumeKeys, enabled: true)

        #expect(rig.trust.prompts == 1)
        #expect(rig.reading.keys == .waiting)
        #expect(rig.reading.isOn(.volumeKeys))
        #expect(rig.defaults.object(forKey: NookMediaKeys.enabledKey) as? Bool == true, "the key Settings writes")

        rig.trust.trusted = true
        rig.model.nook.volume.keys.checkAccess()
        #expect(rig.reading.keys == .active)
        #expect(rig.filter.installs == 1)

        rig.model.setTourMore(.volumeKeys, enabled: false)
        #expect(rig.reading.keys == .off)
        #expect(!rig.reading.isOn(.volumeKeys))
        #expect(rig.trust.prompts == 1, "turning it off asks nothing")
    }

    @Test func theButtonBesideWaitingAsksAgainAndOpensTheAccessibilityList() {
        let rig = MoreRig()
        rig.model.setTourMore(.volumeKeys, enabled: true)
        #expect(rig.trust.prompts == 1)

        rig.model.requestTourKeysAccess()

        #expect(rig.trust.prompts == 2, "it asks each time it is pressed, like Settings' button")
        #expect(rig.recorder.opened.map(\.absoluteString) == [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ])
        rig.model.setTourMore(.volumeKeys, enabled: false)
    }

    @Test func aRefusedFilterShowsTheUnavailableState() {
        let rig = MoreRig()
        rig.trust.trusted = true
        rig.filter.refuses = true
        rig.model.setTourMore(.volumeKeys, enabled: true)
        #expect(rig.reading.keys == .unavailable)
        rig.model.setTourMore(.volumeKeys, enabled: false)
    }

    // MARK: Leaving the tour

    /// A switch the user flipped stays as flipped through Next, Back, Skip and
    /// the end of the tour, and the tour flips nothing by itself.
    @Test func whatTheUserFlippedStaysFlippedWhenTheTourLeavesAndNothingIsFlippedByTheTour() {
        let rig = MoreRig()
        final class Closed { var count = 0 }
        let closed = Closed()
        let tour = rig.model.makeWelcomeTour(close: { closed.count += 1 })
        tour.answerQuestion(.long)
        tour.go(to: .power)
        #expect(tour.page == .power, "the walk starts on a Good to know page")
        let before = rig.reading

        tour.next()
        tour.back()
        #expect(rig.reading == before, "walking the pages flips nothing")
        #expect(rig.login.calls.isEmpty && rig.recorder.dock.isEmpty && rig.trust.prompts == 0)

        tour.actions.setMore(.powerNotices, false)
        tour.actions.setMore(.mute, true)
        tour.actions.setMore(.dockIcon, false)
        tour.next()
        tour.back()
        tour.skip()

        #expect(closed.count == 1)
        #expect(!rig.reading.isOn(.powerNotices) && rig.reading.isOn(.mute) && !rig.reading.isOn(.dockIcon))
        let later = rig.relaunched()
        #expect(later.isSoundMuted && !later.showDockIcon)
        #expect(rig.defaults.object(forKey: NookPowerMonitor.enabledKey) as? Bool == false)
    }

    /// The summary lists what was turned on here, by short name, in the
    /// order of the pages, in one row, and nothing when there is nothing.
    @Test func theSummaryHasOneRowForWhatWasSwitchedOnHere() {
        let rig = MoreRig()
        let tour = rig.model.makeWelcomeTour(startingAt: .power)
        #expect(tour.state.moreSwitchedOn.isEmpty)
        #expect(!OnboardingRecapRow.shown(agentsEnabled: true, hasMoreSwitches: false).contains(.goodToKnow))

        tour.actions.setMore(.mute, true)
        tour.actions.setMore(.launchAtLogin, true)
        tour.actions.setMore(.powerNotices, false)

        #expect(tour.state.moreSwitchedOn == [.mute, .launchAtLogin])
        let rows = OnboardingRecapRow.shown(agentsEnabled: true, hasMoreSwitches: true)
        #expect(rows.filter { $0 == .goodToKnow }.count == 1)
        #expect(rows.last == .goodToKnow)
        #expect(!OnboardingRecapRow.goodToKnow.isInShortTour)
    }

    /// Switched off again, or no longer on, a switch leaves the summary.
    @Test func aSwitchTurnedOffAgainOrChangedFromOutsideLeavesTheSummary() {
        let rig = MoreRig()
        let tour = rig.model.makeWelcomeTour(startingAt: .sounds)
        tour.actions.setMore(.mute, true)
        #expect(tour.state.moreSwitchedOn == [.mute])
        tour.actions.setMore(.mute, false)
        #expect(tour.state.moreSwitchedOn.isEmpty)

        tour.actions.setMore(.links, true)
        rig.model.allowsLinksFromOtherApps = false
        #expect(tour.state.moreSwitchedOn.isEmpty, "the summary reads what is on, not what was clicked")
    }

    // MARK: The agent pages

    @Test func theAgentSwitchesLeaveWithTheAgentsAndTheirPagesStayOutOfAnAgentsOffTour() {
        for item in [OnboardingMoreSwitch.usageMeter, .focusQuiet, .meetingQuiet] { #expect(item.needsAgents) }
        for item in [OnboardingMoreSwitch.powerNotices, .volumeNotice, .volumeKeys, .mute, .links, .launchAtLogin, .dockIcon, .autoUpdates] {
            #expect(!item.needsAgents)
        }
        let rig = MoreRig()
        let tour = rig.model.makeWelcomeTour(startingAt: .quiet)
        tour.actions.setMore(.focusQuiet, false)
        tour.actions.setMore(.mute, true)
        #expect(tour.state.moreSwitchedOn == [.mute] || tour.state.agentsEnabled == false)
        var state = OnboardingState()
        state.agentsEnabled = false
        let pages = OnboardingTour.pages(for: { var s = state; s.length = .long; return s }())
        for page in [OnboardingPage.usage, .quiet, .phone] { #expect(!pages.contains(page)) }
        for page in [OnboardingPage.power, .volume, .sounds, .links, .startup, .updates] { #expect(pages.contains(page)) }
    }

    /// A layout carries a usage setting of its own. The pick made in the tour
    /// comes back after one, the way a glow style does.
    @Test func aLayoutPickedAfterTheUsageSwitchDoesNotTakeThePickBack() throws {
        let rig = MoreRig()
        let tour = rig.model.makeWelcomeTour(startingAt: .usage)
        let template = try #require(PersonalizationTemplate.all.first { $0.appearance.usageDisplay == .compact })
        tour.actions.setMore(.usageMeter, false)
        #expect(rig.model.islandUsageDisplay == .hidden)

        tour.actions.applyTemplate(template)

        #expect(rig.model.islandUsageDisplay == .hidden, "the user's pick, laid back over the layout")
    }

    // MARK: The code the switches write through is Settings' own

    @Test func theSettingsViewsWriteTheSameKeysAndProperties() throws {
        let power = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Nook/Widgets/Power/NookPowerSettings.swift")
        #expect(power.contains("@AppStorage(NookPowerMonitor.enabledKey)"))
        let volume = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Nook/Widgets/Volume/NookVolumeSettings.swift")
        #expect(volume.contains("@AppStorage(NookVolumeMonitor.noticeKey)"))
        #expect(volume.contains("set: { keys.setEnabled($0) }"))
        let pane = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Nook/Views/NookSettingsPane.swift")
        #expect(pane.contains("$nook.focusSuppressesCompletions") && pane.contains("$nook.meetingSuppressesCompletions"))
        let settings = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Views/SettingsView.swift")
        for line in [
            "set: { model.launchAtLoginEnabled = $0 }", "set: { model.showDockIcon = $0 }",
            "set: { model.allowsLinksFromOtherApps = $0 }", "set: { model.updateChecker.installsAutomatically = $0 }",
        ] {
            #expect(settings.contains(line), "\(line)")
        }
        let tour = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/AppModel+Onboarding.swift")
        for line in [
            "nook.power.setEnabled(enabled)", "nook.volume.setNoticeEnabled(enabled)", "nook.volume.keys.setEnabled(enabled)",
            "islandUsageDisplay = enabled ? .compact : .hidden", "isSoundMuted = enabled",
            "allowsLinksFromOtherApps = enabled", "launchAtLoginEnabled = enabled", "showDockIcon = enabled",
            "updateChecker.installsAutomatically = enabled",
        ] {
            #expect(tour.contains(line), "\(line)")
        }
    }

    @Test func theSetupPagesButtonsOpenTheirTabOfSettingsThroughOneDoor() {
        var opened: [SettingsTab] = []
        var actions = OnboardingActions()
        actions.openSettings = { opened.append($0) }
        let tour = OnboardingTour(startingAt: .phone, state: { OnboardingState() }, actions: actions)
        for page in [OnboardingPage.phone, .screens] {
            if let tab = page.more?.settingsTab { tour.actions.openSettings(tab) }
        }
        #expect(opened == [.watch, .general])
        #expect(SettingsTab(rawValue: "watch") == .watch)
    }
}

// MARK: - The pages drawn

@MainActor
struct OnboardingMoreSwitchRenderTests {
    private static let scale: CGFloat = 2

    private func png(_ name: String, _ page: OnboardingPage, _ state: OnboardingState) throws -> Data {
        let size = OnboardingStyle.windowSize
        let view = OnboardingView(tour: OnboardingTour(startingAt: page, state: { state }), lang: LanguageManager.shared)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view.environment(\.nookDrawsStill, true))
        renderer.scale = Self.scale
        let image = try #require(renderer.cgImage)
        #expect(image.width == Int(size.width * Self.scale))
        let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        if ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_SNAPSHOTS"] == "1" {
            let directory = HangoverBrandTests.repoRoot.appendingPathComponent("output/render/onboarding", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return data
    }

    private static func state(_ change: (inout OnboardingState) -> Void = { _ in }) -> OnboardingState {
        var state = OnboardingState()
        state.length = .long
        state.agentsEnabled = true
        change(&state)
        return state
    }

    @Test func everyPageDrawsAndTheSwitchStateChangesThePicture() throws {
        for more in OnboardingMore.allCases {
            let page = more.page
            let plain = try png("32-more-\(more.rawValue)", page, Self.state())
            guard let item = more.switches.first else { continue }
            let flipped = try png("32-more-\(more.rawValue)-flipped", page, Self.state {
                if item.startsOn { $0.more.on.remove(item) } else { $0.more.on.insert(item) }
                $0.more.canCheckForUpdates = true
            })
            #expect(plain != flipped, "\(more) draws its switch")
        }
    }

    @Test func theVolumePageDrawsTheWaitingStateAndTheUnavailableOne() throws {
        let idle = try png("32-more-volume-idle", .volume, Self.state())
        let waiting = try png("32-more-volume-waiting", .volume, Self.state {
            $0.more.on.insert(.volumeKeys)
            $0.more.keys = .waiting
        })
        let unavailable = try png("32-more-volume-unavailable", .volume, Self.state {
            $0.more.on.insert(.volumeKeys)
            $0.more.keys = .unavailable
        })
        #expect(Set([idle, waiting, unavailable]).count == 3)
    }

    @Test func theLightsPageShowsTheBeatSwitchInItsStates() throws {
        let off = try png("32-more-lights-off", .lights, Self.state())
        let on = try png("32-more-lights-on", .lights, Self.state { $0.beat.isOn = true })
        let held = try png("32-more-lights-held", .lights, Self.state {
            $0.beat.isOn = true
            $0.beat.canRunNow = false
        })
        #expect(Set([off, on, held]).count == 3)
    }

    @Test func theSummaryDrawsTheGoodToKnowRow() throws {
        let without = try png("33-done-no-more", .done, Self.state())
        let with = try png("33-done-more", .done, Self.state {
            $0.more.on.formUnion([.mute, .launchAtLogin])
            $0.moreSwitchedOn = [.mute, .launchAtLogin]
        })
        #expect(without != with)
    }
}
