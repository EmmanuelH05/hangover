import Foundation

// The pages only the long tour walks. Each is a feature of the app that no
// page of the main tour teaches: its own page says what the feature does
// and where it is turned on, in two short lines. Each is tied to the code
// that does it: `proofs` names a file and a piece of its text, and
// `OnboardingMoreTests` fails when that text is renamed or removed. A claim
// without a proof is not added. A feature that is a plain setting has its
// switch on its page (`OnboardingMoreSwitch`), which writes what the switch in
// Settings writes and says before the flip what macOS will ask. A feature that
// needs setup has a button that opens its tab of Settings.

/// One feature of the long tour, as one page. The string keys are
/// `onboarding.more.<case>.title`, `.text`, `.where` and, for a feature
/// with something to know first, `.note`.
enum OnboardingMore: String, CaseIterable, Identifiable, Sendable {
    /// The Mirror widget, which starts off: the camera on the island, frames,
    /// stickers and a ring light. A card only tells, and its switch is the widget's.
    case mirror
    /// The photo booth in the mirror: four shots, a strip, where it is saved.
    case booth
    /// The Weather widget, which starts off.
    case weather
    /// The Record widget, which starts off: the screen, a window or an area,
    /// with a face cam bubble, saved in Movies and dropped in the tray. The
    /// page only tells. Nothing on it starts a recording.
    case record
    /// Converting a file in the tray: pictures, video and PDF. The tray
    /// starts on, and the page tells how a file's Convert menu works.
    case convert
    /// The lights that follow the beat, in depth: the Lasers and their reach.
    case lights
    /// The accent color of the app's selections and switches.
    case accent
    /// The charger and the headphones notices on the closed island.
    case power
    /// The volume level on the closed island, and the keys.
    case volume
    /// The Claude usage meter on the open island. Agents only.
    case usage
    /// Completion pop-ups that are not shown during a focus session or a
    /// meeting. Agents only.
    case quiet
    /// The iPhone and Apple Watch relay. Agents only.
    case phone
    case screens
    case sounds
    case links
    case startup
    case updates

    var id: String { rawValue }

    /// The page of the tour that tells it.
    var page: OnboardingPage {
        OnboardingPage.allCases.first { $0.more == self } ?? .done
    }

    /// True for a feature of the agent half, which the agents switch hides
    /// along with its page (D41).
    var needsAgents: Bool {
        switch self {
        case .usage, .quiet, .phone: true
        case .mirror, .booth, .weather, .record, .convert, .lights, .accent, .power, .volume, .screens, .sounds, .links, .startup,
             .updates: false
        }
    }

    var titleKey: String { "onboarding.more.\(rawValue).title" }
    var textKey: String { "onboarding.more.\(rawValue).text" }
    var whereKey: String { "onboarding.more.\(rawValue).where" }
    var noteKey: String { "onboarding.more.\(rawValue).note" }

    /// True for a feature whose page carries a line to read first: what
    /// macOS asks for, or what the feature leaves open.
    var hasNote: Bool {
        switch self {
        case .mirror, .weather, .record, .lights, .volume, .usage, .phone, .links: true
        case .booth, .convert, .accent, .power, .quiet, .screens, .sounds, .startup, .updates: false
        }
    }

    /// True for the page whose button opens Settings on the Setup tab through
    /// `OnboardingActions.showAllAgents`, the door the agents page has: the
    /// Claude usage bridge is installed there.
    var opensSettings: Bool { self == .usage }

    /// The tab of Settings the button of a feature that needs setup opens: the
    /// phone relay is paired on the Watch tab, the screen is picked on General.
    var settingsTab: SettingsTab? {
        switch self {
        case .phone: .watch
        case .screens: .general
        case .accent: .appearance
        default: nil
        }
    }

    /// The switches on the page, which the page reads from the app.
    var switches: [OnboardingMoreSwitch] { OnboardingMoreSwitch.switches(for: self) }

    /// True for a page with controls, which draws a smaller picture.
    var hasControls: Bool {
        self == .lights || !switches.isEmpty || settingsTab != nil || opensSettings
    }

    var symbol: String {
        switch self {
        case .mirror: "camera.viewfinder"
        case .booth: "camera.aperture"
        case .weather: "cloud.sun.fill"
        case .record: "record.circle"
        case .convert: "arrow.triangle.2.circlepath"
        case .accent: "paintpalette.fill"
        case .lights: "sparkles"
        case .power: "bolt.fill"
        case .volume: "speaker.wave.2.fill"
        case .usage: "chart.bar.fill"
        case .quiet: "bell.slash.fill"
        case .phone: "applewatch"
        case .screens: "display.2"
        case .sounds: "speaker.slash.fill"
        case .links: "link"
        case .startup: "power"
        case .updates: "arrow.down.circle.fill"
        }
    }

    /// The code that does what the page says.
    var proofs: [OnboardingProof] {
        switch self {
        // The widget pages stand on the code of the lines the features page
        // tells about the same widget, which `OnboardingShowcaseProofTests` holds.
        case .mirror: OnboardingAbility.mirrorOn.proofs + OnboardingAbility.mirrorRing.proofs
            + OnboardingAbility.mirrorFrames.proofs + [
                .widget("Mirror/NookMirrorCard.swift", "(for: .video) { @Sendable _ in"),
                .widget("Mirror/NookMirrorSettings.swift", "Section(\"Mirror\")"),
            ]
        case .booth: OnboardingAbility.mirrorBooth.proofs + OnboardingAbility.mirrorLooks.proofs
            + OnboardingAbility.mirrorSaved.proofs + OnboardingAbility.mirrorStrip.proofs + [
                .widget("Mirror/PhotoBooth/NookPhotoBoothSettings.swift", "nook.photoBooth.settings.section"),
            ]
        case .weather: OnboardingAbility.weatherForecast.proofs + OnboardingAbility.weatherCity.proofs
            + OnboardingAbility.weatherSource.proofs + [
                .widget("Weather/NookWeatherSettings.swift", "Section(lang.t(\"nook.weather.title\"))"),
            ]
        // Record stands on the code of the lines the features page tells, and
        // on what the note says macOS asks: a screen or an area asks for Screen
        // Recording, a picked window does not, and the voice asks for the
        // microphone.
        case .record: OnboardingAbility.recordTargets.proofs + OnboardingAbility.recordFaceCam.proofs
            + OnboardingAbility.recordSound.proofs + OnboardingAbility.recordSaved.proofs + [
                .widget("Record/NookRecordSettings.swift", "Section(lang.t(\"nook.record.settings.section\"))"),
                .widget("Record/NookScreenRecorder.swift", "if target != .pickedWindow { try requireScreenAccess() }"),
                .widget(
                    "Record/NookScreenRecorder.swift",
                    "if !allowed { throw NookRecordFailure.micPermissionDenied }"
                ),
            ]
        case .convert: OnboardingAbility.trayConvert.proofs + [
            .widget("Tray/NookConvertRules.swift", "static func combineActions(forFilesNamed names: [String])"),
            .widget("Tray/NookTrayTile.swift", "if flags.contains(.command) {"),
            .widget("Tray/NookTraySettings.swift", "Section(lang.t(\"nook.tray.settings.section\"))"),
        ]
        case .accent: [
            .app("Personalization/HangoverAccent.swift", "enum HangoverAccentChoice"),
            .app("Resources/en.lproj/Localizable.strings", "One choice for every display."),
            .app("Resources/en.lproj/Localizable.strings", "06 · Accent color"),
        ]
        case .lights: [
            .nook("Views/NookPersonalizationSections.swift", "NookLaserModeRow("),
            .nook("Views/NookPersonalizationSections.swift", "NookLaserCountRow("),
            .nook("Views/NookPersonalizationSections.swift", "NookBeatReachRow("),
            .app("Views/IslandLaserArrangement.swift", "static let least = 8"),
            .app("Views/IslandLaserArrangement.swift", "static let most = 24"),
            .app("Island/Beat/IslandLaserProgram.swift", "case reactive"),
            .app("Island/Beat/IslandLaserProgram.swift", "case show"),
            .app("Resources/en.lproj/Localizable.strings", "05 · Status glow"),
        ]
        case .power: [
            .widget("Power/NookPowerSettings.swift", "nook.power.settings.notices"),
            .widget("Power/NookPowerMonitor.swift", "On battery"),
            .widget("Power/NookPowerMonitor.swift", "Self.isBluetooth(device)"),
        ]
        case .volume: [
            .widget("Volume/NookVolumeSettings.swift", "nook.volume.settings.notice"),
            .widget("Volume/NookVolumeSettings.swift", "nook.volume.settings.keys"),
            .app("Resources/en.lproj/Localizable.strings", "macOS asks for Accessibility access the first time you turn this on."),
        ]
        case .usage: [
            .app("Views/IslandPanelView.swift", "id: \"claude-5h\""),
            .app("Views/IslandPanelView.swift", "id: \"claude-7d\""),
            .app("AppModelTypes.swift", "var usageDisplay: IslandUsageDisplay = .compact"),
            .app("Views/SettingsView.swift", "lang.t(\"setup.usageBridge\")"),
        ]
        case .quiet: [
            .nook("NookModel.swift", "guard case .sessionCompleted = event else { return false }"),
            // The pop-up is skipped, and nothing shows it later.
            .app("AppModel.swift", "!nook.shouldSuppressNotification(for: event)"),
            .nook("NookModel.swift", "var isFocusModeActive: Bool { timer.isRunning && !timer.isOnBreak }"),
            .nook("Views/NookSettingsPane.swift", "settings.nook.focusSuppresses.title"),
            .nook("Views/NookSettingsPane.swift", "settings.nook.meetingSuppresses.title"),
        ]
        case .phone: [
            .app("Views/SettingsView.swift", "settings.watch.notifications.title"),
            OnboardingProof(file: "Sources/OpenIslandCore/WatchNotificationRelay.swift", text: "onResolvePermission"),
            OnboardingProof(file: "Sources/OpenIslandCore/WatchNotificationRelay.swift", text: "onAnswerQuestion"),
            OnboardingProof(file: "README.md", text: "over your local network"),
        ]
        case .screens: [
            .app("Views/SettingsView.swift", "lang.t(\"settings.general.monitor\")"),
            .nook("Views/NookSettingsPane.swift", "settings.nook.arrange.note"),
        ]
        case .sounds: [
            .app("Views/SettingsView.swift", "lang.t(\"settings.sound.mute\")"),
            .nook("NookModel.swift", "guard !isSoundMuted() else { return }"),
            .widget("Timer/NookTimerSettings.swift", "nook.timer.settings.sound"),
        ]
        case .links: [
            .app("Island/IslandURLAction.swift", "static let scheme = \"hangover\""),
            .app("Island/IslandURLAction.swift", "case startPomodoro"),
            .app("Island/IslandURLAction.swift", "case setMirror(IslandSwitchChange)"),
            .app("Island/IslandURLAction.swift", "case setRingLight(IslandSwitchChange)"),
            .app("Views/SettingsView.swift", "lang.t(\"settings.general.linksFromOtherApps\")"),
            .app("Resources/en.lproj/Localizable.strings", "Any app on this Mac can send one."),
        ]
        case .startup: [
            .app("Views/SettingsView.swift", "lang.t(\"settings.general.launchAtLogin\")"),
            .app("Views/SettingsView.swift", "lang.t(\"settings.general.showDockIcon\")"),
            .app("AppModel.swift", "var launchAtLoginEnabled: Bool = false"),
            .app("AppModel.swift", "var showDockIcon: Bool = false"),
        ]
        case .updates: [
            .app("UpdateChecker.swift", "var installsAutomatically: Bool"),
            .app("Views/SettingsView.swift", "lang.t(\"settings.about.checkForUpdates\")"),
            .app("Views/SettingsView.swift", "lang.t(\"settings.about.installAutomatically\")"),
            OnboardingProof(file: "README.md", text: "About once a day the app also asks GitHub"),
        ]
        }
    }
}

extension OnboardingPage {
    /// The feature this page tells, for the pages of the long tour.
    var more: OnboardingMore? {
        switch self {
        case .mirror: .mirror
        case .booth: .booth
        case .weatherCard: .weather
        case .record: .record
        case .convert: .convert
        case .accent: .accent
        case .lights: .lights
        case .power: .power
        case .volume: .volume
        case .usage: .usage
        case .quiet: .quiet
        case .phone: .phone
        case .screens: .screens
        case .sounds: .sounds
        case .links: .links
        case .startup: .startup
        case .updates: .updates
        case .welcome, .length, .purpose, .opening, .closed, .agents, .widgets, .features, .layout, .arrange,
             .todos, .notes, .weather, .opened, .look, .permissions, .integrations, .tips, .done:
            nil
        }
    }
}
