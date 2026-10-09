import AppKit
import SwiftUI

/// v6 `UnifiedBars` glyph — three vertical bars that share the same geometry
/// across all three notch states (idle / running / waiting). Active states are
/// animated by Core Animation layers so SwiftUI does not invalidate every frame.
///
/// Canonical geometry (from the design handoff): 24×24 box, 3 bars of width
/// 2.5 centered on columns x = 5.25 / 10.75 / 16.25, rounded to a pill.
///
/// Motion model (D16):
/// - `LayerView.update` is idempotent. It stores what it last applied and does
///   nothing when mode, tint and pause state are unchanged.
/// - `layout()` only places the 24 pt design box. It never touches animations.
/// - A mode change springs every bar from what is on screen to the new resting
///   shape. The new mode's loop is added on a global time grid underneath that
///   spring, so the spring lands exactly on the loop and the loop never visibly
///   restarts. All bar instances share the grid and stay in phase.
struct UnifiedBars: View {
    enum Mode: Equatable {
        case idle       // rest — 3 short static bars
        case running    // active — looping wave
        case waiting    // pause — outer bars pulse, middle hidden

        var timelineInterval: TimeInterval? {
            nil
        }

        var usesLayerAnimation: Bool {
            switch self {
            case .idle:
                false
            case .running, .waiting:
                true
            }
        }
    }

    var mode: Mode
    var size: CGFloat = 24
    /// Ink color for bars / tick. Defaults to the v6 paper ink.
    var tint: Color = Color(red: 0xf1 / 255.0, green: 0xea / 255.0, blue: 0xd9 / 255.0)
    /// Freezes the loops while the bars are hidden (the closed pill behind
    /// the opened island). Resuming continues from the frozen frame.
    var isPaused = false

    private nonisolated static let box: CGFloat = 24
    private nonisolated static let barWidth: CGFloat = 2.5
    private nonisolated static let center: CGFloat = 12

    /// Running wave period; the stagger between bars is `Column.waveDelay`.
    nonisolated static let runningPeriod: CFTimeInterval = 0.9
    /// Waiting fade period; the right bar runs half a period behind the left.
    nonisolated static let waitingPeriod: CFTimeInterval = 1.8

    private nonisolated static let columns: [Column] = [
        Column(x: 5.25,  idleH: 3, waveCycle: [4, 12, 4], waveDelay: 0.00, waitH: 10, waitDelay: 0),
        Column(x: 10.75, idleH: 5, waveCycle: [6, 14, 6], waveDelay: 0.15, waitH: 0,  waitDelay: 0),
        Column(x: 16.25, idleH: 3, waveCycle: [4, 10, 4], waveDelay: 0.30, waitH: 10, waitDelay: 0.9),
    ]

    /// Visible bar heights, left to right, in the 24 pt design box when the bars
    /// rest in `mode`. Running reports the first frame of the wave (the frame
    /// the loop passes through at phase 0). Waiting reports 0 for the hidden
    /// middle bar.
    nonisolated static func barHeights(for mode: Mode) -> [CGFloat] {
        columns.map { column in
            switch mode {
            case .idle: column.idleH
            case .running: column.waveCycle.first ?? column.idleH
            case .waiting: column.waitH
            }
        }
    }

    /// Start time for a looping animation on the shared cycle grid: the most
    /// recent moment at or before `now` where a loop with this `period` and
    /// stagger `delay` is at phase 0 on the shared clock. Every loop added with
    /// this time plays as if it had been running since time zero, so re-adding
    /// one never restarts it and all instances stay in phase.
    nonisolated static func alignedBeginTime(
        now: CFTimeInterval,
        period: CFTimeInterval,
        delay: CFTimeInterval
    ) -> CFTimeInterval {
        guard period > 0 else { return now }
        return ((now - delay) / period).rounded(.down) * period + delay
    }

    var body: some View {
        LayerRepresentable(mode: mode, tint: tint, isPaused: isPaused)
            .frame(width: size, height: size)
    }

    private struct LayerRepresentable: NSViewRepresentable {
        let mode: Mode
        let tint: Color
        let isPaused: Bool

        func makeNSView(context: Context) -> LayerView {
            let view = LayerView()
            view.update(mode: mode, tint: NSColor(tint), isPaused: isPaused)
            return view
        }

        func updateNSView(_ nsView: LayerView, context: Context) {
            nsView.update(mode: mode, tint: NSColor(tint), isPaused: isPaused)
        }
    }

    // MARK: - Layer view

    final class LayerView: NSView {
        /// Key of the running/waiting loop on each bar layer.
        static let loopKey = "bars.loop"
        /// Key of the tint cross-fade on each bar layer.
        static let tintKey = "bars.tint"
        static let pathMoveKey = "bars.move.path"
        static let opacityMoveKey = "bars.move.opacity"

        /// Spring for mode changes. Response 0.2 s with damping ratio 0.8 settles
        /// in about 0.3 s with a hint of bounce.
        private static let springResponse = 0.2
        private static let springDampingRatio = 0.8
        private static let tintDuration: CFTimeInterval = 0.3
        private static let settleDuration = makeSpring(keyPath: "path").settlingDuration

        /// Left, middle, right.
        let barLayers = [CAShapeLayer(), CAShapeLayer(), CAShapeLayer()]
        /// Holds the 24 pt design box and carries the scale to the view's size.
        private let boxLayer = CALayer()

        private struct Applied: Equatable {
            var mode: Mode
            var tint: CGColor
            var isPaused: Bool
        }

        private var applied: Applied?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = CALayer()
            layer?.masksToBounds = false

            boxLayer.bounds = CGRect(x: 0, y: 0, width: UnifiedBars.box, height: UnifiedBars.box)
            boxLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer?.addSublayer(boxLayer)

            let scale = NSScreen.main?.backingScaleFactor ?? 2
            for barLayer in barLayers {
                barLayer.bounds = boxLayer.bounds
                barLayer.position = CGPoint(x: UnifiedBars.box / 2, y: UnifiedBars.box / 2)
                barLayer.contentsScale = scale
                boxLayer.addSublayer(barLayer)
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // MARK: State

        func update(mode: Mode, tint: NSColor, isPaused: Bool = false) {
            let next = Applied(mode: mode, tint: tint.cgColor, isPaused: isPaused)
            guard next != applied else { return }
            let previous = applied
            applied = next

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if previous?.mode != next.mode {
                applyMode(next.mode, animated: previous != nil)
            }
            if previous?.tint != next.tint {
                applyTint(next.tint, animated: previous != nil)
            }
            if (previous?.isPaused ?? false) != next.isPaused {
                applyPause(next.isPaused)
            }
            CATransaction.commit()
        }

        // MARK: Geometry

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            needsLayout = true
        }

        override func layout() {
            super.layout()
            layoutBox()
        }

        /// Geometry only: centers the design box and scales it to the view.
        private func layoutBox() {
            let side = min(bounds.width, bounds.height)
            guard side > 0 else { return }

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            boxLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            boxLayer.setAffineTransform(CGAffineTransform(scaleX: side / UnifiedBars.box, y: side / UnifiedBars.box))
            CATransaction.commit()
        }

        // MARK: Mode

        private func applyMode(_ mode: Mode, animated: Bool) {
            let now = localTime()
            let settle = Self.settleDuration

            for (index, column) in UnifiedBars.columns.enumerated() {
                let barLayer = barLayers[index]
                let presentation = barLayer.presentation()
                let fromPath = presentation?.path ?? barLayer.path
                let fromOpacity = presentation?.opacity ?? barLayer.opacity

                for key in [Self.loopKey, Self.pathMoveKey, Self.opacityMoveKey] {
                    barLayer.removeAnimation(forKey: key)
                }

                let rest = column.rest(for: mode)
                barLayer.path = Self.pillPath(column: column, height: rest.height)
                barLayer.opacity = rest.opacity

                // The loop goes in first so the transition springs stack on top of it.
                let heightLoop = column.heightLoop(for: mode)
                let opacityLoop = column.opacityLoop(for: mode)
                if let heightLoop {
                    barLayer.add(
                        Self.loopAnimation(
                            keyPath: "path",
                            values: heightLoop.values.map { Self.pillPath(column: column, height: $0) },
                            loop: heightLoop,
                            now: now
                        ),
                        forKey: Self.loopKey
                    )
                }
                if let opacityLoop {
                    barLayer.add(
                        Self.loopAnimation(
                            keyPath: "opacity",
                            values: opacityLoop.values.map { Float($0) },
                            loop: opacityLoop,
                            now: now
                        ),
                        forKey: Self.loopKey
                    )
                }

                guard animated else { continue }

                // Land exactly where the loop will be when the transition ends.
                let end = now + settle
                let targetHeight = heightLoop?.value(at: end) ?? rest.height
                let targetOpacity = opacityLoop.map { Float($0.value(at: end)) } ?? rest.opacity

                if let fromPath {
                    let spring = Self.makeSpring(keyPath: "path")
                    spring.fromValue = fromPath
                    spring.toValue = Self.pillPath(column: column, height: targetHeight)
                    spring.duration = settle
                    spring.beginTime = now
                    barLayer.add(spring, forKey: Self.pathMoveKey)
                }

                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = fromOpacity
                fade.toValue = targetOpacity
                fade.duration = settle
                fade.beginTime = now
                fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                barLayer.add(fade, forKey: Self.opacityMoveKey)
            }
        }

        private static func loopAnimation(
            keyPath: String,
            values: [Any],
            loop: Loop,
            now: CFTimeInterval
        ) -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = values
            animation.keyTimes = [0, 0.5, 1]
            animation.duration = loop.period
            animation.beginTime = UnifiedBars.alignedBeginTime(now: now, period: loop.period, delay: loop.delay)
            animation.repeatCount = .infinity
            animation.timingFunctions = [
                CAMediaTimingFunction(name: .easeInEaseOut),
                CAMediaTimingFunction(name: .easeInEaseOut),
            ]
            return animation
        }

        private static func makeSpring(keyPath: String) -> CASpringAnimation {
            let omega = 2 * Double.pi / springResponse
            let spring = CASpringAnimation(keyPath: keyPath)
            spring.mass = 1
            spring.stiffness = omega * omega
            spring.damping = 2 * springDampingRatio * omega
            spring.initialVelocity = 0
            return spring
        }

        /// A true pill (not a scaled one) so the caps stay round at every height.
        private static func pillPath(column: Column, height: CGFloat) -> CGPath {
            let radius = min(UnifiedBars.barWidth, height) / 2
            return CGPath(
                roundedRect: CGRect(
                    x: column.x,
                    y: UnifiedBars.center - height / 2,
                    width: UnifiedBars.barWidth,
                    height: height
                ),
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil
            )
        }

        // MARK: Tint

        private func applyTint(_ color: CGColor, animated: Bool) {
            for barLayer in barLayers {
                let from = barLayer.presentation()?.fillColor ?? barLayer.fillColor
                barLayer.fillColor = color
                guard animated, let from else { continue }

                let fade = CABasicAnimation(keyPath: "fillColor")
                fade.fromValue = from
                fade.toValue = color
                fade.duration = Self.tintDuration
                fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                barLayer.add(fade, forKey: Self.tintKey)
            }
        }

        // MARK: Pause

        /// Standard CALayer pause and resume on the root layer: pausing stops the
        /// layer's clock at the current time, resuming restarts it from there.
        private func applyPause(_ paused: Bool) {
            guard let root = layer else { return }
            if paused {
                guard root.speed != 0 else { return }
                let pausedTime = root.convertTime(CACurrentMediaTime(), from: nil)
                root.speed = 0
                root.timeOffset = pausedTime
            } else {
                guard root.speed == 0 else { return }
                let pausedTime = root.timeOffset
                root.speed = 1
                root.timeOffset = 0
                root.beginTime = 0
                root.beginTime = root.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
            }
        }

        /// Now in the bars' own time. It differs from media time after a pause and
        /// resume, and every begin time must be expressed in it.
        private func localTime() -> CFTimeInterval {
            barLayers[0].convertTime(CACurrentMediaTime(), from: nil)
        }
    }

    // MARK: - Model

    /// One looping value of one bar: the values at key times 0, 0.5 and 1.
    fileprivate struct Loop {
        let values: [CGFloat]
        let period: CFTimeInterval
        let delay: CFTimeInterval

        /// The loop's value at `time`, matching Core Animation's ease-in-out
        /// keyframes, so a transition can land on it.
        func value(at time: CFTimeInterval) -> CGFloat {
            guard values.count == 3, period > 0 else { return values.first ?? 0 }
            let cycles = (time - delay) / period
            let phase = cycles - cycles.rounded(.down)
            if phase < 0.5 {
                return Self.lerp(values[0], values[1], Self.easeInOut(phase * 2))
            }
            return Self.lerp(values[1], values[2], Self.easeInOut(phase * 2 - 1))
        }

        private static func lerp(_ from: CGFloat, _ to: CGFloat, _ progress: Double) -> CGFloat {
            from + (to - from) * CGFloat(progress)
        }

        /// `CAMediaTimingFunction.easeInEaseOut`: cubic Bezier (0.42, 0, 0.58, 1).
        private static func easeInOut(_ x: Double) -> Double {
            func bezier(_ t: Double, _ a: Double, _ b: Double) -> Double {
                let u = 1 - t
                return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
            }
            var low = 0.0
            var high = 1.0
            for _ in 0..<32 {
                let mid = (low + high) / 2
                if bezier(mid, 0.42, 0.58) < x { low = mid } else { high = mid }
            }
            return bezier((low + high) / 2, 0, 1)
        }
    }

    fileprivate struct Rest {
        let height: CGFloat
        let opacity: Float
    }

    fileprivate struct Column: Equatable {
        let x: CGFloat
        let idleH: CGFloat
        let waveCycle: [CGFloat]
        let waveDelay: TimeInterval
        let waitH: CGFloat
        let waitDelay: TimeInterval

        /// Shape and opacity the bar settles on in `mode`. A bar that is hidden
        /// in a mode keeps its idle shape and fades out, so coming back only
        /// needs the fade.
        func rest(for mode: Mode) -> Rest {
            switch mode {
            case .idle:
                Rest(height: idleH, opacity: 1)
            case .running:
                Rest(height: waveCycle.first ?? idleH, opacity: 1)
            case .waiting:
                waitH > 0
                    ? Rest(height: waitH, opacity: Float(UnifiedBars.waitingLow))
                    : Rest(height: idleH, opacity: 0)
            }
        }

        func heightLoop(for mode: Mode) -> Loop? {
            guard mode == .running, waveCycle.count == 3, (waveCycle.max() ?? 0) > 0 else { return nil }
            return Loop(values: waveCycle, period: UnifiedBars.runningPeriod, delay: waveDelay)
        }

        func opacityLoop(for mode: Mode) -> Loop? {
            guard mode == .waiting, waitH > 0 else { return nil }
            return Loop(
                values: [UnifiedBars.waitingLow, 1, UnifiedBars.waitingLow],
                period: UnifiedBars.waitingPeriod,
                delay: waitDelay
            )
        }
    }

    private nonisolated static let waitingLow: CGFloat = 0.55
}
