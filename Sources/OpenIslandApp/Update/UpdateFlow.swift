import Foundation
import SwiftUI

/// Where a downloaded update is in its way onto the Mac (D82).
enum UpdatePhase: Equatable, Sendable {
    /// Nothing downloaded.
    case none
    /// Downloaded and held. The island asks as soon as nothing is busy.
    case waiting
    /// The ask is on the island: the pill when it is closed, a card when
    /// it is open.
    case asking
    /// Later was pressed, or the About switch is off: the island shows
    /// "Update ready" and asks again at `askAgainAt`, or never on its own.
    case ready(askAgainAt: Date?)
    /// Install was pressed. "Updating to…" shows, then the relaunch.
    case installing
}

/// What the closed island's right side says about an update.
enum UpdateClosedMark: Equatable, Sendable {
    case ready
    case whatsNew(version: String)
}

/// The card the open island shows about an update.
enum UpdateCardKind: Equatable, Sendable {
    case ask(version: String)
    case ready(version: String)
    case whatsNew(WhatsNewPending)

    /// The ask goes above the agents row; the other two go under it.
    var isAsk: Bool {
        if case .ask = self { return true }
        return false
    }
}

/// Install the moment it lands, with the island asking first (D82).
///
/// Sparkle downloads a new version by itself and hands this flow the block
/// that installs it and relaunches the app (`noteDownloaded`). The flow
/// asks when nothing is busy, holds the ask while something is, and after
/// Later keeps a mark on the closed island and asks again after a day or
/// at the next launch. After the relaunch, `noteLaunch` reads which
/// version the user last saw and gives the What's new card its words.
///
/// Pure where it can be: every rule takes `now`, the app's state comes in
/// through closures the app model installs, and the clock is a tick the
/// app model drives.
@MainActor
@Observable
final class UpdateFlow {
    private(set) var phase: UpdatePhase = .none
    /// The version Sparkle downloaded, nil until it has.
    private(set) var pendingVersion: String?
    /// What the What's new card shows this run, nil once it was dismissed
    /// or when there is nothing to show.
    private(set) var whatsNew: WhatsNewPending?
    /// True once the island opened with the What's new card on it; the
    /// closed island stops announcing it then. The card stays until Done.
    private(set) var whatsNewWasShown = false

    // Installed by the app model.

    /// The About switch. Off means the island never asks: it shows
    /// "Update ready" and waits for Restart now.
    @ObservationIgnored var installsAutomatically: () -> Bool = { true }
    /// A recording running, an agent request waiting, the mirror or the
    /// photo booth on (K7). The ask never shows over any of those.
    @ObservationIgnored var isBusy: () -> Bool = { false }
    /// Shows "Updating to 1.0.14…" on the closed island for the moment
    /// before the relaunch.
    @ObservationIgnored var showUpdating: (_ text: String) -> Void = { _ in }
    /// The ask just went up on the island; the app model pops the island.
    @ObservationIgnored var onAskShown: () -> Void = {}
    /// The ask went up or came down; the app model arms the shortcuts.
    @ObservationIgnored var onAskChanged: () -> Void = {}
    /// Words for the island, in the app's language.
    @ObservationIgnored var lang: () -> LanguageManager = { .shared }

    @ObservationIgnored private var install: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let catalog: WhatsNewCatalog
    @ObservationIgnored private let sleep: (Duration) async -> Void
    @ObservationIgnored private let tickInterval: Duration?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var installTask: Task<Void, Never>?

    /// How long "Later" holds the ask off.
    static let askAgainAfter: TimeInterval = 24 * 60 * 60
    /// How long "Updating to…" shows before the relaunch.
    static let updatingDuration: Duration = .seconds(3)
    /// How often the flow looks again while it holds an update.
    static let tickInterval: Duration = .seconds(10)
    static let lastSeenVersionKey = "update.lastSeenVersion"

    /// `tickInterval` nil never looks again on its own: a test drives
    /// `reconsider` by hand. `sleep` is the wait before the relaunch.
    init(
        defaults: UserDefaults,
        catalog: WhatsNewCatalog = .bundled(),
        tickInterval: Duration? = UpdateFlow.tickInterval,
        sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.defaults = defaults
        self.catalog = catalog
        self.tickInterval = tickInterval
        self.sleep = sleep
    }

    // MARK: - What the island shows

    /// True while the ask is up, which is when the shortcuts answer it.
    var isAsking: Bool { phase == .asking }

    /// The mark on the closed island's right side, nil for none. The
    /// update's own states come first; What's new is for the run after.
    var closedMark: UpdateClosedMark? {
        if case .ready = phase { return .ready }
        if let whatsNew, !whatsNewWasShown { return .whatsNew(version: whatsNew.version) }
        return nil
    }

    /// The card the open island shows, nil for none.
    var card: UpdateCardKind? {
        switch phase {
        case .asking:
            if let pendingVersion { return .ask(version: pendingVersion) }
        case .ready:
            if let pendingVersion { return .ready(version: pendingVersion) }
        case .none, .waiting, .installing:
            break
        }
        if let whatsNew { return .whatsNew(whatsNew) }
        return nil
    }

    /// The line under the switch in Settings, About: nil with nothing
    /// downloaded.
    var settingsStatus: String? {
        guard let pendingVersion else { return nil }
        let lang = lang()
        switch phase {
        case .waiting, .asking:
            return lang.t("update.about.status.asks", pendingVersion)
        case .ready, .installing, .none:
            return lang.t("update.about.status.restart", pendingVersion)
        }
    }

    // MARK: - Launch

    /// Reads which version the user last ran. A first run learns the
    /// version and shows nothing (the tour is for that). A run on a newer
    /// version than the last one gets the What's new card, covering every
    /// version since, when any of them has something to show.
    ///
    /// Builds before this one never wrote the version. A copy that ran
    /// before and has no record is taken to have run the version just
    /// before this one, which shows this version's own card once.
    func noteLaunch(currentVersion: String, hasRunBefore: Bool = false) {
        defer { defaults.set(currentVersion, forKey: Self.lastSeenVersionKey) }
        let releases: [WhatsNewRelease]
        if let lastSeen = defaults.string(forKey: Self.lastSeenVersionKey) {
            guard AppVersion.compare(lastSeen, currentVersion) == .orderedAscending else { return }
            releases = catalog.releases(after: lastSeen, upTo: currentVersion)
        } else if hasRunBefore {
            releases = catalog.releases.filter {
                AppVersion.compare($0.version, currentVersion) == .orderedSame && !$0.items.isEmpty
            }
        } else {
            return
        }
        guard !releases.isEmpty else { return }
        whatsNew = WhatsNewPending(releases: releases)
        whatsNewWasShown = false
    }

    /// The island opened. A What's new card on it counts as seen, and the
    /// closed island stops announcing it.
    func noteIslandOpened() {
        guard whatsNew != nil, !whatsNewWasShown else { return }
        whatsNewWasShown = true
    }

    /// Done on the What's new card.
    func dismissWhatsNew() {
        whatsNew = nil
    }

    // MARK: - The downloaded update

    /// Sparkle downloaded `version` and holds `install`, which installs it
    /// and relaunches the app. The ask goes up at once when nothing is
    /// busy. Sparkle can hand the same update over again on a later check;
    /// that keeps the newer block and changes nothing else, which is what
    /// keeps Later's day and an install under way intact. A newer version
    /// starts the flow over.
    func noteDownloaded(version: String, install: @escaping () -> Void, now: Date = .now) {
        if phase == .installing { return }
        self.install = install
        if version == pendingVersion, phase != .none {
            reconsider(now: now)
            return
        }
        pendingVersion = version
        setPhase(.waiting)
        reconsider(now: now)
        startTicking()
    }

    /// Looks at the state again: the ask goes up when it may, comes down
    /// when something got busy, and comes back after Later's day. Called
    /// on every tick and by the app model when something it watches
    /// changes. Safe to call at any time.
    func reconsider(now: Date = .now) {
        guard pendingVersion != nil else { return }
        let automatic = installsAutomatically()
        let canAsk = automatic && !isBusy()
        switch phase {
        case .none, .installing:
            return
        case .waiting:
            if canAsk {
                showAsk()
            } else if !automatic {
                setPhase(.ready(askAgainAt: nil))
            }
        case .asking:
            if !canAsk {
                setPhase(automatic ? .waiting : .ready(askAgainAt: nil))
            }
        case let .ready(askAgainAt):
            if let askAgainAt {
                if now >= askAgainAt, canAsk { showAsk() }
            } else if automatic {
                // The switch came back on: the next free moment asks.
                setPhase(.waiting)
                if canAsk { showAsk() }
            }
        }
    }

    /// Later: a mark on the closed island, and the ask again in a day.
    func answerLater(now: Date = .now) {
        guard phase == .asking || phase == .waiting else { return }
        setPhase(.ready(askAgainAt: now.addingTimeInterval(Self.askAgainAfter)))
    }

    /// Install, or Restart now: "Updating to…" for a moment, then the
    /// relaunch through Sparkle's block. Nothing installs over a recording
    /// or a request that began since the ask went up (K7): the press is
    /// dropped, and the next look takes the ask down.
    func answerInstall(now: Date = .now) {
        guard let pendingVersion, let install, phase != .installing, phase != .none else { return }
        guard !isBusy() else {
            reconsider(now: now)
            return
        }
        setPhase(.installing)
        tickTask?.cancel()
        tickTask = nil
        showUpdating(lang().t("update.updating", pendingVersion))
        installTask?.cancel()
        installTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.sleep(Self.updatingDuration)
            guard !Task.isCancelled else { return }
            install()
        }
    }

    // MARK: - Private

    private func showAsk() {
        setPhase(.asking)
        onAskShown()
    }

    private func setPhase(_ next: UpdatePhase) {
        let wasAsking = phase == .asking
        phase = next
        if wasAsking != (next == .asking) { onAskChanged() }
    }

    private func startTicking() {
        tickTask?.cancel()
        guard let tickInterval else { return }
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: tickInterval)
                guard !Task.isCancelled, let self, self.pendingVersion != nil, self.phase != .installing else { return }
                self.reconsider()
            }
        }
    }
}
