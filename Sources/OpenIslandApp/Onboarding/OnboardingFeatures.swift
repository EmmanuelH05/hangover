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

/// Where the camera permission stands, as the page needs it. Read from
/// macOS without asking it for anything.
enum OnboardingCameraAccess: Equatable, Sendable {
    case allowed
    /// Never asked: the mirror's button can raise the prompt.
    case undecided
    /// Refused or restricted: the prompt will not come again.
    case refused
    /// This Mac has no camera the mirror can use.
    case unavailable
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
    var camera: OnboardingCameraAccess = .undecided
    /// The photo booth could start now: the mirror shows the camera and
    /// the booth is idle.
    var canStartBooth = false
    /// The booth has anything on the mirror: a session, a strip or a failure.
    var isBoothShowing = false
    /// The booth made a strip, which is on the mirror now.
    var hasBoothStrip = false
    /// Nil while nothing plays or the player reports nothing.
    var music: OnboardingMusicReading?
    var isTimerActive = false
    /// The length of the one-off countdown that is active, in seconds. Nil
    /// for a pomodoro run, a timer on the saved preset and no timer.
    var timerOneOff: TimeInterval?
    /// The tray's clipboard tab is switched on.
    var isClipboardOn = false
    /// The clipboard list holds the sample line.
    var hasSampleLine = false
    var calendar: OnboardingCalendarAccess = .undecided

    /// The active timer is the countdown this page starts: a one-off of its
    /// length. A timer the user started is anything else that is active.
    var isTourTimer: Bool { isTimerActive && timerOneOff == OnboardingTry.timerLength }
    var isUsersTimer: Bool { isTimerActive && !isTourTimer }
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
    /// The note says camera access is off, and the row offers the button
    /// that opens the camera list in System Settings.
    var offersCameraSettings = false
}

extension OnboardingTry {
    static let cameraRefusedKey = "onboarding.features.camera.refused"
    static let cameraNoneKey = "onboarding.features.camera.none"

    /// The button for the reading and the progress of the page. The note is
    /// what the user needs to know before the click.
    func button(_ reading: OnboardingFeatureReading, progress: OnboardingFeatureProgress) -> OnboardingTryButton {
        func make(
            _ title: String? = nil, enabled: Bool = true, note: String? = nil, settings: Bool = false
        ) -> OnboardingTryButton {
            OnboardingTryButton(titleKey: title ?? titleKey, isEnabled: enabled, noteKey: note, offersCameraSettings: settings)
        }
        let needsMirror = "onboarding.features.needsMirror"
        switch self {
        case .mirrorOn:
            // The note follows the camera: macOS asks only while nothing was
            // decided, and a refusal says where to change it.
            switch reading.camera {
            case .refused:
                return make(reading.isMirrorOn ? offTitleKey : nil, enabled: reading.isMirrorOn, note: Self.cameraRefusedKey, settings: true)
            case .unavailable:
                return make(reading.isMirrorOn ? offTitleKey : nil, enabled: reading.isMirrorOn, note: Self.cameraNoneKey)
            case .undecided:
                return reading.isMirrorOn ? make(offTitleKey) : make(note: titleKey + ".note")
            case .allowed:
                return make(reading.isMirrorOn ? offTitleKey : nil)
            }
        case .ringLight:
            guard reading.isMirrorOn else { return make(enabled: false, note: needsMirror) }
            return make(reading.isRingLightOn ? offTitleKey : nil)
        case .photoBooth:
            guard reading.canStartBooth || reading.isBoothShowing else {
                let note = switch reading.camera {
                case .refused: Self.cameraRefusedKey
                case .unavailable: Self.cameraNoneKey
                // The mirror may be on while the camera still starts, or
                // waits for macOS.
                case .undecided: reading.isMirrorOn ? "onboarding.features.waitCamera" : needsMirror
                case .allowed: reading.isMirrorOn ? "onboarding.features.startingCamera" : needsMirror
                }
                return make(enabled: false, note: note)
            }
            return make(enabled: reading.canStartBooth, note: titleKey + ".note")
        case .musicPlay:
            return make(note: reading.music == nil ? "onboarding.features.needsSong" : nil)
        case .musicNext, .notesLine:
            return make()
        case .timerStart:
            // The user's timer is one that runs and is not this page's own.
            if reading.isUsersTimer { return make(enabled: false, note: "onboarding.features.timerBusy") }
            return make(enabled: !reading.isTimerActive)
        case .timerStop:
            return make(enabled: reading.isTourTimer)
        case .trayCopy:
            if progress.copyFailed { return make(note: "onboarding.features.copyFailed") }
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
/// (the mirror is on with the camera allowed, a strip came out, the track
/// changed), never from a click.
struct OnboardingFeatureProgress: Equatable, Sendable {
    private(set) var done: Set<OnboardingTry> = []
    /// What the music was doing when the page first saw it.
    private(set) var musicBaseline: OnboardingMusicReading?
    /// True after the sample line could not be put on the pasteboard, until
    /// a copy works.
    var copyFailed = false

    /// This progress with another's: what either has seen. A state handed
    /// in with ticks keeps them beside the ones the tour noted.
    func merged(with other: OnboardingFeatureProgress) -> OnboardingFeatureProgress {
        var merged = self
        merged.done.formUnion(other.done)
        merged.musicBaseline = musicBaseline ?? other.musicBaseline
        merged.copyFailed = copyFailed || other.copyFailed
        return merged
    }

    /// Notes what the app shows now.
    mutating func note(_ reading: OnboardingFeatureReading) {
        // A mirror with no camera allowed shows nothing, which is not a tick.
        if reading.isMirrorOn, reading.camera == .allowed { done.insert(.mirrorOn) }
        if reading.isMirrorOn, reading.isRingLightOn { done.insert(.ringLight) }
        // A failed session leaves the booth showing too. Only a strip counts.
        if reading.hasBoothStrip { done.insert(.photoBooth) }
        if let music = reading.music {
            let baseline = musicBaseline ?? music
            musicBaseline = baseline
            if music.isPlaying != baseline.isPlaying { done.insert(.musicPlay) }
            if music.track != baseline.track { done.insert(.musicNext) }
        }
        // A timer of the user's own is not this page's start.
        if reading.isTourTimer { done.insert(.timerStart) }
        if reading.hasSampleLine { done.insert(.trayCopy) }
        if reading.calendar == .allowed { done.insert(.calendarShow) }
    }

    /// The stop button was pressed: it ticks when it stopped this page's
    /// own countdown. A minute that ran out by itself is not a stop.
    mutating func noteTimerStop(before: OnboardingFeatureReading, after: OnboardingFeatureReading) {
        if before.isTourTimer, !after.isTimerActive { done.insert(.timerStop) }
    }
}

// MARK: - The clean-up

/// What the app showed when the features page came up. The clean-up puts
/// the mirror and the ring light setting back to this, and never past it.
struct OnboardingFeatureBaseline: Equatable, Sendable {
    var isMirrorOn = false
    /// The saved ring light setting.
    var isRingLightOn = false
    var isBoothShowing = false
    var isTimerActive = false

    init(isMirrorOn: Bool = false, isRingLightOn: Bool = false, isBoothShowing: Bool = false, isTimerActive: Bool = false) {
        self.isMirrorOn = isMirrorOn
        self.isRingLightOn = isRingLightOn
        self.isBoothShowing = isBoothShowing
        self.isTimerActive = isTimerActive
    }

    init(_ reading: OnboardingFeatureReading) {
        self.init(
            isMirrorOn: reading.isMirrorOn,
            isRingLightOn: reading.isRingLightOn,
            isBoothShowing: reading.isBoothShowing,
            isTimerActive: reading.isTimerActive
        )
    }
}

/// What the tour switched on for a try-it, which it switches off again when
/// the user leaves the widget's step, the page, or the tour closes. The
/// baseline is taken once, when the page comes up (D49): a mirror that was
/// on then is left exactly as it is, a mirror that was off goes off, and the
/// ring light setting goes back to its baseline value when a tour button
/// changed it. Nothing here ever switches a camera on.
struct OnboardingTrials: Equatable, Sendable {
    /// Nil until the features page is up, and nothing is released without it.
    var baseline: OnboardingFeatureBaseline?
    /// The value a tour button last wrote to the ring light setting, nil
    /// while no button changed it. A value the user changed since is not
    /// the tour's (`observing`).
    var ringLight: Bool?
    /// The tour's button started a photo booth session that was not
    /// showing at the press.
    var booth = false
    /// The tour's countdown is the active timer.
    var timer = false

    enum Release: Equatable, Sendable {
        case boothCancel
        /// Writes the ring light setting back to this value.
        case ringLight(Bool)
        case mirrorOff, timerOff
    }

    /// What to put back now, given what is on. `kind` is the widget being
    /// left, or nil for every one (the page or the tour is closing). The
    /// order is the booth, the ring light, the mirror, the timer.
    func releases(leaving kind: NookWidgetKind?, reading: OnboardingFeatureReading) -> [Release] {
        guard let baseline else { return [] }
        var list: [Release] = []
        if kind == nil || kind == .mirror {
            // The session goes first, whoever owns the mirror.
            if booth, reading.isBoothShowing { list.append(.boothCancel) }
            if ringLight != nil, reading.isRingLightOn != baseline.isRingLightOn {
                list.append(.ringLight(baseline.isRingLightOn))
            }
            if !baseline.isMirrorOn, reading.isMirrorOn { list.append(.mirrorOff) }
        }
        if kind == nil || kind == .timer, timer, reading.isTourTimer { list.append(.timerOff) }
        return list
    }

    /// The same trials with the released ones forgotten. The baseline stays
    /// while the page is up.
    func after(leaving kind: NookWidgetKind?) -> OnboardingTrials {
        if kind == nil { return OnboardingTrials() }
        var next = self
        if kind == .mirror { next.booth = false; next.ringLight = nil }
        if kind == .timer { next.timer = false }
        return next
    }

    /// The same trials after looking at the app: a session that is gone, a
    /// timer that stopped or is no longer the tour's countdown, and a ring
    /// light the user changed by hand are no longer the tour's to put back.
    func observing(_ reading: OnboardingFeatureReading) -> OnboardingTrials {
        var next = self
        if booth, !reading.isBoothShowing { next.booth = false }
        if timer, !reading.isTourTimer { next.timer = false }
        if let written = ringLight, written != reading.isRingLightOn { next.ringLight = nil }
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
        case .trayCopy: _ = actions.copySampleLine(sample)
        case .notesLine: actions.showNotes()
        case .calendarShow: actions.showCalendar()
        }
    }
}
