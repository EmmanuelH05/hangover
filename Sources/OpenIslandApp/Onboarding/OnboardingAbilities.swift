import Foundation

// What the features page tells about each widget (D43, D47). Each line is
// tied to the code that does it: `proofs` names a file and a piece of its
// text, and `OnboardingShowcaseProofTests` fails when that text is renamed
// or removed. A claim without a proof is not added. A number in a line
// (shots, layouts, themes) is checked against the code by a test as well.

/// One thing a widget can do, as a line of the features page. The string
/// key is `onboarding.feature.<case>`. The lines of a widget are four to
/// seven, in the order they are told.
enum OnboardingAbility: String, CaseIterable, Identifiable, Sendable {
    case mirrorOn, mirrorRing, mirrorBooth, mirrorLooks, mirrorSaved, mirrorStrip, mirrorFrames
    case mediaNow, mediaControl, mediaSpeaker, mediaGlow, mediaGif
    case calendarLooks, calendarAdd, calendarEdit, calendarNext
    case todoCheck, todoNotes, todoDue, todoSources
    case notesAdd, notesRecent, notesDelete, notesWhere
    case trayDrag, trayActions, trayClipboard, trayPrivate
    case timerSet, timerPomodoro, timerPause, timerClosed
    case weatherForecast, weatherCity, weatherClosed, weatherSource

    var id: String { rawValue }

    var textKey: String { "onboarding.feature.\(rawValue)" }

    /// The widget the line is about.
    var widget: NookWidgetKind {
        switch self {
        case .mirrorOn, .mirrorRing, .mirrorBooth, .mirrorLooks, .mirrorSaved, .mirrorStrip, .mirrorFrames: .mirror
        case .mediaNow, .mediaControl, .mediaSpeaker, .mediaGlow, .mediaGif: .media
        case .calendarLooks, .calendarAdd, .calendarEdit, .calendarNext: .calendar
        case .todoCheck, .todoNotes, .todoDue, .todoSources: .todo
        case .notesAdd, .notesRecent, .notesDelete, .notesWhere: .notes
        case .trayDrag, .trayActions, .trayClipboard, .trayPrivate: .tray
        case .timerSet, .timerPomodoro, .timerPause, .timerClosed: .timer
        case .weatherForecast, .weatherCity, .weatherClosed, .weatherSource: .weather
        }
    }

    /// The lines of a widget, in the order the page shows them.
    static func lines(for kind: NookWidgetKind) -> [OnboardingAbility] {
        allCases.filter { $0.widget == kind }
    }

    /// The code that does what the line says.
    var proofs: [OnboardingProof] {
        switch self {
        case .mirrorOn: [
            .widget("Mirror/NookMirrorCard.swift", "The camera stays off until you turn it on."),
            .widget("Mirror/NookMirrorCard.swift", "Showing above your widgets until you turn it off."),
        ]
        case .mirrorRing: [
            .widget("Mirror/NookMirrorCard.swift", "Light your face with the screen"),
            .widget("Mirror/NookRingLight.swift", "enum NookRingLightTint"),
            .widget("Mirror/NookMirrorSettings.swift", "NookRingLightTintRow()"),
        ]
        case .mirrorBooth: [
            .widget("Mirror/PhotoBooth/NookPhotoBooth.swift", "camera.aperture"),
            .widget("Mirror/PhotoBooth/NookPhotoBoothModel.swift", "NookPhotoBoothPlan(shots: layout.shots"),
            .widget("Mirror/PhotoBooth/NookPhotoBoothSession.swift", "static let defaultCountdown = 5"),
        ]
        case .mirrorLooks: [
            .widget("Mirror/PhotoBooth/NookPhotoBoothSettings.swift", "ForEach(NookPhotoStripLayout.Kind.allCases)"),
            .widget("Mirror/PhotoBooth/NookPhotoBoothSettings.swift", "ForEach(NookPhotoStripTheme.all)"),
            .widget("Mirror/PhotoBooth/NookPhotoBoothSettings.swift", "text: $booth.caption"),
        ]
        case .mirrorSaved: [
            .widget("Mirror/PhotoBooth/NookPhotoBoothStore.swift", "static let folderName = \"Hangover Photo Booth\""),
            .widget("Mirror/PhotoBooth/NookPhotoBoothStore.swift", "Photo Strip \\(formatter.string(from: date))"),
            .widget("Mirror/PhotoBooth/NookPhotoBoothStore.swift", ".picturesDirectory"),
        ]
        case .mirrorStrip: [
            .widget("Mirror/PhotoBooth/NookPhotoBooth.swift", "booth.revealInFinder()"),
            .widget("Mirror/PhotoBooth/NookPhotoBooth.swift", "booth.share(from: shareAnchor.view)"),
            .widget("Mirror/PhotoBooth/NookPhotoBooth.swift", "booth.addToTray()"),
            .widget("Mirror/PhotoBooth/NookPhotoBooth.swift", "booth.retake()"),
        ]
        case .mirrorFrames: [
            .widget("Mirror/Decorations/NookMirrorDecorationPicker.swift", "case stickers"),
            .widget("Mirror/Decorations/NookMirrorDecorationPicker.swift", "case frames"),
            .widget("Mirror/PhotoBooth/NookPhotoBoothModel.swift", "var decorations: () -> NookMirrorDecorationSet"),
        ]
        case .mediaNow: [
            .nook("Media/MediaRemoteService.swift", "Reads system Now Playing state"),
            .nook("Media/NowPlayingState.swift", "var artworkData: Data?"),
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
        case .mediaGif: [
            .nook("NookModel.swift", "Animated GIF shown on the right side of the closed notch"),
            .nook("NookModel.swift", "var gifURL: URL?"),
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
        case .calendarEdit: [
            .widget("Calendar/NookEventEditor.swift", "Add location"),
            .widget("Calendar/NookEventEditor.swift", "Add notes"),
            .widget("Calendar/NookEventEditor.swift", ".help(\"Alert\")"),
            .widget("Calendar/NookEventEditor.swift", ".help(\"Repeat\")"),
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
        case .todoDue: [
            .widget("Todo/NookTodoCard.swift", "Self.dueLabel(due)"),
            .widget("Todo/NookTodoCard.swift", "Self.isOverdue(due)"),
        ]
        case .todoSources: [
            .widget("Todo/NookTodoSource.swift", "case reminders"),
            .widget("Todo/NookTodoSource.swift", "case notion"),
            .widget("Todo/NookTodoSource.swift", "case tickTick"),
        ]
        case .notesAdd: [
            .widget("Notes/NookNotesCard.swift", "service.append(draft)"),
        ]
        case .notesRecent: [
            .widget("Notes/NookNotesCard.swift", "service.entries.prefix(visibleEntryCount)"),
        ]
        case .notesDelete: [
            .widget("Notes/NookNotesCard.swift", "service.delete(entry.id)"),
            .widget("Notes/NookNotesService.swift", "var canDelete: Bool { destination == .file }"),
        ]
        case .notesWhere: [
            .widget("Notes/NookAppleNotes.swift", "case file"),
            .widget("Notes/NookAppleNotes.swift", "case appleNotes"),
            .widget("Notes/NookNotesSettings.swift", "chooseFile(service)"),
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
        case .trayPrivate: [
            .widget("Tray/NookClipboardHistory.swift", "org.nspasteboard.ConcealedType"),
            .widget("Tray/NookClipboardHistory.swift", "Kept in memory only"),
        ]
        case .timerSet: [
            .widget("Timer/NookTimerCard.swift", "Type minutes or 1:30"),
            .widget("Timer/NookTimerCard.swift", "chips = [15, 25, 50]"),
        ]
        case .timerPomodoro: [
            .widget("Timer/NookTimerCard.swift", "Button(action: startPomodoro)"),
            .widget("Timer/NookTimerSettings.swift", "nook.timer.pomodoro.settings.shortBreak"),
        ]
        case .timerPause: [
            .widget("Timer/NookTimerCard.swift", "timer.pause()"),
            .widget("Timer/NookFocusTimer.swift", "func reset()"),
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
        case .weatherClosed: [
            .nook("NookClosedActivity.swift", "case weather(text: String, symbol: String)"),
            .nook("NookDisplayPreferences.swift", "case weather"),
        ]
        case .weatherSource: [
            .widget("Weather/NookWeatherClient.swift", "api.open-meteo.com"),
            .widget("Weather/NookWeatherSettings.swift", "nook.weather.settings.privacy"),
        ]
        }
    }
}
