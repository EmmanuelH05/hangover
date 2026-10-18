import SwiftUI

/// Glue between `AppModel` and the update flow (D82): what counts as busy,
/// how the ask and the marks show on the island, and the shortcuts that
/// answer the ask. The rules live in `UpdateFlow`.
extension AppModel {
    func configureUpdateFlow() {
        updateFlow.lang = { [weak self] in self?.lang ?? .shared }
        updateFlow.installsAutomatically = { [weak self] in self?.updateChecker.installsAutomatically ?? true }
        updateFlow.isBusy = { [weak self] in self?.updateAskIsBlocked ?? true }
        updateFlow.showUpdating = { [weak self] text in
            // A little longer than the wait before the relaunch, which
            // keeps the words on the island until the app goes.
            self?.nook.showTransient(
                symbol: "arrow.triangle.2.circlepath",
                text: text,
                duration: UpdateFlow.updatingDuration + .seconds(2),
                spins: true
            )
        }
        updateFlow.onAskShown = { [weak self] in self?.notchPop() }
        updateFlow.onAskChanged = { [weak self] in self?.refreshUpdateHotkeyArming() }
        updateChecker.onDownloaded = { [weak self] version, install in
            self?.updateFlow.noteDownloaded(version: version, install: install)
        }
        updateChecker.onInstallsAutomaticallyChanged = { [weak self] in self?.updateFlow.reconsider() }
    }

    /// The ask never shows over a recording, an agent request waiting, or
    /// the mirror or the photo booth on (K7). Nothing else counts: not the
    /// island being closed, not the time of day.
    var updateAskIsBlocked: Bool {
        if surfacedSessions.contains(where: { $0.phase.requiresAttention }) { return true }
        if nook.isMirrorOn || nook.photoBooth.session != nil { return true }
        switch nook.record.phase {
        case .idle, .finished, .failed: return false
        case .countdown, .recording, .paused, .saving: return true
        }
    }

    /// The ask as the closed pill draws it: the arrow, the question in the
    /// left wing, Later and Install as chips on the right (K4, K5, K6).
    var updateAskActivity: NookClosedActivity? {
        guard updateFlow.isAsking else { return nil }
        let hint = agentHotkeys.hint
        return NookClosedActivity(
            leading: .symbol("arrow.down.circle.fill", V6Palette.paper),
            trailing: .chips(NookClosedChips(
                deny: NookClosedChip(keys: hint.deny, title: lang.t("update.ask.later")),
                approve: NookClosedChip(keys: hint.approve, title: lang.t("update.ask.install"), isPrimary: true)
            )),
            yieldsToAgents: false,
            leadingText: lang.t("update.ask")
        )
    }

    /// The mark on the closed island's right side: "Update ready" after
    /// Later, "1.0.14 · what's new" after a relaunch. Nil for none.
    var updateClosedMark: NookSideSlotContent? {
        switch updateFlow.closedMark {
        case .ready: .notice(lang.t("update.mark.ready"))
        case let .whatsNew(version): .notice(lang.t("update.mark.whatsNew", version))
        case nil: nil
        }
    }

    /// The keys under the ask card's body, nil when neither shortcut is
    /// ready.
    var updateAskHint: AgentHotkeyHint? {
        let hint = agentHotkeys.hint
        return hint.isEmpty ? nil : hint
    }

    /// Height the update card adds to the open island, with its row gap.
    var updateCardHeight: CGFloat {
        updateFlow.card.map { UpdateCardLayout.pageHeight(for: $0) } ?? 0
    }

    // MARK: - Shortcuts

    /// The approve and deny shortcuts answer the ask while it is up, with
    /// the agents on or off. With the agents off the controller is held
    /// only for that long.
    func refreshUpdateHotkeyArming() {
        if updateFlow.isAsking, !agentHotkeys.isActive, let agentHotkeyRegistrar {
            agentHotkeys.activate(registrar: agentHotkeyRegistrar)
        }
        refreshAgentHotkeyArming(hasWaitingSession: hasSessionWaitingForApproval)
        if !updateFlow.isAsking, !agentsEnabled, agentHotkeys.isActive {
            agentHotkeys.deactivate()
        }
    }

    var hasSessionWaitingForApproval: Bool {
        state.sessionsByID.values.contains { $0.phase == .waitingForApproval && $0.permissionRequest != nil }
    }

    // MARK: - The card's buttons

    func updateCardLater() {
        updateFlow.answerLater()
    }

    func updateCardInstall() {
        updateFlow.answerInstall()
    }

    func updateCardDone() {
        updateFlow.dismissWhatsNew()
    }

    /// "See all" opens the release notes on the web.
    func updateCardSeeAll() {
        NSWorkspace.shared.open(AppBrand.releasesURL)
    }
}
