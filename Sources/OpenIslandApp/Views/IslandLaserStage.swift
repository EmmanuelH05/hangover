import AppKit
import QuartzCore

/// What kind of window the lasers get, as plain values (D56). Nothing
/// here needs a window to be read, and the window is made from it.
///
/// The beams are decoration and must never be in the way. The window is
/// above the apps' own windows and under everything that asks the user
/// for something: an alert or a permission prompt, which sit on the modal
/// panel level, the Dock, the menu bar and the island's panel. It joins no
/// full screen Space: a film played full screen is music too, and beams
/// across it are not wanted. It takes no click, ever.
struct IslandLaserWindowTraits: Equatable {
    var level: NSWindow.Level
    var styleMask: NSWindow.StyleMask
    var collectionBehavior: NSWindow.CollectionBehavior
    /// A click on a beam goes to whatever is under it.
    var ignoresMouseEvents: Bool
    var acceptsMouseMovedEvents: Bool
    var hasShadow: Bool
    var isOpaque: Bool
    /// Where it is put among the windows of its level, against the
    /// island's panel.
    var order: NSWindow.OrderingMode

    /// One level under the modal panels. In the demo mode the backdrop
    /// sits on the island's own level (D51), and a window under it would
    /// be hidden: there the lasers take the island's level and are
    /// ordered right under its panel.
    static func level(isDemo: Bool) -> NSWindow.Level {
        isDemo ? DemoWindowLevels.island : NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue - 1)
    }

    static func traits(isDemo: Bool) -> IslandLaserWindowTraits {
        IslandLaserWindowTraits(
            level: level(isDemo: isDemo),
            // Borderless and clear, and never the key window.
            styleMask: [.borderless, .nonactivatingPanel],
            // On every desktop Space, and it stays put when the desktop
            // is revealed. Not `fullScreenAuxiliary`: that is what would
            // put it over a full screen app.
            collectionBehavior: [.canJoinAllSpaces, .ignoresCycle, .stationary],
            ignoresMouseEvents: true,
            acceptsMouseMovedEvents: false,
            hasShadow: false,
            isOpaque: false,
            order: .below
        )
    }
}

/// Where the lasers' window goes and what it is, as plain values (D56).
///
/// The beams are far larger than the island. They get a window of their
/// own, and the island's panel stays the size it was: its layout and its
/// hit testing are untouched. The window exists only while the look is
/// Lasers and the pulse is what the island shows, which is only while the
/// tap is listening and has heard sound. It takes no click, ever.
struct IslandLaserWindowPlan: Equatable {
    /// The window's frame on the screen, in AppKit's bottom-up space.
    var frame: CGRect
    /// The closed island inside the window, in the window's own space.
    var notch: CGRect
    /// What kind of window it is.
    var traits: IslandLaserWindowTraits

    var level: NSWindow.Level { traits.level }

    /// The plan for the lasers' window, and nil when there is to be none:
    /// with the look on Glow, while the pulse is not what the island
    /// shows, or before the island is on a screen.
    ///
    /// `pill` is the closed island on its screen and `screen` that
    /// screen's frame, both in AppKit's space. The window holds the pill
    /// and every beam under it, the ones that lean and the curtains at
    /// their widest, and is cut to the island's own screen: the beams
    /// never reach onto the display beside it.
    ///
    /// `reach` is the lasers' own, 0 to 1. At its far end the beams cross
    /// the screen, and the window is the screen and never more than it.
    static func plan(
        look: IslandBeatLook,
        showsPulse: Bool,
        pill: CGRect?,
        screen: CGRect?,
        reach: Double,
        isDemo: Bool
    ) -> IslandLaserWindowPlan? {
        guard look == .lasers, showsPulse, let pill, let screen,
              pill.width > 0, pill.height > 0 else { return nil }
        let length = beamLength(reach: reach, pill: pill, screen: screen)
        let frame = IslandLaserRoom.rect(length: length, reach: reach, pill: pill, screen: screen).integral
        guard !frame.isNull, frame.width > 0, frame.height > 0 else { return nil }
        return IslandLaserWindowPlan(
            frame: frame,
            notch: pill.offsetBy(dx: -frame.minX, dy: -frame.minY),
            traits: .traits(isDemo: isDemo)
        )
    }
}

extension IslandLaserWindowPlan {
    /// A beam's full length for the lasers' reach on this screen.
    static func beamLength(reach: Double, pill: CGRect, screen: CGRect) -> Double {
        IslandLaserReach.length(reach: reach, farthest: IslandLaserReach.farthest(pill: pill, screen: screen))
    }
}

/// What the lasers are drawn on. The real one is a window. A test hands in
/// a fake, and no test shows a window.
@MainActor
protocol IslandLaserSurface: AnyObject {
    /// Puts the surface on screen as the plan says, with `layer` in it,
    /// under the window with that number. Calling it again moves it.
    func show(_ plan: IslandLaserWindowPlan, hosting layer: CALayer, below windowNumber: Int)
    /// Takes it off the screen and lets it go.
    func close()
}

/// The lasers' own window: borderless, clear, and blind to the mouse.
@MainActor
final class IslandLaserWindow: IslandLaserSurface {
    private var panel: NSPanel?

    func show(_ plan: IslandLaserWindowPlan, hosting layer: CALayer, below windowNumber: Int) {
        let traits = plan.traits
        let panel = panel ?? makePanel(traits)
        self.panel = panel
        if panel.level != traits.level { panel.level = traits.level }
        if panel.collectionBehavior != traits.collectionBehavior {
            panel.collectionBehavior = traits.collectionBehavior
        }
        if panel.frame != plan.frame { panel.setFrame(plan.frame, display: false) }
        if let host = panel.contentView?.layer, layer.superlayer !== host {
            layer.removeFromSuperlayer()
            host.addSublayer(layer)
        }
        // Under the island's panel when the two share a level, which is
        // the demo mode. Otherwise the level alone puts it under.
        panel.order(traits.order, relativeTo: windowNumber)
    }

    func close() {
        panel?.orderOut(nil)
        panel?.contentView?.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        panel = nil
    }

    private func makePanel(_ traits: IslandLaserWindowTraits) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: traits.styleMask, backing: .buffered, defer: true)
        panel.isReleasedWhenClosed = false
        // Not a floating panel: its level is the one the traits name.
        panel.isFloatingPanel = false
        panel.backgroundColor = .clear
        panel.isOpaque = traits.isOpaque
        panel.hasShadow = traits.hasShadow
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = traits.ignoresMouseEvents
        panel.acceptsMouseMovedEvents = traits.acceptsMouseMovedEvents
        panel.sharingType = .readOnly
        panel.level = traits.level
        panel.collectionBehavior = traits.collectionBehavior
        let content = NSView(frame: .zero)
        content.wantsLayer = true
        content.layer?.masksToBounds = false
        panel.contentView = content
        return panel
    }
}

/// The Lasers look of the beat (D56): the beams, the window they are in,
/// and the song's frames on their way to them.
///
/// The beams follow the glow's rule. A low hit shoots them out in the next
/// color and they come all the way back in about 140 ms. A snare with no
/// punch in flight snaps them to the next arrangement, another shape of
/// fan and the other way of facing, flat on the screen or out of it
/// toward the viewer, and shoots a shorter burst in the next color; one
/// that lands while a punch is coming back only flashes the faint glow
/// under the notch. A hat is a small flicker of that glow. Between hits
/// there are no beams. A fan that faces the viewer lunges on a low hit:
/// it starts a few degrees further forward and is back with its beams.
///
/// That is the Reactive mode. In the Show mode a director runs the song
/// (`IslandLaserDirector`): one look at a time in two colors, with the
/// beams on between hits, and a hit only moves what the look shows. The
/// stage hands it each frame and does what it asks.
///
/// The island's glow tells it when to exist. While the look is Lasers and
/// the pulse is what the island shows, the glow hands over where the
/// closed island is on its screen, and every frame after that. When either
/// stops, the window is closed and nothing of it is left.
@MainActor
final class IslandLaserStage {
    let layer = IslandLaserLayer()

    /// Makes the surface the beams are drawn on. A test hands in a fake.
    var makeSurface: () -> any IslandLaserSurface = { IslandLaserWindow() }
    /// The wall clock. A test hands in its own.
    var now: () -> CFTimeInterval = CACurrentMediaTime
    /// Whether the user asked macOS to dim flashing lights. A snare snaps
    /// the fan and steps its color, which is a flash, and with the setting
    /// on no second holds more than three of those.
    var flashingLights: any IslandFlashingLightsSetting = SystemFlashingLightsSetting.shared
    /// The demo mode's level rule (D51).
    var isDemo: () -> Bool = { DemoMode.isActive }

    /// What is on screen now, and nil while there are no lasers.
    private(set) var plan: IslandLaserWindowPlan?
    private var surface: (any IslandLaserSurface)?
    private var pulse: IslandHaloPulse?
    /// A beam's full length on the screen the lasers are on, in points.
    private(set) var beamLength: Double = 0
    /// The room the beams have on that screen.
    private var space = IslandLaserSpace(notchWidth: 0, left: 0, right: 0, down: 0)
    private var score = IslandLaserScore()
    private var flashTimes: [CFTimeInterval] = []
    /// Which color the fan is in. A low hit takes the next one.
    private(set) var hueIndex = 0
    private var punchEnds: CFTimeInterval = -.infinity
    private var flashEnds: CFTimeInterval = -.infinity
    /// The show of the song that is on, once there has been one. It is
    /// kept while the song is the same: when the lasers go away for a
    /// hover, a notice or an agent's flash and come back, the show goes
    /// on where it was.
    private(set) var director: IslandLaserDirector?
    /// The show's picture that is on, and nil while the show is dark.
    private(set) var picture: IslandLaserPicture?

    /// How long a show takes to go dark.
    static let darkFade: TimeInterval = 0.12

    /// How far a snare's burst goes, as a share of a full punch.
    static let snareBurst = 0.45
    /// The least a punch goes out, as a share of the full length.
    static let leastPunch = 0.3

    /// How far a fan that faces the viewer lunges for a low hit of this
    /// strength, in degrees. A flat fan does not lunge.
    static func lunge(tilt: Double, strength: Double) -> Double {
        guard tilt > 0, strength.isFinite else { return 0 }
        return IslandLaserTilt.lunge * min(max(strength, 0), 1)
    }

    var isShowing: Bool { plan != nil }

    /// Called by the island's glow whenever its state or its place may
    /// have changed. Shows, moves or closes the lasers as the plan says.
    func update(
        pulse: IslandHaloPulse?,
        pill: CGRect?,
        screen: CGRect?,
        contentsScale: CGFloat,
        islandWindowNumber: Int?
    ) {
        let wanted = pulse.flatMap {
            IslandLaserWindowPlan.plan(
                look: $0.look, showsPulse: true, pill: pill, screen: screen, reach: $0.laserReach, isDemo: isDemo()
            )
        }
        guard let pulse, let wanted, let islandWindowNumber else {
            close()
            return
        }
        let isNew = plan == nil
        guard wanted != plan || pulse != self.pulse else { return }
        let before = self.pulse
        plan = wanted
        self.pulse = pulse
        if let pill, let screen {
            beamLength = IslandLaserWindowPlan.beamLength(reach: pulse.laserReach, pill: pill, screen: screen)
            space = IslandLaserSpace(pill: pill, screen: screen)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.container.frame = CGRect(origin: .zero, size: wanted.frame.size)
        CATransaction.commit()
        layer.setContentsScale(contentsScale)
        layer.setBeamCount(pulse.laserCount)
        layer.layout(notch: wanted.notch, length: beamLength)

        let surface = surface ?? makeSurface()
        self.surface = surface
        surface.show(wanted, hosting: layer.container, below: islandWindowNumber)
        let isNewMode = isNew || before?.laserMode != pulse.laserMode
        guard pulse.laserMode == .reactive else {
            startShow(pulse: pulse, isNewMode: isNewMode)
            return
        }
        if isNewMode, picture != nil || layer.scene != nil {
            picture = nil
            layer.end(animated: false)
        }
        // What the show flashed counts against Reactive's own limit.
        if before?.laserMode == .show, let director {
            flashTimes = (flashTimes + director.flashLog).sorted()
        }
        // The fan at rest, with every beam back at the notch, until the
        // first hit.
        if isNewMode {
            var rest = score.fan(
                for: IslandBeatFrame(), reach: pulse.laserReach, tint: pulse.tint,
                count: pulse.laserCount, space: space, time: now(), fullLength: beamLength
            )
            rest.beams = rest.beams.map { beam in
                var back = beam
                back.length = 0
                back.brightness = 0
                return back
            }
            rest.haze = Double(IslandLaserLayer.restingHaze)
            layer.apply(rest)
        }
    }

    /// Takes the lasers and their window away.
    func close() {
        guard plan != nil || surface != nil else { return }
        layer.end(animated: false)
        surface?.close()
        surface = nil
        plan = nil
        pulse = nil
        // The director stays: the same song comes back to the same show.
        picture = nil
        punchEnds = -.infinity
        flashEnds = -.infinity
    }

    /// One frame of the song. Only a hit moves the beams, at once and with
    /// no rise. A hit that the flash rule turns away shows nothing.
    func follow(_ frame: IslandBeatFrame) {
        guard plan != nil, let pulse else { return }
        guard pulse.laserMode == .reactive else {
            followShow(frame, pulse: pulse)
            return
        }
        let time = now()
        let isPunching = time < punchEnds && time >= punchEnds - IslandBeatGlow.punchFall
        switch frame.hit {
        case .kick:
            guard mayFlash() else { return }
            hueIndex += 1
            punchEnds = time + IslandBeatGlow.punchFall
            flashEnds = punchEnds
            let strength = max(min(max(frame.low, 0), 1), Self.leastPunch)
            shoot(
                IslandBeatFrame(low: 1, mid: frame.mid, high: frame.high, hit: .kick),
                lengthShare: strength, lunges: true, over: IslandBeatGlow.punchFall, pulse: pulse, time: time
            )
        case .snare:
            guard mayFlash() else { return }
            flashEnds = max(flashEnds, time + IslandBeatGlow.flashFall)
            guard !isPunching else {
                // One color for a low hit's whole trip: only brightness.
                layer.flashHaze(to: 1, over: IslandBeatGlow.flashFall)
                return
            }
            hueIndex += 1
            shoot(
                IslandBeatFrame(low: 1, mid: frame.mid, high: frame.high, hit: .snare),
                lengthShare: Self.snareBurst, lunges: false, over: IslandBeatGlow.flashFall, pulse: pulse, time: time
            )
        case .hat:
            // A flicker at the notch, and nothing while a hit is fading.
            guard time >= flashEnds || time < flashEnds - IslandBeatGlow.punchFall else { return }
            let lift = IslandLaserLimits.hatCeiling * max(0.5, min(max(frame.high, 0), 1))
            layer.flashHaze(to: IslandLaserLayer.restingHaze + Float(lift), over: IslandBeatGlow.shimmerFall)
        case nil:
            break
        }
    }

    /// The beams for a hit, cut to `lengthShare` of their full length and
    /// in the stage's own color, out at once and back over `duration`. A
    /// low hit also lunges a fan that faces the viewer, as far as it was
    /// hard.
    private func shoot(
        _ frame: IslandBeatFrame,
        lengthShare: Double,
        lunges: Bool,
        over duration: TimeInterval,
        pulse: IslandHaloPulse,
        time: CFTimeInterval
    ) {
        var peak = score.fan(
            for: frame, reach: pulse.laserReach, tint: pulse.tint,
            count: pulse.laserCount, space: space, time: time, fullLength: beamLength
        )
        peak.beams = peak.beams.map { beam in
            var cut = beam
            cut.length = beam.length * lengthShare
            return cut
        }
        let hues = IslandBeatHues.hues(around: pulse.tint)
        peak.color = hues[hueIndex % hues.count]
        layer.shoot(
            peak, over: duration, lunge: lunges ? Self.lunge(tilt: peak.tilt, strength: lengthShare) : 0
        )
    }

    // MARK: The show

    /// Brings the show on for a pulse that asks for one. A new song has
    /// a show of its own, from the top. The same song keeps its show:
    /// the look, the colors and the place in the phrase it had.
    private func startShow(pulse: IslandHaloPulse, isNewMode: Bool) {
        guard let kept = director, kept.program.seed == pulse.laserSeed else {
            // The flashes of the last second count against the new
            // show's limit too, whoever made them.
            director = IslandLaserDirector(
                program: IslandLaserProgram(seed: pulse.laserSeed),
                flashLog: (director?.flashLog ?? []) + flashTimes
            )
            picture = nil
            layer.end(animated: false)
            return
        }
        if isNewMode {
            director?.carry(flashes: flashTimes)
            picture = kept.isDark ? nil : kept.picture
        }
        if let picture {
            // The picture that was on, in its place, size and colors now.
            layer.show(scene(for: picture, pulse: pulse))
        } else if isNewMode {
            layer.end(animated: false)
        }
    }

    /// One frame of the song for the director, and what it asks for.
    private func followShow(_ frame: IslandBeatFrame, pulse: IslandHaloPulse) {
        guard var director else { return }
        director.flashRule = IslandFlashRule.rule(dimsFlashingLights: flashingLights.dimsFlashingLights)
        let cues = director.follow(frame, at: now())
        self.director = director
        for cue in cues {
            perform(cue, pulse: pulse)
        }
    }

    private func perform(_ cue: IslandLaserCue, pulse: IslandHaloPulse) {
        switch cue {
        case let .show(picture):
            self.picture = picture
            layer.show(scene(for: picture, pulse: pulse))
        case let .push(picture, strength):
            self.picture = picture
            layer.push(
                scene(for: picture, pulse: pulse), by: IslandLaserShow.pushLength * strength,
                over: IslandLaserShow.pushFall
            )
        case let .flash(picture):
            self.picture = picture
            layer.flashWhite(into: scene(for: picture, pulse: pulse), over: IslandLaserShow.flashFall)
        case let .shimmer(strength):
            layer.shimmer(strength, over: IslandLaserShow.shimmerFall)
        case let .stir(picture):
            self.picture = picture
            layer.stir(scene(for: picture, pulse: pulse))
        case .dark:
            picture = nil
            layer.blackOut(over: Self.darkFade)
        case let .burst(picture):
            self.picture = nil
            layer.burst(
                scene(for: picture, pulse: pulse).burst, spread: IslandLaserShow.burstSpread,
                hold: IslandLaserShow.burstHold, fall: IslandLaserShow.burstFall
            )
        }
    }

    /// A picture as beams on this screen, in the colors around the art's.
    private func scene(for picture: IslandLaserPicture, pulse: IslandHaloPulse) -> IslandLaserScene {
        IslandLaserScene(
            picture: picture, hues: IslandBeatHues.hues(around: pulse.tint), count: pulse.laserCount,
            space: space, reach: pulse.laserReach, fullLength: beamLength
        )
    }

    private func mayFlash() -> Bool {
        let time = now()
        flashTimes.removeAll { time - $0 >= 1 || time < $0 }
        let rule = IslandFlashRule.rule(dimsFlashingLights: flashingLights.dimsFlashingLights)
        guard rule.allows(at: time, after: flashTimes) else { return false }
        flashTimes.append(time)
        return true
    }
}
