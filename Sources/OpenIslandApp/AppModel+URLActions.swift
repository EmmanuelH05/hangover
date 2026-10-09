import Foundation
import OSLog

private let linkLog = Logger(subsystem: "app.openisland", category: "links")

/// Links from other apps on the live models. `IslandURLAction` reads the
/// link and holds the whole list of what one can do; this only carries an
/// action out.
extension AppModel {
    /// Reads a `hangover://` link and carries it out. A link that does
    /// not read is ignored with a log line, and every link is ignored while
    /// links from other apps are switched off. Returns what was done, nil
    /// for an ignored link.
    @discardableResult
    func handleIncomingURL(_ url: URL) -> IslandURLAction? {
        guard allowsLinksFromOtherApps else {
            linkLog.notice("Ignored a link: links from other apps are switched off")
            return nil
        }
        switch IslandURLAction.parse(url) {
        case .success(let action):
            return perform(action) ? action : nil
        case .failure(let error):
            linkLog.notice("Ignored a link: \(error.logLine, privacy: .public)")
            return nil
        }
    }

    /// A link arrived whose text is not a URL at all. Nothing is done with
    /// it beyond a log line.
    func noteUnreadableLink(_ text: String?) {
        linkLog.notice("Ignored a link: \(IslandLinkLog.unreadableLine(for: text), privacy: .public)")
    }

    /// Carries out one action. False when the island's state turns it
    /// down: a card waiting for an answer is up, or the Mirror widget is
    /// not on this display's page.
    @discardableResult
    func perform(_ action: IslandURLAction) -> Bool {
        switch action {
        case .openNook:
            return showPage(.nook)
        case .openAgents:
            guard agentsEnabled else {
                linkLog.notice("Ignored a link: agents are switched off")
                return false
            }
            return showPage(.agents)
        case .startTimer(let minutes):
            if let minutes {
                nook.timer.start(length: TimeInterval(minutes * 60))
            } else {
                nook.timer.reset()
                nook.timer.start()
            }
            return true
        case .startPomodoro:
            nook.timer.startPomodoro()
            return true
        case .stopTimer:
            nook.timer.reset()
            return true
        case .setMirror(let change):
            return setMirror(change.applied(to: nook.isMirrorOn))
        case .setRingLight(let change):
            // The light itself only shows while the mirror is on.
            nook.isRingLightOn = change.applied(to: nook.isRingLightOn)
            return true
        }
    }

    /// True while the open island shows an approval or a question in a row
    /// of its list. The Nook page shows no rows, and a card is told apart
    /// by its open reason.
    var showsWaitingRequestInList: Bool {
        notchStatus == .opened
            && !showsNookPage
            && islandListSessions.contains { $0.phase.requiresAttention }
    }

    private func showPage(_ page: NookOpenedPage) -> Bool {
        let move = IslandURLPageMove.resolve(
            status: notchStatus,
            reason: notchOpenReason,
            showsWaitingRequest: showsWaitingRequestInList
        )
        switch move {
        case .open:
            // Opened the way a click opens it: it stays until a click
            // outside.
            notchOpen(reason: .click, page: page)
        case .turn:
            if page == .nook { showNookPage() } else { showAgentsPage() }
            if IslandURLPageMove.pinsOnTurn(reason: notchOpenReason) {
                overlay.pinIslandOpenedForLink()
            }
        case .refuse:
            linkLog.notice("Ignored a link: an approval or a question is on screen")
            return false
        }
        return true
    }

    /// The mirror lives at the top of the Nook page and needs its tile
    /// there. Turning it on opens the island on that page, which is also
    /// what shows the user that the camera is on.
    private func setMirror(_ isOn: Bool) -> Bool {
        guard isOn else {
            nook.isMirrorOn = false
            return true
        }
        guard nookWidgetPlacements.contains(where: { $0.kind == .mirror }) else {
            linkLog.notice("Ignored a link: the Mirror widget is not on this display's page")
            return false
        }
        guard showPage(.nook) else { return false }
        nook.isMirrorOn = true
        return true
    }
}
