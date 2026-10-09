import SwiftUI

/// Settings for the TickTick task source: the API token and the list.
/// Rendered only while TickTick is the selected source.
struct NookTickTickTodoSettings: View {
    var service: NookTickTickTodoService

    /// The API token is made in the web app, under Settings, Account.
    private static let webAppURL = URL(string: "https://ticktick.com/webapp/")

    @State private var draftToken = ""

    private var lang: LanguageManager { .shared }

    /// A rejected token keeps the field up, ready for a new one.
    private var needsToken: Bool { !service.hasToken || service.tokenRejected }

    var body: some View {
        connectionSection
        if service.hasToken {
            listSection
        }
    }

    // MARK: Token

    private var connectionSection: some View {
        Section(lang.t("nook.todo.ticktick.section")) {
            if needsToken {
                SecureField(lang.t("nook.todo.ticktick.token.placeholder"), text: $draftToken)
                    .textContentType(.password)
                    .onSubmit(connect)
                Text(lang.t("nook.todo.ticktick.token.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent(lang.t("nook.todo.ticktick.token.placeholder")) {
                    Text(lang.t("nook.todo.ticktick.token.saved"))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            HStack {
                if needsToken {
                    Button(lang.t("nook.todo.ticktick.connect"), action: connect)
                        .disabled(draftToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || service.state == .connecting)
                }
                if service.hasToken {
                    Button(lang.t("nook.todo.ticktick.disconnect"), role: .destructive) {
                        draftToken = ""
                        Task { await service.disconnect() }
                    }
                }
                Spacer()
                if let url = Self.webAppURL {
                    Link(lang.t("nook.todo.ticktick.openWeb"), destination: url)
                }
            }
            statusRow
            if service.tokenRemovalFailed {
                warning("nook.todo.ticktick.error.tokenNotRemoved")
            }
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
            text += " " + lang.t("nook.todo.ticktick.savedTasks")
        }
        if service.cacheFailed {
            text += " " + lang.t("nook.todo.ticktick.cacheFailed")
        }
        return text
    }

    private var isProblem: Bool {
        switch service.state {
        case .ready, .connecting, .inactive, .noToken: service.cacheFailed
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

    // MARK: List

    private var listSection: some View {
        Section(lang.t("nook.todo.ticktick.list.section")) {
            Picker(lang.t("nook.todo.ticktick.list"), selection: Binding(
                get: { service.selectedListID },
                set: { id in Task { await service.selectList(id) } }
            )) {
                Text(lang.t("nook.todo.ticktick.inbox")).tag(TickTickClient.inboxID)
                ForEach(listChoices) { choice in
                    Text(choice.name).tag(choice.id)
                }
            }
            HStack {
                Button(lang.t("nook.todo.ticktick.list.reload")) {
                    Task { await service.loadLists() }
                }
                .disabled(service.isLoadingLists)
                Button(lang.t("nook.todo.ticktick.list.refresh")) { service.recheck() }
                if service.isLoadingLists {
                    ProgressView().controlSize(.small)
                }
            }
            if service.listsLoadFailed {
                warning("nook.todo.ticktick.list.loadFailed")
            }
            if service.isListReadOnly || !service.canWrite {
                warning("nook.todo.ticktick.error.readOnly")
            }
        }
        .task {
            if !service.hasLoadedLists, !service.isLoadingLists {
                await service.loadLists()
            }
        }
    }

    private func warning(_ key: String) -> some View {
        Label(lang.t(key), systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
    }

    /// The loaded lists, plus the saved choice when they do not have it
    /// (not loaded yet, or the list was archived).
    private var listChoices: [TickTickListChoice] {
        var choices = service.lists
        let id = service.selectedListID
        if id != TickTickClient.inboxID, !choices.contains(where: { $0.id == id }) {
            choices.insert(TickTickListChoice(id: id, name: service.displayName), at: 0)
        }
        return choices
    }
}
