import SwiftUI
import OpenIslandCore

// The preview stage: a small "top of the screen" that draws one setup at one
// moment, and the sheet around it that picks moments and plays them in order
// ("See it in action"). Everything is drawn from a `PersonalizationSetup`,
// which lets the same stage show the setup being edited or a template that
// is not applied. Rules live in `PreviewScene`; this file only draws.

// MARK: - Sizes

@MainActor
enum PreviewStageMetrics {
    /// The scene is laid out at the island's real size and drawn smaller.
    static let scale: CGFloat = 0.78
    /// The stage's width inside the sheet, and the scene's width before scaling.
    static let stageWidth: CGFloat = 560
    static let naturalWidth: CGFloat = stageWidth / scale
    static let menuBarHeight: CGFloat = 32
    static let physicalNotchWidth: CGFloat = 180
    static let bottomPadding: CGFloat = 16
    /// The stage never grows past this; a taller page scrolls inside it.
    static let maxAreaHeight: CGFloat = 460
    static let minAreaHeight: CGFloat = 220
    /// Sessions the stage lists. The settings preview shows five; three
    /// keep the agents page about as tall as a Nook page.
    static let agentsListLimit = 3
    /// Height of the agents page with those sessions: header, rows and foot.
    static let agentsListHeight: CGFloat = 330
    static let agentsSectionHeaderHeight: CGFloat = 28

    static func nookPanelHeight(
        setup: PersonalizationSetup,
        enabledWidgets: [NookWidgetKind]
    ) -> CGFloat {
        let page = NookPanelView.preferredHeight(
            for: setup.nook.placements(enabled: enabledWidgets),
            calendarStyle: setup.nook.calendarStyle,
            isEditing: false
        )
        let bar = setup.nook.showsAgentsBar ? NookAgentsBar.outerHeight : 0
        return PreviewNookPanel.headHeight + bar + page + PreviewNookPanel.footHeight
    }

    static func agentsPanelHeight(setup: PersonalizationSetup) -> CGFloat {
        // The sections the first sessions fall into.
        let sections: CGFloat = switch setup.appearance.sessionGroup {
        case .none: 0
        case .state, .agent: 3
        case .project: 2
        }
        let bar = setup.nook.showsCompactBar ? NookCompactBar.outerHeight : 0
        return agentsListHeight + sections * agentsSectionHeaderHeight + bar
    }

    /// One height for every moment of a setup, which keeps the sheet still
    /// while the storyboard plays.
    static func areaHeight(setup: PersonalizationSetup, enabledWidgets: [NookWidgetKind]) -> CGFloat {
        let tallest = max(
            nookPanelHeight(setup: setup, enabledWidgets: enabledWidgets),
            agentsPanelHeight(setup: setup)
        )
        return min(max(tallest * scale + bottomPadding, minAreaHeight), maxAreaHeight)
    }
}

/// Reports its child's natural size times `scale`. Paired with
/// `scaleEffect(scale, anchor: .topLeading)` on the child, the drawn size and
/// the layout size agree.
private struct PreviewScaledLayout: Layout {
    var scale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let natural = child.sizeThatFits(.unspecified)
        return CGSize(width: natural.width * scale, height: natural.height * scale)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        child.place(at: bounds.origin, anchor: .topLeading, proposal: .unspecified)
    }
}

// MARK: - Stage

/// One setup at one moment, drawn the way the top of the screen would look.
struct PreviewStageView: View {
    let scene: PreviewScene
    let setup: PersonalizationSetup
    let profile: IslandAppearanceDisplayProfile
    let enabledWidgets: [NookWidgetKind]
    let lang: LanguageManager
    /// False lays the scene out at its own height with no scroll area, for
    /// offscreen renders (`ImageRenderer` leaves a `ScrollView` blank).
    var isScrollable = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var layout: V6ClosedLayout { profile == .notch ? .macbook : .external }

    var body: some View {
        SettingsPreviewStage(contentTopPadding: 0, contentBottomPadding: 0) {
            if isScrollable {
                ScrollView(.vertical) { scaledScene }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: PreviewStageMetrics.areaHeight(setup: setup, enabledWidgets: enabledWidgets))
            } else {
                scaledScene
                    .frame(
                        height: PreviewStageMetrics.areaHeight(setup: setup, enabledWidgets: enabledWidgets),
                        alignment: .top
                    )
            }
        }
        .overlay(alignment: .bottomLeading) { sampleTag }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lang.t("settings.appearance.stage.sample"))
    }

    private var scaledScene: some View {
        PreviewScaledLayout(scale: PreviewStageMetrics.scale) {
            sceneContent
                .frame(width: PreviewStageMetrics.naturalWidth, alignment: .top)
                .scaleEffect(PreviewStageMetrics.scale, anchor: .topLeading)
        }
        .padding(.bottom, PreviewStageMetrics.bottomPadding)
        .frame(maxWidth: .infinity)
        // Samples take no clicks. The scroll area around them still scrolls.
        .allowsHitTesting(false)
    }

    private var sampleTag: some View {
        Text(lang.t("settings.appearance.stage.sampleTag").uppercased())
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1)
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.black.opacity(0.35)))
            .padding(10)
            .allowsHitTesting(false)
    }

    // MARK: Scene

    private var sceneContent: some View {
        let openTransition = Motion.transition(
            .opacity.combined(with: .scale(scale: 0.92, anchor: .top)),
            reduceMotion: reduceMotion
        )
        return ZStack(alignment: .top) {
            desktopWindow
            menuBar
            switch scene.page {
            case nil:
                closedIsland
                    .transition(openTransition)
            case .agents:
                agentsPage
                    .transition(openTransition)
            case .nook:
                nookPage
                    .transition(openTransition)
            }
        }
    }

    /// A hint of the menu bar, which places the island at the top of a screen.
    private var menuBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "apple.logo")
                .font(.system(size: 13, weight: .semibold))
            ForEach([34, 26, 30, 38], id: \.self) { width in
                Capsule().frame(width: CGFloat(width), height: 5)
            }
            Spacer(minLength: 0)
            ForEach(["wifi", "battery.75percent", "magnifyingglass"], id: \.self) { symbol in
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
            }
            Text("9:41")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.5))
        .padding(.horizontal, 18)
        .frame(height: PreviewStageMetrics.menuBarHeight)
        .background(Color.black.opacity(0.22))
    }

    /// A faint app window under the island. It gives the empty screen some
    /// scale while the island is closed, and the opened island covers it the
    /// way it covers real windows.
    private var desktopWindow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().frame(width: 9, height: 9)
                }
            }
            ForEach([220, 300, 180, 260, 140], id: \.self) { width in
                Capsule().frame(width: CGFloat(width), height: 6)
            }
        }
        .foregroundStyle(.white.opacity(0.07))
        .padding(16)
        .frame(width: 440, height: 250, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .padding(.top, PreviewStageMetrics.menuBarHeight + 46)
    }

    // MARK: Closed island

    private var closedIsland: some View {
        let activity = closedActivity
        return ZStack(alignment: .top) {
            if layout == .macbook {
                // The hardware notch the island grows out of.
                V6ClosedPillShape()
                    .fill(Color.black)
                    .frame(width: PreviewStageMetrics.physicalNotchWidth, height: PreviewStageMetrics.menuBarHeight)
            }
            IslandPreviewPill(
                mode: scene.mode,
                label: labelText,
                rightSlot: rightSlot,
                layout: layout,
                physicalNotchWidth: PreviewStageMetrics.physicalNotchWidth,
                activity: activity,
                agentsNeedAttention: scene.mode == .waiting,
                agentStatusTint: agentStatusTint,
                leftSlot: leftSlot,
                rightExtra: setup.nook.rightSlot.flatMap {
                    AppearanceSettingsPane.sampleSideSlot($0, mode: scene.mode)
                }
            )
            .equatable()
            .fixedSize(horizontal: true, vertical: false)
            .islandHaloPreview(IslandHaloState.resolve(scene.halo), cornerRadius: PreviewStageMetrics.menuBarHeight / 2)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: PreviewStageMetrics.menuBarHeight)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// The live island's own rule, fed with the sample track or notice.
    private var closedActivity: NookClosedActivity? {
        switch scene.activity {
        case .music:
            let media = NookClosedMediaActivity(
                artwork: PreviewSampleArt.image,
                gifURL: nil,
                gifScale: 1,
                gifOffset: .zero,
                isPlaying: true
            )
            return .resolve(transient: nil, timerText: nil, media: media, preferences: setup.nook)
        case .notice:
            let notice = NookTransientActivity(
                symbol: PreviewSamples.noticeSymbol,
                text: PreviewSamples.noticeText,
                tint: PreviewSamples.noticeTint.color
            )
            return .resolve(transient: notice, timerText: nil, media: nil, preferences: setup.nook)
        case nil:
            return nil
        }
    }

    private var labelText: String? {
        switch scene.label {
        case .permissionNeeded: lang.t("settings.appearance.preview.permissionNeeded")
        case .agentAction: lang.t("settings.appearance.preview.agentEditing")
        case .sessionName: "open-island"
        case .track: lang.t("settings.appearance.nook.preview.track")
        case .nextEvent: lang.t("settings.appearance.nook.preview.event")
        case nil: nil
        }
    }

    private var rightSlot: IslandRightSlotContent? {
        switch setup.appearance.rightSlot {
        case .none:
            return nil
        case .count:
            return .count(PreviewSamples.agentCount)
        case .agents:
            let claude = Color(hex: AgentTool.claudeCode.brandColorHex) ?? .white
            return .agents((0..<PreviewSamples.agentCount).map { index in
                .session(color: claude, state: scene.mode == .waiting && index == 1 ? .waiting : .running)
            })
        }
    }

    private var leftSlot: NookSideSlotContent? {
        let slot = setup.nook.leftSlot
        return slot == .agents ? nil : AppearanceSettingsPane.sampleSideSlot(slot, mode: scene.mode)
    }

    private var agentStatusTint: Color? {
        guard setup.nook.showsAgentDotOnArt else { return nil }
        switch scene.mode {
        case .waiting: return IslandDesignPalette.Status.waitingAggregate
        case .running: return IslandDesignPalette.Status.running
        case .idle: return nil
        }
    }

    // MARK: Opened island

    private var agentsPage: some View {
        let appearance = setup.appearance
        return SessionListPanelPreview(
            sections: SessionListPreviewSamples.sections(
                lang: lang,
                group: appearance.sessionGroup,
                sort: appearance.sessionSort,
                staleThreshold: appearance.completedStaleThreshold,
                limit: PreviewStageMetrics.agentsListLimit
            ),
            showsSections: appearance.sessionGroup != .none,
            indicator: appearance.sessionStateIndicator,
            profile: profile,
            look: setup.nook.openedLook,
            lang: lang,
            showsNowPlayingRow: scene.showsCompactBar
        )
        .equatable()
    }

    private var nookPage: some View {
        PreviewNookPanel(
            placements: setup.nook.placements(enabled: enabledWidgets),
            calendarStyle: setup.nook.calendarStyle,
            profile: profile,
            look: setup.nook.openedLook,
            showsAgentsBar: scene.showsAgentsBar,
            emptyTitle: lang.t("settings.appearance.stage.emptyNook")
        )
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Sheet

/// The stage with its controls: a caption for the moment on screen, the
/// storyboard player, a chip per moment, and the buttons that leave.
struct PreviewStageSheet: View {
    let title: String
    let setup: PersonalizationSetup
    let profile: IslandAppearanceDisplayProfile
    let enabledWidgets: [NookWidgetKind]
    let lang: LanguageManager
    /// Nil hides the primary button.
    let primaryTitle: String?
    let onPrimary: () -> Void
    let onClose: () -> Void
    private let isScrollable: Bool

    @State private var moment: PreviewMoment
    @State private var isPlaying: Bool
    /// The storyboard step on screen, or `steps.count` once it has played out.
    @State private var stepIndex: Int
    /// Bumped whenever the player starts a step, which restarts its bar.
    @State private var stepRun = 0
    /// Set while the done flash is live; cleared after `Motion.Halo.flashHold`.
    @State private var flashToken: UInt64?
    @State private var flashCount: UInt64 = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let width: CGFloat = PreviewStageMetrics.stageWidth + 40
    private static let captionHeight: CGFloat = 48

    init(
        title: String,
        setup: PersonalizationSetup,
        profile: IslandAppearanceDisplayProfile,
        enabledWidgets: [NookWidgetKind],
        lang: LanguageManager,
        primaryTitle: String? = nil,
        onPrimary: @escaping () -> Void = {},
        onClose: @escaping () -> Void,
        startsPlaying: Bool = true,
        initialMoment: PreviewMoment = .idle,
        isScrollable: Bool = true
    ) {
        self.title = title
        self.setup = setup
        self.profile = profile
        self.enabledWidgets = enabledWidgets
        self.lang = lang
        self.primaryTitle = primaryTitle
        self.onPrimary = onPrimary
        self.onClose = onClose
        self.isScrollable = isScrollable
        _moment = State(initialValue: initialMoment)
        _isPlaying = State(initialValue: startsPlaying)
        _stepIndex = State(initialValue: PreviewStoryboard.index(of: initialMoment))
    }

    private var scene: PreviewScene {
        PreviewScene.resolve(
            moment,
            setup: setup,
            profile: profile,
            policy: SystemMotionMonitor.shared.policy,
            flashToken: flashToken
        )
    }

    var body: some View {
        let scene = scene
        VStack(alignment: .leading, spacing: 14) {
            header
            PreviewStageView(
                scene: scene,
                setup: setup,
                profile: profile,
                enabledWidgets: enabledWidgets,
                lang: lang,
                isScrollable: isScrollable
            )
            caption(scene)
            player
            chips
            footer
        }
        .padding(20)
        .frame(width: Self.width)
        .background(Color(red: 0.055, green: 0.055, blue: 0.06))
        .environment(\.colorScheme, .dark)
        // Restarts when playing starts or stops, not on every step.
        .task(id: isPlaying) {
            await play()
        }
        .task(id: flashToken) {
            await clearFlashWhenDone()
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
            Text(lang.t(profile == .notch
                ? "settings.appearance.profile.macbook.title"
                : "settings.appearance.profile.external.title"))
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func caption(_ scene: PreviewScene) -> some View {
        Text(captionText(scene))
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(V6Palette.paper.opacity(0.82))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: Self.captionHeight, alignment: .topLeading)
            .id(scene.moment)
            .transition(.opacity)
    }

    /// Sentences run together with a space, except in Chinese.
    private func captionText(_ scene: PreviewScene) -> String {
        let separator = lang.language.resolvedCode.hasPrefix("zh") ? "" : " "
        return scene.captionKeys.map { lang.t($0) }.joined(separator: separator)
    }

    private var player: some View {
        let control = PreviewStoryboard.control(isPlaying: isPlaying, stepIndex: stepIndex)
        return HStack(spacing: 12) {
            Button(action: togglePlay) {
                Label(lang.t(Self.titleKey(for: control)), systemImage: Self.symbol(for: control))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(V6Palette.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(Capsule().fill(V6Palette.paper))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle())

            HStack(spacing: 4) {
                ForEach(Array(PreviewStoryboard.steps.enumerated()), id: \.offset) { index, step in
                    PreviewStepBar(
                        phase: barPhase(index),
                        seconds: step.seconds,
                        run: stepRun
                    )
                }
            }
        }
    }

    private func barPhase(_ index: Int) -> PreviewStepBar.Phase {
        if index < stepIndex { return .done }
        if index > stepIndex { return .upcoming }
        return isPlaying ? .playing : .held
    }

    private static func titleKey(for control: PreviewStoryboard.Control) -> String {
        switch control {
        case .play: "settings.appearance.stage.play"
        case .pause: "settings.appearance.stage.pause"
        case .replay: "settings.appearance.stage.replay"
        }
    }

    private static func symbol(for control: PreviewStoryboard.Control) -> String {
        switch control {
        case .play: "play.fill"
        case .pause: "pause.fill"
        case .replay: "arrow.counterclockwise"
        }
    }

    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(PreviewMoment.allCases) { candidate in
                MonoChip(title: lang.t(candidate.titleKey), selected: moment == candidate) {
                    pick(candidate)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(lang.t("settings.appearance.stage.sample"))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.38))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Button(action: onClose) {
                Text(lang.t("settings.appearance.stage.close"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .keyboardShortcut(.cancelAction)

            if let primaryTitle {
                Button(action: onPrimary) {
                    Text(primaryTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(V6Palette.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(Capsule().fill(V6Palette.paper))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Player

    /// A chip shows one moment and stops the storyboard there.
    private func pick(_ picked: PreviewMoment) {
        isPlaying = false
        stepIndex = PreviewStoryboard.index(of: picked)
        show(picked)
    }

    private func togglePlay() {
        switch PreviewStoryboard.control(isPlaying: isPlaying, stepIndex: stepIndex) {
        case .pause:
            isPlaying = false
        case .play:
            isPlaying = true
        case .replay:
            stepIndex = 0
            isPlaying = true
        }
    }

    private func show(_ next: PreviewMoment) {
        // The island opening and closing uses its own spring; everything
        // else morphs the way the closed pill does.
        let opens = PreviewScene.page(for: next) != nil || PreviewScene.page(for: moment) != nil
        withMotion(opens ? Motion.islandOpen : Motion.morph) {
            moment = next
            if next == .finished {
                flashCount &+= 1
                flashToken = flashCount
            }
        }
    }

    /// Walks the storyboard from the step on screen. Stops when the view
    /// goes away or playing is switched off, because the task is cancelled.
    private func play() async {
        guard isPlaying else { return }
        let steps = PreviewStoryboard.steps
        while stepIndex < steps.count {
            let step = steps[stepIndex]
            stepRun += 1
            show(step.moment)
            try? await Task.sleep(for: .seconds(step.seconds))
            guard !Task.isCancelled else { return }
            stepIndex += 1
        }
        isPlaying = false
    }

    /// Mirrors `IslandHaloController`: a flash token stays live for
    /// `Motion.Halo.flashHold`, then the glow falls back to what is under it.
    private func clearFlashWhenDone() async {
        guard flashToken != nil else { return }
        try? await Task.sleep(for: .seconds(Motion.Halo.flashHold))
        guard !Task.isCancelled else { return }
        flashToken = nil
    }
}

/// The small capsule that opens the stage: on a template card ("Preview")
/// and beside the closed preview ("See it in action").
struct PreviewPlayLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "play.fill")
                .font(.system(size: 7.5, weight: .bold))
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(V6Palette.paper.opacity(0.9))
        .padding(.horizontal, 9)
        .frame(height: 20)
        .background(Capsule().fill(Color.white.opacity(0.12)))
        .fixedSize()
    }
}

/// One step of the storyboard in the progress row. The step on screen fills
/// over its own time while the storyboard plays.
private struct PreviewStepBar: View {
    enum Phase: Equatable {
        case done
        case playing
        case held
        case upcoming
    }

    let phase: Phase
    let seconds: TimeInterval
    /// Changes each time the player starts a step.
    let run: Int

    @State private var isFilling = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Trigger: Equatable {
        let phase: Phase
        let run: Int
    }

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.14))
            .frame(height: 3)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Capsule()
                        .fill(V6Palette.paper.opacity(phase == .held ? 0.45 : 0.85))
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .task(id: Trigger(phase: phase, run: run)) {
                isFilling = false
                guard phase == .playing else { return }
                // One frame at empty first, or the fill has nothing to start from.
                try? await Task.sleep(for: .milliseconds(30))
                guard !Task.isCancelled else { return }
                withAnimation(Motion.resolved(Motion.stepProgress(seconds: seconds), reduceMotion: reduceMotion)) {
                    isFilling = true
                }
            }
    }

    private var fraction: CGFloat {
        switch phase {
        case .done, .held: 1
        case .playing: isFilling ? 1 : 0
        case .upcoming: 0
        }
    }
}
