import Foundation

/// One moment of island life the preview stage can show.
enum PreviewMoment: String, CaseIterable, Identifiable, Sendable {
    case idle
    case working
    case approval
    case finished
    case music
    case notice
    case openAgents
    case openNook

    var id: String { rawValue }

    /// The key of the chip title.
    var titleKey: String { "settings.appearance.stage.moment.\(rawValue)" }
}

/// Fixed sample values the stage shows in place of live data.
enum PreviewSamples {
    /// The album color of the sample track.
    static let musicTint = IslandHaloRGB.rgb255(255, 55, 95)
    /// The color of the sample notice, a timer that just ended.
    static let noticeTint = IslandHaloRGB.rgb255(255, 159, 10)
    static let noticeSymbol = "timer"
    static let noticeText = "Timer done"
    /// Agents in the samples: the count badge, the grid and the agents bar.
    static let agentCount = 3
}

/// What the stage draws for one moment of one setup. Plain values worked out
/// from the setup alone, never from the live island, which lets the same
/// stage show a template that is not applied.
struct PreviewScene: Equatable {
    enum Page: Equatable, Sendable {
        case agents
        case nook
    }

    /// What takes the closed island besides the agents.
    enum Activity: Equatable, Sendable {
        case music
        case notice
    }

    /// The center label on an external display.
    enum Label: Equatable, Sendable {
        case permissionNeeded
        case agentAction
        case sessionName
        case track
        case nextEvent
    }

    var moment: PreviewMoment
    var mode: UnifiedBars.Mode
    /// Nil when the moment has none or the setup keeps it out of the island.
    var activity: Activity?
    var label: Label?
    /// What the real halo resolver is fed.
    var halo: IslandHaloInputs
    /// The page of the opened island. Nil while the island is closed.
    var page: Page?
    /// The agent summary row above the Nook widgets.
    var showsAgentsBar: Bool
    /// The now-playing row under the agent list.
    var showsCompactBar: Bool
    /// Sentence keys under `settings.appearance.stage.caption.`, in order:
    /// what just happened, then what this setup does about it.
    var captionKeys: [String]
}

extension PreviewScene {
    static let captionPrefix = "settings.appearance.stage.caption."

    static func resolve(
        _ moment: PreviewMoment,
        setup: PersonalizationSetup,
        profile: IslandAppearanceDisplayProfile,
        policy: IslandMotionPolicy,
        flashToken: UInt64? = nil
    ) -> PreviewScene {
        let nook = setup.nook
        let mode = mode(for: moment)
        let activity = activity(for: moment, nook: nook)
        let page = page(for: moment)
        let halo = IslandHaloInputs(
            style: nook.haloStyle,
            policy: policy,
            isOpened: page != nil,
            waiting: mode == .waiting ? .approval : nil,
            flashToken: moment == .finished ? flashToken : nil,
            noticeTint: activity == .notice ? PreviewSamples.noticeTint : nil,
            // Like the live island, the glow follows music only while the art shows.
            musicTint: activity == .music && nook.haloFollowsMusic ? PreviewSamples.musicTint : nil,
            isRunning: mode == .running,
            palette: nook.haloColors.effectivePalette,
            isMusicPlaying: activity == .music && nook.haloFollowsMusic
        )
        return PreviewScene(
            moment: moment,
            mode: mode,
            activity: activity,
            label: page == nil ? label(mode: mode, activity: activity, setup: setup, profile: profile) : nil,
            halo: halo,
            page: page,
            showsAgentsBar: page == .nook && nook.showsAgentsBar,
            showsCompactBar: page == .agents && nook.showsCompactBar,
            captionKeys: captionKeys(for: moment, nook: nook).map { captionPrefix + $0 }
        )
    }

    /// What the agents are doing in each moment. Music plays over working
    /// agents, which shows how a setup shares the island between the two.
    static func mode(for moment: PreviewMoment) -> UnifiedBars.Mode {
        switch moment {
        case .idle, .finished, .notice, .openNook: .idle
        case .working, .music: .running
        case .approval, .openAgents: .waiting
        }
    }

    static func page(for moment: PreviewMoment) -> Page? {
        switch moment {
        case .openAgents: .agents
        case .openNook: .nook
        case .idle, .working, .approval, .finished, .music, .notice: nil
        }
    }

    private static func activity(for moment: PreviewMoment, nook: NookDisplayPreferences) -> Activity? {
        switch moment {
        case .music: nook.mediaStyle == .off ? nil : .music
        case .notice: nook.showsNotices ? .notice : nil
        case .idle, .working, .approval, .finished, .openAgents, .openNook: nil
        }
    }

    /// The same order the live island uses: the track while music shows and
    /// no agent waits, then the agent label, then the next event while the
    /// agents are quiet. The MacBook notch covers the label's place.
    private static func label(
        mode: UnifiedBars.Mode,
        activity: Activity?,
        setup: PersonalizationSetup,
        profile: IslandAppearanceDisplayProfile
    ) -> Label? {
        guard profile == .topBar else { return nil }
        let nook = setup.nook
        if nook.centerLabelShowsTrack, mode != .waiting, activity == .music { return .track }
        switch (mode, setup.appearance.centerLabel) {
        case (.waiting, .agentAction), (.waiting, .sessionName): return .permissionNeeded
        case (.running, .agentAction): return .agentAction
        case (.running, .sessionName): return .sessionName
        case (.idle, _), (_, .off): break
        }
        if nook.centerLabelShowsNextEvent, mode == .idle { return .nextEvent }
        return nil
    }

    private static func captionKeys(for moment: PreviewMoment, nook: NookDisplayPreferences) -> [String] {
        let glows = nook.haloStyle != .off
        switch moment {
        case .idle:
            return ["idle"]
        case .working:
            return ["working", glows ? "working.glow" : "working.noGlow"]
        case .approval:
            switch nook.haloStyle {
            case .off: return ["approval", "approval.noGlow"]
            case .subtle: return ["approval", "approval.subtle"]
            case .vivid: return ["approval", "approval.vivid"]
            }
        case .finished:
            return ["finished", glows ? "finished.flash" : "finished.noFlash"]
        case .music:
            switch nook.mediaStyle {
            case .off:
                return ["music", "music.off"]
            case .artOnly:
                return ["music", "music.artOnly"] + (glows && nook.haloFollowsMusic ? ["music.glow"] : [])
            case .artAndVisual:
                return ["music", "music.artAndVisual"] + (glows && nook.haloFollowsMusic ? ["music.glow"] : [])
            }
        case .notice:
            guard nook.showsNotices else { return ["notice", "notice.off"] }
            return ["notice", glows ? "notice.glow" : "notice.on"]
        case .openAgents:
            return ["openAgents", nook.openedPage == .nook ? "openAgents.opensOnNook" : "openAgents.opensHere"]
                + (nook.showsCompactBar ? ["openAgents.compactBar"] : [])
        case .openNook:
            switch nook.openedPage {
            case .agents: return ["openNook", "openNook.opensOnAgents"]
            case .auto: return ["openNook", "openNook.auto"]
            case .nook: return ["openNook", "openNook.always"]
            }
        }
    }

    /// Every caption sentence a setup can produce, for the string tables.
    static let allCaptionKeys: [String] = [
        "idle",
        "working", "working.glow", "working.noGlow",
        "approval", "approval.noGlow", "approval.subtle", "approval.vivid",
        "finished", "finished.flash", "finished.noFlash",
        "music", "music.off", "music.artOnly", "music.artAndVisual", "music.glow",
        "notice", "notice.off", "notice.on", "notice.glow",
        "openAgents", "openAgents.opensOnNook", "openAgents.opensHere", "openAgents.compactBar",
        "openNook", "openNook.opensOnAgents", "openNook.auto", "openNook.always",
    ].map { captionPrefix + $0 }
}

/// "See it in action": the moments in the order a working day brings them,
/// each held long enough to read its caption.
enum PreviewStoryboard {
    struct Step: Equatable, Sendable {
        let moment: PreviewMoment
        /// How long the step stays on screen.
        let seconds: TimeInterval
    }

    static let steps: [Step] = [
        Step(moment: .idle, seconds: 2.4),
        Step(moment: .working, seconds: 3.2),
        Step(moment: .approval, seconds: 4.0),
        Step(moment: .openAgents, seconds: 4.4),
        Step(moment: .finished, seconds: 3.2),
        Step(moment: .music, seconds: 4.0),
        Step(moment: .notice, seconds: 3.6),
        Step(moment: .openNook, seconds: 5.0),
    ]

    /// Where a moment sits in the storyboard, for resuming after a chip pick.
    static func index(of moment: PreviewMoment) -> Int {
        steps.firstIndex { $0.moment == moment } ?? 0
    }

    /// What the play button does next.
    enum Control: Equatable, Sendable {
        case play
        case pause
        case replay
    }

    static func control(isPlaying: Bool, stepIndex: Int) -> Control {
        if isPlaying { return .pause }
        return stepIndex >= steps.count ? .replay : .play
    }
}
