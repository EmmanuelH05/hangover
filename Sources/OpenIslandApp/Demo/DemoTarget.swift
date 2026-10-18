import Foundation

/// A control a demo script presses (D51, D65). The control's view tags
/// itself with `.demoTarget(_:)`, and the drawn pointer goes to its middle
/// before the step calls its door. Outside the demo mode the tag does
/// nothing.
enum DemoTarget: Hashable, Sendable {
    // The island
    /// The closed island at the top of the screen.
    case notch
    /// A widget's tile in edit mode, where a drag picks it up.
    case widget(NookWidgetKind)
    /// The grid of tiles, where a long press begins edit mode.
    case widgetPage
    /// A tile's S, M or L button in edit mode.
    case widgetSize(NookWidgetKind, NookWidgetSize)
    /// A chip on the edit mode shelf.
    case shelfChip(NookWidgetKind)
    /// The shelf's Done button.
    case editDone
    // Music
    case playPause
    case nextTrack
    case previousTrack
    /// The shuffle and repeat buttons, drawn in the dev copy.
    case shuffle
    case repeatMode
    // To-dos, notes, the timer and the weather
    /// A to-do's check box, by its place in the list.
    case todoCheck(position: Int)
    case todoField
    case notesField
    case timerStart
    case weatherMode(NookWeatherForecastMode)
    // Layouts in Settings. No script opens Settings yet, which is why the
    // steps that apply a layout move no pointer: their gesture is `.none`.
    case template(PersonalizationTemplate.ID)
    case templateUndo
    // The welcome tour
    case tourNext
    case tourLength(OnboardingLength)
    case tourWidgetSwitch(NookWidgetKind)
    case tourNextFeature
    case tourTry(OnboardingTry)
    case tourCalendarLook(NookCalendarStyle)
    case tourTemplate(PersonalizationTemplate.ID)
    case tourArrangeWidget(NookWidgetKind)
    case tourPutBack
    /// A switch card on a Good to know page.
    case tourMoreSwitch(OnboardingMoreSwitch)
    // The design kit
    case designTab(NookDesignTab)
    /// A swatch of the active palette, by its place on the card.
    case designSwatch(position: Int)
    case designKeepPill
    case designColorField
    case designAddColor

    /// The most to-do rows a card shows, the large card's eight, which
    /// bounds `todoCheck`.
    static let todoPositions = 0..<8
    /// The most swatches the large card shows, which bounds `designSwatch`.
    static let swatchPositions = 0..<24

    /// Every target, with every value it can carry, for the widgets this
    /// copy of the app offers.
    static let all: [DemoTarget] = {
        var all: [DemoTarget] = [
            .notch, .widgetPage, .editDone, .playPause, .nextTrack, .previousTrack, .shuffle, .repeatMode,
            .todoField, .notesField, .timerStart, .templateUndo,
            .tourNext, .tourNextFeature, .tourPutBack,
            .designKeepPill, .designColorField, .designAddColor,
        ]
        for kind in NookWidgetKind.offered {
            all += [.widget(kind), .shelfChip(kind), .tourWidgetSwitch(kind), .tourArrangeWidget(kind)]
            all += NookWidgetSize.allCases.map { .widgetSize(kind, $0) }
        }
        all += todoPositions.map { .todoCheck(position: $0) }
        all += NookWeatherForecastMode.allCases.map { .weatherMode($0) }
        all += PersonalizationTemplate.ID.allCases.flatMap { [.template($0), .tourTemplate($0)] }
        all += OnboardingLength.allCases.map { .tourLength($0) }
        all += OnboardingTry.allCases.map { .tourTry($0) }
        all += NookCalendarStyle.allCases.map { .tourCalendarLook($0) }
        all += OnboardingMoreSwitch.allCases.map { .tourMoreSwitch($0) }
        all += NookDesignTab.allCases.map { .designTab($0) }
        all += swatchPositions.map { .designSwatch(position: $0) }
        return all
    }()
}

/// What the drawn pointer does before a step's door runs.
enum DemoGesture: Equatable, Sendable {
    /// Nothing: the control is not on the screen, such as a picker in
    /// Settings or a notice the Mac sends.
    case none
    /// Glides to the control and clicks it.
    case click(DemoTarget)
    /// Glides to the control and holds the button down, which is the long
    /// press that begins edit mode.
    case hold(DemoTarget)
    /// Glides onto the closed island and rests there, which opens it.
    case enter(DemoTarget)
    /// Glides away from the open island and down, which lets it close.
    case leave

    var target: DemoTarget? {
        switch self {
        case .click(let target), .hold(let target), .enter(let target): target
        case .none, .leave: nil
        }
    }
}

extension DemoAction {
    /// The pointer's part in the step: the control the step's door belongs
    /// to, where that control is on screen.
    var gesture: DemoGesture {
        switch self {
        case .openIsland: .enter(.notch)
        case .closeIsland: .leave
        case .playOrPause: .click(.playPause)
        case .nextTrack: .click(.nextTrack)
        case .previousTrack: .click(.previousTrack)
        case .toggleShuffle: .click(.shuffle)
        case .cycleRepeat: .click(.repeatMode)
        case .checkOffTodo(let position): .click(.todoCheck(position: position))
        case .addTodo, .typeTodo: .click(.todoField)
        case .saveNote, .typeNote: .click(.notesField)
        case .startTimer: .click(.timerStart)
        case .beginEditing: .hold(.widgetPage)
        case .endEditing: .click(.editDone)
        case .moveWidget(let kind, _), .tourMoveWidget(let kind, _): .click(.widget(kind))
        case .resizeWidget(let kind, let size): .click(.widgetSize(kind, size))
        case .addWidget(let kind): .click(.shelfChip(kind))
        case .setWeatherMode(let mode): .click(.weatherMode(mode))
        case .tourNext: .click(.tourNext)
        case .tourChooseLength(let length): .click(.tourLength(length))
        case .tourSetWidget(let kind, _): .click(.tourWidgetSwitch(kind))
        case .tourNextFeature: .click(.tourNextFeature)
        case .tourTry(let step): .click(.tourTry(step))
        case .tourSetCalendarLook(let style): .click(.tourCalendarLook(style))
        case .tourApplyTemplate(let id): .click(.tourTemplate(id))
        case .tourPickWidget(let kind): .click(.tourArrangeWidget(kind))
        case .tourPutBack: .click(.tourPutBack)
        case .tourSetMore(let item, _): .click(.tourMoreSwitch(item))
        case .designTab(let tab): .click(.designTab(tab))
        case .copySwatch(let position): .click(.designSwatch(position: position))
        case .toggleKeepPicking: .click(.designKeepPill)
        case .typeColor: .click(.designColorField)
        case .addTypedColor: .click(.designAddColor)
        // A picker in Settings, the tour's closed page, a link's action, a
        // jump to a page or something the Mac sends: nothing on the screen
        // to press.
        case .stopTimer, .setCalendarLook, .chooseRightSide, .chooseLeftSide, .setGlow,
             .showChargingNotice, .showCalendarNotice, .openTour, .tourGo,
             .applyTemplate, .undoTemplate:
            .none
        }
    }
}
