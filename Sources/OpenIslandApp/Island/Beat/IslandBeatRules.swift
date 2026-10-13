import Foundation

/// The facts that decide whether Hangover listens to the Mac's sound (D56).
struct IslandBeatListeningInputs: Equatable, Sendable {
    /// "Pulse with the beat" for the display the island is on.
    var isSwitchOn: Bool
    var style: IslandHaloStyle
    /// "Glow with music", on a display whose closed island shows music.
    var followsMusic: Bool
    var isMusicPlaying: Bool
    var policy: IslandMotionPolicy
    /// Music is what the closed island shows, a short notice aside: no
    /// swipe has hidden it and no timer holds it.
    var islandShowsMusic: Bool
    var isIslandClosed: Bool
    /// The screen is awake and unlocked, and this user's session is the
    /// one in front. A glow nobody can see is not listened for.
    var isScreenOn: Bool

    /// The switch is off. Nothing else was looked at.
    static let off = IslandBeatListeningInputs(
        isSwitchOn: false, style: .off, followsMusic: false, isMusicPlaying: false,
        policy: .minimal, islandShowsMusic: false, isIslandClosed: false, isScreenOn: false
    )
}

/// What to do with the tap for a set of inputs.
enum IslandBeatDecision: Equatable, Sendable {
    /// Everything holds: listen.
    case listen
    /// Only the music paused or the island opened, both of which are over
    /// in a moment more often than not. A tap that runs is kept for
    /// `IslandBeatController.grace` before it is destroyed, which saves
    /// building an audio device on every pause and every look at the
    /// island.
    case linger
    /// Destroy the tap at once.
    case stop
}

enum IslandBeatRules {
    /// Whether the system lets the glow follow the song. Reduce Motion, Low
    /// Power Mode and a serious or critical thermal state all say no.
    static func allowsPulse(_ policy: IslandMotionPolicy) -> Bool {
        policy.animates && policy.allowsAmbient && !policy.waitingOnly
    }

    /// Listening is only for a pulse that would be drawn. The switch, the
    /// glow, glow with music, the motion policy, the screen and what the
    /// island shows stop the tap the moment one of them stops holding.
    /// Music pausing and the island opening leave it a grace time.
    static func decision(_ inputs: IslandBeatListeningInputs) -> IslandBeatDecision {
        guard inputs.isSwitchOn,
              inputs.style != .off,
              inputs.followsMusic,
              allowsPulse(inputs.policy),
              inputs.isScreenOn,
              inputs.islandShowsMusic else { return .stop }
        return inputs.isMusicPlaying && inputs.isIslandClosed ? .listen : .linger
    }

    /// True when every input holds.
    static func shouldListen(_ inputs: IslandBeatListeningInputs) -> Bool {
        decision(inputs) == .listen
    }
}

/// The colors a pulsing glow steps through on the beat (D56).
enum IslandBeatHues {
    /// How far each color sits from the art's own, in turns of the color
    /// wheel, in the order the beat steps through them. Two on each side,
    /// and every step is a visible change.
    static let offsets: [Double] = [-0.14, 0.05, -0.05, 0.14]

    /// Magenta, cyan, purple and green, for art with no color of its own.
    static let fixed: [IslandHaloRGB] = [
        IslandHaloRGB(rgb: 0xFF3DCB),
        IslandHaloRGB(rgb: 0x32E6FF),
        IslandHaloRGB(rgb: 0xA259FF),
        IslandHaloRGB(rgb: 0x4DFF88),
    ]

    /// A color less saturated than this has no hue worth spreading around.
    static let minimumSaturation = 0.15
    /// The pulse's colors are at least this saturated and this bright.
    static let saturationFloor = 0.6
    static let brightnessFloor = 0.9

    /// Four colors spread around `tint`, or the fixed four when the art is
    /// gray or there is none.
    static func hues(around tint: IslandHaloRGB?) -> [IslandHaloRGB] {
        guard let tint else { return fixed }
        let base = NookArtworkPalette.hsb(of: tint)
        guard base.saturation >= minimumSaturation else { return fixed }
        return offsets.map { offset in
            NookArtworkPalette.rgb(
                hue: wrapped(base.hue + offset),
                saturation: max(base.saturation, saturationFloor),
                brightness: max(base.brightness, brightnessFloor)
            )
        }
    }

    /// A hue brought back into 0..<1.
    static func wrapped(_ hue: Double) -> Double {
        let turned = hue.truncatingRemainder(dividingBy: 1)
        return turned < 0 ? turned + 1 : turned
    }
}

/// How far a pulsing glow goes out, from the user's "How far it reaches"
/// (D56). Plain numbers: the layer turns them into a scale of pictures that
/// are already drawn, and nothing is blurred again for a level.
enum IslandBeatReach {
    /// Where the slider starts: the middle.
    static let standard = 0.5
    /// How far the peak goes at each end of the slider and in the middle,
    /// as a multiple of how far the resting glow goes.
    static let leastFactor: CGFloat = 1.05
    static let standardFactor: CGFloat = 1.4
    static let mostFactor: CGFloat = 2.2

    /// A reach held inside 0 to 1. Anything that is not a number is the
    /// standard.
    static func clamped(_ reach: Double) -> Double {
        guard reach.isFinite else { return standard }
        return min(1, max(0, reach))
    }

    /// How far the peak of the pulse goes for a reach: 1.05 at 0, where the
    /// glow only brightens and barely grows, 1.4 in the middle and 2.2 at 1.
    /// One curve through the three, and it only ever rises.
    static func peakFactor(_ reach: Double) -> CGFloat {
        let r = CGFloat(clamped(reach))
        // The curve through (0, least), (0.5, standard) and (1, most).
        let bend = 2 * (mostFactor + leastFactor - 2 * standardFactor)
        let slope = mostFactor - leastFactor - bend
        return leastFactor + slope * r + bend * r * r
    }

    /// The scale along one side of the pill that takes the glow's edge from
    /// `radius` past the pill to `factor` times `radius` past it. `half` is
    /// half the pill's size along that side.
    static func peakScale(half: CGFloat, radius: CGFloat, factor: CGFloat) -> CGFloat {
        guard half + radius > 0 else { return 1 }
        return max(1, (half + factor * radius) / (half + radius))
    }

    /// How far past the pill's edge a picture scaled by `scale` can paint.
    /// The picture's own paint ends twice its radius out, plus the drop.
    static func outerExtent(half: CGFloat, radius: CGFloat, drop: CGFloat, scale: CGFloat) -> CGFloat {
        scale * (half + radius * 2 + drop) - half
    }

    /// The peak scale for a reach, held to what fits in `room` past the
    /// pill's edge. The glow is never cut off: it stops growing first.
    static func fittedScale(half: CGFloat, radius: CGFloat, drop: CGFloat, reach: Double, room: CGFloat) -> CGFloat {
        let wanted = peakScale(half: half, radius: radius, factor: peakFactor(reach))
        let painted = half + radius * 2 + drop
        guard painted > 0 else { return 1 }
        let most = (half + max(0, room)) / painted
        return max(1, min(wanted, most))
    }

    /// The room a glow has around a closed pill inside the island's window:
    /// to the nearer side edge and down to the bottom edge. The window is
    /// the opened island's size even while the island is closed, and while
    /// closed it takes no clicks at all, which is why the glow may use all
    /// of it. `pill` is in the window's own bottom-up coordinates, and
    /// neither number is more than `limit`, the layer's own drawing area.
    static func room(pill: CGRect, inWindowOfSize window: CGSize, limit: CGFloat) -> (side: CGFloat, below: CGFloat) {
        let side = min(pill.minX, window.width - pill.maxX)
        return (max(0, min(limit, side)), max(0, min(limit, pill.minY)))
    }
}
