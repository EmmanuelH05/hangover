import Foundation
import Observation
import OpenIslandCore

/// The agents the tour offers to connect. The Setup tab lists every agent
/// the app knows; the tour keeps to the common ones and links there.
enum OnboardingAgent: String, CaseIterable, Identifiable, Sendable {
    case claudeCode
    case codex
    case cursor
    case gemini
    case openCode

    var id: String { rawValue }

    /// Product names, which are not translated.
    var name: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .gemini: "Gemini CLI"
        case .openCode: "OpenCode"
        }
    }
}

/// Where one agent stands, as the agents page draws it.
struct OnboardingAgentStatus: Equatable, Sendable {
    var isConnected = false
    var isBusy = false
    /// False while the app cannot install for this agent yet, which is the
    /// case until its hooks helper has been found.
    var canConnect = true
    /// True when Connect was pressed in this tour and the install ended
    /// without the agent being connected.
    var didFail = false
}

/// Everything the pages show that comes from the app. A plain value: the
/// live window reads it from the app model on every draw, and a test or a
/// snapshot hands in a fixed one.
struct OnboardingState: Equatable, Sendable {
    /// The agents switch. Off, the tour leaves its agents page out and
    /// says nothing about agents on the others (D41).
    var agentsEnabled = true
    var openTrigger: IslandOpenTrigger = .hover
    /// True while the real island is open, which is how the tour knows the
    /// user tried it.
    var isIslandOpen = false
    var agents: [OnboardingAgent: OnboardingAgentStatus] = [:]
    /// True when an agent the tour does not list is connected, from the
    /// Setup tab.
    var hasAgentOutsideTour = false
    /// What the right of the closed island shows on the display in use.
    /// Nil for a pick the tour does not offer, made in Settings.
    var closedSide: OnboardingClosedSide? = .count
    /// What the left of the closed island shows on the display in use.
    var closedLeft: OnboardingClosedLeft = .bars
    /// The media style and the switches of Settings' "While music plays"
    /// section on the display in use.
    var closedMusic = OnboardingClosedMusic()
    /// The Nook widgets that are switched on.
    var enabledWidgets: Set<NookWidgetKind> = Set(NookWidgetKind.defaultEnabled)
    /// The widget page of the display in use, in order and with sizes. Nil
    /// draws the page from the template and the widgets that are on, which
    /// is what a snapshot hands in.
    var nookPlacements: [NookWidgetPlacement]?
    var calendarStyle: NookCalendarStyle = .strip
    /// Where the to-do widget gets its tasks.
    var todoSource: NookTodoSourceKind = .reminders
    /// True while that source can show tasks: Reminders was allowed, or
    /// the Notion or TickTick token is in and its list was found.
    var isTodoSourceReady = false
    /// Where the connecting of that source stands (D44). The secret is not
    /// part of it.
    var todoSetup = OnboardingTodoSetup()
    /// Where quick notes go.
    var notesDestination: NookNotesDestination = .file
    /// The Markdown file notes go to, as the page prints it.
    var notesFilePath = ""
    /// How many notes the app has saved since it started. The tour compares
    /// it with the count when the notes page came up.
    var notesSavedCount = 0
    /// True once a note was saved while the notes page was up. Set by the
    /// tour, which is the one that knows when the page came up.
    var hasSavedNote = false
    /// Where the user is, for the weather card (D44).
    var weather = OnboardingWeatherSetup()
    /// The layout template the display in use is on, if any.
    var appliedTemplate: PersonalizationTemplate.ID?
    /// The template picked in this tour. It stays the user's pick after a
    /// glow of their own is chosen, which Settings would call a setup of
    /// their own.
    var pickedTemplate: PersonalizationTemplate.ID?
    /// True when a template was picked in this tour over a layout of the
    /// user's own, which the tour can put back.
    var canKeepOwnLayout = false
    /// The page the user's own layout makes, held by the tour while a
    /// template is on. Nil while the display is on its own layout, or when
    /// the app hands in nothing.
    var ownPlacements: [NookWidgetPlacement]?
    var glowStyle: IslandHaloStyle = .subtle
    /// The glow's colors on the display in use.
    var glowPalette: IslandHaloPalette = .standard
    /// The glow theme the display's colors equal, nil for colors of the
    /// user's own or one color for everything.
    var glowThemeID: String?
    /// How the opened island looks on the display in use.
    var openedLook = IslandOpenedLook.standard
    /// The kind of display the island is on, which the look's pictures
    /// are drawn for.
    var displayProfile: IslandAppearanceDisplayProfile = .notch
    /// True once the real island was open while this tour was up. It stays
    /// true after the island closes.
    var hasOpenedIsland = false
    /// True while the real island is in widget editing (D44).
    var isEditingWidgets = false
    /// What the features page's buttons read from the app (D47).
    var features = OnboardingFeatureReading()
    /// The widget the features page shows. Nil until the page picks the
    /// first one on the user's page.
    var featureKind: NookWidgetKind?
    /// What the features page has seen happen since it came up.
    var featureProgress = OnboardingFeatureProgress()
    /// The widget the arrange page was asked to teach with, and what the
    /// page looked like then. Nil until one is picked, and off that page.
    var arrangePick: OnboardingArrangePick?
    /// The widget page when the arrange page came up, which its reset
    /// button puts back. Nil off that page.
    var arrangeStart: [NookWidgetPlacement]?
    /// The approve shortcut as key caps, such as control, option, Y. Nil
    /// while that shortcut is switched off.
    var approveKeys: [String]?
    var denyKeys: [String]?

    func status(of agent: OnboardingAgent) -> OnboardingAgentStatus {
        agents[agent] ?? OnboardingAgentStatus()
    }

    /// The template the pages show as chosen: the one the display is on
    /// right now, or the one picked in this tour when a later choice, such
    /// as a glow, made the display match none.
    var shownTemplate: PersonalizationTemplate.ID? { appliedTemplate ?? pickedTemplate }

    /// The widget page the tour draws: the display's own, or the shown
    /// template's widgets that are switched on, or the app's starting page.
    var shownPlacements: [NookWidgetPlacement] {
        if let nookPlacements { return nookPlacements }
        if let id = shownTemplate, let template = PersonalizationTemplate.all.first(where: { $0.id == id }) {
            return template.widgets.filter { enabledWidgets.contains($0.kind) }
        }
        return NookDisplayPreferences().placements(enabled: Array(enabledWidgets))
    }

    /// The page the "Keep mine" card draws: the display's own while it is on
    /// no template, else the one the tour holds, else the app's starting page.
    var ownLayoutPlacements: [NookWidgetPlacement] {
        if shownTemplate == nil { return shownPlacements }
        return ownPlacements ?? NookDisplayPreferences().placements(enabled: Array(enabledWidgets))
    }

    /// What the arrange page shows for the picked widget. Nil until one is
    /// picked.
    var arrangeProgress: OnboardingArrangeProgress? {
        arrangePick.map {
            .reading(
                picked: $0.kind,
                atPick: $0.atPick,
                now: shownPlacements,
                isEditing: isEditingWidgets,
                editingEnded: $0.hasEndedEditing
            )
        }
    }

    /// The features page's list: the widgets on the page, in order, and the
    /// one shown.
    var featureWalk: OnboardingFeatureWalk {
        OnboardingFeatureWalk(kinds: shownPlacements.map(\.kind), current: featureKind)
    }

    /// True once the app showed a "Try it" done. The notes step is the
    /// notes page's: a note saved while the page was up.
    func isDone(_ step: OnboardingTry) -> Bool {
        step == .notesLine ? hasSavedNote : featureProgress.done.contains(step)
    }

    /// True while a widget is on the page the tour draws.
    func showsWidget(_ kind: NookWidgetKind) -> Bool {
        shownPlacements.contains { $0.kind == kind }
    }

    /// The agents that are connected, in the order the tour lists them.
    var connectedAgents: [OnboardingAgent] {
        OnboardingAgent.allCases.filter { status(of: $0).isConnected }
    }
}

/// What a click in the tour can do to the app. Each one runs only from a
/// button the user pressed. Only `allowReminders` asks macOS for a
/// permission, from the button on the to-dos page that says macOS will ask
/// (D44). Apple Notes asks by itself when the first note is saved, in the
/// island, and not from any button here.
@MainActor
struct OnboardingActions {
    /// The agents switch on the first page. It writes the same preference
    /// as the one in Settings.
    var setAgentsEnabled: (Bool) -> Void = { _ in }
    var setOpenTrigger: (IslandOpenTrigger) -> Void = { _ in }
    var setClosedSide: (OnboardingClosedSide) -> Void = { _ in }
    var setClosedLeft: (OnboardingClosedLeft) -> Void = { _ in }
    var setClosedMusic: (OnboardingClosedMusicPick) -> Void = { _ in }
    var connect: (OnboardingAgent) -> Void = { _ in }
    /// Opens Settings on the Setup tab, where every agent is listed.
    var showAllAgents: () -> Void = {}
    var setWidget: (_ kind: NookWidgetKind, _ isEnabled: Bool) -> Void = { _, _ in }
    /// Picks where the to-do widget gets its tasks. The same preference as
    /// the Source picker in Settings.
    var setTodoSource: (NookTodoSourceKind) -> Void = { _ in }
    /// Opens the page a source's token is made on, in the browser.
    var openTodoSetupPage: (NookTodoSourceKind) -> Void = { _ in }
    /// Opens Settings on the Nook tab at its to-do section, where a token
    /// is pasted. The tour takes no token itself.
    var showTodoSettings: () -> Void = {}
    /// Connects the picked source with the secret the page's field held.
    /// The tour passes it straight through and keeps nothing.
    var connectTodo: (_ token: String) -> Void = { _ in }
    /// Loads the databases or the lists again.
    var checkTodoAgain: () -> Void = {}
    /// Picks a database or a list by its ID.
    var chooseTodo: (_ id: String) -> Void = { _ in }
    /// Asks macOS for Reminders access. Runs only from the page's button.
    var allowReminders: () -> Void = {}
    /// Opens System Settings at the Reminders privacy list.
    var openRemindersSettings: () -> Void = {}
    /// Picks where quick notes go. The preference Settings writes.
    var setNotesDestination: (NookNotesDestination) -> Void = { _ in }
    /// Opens the system folder chooser and saves the pick as the notes
    /// folder. The panel is the app's, not the page's.
    var chooseNotesFolder: () -> Void = {}
    /// Shows the notes file in Finder, or opens Notes.
    var showNotes: () -> Void = {}
    /// Looks a typed city up. The search Settings runs.
    var searchWeather: (String) -> Void = { _ in }
    /// Saves a found place as the city. The call Settings makes on a pick.
    var chooseWeatherPlace: (NookWeatherPlace) -> Void = { _ in }
    /// Writes the temperature unit, as the picker in Settings does.
    var setWeatherUnit: (NookTemperatureUnit) -> Void = { _ in }
    var applyTemplate: (PersonalizationTemplate) -> Void = { _ in }
    /// Puts back the layout the display had before a template was picked
    /// in this tour.
    var keepOwnLayout: () -> Void = {}
    var setGlowStyle: (IslandHaloStyle) -> Void = { _ in }
    var setGlowTheme: (IslandHaloTheme) -> Void = { _ in }
    var setOpenedWidth: (IslandOpenedWidth) -> Void = { _ in }
    var setOpenedCorners: (IslandOpenedCorners) -> Void = { _ in }
    /// Holds the real island open on the Nook page, or lets it go (D44).
    /// The tour calls it from its own moves and nowhere else: on while a
    /// live page is up, off on every other page and when the tour ends.
    var holdIsland: (Bool) -> Void = { _ in }
    /// Puts the display's widget page back as the arrange page found it.
    var restorePlacements: ([NookWidgetPlacement]) -> Void = { _ in }
    /// Starts or ends widget editing on the real island: what a long press
    /// on a widget and the Done button do. The tour starts it when a widget
    /// is picked and ends it on every way out of the page.
    var setEditingWidgets: (Bool) -> Void = { _ in }
    /// Rings a widget's tile in the real island, or none with nil. The
    /// tour sets it with a pick and clears it on every way out.
    var outlineWidget: (NookWidgetKind?) -> Void = { _ in }
    /// The arrange page's buttons. The tour answers them with the page it
    /// kept; the app never sees these.
    var pickArrangeWidget: (NookWidgetKind) -> Void = { _ in }
    var tryAnotherWidget: () -> Void = {}
    var resetArrangement: () -> Void = {}
    /// The features page's buttons (D47). Each is the call the widget's own
    /// button makes, and none raises a macOS prompt except `setMirror`
    /// (the camera) and `showCalendar`, whose notes name the prompt first.
    /// Turns the mirror's camera on or off, as the Mirror tile does.
    var setMirror: (Bool) -> Void = { _ in }
    /// Switches the mirror's ring light, as its bulb button does.
    var setRingLight: (Bool) -> Void = { _ in }
    /// Starts the photo booth, as the mirror's camera button does.
    var openPhotoBooth: () -> Void = {}
    /// The music card's play and pause button.
    var playOrPause: () -> Void = {}
    /// The music card's next track button.
    var nextTrack: () -> Void = {}
    /// Starts a one-off countdown of that many seconds.
    var startTimer: (TimeInterval) -> Void = { _ in }
    /// Stops the focus timer, as its reset button does.
    var stopTimer: () -> Void = {}
    /// Copies a sentence through the tray's own clipboard door, which the
    /// clipboard list then shows if its tab is on.
    var copySampleLine: (String) -> Void = { _ in }
    /// Lets the calendar ask macOS for access. The one call that can raise
    /// the Calendar prompt, from the button that names it.
    var showCalendar: () -> Void = {}
    /// The features page's next and previous widget. The tour answers them
    /// with the walk it kept; the app never sees these.
    var nextFeature: () -> Void = {}
    var previousFeature: () -> Void = {}
}

/// What the user chose in one run of the tour, kept by the tour itself.
/// It is what lets a choice on one page survive a choice on another: a
/// template sets a glow style and a closed island of its own, and the ones
/// picked here are put back after it.
struct OnboardingPicks: Equatable, Sendable {
    var template: PersonalizationTemplate.ID?
    /// True once a template was picked over a layout that was on none.
    var hasOwnLayout = false
    var glowStyle: IslandHaloStyle?
    var closedSide: OnboardingClosedSide?
    var closedLeft: OnboardingClosedLeft?
    /// The last media style and switch values picked on the closed page.
    var musicStyle: NookClosedMediaStyle?
    var musicOptions: [NookClosedMusicOption: Bool] = [:]
    /// Agents whose Connect button was pressed.
    var connectAttempts: Set<OnboardingAgent> = []
}

extension OnboardingPicks {
    /// Notes a pick on the music group. A later pick of the same thing wins.
    mutating func keep(_ pick: OnboardingClosedMusicPick) {
        switch pick {
        case .style(let style): musicStyle = style
        case .option(let option, let isOn): musicOptions[option] = isOn
        }
    }

    /// The picks to write again, the style first: a switch is only
    /// meaningful against the style it was picked for.
    var musicPicks: [OnboardingClosedMusicPick] {
        let style = musicStyle.map { [OnboardingClosedMusicPick.style($0)] } ?? []
        let options = NookClosedMusicOption.allCases.compactMap { option in
            musicOptions[option].map { OnboardingClosedMusicPick.option(option, isOn: $0) }
        }
        return style + options
    }
}

/// One run of the welcome tour: its flow, where it reads the app's state
/// from and what its buttons do.
@MainActor
@Observable
final class OnboardingTour {
    private(set) var flow: OnboardingFlow
    /// What was chosen in this run. The pages read it through `state`.
    private(set) var picks = OnboardingPicks()

    @ObservationIgnored private let readState: () -> OnboardingState
    /// The doors into the app, as they were handed in.
    @ObservationIgnored private let appActions: OnboardingActions
    /// Set the first time the real island is seen open, and never cleared.
    @ObservationIgnored private var hasSeenIslandOpen = false
    /// True while this tour has asked the app to hold the island open.
    @ObservationIgnored private var holdsIsland = false
    /// Whether Hangover is the active app and the tour window can be seen.
    /// The window controller keeps both current (`setPresence`).
    @ObservationIgnored private var appIsActive = true
    @ObservationIgnored private var windowIsVisible = true
    /// The widget page when the arrange page came up. Reset when the page
    /// goes.
    @ObservationIgnored private var arrangeStart: [NookWidgetPlacement]?
    /// The widget the arrange page teaches with. Observed: a pick changes
    /// the page even when the island was already editing.
    private var arrangePick: OnboardingArrangePick?
    /// Whether the island has been seen editing since the pick, and whether
    /// editing ended after that. Read off the island on each draw.
    @ObservationIgnored private var hasSeenEditing = false
    @ObservationIgnored private var hasEndedEditing = false
    /// How many notes were saved when the notes or the features page came
    /// up. Nil off those pages.
    @ObservationIgnored private var notesBaseline: Int?
    /// The widget the features page shows (D47). Observed: next and previous
    /// change the page.
    private var featureKind: NookWidgetKind?
    /// True from the moment the features page rang its first widget until
    /// every way out of the page let go of it.
    @ObservationIgnored private var featuresActive = false
    /// What the features page has seen done since it came up.
    @ObservationIgnored private var featureProgress = OnboardingFeatureProgress()
    /// What a "Try it" switched on, which the clean-up switches off.
    @ObservationIgnored private var trials = OnboardingTrials()
    /// Runs once, when the tour ends by its last button, by Skip or by its
    /// window closing.
    @ObservationIgnored private let onEnd: (OnboardingOutcome) -> Void

    init(
        startingAt page: OnboardingPage = .welcome,
        state: @escaping () -> OnboardingState,
        actions: OnboardingActions = OnboardingActions(),
        onEnd: @escaping (OnboardingOutcome) -> Void = { _ in }
    ) {
        flow = OnboardingFlow(startingAt: page, pages: Self.pages(for: state()))
        readState = state
        appActions = actions
        self.onEnd = onEnd
    }

    /// The pages this run walks, read from the app as it is now. The agents
    /// switch and the to-do widget can change under the tour, from its own
    /// pages or from Settings.
    var pages: [OnboardingPage] { Self.pages(for: readState()) }

    static func pages(for state: OnboardingState) -> [OnboardingPage] {
        OnboardingPage.shown(
            agentsEnabled: state.agentsEnabled,
            hasTodoWidget: state.showsWidget(.todo),
            hasNotesWidget: state.showsWidget(.notes),
            hasWeatherWidget: state.showsWidget(.weather)
        )
    }

    /// The page that is up. One the switch has just taken out gives way to
    /// the page before it.
    var page: OnboardingPage { OnboardingPage.landing(flow.page, in: pages) }
    var isFirstPage: Bool { page == pages.first }
    var isLastPage: Bool { page == pages.last }

    /// The app's state with this run's picks laid over it. What the state
    /// already says about a pick, a failure or the island having been
    /// opened is kept, which lets a snapshot hand in a fixed one.
    var state: OnboardingState {
        var state = readState()
        if state.isIslandOpen { hasSeenIslandOpen = true }
        state.hasOpenedIsland = state.hasOpenedIsland || hasSeenIslandOpen
        trackArrange(in: state)
        // A state handed in with a pick, as a snapshot does, is kept.
        if page == .arrange, let pick = arrangePick {
            state.arrangePick = OnboardingArrangePick(kind: pick.kind, atPick: pick.atPick, hasEndedEditing: hasEndedEditing)
        }
        trackNotes(in: state)
        trackFeatures(in: state)
        state.featureKind = featureKind ?? state.featureKind
        state.featureProgress = state.featureProgress.merged(with: featureProgress)
        state.hasSavedNote = state.hasSavedNote || notesBaseline.map { state.notesSavedCount > $0 } ?? false
        state.arrangeStart = state.arrangeStart ?? arrangeStart
        state.pickedTemplate = picks.template ?? state.pickedTemplate
        state.canKeepOwnLayout = state.canKeepOwnLayout || picks.hasOwnLayout
        for agent in picks.connectAttempts {
            var status = state.status(of: agent)
            status.didFail = !status.isConnected && !status.isBusy
            state.agents[agent] = status
        }
        return state
    }

    /// What the pages' buttons call. Each one goes through to the app, and
    /// some of them also keep a note of the pick.
    var actions: OnboardingActions {
        var actions = appActions
        actions.connect = { [weak self, appActions] agent in
            self?.picks.connectAttempts.insert(agent)
            appActions.connect(agent)
        }
        actions.applyTemplate = { [weak self, appActions, readState] template in
            let wasOnNoTemplate = readState().appliedTemplate == nil
            appActions.applyTemplate(template)
            guard let self else { return }
            if picks.template == nil, wasOnNoTemplate { picks.hasOwnLayout = true }
            picks.template = template.id
            putPicksBack()
        }
        actions.keepOwnLayout = { [weak self, appActions] in
            appActions.keepOwnLayout()
            guard let self else { return }
            picks.template = nil
            picks.hasOwnLayout = false
            putPicksBack()
        }
        actions.setClosedSide = { [weak self, appActions] side in
            self?.picks.closedSide = side
            appActions.setClosedSide(side)
        }
        actions.setClosedLeft = { [weak self, appActions] left in
            self?.picks.closedLeft = left
            appActions.setClosedLeft(left)
        }
        actions.setClosedMusic = { [weak self, appActions] pick in
            self?.picks.keep(pick)
            appActions.setClosedMusic(pick)
        }
        actions.setGlowStyle = { [weak self, appActions] style in
            self?.picks.glowStyle = style
            appActions.setGlowStyle(style)
        }
        // What a try-it switches on is noted, so that leaving puts it back.
        // A thing that was already on is not noted, and is left alone.
        actions.setMirror = { [weak self, appActions, readState] isOn in
            if isOn, !readState().features.isMirrorOn { self?.trials.mirror = true }
            appActions.setMirror(isOn)
        }
        actions.setRingLight = { [weak self, appActions, readState] isOn in
            if isOn, !readState().features.isRingLightOn { self?.trials.ringLight = true }
            appActions.setRingLight(isOn)
        }
        actions.startTimer = { [weak self, appActions, readState] length in
            if !readState().features.isTimerActive { self?.trials.timer = true }
            appActions.startTimer(length)
        }
        actions.nextFeature = { [weak self] in self?.showFeature(self?.currentWalk.next) }
        actions.previousFeature = { [weak self] in self?.showFeature(self?.currentWalk.previous) }
        actions.pickArrangeWidget = { [weak self] in self?.pickArrangeWidget($0) }
        actions.tryAnotherWidget = { [weak self] in self?.endArrange() }
        actions.resetArrangement = { [weak self, appActions] in
            guard let self, let start = arrangeStart else { return }
            appActions.restorePlacements(start)
            // Back to the pick, with the editing and the ring let go.
            endArrange()
        }
        return actions
    }

    /// Holds the real island open while a live page is up and Hangover is
    /// the active app, and lets it go on every other page, while the user is
    /// in another app and once the tour has ended (D44). Safe to call any
    /// number of times: the app is told only when the answer changes.
    func syncIsland() {
        let holds = !flow.hasEnded && OnboardingIslandHold.holds(
            isLivePage: page.isLive,
            appIsActive: appIsActive,
            windowIsVisible: windowIsVisible
        )
        if holds, page == .features { enterFeatures() }
        guard holds != holdsIsland else { return }
        holdsIsland = holds
        if !holds {
            endArrange()
            endFeatures()
        }
        appActions.holdIsland(holds)
    }

    /// Tells the tour whether Hangover is the active app and its window can
    /// be seen, and lets the hold follow. Leaving the app lets the island go;
    /// coming back with a live page up holds it again.
    func setPresence(appIsActive: Bool, windowIsVisible: Bool) {
        self.appIsActive = appIsActive
        self.windowIsVisible = windowIsVisible
        syncIsland()
    }

    /// Lets the island go whatever page is up. The window calls it on every
    /// way it can go away, as a second guard behind the tour's own end.
    func releaseIsland() {
        endArrange()
        endFeatures()
        guard holdsIsland else { return }
        holdsIsland = false
        appActions.holdIsland(false)
    }

    /// Keeps the arrange page's starting point and what the island did
    /// since the pick: taken when the page is up, dropped when it is not.
    /// It reads and notes; the editing and the ring are let go by
    /// `endArrange`, which never runs from a draw.
    private func trackArrange(in state: OnboardingState) {
        guard page == .arrange, !flow.hasEnded else {
            arrangeStart = nil
            return
        }
        if arrangeStart == nil { arrangeStart = state.arrangeStart ?? state.shownPlacements }
        guard arrangePick != nil else { return }
        if state.isEditingWidgets {
            hasSeenEditing = true
        } else if hasSeenEditing {
            hasEndedEditing = true
        }
    }

    /// A widget picked on the arrange page: the island starts editing by
    /// itself and the widget's tile is ringed so it can be found.
    private func pickArrangeWidget(_ kind: NookWidgetKind) {
        guard page == .arrange, !flow.hasEnded else { return }
        let placements = readState().shownPlacements
        guard placements.contains(where: { $0.kind == kind }) else { return }
        arrangePick = OnboardingArrangePick(kind: kind, atPick: placements)
        hasSeenEditing = false
        hasEndedEditing = false
        appActions.setEditingWidgets(true)
        appActions.outlineWidget(kind)
    }

    /// Lets go of what a pick started: the ring, the editing and the pick
    /// itself. Every way out of the arrange page runs it: Try another, Put
    /// it back, a move to another page, the end of the tour, the window
    /// closing and the hold going off.
    private func endArrange() {
        guard arrangePick != nil else { return }
        arrangePick = nil
        hasSeenEditing = false
        hasEndedEditing = false
        appActions.outlineWidget(nil)
        appActions.setEditingWidgets(false)
    }

    /// Keeps the count of saved notes from when the notes page or the
    /// features page came up, dropped when neither is up.
    private func trackNotes(in state: OnboardingState) {
        guard page == .notes || page == .features, !flow.hasEnded else {
            notesBaseline = nil
            return
        }
        if notesBaseline == nil { notesBaseline = state.notesSavedCount }
    }

    // MARK: The features page (D47)

    /// The list of the features page as it stands now.
    private var currentWalk: OnboardingFeatureWalk {
        OnboardingFeatureWalk(kinds: readState().shownPlacements.map(\.kind), current: featureKind)
    }

    /// Notes what the app shows while the features page is up, and starts
    /// over when it is not. It reads and notes; the ring and the clean-up
    /// are never touched from a draw.
    private func trackFeatures(in state: OnboardingState) {
        guard page == .features, !flow.hasEnded else {
            featureProgress = OnboardingFeatureProgress()
            return
        }
        featureProgress.note(state.features)
    }

    /// The page came up with the island held: the first widget on the page
    /// is shown and ringed. Safe to call any number of times.
    private func enterFeatures() {
        guard !featuresActive, !flow.hasEnded else { return }
        featuresActive = true
        featureKind = currentWalk.current
        // What was already running is the user's, from the first look.
        featureProgress.note(readState().features)
        appActions.outlineWidget(featureKind)
    }

    /// Next or previous widget. What the widget being left switched on is
    /// switched off first, and the ring moves to the new one.
    private func showFeature(_ kind: NookWidgetKind?) {
        guard featuresActive, !flow.hasEnded, let kind else { return }
        releaseTrials(leaving: currentWalk.current)
        featureKind = kind
        appActions.outlineWidget(kind)
    }

    /// Lets go of everything the features page started: the camera, the ring
    /// light and a timer the tour switched on, and the ring on the island.
    /// Every way out of the page runs it: Next, Back, a dot, Skip,
    /// finishing, the window closing (`releaseIsland`) and the hold going
    /// off.
    private func endFeatures() {
        releaseTrials(leaving: nil)
        guard featuresActive else { return }
        featuresActive = false
        featureKind = nil
        appActions.outlineWidget(nil)
    }

    /// Switches off what the tour switched on for the widget being left, or
    /// for every widget with nil. The ring light goes before the mirror. A
    /// thing the user had on before the tour touched it was never noted, and
    /// stays.
    private func releaseTrials(leaving kind: NookWidgetKind?) {
        for release in trials.releases(leaving: kind, reading: readState().features) {
            switch release {
            case .ringLightOff: appActions.setRingLight(false)
            case .mirrorOff: appActions.setMirror(false)
            case .timerOff: appActions.stopTimer()
            }
        }
        trials = trials.after(leaving: kind)
    }

    isolated deinit {
        releaseIsland()
    }

    /// A template, and the layout from before it, carry a glow style and a
    /// closed island (both sides) of their own. The ones picked on other pages of this
    /// tour are the user's and come back.
    private func putPicksBack() {
        if let style = picks.glowStyle { appActions.setGlowStyle(style) }
        if let side = picks.closedSide { appActions.setClosedSide(side) }
        if let left = picks.closedLeft { appActions.setClosedLeft(left) }
        for pick in picks.musicPicks { appActions.setClosedMusic(pick) }
    }

    func next() { move { $0.next() } }
    func back() { move { $0.back() } }
    func skip() { move { $0.skip() } }
    func go(to page: OnboardingPage) { move { $0.go(to: page) } }

    private func move(_ change: (inout OnboardingFlow) -> Void) {
        let hadEnded = flow.hasEnded
        // The flow walks the pages the agents switch leaves in right now.
        let pages = pages
        if flow.pages != pages { flow.pages = pages }
        change(&flow)
        if page != .arrange || flow.hasEnded { endArrange() }
        if page != .features || flow.hasEnded { endFeatures() }
        trackArrange(in: readState())
        trackNotes(in: readState())
        // The hold goes before the end is recorded and the window closed.
        syncIsland()
        if !hadEnded, let outcome = flow.outcome {
            onEnd(outcome)
        }
    }
}

extension OnboardingTour {
    /// A tour whose end is put on record in `store` before `close` runs.
    /// Finishing, skipping and closing are recorded alike, and that record
    /// is what keeps the tour from coming up by itself again.
    static func recording(
        in store: AgentIntentStore,
        startingAt page: OnboardingPage = .welcome,
        state: @escaping () -> OnboardingState,
        actions: OnboardingActions = OnboardingActions(),
        close: @escaping @MainActor () -> Void = {}
    ) -> OnboardingTour {
        OnboardingTour(startingAt: page, state: state, actions: actions) { _ in
            store.welcomeTourEnded = true
            store.firstLaunchCompleted = true
            close()
        }
    }
}

/// Spells a shortcut out as the words printed on the keys. The symbols
/// macOS menus use are hard to read for anyone who has not learned them.
enum OnboardingShortcutWords {
    static func caps(for combo: AgentHotkeyCombo, keyName: (UInt16) -> String?) -> [String] {
        var caps: [String] = []
        if combo.modifiers.contains(.control) { caps.append("control") }
        if combo.modifiers.contains(.option) { caps.append("option") }
        if combo.modifiers.contains(.shift) { caps.append("shift") }
        if combo.modifiers.contains(.command) { caps.append("command") }
        caps.append(keyName(combo.keyCode) ?? "Key \(combo.keyCode)")
        return caps
    }
}
