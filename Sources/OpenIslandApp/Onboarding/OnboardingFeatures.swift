import Foundation

// The features page (D47): the switched-on widgets one at a time, each with
// what it can do and buttons that make the real widget do it. Everything
// here is a plain value or a pure function, which keeps the walk, the ticks
// and the clean-up testable without a window or a camera.

// MARK: - The walk

/// Where the features page is in its list: the widgets on the user's page,
/// in the order they sit there, and the one shown now.
struct OnboardingFeatureWalk: Equatable, Sendable {
    let kinds: [NookWidgetKind]
    /// The widget shown now. Always one of `kinds`, or nil for no widgets.
    let current: NookWidgetKind?

    /// A `current` that is not on the page gives way to the first widget.
    init(kinds: [NookWidgetKind], current: NookWidgetKind?) {
        self.kinds = kinds
        self.current = current.flatMap { kinds.contains($0) ? $0 : nil } ?? kinds.first
    }

    var count: Int { kinds.count }
    private var index: Int? { current.flatMap { kinds.firstIndex(of: $0) } }
    /// Counted from one, for "2 of 6". Zero with no widgets.
    var position: Int { (index ?? -1) + 1 }
    var next: NookWidgetKind? { index.flatMap { $0 + 1 < kinds.count ? kinds[$0 + 1] : nil } }
    var previous: NookWidgetKind? { index.flatMap { $0 > 0 ? kinds[$0 - 1] : nil } }
    /// True on the last widget, and with none: the page then says the
    /// others can be switched on from the page before.
    var isAtEnd: Bool { next == nil }
}

// MARK: - What the buttons do

/// Where the calendar permission stands, as the page needs it.
enum OnboardingCalendarAccess: Equatable, Sendable {
    case allowed
    /// Never asked: the button can raise the prompt.
    case undecided
    /// Refused or restricted: the prompt will not come again.
    case refused
}

/// What the music widget is playing, as the page reads it.
struct OnboardingMusicReading: Equatable, Sendable {
    var isPlaying: Bool
    /// The item's identity, or its title when the player gives none.
    var track: String
}

/// What the buttons read from the app, in plain values.
struct OnboardingFeatureReading: Equatable, Sendable {
    var isMirrorOn = false
    var isRingLightOn = false
    /// The photo booth could start now: the mirror shows the camera and
    /// the booth is idle.
    var canStartBooth = false
    var isBoothShowing = false
    /// Nil while nothing plays or the player reports nothing.
    var music: OnboardingMusicReading?
    var isTimerActive = false
    /// The tray's clipboard tab is switched on.
    var isClipboardOn = false
    /// The clipboard list holds the sample line.
    var hasSampleLine = false
    var calendar: OnboardingCalendarAccess = .undecided
}

/// The fixed sentence the file tray button copies. Its words are in the
/// string table, which makes it read in the user's language.
enum OnboardingFeatureSample {
    static let clipboardKey = "onboarding.features.sample"
}

/// One "Try it" button of the features page. The page draws these under a
/// widget's lines. A widget with none is explained only: to-dos and
/// weather, which the next pages connect.
enum OnboardingTry: String, CaseIterable, Identifiable, Sendable {
    case mirrorOn, ringLight, photoBooth
    case musicPlay, musicNext
    case timerStart, timerStop
    case trayCopy
    case notesLine
    case calendarShow

    var id: String { rawValue }

    var widget: NookWidgetKind {
        switch self {
        case .mirrorOn, .ringLight, .photoBooth: .mirror
        case .musicPlay, .musicNext: .media
        case .timerStart, .timerStop: .timer
        case .trayCopy: .tray
        case .notesLine: .notes
        case .calendarShow: .calendar
        }
    }

    /// The buttons of a widget, in the order they are shown.
    static func tries(for kind: NookWidgetKind) -> [OnboardingTry] {
        allCases.filter { $0.widget == kind }
    }

    var titleKey: String { "onboarding.features.try.\(rawValue)" }
    /// The label while the thing is on, for a button that switches it back.
    var offTitleKey: String? {
        switch self {
        case .mirrorOn, .ringLight: titleKey + ".off"
        default: nil
        }
    }

    /// True when the click raises a macOS prompt. The note under the button
    /// names it before the click (D47).
    var asksMacOS: Bool { self == .mirrorOn || self == .calendarShow }

    /// The button's key in `OnboardingActions`, named for the test that
    /// checks each one calls its door.
    var doorName: String {
        switch self {
        case .mirrorOn: "setMirror"
        case .ringLight: "setRingLight"
        case .photoBooth: "openPhotoBooth"
        case .musicPlay: "playOrPause"
        case .musicNext: "nextTrack"
        case .timerStart: "startTimer"
        case .timerStop: "stopTimer"
        case .trayCopy: "copySampleLine"
        case .notesLine: "showNotes"
        case .calendarShow: "showCalendar"
        }
    }
}

/// How a button looks right now: its label, whether it can be pressed, and
/// the note under it, as string keys.
struct OnboardingTryButton: Equatable, Sendable {
    var titleKey: String
    var isEnabled = true
    var noteKey: String?
}

extension OnboardingTry {
    /// The button for the reading and the progress of the page. The note is
    /// what the user needs to know before the click.
    func button(_ reading: OnboardingFeatureReading, progress: OnboardingFeatureProgress) -> OnboardingTryButton {
        func make(_ title: String? = nil, enabled: Bool = true, note: String? = nil) -> OnboardingTryButton {
            OnboardingTryButton(titleKey: title ?? titleKey, isEnabled: enabled, noteKey: note)
        }
        let needsMirror = "onboarding.features.needsMirror"
        switch self {
        case .mirrorOn:
            // The note comes before the click: macOS asks for the camera,
            // and the picture stays on the Mac.
            return reading.isMirrorOn ? make(offTitleKey) : make(note: titleKey + ".note")
        case .ringLight:
            guard reading.isMirrorOn else { return make(enabled: false, note: needsMirror) }
            return make(reading.isRingLightOn ? offTitleKey : nil)
        case .photoBooth:
            guard reading.canStartBooth || reading.isBoothShowing else {
                // The mirror may be on while the camera still waits for macOS.
                return make(enabled: false, note: reading.isMirrorOn ? "onboarding.features.waitCamera" : needsMirror)
            }
            return make(enabled: reading.canStartBooth, note: titleKey + ".note")
        case .musicPlay:
            return make(note: reading.music == nil ? "onboarding.features.needsSong" : nil)
        case .musicNext, .notesLine:
            return make()
        case .timerStart:
            if progress.isUsersTimer { return make(enabled: false, note: "onboarding.features.timerBusy") }
            return make(enabled: !reading.isTimerActive)
        case .timerStop:
            return make(enabled: reading.isTimerActive && !progress.isUsersTimer)
        case .trayCopy:
            return make(note: reading.isClipboardOn ? nil : titleKey + ".note")
        case .calendarShow:
            switch reading.calendar {
            case .allowed: return make(enabled: false)
            case .undecided: return make(note: titleKey + ".note")
            case .refused: return make(enabled: false, note: titleKey + ".refused")
            }
        }
    }
}

// MARK: - The ticks

/// What the page has seen happen since it came up. A try is ticked once the
/// model showed the thing done, and the tick stays: it is read from the app
/// (the mirror is on, the timer ran, the track changed), never from a click.
struct OnboardingFeatureProgress: Equatable, Sendable {
    private(set) var done: Set<OnboardingTry> = []
    /// What the music was doing when the page first saw it.
    private(set) var musicBaseline: OnboardingMusicReading?
    /// True when a timer was already running as the page came up. It is
    /// the user's, and the tour starts and stops none over it.
    private(set) var timerBusyAtStart: Bool?

    var isUsersTimer: Bool { timerBusyAtStart == true }

    /// This progress with another's: what either has seen. A state handed
    /// in with ticks keeps them beside the ones the tour noted.
    func merged(with other: OnboardingFeatureProgress) -> OnboardingFeatureProgress {
        var merged = self
        merged.done.formUnion(other.done)
        merged.musicBaseline = musicBaseline ?? other.musicBaseline
        merged.timerBusyAtStart = timerBusyAtStart ?? other.timerBusyAtStart
        return merged
    }

    /// Notes what the app shows now.
    mutating func note(_ reading: OnboardingFeatureReading) {
        if timerBusyAtStart == nil { timerBusyAtStart = reading.isTimerActive }
        if reading.isMirrorOn { done.insert(.mirrorOn) }
        if reading.isMirrorOn, reading.isRingLightOn { done.insert(.ringLight) }
        if reading.isBoothShowing { done.insert(.photoBooth) }
        if let music = reading.music {
            let baseline = musicBaseline ?? music
            musicBaseline = baseline
            if music.isPlaying != baseline.isPlaying { done.insert(.musicPlay) }
            if music.track != baseline.track { done.insert(.musicNext) }
        }
        if reading.isTimerActive, !isUsersTimer { done.insert(.timerStart) }
        if done.contains(.timerStart), !reading.isTimerActive { done.insert(.timerStop) }
        if reading.hasSampleLine { done.insert(.trayCopy) }
        if reading.calendar == .allowed { done.insert(.calendarShow) }
    }
}

// MARK: - The clean-up

/// What the tour switched on for a try-it, which it switches off again when
/// the user leaves the widget's step, the page, or the tour closes. A thing
/// that was on before the tour touched it is never recorded, and so never
/// switched off.
struct OnboardingTrials: Equatable, Sendable {
    var mirror = false
    var ringLight = false
    var timer = false

    enum Release: Equatable, Sendable {
        case ringLightOff, mirrorOff, timerOff
    }

    /// What to switch off now, given what is on. `kind` is the widget being
    /// left, or nil for every one (the page or the tour is closing). The
    /// ring light goes before the mirror.
    func releases(leaving kind: NookWidgetKind?, reading: OnboardingFeatureReading) -> [Release] {
        var list: [Release] = []
        if kind == nil || kind == .mirror {
            if ringLight, reading.isRingLightOn { list.append(.ringLightOff) }
            if mirror, reading.isMirrorOn { list.append(.mirrorOff) }
        }
        if kind == nil || kind == .timer, timer, reading.isTimerActive { list.append(.timerOff) }
        return list
    }

    /// The same trials with the released ones forgotten.
    func after(leaving kind: NookWidgetKind?) -> OnboardingTrials {
        var next = self
        if kind == nil || kind == .mirror { next.mirror = false; next.ringLight = false }
        if kind == nil || kind == .timer { next.timer = false }
        return next
    }
}

// MARK: - The buttons' doors

extension OnboardingTry {
    /// The length of the timer the page starts.
    static let timerLength: TimeInterval = 60

    /// What a press does: one call to the door the widget's own button
    /// reaches. The notes step has no button of its own. It is the notes
    /// page's step, which asks the user to type in the real notes card.
    @MainActor
    func press(
        reading: OnboardingFeatureReading,
        sample: String,
        actions: OnboardingActions
    ) {
        switch self {
        case .mirrorOn: actions.setMirror(!reading.isMirrorOn)
        case .ringLight: actions.setRingLight(!reading.isRingLightOn)
        case .photoBooth: actions.openPhotoBooth()
        case .musicPlay: actions.playOrPause()
        case .musicNext: actions.nextTrack()
        case .timerStart: actions.startTimer(Self.timerLength)
        case .timerStop: actions.stopTimer()
        case .trayCopy: actions.copySampleLine(sample)
        case .notesLine: actions.showNotes()
        case .calendarShow: actions.showCalendar()
        }
    }
}
