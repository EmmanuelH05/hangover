import EventKit
import SwiftUI

struct NookTodoSettings: View {
    var nook: NookModel

    private var lang: LanguageManager { .shared }

    var body: some View {
        let hub = nook.todo
        let service = nook.reminders
        Section("Todo") {
            Picker(lang.t("nook.todo.source"), selection: Binding(
                get: { hub.selectedKind },
                set: { kind in
                    hub.selectedKind = kind
                    // Picking Reminders is when macOS is asked for it.
                    if kind == .reminders { nook.widgetTurnedOn(.todo) }
                }
            )) {
                Text(lang.t("nook.todo.source.reminders")).tag(NookTodoSourceKind.reminders)
                Text(lang.t("nook.todo.source.notion")).tag(NookTodoSourceKind.notion)
                Text(lang.t("nook.todo.source.ticktick")).tag(NookTodoSourceKind.tickTick)
            }

            if hub.selectedKind == .reminders {
                Picker("List", selection: Binding(
                    get: { service.selectedListID },
                    set: { service.selectedListID = $0 }
                )) {
                    Text("Default list").tag(String?.none)
                    ForEach(service.lists) { list in
                        Text(list.title).tag(Optional(list.id))
                    }
                }
                .disabled(!service.hasAccess)

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
        }

        if hub.selectedKind == .notion {
            NookNotionTodoSettings(service: hub.notion)
        }
        if hub.selectedKind == .tickTick {
            NookTickTickTodoSettings(service: hub.tickTick)
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
