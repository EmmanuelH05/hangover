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
    /// Hands typing to the field on screen (D65).
    let typist: DemoTypist
    var log: (String) -> Void = { line in
        print(line)
        fflush(stdout)
    }

    init(
        model: AppModel,
        typist: DemoTypist = DemoTypist.current ?? DemoTypist(),
        openTour: (() -> Void)? = nil,
        currentTour: @escaping () -> OnboardingTour? = { OnboardingWindowController.shared.currentTour }
    ) {
        self.model = model
        self.typist = typist
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
        case .toggleShuffle: nook.media.toggleShuffle()
        case .cycleRepeat: nook.media.cycleRepeat()
        case .checkOffTodo(let position): checkOffTodo(at: position)
        case .addTodo(let title): nook.todo.source(reminders: nook.reminders).add(title)
        case .saveNote(let text): saveNote(text)
        case .typeTodo: typist.focus(.todo)
        case .typeNote: typeNote()
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
        case .tourChooseLength(let length): currentTour()?.actions.chooseLength(length)
        case .tourSetWidget(let kind, let isOn): currentTour()?.actions.setWidget(kind, isOn)
        case .tourNextFeature: currentTour()?.actions.nextFeature()
        case .tourTry(let step): press(step)
        case .tourSetCalendarLook(let style): currentTour()?.actions.setCalendarStyle(style)
        case .tourApplyTemplate(let id): tourApply(id)
        case .tourPickWidget(let kind): currentTour()?.actions.pickArrangeWidget(kind)
        case .tourMoveWidget(let kind, let index): move(kind, to: index)
        case .tourPutBack: currentTour()?.actions.resetArrangement()
        case .tourGo(let page): currentTour()?.show(page)
        case .tourSetMore(let item, let isOn): currentTour()?.actions.setMore(item, isOn)
        case .designTab(let tab): nook.design.tab = tab
        case .copySwatch(let position): copySwatch(at: position)
        case .toggleKeepPicking: nook.design.toggleKeepsPicking()
        case .typeColor: typist.focus(.designColor)
        case .addTypedColor: submit(.designColor)
        }
    }

    // MARK: Typing

    func type(_ text: String, into field: DemoTypingField) {
        typist.type(text, into: field)
    }

    /// Return, which the field on screen takes through its own submit. With
    /// no such field on screen the text goes to the service the field
    /// saves to, and the log says it.
    func submit(_ field: DemoTypingField) {
        guard !typist.submit(field) else { return }
        let text = typist.line(field).text
        guard !text.isEmpty else { return }
        log("DEMO no \(field.rawValue) field on screen, its service took the text")
        switch field {
        case .note: saveNote(text)
        case .todo: nook.todo.source(reminders: nook.reminders).add(text)
        case .designColor: nook.design.addColor(text: text)
        }
    }

    // MARK: Notes

    /// The New note button, which opens the editor on a blank note. The
    /// editor takes the cursor by itself; the typist's focus is for a field
    /// that is already on screen.
    private func typeNote() {
        withMotion(Motion.reflow) { nook.notes.beginNewNote() }
        typist.focus(.note)
    }

    /// A whole note at once: the button, the text, and the editor closed.
    private func saveNote(_ text: String) {
        let notes = nook.notes
        withMotion(Motion.reflow) {
            notes.beginNewNote()
            notes.edit(text)
            notes.closeEditor()
        }
    }

    // MARK: Doors with a little more to them

    /// The row's check, which asks the source to complete the task at that
    /// place in its list.
    private func checkOffTodo(at position: Int) {
        let items = nook.todoItems
        guard items.indices.contains(position) else { return }
        let id = items[position].id
        nook.todo.source(holding: id, reminders: nook.reminders)?.complete(id)
    }

    /// A swatch on the card, by its place in the order the card shows.
    private func copySwatch(at position: Int) {
        let kit = nook.design
        let swatches = NookDesignLibrary.compactOrder(kit.palettes.activePalette?.swatches ?? [])
        guard swatches.indices.contains(position) else { return }
        let swatch = swatches[position]
        withMotion(Motion.selection) { _ = kit.copy(swatch.color, from: swatch.id) }
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
