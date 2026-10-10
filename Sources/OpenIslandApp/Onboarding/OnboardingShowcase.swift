import Foundation

// What the integrations page tells (D43). Each integration is tied to the
// code that does it: `proofs` names a file and a piece of its text, and
// `OnboardingShowcaseProofTests` fails when that text is renamed or removed.
// A claim without a proof is not added. The widget lines are in
// `OnboardingAbilities.swift`.

/// A piece of code that a claim stands on: the file, and text that file
/// has to keep.
struct OnboardingProof: Equatable, Sendable {
    /// Path from the repo root.
    let file: String
    let text: String

    private static let nook = "Sources/OpenIslandApp/Nook/"
    private static let widgets = nook + "Widgets/"

    static func widget(_ path: String, _ text: String) -> OnboardingProof {
        OnboardingProof(file: widgets + path, text: text)
    }

    static func nook(_ path: String, _ text: String) -> OnboardingProof {
        OnboardingProof(file: nook + path, text: text)
    }

    static func app(_ path: String, _ text: String) -> OnboardingProof {
        OnboardingProof(file: "Sources/OpenIslandApp/" + path, text: text)
    }
}

// MARK: - What it connects to

/// An outside thing the app connects to, as a card of the integrations
/// page. The string keys are `onboarding.integrations.<case>.name`, `.text`
/// and `.where`. Nothing here asks macOS for anything: the page only says
/// what the connection does and where it is set up.
enum OnboardingIntegration: String, CaseIterable, Identifiable, Sendable {
    case calendar
    case appleNotes
    case notion
    case tickTick
    case music
    case power
    case volume
    case weather
    /// Only with the agents switch on.
    case agents
    /// Only with the agents switch on.
    case terminals

    var id: String { rawValue }

    var needsAgents: Bool { self == .agents || self == .terminals }

    var nameKey: String { "onboarding.integrations.\(rawValue).name" }
    var textKey: String { "onboarding.integrations.\(rawValue).text" }
    var whereKey: String { "onboarding.integrations.\(rawValue).where" }

    var symbol: String {
        switch self {
        case .calendar: "calendar"
        case .appleNotes: "note.text"
        case .notion: "doc.text"
        case .tickTick: "checkmark.circle"
        case .music: "music.note"
        case .power: "airpodspro"
        case .volume: "speaker.wave.2.fill"
        case .weather: "cloud.sun"
        case .agents: "sparkles"
        case .terminals: "terminal.fill"
        }
    }

    /// The cards a run shows, in this order. Agents and terminals are left
    /// out with the agents switch off.
    static func shown(agentsEnabled: Bool) -> [OnboardingIntegration] {
        allCases.filter { agentsEnabled || !$0.needsAgents }
    }

    /// The code that does what the card says.
    var proofs: [OnboardingProof] {
        switch self {
        case .calendar: [
            .widget("Calendar/NookCalendarService.swift", "EKEventStore"),
            .widget("Todo/NookRemindersService.swift", "predicateForIncompleteReminders"),
        ]
        case .appleNotes: [
            .widget("Notes/NookAppleNotes.swift", "case appleNotes"),
            .widget("Notes/NookNotesSettings.swift", "Text(\"Apple Notes\").tag(NookNotesDestination.appleNotes)"),
        ]
        case .notion: [
            .widget("Todo/Notion/NotionClient.swift", "api.notion.com"),
        ]
        case .tickTick: [
            .widget("Todo/TickTick/TickTickClient.swift", "api.ticktick.com"),
        ]
        case .music: [
            .nook("Media/MediaRemoteService.swift", "Reads system Now Playing state"),
            .nook("Views/NookMediaViews.swift", "Play something in Spotify or Music"),
            .nook("Views/NookMediaViews.swift", "nook.media.nextTrack()"),
        ]
        case .power: [
            .widget("Power/NookPowerSettings.swift", "Show charger and headphone notices"),
            .widget("Power/NookPowerMonitor.swift", "localizedCaseInsensitiveContains(\"AirPods\")"),
            .widget("Power/NookPowerMonitor.swift", "Charging"),
        ]
        case .volume: [
            .widget("Volume/NookVolumeSettings.swift", "nook.volume.settings.keys"),
            .widget("Volume/NookVolumeSettings.swift", "nook.volume.settings.notice"),
        ]
        case .weather: [
            .widget("Weather/NookWeatherClient.swift", "api.open-meteo.com"),
            .widget("Weather/NookWeatherSettings.swift", "nook.weather.settings.privacy"),
        ]
        case .agents: [
            .app("Onboarding/OnboardingTour.swift", "case claudeCode"),
            .app("Onboarding/OnboardingTour.swift", "case openCode"),
            .proof(core: "AgentSession.swift", "case qwenCode"),
            .proof(core: "AgentSession.swift", "case kimiCLI"),
        ]
        case .terminals: [
            .app("TerminalJumpService.swift", "displayName: \"iTerm\""),
            .app("TerminalJumpService.swift", "displayName: \"Ghostty\""),
            .app("TerminalJumpService.swift", "displayName: \"Terminal\""),
            .app("TerminalJumpService.swift", "displayName: \"Warp\""),
            .app("TerminalJumpService.swift", "displayName: \"WezTerm\""),
            .app("TerminalJumpService.swift", "displayName: \"VS Code\""),
        ]
        }
    }
}

private extension OnboardingProof {
    static func proof(core path: String, _ text: String) -> OnboardingProof {
        OnboardingProof(file: "Sources/OpenIslandCore/" + path, text: text)
    }
}
