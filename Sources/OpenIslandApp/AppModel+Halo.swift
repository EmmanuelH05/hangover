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

    /// The glow's style, or off while the design kit's eyedropper is up. The
    /// glow and the lasers are drawn over the screen, and the loupe reads
    /// the screen as it is drawn: a beam over the pixel under the loupe
    /// would be picked along with it. The island gets out of the way for
    /// the same reason.
    func glowStyleNow(_ display: NookDisplayPreferences) -> IslandHaloStyle {
        nook.design.isSampling ? .off : display.haloStyle
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
        // The track is read only while a show runs on it: nothing else
        // here is to change when the song does.
        let runsShow = beat.isPulsing && display.haloBeatLook == .lasers && display.haloLaserMode == .show
        let track = runsShow ? nook.media.state : nil
        return IslandHaloInputs(
            style: glowStyleNow(display),
            policy: SystemMotionMonitor.shared.policy,
            isOpened: notchStatus == .opened,
            waiting: waiting,
            // A flash is an agent finishing.
            flashToken: agentsEnabled ? halo.flashToken : nil,
            noticeTint: noticeTint,
            musicTint: musicTint,
            isRunning: !closedContentIsHidden && sessions.contains { $0.phase == .running },
            palette: display.haloColors.effectivePalette,
            isMusicPlaying: glowsWithMusic,
            pulsesWithBeat: beat.isPulsing,
            pulseReach: display.haloPulseReach,
            pulseLook: display.haloBeatLook,
            pulseLaserReach: display.haloLaserReach,
            pulseLaserCount: display.haloLaserCount,
            pulseLaserMode: display.haloLaserMode,
            pulseLaserSeed: runsShow
                ? IslandLaserSeed.seed(title: track?.title, artist: track?.artist, tint: musicTint) : 0
        )
    }
}

// MARK: - The beat (D56)

extension AppModel {
    /// What decides whether Hangover listens to the Mac's sound. With the
    /// switch off this reads the display's choices and nothing else, which
    /// means nothing else can wake it.
    var beatListeningInputs: IslandBeatListeningInputs {
        let display = nookDisplay
        guard display.haloPulsesWithBeat else { return .off }
        // Music is what the closed island shows, a short notice aside: a
        // notice is gone in seconds and is no reason to tear the tap down.
        let showsMusic = NookClosedActivity.resolve(
            transient: nil,
            timerText: nook.timer.closedText,
            media: nook.closedMediaActivity,
            preferences: display,
            isHidden: closedContentIsHidden
        )?.showsArtwork == true
        return IslandBeatListeningInputs(
            isSwitchOn: true,
            style: glowStyleNow(display),
            followsMusic: display.haloFollowsMusic,
            isMusicPlaying: nook.media.state?.isPlaying == true,
            policy: SystemMotionMonitor.shared.policy,
            islandShowsMusic: showsMusic,
            isIslandClosed: notchStatus != .opened,
            isScreenOn: IslandScreenPresence.shared.isOn
        )
    }

    /// Hands the listening rule its inputs now and again whenever one of
    /// them changes. `withObservationTracking` fires once for each
    /// registration, which is why this registers itself again.
    func followBeatInputs() {
        let inputs = withObservationTracking {
            beatListeningInputs
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.followBeatInputs() }
        }
        beat.update(inputs)
    }
}
