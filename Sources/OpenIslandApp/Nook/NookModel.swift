import AppKit
import Foundation
import Observation
import OpenIslandCore
import SwiftUI

/// Which page the opened island shows. `auto` means the agent list while a
/// session is running or waiting on the user, and the Nook otherwise.
enum NookOpenedPage: String, CaseIterable, Sendable {
    case auto
    case agents
    case nook

}

/// The widgets that can appear on the Nook page, in display order.
enum NookWidgetKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case media
    case calendar
    case todo
    case notes
    case tray
    case timer
    case mirror
    case weather

    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: "Now playing"
        case .calendar: "Calendar"
        case .todo: "Todo"
        case .notes: "Notes"
        case .tray: "File tray"
        case .timer: "Focus timer"
        case .mirror: "Mirror"
        case .weather: LanguageManager.shared.t("nook.weather.title")
        }
    }

    var systemImage: String {
        switch self {
        case .media: "music.note"
        case .calendar: "calendar"
        case .todo: "checklist"
        case .notes: "note.text"
        case .tray: "tray.full"
        case .timer: "timer"
        case .mirror: "camera"
        case .weather: "cloud.sun"
        }
    }

    /// The mirror stays off until asked for; it turns the camera on while
    /// the island is open. Weather stays off too: it is the one widget
    /// that asks a server for anything.
    static let defaultEnabled: [NookWidgetKind] = [.media, .calendar, .todo, .notes, .tray, .timer]
}

/// Everything the closed island needs to draw the media live activity.
/// `NSImage` is a reference type, so equality is identity-based; the model
/// hands out one decoded image per track, which keeps SwiftUI diffing cheap.
struct NookClosedMediaActivity {
    var artwork: NSImage?
    var gifURL: URL?
    var gifScale: CGFloat
    var gifOffset: CGSize
    var isPlaying: Bool
}

extension NookClosedMediaActivity: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.artwork === rhs.artwork
            && lhs.gifURL == rhs.gifURL
            && lhs.gifScale == rhs.gifScale
            && lhs.gifOffset == rhs.gifOffset
            && lhs.isPlaying == rhs.isPlaying
    }
}

/// State and preferences for the NotchNook-style features layered on top of
/// Open Island. Owned by `AppModel`; every service starts from `start()`.
@MainActor
@Observable
final class NookModel {
    private static let enabledWidgetsKey = "nook.enabledWidgets"
    private static let ringLightKey = "nook.mirror.ringLight"
    private static let gifPathKey = "nook.media.gifPath"
    private static let gifScaleKey = "nook.media.gifScale"
    private static let gifOffsetXKey = "nook.media.gifOffsetX"
    private static let gifOffsetYKey = "nook.media.gifOffsetY"
    private static let focusSuppressesCompletionsKey = "nook.agents.focusSuppressesCompletions"
    private static let meetingSuppressesCompletionsKey = "nook.agents.meetingSuppressesCompletions"
    /// How long the album art stays in the closed notch after playback pauses.
    private static let pausedActivityLinger: Duration = .seconds(10)

    // MARK: Services (one per widget folder under Nook/Widgets)

    let media = MediaRemoteService()
    let calendar: NookCalendarService
    let reminders: NookRemindersService
    let todo: NookTodoHub
    let notes = NookNotesService()
    let tray = NookTrayStore()
    let timer = NookFocusTimer()
    /// The photo booth in the mirror.
    let photoBooth = NookPhotoBoothModel()
    let power = NookPowerMonitor()
    /// Sound outputs for the speaker picker on the now-playing card.
    let audioOutputs = NookAudioOutputs()
    /// Volume and brightness notices, and the optional key takeover.
    let volume = NookVolumeMonitor()
    let weather = NookWeatherService()
    /// Dominant album-art color for the music halo.
    let artworkTint = NookArtworkTintService()

    // MARK: Preferences

    /// Per-display choices from the Personalization tab: one set for the
    /// MacBook notch and one for external displays.
    private var notchDisplay: NookDisplayPreferences {
        didSet { displayPreferencesDidChange(from: oldValue, to: notchDisplay, profile: .notch) }
    }

    private var topBarDisplay: NookDisplayPreferences {
        didSet { displayPreferencesDidChange(from: oldValue, to: topBarDisplay, profile: .topBar) }
    }

    /// Page forced by OPEN_ISLAND_NOOK_PAGE=auto|agents|nook for harness
    /// screenshots. Wins over the per-display setting.
    let forcedPage: NookOpenedPage?

    /// Lets the app model resize the island when a display choice changes.
    @ObservationIgnored var onDisplayPreferencesChanged: (() -> Void)?

    /// Set by the header toggle for the current open; cleared when the
    /// island opens again, so `openedPage` decides afresh each time.
    var pageOverride: NookOpenedPage?

    /// True while the Nook page is in edit mode: cards can be dragged,
    /// resized and removed, and the island stays open when the pointer
    /// leaves. Ends when the island closes.
    var isEditingLayout = false {
        didSet { if isEditingLayout != oldValue { onDisplayPreferencesChanged?() } }
    }

    /// The widget the welcome tour is teaching with: its tile gets a ring in
    /// the grid so a beginner can find it. Set and cleared by the tour and by
    /// nothing else (D44), and never saved.
    var tourOutlinedWidget: NookWidgetKind?

    /// True once the Mirror widget's tile turns the camera on. The mirror
    /// then sits at the top of the Nook page and holds the island open
    /// until it is turned off: by its tile, by its close button, by closing
    /// the island, by leaving the Nook page or by removing the tile. Never
    /// saved: a fresh launch does not start with the camera on.
    var isMirrorOn = false {
        didSet {
            guard isMirrorOn != oldValue else { return }
            // Mirror off closes the sticker picker here and not only when
            // its view goes away, which can be late or never.
            if !isMirrorOn { stopDecoratingMirror() }
            // An explicit off stops the camera at once.
            if isMirrorOn {
                NookMirrorController.shared.resumeIfAttached()
            } else {
                // No mirror, no booth: a session in progress is thrown away.
                photoBooth.cancel()
                NookMirrorController.shared.stopNow()
            }
            presentRingLight(isMirrorOn && isRingLightOn)
            onDisplayPreferencesChanged?()
        }
    }

    /// True while the event editor is up at the top of the Nook page. The
    /// island stays open then, which keeps a drifting pointer from throwing
    /// away what was typed.
    private(set) var isEventEditorOpen = false {
        didSet { if isEventEditorOpen != oldValue { onDisplayPreferencesChanged?() } }
    }

    var isAddingEvent: Bool { isEventEditorOpen }

    /// What the editor holds. Only the editor reads it, which keeps a
    /// keystroke from re-rendering the whole page.
    var eventForm: NookEventForm?

    /// A form the island closed on before it was saved. The next "+"
    /// brings it back.
    @ObservationIgnored private var stashedEventForm: NookEventForm?

    /// Rows the calendar card has grown by after "+N more". Zero is its
    /// normal height.
    var calendarExtraRows = 0 {
        didSet { if calendarExtraRows != oldValue { onDisplayPreferencesChanged?() } }
    }

    /// The meeting the Join bar offers right now: one that starts within
    /// ten minutes or began within the last fifteen. Nil the rest of the
    /// time, and after it is joined or put away.
    private(set) var meetingPrompt: NookCalendarEvent? {
        didSet { if meetingPrompt?.id != oldValue?.id { onDisplayPreferencesChanged?() } }
    }

    /// Meetings already joined or put away. Kept in memory only.
    @ObservationIgnored private var dismissedMeetingIDs: Set<String> = []

    /// Opens a meeting link. A test swaps this for a recorder, which keeps
    /// it from opening a real meeting.
    @ObservationIgnored var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

    /// The ring light: a bright band around the screen's edge while the
    /// mirror is on. Saved, which brings it back with the mirror next time.
    var isRingLightOn: Bool {
        didSet {
            guard isRingLightOn != oldValue else { return }
            defaults.set(isRingLightOn, forKey: Self.ringLightKey)
            presentRingLight(isMirrorOn && isRingLightOn)
        }
    }

    /// Shows or hides the ring light. The app model installs it; a bare
    /// model lights nothing.
    @ObservationIgnored var presentRingLight: (_ isLit: Bool) -> Void = { _ in }

    /// The frame and stickers on the mirror. The live mirror shows them and
    /// the photo booth draws them into its photos. Saved.
    var mirrorDecorations: NookMirrorDecorationSet {
        didSet {
            guard mirrorDecorations != oldValue else { return }
            NookMirrorDecorationStore.save(mirrorDecorations, to: defaults)
        }
    }

    /// True while the decoration picker is up under the mirror. The island
    /// grows by the picker's height then.
    var isDecoratingMirror = false {
        didSet { if isDecoratingMirror != oldValue { onDisplayPreferencesChanged?() } }
    }

    /// The sticker the editor's handles are on.
    var selectedMirrorStickerID: UUID?

    /// While the focus timer runs, agent completion cards stay quiet;
    /// permission and question cards still come through.
    var focusSuppressesCompletions: Bool {
        didSet { defaults.set(focusSuppressesCompletions, forKey: Self.focusSuppressesCompletionsKey) }
    }

    /// While a calendar event with a meeting link is on, agent completion
    /// cards stay quiet, the same way they do during a focus session.
    var meetingSuppressesCompletions: Bool {
        didSet { defaults.set(meetingSuppressesCompletions, forKey: Self.meetingSuppressesCompletionsKey) }
    }

    /// The display profile the island is on right now. The app model
    /// installs this; cards read `activeDisplay` through it.
    @ObservationIgnored var activeProfile: () -> IslandAppearanceDisplayProfile = { .topBar }

    var activeDisplay: NookDisplayPreferences { displayPreferences(for: activeProfile()) }

    /// Hooks the app model installs so the Nook can use the island's own
    /// pop animation and mute switch without owning the app model.
    @ObservationIgnored var onTransient: (() -> Void)?
    @ObservationIgnored var isSoundMuted: () -> Bool = { false }

    /// Widgets shown on the Nook page, in order.
    var enabledWidgets: [NookWidgetKind] {
        didSet {
            defaults.set(enabledWidgets.map(\.rawValue), forKey: Self.enabledWidgetsKey)
            // The page and the window height follow the enabled set.
            if enabledWidgets != oldValue { onDisplayPreferencesChanged?() }
            // Switching the Mirror widget off takes its tile off every page.
            if oldValue.contains(.mirror), !enabledWidgets.contains(.mirror) { isMirrorOn = false }
        }
    }

    /// Animated GIF shown on the right side of the closed notch while music
    /// plays. `nil` falls back to the bar visualizer.
    var gifURL: URL? {
        didSet { defaults.set(gifURL?.path, forKey: Self.gifPathKey) }
    }

    var gifScale: Double {
        didSet { defaults.set(gifScale, forKey: Self.gifScaleKey) }
    }

    var gifOffsetX: Double {
        didSet { defaults.set(gifOffsetX, forKey: Self.gifOffsetXKey) }
    }

    var gifOffsetY: Double {
        didSet { defaults.set(gifOffsetY, forKey: Self.gifOffsetYKey) }
    }

    // MARK: Live state

    /// False once playback has been paused for a while, so the closed notch
    /// shrinks back instead of showing stale artwork all day.
    private(set) var isMediaActivityLive = false

    /// Short notice currently occupying the closed notch, if any.
    private(set) var transient: NookTransientActivity?

    /// A sideways swipe on the closed island sent what it shows away (D46).
    /// Not saved: a new launch starts with the island showing everything.
    var closedContentHiddenBySwipe = false

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var cachedArtwork: (key: String, image: NSImage)?
    @ObservationIgnored private var lingerTask: Task<Void, Never>?
    @ObservationIgnored private var transientTask: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false

    /// The three services default to the real ones. A test of permission
    /// timing hands in services that carry permissions of its own.
    init(
        calendar: NookCalendarService? = nil,
        reminders: NookRemindersService? = nil,
        todo: NookTodoHub? = nil
    ) {
        self.calendar = calendar ?? NookCalendarService()
        self.reminders = reminders ?? NookRemindersService()
        self.todo = todo ?? NookTodoHub()
        let defaults = UserDefaults.standard
        forcedPage = ProcessInfo.processInfo.environment["OPEN_ISLAND_NOOK_PAGE"].flatMap(NookOpenedPage.init(rawValue:))
        // OPEN_ISLAND_NOOK_EDITING=1 opens the page in edit mode for harness screenshots.
        isEditingLayout = ProcessInfo.processInfo.environment["OPEN_ISLAND_NOOK_EDITING"] == "1"
        isRingLightOn = defaults.object(forKey: Self.ringLightKey) as? Bool ?? false
        mirrorDecorations = NookMirrorDecorationStore.load(from: defaults)
        notchDisplay = NookDisplayPreferences.load(for: .notch, defaults: defaults)
        topBarDisplay = NookDisplayPreferences.load(for: .topBar, defaults: defaults)
        focusSuppressesCompletions = defaults.object(forKey: Self.focusSuppressesCompletionsKey) as? Bool ?? true
        meetingSuppressesCompletions = defaults.object(forKey: Self.meetingSuppressesCompletionsKey) as? Bool ?? true
        if let raw = defaults.stringArray(forKey: Self.enabledWidgetsKey) {
            enabledWidgets = raw.compactMap(NookWidgetKind.init(rawValue:))
        } else {
            enabledWidgets = NookWidgetKind.defaultEnabled
        }
        if let path = defaults.string(forKey: Self.gifPathKey) {
            gifURL = URL(fileURLWithPath: path)
        } else {
            gifURL = Self.importedNotchNookGIF()
        }
        gifScale = defaults.object(forKey: Self.gifScaleKey) as? Double ?? 1
        gifOffsetX = defaults.object(forKey: Self.gifOffsetXKey) as? Double ?? 0
        gifOffsetY = defaults.object(forKey: Self.gifOffsetYKey) as? Double ?? 0
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        media.start()
        observePlayback()
        calendar.start(nook: self)
        reminders.start(nook: self)
        todo.start(nook: self)
        notes.start(nook: self)
        tray.start(nook: self)
        timer.start(nook: self)
        photoBooth.attach(nook: self)
        power.start(nook: self)
        audioOutputs.start()
        volume.start(nook: self)
        weather.start(nook: self)
        artworkTint.start(nook: self)
        observeScreenGoingAway()
        // Nothing above asks macOS for the calendar or Reminders. From here
        // on a widget that is shown or turned on may (`NookAccessTiming`).
        allowsAccessRequests = true
    }

    // MARK: - Calendar and Reminders access

    /// False until `start()`. A model that was never started asks macOS
    /// for nothing, which keeps a test or a preview from raising a real
    /// prompt. A test of the timing turns it on, with services that carry
    /// permissions of its own.
    @ObservationIgnored var allowsAccessRequests = false

    /// The widgets the user is looking at right now. The app model
    /// installs it (`NookAccessTiming.widgetsInView`); a bare model shows
    /// nothing to anyone.
    @ObservationIgnored var widgetsInUserView: () -> Set<NookWidgetKind> = { [] }

    /// The last piece of queued access work. Each new piece waits for it.
    @ObservationIgnored private var accessWork: Task<Void, Never>?
    /// True from the moment a pass over the widgets in view is queued until
    /// it starts to run.
    @ObservationIgnored private var isViewPassQueued = false

    /// Asks macOS for what a widget needs at this moment, if anything is
    /// still undecided. Returns the permissions macOS was asked for.
    @discardableResult
    func askForAccess(for kind: NookWidgetKind, at moment: NookAccessMoment) async -> Set<NookEventKitPermission> {
        guard allowsAccessRequests else { return [] }
        let needed = NookAccessTiming.permissions(
            for: kind,
            at: moment,
            isEnabled: isWidgetEnabled(kind),
            todoSource: todo.selectedKind
        )
        var asked: Set<NookEventKitPermission> = []
        if needed.contains(.calendar), await calendar.requestAccessIfUndecided() { asked.insert(.calendar) }
        if needed.contains(.reminders), await reminders.requestAccessIfUndecided() { asked.insert(.reminders) }
        return asked
    }

    /// The user switched a widget on in Settings, or picked Reminders as
    /// the to-do source there. The returned task ends when macOS has its
    /// answer; a test awaits it.
    @discardableResult
    func widgetTurnedOn(_ kind: NookWidgetKind) -> Task<Void, Never>? {
        guard allowsAccessRequests else { return nil }
        return queueAccessWork { nook in await nook.askForAccess(for: kind, at: .turnedOn) }
    }

    /// A calendar or to-do tile appeared, or the island's open state
    /// changed. Asks for what the widgets in the user's view need. One open
    /// calls this several times (the island's state, then each tile), and
    /// only the first call queues a pass.
    @discardableResult
    func widgetsCameIntoView() -> Task<Void, Never>? {
        guard allowsAccessRequests, !isViewPassQueued, !widgetsInUserView().isEmpty else { return nil }
        isViewPassQueued = true
        return queueAccessWork { nook in
            // What is in view is read when the pass runs, not when it was
            // queued: the island may have closed since.
            nook.isViewPassQueued = false
            let inView = nook.widgetsInUserView()
            for kind in NookWidgetKind.allCases where inView.contains(kind) {
                await nook.askForAccess(for: kind, at: .shown)
            }
        }
    }

    /// Runs one piece of access work after whatever is already queued,
    /// which keeps macOS from ever being asked for two things at once.
    private func queueAccessWork(_ work: @escaping @MainActor (NookModel) async -> Void) -> Task<Void, Never> {
        let earlier = accessWork
        let task = Task { @MainActor [weak self] in
            await earlier?.value
            guard let self else { return }
            await work(self)
        }
        accessWork = task
        return task
    }

    /// The mirror goes off when the Mac sleeps, its screens sleep, the
    /// screen locks or another user takes over. A photo booth countdown
    /// would otherwise pick up on wake and take its pictures behind the
    /// lock screen, with the camera on and nobody looking.
    private func observeScreenGoingAway() {
        let workspace = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ]
        for name in names {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screenWentAway() }
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenWentAway() }
        }
    }

    /// Turns the mirror off, which stops the camera at once and cancels a
    /// photo booth session.
    func screenWentAway() {
        isMirrorOn = false
    }

    // MARK: - Widgets

    func isWidgetEnabled(_ kind: NookWidgetKind) -> Bool {
        enabledWidgets.contains(kind)
    }

    func setWidget(_ kind: NookWidgetKind, enabled: Bool) {
        if enabled {
            guard !enabledWidgets.contains(kind) else { return }
            // Keep the canonical order so toggling never reshuffles the page.
            enabledWidgets = NookWidgetKind.allCases.filter { $0 == kind || enabledWidgets.contains($0) }
        } else {
            enabledWidgets.removeAll { $0 == kind }
        }
    }

    // MARK: - Per-display preferences

    func displayPreferences(for profile: IslandAppearanceDisplayProfile) -> NookDisplayPreferences {
        switch profile {
        case .notch: notchDisplay
        case .topBar: topBarDisplay
        }
    }

    func updateDisplayPreferences(
        for profile: IslandAppearanceDisplayProfile,
        _ update: (inout NookDisplayPreferences) -> Void
    ) {
        switch profile {
        case .notch: update(&notchDisplay)
        case .topBar: update(&topBarDisplay)
        }
    }

    private func displayPreferencesDidChange(
        from oldValue: NookDisplayPreferences,
        to newValue: NookDisplayPreferences,
        profile: IslandAppearanceDisplayProfile
    ) {
        guard newValue != oldValue else { return }
        newValue.persistChanges(from: oldValue, for: profile, defaults: defaults)
        let losesMirror = NookMirrorLayout.losesTile(
            from: oldValue.placements(enabled: enabledWidgets),
            to: newValue.placements(enabled: enabledWidgets)
        )
        if losesMirror { isMirrorOn = false }
        // A changed page may have another calendar look or size: the card
        // goes back to its normal height. A change to the glow colors alone
        // leaves the page as it is, and a color drag writes many of them.
        if newValue.changesThePage(from: oldValue) { calendarExtraRows = 0 }
        // Editing the display that is not on screen must not reposition the
        // real island.
        guard profile == activeProfile() else { return }
        onDisplayPreferencesChanged?()
    }

    // MARK: - Event editor

    /// Opens the event editor on a day. A draft the island closed on comes
    /// back as it was; otherwise the editor starts fresh on that day.
    func beginAddingEvent(on day: Date) {
        if let stashed = stashedEventForm, stashed.hasContent {
            eventForm = stashed
        } else {
            eventForm = NookEventForm.new(on: day, now: Date(), calendar: .current)
        }
        stashedEventForm = nil
        isEventEditorOpen = true
    }

    /// Closes the editor. Cancel and Save drop what was typed; the island
    /// closing by itself keeps it for the next "+".
    func closeEventEditor(keepingDraft: Bool) {
        guard isEventEditorOpen else { return }
        stashedEventForm = keepingDraft ? eventForm.flatMap { $0.hasContent ? $0 : nil } : nil
        eventForm = nil
        isEventEditorOpen = false
    }

    // MARK: - Closed island

    /// What the closed island shows on a display with these preferences.
    /// `isHidden` keeps only the notices (D46).
    func closedActivity(for preferences: NookDisplayPreferences, isHidden: Bool = false) -> NookClosedActivity? {
        .resolve(
            transient: transient,
            timerText: timer.closedText,
            timerLeading: .symbol(
                NookPomodoroLook.symbol(for: timer.pomodoro),
                NookPomodoroLook.tint(for: timer.pomodoro)
            ),
            media: closedMediaActivity,
            preferences: preferences,
            isHidden: isHidden
        )
    }

    /// What the Personalization preview draws: music as if it were playing,
    /// with the current album art and GIF.
    func previewClosedActivity(for preferences: NookDisplayPreferences) -> NookClosedActivity? {
        let media = NookClosedMediaActivity(
            artwork: artwork,
            gifURL: gifURL,
            gifScale: gifScale,
            gifOffset: CGSize(width: gifOffsetX, height: gifOffsetY),
            isPlaying: true
        )
        return .resolve(transient: nil, timerText: nil, media: media, preferences: preferences)
    }

    /// Shows a notice in the closed notch for a few seconds. Widgets call
    /// this for chargers, headphones, finished timers and events coming up.
    /// `pops` false changes a notice that is already up without popping
    /// the island again, for a stream of them such as a held volume key.
    /// `level` draws a ring with that number in place of the text.
    func showTransient(
        symbol: String,
        text: String,
        tint: Color = .white,
        level: Int? = nil,
        duration: Duration = .seconds(4),
        pops: Bool = true
    ) {
        transientTask?.cancel()
        transient = NookTransientActivity(symbol: symbol, text: text, tint: tint, level: level)
        if pops { onTransient?() }
        transientTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.transient = nil
        }
    }

    // MARK: - Working with the agents

    /// Plays a system sound unless the island's sound is muted.
    func playSound(_ name: String) {
        guard !isSoundMuted() else { return }
        NotificationSoundService.play(name)
    }

    /// A pomodoro break is not focus time.
    var isFocusModeActive: Bool { timer.isRunning && !timer.isOnBreak }

    /// Completion cards stay quiet during a focus session. Anything that
    /// needs an answer still pops.
    func shouldSuppressNotification(for event: AgentEvent) -> Bool {
        guard case .sessionCompleted = event else { return false }
        if focusSuppressesCompletions, isFocusModeActive { return true }
        if meetingSuppressesCompletions, currentMeeting(now: Date()) != nil { return true }
        return false
    }

    // MARK: - Calendar

    /// The coming week's events on the calendars this display shows.
    var upcomingEvents: [NookCalendarEvent] {
        let hidden = activeDisplay.hiddenCalendarIDs
        return hidden.isEmpty ? calendar.events : calendar.events.filter { !hidden.contains($0.calendarID) }
    }

    /// Events in any range on the calendars this display shows.
    func calendarEvents(from start: Date, to end: Date) -> [NookCalendarEvent] {
        let hidden = activeDisplay.hiddenCalendarIDs
        let all = calendar.events(from: start, to: end)
        return hidden.isEmpty ? all : all.filter { !hidden.contains($0.calendarID) }
    }

    /// The next event the calendar card would list first.
    var nextEvent: NookCalendarEvent? {
        NookCalendarCard.visibleEvents(upcomingEvents, now: Date()).first
    }

    /// A timed event with a meeting link that is on right now.
    func currentMeeting(now: Date) -> NookCalendarEvent? {
        calendar.events.first { !$0.isAllDay && $0.meetingURL != nil && $0.start <= now && $0.end > now }
    }

    /// Works out again which meeting the Join bar offers. The calendar
    /// calls this each minute and whenever its events change. `events` is
    /// this display's coming week unless a caller hands in its own.
    func refreshMeetingPrompt(now: Date, events: [NookCalendarEvent]? = nil) {
        meetingPrompt = NookMeetingPrompt.current(
            events: events ?? upcomingEvents,
            now: now,
            dismissed: dismissedMeetingIDs
        )
    }

    /// Opens the event's meeting link and puts the Join bar away. A link
    /// that is not a known meeting link is never opened.
    func joinMeeting(_ event: NookCalendarEvent) {
        guard let url = event.meetingURL, NookMeetingLink.open(url, using: openURL) else { return }
        dismissMeetingPrompt(for: event)
    }

    /// Puts the Join bar away for this meeting. Its row keeps its join mark.
    func dismissMeetingPrompt(for event: NookCalendarEvent) {
        dismissedMeetingIDs.insert(event.id)
        if meetingPrompt?.id == event.id { meetingPrompt = nil }
    }

    /// Open tasks due on a day, for the styles that mark tasks on dates.
    func tasksDue(on day: Date) -> [NookTodoItem] {
        let cal = Calendar.current
        return todo.source(reminders: reminders).items.filter { item in
            guard !item.isCompleted, let due = item.dueDate else { return false }
            return cal.isDate(due, inSameDayAs: day)
        }
    }

    /// Starts a line for an event in Quick Notes.
    func startNote(for event: NookCalendarEvent) {
        let when = event.isAllDay
            ? event.start.formatted(.dateTime.month(.abbreviated).day())
            : event.start.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        notes.append("\(event.title) (\(when)): ")
        showTransient(symbol: "note.text", text: "Note started", duration: .seconds(3))
    }

    /// Whether the compact bar on the agents page has anything to say.
    var hasCompactBarContent: Bool {
        nowPlaying != nil || timer.closedText != nil || nextEvent != nil || meetingPrompt != nil
            || !tray.items.isEmpty
    }

    // MARK: - Media

    var nowPlaying: NowPlayingState? { media.state }

    /// Album art decoded once per track and reused until the track changes.
    var artwork: NSImage? {
        guard let state = media.state, let data = state.artworkData else { return nil }
        let key = "\(state.itemIdentifier ?? state.title)#\(data.count)"
        if let cached = cachedArtwork, cached.key == key {
            return cached.image
        }
        guard let image = NSImage(data: data) else { return nil }
        cachedArtwork = (key, image)
        return image
    }

    /// Payload for the closed island, or nil when music is not the thing to
    /// show right now.
    var closedMediaActivity: NookClosedMediaActivity? {
        guard isMediaActivityLive, let state = media.state else { return nil }
        return NookClosedMediaActivity(
            artwork: artwork,
            gifURL: gifURL,
            gifScale: gifScale,
            gifOffset: CGSize(width: gifOffsetX, height: gifOffsetY),
            isPlaying: state.isPlaying
        )
    }

    /// Re-registers observation on every change: `withObservationTracking`
    /// fires its `onChange` once per registration.
    private func observePlayback() {
        withObservationTracking {
            _ = media.state?.isPlaying
            _ = media.state == nil
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.playbackDidChange()
                self.observePlayback()
            }
        }
        playbackDidChange()
    }

    private func playbackDidChange() {
        lingerTask?.cancel()
        lingerTask = nil
        guard let state = media.state else {
            isMediaActivityLive = false
            return
        }
        if state.isPlaying {
            isMediaActivityLive = true
            return
        }
        // Paused: keep the art up briefly, then let the notch close back up.
        lingerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.pausedActivityLinger)
            guard !Task.isCancelled else { return }
            self?.isMediaActivityLive = false
        }
    }

    // MARK: - GIF

    /// NotchNook kept custom GIFs under `Application Support/CustomGIF`. If
    /// one is still there and nothing has been chosen yet, reuse it so the
    /// switch-over keeps the look the user already had.
    private static func importedNotchNookGIF() -> URL? {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let dir = support?.appendingPathComponent("CustomGIF", isDirectory: true),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return nil
        }
        let gifs = files.filter { $0.pathExtension.lowercased() == "gif" }
        return gifs.max { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da < db
        }
    }

    func chooseGIF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.gif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Pick a GIF to play next to the notch while music is on."
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            gifURL = url
        }
    }

    func clearGIF() {
        gifURL = nil
    }
}
