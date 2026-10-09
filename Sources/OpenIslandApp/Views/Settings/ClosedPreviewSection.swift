import SwiftUI
import OpenIslandCore

/// The closed-island preview at the top of the Personalization tab: the pill
/// (with the status halo behind it), the MacBook notch mock, and the chips that
/// pick what the pill shows.
///
/// It owns the preview's own state (mode, auto-cycle, music, the done flash),
/// so the two-second auto-cycle re-renders only this view and not the whole
/// pane. Everything it shows comes from the profile being edited: the pane
/// hands over the two island choices it needs (so other clicks leave this view
/// alone) and the Nook preferences are read from the model here.
struct ClosedPreviewSection: View {
    let model: AppModel
    let profile: IslandAppearanceDisplayProfile
    let rightSlot: IslandRightSlot
    let centerLabel: IslandCenterLabel

    @State private var previewMode: UnifiedBars.Mode = .idle
    @State private var previewAutoCycle = true
    /// Draws the preview as it looks while music plays.
    @State private var previewMusic = false
    /// Set while the done flash is live; cleared after `Motion.Halo.flashHold`.
    @State private var flashToken: UInt64?
    /// Every flash gets a new token, so repeating Done replays the flash.
    @State private var flashCount: UInt64 = 0
    /// The preview stage, playing the setup being edited.
    @State private var isShowingStage = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let autoCycleOrder: [UnifiedBars.Mode] = [.idle, .running, .waiting]
    private static let autoCycleInterval: Duration = .seconds(2)
    private static let physicalNotchWidth: CGFloat = 180
    private static let pillHeight: CGFloat = 32
    /// Glow color for the music chip when the track has no usable art color.
    private static let fallbackMusicHex = "FF2D55"

    private var lang: LanguageManager { model.lang }
    private var nookPreferences: NookDisplayPreferences { model.nook.displayPreferences(for: profile) }
    private var layout: V6ClosedLayout { profile == .notch ? .macbook : .external }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 8) {
                PersonalizationSectionHeader(title: lang.t("settings.appearance.preview"), note: nil)
                Spacer(minLength: 8)
                Button {
                    isShowingStage = true
                } label: {
                    PreviewPlayLabel(title: lang.t("settings.appearance.stage.seeInAction"))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
            }

            SettingsPreviewStage(contentTopPadding: 16, contentBottomPadding: 18) {
                VStack(spacing: 14) {
                    stage
                    controls
                }
                .padding(.horizontal, 18)
            }
        }
        .sheet(isPresented: $isShowingStage) {
            PreviewStageSheet(
                title: lang.t("settings.appearance.stage.yourSetup"),
                setup: model.personalizationSetup(for: profile),
                profile: profile,
                enabledWidgets: model.nook.enabledWidgets,
                lang: lang,
                onClose: { isShowingStage = false }
            )
        }
        .task(id: previewAutoCycle) {
            await runAutoCycle()
        }
        .task(id: flashToken) {
            await clearFlashWhenDone()
        }
    }

    // MARK: - Stage

    private var stage: some View {
        let activity = previewNookActivity
        return ZStack(alignment: .top) {
            if layout == .macbook {
                // Physical hardware notch mock, pinned to the top of the frame
                // the way the real cutout sits at the top of the display. It
                // fades and scales in and out when the layout switches.
                V6ClosedPillShape()
                    .fill(Color.black)
                    .frame(width: Self.physicalNotchWidth, height: Self.pillHeight)
                    .transition(notchTransition)
            }

            IslandPreviewPill(
                mode: previewMode,
                label: previewNookLabel(activity: activity) ?? previewLabel,
                rightSlot: previewRightContent,
                layout: layout,
                physicalNotchWidth: Self.physicalNotchWidth,
                activity: activity,
                agentsNeedAttention: previewMode == .waiting,
                agentStatusTint: previewNookStatusTint,
                leftSlot: previewNookSideSlot,
                rightExtra: nookPreferences.rightSlot.flatMap {
                    AppearanceSettingsPane.sampleSideSlot($0, mode: previewMode)
                }
            )
            .equatable()
            // `IslandPreviewPill` fills the width, so size it to the pill
            // first. The halo then hugs the pill and follows its morphs.
            .fixedSize(horizontal: true, vertical: false)
            .islandHaloPreview(haloState(activity: activity), cornerRadius: Self.pillHeight / 2)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: Self.pillHeight)
        .frame(maxWidth: .infinity, alignment: .center)
        .motionAnimation(Motion.morph, value: layout)
    }

    private var notchTransition: AnyTransition {
        Motion.transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)), reduceMotion: reduceMotion)
    }

    // MARK: - Halo

    /// The same resolver the live island uses, fed with the profile being
    /// edited and the state the chips picked.
    private func haloState(activity: NookClosedActivity?) -> IslandHaloState {
        let preferences = nookPreferences
        // Like the live island, the glow only follows music while the art shows.
        let followsMusic = previewMusic && preferences.haloFollowsMusic && activity?.showsArtwork == true
        let musicTint = followsMusic
            ? (model.nook.artworkTint.tint ?? IslandHaloRGB(hex: Self.fallbackMusicHex))
            : nil
        return IslandHaloState.resolve(IslandHaloInputs(
            style: preferences.haloStyle,
            policy: SystemMotionMonitor.shared.policy,
            isOpened: false,
            waiting: previewMode == .waiting ? .approval : nil,
            flashToken: flashToken,
            noticeTint: nil,
            musicTint: musicTint,
            isRunning: previewMode == .running,
            palette: preferences.haloColors.effectivePalette,
            isMusicPlaying: followsMusic
        ))
    }

    // MARK: - Chips

    private var controls: some View {
        HStack(spacing: 10) {
            // Auto-cycle toggle (default on, drives the state chips).
            MonoChip(
                title: previewAutoCycle
                    ? lang.t("settings.appearance.state.auto.on")
                    : lang.t("settings.appearance.state.auto.off"),
                selected: previewAutoCycle
            ) {
                withMotion(Motion.contentSwap) { previewAutoCycle.toggle() }
            }

            // Manual state chips; selecting one turns off auto-cycle.
            ForEach(Self.autoCycleOrder, id: \.self) { mode in
                MonoChip(title: title(for: mode), selected: !previewAutoCycle && previewMode == mode) {
                    withMotion(Motion.contentSwap) {
                        previewAutoCycle = false
                        previewMode = mode
                    }
                }
            }

            MonoChip(title: lang.t("settings.appearance.nook.preview.done"), selected: flashToken != nil) {
                playDoneFlash()
            }

            MonoChip(title: lang.t("settings.appearance.nook.preview.music"), selected: previewMusic) {
                withMotion(Motion.contentSwap) { previewMusic.toggle() }
            }

            Spacer(minLength: 0)
        }
    }

    /// An agent finishing: the green flash plays once. A waiting agent would
    /// hide it (waiting outranks the flash), so the preview moves to idle.
    private func playDoneFlash() {
        withMotion(Motion.contentSwap) {
            previewAutoCycle = false
            if previewMode == .waiting { previewMode = .idle }
            flashCount &+= 1
            flashToken = flashCount
        }
    }

    private func runAutoCycle() async {
        guard previewAutoCycle else { return }

        while !Task.isCancelled {
            try? await Task.sleep(for: Self.autoCycleInterval)
            guard !Task.isCancelled, previewAutoCycle else { return }

            let order = Self.autoCycleOrder
            let current = order.firstIndex(of: previewMode) ?? 0
            let next = order[(current + 1) % order.count]
            withMotion(Motion.morph) {
                previewMode = next
            }
        }
    }

    /// Mirrors `IslandHaloController`: a flash token stays live for
    /// `Motion.Halo.flashHold`, then lets the glow fall back to what is under it.
    private func clearFlashWhenDone() async {
        guard flashToken != nil else { return }
        try? await Task.sleep(for: .seconds(Motion.Halo.flashHold))
        guard !Task.isCancelled else { return }
        flashToken = nil
    }

    private func title(for mode: UnifiedBars.Mode) -> String {
        switch mode {
        case .idle:    lang.t("settings.appearance.state.idle")
        case .running: lang.t("settings.appearance.state.running")
        case .waiting: lang.t("settings.appearance.state.waiting")
        }
    }

    // MARK: - What the pill shows

    private var previewAgentCells: [AgentGridCell] {
        // Three Claude sessions, with one waiting when the preview mode is
        // `waiting` so the breathing tile is visible in the live preview.
        let claude = Color(hex: AgentTool.claudeCode.brandColorHex) ?? .white
        let waitingIdx = previewMode == .waiting ? 1 : -1
        return (0..<3).map { idx in
            if idx == waitingIdx {
                return .session(color: claude, state: .waiting)
            }
            return .session(color: claude, state: .running)
        }
    }

    private var previewLabel: String? {
        guard layout == .external, centerLabel != .off else { return nil }
        switch (previewMode, centerLabel) {
        case (.idle, _):               return nil
        case (.waiting, _):            return lang.t("settings.appearance.preview.permissionNeeded")
        case (.running, .agentAction): return lang.t("settings.appearance.preview.agentEditing")
        case (.running, .sessionName): return "open-island"
        case (.running, .off):         return nil
        }
    }

    // Nook preview: the same rules the live island applies, fed with the
    // preferences being edited instead of the active display's.

    private var previewNookActivity: NookClosedActivity? {
        previewMusic ? model.nook.previewClosedActivity(for: nookPreferences) : nil
    }

    private func previewNookLabel(activity: NookClosedActivity?) -> String? {
        guard layout == .external else { return nil }
        let preferences = nookPreferences
        if preferences.centerLabelShowsTrack,
           previewMode != .waiting,
           activity?.showsArtwork == true {
            let title = model.nook.nowPlaying?.title ?? lang.t("settings.appearance.nook.preview.track")
            return AppModel.truncatedLabel(title, limit: AppModel.nookTrackLabelLimit)
        }
        // The agents have nothing to say while idle; the next event may.
        if preferences.centerLabelShowsNextEvent, previewMode == .idle {
            return lang.t("settings.appearance.nook.preview.event")
        }
        return nil
    }

    private var previewNookSideSlot: NookSideSlotContent? {
        let slot = nookPreferences.leftSlot
        return slot == .agents ? nil : AppearanceSettingsPane.sampleSideSlot(slot, mode: previewMode)
    }

    private var previewNookStatusTint: Color? {
        guard nookPreferences.showsAgentDotOnArt else { return nil }
        switch previewMode {
        case .waiting: return IslandDesignPalette.Status.waitingAggregate
        case .running: return IslandDesignPalette.Status.running
        case .idle: return nil
        }
    }

    private var previewRightContent: IslandRightSlotContent? {
        switch rightSlot {
        case .none: return nil
        case .count: return .count(3)
        case .agents: return .agents(previewAgentCells)
        }
    }
}
