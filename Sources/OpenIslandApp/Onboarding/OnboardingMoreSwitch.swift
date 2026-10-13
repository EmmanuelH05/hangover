import Foundation

// The switches on the long tour's Good to know pages. Each is a plain setting
// of the app, read from the model and written through the same door the
// switch in Settings uses. The tour switches nothing on by itself: a switch
// is what the user flips, and it stays as flipped when the tour ends. The
// lights page has its own switch (`OnboardingBeatReading`), the same one the
// glow page has.

/// One switch of a Good to know page.
enum OnboardingMoreSwitch: String, CaseIterable, Identifiable, Sendable {
    /// The charger and headphones notices (Settings, Nook tab, Battery and headphones).
    case powerNotices
    /// The volume level on the closed island.
    case volumeNotice
    /// Taking the volume and brightness keys. The one switch that makes macOS
    /// ask: for Accessibility access.
    case volumeKeys
    /// The usage meter on the open island (Personalization, Usage).
    case usageMeter
    /// No completion pop-up while a focus timer runs.
    case focusQuiet
    /// No completion pop-up during a meeting.
    case meetingQuiet
    /// The Mute switch.
    case mute
    /// Links from other apps.
    case links
    case launchAtLogin
    case dockIcon
    case autoUpdates
    /// The Mirror widget, which starts off. Only the widget: the camera stays
    /// off until its own button is pressed. The mirror and photo booth pages
    /// both carry it.
    case mirrorWidget
    /// The Weather widget, which starts off.
    case weatherWidget

    var id: String { rawValue }

    /// The page the switch is on.
    var more: OnboardingMore {
        switch self {
        case .powerNotices: .power
        case .volumeNotice, .volumeKeys: .volume
        case .usageMeter: .usage
        case .focusQuiet, .meetingQuiet: .quiet
        case .mute: .sounds
        case .links: .links
        case .launchAtLogin, .dockIcon: .startup
        case .autoUpdates: .updates
        case .mirrorWidget: .mirror
        case .weatherWidget: .weather
        }
    }

    /// The switches of a page, in the order Settings lists them.
    static func switches(for more: OnboardingMore) -> [OnboardingMoreSwitch] {
        // The photo booth is a part of the Mirror widget, which is its switch.
        more == .booth ? [.mirrorWidget] : allCases.filter { $0.more == more }
    }

    /// True for a switch of the agent half, which the agents switch hides
    /// along with its page.
    var needsAgents: Bool { more.needsAgents }

    /// True for the switch that makes macOS ask for something when it is
    /// flipped on. Its line says what, before the flip.
    var asksMacOS: Bool { self == .volumeKeys }

    /// Settings' own label where Settings has one in a language file.
    var titleKey: String {
        switch self {
        case .volumeNotice: "nook.volume.settings.notice"
        case .volumeKeys: "nook.volume.settings.keys"
        case .mute: "settings.sound.mute"
        case .links: "settings.general.linksFromOtherApps"
        case .launchAtLogin: "settings.general.launchAtLogin"
        case .dockIcon: "settings.general.showDockIcon"
        case .autoUpdates: "settings.about.installAutomatically"
        case .mirrorWidget: "onboarding.nook.widget.mirror"
        case .weatherWidget: "onboarding.nook.widget.weather"
        case .powerNotices, .usageMeter, .focusQuiet, .meetingQuiet: "onboarding.more.switch.\(rawValue)"
        }
    }

    /// The line under the switch: what it does and, for a switch that makes
    /// macOS ask, what macOS will ask.
    var lineKey: String { "onboarding.more.switch.\(rawValue).line" }

    /// What the app does when nothing was ever flipped.
    var startsOn: Bool {
        switch self {
        case .powerNotices, .volumeNotice, .usageMeter, .focusQuiet, .meetingQuiet, .links, .dockIcon: true
        case .volumeKeys, .mute, .launchAtLogin, .autoUpdates, .mirrorWidget, .weatherWidget: false
        }
    }
}

/// Where the volume and brightness keys stand, the way Settings shows it.
enum OnboardingKeysAccess: Equatable, Sendable {
    case off
    /// Switched on, and macOS has not said yes to Accessibility.
    case waiting
    case active
    /// macOS said yes and still refused the key filter.
    case unavailable
}

/// What the Good to know pages read from the app.
struct OnboardingMoreReading: Equatable, Sendable {
    /// The switches that are on.
    var on: Set<OnboardingMoreSwitch> = Set(OnboardingMoreSwitch.allCases.filter(\.startsOn))
    var keys: OnboardingKeysAccess = .off
    /// A launch found the keys switch on and no grant: macOS may be holding a
    /// grant from an older version.
    var keysAccessWasMissingAtLaunch = false
    /// The updater runs (the downloaded app). Where it does not, Settings
    /// leaves its switch dimmed, and the tour does the same.
    var canCheckForUpdates = false

    func isOn(_ item: OnboardingMoreSwitch) -> Bool { on.contains(item) }

    /// Whether the switch can be flipped.
    func isEnabled(_ item: OnboardingMoreSwitch) -> Bool {
        item != .autoUpdates || canCheckForUpdates
    }
}
