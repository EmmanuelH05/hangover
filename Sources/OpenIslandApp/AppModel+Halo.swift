import Foundation
import OpenIslandCore

/// Harness override, read once: `OPEN_ISLAND_HALO=...` (see
/// `IslandHaloState.forced(from:)`).
private let forcedIslandHaloState: IslandHaloState? = IslandHaloState.forced(from: ProcessInfo.processInfo.environment)

extension AppModel {
    /// The halo for the display the island is on right now (D16).
    var islandHaloState: IslandHaloState {
        if let forcedIslandHaloState { return forcedIslandHaloState }
        return .resolve(islandHaloInputs)
    }

    var islandHaloInputs: IslandHaloInputs {
        let display = nookDisplay
        let sessions = surfacedSessions
        let waiting: IslandWaitingKind? = if sessions.contains(where: { $0.phase == .waitingForApproval }) {
            .approval
        } else if sessions.contains(where: { $0.phase == .waitingForAnswer }) {
            .question
        } else {
            nil
        }
        let noticeTint = display.showsNotices ? nook.transient.flatMap { IslandHaloRGB($0.tint) } : nil
        let showsArtwork = nookClosedActivity?.showsArtwork == true
        let glowsWithMusic = display.haloFollowsMusic && showsArtwork
        let musicTint = glowsWithMusic ? nook.artworkTint.tint : nil
        return IslandHaloInputs(
            style: display.haloStyle,
            policy: SystemMotionMonitor.shared.policy,
            isOpened: notchStatus == .opened,
            waiting: waiting,
            // A flash is an agent finishing.
            flashToken: agentsEnabled ? halo.flashToken : nil,
            noticeTint: noticeTint,
            musicTint: musicTint,
            isRunning: !closedContentIsHidden && sessions.contains { $0.phase == .running },
            palette: display.haloColors.effectivePalette,
            isMusicPlaying: glowsWithMusic
        )
    }
}
