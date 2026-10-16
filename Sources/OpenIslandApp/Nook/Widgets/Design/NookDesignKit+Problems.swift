import Foundation

/// One shelf's trouble at its last read, with the tab it belongs to.
struct NookDesignStoreProblem: Equatable, Identifiable, Sendable {
    let tab: NookDesignTab
    let problem: NookDesignLoadProblem

    var id: String { tab.rawValue }

    /// The shelf's name as Settings lists it.
    var nameKey: String {
        switch tab {
        case .colors: "nook.design.settings.colors"
        case .links: "nook.design.settings.links"
        case .references: "nook.design.settings.references"
        }
    }

    /// What happened and what it means, in a sentence for Settings.
    func settingsText(_ lang: LanguageManager = .shared) -> String {
        switch problem {
        case .unreadable:
            lang.t("nook.design.settings.problem.unreadable")
        case .unreadableNotKept:
            lang.t("nook.design.settings.problem.unreadableNotKept")
        case let .partlyRead(skipped):
            lang.t("nook.design.settings.problem.partly", skipped)
        case let .partlyReadNotKept(skipped):
            lang.t("nook.design.settings.problem.partlyNotKept", skipped)
        case .newerVersion:
            lang.t("nook.design.settings.problem.newer")
        case let .indexMissing(recovered):
            lang.t("nook.design.settings.problem.indexMissing", recovered)
        case let .picturesTakenBack(count):
            lang.t("nook.design.settings.problem.takenBack", count)
        }
    }

    /// The caption with the shelf's name in front.
    func settingsLine(_ lang: LanguageManager = .shared) -> String {
        lang.t("nook.design.settings.problem.line", lang.t(nameKey), settingsText(lang))
    }

    /// The short line the card shows for the shelf on its tab.
    func cardLine(_ lang: LanguageManager = .shared) -> String {
        if case .newerVersion = problem {
            return lang.t("nook.design.notice.loadNewer", lang.t(nameKey))
        }
        return lang.t("nook.design.notice.loadProblem", lang.t(nameKey))
    }
}

extension NookDesignKit {
    /// The line that stands in the card for as long as the eyedropper's
    /// shortcut is set and does not work, whatever the cause: macOS refused
    /// it, uses it itself, an agent shortcut or Record has the keys, or it
    /// breaks a rule. It is the only place besides Settings that reports it,
    /// and it opens Settings.
    var standingNotice: NookDesignStandingNotice? {
        let lang = LanguageManager.shared
        guard let combo = hotkey.combo else { return nil }
        let text: String
        switch hotkey.status {
        case let .failed(code): text = lang.t("nook.design.standing.failed", Int(code))
        case .usedBySystem: text = lang.t("nook.design.standing.system")
        case .invalid(.usedByAgentShortcut):
            text = lang.t(holder(of: combo).standingKey)
        case .invalid(.needsModifiers): text = lang.t("nook.design.standing.invalid")
        case .none, .inactive, .ready: return nil
        }
        return NookDesignStandingNotice(text: text, opensSettings: true)
    }

    /// A press on the standing line.
    func openSettingsFromStandingNotice() {
        openSettings()
    }

    /// The island opened. Every shelf is looked at for a change another copy
    /// of the app made, which keeps what is shown current, and the line for a
    /// shelf that had trouble reading is shown once, on its tab.
    func islandOpened() {
        guard isLive else { return }
        palettes.refreshIfChanged()
        links.refreshIfChanged()
        references.refreshIfChanged()
        noteTabShown()
    }

    /// The island closed. Whatever is still waiting to be written is
    /// written, which keeps a quit right after a change from losing it.
    @discardableResult
    func islandClosed() -> Task<Void, Never> {
        closeFlushCount += 1
        return Task { [weak self] in await self?.flush() }
    }

    /// True while any shelf has a write that is not on disk yet.
    var hasPendingWrites: Bool {
        palettes.hasPendingWrites || links.hasPendingWrites || references.hasPendingWrites
    }

    /// Says on the card, once, that the shelf of the tab now showing had
    /// trouble reading. Called when the island opens and when the tab moves.
    func noteTabShown() {
        guard isLive, let found = storeProblems.first(where: { $0.tab == tab }),
              reportedProblems[found.tab] != found.problem else { return }
        reportedProblems[found.tab] = found.problem
        let isInfo: Bool
        if case .picturesTakenBack = found.problem { isInfo = true } else { isInfo = false }
        postText(found.cardLine(), isInfo ? .info : .error, quietly: true)
    }

    /// The trouble each shelf had at its last read, every one that has
    /// any, in the order of the tabs.
    var storeProblems: [NookDesignStoreProblem] {
        var result: [NookDesignStoreProblem] = []
        if let problem = palettes.loadProblem { result.append(NookDesignStoreProblem(tab: .colors, problem: problem)) }
        if let problem = links.loadProblem { result.append(NookDesignStoreProblem(tab: .links, problem: problem)) }
        if let problem = references.loadProblem { result.append(NookDesignStoreProblem(tab: .references, problem: problem)) }
        return result
    }
}

/// Who holds keys the eyedropper may not take. The agents', Record's and the
/// new note shortcut's keys are checked as one list, and the sentence that
/// refuses them still says whose they are.
enum NookTakenKeysHolder: CaseIterable, Sendable {
    case agent, record, notes

    /// The island's standing line under the eyedropper.
    var standingKey: String {
        switch self {
        case .agent: "nook.design.standing.agent"
        case .record: "nook.design.standing.record"
        case .notes: "nook.design.standing.notes"
        }
    }

    /// The line under the shortcut in Settings.
    var problemKey: String {
        switch self {
        case .agent: "nook.design.hotkey.problem.agent"
        case .record: "nook.design.hotkey.problem.record"
        case .notes: "nook.design.hotkey.problem.notes"
        }
    }
}

extension NookDesignKit {
    func holder(of combo: AgentHotkeyCombo) -> NookTakenKeysHolder {
        if nook?.record.reservedShortcuts.contains(combo) == true { return .record }
        if nook?.notes.hotkey.combo == combo { return .notes }
        return .agent
    }

    /// The Settings sentence for a shortcut that breaks a rule. Keys another
    /// shortcut holds are named by their holder; a rule the keys break by
    /// themselves names nobody.
    func problemMessageKey(_ problem: NookDesignHotkeyProblem, combo: AgentHotkeyCombo?) -> String {
        guard problem == .usedByAgentShortcut, let combo else { return problem.messageKey }
        return holder(of: combo).problemKey
    }
}
