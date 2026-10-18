import EventKit
import SwiftUI

/// The To-dos section of the Nook tab: one row per app with a toggle (B8).
/// An app that is on opens its setup under its row.
struct NookTodoSettings: View {
    var nook: NookModel

    private var lang: LanguageManager { .shared }

    var body: some View {
        let hub = nook.todo
        Section("To-dos") {
            Text(lang.t("nook.todo.sources.lead"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                // Where the tab scrolls to when it is opened for the
                // to-dos. On the row, not the Section: a Section hands
                // its id to every row, which would cover the anchor below.
                .id(NookSettingsAnchor.todo)

            Toggle(lang.t("nook.todo.due.remind"), isOn: Binding(
                get: { hub.dueReminder.isEnabled },
                set: { hub.dueReminder.isEnabled = $0 }
            ))
            .settingsAnchor(SettingsIndex.entry("nook.todo.remind")!)
            Text(lang.t("nook.todo.due.remind.note"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        ForEach(NookTodoSourceKind.allCases, id: \.self) { kind in
            appSection(kind, hub: hub)
            // Notion and TickTick draw Sections of their own.
            if hub.isEnabled(kind) {
                switch kind {
                case .notion: NookNotionTodoSettings(service: hub.notion)
                case .tickTick: NookTickTickTodoSettings(service: hub.tickTick)
                default: EmptyView()
                }
            }
        }
    }

    // MARK: One app

    private func appSection(_ kind: NookTodoSourceKind, hub: NookTodoHub) -> some View {
        Section {
            anchoredAppRow(kind, hub: hub)
            if hub.isEnabled(kind) {
                switch kind {
                case .reminders: remindersSetup
                case .asana: NookRemoteTodoSettings(service: hub.asana)
                case .monday: NookRemoteTodoSettings(service: hub.monday)
                case .canvas: NookRemoteTodoSettings(service: hub.canvas)
                case .notion, .tickTick: EmptyView()
                }
            }
        }
    }

    /// The app's row with its search anchor; each app has its own entry.
    @ViewBuilder
    private func anchoredAppRow(_ kind: NookTodoSourceKind, hub: NookTodoHub) -> some View {
        switch kind {
        case .reminders:
            appRow(kind, hub: hub).settingsAnchor(SettingsIndex.entry("nook.todo.app.reminders")!)
        case .notion:
            appRow(kind, hub: hub).settingsAnchor(SettingsIndex.entry("nook.todo.app.notion")!)
        case .tickTick:
            appRow(kind, hub: hub).settingsAnchor(SettingsIndex.entry("nook.todo.app.ticktick")!)
        case .asana:
            appRow(kind, hub: hub).settingsAnchor(SettingsIndex.entry("nook.todo.app.asana")!)
        case .monday:
            appRow(kind, hub: hub).settingsAnchor(SettingsIndex.entry("nook.todo.app.monday")!)
        case .canvas:
            appRow(kind, hub: hub).settingsAnchor(SettingsIndex.entry("nook.todo.app.canvas")!)
        }
    }

    private func appRow(_ kind: NookTodoSourceKind, hub: NookTodoHub) -> some View {
        Toggle(isOn: Binding(
            get: { hub.isEnabled(kind) },
            set: { isOn in
                hub.setEnabled(kind, isOn)
                // Turning Reminders on is when macOS is asked for it.
                if isOn, kind == .reminders { nook.widgetTurnedOn(.todo) }
            }
        )) {
            HStack(spacing: 10) {
                Circle()
                    .fill(kind.dotColor)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(lang.t(kind.nameKey))
                    Text(lang.t(kind.subtitleKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
    }

    // MARK: Reminders

    @ViewBuilder
    private var remindersSetup: some View {
        let service = nook.reminders
        Picker(lang.t("nook.todo.reminders.list"), selection: Binding(
            get: { service.selectedListID },
            set: { service.selectedListID = $0 }
        )) {
            Text("Default list").tag(String?.none)
            ForEach(service.lists) { list in
                Text(list.title).tag(Optional(list.id))
            }
        }
        .disabled(!service.hasAccess)
        .settingsAnchor(SettingsIndex.entry("nook.todo.reminders.list")!)

        HStack {
            Text(statusText(service.authorization))
                .foregroundStyle(.secondary)
            Spacer()
            if service.authorization == .denied || service.authorization == .restricted {
                Button("Open System Settings") { service.openSystemSettings() }
            } else if service.authorization == .notDetermined {
                Button("Allow Access") { service.requestAccess() }
            }
        }
    }

    private func statusText(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .fullAccess: "Reminders access granted."
        case .denied: "Reminders access denied."
        case .restricted: "Reminders access is restricted."
        case .writeOnly: "Reminders access is write only."
        default: "Reminders access not requested yet."
        }
    }
}

/// A place on the Nook tab that Settings can be opened at.
enum NookSettingsAnchor: Hashable, Sendable {
    /// The to-do section, where the apps are turned on and connected.
    case todo
}
