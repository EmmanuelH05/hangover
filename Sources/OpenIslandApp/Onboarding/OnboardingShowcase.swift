import Foundation

// What the widgets page and the integrations page tell (D43). Each line
// and each integration is tied to the code that does it: `proofs` names a
// file and a piece of its text, and `OnboardingShowcaseTests` fails when
// that text is renamed or removed. A claim without a proof is not added.

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

// MARK: - What a widget can do

/// One thing a widget can do beyond the obvious, as the spotlight on the
/// widgets page says it. The string key is `onboarding.spotlight.<case>`.
enum OnboardingAbility: String, CaseIterable, Identifiable, Sendable {
    case mirrorBooth, mirrorStrip, mirrorFrames
    case trayDrag, trayActions, trayClipboard
    case mediaControl, mediaSpeaker, mediaGlow
    case calendarLooks, calendarAdd, calendarNext
    case todoCheck, todoNotes, todoSources
    case notesAdd, notesWhere
    case timerSet, timerPomodoro, timerClosed
    case weatherForecast, weatherCity

    var id: String { rawValue }

    var textKey: String { "onboarding.spotlight.\(rawValue)" }

    /// The widget the line is about.
    var widget: NookWidgetKind {
        switch self {
        case .mirrorBooth, .mirrorStrip, .mirrorFrames: .mirror
        case .trayDrag, .trayActions, .trayClipboard: .tray
        case .mediaControl, .mediaSpeaker, .mediaGlow: .media
        case .calendarLooks, .calendarAdd, .calendarNext: .calendar
        case .todoCheck, .todoNotes, .todoSources: .todo
        case .notesAdd, .notesWhere: .notes
        case .timerSet, .timerPomodoro, .timerClosed: .timer
        case .weatherForecast, .weatherCity: .weather
        }
    }

    /// The lines of a widget, in the order the spotlight shows them.
    static func lines(for kind: NookWidgetKind) -> [OnboardingAbility] {
        allCases.filter { $0.widget == kind }
    }

    /// The code that does what the line says.
    var proofs: [OnboardingProof] {
        switch self {
        case .mirrorBooth: [
            .widget("Mirror/PhotoBooth/NookPhotoBooth.swift", "camera.aperture"),
            .widget("Mirror/PhotoBooth/NookPhotoBoothModel.swift", "NookPhotoBoothPlan(shots: layout.shots"),
        ]
        case .mirrorStrip: [
            .widget("Mirror/PhotoBooth/NookPhotoBoothStore.swift", "pictures.appendingPathComponent(folderName"),
            .widget("Mirror/PhotoBooth/NookPhotoBooth.swift", "booth.revealInFinder()"),
            .widget("Mirror/PhotoBooth/NookPhotoBooth.swift", "booth.share(from: shareAnchor.view)"),
        ]
        case .mirrorFrames: [
            .widget("Mirror/Decorations/NookMirrorDecorationPicker.swift", "case stickers"),
            .widget("Mirror/Decorations/NookMirrorDecorationPicker.swift", "case frames"),
            .widget("Mirror/NookMirrorCard.swift", "Light your face with the screen"),
        ]
        case .trayDrag: [
            .app("Views/IslandPanelView.swift", "model.nook.tray.handleDrop(providers)"),
            .widget("Tray/NookTrayCard.swift", ".onDrag {"),
        ]
        case .trayActions: [
            .widget("Tray/NookTrayCard.swift", "store.share(item, from: anchor.view)"),
            .widget("Tray/NookTrayCard.swift", "store.airDrop(item)"),
            .widget("Tray/NookTrayCard.swift", "store.compress(item)"),
            .widget("Tray/NookTrayCard.swift", "store.copyPath(of: item)"),
        ]
        case .trayClipboard: [
            .widget("Tray/NookClipboardViews.swift", "store.clipboard.setEnabled(true)"),
            .widget("Tray/NookClipboardViews.swift", "store.copyAgain(entry)"),
            .widget("Tray/NookClipboardHistory.swift", "case image(data: Data"),
            .widget("Tray/NookClipboardHistory.swift", "case text(String)"),
        ]
        case .mediaControl: [
            .nook("Views/NookMediaViews.swift", "nook.media.previousTrack()"),
            .nook("Views/NookMediaViews.swift", "nook.media.togglePlayPause()"),
            .nook("Views/NookMediaViews.swift", "nook.media.nextTrack()"),
            .nook("Views/NookMediaControls.swift", "media.seek(to: fraction * duration)"),
        ]
        case .mediaSpeaker: [
            .nook("Views/NookMediaViews.swift", "nook.audioOutputs.beginPicking()"),
        ]
        case .mediaGlow: [
            .nook("Views/NookMediaViews.swift", "NookBarVisualizer(isPlaying: activity.isPlaying"),
            .app("AppModel+Halo.swift", "nook.artworkTint.tint"),
        ]
        case .calendarLooks: [
            .widget("Calendar/NookCalendarShared.swift", "case strip"),
            .widget("Calendar/NookCalendarShared.swift", "case agenda"),
            .widget("Calendar/NookCalendarShared.swift", "case timeline"),
            .widget("Calendar/NookCalendarShared.swift", "case hero"),
            .widget("Calendar/NookCalendarShared.swift", "case month"),
        ]
        case .calendarAdd: [
            .widget("Calendar/NookEventForm.swift", "NookEventQuickAdd.parse(title"),
        ]
        case .calendarNext: [
            .widget("Calendar/NookCalendarSettings.swift", "Next-up notices (10 and 2 minutes before)"),
            .widget("Calendar/NookMeetingLink.swift", "static let lead: TimeInterval = 10 * 60"),
            .nook("Views/NookPanelView.swift", "NookJoinBar(nook: nook, event: meeting)"),
        ]
        case .todoCheck: [
            .widget("Todo/NookTodoCard.swift", "source.complete(item.id)"),
            .widget("Todo/NookTodoCard.swift", "source.add(draft)"),
        ]
        case .todoNotes: [
            .widget("Todo/NookTodoCard.swift", "open(item)"),
            .widget("Todo/NookTodoDetailPage.swift", "var onSave: () -> Void"),
        ]
        case .todoSources: [
            .widget("Todo/NookTodoSource.swift", "case reminders"),
            .widget("Todo/NookTodoSource.swift", "case notion"),
            .widget("Todo/NookTodoSource.swift", "case tickTick"),
        ]
        case .notesAdd: [
            .widget("Notes/NookNotesCard.swift", "service.append(draft)"),
        ]
        case .notesWhere: [
            .widget("Notes/NookAppleNotes.swift", "case file"),
            .widget("Notes/NookAppleNotes.swift", "case appleNotes"),
            .widget("Notes/NookNotesSettings.swift", "chooseFile(service)"),
        ]
        case .timerSet: [
            .widget("Timer/NookTimerCard.swift", "Type minutes or 1:30"),
            .widget("Timer/NookTimerCard.swift", "chips = [15, 25, 50]"),
        ]
        case .timerPomodoro: [
            .widget("Timer/NookTimerCard.swift", "Button(action: startPomodoro)"),
            .widget("Timer/NookTimerSettings.swift", "nook.timer.pomodoro.settings.shortBreak"),
        ]
        case .timerClosed: [
            .widget("Timer/NookFocusTimer.swift", "var closedText: String?"),
            .widget("Timer/NookTimerSettings.swift", "Play a sound when done"),
        ]
        case .weatherForecast: [
            .widget("Weather/NookWeatherModels.swift", "case hours"),
            .widget("Weather/NookWeatherModels.swift", "case week"),
            .widget("Weather/NookWeatherCard.swift", "nook.weather.feelsLike"),
        ]
        case .weatherCity: [
            .widget("Weather/NookWeatherSettings.swift", "nook.weather.settings.search.placeholder"),
            .widget("Weather/NookWeatherSettings.swift", "NookTemperatureUnit.fahrenheit"),
            .widget("Weather/NookWeatherSettings.swift", "NookTemperatureUnit.celsius"),
        ]
        }
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
