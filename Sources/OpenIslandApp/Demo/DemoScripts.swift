import Foundation

/// The four scripts of the demo mode (D51). The content is fixed; the
/// timings are tuned to read like a person: one to two and a half seconds
/// between small actions, longer where something should be read.
enum DemoScripts {
    static let all = [tour, use, closed, looks]

    static let names = all.map(\.name)

    static func named(_ name: String) -> DemoScript? {
        all.first { $0.name == name }
    }

    /// The pages the tour walks in the demo: no agents page and no weather
    /// page, because the agents are off and the weather widget starts off.
    static let tourPages = OnboardingPage.shown(
        agentsEnabled: false, hasTodoWidget: true, hasNotesWidget: true, hasWeatherWidget: false
    )

    // MARK: tour

    /// The welcome tour, page by page with its own Next, from the first page
    /// to its last button. It presses nothing that asks macOS for anything:
    /// no camera, no calendar access, no Reminders, no Finder.
    static let tour = DemoScript(
        name: "tour",
        startsPlaying: true,
        steps: [
            DemoStep(2.5, .openTour),
            // welcome, purpose, opening, closed
            DemoStep(3.5, .tourNext),
            DemoStep(3.0, .tourNext),
            DemoStep(3.0, .tourNext),
            DemoStep(3.5, .tourNext),
            // widgets: one switched off and on
            DemoStep(1.2, .tourSetWidget(.tray, isOn: false)),
            DemoStep(1.5, .tourSetWidget(.tray, isOn: true)),
            DemoStep(1.2, .tourNext),
            // features: each widget on the page, in the order it sits there
            DemoStep(1.5, .tourTry(.musicPlay)),
            DemoStep(1.8, .tourTry(.musicNext)),
            DemoStep(1.8, .tourNextFeature),
            DemoStep(1.5, .tourSetCalendarLook(.agenda)),
            DemoStep(2.0, .tourSetCalendarLook(.timeline)),
            DemoStep(2.0, .tourSetCalendarLook(.month)),
            DemoStep(1.8, .tourNextFeature),
            DemoStep(2.0, .tourNextFeature),
            DemoStep(2.0, .tourNextFeature),
            DemoStep(2.0, .tourNextFeature),
            DemoStep(1.5, .tourTry(.timerStart)),
            DemoStep(2.5, .tourTry(.timerStop)),
            DemoStep(1.5, .tourNext),
            // layout: two templates. The calendar look picked above stays.
            DemoStep(1.5, .tourApplyTemplate(.planner)),
            DemoStep(2.2, .tourApplyTemplate(.focus)),
            DemoStep(2.2, .tourNext),
            // arrange: pick a widget, move it one place, put it back
            DemoStep(1.5, .tourPickWidget(.todo)),
            DemoStep(2.0, .tourMoveWidget(.todo, to: 1)),
            DemoStep(2.5, .tourPutBack),
            DemoStep(1.5, .tourNext),
            // to-dos, notes, opened, look, permissions, integrations, tips, done
            DemoStep(3.0, .tourNext),
            DemoStep(3.0, .tourNext),
            DemoStep(3.0, .tourNext),
            DemoStep(3.0, .tourNext),
            DemoStep(3.0, .tourNext),
            DemoStep(3.0, .tourNext),
            DemoStep(3.5, .tourNext),
            DemoStep(3.0, .tourNext),
        ]
    )

    // MARK: use

    /// The island in everyday use, from opening it to closing it again.
    static let use = DemoScript(
        name: "use",
        startsPlaying: false,
        steps: [
            DemoStep(2.5, .openIsland),
            DemoStep(2.5, .playOrPause),
            DemoStep(2.5, .playOrPause),
            DemoStep(1.8, .playOrPause),
            DemoStep(2.2, .nextTrack),
            DemoStep(2.5, .checkOffTodo(position: 0)),
            DemoStep(2.0, .addTodo("Call home")),
            DemoStep(2.5, .startTimer(minutes: 25)),
            // The timer runs a few seconds, then the closed pill shows the
            // time left and the music.
            DemoStep(4.5, .closeIsland),
            DemoStep(5.0, .openIsland),
            DemoStep(2.0, .saveNote("Pick up groceries on the way back")),
            DemoStep(3.0, .applyTemplate(.focus)),
            DemoStep(3.5, .undoTemplate),
            DemoStep(3.0, .beginEditing),
            DemoStep(2.0, .moveWidget(.timer, to: 1)),
            DemoStep(2.0, .resizeWidget(.todo, .large)),
            DemoStep(2.2, .endEditing),
            DemoStep(2.5, .closeIsland),
        ]
    )

    // MARK: closed

    /// Only the closed island, a few seconds on each look.
    static let closed = DemoScript(
        name: "closed",
        startsPlaying: false,
        steps: [
            // Idle.
            DemoStep(2.5, .closeIsland),
            // Music with the bars, then the timer counting beside it.
            DemoStep(4.0, .playOrPause),
            DemoStep(5.0, .startTimer(minutes: 25)),
            // Both go, and the paused art lets go of the island (ten
            // seconds) while the two notices show.
            DemoStep(5.0, .stopTimer),
            DemoStep(0.8, .playOrPause),
            DemoStep(1.0, .showChargingNotice),
            DemoStep(4.5, .showCalendarNotice),
            // Each side shows the date, the battery, the weather and the
            // count of to-dos.
            DemoStep(6.5, .chooseRightSide(.date)),
            DemoStep(2.8, .chooseRightSide(.battery)),
            DemoStep(2.8, .chooseRightSide(.weather)),
            DemoStep(2.8, .chooseRightSide(.todos)),
            DemoStep(2.8, .chooseRightSide(.nothing)),
            DemoStep(1.0, .chooseLeftSide(.date)),
            DemoStep(2.8, .chooseLeftSide(.battery)),
            DemoStep(2.8, .chooseLeftSide(.weather)),
            DemoStep(2.8, .chooseLeftSide(.todos)),
            DemoStep(2.8, .chooseLeftSide(.nothing)),
            // The status glow on Vivid, with music. The skip at the end keeps
            // the glow on screen for a few seconds before the app quits.
            DemoStep(1.5, .playOrPause),
            DemoStep(1.5, .setGlow(.vivid)),
            DemoStep(4.0, .nextTrack),
        ]
    )

    // MARK: looks

    /// The open island: the calendar's five looks, the weather from hours to
    /// the week, and three layouts.
    static let looks = DemoScript(
        name: "looks",
        startsPlaying: true,
        steps: [
            DemoStep(2.5, .openIsland),
            DemoStep(2.5, .resizeWidget(.calendar, .large)),
            DemoStep(2.5, .setCalendarLook(.strip)),
            DemoStep(3.0, .setCalendarLook(.agenda)),
            DemoStep(3.0, .setCalendarLook(.timeline)),
            DemoStep(3.0, .setCalendarLook(.hero)),
            DemoStep(3.0, .setCalendarLook(.month)),
            // The weather takes the top of the page.
            DemoStep(3.5, .resizeWidget(.calendar, .medium)),
            DemoStep(1.5, .addWidget(.weather)),
            DemoStep(1.5, .moveWidget(.weather, to: 0)),
            DemoStep(1.5, .setWeatherMode(.hours)),
            DemoStep(3.5, .setWeatherMode(.week)),
            // Three layouts in turn.
            DemoStep(3.5, .applyTemplate(.planner)),
            DemoStep(3.5, .applyTemplate(.study)),
            DemoStep(3.5, .applyTemplate(.nowPlaying)),
            DemoStep(3.5, .closeIsland),
        ]
    )
}
