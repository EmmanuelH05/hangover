import SwiftUI

/// Setup rows for a task app reached over the network (Asana, monday,
/// Canvas): the token, the place, the status and the scope. It draws rows,
/// not Sections, because Settings places it inside the app's own Section.
struct NookRemoteTodoSettings<Backend: NookTodoBackend>: View {
    var service: NookRemoteTodoService<Backend>

    @State private var draftToken = ""
    @State private var draftHost = ""

    private var lang: LanguageManager { .shared }
    private var kindKey: String { Backend.kind.rawValue }

    /// A rejected token keeps the field up, ready for a new one.
    private var needsToken: Bool { !service.hasToken || service.tokenRejected }

    var body: some View {
        Group {
            if Backend.needsHost {
                TextField(
                    lang.t("nook.todo.\(kindKey).host.label"),
                    text: $draftHost,
                    prompt: Text(lang.t("nook.todo.\(kindKey).host.placeholder"))
                )
                .onSubmit(connect)
                .settingsAnchor(SettingsIndex.entry("nook.todo.canvas.host")!)
            }
            tokenAnchored(tokenRow)
            buttonRow
            if Backend.needsPlace, service.hasToken {
                placeRows
            }
            statusRow
            if service.tokenRemovalFailed {
                warning("nook.todo.remote.error.tokenNotRemoved")
            }
            Text(lang.t("nook.todo.\(kindKey).scope"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            if draftHost.isEmpty, let host = service.host { draftHost = host }
        }
    }

    // MARK: Search anchors

    /// The token row with the anchor of the app it belongs to. The ids are
    /// written out one by one so the index test can read them.
    @ViewBuilder
    private func tokenAnchored<Content: View>(_ content: Content) -> some View {
        switch Backend.kind {
        case .asana: content.settingsAnchor(SettingsIndex.entry("nook.todo.asana.token")!)
        case .monday: content.settingsAnchor(SettingsIndex.entry("nook.todo.monday.token")!)
        case .canvas: content.settingsAnchor(SettingsIndex.entry("nook.todo.canvas.token")!)
        case .reminders, .notion, .tickTick: content
        }
    }

    /// The workspace or board picker with its app's anchor.
    @ViewBuilder
    private func placeAnchored<Content: View>(_ content: Content) -> some View {
        switch Backend.kind {
        case .asana: content.settingsAnchor(SettingsIndex.entry("nook.todo.asana.workspace")!)
        case .monday: content.settingsAnchor(SettingsIndex.entry("nook.todo.monday.board")!)
        case .reminders, .notion, .tickTick, .canvas: content
        }
    }

    // MARK: Token

    @ViewBuilder
    private var tokenRow: some View {
        if needsToken {
            SecureField(
                lang.t("nook.todo.\(kindKey).token.label"),
                text: $draftToken,
                prompt: Text(lang.t("nook.todo.\(kindKey).token.placeholder"))
            )
            .textContentType(.password)
            .onSubmit(connect)
        } else {
            LabeledContent(lang.t("nook.todo.\(kindKey).token.label")) {
                Text(lang.t("nook.todo.remote.token.saved"))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// The typed address differs from the saved one while a token is
    /// stored: Connect then checks the token at the new address.
    private var hostChanged: Bool {
        guard Backend.needsHost, service.hasToken, !service.tokenRejected else { return false }
        let typed = NookTodoRemoteHost.normalized(draftHost)
        return typed != nil && typed != service.host
    }

    private var buttonRow: some View {
        HStack {
            if needsToken {
                Button(lang.t("nook.todo.remote.connect"), action: connect)
                    .disabled(!canConnect)
            } else if hostChanged {
                Button(lang.t("nook.todo.remote.connect")) {
                    let host = draftHost
                    Task { await service.changeHost(host) }
                }
                .disabled(service.state == .connecting)
            }
            if service.hasToken {
                Button(lang.t("nook.todo.remote.disconnect"), role: .destructive) {
                    draftToken = ""
                    Task { await service.disconnect() }
                }
            }
            Spacer()
            if let url = setupURL {
                Link(lang.t("nook.todo.remote.openWeb", service.appName), destination: url)
            }
        }
    }

    private var setupURL: URL? {
        if Backend.needsHost {
            let host = NookTodoRemoteHost.normalized(draftHost) ?? service.host
            return host.flatMap { NookTodoSetupLink.canvasSettings(host: $0) }
        }
        return NookTodoSetupLink.url(for: Backend.kind)
    }

    private var canConnect: Bool {
        let hasToken = !draftToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasHost = !Backend.needsHost || !draftHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasToken && hasHost && service.state != .connecting
    }

    private func connect() {
        // Return in a field reaches here too, which the button's own
        // disabled state does not stop.
        if hostChanged, !canConnect {
            let host = draftHost
            Task { await service.changeHost(host) }
            return
        }
        guard canConnect else { return }
        let token = draftToken
        let host = Backend.needsHost ? draftHost : nil
        Task {
            await service.connect(token: token, host: host)
            // Once it connects the token lives only in its file. After a
            // failure it stays in the field for another try.
            if service.hasToken, !service.tokenRejected, draftToken == token {
                draftToken = ""
            }
        }
    }

    // MARK: Place

    @ViewBuilder
    private var placeRows: some View {
        placeAnchored(
            Picker(lang.t("nook.todo.\(kindKey).place.label"), selection: Binding(
                get: { service.selectedPlaceID ?? "" },
                set: { id in
                    guard !id.isEmpty else { return }
                    Task { await service.selectPlace(id) }
                }
            )) {
                if service.selectedPlaceID == nil {
                    Text(lang.t("nook.todo.remote.place.choose")).tag("")
                }
                ForEach(placeChoices) { choice in
                    Text(choice.name).tag(choice.id)
                }
            }
        )
        HStack {
            Button(lang.t("nook.todo.remote.place.reload")) {
                Task { await service.loadPlaces() }
            }
            .disabled(service.isLoadingPlaces)
            Button(lang.t("nook.todo.remote.place.refresh")) { service.recheck() }
            if service.isLoadingPlaces {
                ProgressView().controlSize(.small)
            }
        }
        if service.placesLoadFailed {
            warning("nook.todo.remote.place.loadFailed")
        }
        // The first load of the choices happens when the rows first show.
        Color.clear
            .frame(height: 0)
            .task {
                if !service.hasLoadedPlaces, !service.isLoadingPlaces {
                    await service.loadPlaces()
                }
            }
    }

    /// The loaded places, plus the saved choice when they do not have it
    /// yet (not loaded, or it was removed).
    private var placeChoices: [NookTodoPlaceChoice] {
        var choices = service.places
        if let id = service.selectedPlaceID, !choices.contains(where: { $0.id == id }) {
            choices.insert(NookTodoPlaceChoice(id: id, name: service.placeName ?? id), at: 0)
        }
        return choices
    }

    // MARK: Status

    private var statusRow: some View {
        HStack(spacing: 6) {
            if service.state == .connecting {
                ProgressView().controlSize(.small)
            }
            Text(statusText)
                .font(.caption)
                .foregroundStyle(isProblem ? Color.orange : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusText: String {
        [service.state.message(app: service.appName), service.tokenProblemText]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private var isProblem: Bool {
        switch service.state {
        case .ready, .connecting, .inactive, .noToken: false
        default: true
        }
    }

    private func warning(_ key: String) -> some View {
        Label(lang.t(key), systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
    }
}
