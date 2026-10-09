import SwiftUI

/// The "+" every calendar look puts in its header. It opens the event
/// editor at the top of the Nook page.
struct NookCalendarAddButton: View {
    /// True in a header that is only as tall as its text. The button keeps
    /// its 22pt hit area without making that row taller.
    var isInline = false
    let action: () -> Void

    private static let hitArea: CGFloat = 22
    private static let inlineOverhang: CGFloat = 5

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: Self.hitArea, height: Self.hitArea)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Add event")
        .accessibilityLabel("Add event")
        .padding(.vertical, isInline ? -Self.inlineOverhang : 0)
    }
}

/// The event editor at the top of the Nook page: a month to pick the day on
/// the left, the event's details on the right, and a line at the bottom
/// that says exactly what will be saved. Every choice is a visible control;
/// nothing is read out of the title unless the user takes the suggestion.
struct NookEventEditor: View {
    var nook: NookModel

    @State private var visibleMonth = Date()
    @State private var errorMessage: String?
    @FocusState private var isTitleFocused: Bool

    private static let rowHeight: CGFloat = 24
    private static let titleHeight: CGFloat = 28
    private static let notesHeight: CGFloat = 40

    private var form: NookEventForm {
        nook.eventForm ?? NookEventForm.new(on: Date(), now: Date(), calendar: .current)
    }

    var body: some View {
        let form = form
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 14) {
                NookMiniMonth(visibleMonth: $visibleMonth, picked: form.day) { day in
                    update { form in
                        var next = form
                        next.day = Calendar.current.startOfDay(for: day)
                        return next
                    }
                }
                .frame(width: NookEventEditorLayout.monthWidth)

                details(form)
            }
            footer(form)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NookCardBackground())
        .onAppear {
            visibleMonth = form.day
            isTitleFocused = true
        }
    }

    // MARK: - Details

    private func details(_ form: NookEventForm) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                field(prompt: "Add title", text: binding(\.title), size: 13, weight: .semibold)
                    .focused($isTitleFocused)
                    .onSubmit { save() }
                    .frame(height: Self.titleHeight)
                iconButton("xmark", help: "Cancel") { cancel() }
            }
            whenRow(form)
            field(prompt: "Add location", text: binding(\.location), icon: "mappin.and.ellipse")
                .frame(height: Self.rowHeight)
            field(prompt: "Add notes", text: binding(\.notes), icon: "text.alignleft", isMultiline: true)
                .frame(height: Self.notesHeight)
            optionsRow(form)
        }
        .onExitCommand { cancel() }
    }

    /// Start and end as menus, the way a calendar app offers them, with All
    /// day beside them.
    private func whenRow(_ form: NookEventForm) -> some View {
        let calendar = Calendar.current
        return HStack(spacing: 4) {
            Menu {
                ForEach(NookEventDayPart.allCases) { part in
                    Menu(part.title) {
                        ForEach(part.minutes, id: \.self) { minute in
                            Button(timeText(minute: minute, on: form.day)) {
                                update { $0.settingStart(minute: minute) }
                            }
                        }
                    }
                }
            } label: {
                chip(form.isAllDay ? "Start" : NookEventText.time(form.start(calendar: calendar)), dimmed: form.isAllDay)
            }
            .eventMenuStyle()
            .help("Start time")

            Text("to")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))

            Menu {
                ForEach(NookEventForm.durations, id: \.self) { minutes in
                    Button("\(timeText(minute: form.startMinute + minutes, on: form.day))  ·  \(NookEventText.duration(minutes: minutes))") {
                        update { $0.settingDuration(minutes: minutes) }
                    }
                }
            } label: {
                chip(form.isAllDay ? "End" : NookEventText.time(form.end(calendar: calendar)), dimmed: form.isAllDay)
            }
            .eventMenuStyle()
            .help("End time")

            Spacer(minLength: 4)

            Button {
                update { $0.settingAllDay(!form.isAllDay) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: form.isAllDay ? "checkmark.square.fill" : "square")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(form.isAllDay ? Color.orange : Color.white.opacity(0.5))
                    Text("All day")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .frame(height: Self.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: Self.rowHeight)
    }

    /// Which calendar, when to be reminded, and whether it repeats.
    private func optionsRow(_ form: NookEventForm) -> some View {
        let writable = nook.calendar.calendars.filter(\.allowsChanges)
        let chosenID = form.calendarID ?? nook.calendar.defaultCalendarID
        let chosen = writable.first { $0.id == chosenID } ?? writable.first
        return HStack(spacing: 4) {
            Menu {
                ForEach(writable) { calendar in
                    Button {
                        update { form in
                            var next = form
                            next.calendarID = calendar.id
                            return next
                        }
                    } label: {
                        if calendar.id == chosen?.id {
                            Label(calendar.title, systemImage: "checkmark")
                        } else {
                            Text(calendar.title)
                        }
                    }
                }
            } label: {
                chip(chosen?.title ?? "Calendar", dot: chosen?.color ?? .gray)
            }
            .eventMenuStyle()
            .help("Calendar")
            .layoutPriority(-1)

            Menu {
                ForEach(NookEventAlert.options(isAllDay: form.isAllDay)) { alert in
                    Button(alert.title(isAllDay: form.isAllDay)) {
                        update { form in
                            var next = form
                            next.alert = alert
                            return next
                        }
                    }
                }
            } label: {
                chip(form.alert.title(isAllDay: form.isAllDay), icon: form.alert == .none ? "bell.slash" : "bell.fill")
            }
            .eventMenuStyle()
            .help("Alert")

            Menu {
                ForEach(NookEventRepeat.allCases) { repeats in
                    Button(repeats.title) {
                        update { form in
                            var next = form
                            next.repeats = repeats
                            return next
                        }
                    }
                }
            } label: {
                chip(form.repeats == .never ? "Once" : form.repeats.title, icon: "repeat")
            }
            .eventMenuStyle()
            .help("Repeat")

            Spacer(minLength: 0)
        }
        .frame(height: Self.rowHeight)
    }

    // MARK: - Footer

    private func footer(_ form: NookEventForm) -> some View {
        let calendar = Calendar.current
        let suggestion = form.suggestion(now: Date(), calendar: calendar)
        return HStack(spacing: 8) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else if let suggestion {
                // The title names a time or a day. Offer it; never take it
                // without being asked.
                Button {
                    update { $0.applying(suggestion, calendar: calendar) }
                    visibleMonth = suggestion.start
                } label: {
                    chip(
                        "Use " + (suggestion.isAllDay ? NookEventText.day(suggestion.start) : suggestion.summary()),
                        icon: "wand.and.stars"
                    )
                }
                .buttonStyle(.plain)
                .help("Set the day and time from the title")
            } else {
                Text(form.draft(calendar: calendar).summary())
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 4)
            Button("Cancel") { cancel() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 10)
                .frame(height: Self.rowHeight)
                .contentShape(Rectangle())
            Button("Save") { save() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(form.canSave ? Color.black : Color.white.opacity(0.35))
                .padding(.horizontal, 14)
                .frame(height: Self.rowHeight)
                .background(Capsule().fill(form.canSave ? Color.white.opacity(0.9) : Color.white.opacity(0.08)))
                .contentShape(Capsule())
                .disabled(!form.canSave)
        }
        .frame(height: Self.rowHeight)
    }

    // MARK: - Pieces

    private func field(
        prompt: String,
        text: Binding<String>,
        icon: String? = nil,
        size: CGFloat = 12,
        weight: Font.Weight = .regular,
        isMultiline: Bool = false
    ) -> some View {
        HStack(alignment: isMultiline ? .top : .center, spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 14)
                    .padding(.top, isMultiline ? 2 : 0)
            }
            if isMultiline {
                TextField("", text: text, prompt: Text(prompt), axis: .vertical)
                    .lineLimit(2, reservesSpace: true)
                    .textFieldStyle(.plain)
                    .font(.system(size: size, weight: weight))
                    .foregroundStyle(.white.opacity(0.85))
            } else {
                TextField("", text: text, prompt: Text(prompt))
                    .textFieldStyle(.plain)
                    .font(.system(size: size, weight: weight))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, isMultiline ? 5 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isMultiline ? .topLeading : .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    /// A small capsule: the label of every menu in the editor.
    private func chip(_ title: String, icon: String? = nil, dot: Color? = nil, dimmed: Bool = false) -> some View {
        HStack(spacing: 4) {
            if let dot {
                Circle().fill(dot).frame(width: 7, height: 7)
            }
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(dimmed ? 0.4 : 0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .contentShape(Capsule())
    }

    private func iconButton(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func timeText(minute: Int, on day: Date) -> String {
        let date = Calendar.current.date(byAdding: .minute, value: minute, to: day) ?? day
        return NookEventText.time(date)
    }

    // MARK: - Changes

    private func binding(_ keyPath: WritableKeyPath<NookEventForm, String>) -> Binding<String> {
        Binding(
            get: { form[keyPath: keyPath] },
            set: { value in
                update { form in
                    var next = form
                    next[keyPath: keyPath] = value
                    return next
                }
            }
        )
    }

    private func update(_ change: (NookEventForm) -> NookEventForm) {
        let next = change(form)
        guard next != nook.eventForm else { return }
        nook.eventForm = next
        errorMessage = nil
    }

    private func cancel() {
        withMotion(Motion.reflow) { nook.closeEventEditor(keepingDraft: false) }
    }

    private func save() {
        let form = form
        guard form.canSave else { return }
        do {
            try nook.calendar.addEvent(form.draft(calendar: .current))
            withMotion(Motion.reflow) { nook.closeEventEditor(keepingDraft: false) }
        } catch {
            errorMessage = error.message
        }
    }
}

private extension View {
    /// Draws a menu as its own label, with no button chrome and no arrow.
    func eventMenuStyle() -> some View {
        menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
    }
}

/// A small month for picking a day: today in orange, the picked day filled.
struct NookMiniMonth: View {
    @Binding var visibleMonth: Date
    let picked: Date
    let onPick: (Date) -> Void

    private static let cellHeight: CGFloat = 19
    private static let headerHeight: CGFloat = 20
    private static let weekdayHeight: CGFloat = 12
    private static let daysPerWeek = 7
    private static let weeks = 6

    var body: some View {
        let calendar = Calendar.current
        let start = NookCalendarMonthView.gridStart(for: visibleMonth, calendar: calendar)
        let dates = (0..<Self.weeks * Self.daysPerWeek).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let now = Date()
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                Text(visibleMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 0)
                nav("chevron.left", help: "Previous month") { shift(by: -1, calendar: calendar) }
                nav("chevron.right", help: "Next month") { shift(by: 1, calendar: calendar) }
            }
            .frame(height: Self.headerHeight)

            HStack(spacing: 0) {
                ForEach(Array(NookCalendarMonthView.weekdayInitials(calendar: calendar).enumerated()), id: \.offset) { _, initial in
                    Text(initial)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: Self.weekdayHeight)

            ForEach(0..<Self.weeks, id: \.self) { week in
                HStack(spacing: 0) {
                    ForEach(0..<Self.daysPerWeek, id: \.self) { weekday in
                        let index = week * Self.daysPerWeek + weekday
                        if index < dates.count {
                            cell(dates[index], now: now, calendar: calendar)
                        }
                    }
                }
            }
        }
    }

    private func cell(_ date: Date, now: Date, calendar: Calendar) -> some View {
        let isPicked = calendar.isDate(date, inSameDayAs: picked)
        let isToday = calendar.isDate(date, inSameDayAs: now)
        let inMonth = calendar.isDate(date, equalTo: visibleMonth, toGranularity: .month)
        return Button {
            onPick(date)
            if !inMonth { visibleMonth = date }
        } label: {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 10.5, weight: isPicked || isToday ? .semibold : .regular))
                .foregroundStyle(isPicked ? Color.black : (isToday ? Color.orange : Color.white.opacity(0.85)))
                .frame(width: Self.cellHeight - 2, height: Self.cellHeight - 2)
                .background(Circle().fill(isPicked ? Color.white.opacity(0.9) : Color.clear))
                .frame(maxWidth: .infinity, minHeight: Self.cellHeight, maxHeight: Self.cellHeight)
                .opacity(inMonth || isPicked ? 1 : 0.3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func nav(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 20, height: Self.headerHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func shift(by months: Int, calendar: Calendar) {
        let base = NookCalendarMonthView.monthStart(of: visibleMonth, calendar: calendar)
        visibleMonth = calendar.date(byAdding: .month, value: months, to: base) ?? visibleMonth
    }
}
