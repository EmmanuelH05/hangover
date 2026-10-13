import SwiftUI

/// A made-up beat for the tour's pictures of the lights (D56). Nothing here
/// listens to anything: the pictures play a short pattern of their own, which
/// is why the page can show the lights before the user has allowed a sound
/// tap. It is a plain value, which keeps the pattern testable.
enum OnboardingBeatLoop {
    /// One bar, a step at a time: how hard the hit is, from 0 for none to 1.
    /// A kick, a snare, a kick, a snare with a flicker before it.
    static let pattern: [Double] = [1, 0, 0.5, 0, 1, 0.3, 0.5, 0]
    /// How many bars a picture plays before it comes to rest. Nothing here
    /// repeats forever (D38): the picture plays again when its page asks.
    static let bars = 3
    static let stepDuration: TimeInterval = 0.2
    /// What the glow shows between hits, as a fraction of its full strength.
    static let restStrength: Double = 0.25

    static var stepCount: Int { pattern.count * bars }

    /// Every step of a run: the bar, `bars` times. With `dimmed` on ("Dim
    /// flashing lights" is on in macOS) a hit that would come closer than
    /// `IslandBeatLimits.dimmedFlashGap` to the one before it is left out,
    /// across the bars too, which holds the picture to what the real lights
    /// do under that setting.
    static func steps(dimmed: Bool) -> [Double] {
        let all = (0..<stepCount).map { pattern[$0 % pattern.count] }
        guard dimmed else { return all }
        var lastHit: Int?
        return all.enumerated().map { index, strength in
            guard strength > 0 else { return 0 }
            if let lastHit, Double(index - lastHit) * stepDuration < IslandBeatLimits.dimmedFlashGap { return 0 }
            lastHit = index
            return strength
        }
    }

    /// The hit at a step, from 0 to 1. Zero outside the pattern.
    static func strength(at step: Int, dimmed: Bool = false) -> Double {
        guard (0..<stepCount).contains(step) else { return 0 }
        return steps(dimmed: dimmed)[step]
    }

    /// Which of the four colors the glow is in at a step: the next one on
    /// each hit, and the same one in between.
    static func hue(at step: Int, dimmed: Bool = false) -> Int {
        guard step >= 0 else { return 0 }
        let hits = steps(dimmed: dimmed).prefix(min(step, stepCount - 1) + 1).filter { $0 > 0 }.count
        return max(0, hits - 1) % hues.count
    }

    /// The four colors a hit takes in turn, the tour's own.
    static let hues: [Color] = [
        OnboardingStyle.album,
        OnboardingStyle.working,
        OnboardingStyle.finished,
        OnboardingStyle.waiting,
    ]
}

/// The closed island and the light of one look: the glow pulsing out under
/// the pill, or beams shooting out of it, playing `OnboardingBeatLoop` and
/// coming to rest. A picture drawn offscreen shows one hit at its peak
/// (`nookDrawsStill`), as does one with Reduce Motion on, which does not
/// play. With "Dim flashing lights" on it plays the pattern with the close
/// hits left out.
struct OnboardingBeatPicture: View {
    let look: IslandBeatLook
    /// Changes when the picture should play again.
    var restartKey = 0
    /// Reduce Motion is on in macOS: the picture stays on its peak frame.
    var reduceMotion = false
    /// "Dim flashing lights" is on in macOS.
    var dimsFlashingLights = false

    @Environment(\.nookDrawsStill) private var drawsStill
    /// The step being shown, or nil at rest.
    @State private var step: Int?

    private static let pillSize = CGSize(width: 150, height: 28)
    private static let beamAngles: [Double] = [-64, -48, -32, -16, 0, 16, 32, 48, 64]
    private static let beamLength: CGFloat = 62

    var body: some View {
        let shown = Self.shownStep(playing: step, drawsStill: drawsStill, reduceMotion: reduceMotion)
        let strength = shown.map { OnboardingBeatLoop.strength(at: $0, dimmed: dimsFlashingLights) } ?? 0
        let color = OnboardingBeatLoop.hues[shown.map { OnboardingBeatLoop.hue(at: $0, dimmed: dimsFlashingLights) } ?? 0]
        ZStack(alignment: .top) {
            if look == .lasers {
                beams(strength: strength, color: color)
            }
            OnboardingPillArt(
                width: Self.pillSize.width,
                height: Self.pillSize.height,
                glow: color,
                glowStrength: look == .glow ? OnboardingBeatLoop.restStrength + (1 - OnboardingBeatLoop.restStrength) * strength : 0.2,
                left: .art,
                right: .nothing
            )
        }
        .frame(width: 190, height: 96, alignment: .top)
        .task(id: restartKey) { await play() }
        .accessibilityHidden(true)
    }

    /// The step the picture draws: the peak frame when it is drawn offscreen
    /// or Reduce Motion is on, and otherwise the one that is playing (nil at
    /// rest).
    static func shownStep(playing step: Int?, drawsStill: Bool, reduceMotion: Bool) -> Int? {
        drawsStill || reduceMotion ? 0 : step
    }

    /// Reduce Motion plays nothing: the still frame is the picture.
    static func plays(reduceMotion: Bool) -> Bool { !reduceMotion }

    /// The beams fan out under the pill on a hit, and are gone between hits.
    private func beams(strength: Double, color: Color) -> some View {
        ZStack(alignment: .top) {
            ForEach(Array(Self.beamAngles.enumerated()), id: \.offset) { _, angle in
                Capsule()
                    .fill(color)
                    .frame(width: 2.5, height: Self.beamLength * (0.3 + 0.7 * strength))
                    .rotationEffect(.degrees(angle * 0.9), anchor: .top)
            }
        }
        .opacity(strength)
        .offset(y: Self.pillSize.height - 4)
    }

    /// Plays the pattern, then rests. Cancelled when the picture goes away.
    private func play() async {
        guard Self.plays(reduceMotion: reduceMotion) else { return }
        for index in 0..<OnboardingBeatLoop.stepCount {
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: OnboardingBeatLoop.stepDuration * 0.7)) { step = index }
            try? await Task.sleep(for: .seconds(OnboardingBeatLoop.stepDuration))
        }
        if Task.isCancelled { return }
        withAnimation(.easeOut(duration: 0.4)) { step = nil }
    }
}
