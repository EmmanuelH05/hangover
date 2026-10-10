import AppKit
import SwiftUI
import OpenIslandCore

/// Per-cell state for the closed-island agents grid. Drives tile rendering:
/// running = full color, idle = dim, waiting = opacity pulse.
enum AgentGridCellState: Equatable {
    case running
    case idle
    case waiting
}

/// One cell in the closed-island agents grid. `.session` carries the agent
/// tool's brand color and its current state. `.overflow` is a single trailing
/// cell shown when there are more sessions than the grid can display.
enum AgentGridCell: Equatable {
    case session(color: Color, state: AgentGridCellState)
    case overflow(Int)
}

/// Concrete payload for the closed island's right slot. The `AppModel`
/// computes one of these from live session state according to the user's
/// `islandRightSlot` preference; the view side is agnostic to which
/// setting produced it.
enum IslandRightSlotContent: Equatable {
    case count(Int)              // "×N" badge
    case agents([AgentGridCell]) // balanced grid, one tile per session
}

// MARK: - Right-slot renderers

struct V6RightSlotView: View {
    let content: IslandRightSlotContent
    /// False stops the waiting tile's pulse, for when the pill is hidden
    /// behind the opened island.
    var isLive: Bool = true

    var body: some View {
        switch content {
        case .count(let n):
            Text("×\(n)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(V6Palette.paper.opacity(0.72))
                .contentTransition(.numericText())
        case .agents(let cells):
            AgentsGridBody(cells: cells, isLive: isLive)
        }
    }

    /// Intrinsic width used by the fluid-layout math. Values are slightly
    /// padded beyond the raw text measurement so the pill always reserves
    /// enough room for the `.fixedSize()` content to render on one line,
    /// without HStack compression forcing a wrap.
    static func intrinsicWidth(of content: IslandRightSlotContent) -> CGFloat {
        switch content {
        case .count(let n):
            let digits = Double(max(1, String(n).count))
            // "×" + digits at 11pt mono ≈ 7.2pt/char.
            return CGFloat(14.4 + max(0.0, digits - 1.0) * 7.2)
        case .agents(let cells):
            let n = cells.count
            guard n > 0 else { return 0 }
            let rows = balancedRows(n)
            let maxRow = rows.max() ?? 0
            let geom = cellGeometry(rowCount: rows.count)
            return CGFloat(maxRow) * geom.cell + CGFloat(max(0, maxRow - 1)) * geom.gap
        }
    }

    // MARK: Balanced layout algorithm
    //
    // For each n from 1 to 9, we hand-tune the per-row cell counts so the
    // matrix reads as a deliberate shape instead of a wrap-at-4-columns grid.
    // For n >= 10 the AppModel caps the list at 7 sessions + 1 overflow cell,
    // which lays out as [4,4] — so balancedRows(8) is what actually renders
    // for all high-count cases in production.
    static func balancedRows(_ n: Int) -> [Int] {
        switch n {
        case ..<1: return []
        case 1: return [1]
        case 2: return [2]
        case 3: return [3]
        case 4: return [2, 2]
        case 5: return [3, 2]
        case 6: return [3, 3]
        case 7: return [4, 3]
        case 8: return [4, 4]
        case 9: return [3, 3, 3]
        default: return [4, 4]
        }
    }

    /// Cell size shrinks when the matrix has 3 rows so total height still
    /// fits inside the pill's internal vertical budget (~20pt).
    static func cellGeometry(rowCount: Int) -> (cell: CGFloat, gap: CGFloat, radius: CGFloat) {
        if rowCount >= 3 { return (cell: 6, gap: 1.5, radius: 1.0) }
        return (cell: 8, gap: 2, radius: 1.5)
    }

    static func splitIntoRows(_ cells: [AgentGridCell], rowSizes: [Int]) -> [[AgentGridCell]] {
        var out: [[AgentGridCell]] = []
        var idx = 0
        for size in rowSizes {
            let end = min(idx + size, cells.count)
            out.append(Array(cells[idx..<end]))
            idx = end
            if idx >= cells.count { break }
        }
        return out
    }
}

// MARK: - Agents grid body

/// V1a Dense Grid renderer. 2D matrix of 8×8 rounded squares (6×6 when 3 rows),
/// each row horizontally centered around the widest row. Running = full color,
/// idle = 22% alpha, waiting = opacity 0.35 ↔ 1 breathing pulse.
private struct AgentsGridBody: View {
    let cells: [AgentGridCell]
    var isLive: Bool = true

    var body: some View {
        let rowSizes = V6RightSlotView.balancedRows(cells.count)
        let geom = V6RightSlotView.cellGeometry(rowCount: rowSizes.count)
        let rows = V6RightSlotView.splitIntoRows(cells, rowSizes: rowSizes)

        VStack(spacing: geom.gap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: geom.gap) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        AgentsGridTileView(cell: cell, size: geom.cell, radius: geom.radius, isLive: isLive)
                    }
                }
            }
        }
        .fixedSize()
    }
}

private struct AgentsGridTileView: View {
    let cell: AgentGridCell
    let size: CGFloat
    let radius: CGFloat
    let isLive: Bool

    var body: some View {
        switch cell {
        case .session(let color, let state):
            switch state {
            case .running:
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(color)
                    .frame(width: size, height: size)
            case .idle:
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(color.opacity(0.22))
                    .frame(width: size, height: size)
            case .waiting:
                AgentsGridWaitingTile(color: color, size: size, radius: radius, isLive: isLive)
            }
        case .overflow(let n):
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(V6Palette.paper.opacity(0.14))
                Text("+\(n)")
                    .font(.system(size: max(5, size * 0.55), weight: .bold, design: .monospaced))
                    .foregroundStyle(V6Palette.paper)
            }
            .frame(width: size, height: size)
        }
    }
}

/// The waiting tile. While live it breathes between `WaitingTilePulse.lowOpacity`
/// and `highOpacity` on a Core Animation layer, so the pulse costs no
/// main-thread frames. When not live (the pill is hidden behind the opened
/// island) it draws one static opacity and nothing animates.
private struct AgentsGridWaitingTile: View {
    let color: Color
    let size: CGFloat
    let radius: CGFloat
    var isLive: Bool = true

    var body: some View {
        if isLive {
            WaitingTilePulseView(color: color, radius: radius)
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(color)
                .opacity(WaitingTilePulse.restOpacity)
                .frame(width: size, height: size)
        }
    }
}

/// The waiting tile's breathing pulse: an opacity loop on the shared cycle
/// grid, so every tile pulses in step and re-adding one never restarts it.
enum WaitingTilePulse {
    static let lowOpacity: CGFloat = 0.35
    static let highOpacity: CGFloat = 1.0
    /// One half of the breathing cycle. Motion.swift has no name for a
    /// continuous pulse, so the duration lives here.
    static let halfPeriod: CFTimeInterval = 0.7
    static let period: CFTimeInterval = halfPeriod * 2
    /// What the tile shows while it is not live.
    static let restOpacity: CGFloat = (lowOpacity + highOpacity) / 2
    static let animationKey = "waiting.pulse"

    /// The loop, starting on the cycle grid at or before `now` (in the
    /// layer's own time).
    static func animation(now: CFTimeInterval) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [lowOpacity, highOpacity, lowOpacity].map { Float($0) }
        animation.keyTimes = [0, 0.5, 1]
        animation.duration = period
        animation.beginTime = UnifiedBars.alignedBeginTime(now: now, period: period, delay: 0)
        animation.repeatCount = .infinity
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
        ]
        return animation
    }
}

private struct WaitingTilePulseView: NSViewRepresentable {
    let color: Color
    let radius: CGFloat

    func makeNSView(context: Context) -> WaitingTilePulseLayerView {
        let view = WaitingTilePulseLayerView()
        view.update(color: NSColor(color), radius: radius)
        return view
    }

    func updateNSView(_ nsView: WaitingTilePulseLayerView, context: Context) {
        nsView.update(color: NSColor(color), radius: radius)
    }
}

/// A rounded square whose opacity loops by Core Animation. `update` is
/// idempotent and never restarts a running loop.
final class WaitingTilePulseLayerView: NSView {
    private var appliedColor: CGColor?
    private var appliedRadius: CGFloat?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.cornerCurve = .continuous
        layer?.opacity = Float(WaitingTilePulse.highOpacity)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(color: NSColor, radius: CGFloat) {
        guard let layer else { return }
        let cgColor = color.cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if appliedColor != cgColor {
            appliedColor = cgColor
            layer.backgroundColor = cgColor
        }
        if appliedRadius != radius {
            appliedRadius = radius
            layer.cornerRadius = radius
        }
        startPulseIfNeeded()
        CATransaction.commit()
    }

    /// Core Animation can drop a layer's animations when its window goes away,
    /// so the loop is checked again whenever the view lands in one.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        startPulseIfNeeded()
    }

    private func startPulseIfNeeded() {
        guard let layer, layer.animation(forKey: WaitingTilePulse.animationKey) == nil else { return }
        let now = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.add(WaitingTilePulse.animation(now: now), forKey: WaitingTilePulse.animationKey)
    }
}

// MARK: - Center label renderer

struct V6CenterLabelView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(V6Palette.paper)
            .contentTransition(.interpolate)
    }

    static func intrinsicWidth(of text: String) -> CGFloat {
        CGFloat(Double(text.count) * 7.3 + 10)
    }
}

// MARK: - Closed-pill content identity

/// What kind of thing fills a slot, ignoring its values. It is the slot's view
/// identity: a different kind swaps (blur-replace), while the same kind with
/// new values stays in place so numbers and colors morph instead.
enum PillSlotIdentity: Hashable {
    case bars
    case artwork
    case symbol(String)
    case agentCount
    case agentGrid
    case date
    case battery
    case countdown
    case weather
    case timer
    case todos
    case hidden
    case mediaWing
    case textWing
    case levelWing

    init(rightSlot content: IslandRightSlotContent) {
        switch content {
        case .count: self = .agentCount
        case .agents: self = .agentGrid
        }
    }

    init(sideSlot content: NookSideSlotContent) {
        switch content {
        case .bars: self = .bars
        case .agentSlot(let slot): self = Self(rightSlot: slot)
        case .date: self = .date
        case .battery: self = .battery
        case .countdown: self = .countdown
        case .weather: self = .weather
        case .timer: self = .timer
        case .todos: self = .todos
        case .hidden: self = .hidden
        }
    }

    init(leading: NookClosedActivity.Leading) {
        switch leading {
        case .artwork: self = .artwork
        case .symbol(let name, _): self = .symbol(name)
        }
    }

    init(trailing: NookClosedActivity.Trailing) {
        switch trailing {
        case .media: self = .mediaWing
        case .text: self = .textWing
        case .level: self = .levelWing
        }
    }
}

/// Everything about the closed pill whose change should animate. The pill
/// animates on this instead of on its width alone, so swapping two things of
/// the same width (a date for a battery) morphs too.
struct PillContentKey: Equatable {
    /// The activity without the values that change on their own (play state,
    /// GIF placement, artwork), which are not content swaps.
    struct ActivityKey: Equatable {
        var leading: PillSlotIdentity
        var trailing: PillSlotIdentity?
        var text: String?
        var showsOnRight: Bool
    }

    var label: String?
    var rightSlot: IslandRightSlotContent?
    var mode: UnifiedBars.Mode
    var activity: ActivityKey?
    var leftSlot: NookSideSlotContent?
    var rightExtra: NookSideSlotContent?
    var layout: V6ClosedLayout
}

// MARK: - Closed-pill layouts

/// The canonical v6 closed-island pill rendered inside a fixed-height frame.
/// Pure view — takes all parameters explicitly so it can be reused for the
/// live settings preview and the real island.
///
/// One body serves both layouts. The layout only changes the fill, the edge
/// padding, whether the label shows and how wide the trailing wing is, so
/// switching layouts morphs the width instead of cutting.
struct V6ClosedPill: View {
    var mode: UnifiedBars.Mode
    var label: String?          // suppressed automatically in MacBook layout
    var rightSlot: IslandRightSlotContent?
    var layout: V6ClosedLayout
    var height: CGFloat = 32

    /// MacBook mode only — width of the physical notch cutout to wrap.
    var physicalNotchWidth: CGFloat = 0

    /// External mode only — minimum pill width (locked). Defaults to the
    /// width that fits just the glyph.
    var minWidth: CGFloat = 70

    /// Nook: what the two wings show instead of the glyph and right slot
    /// (album art + GIF while music plays, symbol + text for a timer or a
    /// transient notice).
    var activity: NookClosedActivity? = nil
    /// Whether an agent is waiting on the user. Activities that
    /// `yieldsToAgents` hand the right wing back to the agent slot then.
    var agentsNeedAttention: Bool = false
    /// Status dot drawn on the album art so agent activity stays visible
    /// while music plays.
    var agentStatusTint: Color? = nil
    /// Nook: what replaces the agent bars on the left while nothing else
    /// claims it. A waiting agent always gets the bars back.
    var leftSlot: NookSideSlotContent? = nil
    /// Nook: the same for the right side. The island's own right slot
    /// comes back while an agent waits.
    var rightExtra: NookSideSlotContent? = nil
    /// False omits the fill, for when the island draws one surface behind the
    /// pill (the closed pill morphs into the opened island).
    var drawsBackground: Bool = true
    /// False freezes the visualizer, the GIF and the bars, for when the pill
    /// is hidden behind the opened island.
    var isLive: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The right-side extra, unless an agent is waiting and has a slot to show.
    private var shownRightExtra: NookSideSlotContent? {
        guard let rightExtra, !showsActivityOnRight else { return nil }
        if agentsNeedAttention, rightSlot != nil { return nil }
        return rightExtra
    }

    private var shownLeftSlot: NookSideSlotContent? {
        guard activity == nil, mode != .waiting else { return nil }
        return leftSlot
    }

    /// The label only exists in the external layout.
    private var shownLabel: String? {
        layout == .external ? label : nil
    }

    private var leadingWidth: CGFloat {
        shownLeftSlot.map { NookSideSlotView.width(of: $0) } ?? 24
    }

    static let plainWingWidth: CGFloat = 44
    static let mediaWingWidth: CGFloat = 50
    /// Horizontal inset while an activity shows; tighter than the plain pad
    /// so the art and GIF sit close to the physical notch.
    private static let activityPad: CGFloat = 12
    private static let externalMediaSideWidth: CGFloat = 52

    private var showsActivityOnRight: Bool {
        guard let activity, activity.trailing != nil else { return false }
        return !(agentsNeedAttention && activity.yieldsToAgents && rightSlot != nil)
    }

    private var albumArtSize: CGFloat { max(16, height - 10) }

    // Horizontal edge padding is identical left/right — canonical v6 pill
    // has r = h/2 semicircular bottoms, so edge inset = r keeps content
    // clear of the curve.
    private var pad: CGFloat { height / 2 }

    // Minimum breathing room between the center label (or glyph, when no
    // label) and the right-slot content so they never touch at small widths.
    private static let innerGap: CGFloat = 6

    var resolvedWidth: CGFloat {
        switch layout {
        case .external:
            let glyphWidth = leadingWidth
            let labelWidth = label.map { V6CenterLabelView.intrinsicWidth(of: $0) } ?? 0
            let rightWidth = rightSlot.map { V6RightSlotView.intrinsicWidth(of: $0) } ?? 0
            let labelBlock = label == nil ? 0 : 6 + labelWidth
            let rightBlock: CGFloat
            if showsActivityOnRight {
                rightBlock = Self.innerGap + Self.externalMediaSideWidth
            } else if let extra = shownRightExtra {
                rightBlock = Self.innerGap + NookSideSlotView.width(of: extra)
            } else {
                rightBlock = rightSlot == nil ? 0 : Self.innerGap + rightWidth
            }
            return max(minWidth, pad * 2 + glyphWidth + labelBlock + rightBlock)
        case .macbook:
            let wing = activity == nil ? Self.plainWingWidth : Self.mediaWingWidth
            return wing + physicalNotchWidth + wing
        }
    }

    // MARK: Per-layout values

    /// External pads by `pad` always; the MacBook pill tightens to
    /// `activityPad` while an activity shows.
    private var horizontalPadding: CGFloat {
        layout == .macbook && activity != nil ? Self.activityPad : pad
    }

    /// The MacBook pill spans the whole notch, so its two sides can touch the
    /// spacer; the external pill keeps `innerGap` between them.
    private var spacerMinLength: CGFloat {
        layout == .macbook ? 0 : Self.innerGap
    }

    private var trailingWingWidth: CGFloat {
        switch layout {
        case .external: Self.externalMediaSideWidth
        case .macbook: Self.mediaWingWidth - Self.activityPad - 2
        }
    }

    // MARK: Content

    /// What the right side shows, in priority order.
    private enum RightContent {
        case wing(NookClosedActivity.Trailing)
        case extra(NookSideSlotContent)
        case agents(IslandRightSlotContent)

        var identity: PillSlotIdentity {
            switch self {
            case .wing(let trailing): PillSlotIdentity(trailing: trailing)
            case .extra(let extra): PillSlotIdentity(sideSlot: extra)
            case .agents(let slot): PillSlotIdentity(rightSlot: slot)
            }
        }
    }

    private var rightContent: RightContent? {
        if showsActivityOnRight, let trailing = activity?.trailing { return .wing(trailing) }
        if let extra = shownRightExtra { return .extra(extra) }
        if let rightSlot { return .agents(rightSlot) }
        return nil
    }

    private var leadingIdentity: PillSlotIdentity {
        if let activity { return PillSlotIdentity(leading: activity.leading) }
        if let leftSlot = shownLeftSlot { return PillSlotIdentity(sideSlot: leftSlot) }
        return .bars
    }

    /// Everything the pill animates on. Two pills with the same width but
    /// different content have different keys.
    var contentKey: PillContentKey {
        PillContentKey(
            label: shownLabel,
            rightSlot: rightSlot,
            mode: mode,
            activity: activity.map { activity in
                let text: String?
                switch activity.trailing {
                case .text(let value): text = value
                case .level(let percent, _): text = "\(percent)"
                case .media, nil: text = nil
                }
                return PillContentKey.ActivityKey(
                    leading: PillSlotIdentity(leading: activity.leading),
                    trailing: activity.trailing.map { PillSlotIdentity(trailing: $0) },
                    text: text,
                    showsOnRight: showsActivityOnRight
                )
            },
            leftSlot: shownLeftSlot,
            rightExtra: shownRightExtra,
            layout: layout
        )
    }

    /// What the width and the fill animate on.
    private struct ShapeKey: Equatable {
        var width: CGFloat
        var layout: V6ClosedLayout
    }

    /// Slot swaps blur-replace, except under Reduce Motion or a motion
    /// policy that has dropped blur (Low Power, thermal), which only fade.
    private var slotTransition: AnyTransition {
        PillSlotSwap.resolve(
            reduceMotion: reduceMotion,
            allowsBlur: SystemMotionMonitor.shared.policy.allowsBlur
        ).transition
    }

    private var labelTransition: AnyTransition {
        Motion.transition(.opacity.combined(with: .move(edge: .leading)), reduceMotion: reduceMotion)
    }

    var body: some View {
        ZStack {
            if drawsBackground {
                V6ClosedPillShape()
                    .fill(V6Palette.surface(for: layout))
            }

            HStack(spacing: 0) {
                leadingGlyph
                    .frame(width: leadingWidth, height: 24)
                    .id(leadingIdentity)
                    .transition(slotTransition)

                if let shownLabel {
                    V6CenterLabelView(text: shownLabel)
                        .padding(.leading, 6)
                        .transition(labelTransition)
                }

                Spacer(minLength: spacerMinLength)

                if let right = rightContent {
                    rightView(right)
                        .id(right.identity)
                        .transition(slotTransition)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .motionAnimation(Motion.contentSwap, value: contentKey)
        }
        .frame(width: resolvedWidth, height: height)
        // Moving content never draws outside the pill.
        .clipShape(V6ClosedPillShape())
        .motionAnimation(Motion.morph, value: ShapeKey(width: resolvedWidth, layout: layout))
    }

    /// Album art or a symbol while the Nook has something to show, the
    /// agent glyph otherwise.
    @ViewBuilder
    private var leadingGlyph: some View {
        if let activity {
            NookLeadingWingView(leading: activity.leading, size: albumArtSize, statusTint: agentStatusTint)
        } else if let leftSlot = shownLeftSlot {
            NookSideSlotView(content: leftSlot, size: 24, isLive: isLive)
        } else {
            UnifiedBars(mode: mode, size: 24, isPaused: !isLive)
        }
    }

    @ViewBuilder
    private func rightView(_ content: RightContent) -> some View {
        switch content {
        case .wing(let trailing):
            NookTrailingWingView(trailing: trailing, height: height - 6, width: trailingWingWidth, isLive: isLive)
        case .extra(let extra):
            NookSideSlotView(content: extra, size: 24, isLive: isLive)
        case .agents(let slot):
            V6RightSlotView(content: slot, isLive: isLive)
        }
    }
}

/// How a slot swap looks. The choice is a pure function so a test can check it.
enum PillSlotSwap: Equatable {
    case blurReplace
    case fade

    static func resolve(reduceMotion: Bool, allowsBlur: Bool) -> PillSlotSwap {
        reduceMotion || !allowsBlur ? .fade : .blurReplace
    }

    var transition: AnyTransition {
        switch self {
        case .blurReplace: Motion.slotSwap
        case .fade: .opacity
        }
    }
}

/// Two pills are equal when every input is. `NookClosedActivity` compares
/// artwork by identity, as it already does, so a new track is a change.
extension V6ClosedPill: Equatable {
    nonisolated static func == (lhs: V6ClosedPill, rhs: V6ClosedPill) -> Bool {
        lhs.mode == rhs.mode
            && lhs.label == rhs.label
            && lhs.rightSlot == rhs.rightSlot
            && lhs.layout == rhs.layout
            && lhs.height == rhs.height
            && lhs.physicalNotchWidth == rhs.physicalNotchWidth
            && lhs.minWidth == rhs.minWidth
            && lhs.activity == rhs.activity
            && lhs.agentsNeedAttention == rhs.agentsNeedAttention
            && lhs.agentStatusTint == rhs.agentStatusTint
            && lhs.leftSlot == rhs.leftSlot
            && lhs.rightExtra == rhs.rightExtra
            && lhs.drawsBackground == rhs.drawsBackground
            && lhs.isLive == rhs.isLive
    }
}

enum V6ClosedLayout: Equatable {
    case external
    case macbook
}

// MARK: - Settings-tab live preview

/// Fixed-width pill that mimics the real island inside the settings-tab
/// preview stage. Parameters match what the tab exposes.
struct IslandPreviewPill: View {
    let mode: UnifiedBars.Mode
    let label: String?
    let rightSlot: IslandRightSlotContent?
    let layout: V6ClosedLayout
    let physicalNotchWidth: CGFloat
    /// Kept so existing call sites compile. The pill no longer reads it, and
    /// it does not take part in equality.
    var now: Date? = nil
    /// Nook: lets the preview show the closed island while music plays.
    var activity: NookClosedActivity? = nil
    var agentsNeedAttention: Bool = false
    var agentStatusTint: Color? = nil
    var leftSlot: NookSideSlotContent? = nil
    var rightExtra: NookSideSlotContent? = nil

    var body: some View {
        V6ClosedPill(
            mode: mode,
            label: label,
            rightSlot: rightSlot,
            layout: layout,
            physicalNotchWidth: physicalNotchWidth,
            activity: activity,
            agentsNeedAttention: agentsNeedAttention,
            agentStatusTint: agentStatusTint,
            leftSlot: leftSlot,
            rightExtra: rightExtra
        )
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

extension IslandPreviewPill: Equatable {
    nonisolated static func == (lhs: IslandPreviewPill, rhs: IslandPreviewPill) -> Bool {
        lhs.mode == rhs.mode
            && lhs.label == rhs.label
            && lhs.rightSlot == rhs.rightSlot
            && lhs.layout == rhs.layout
            && lhs.physicalNotchWidth == rhs.physicalNotchWidth
            && lhs.activity == rhs.activity
            && lhs.agentsNeedAttention == rhs.agentsNeedAttention
            && lhs.agentStatusTint == rhs.agentStatusTint
            && lhs.leftSlot == rhs.leftSlot
            && lhs.rightExtra == rhs.rightExtra
    }
}
