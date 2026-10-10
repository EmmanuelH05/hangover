import Foundation

/// Carries a demo action out through the app's own doors (D51): for each
/// action, the function the matching control calls, with the animation that
/// control wraps it in. Where a control is a drag, the door is the function
/// the drag ends in.
@MainActor
final class AppDemoDoors: DemoDoors {
    private let model: AppModel
    /// Opens the welcome tour's window. A test swaps it for a tour it made.
    private let openTour: () -> Void
    /// The tour that is up, if any.
    private let currentTour: () -> OnboardingTour?

    init(
        model: AppModel,
        openTour: (() -> Void)? = nil,
        currentTour: @escaping () -> OnboardingTour? = { OnboardingWindowController.shared.currentTour }
    ) {
        self.model = model
        self.openTour = openTour ?? { [unowned model] in model.showWelcomeTour() }
        self.currentTour = currentTour
    }

    private var nook: NookModel { model.nook }
    private var profile: IslandAppearanceDisplayProfile { model.activeAppearanceProfile }

    func perform(_ action: DemoAction) {
        switch action {
        case .openIsland: model.perform(.openNook)
        case .closeIsland: model.notchClose()
        case .playOrPause: nook.media.togglePlayPause()
        case .nextTrack: nook.media.nextTrack()
        case .previousTrack: nook.media.previousTrack()
        case .checkOffTodo(let position): checkOffTodo(at: position)
        case .addTodo(let title): nook.todo.source(reminders: nook.reminders).add(title)
        case .saveNote(let text): nook.notes.append(text)
        case .startTimer(let minutes): model.perform(.startTimer(minutes: minutes))
        case .stopTimer: model.perform(.stopTimer)
        case .applyTemplate(let id): applyTemplate(id)
        case .undoTemplate: withMotion(Motion.morph) { model.undoTemplate(for: profile) }
        case .beginEditing: withMotion(Motion.editToggle) { nook.isEditingLayout = true }
        case .endEditing: withMotion(Motion.editToggle) { nook.isEditingLayout = false }
        case .moveWidget(let kind, let index): move(kind, to: index)
        case .resizeWidget(let kind, let size):
            withMotion(Motion.reflow) { nook.setWidgetSize(kind, size, for: profile) }
        case .addWidget(let kind): withMotion(Motion.reflow) { nook.addWidget(kind, for: profile) }
        case .setCalendarLook(let style): update { $0.calendarStyle = style }
        case .setWeatherMode(let mode): withMotion(Motion.contentSwap) { nook.weather.forecastMode = mode }
        case .chooseRightSide(let side): model.chooseClosedSide(side)
        case .chooseLeftSide(let side): model.chooseClosedLeft(side)
        case .setGlow(let style): update { $0.haloStyle = style }
        case .showChargingNotice: nook.power.showPower(.init(isOnAC: true, percent: 78))
        case .showCalendarNotice: showCalendarNotice()
        case .openTour: openTour()
        case .tourNext: currentTour()?.next()
        case .tourSetWidget(let kind, let isOn): currentTour()?.actions.setWidget(kind, isOn)
        case .tourNextFeature: currentTour()?.actions.nextFeature()
        case .tourTry(let step): press(step)
        case .tourSetCalendarLook(let style): currentTour()?.actions.setCalendarStyle(style)
        case .tourApplyTemplate(let id): tourApply(id)
        case .tourPickWidget(let kind): currentTour()?.actions.pickArrangeWidget(kind)
        case .tourMoveWidget(let kind, let index): move(kind, to: index)
        case .tourPutBack: currentTour()?.actions.resetArrangement()
        }
    }

    // MARK: Doors with a little more to them

    /// The row's check, which asks the source to complete the task at that
    /// place in its list.
    private func checkOffTodo(at position: Int) {
        let source = nook.todo.source(reminders: nook.reminders)
        guard source.items.indices.contains(position) else { return }
        source.complete(source.items[position].id)
    }

    private func applyTemplate(_ id: PersonalizationTemplate.ID) {
        guard let template = PersonalizationTemplate.all.first(where: { $0.id == id }) else { return }
        withMotion(Motion.morph) { model.applyTemplate(template, for: profile) }
    }

    private func tourApply(_ id: PersonalizationTemplate.ID) {
        guard let template = PersonalizationTemplate.all.first(where: { $0.id == id }) else { return }
        currentTour()?.actions.applyTemplate(template)
    }

    /// Where a drag on a tile ends.
    private func move(_ kind: NookWidgetKind, to index: Int) {
        withMotion(Motion.reflow) { nook.moveWidget(kind, to: index, for: profile) }
    }

    /// The Personalization pickers' write, through their motion.
    private func update(_ change: (inout NookDisplayPreferences) -> Void) {
        withMotion(Motion.selection) { nook.updateDisplayPreferences(for: profile, change) }
    }

    /// The minute tick, asked at the moment ten minutes before the next
    /// event starts.
    private func showCalendarNotice() {
        guard let event = nook.calendar.events.first(where: { !$0.isAllDay }) else { return }
        nook.calendar.checkNextUp(now: event.start.addingTimeInterval(-9.5 * 60))
    }

    /// A "Try it" button, the way the features page presses it: only when
    /// the button is enabled.
    private func press(_ step: OnboardingTry) {
        guard let tour = currentTour() else { return }
        let state = tour.state
        guard step.button(state.features, progress: state.featureProgress).isEnabled else { return }
        step.press(
            reading: state.features,
            sample: LanguageManager.shared.t(OnboardingFeatureSample.clipboardKey),
            actions: tour.actions
        )
    }
}
