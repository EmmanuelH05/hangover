import SwiftUI

/// Settings for the Notion task source: token, database and column mapping.
/// Rendered only while Notion is the selected source.
struct NookNotionTodoSettings: View {
    var service: NookNotionTodoService

    private static let integrationsURL = URL(string: "https://www.notion.so/my-integrations")

    @State private var draftToken = ""

    private var lang: LanguageManager { .shared }

    /// A rejected token keeps the field up, ready for a new one.
    private var needsToken: Bool { !service.hasToken || service.tokenRejected }

    var body: some View {
        connectionSection
        if service.hasToken {
            databaseSection
        }
        if service.hasToken, let schema = service.schema {
            NookNotionMappingSection(service: service, schema: schema)
        }
    }

    // MARK: Token

    private var connectionSection: some View {
        Section(lang.t("nook.todo.notion.section")) {
            if needsToken {
                SecureField(lang.t("nook.todo.notion.token.placeholder"), text: $draftToken)
                    .textContentType(.password)
                    .onSubmit(connect)
                Text(lang.t("nook.todo.notion.token.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent(lang.t("nook.todo.notion.account")) {
                    Text(service.accountName ?? "Notion")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            HStack {
                if needsToken {
                    Button(lang.t("nook.todo.notion.connect"), action: connect)
                        .disabled(draftToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || service.state == .connecting)
                }
                if service.hasToken {
                    Button(lang.t("nook.todo.notion.disconnect"), role: .destructive) {
                        draftToken = ""
                        Task { await service.disconnect() }
                    }
                }
                Spacer()
                if let url = Self.integrationsURL {
                    Link(lang.t("nook.todo.notion.openIntegrations"), destination: url)
                }
            }
            statusRow
        }
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            if service.state == .connecting {
                ProgressView().controlSize(.small)
            }
            Text(statusText)
                .font(.caption)
                .foregroundStyle(isProblem ? Color.orange : Color.secondary)
        }
    }

    private var statusText: String {
        var text = lang.t(service.state.messageKey)
        if service.isShowingCachedItems {
            text += " " + lang.t("nook.todo.notion.savedTasks")
        }
        if service.cacheFailed {
            text += " " + lang.t("nook.todo.notion.cacheFailed")
        }
        return text
    }

    private var isProblem: Bool {
        switch service.state {
        case .ready, .connecting, .inactive, .noToken, .noDatabase: service.cacheFailed
        default: true
        }
    }

    private func connect() {
        let token = draftToken
        Task {
            await service.connect(token: token)
            // Once it connects the token lives only in the Keychain. After a
            // failure it stays in the field for another try.
            if service.hasToken, !service.tokenRejected, draftToken == token {
                draftToken = ""
            }
        }
    }

    // MARK: Database

    private var databaseSection: some View {
        Section(lang.t("nook.todo.notion.database.section")) {
            Picker(lang.t("nook.todo.notion.database"), selection: Binding(
                get: { service.selectedDatabaseID },
                set: { id in Task { await service.selectDatabase(id) } }
            )) {
                Text(lang.t("nook.todo.notion.database.choose")).tag(String?.none)
                ForEach(databaseChoices) { choice in
                    Text(choice.title).tag(Optional(choice.id))
                }
            }
            HStack {
                Button(lang.t("nook.todo.notion.database.reload")) {
                    Task { await service.loadDatabases() }
                }
                .disabled(service.isLoadingDatabases)
                Button(lang.t("nook.todo.notion.database.refresh")) { service.recheck() }
                    .disabled(service.selectedDatabaseID == nil)
                if service.isLoadingDatabases {
                    ProgressView().controlSize(.small)
                }
            }
            if service.hasLoadedDatabases, service.databases.isEmpty {
                Text(lang.t("nook.todo.notion.database.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !service.canInsert {
                capabilityNote("nook.todo.notion.error.cannotInsert")
            }
            if !service.canUpdate {
                capabilityNote("nook.todo.notion.error.cannotUpdate")
            }
        }
        .task {
            if !service.hasLoadedDatabases, !service.isLoadingDatabases {
                await service.loadDatabases()
            }
        }
    }

    /// The loaded list, plus the saved choice when the list does not have it
    /// (not loaded yet, or the database is no longer shared).
    private var databaseChoices: [NotionDatabaseChoice] {
        var choices = service.databases
        if let id = service.selectedDatabaseID, !choices.contains(where: { $0.id == id }) {
            choices.insert(NotionDatabaseChoice(id: id, title: service.displayName), at: 0)
        }
        return choices
    }

    private func capabilityNote(_ key: String) -> some View {
        Label(lang.t(key), systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
    }
}
