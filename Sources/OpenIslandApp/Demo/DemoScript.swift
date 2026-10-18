import Foundation

/// One thing a demo script does (D51). Each case is named after the door it
/// calls: the same function the app's own control calls, and never a private
/// shortcut that would skip an animation. `DemoDoors` carries them out.
enum DemoAction: Equatable, Sendable {
    // The island
    case openIsland
    case closeIsland
    // Music
    case playOrPause
    case nextTrack
    case previousTrack
    /// The shuffle and repeat buttons, drawn in the dev copy.
    case toggleShuffle
    case cycleRepeat
    // To-dos and notes
    case checkOffTodo(position: Int)
    case addTodo(String)
    case saveNote(String)
    /// Clicks into the field, types the text one key at a time and presses
    /// Return, through the field's own draft and submit (D65). A note has no
    /// Return: `typeNote` opens a new note with the New note button, types
    /// into the editor, and its last beat is the one in which the note saves.
    case typeTodo(String)
    case typeNote(String)
    // The timer
    case startTimer(minutes: Int)
    case stopTimer
    // Layouts and editing
    case applyTemplate(PersonalizationTemplate.ID)
    case undoTemplate
    case beginEditing
    case endEditing
    case moveWidget(NookWidgetKind, to: Int)
    case resizeWidget(NookWidgetKind, NookWidgetSize)
    case addWidget(NookWidgetKind)
    // Looks
    case setCalendarLook(NookCalendarStyle)
    case setWeatherMode(NookWeatherForecastMode)
    // The closed island
    case chooseRightSide(OnboardingClosedSide)
    case chooseLeftSide(OnboardingClosedLeft)
    case setGlow(IslandHaloStyle)
    case showChargingNotice
    case showCalendarNotice
    // The welcome tour
    case openTour
    case tourNext
    case tourChooseLength(OnboardingLength)
    case tourSetWidget(NookWidgetKind, isOn: Bool)
    case tourNextFeature
    case tourTry(OnboardingTry)
    case tourSetCalendarLook(NookCalendarStyle)
    case tourApplyTemplate(PersonalizationTemplate.ID)
    case tourPickWidget(NookWidgetKind)
    case tourMoveWidget(NookWidgetKind, to: Int)
    case tourPutBack
    /// Straight to a page, the way the island's hint turns the tour to one.
    /// A page of a longer tour lengthens the tour.
    case tourGo(OnboardingPage)
    /// A switch on a Good to know page.
    case tourSetMore(OnboardingMoreSwitch, isOn: Bool)
    // The design kit
    case designTab(NookDesignTab)
    case copySwatch(position: Int)
    case toggleKeepPicking
    /// Types a color into the large card's field, one key at a time, with
    /// no Return. `addTypedColor` presses the Add pill after it.
    case typeColor(String)
    case addTypedColor

    /// The step's name in the line the runner prints.
    var name: String {
        switch self {
        case .openIsland: "open-island"
        case .closeIsland: "close-island"
        case .playOrPause: "play-pause"
        case .nextTrack: "next-track"
        case .previousTrack: "previous-track"
        case .toggleShuffle: "shuffle"
        case .cycleRepeat: "repeat"
        case .checkOffTodo(let position): "check-off-todo-\(position + 1)"
        case .addTodo: "add-todo"
        case .saveNote: "save-note"
        case .typeTodo: "type-todo"
        case .typeNote: "type-note"
        case .startTimer(let minutes): "start-timer-\(minutes)"
        case .stopTimer: "stop-timer"
        case .applyTemplate(let id): "template-\(id.rawValue)"
        case .undoTemplate: "template-undo"
        case .beginEditing: "editing-begin"
        case .endEditing: "editing-end"
        case .moveWidget(let kind, let index): "move-\(kind.rawValue)-to-\(index)"
        case .resizeWidget(let kind, let size): "resize-\(kind.rawValue)-\(size.rawValue)"
        case .addWidget(let kind): "add-\(kind.rawValue)"
        case .setCalendarLook(let style): "calendar-look-\(style.rawValue)"
        case .setWeatherMode(let mode): "weather-\(mode.rawValue)"
        case .chooseRightSide(let side): "right-side-\(side.rawValue)"
        case .chooseLeftSide(let side): "left-side-\(side.rawValue)"
        case .setGlow(let style): "glow-\(style.rawValue)"
        case .showChargingNotice: "notice-charging"
        case .showCalendarNotice: "notice-calendar"
        case .openTour: "tour-open"
        case .tourNext: "tour-next"
        case .tourChooseLength(let length): "tour-length-\(length.rawValue)"
        case .tourSetWidget(let kind, let isOn): "tour-widget-\(kind.rawValue)-\(isOn ? "on" : "off")"
        case .tourNextFeature: "tour-next-feature"
        case .tourTry(let step): "tour-try-\(step.rawValue)"
        case .tourSetCalendarLook(let style): "tour-calendar-look-\(style.rawValue)"
        case .tourApplyTemplate(let id): "tour-template-\(id.rawValue)"
        case .tourPickWidget(let kind): "tour-pick-\(kind.rawValue)"
        case .tourMoveWidget(let kind, let index): "tour-move-\(kind.rawValue)-to-\(index)"
        case .tourPutBack: "tour-put-back"
        case .tourGo(let page): "tour-go-\(page.rawValue)"
        case .tourSetMore(let item, let isOn): "tour-more-\(item.rawValue)-\(isOn ? "on" : "off")"
        case .designTab(let tab): "design-tab-\(tab.rawValue)"
        case .copySwatch(let position): "copy-swatch-\(position + 1)"
        case .toggleKeepPicking: "keep-pill"
        case .typeColor: "type-color"
        case .addTypedColor: "add-color"
        }
    }

    /// The function the step calls, in words. A script is plain values, and
    /// this is what keeps every step tied to a door.
    var door: String {
        switch self {
        case .openIsland: "AppModel.perform(.openNook), the link's own action"
        case .closeIsland: "AppModel.notchClose()"
        case .playOrPause: "MediaRemoteService.togglePlayPause(), the play button"
        case .nextTrack: "MediaRemoteService.nextTrack(), the forward button"
        case .previousTrack: "MediaRemoteService.previousTrack(), the back button"
        case .toggleShuffle: "MediaRemoteService.toggleShuffle(), the shuffle button"
        case .cycleRepeat: "MediaRemoteService.cycleRepeat(), the repeat button"
        case .checkOffTodo: "NookTodoSource.complete(_:), the row's check"
        case .addTodo: "NookTodoSource.add(_:), the add field"
        case .saveNote: "NookNotesStore.beginNewNote(), edit(_:) and closeEditor(), the New note button"
        case .typeTodo: "NookTodoCard's draft and its Return, the add field"
        case .typeNote: "NookNotesStore.beginNewNote(), the New note button, then the editor's text"
        case .startTimer: "AppModel.perform(.startTimer), the link's own action"
        case .stopTimer: "AppModel.perform(.stopTimer), the link's own action"
        case .applyTemplate: "AppModel.applyTemplate(_:for:), the template card"
        case .undoTemplate: "AppModel.undoTemplate(for:), the undo link"
        case .beginEditing: "NookModel.isEditingLayout, the long press"
        case .endEditing: "NookModel.isEditingLayout, the Done button"
        case .moveWidget: "NookModel.moveWidget(_:to:for:), where a drag ends"
        case .resizeWidget: "NookModel.setWidgetSize(_:_:for:), where a resize drag ends"
        case .addWidget: "NookModel.addWidget(_:at:for:), the shelf's chip"
        case .setCalendarLook: "NookModel.updateDisplayPreferences, the look picker"
        case .setWeatherMode: "NookWeatherService.forecastMode, the card's switch"
        case .chooseRightSide: "AppModel.chooseClosedSide(_:), the closed page's card"
        case .chooseLeftSide: "AppModel.chooseClosedLeft(_:), the closed page's card"
        case .setGlow: "NookModel.updateDisplayPreferences, the glow picker"
        case .showChargingNotice: "NookPowerMonitor.showPower(_:), a charger going in"
        case .showCalendarNotice: "NookCalendarService.checkNextUp(now:), the minute tick"
        case .openTour: "AppModel.showWelcomeTour()"
        case .tourNext: "OnboardingTour.next(), the Next button"
        case .tourChooseLength: "OnboardingActions.chooseLength, the question page's card"
        case .tourSetWidget: "OnboardingActions.setWidget, the widgets page's switch"
        case .tourNextFeature: "OnboardingActions.nextFeature, the features page's arrow"
        case .tourTry: "OnboardingTry.press(reading:sample:actions:), a Try it button"
        case .tourSetCalendarLook: "OnboardingActions.setCalendarStyle, a look card"
        case .tourApplyTemplate: "OnboardingActions.applyTemplate, a template card"
        case .tourPickWidget: "OnboardingActions.pickArrangeWidget, the arrange page's card"
        case .tourMoveWidget: "NookModel.moveWidget(_:to:for:), where a drag ends"
        case .tourPutBack: "OnboardingActions.resetArrangement, the Put it back button"
        case .tourGo: "OnboardingTour.show(_:), the island's hint and a progress dot"
        case .tourSetMore: "OnboardingActions.setMore, a Good to know page's switch"
        case .designTab: "NookDesignKit.tab, the card's tab name"
        case .copySwatch: "NookDesignKit.copy(_:from:), a swatch"
        case .toggleKeepPicking: "NookDesignKit.toggleKeepsPicking(), the pill"
        case .typeColor: "NookDesignQuickAdd's draft, the color field"
        case .addTypedColor: "NookDesignQuickAdd's add, the Add pill"
        }
    }

    /// The field a typing step types into, the text and whether it ends
    /// with Return. Nil for every other step.
    var typing: DemoTypingRun? {
        switch self {
        case .typeTodo(let text): DemoTypingRun(field: .todo, text: text, pressesReturn: true)
        case .typeNote(let text): DemoTypingRun(field: .note, text: text, pressesReturn: true)
        case .typeColor(let text): DemoTypingRun(field: .designColor, text: text, pressesReturn: false)
        default: nil
        }
    }
}

/// A step: a pause, then an action. The pause is the time since the step
/// before it, or since the script began.
struct DemoStep: Equatable, Sendable {
    let pause: TimeInterval
    let action: DemoAction

    init(_ pause: TimeInterval, _ action: DemoAction) {
        self.pause = pause
        self.action = action
    }

    var name: String { action.name }

    /// The time the step's typing takes after its door, zero for a step
    /// that types nothing.
    var typingTime: TimeInterval {
        action.typing?.duration ?? 0
    }
}

/// A named list of timed steps (D51).
struct DemoScript: Equatable, Sendable {
    /// How long the app waits after the last step before it quits.
    static let endPause: TimeInterval = 2
    /// The longest a script may run.
    static let longestAllowed: TimeInterval = 120

    let name: String
    /// Whether the sample music is playing when the app starts.
    let startsPlaying: Bool
    let steps: [DemoStep]

    /// The time from the first step's start to the quit, in seconds. The
    /// pointer moves inside each step's pause, and typing adds its own time.
    var duration: TimeInterval {
        steps.reduce(0) { $0 + $1.pause + $1.typingTime } + Self.endPause
    }
}
