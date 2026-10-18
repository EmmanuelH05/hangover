import SwiftUI

struct NookTimerSettings: View {
    var nook: NookModel

    var body: some View {
        Section("Focus timer") {
            Stepper(
                "\(lang.t("nook.timer.settings.length")): \(NookFocusTimer.format(nook.timer.preset))",
                value: Binding(
                    // Typed lengths can be seconds or longer than 3 hours.
                    get: { min(max(Int((nook.timer.preset / 60).rounded()), 1), 180) },
                    set: { nook.timer.set(preset: TimeInterval($0 * 60)) }
                ),
                in: 1...180
            )
            .settingsAnchor(SettingsIndex.entry("nook.timer.length")!)
            Toggle(lang.t("nook.timer.settings.sound"), isOn: Binding(
                get: { nook.timer.soundEnabled },
                set: { nook.timer.soundEnabled = $0 }
            ))
            .settingsAnchor(SettingsIndex.entry("nook.timer.sound")!)
        }
        Section {
            minutesStepper("nook.timer.pomodoro.settings.work", \.work)
                .settingsAnchor(SettingsIndex.entry("nook.timer.pomodoro.work")!)
            minutesStepper("nook.timer.pomodoro.settings.shortBreak", \.shortBreak)
                .settingsAnchor(SettingsIndex.entry("nook.timer.pomodoro.shortBreak")!)
            minutesStepper("nook.timer.pomodoro.settings.longBreak", \.longBreak)
                .settingsAnchor(SettingsIndex.entry("nook.timer.pomodoro.longBreak")!)
            Stepper(
                lang.t("nook.timer.pomodoro.settings.rounds", nook.timer.pomodoroPlan.rounds),
                value: Binding(
                    get: { nook.timer.pomodoroPlan.rounds },
                    set: { rounds in update { $0.rounds = rounds } }
                ),
                in: NookPomodoroPlan.roundsRange
            )
            .settingsAnchor(SettingsIndex.entry("nook.timer.pomodoro.rounds")!)
        } header: {
            Text(lang.t("nook.timer.pomodoro"))
        } footer: {
            Text(lang.t("nook.timer.pomodoro.settings.note"))
        }
    }

    private var lang: LanguageManager { .shared }

    /// One stepper for a length of the pomodoro plan, in whole minutes.
    private func minutesStepper(
        _ key: String,
        _ length: WritableKeyPath<NookPomodoroPlan, TimeInterval>
    ) -> some View {
        let minutes = Int((nook.timer.pomodoroPlan[keyPath: length] / 60).rounded())
        let range = NookPomodoroPlan.lengthRange
        return Stepper(
            lang.t(key, minutes),
            value: Binding(
                get: { minutes },
                set: { value in update { $0[keyPath: length] = TimeInterval(value * 60) } }
            ),
            in: Int(range.lowerBound / 60)...Int(range.upperBound / 60)
        )
    }

    private func update(_ change: (inout NookPomodoroPlan) -> Void) {
        var plan = nook.timer.pomodoroPlan
        change(&plan)
        nook.timer.set(pomodoroPlan: plan)
    }
}
