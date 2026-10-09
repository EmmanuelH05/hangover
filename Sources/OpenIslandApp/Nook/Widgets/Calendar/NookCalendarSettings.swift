import EventKit
import SwiftUI

struct NookCalendarSettings: View {
    var nook: NookModel

    @AppStorage(NookCalendarService.nextUpEnabledKey) private var nextUpEnabled = true

    var body: some View {
        let service = nook.calendar
        Section("Calendar") {
            Toggle("Next-up notices (10 and 2 minutes before)", isOn: $nextUpEnabled)

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

            Button("Refresh") { service.refresh() }
                .disabled(!service.hasAccess)
        }
    }

    private func statusText(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .fullAccess: "Calendar access: allowed"
        case .notDetermined: "Calendar access: not requested yet"
        case .denied: "Calendar access: denied"
        case .restricted: "Calendar access: restricted"
        case .writeOnly: "Calendar access: write only (full access needed)"
        @unknown default: "Calendar access: unknown"
        }
    }
}
