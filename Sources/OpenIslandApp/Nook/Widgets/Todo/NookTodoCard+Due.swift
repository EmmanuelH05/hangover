import SwiftUI

/// The date button beside the add field: medium and large cards only.
extension NookTodoCard {
    @ViewBuilder
    func dueControl(_ source: any NookTodoSource) -> some View {
        let lang = LanguageManager.shared
        let calendar = Calendar.current
        let now = Date()
        let locale = Locale(identifier: lang.language.resolvedCode)
        let canSetDue = source.canSetDue
        let label = dueDraft.map {
            NookTodoDueChoices.buttonLabel(for: $0, now: now, calendar: calendar, lang: lang, locale: locale)
        }
        HStack(spacing: 4) {
            Menu {
                dueMenu(now: now, calendar: calendar, lang: lang, locale: locale)
            } label: {
                // A day picked earlier stays on the button while the source
                // cannot take dates for now, dimmed (D3).
                dueChip(label: label, isOn: canSetDue)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(!canSetDue)
            .help(canSetDue ? lang.t("nook.todo.due.button") : (source.dueUnavailableReason ?? ""))
            .accessibilityLabel(lang.t("nook.todo.due.button"))
            .accessibilityValue(label ?? (canSetDue ? lang.t("nook.todo.due.none") : ""))
            .popover(isPresented: $isPickingDate, arrowEdge: .bottom) {
                datePopover(calendar: calendar)
            }
            // The island stays open while the picker is up (D20).
            .onChange(of: isPickingDate) { _, isUp in
                nook.setDraft(.todo, isUnsaved: isUp || NookDraft.isUnsaved(draft))
                // A click in the popover is not a click outside the island (D7).
                nook.todo.isPickingDate = isUp
            }

            // The day can be dropped even while the button is off.
            if dueDraft != nil {
                clearButton(lang: lang)
            }
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private func dueMenu(now: Date, calendar: Calendar, lang: LanguageManager, locale: Locale) -> some View {
        ForEach(NookTodoDueChoices.options(now: now, calendar: calendar)) { choice in
            let title = choice.title(lang: lang, locale: locale, calendar: calendar)
            Button {
                dueDraft = choice.day
            } label: {
                if choice.day == dueDraft {
                    Label(title, systemImage: "checkmark")
                } else {
                    Text(title)
                }
            }
        }
        Divider()
        Button(lang.t("nook.todo.due.pick")) { isPickingDate = true }
        Button {
            dueDraft = nil
        } label: {
            if dueDraft == nil {
                Label(lang.t("nook.todo.due.none"), systemImage: "checkmark")
            } else {
                Text(lang.t("nook.todo.due.none"))
            }
        }
    }

    private func dueChip(label: String?, isOn: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "calendar")
                .font(.system(size: 11, weight: .medium))
            if let label {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(label == nil ? Color.white.opacity(isOn ? 0.6 : 0.25) : accent.highlight(.white.opacity(0.9)))
        .opacity(label != nil && !isOn ? 0.5 : 1)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.08)))
        .contentShape(Rectangle())
    }

    private func clearButton(lang: LanguageManager) -> some View {
        Button {
            dueDraft = nil
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(lang.t("nook.todo.due.clear"))
        .accessibilityLabel(lang.t("nook.todo.due.clear"))
    }

    /// A small month. Picking a day sets it and puts the popover away.
    private func datePopover(calendar: Calendar) -> some View {
        let today = calendar.startOfDay(for: Date())
        return DatePicker(
            "",
            selection: Binding(
                get: { dueDraft.flatMap { NookTodoDay.date(from: $0, calendar: calendar) } ?? today },
                set: { date in
                    dueDraft = NookTodoDay.components(of: date, calendar: calendar)
                    isPickingDate = false
                }
            ),
            in: today...,
            displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .labelsHidden()
        .padding(8)
    }
}
