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
    // To-dos and notes
    case checkOffTodo(position: Int)
    case addTodo(String)
    case saveNote(String)
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
    case tourSetWidget(NookWidgetKind, isOn: Bool)
    case tourNextFeature
    case tourTry(OnboardingTry)
    case tourSetCalendarLook(NookCalendarStyle)
    case tourApplyTemplate(PersonalizationTemplate.ID)
    case tourPickWidget(NookWidgetKind)
    case tourMoveWidget(NookWidgetKind, to: Int)
    case tourPutBack

    /// The step's name in the line the runner prints.
    var name: String {
        switch self {
        case .openIsland: "open-island"
        case .closeIsland: "close-island"
        case .playOrPause: "play-pause"
        case .nextTrack: "next-track"
        case .previousTrack: "previous-track"
        case .checkOffTodo(let position): "check-off-todo-\(position + 1)"
        case .addTodo: "add-todo"
        case .saveNote: "save-note"
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
        case .tourSetWidget(let kind, let isOn): "tour-widget-\(kind.rawValue)-\(isOn ? "on" : "off")"
        case .tourNextFeature: "tour-next-feature"
        case .tourTry(let step): "tour-try-\(step.rawValue)"
        case .tourSetCalendarLook(let style): "tour-calendar-look-\(style.rawValue)"
        case .tourApplyTemplate(let id): "tour-template-\(id.rawValue)"
        case .tourPickWidget(let kind): "tour-pick-\(kind.rawValue)"
        case .tourMoveWidget(let kind, let index): "tour-move-\(kind.rawValue)-to-\(index)"
        case .tourPutBack: "tour-put-back"
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
        case .checkOffTodo: "NookTodoSource.complete(_:), the row's check"
        case .addTodo: "NookTodoSource.add(_:), the add field"
        case .saveNote: "NookNotesService.append(_:), the note field"
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
        case .tourSetWidget: "OnboardingActions.setWidget, the widgets page's switch"
        case .tourNextFeature: "OnboardingActions.nextFeature, the features page's arrow"
        case .tourTry: "OnboardingTry.press(reading:sample:actions:), a Try it button"
        case .tourSetCalendarLook: "OnboardingActions.setCalendarStyle, a look card"
        case .tourApplyTemplate: "OnboardingActions.applyTemplate, a template card"
        case .tourPickWidget: "OnboardingActions.pickArrangeWidget, the arrange page's card"
        case .tourMoveWidget: "NookModel.moveWidget(_:to:for:), where a drag ends"
        case .tourPutBack: "OnboardingActions.resetArrangement, the Put it back button"
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

    /// The time from the first step's start to the quit, in seconds.
    var duration: TimeInterval {
        steps.reduce(0) { $0 + $1.pause } + Self.endPause
    }
}
