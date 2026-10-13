import SwiftUI

/// What the glow page's lights row reads from the app (D56): the switch
/// "Pulse with the beat" and the Look for the display in use, and what macOS
/// says about motion. A plain value, which lets the page be drawn from a
/// fixed one and tested without a sound device.
struct OnboardingBeatReading: Equatable, Sendable {
    /// This Mac can run the pulse (macOS 14.2 and later). Where it cannot,
    /// the page has no row about it, as Settings has no switch.
    var isAvailable = true
    /// The switch is on for the display in use. Flipping it is what makes
    /// the app listen to the Mac's sound, and macOS asks once.
    var isOn = false
    var look: IslandBeatLook = .glow
    /// The switch can act: the glow is on and the closed island shows music.
    /// Glow with music is not part of it. When that is the only thing off,
    /// the switch turns it on with the pulse (`needsGlowWithMusic`).
    var canPulse = true
    /// The glow is on, but Glow with music is off. Flipping the switch on
    /// then switches that on with the pulse, and the card says that.
    var needsGlowWithMusic = false
    /// The glow itself is off (Off in the strength cards on the same page),
    /// which is what leaves `canPulse` false. Otherwise it is the closed
    /// island showing no music.
    var glowIsOff = false
    /// macOS said no to hearing the Mac's sound: the tap did not start, or it
    /// heard nothing while music played (`IslandBeatProblem.cannotHear`).
    var cannotHear = false
    /// The lights may run right now: Low Power Mode and heat are not holding
    /// them back (`IslandBeatRules.allowsPulse`). Reduce Motion is the other
    /// thing that stops them, and has its own note.
    var canRunNow = true
    /// Reduce Motion is on, which turns the pulse off altogether.
    var reduceMotion = false
    /// "Dim flashing lights" is on, which holds the flashes to three a second.
    var dimsFlashingLights = false

    /// The summary lists the lights when the user switched them on and macOS
    /// did not refuse to let the app hear: lights that cannot run are not
    /// something the tour set up.
    var showsInSummary: Bool { isAvailable && isOn && !cannotHear }
}

extension OnboardingBeatReading {
    /// What the app's models say, in plain values. The display's preferences
    /// are for the display in use; the others are the system's own.
    init(
        display: NookDisplayPreferences,
        cannotHear: Bool,
        policy: IslandMotionPolicy,
        reduceMotion: Bool,
        dimsFlashingLights: Bool,
        isAvailable: Bool = IslandBeatSupport.isAvailable
    ) {
        let glowIsOff = display.haloStyle == .off
        let canPulse = !glowIsOff && display.mediaStyle != .off
        self.init(
            isAvailable: isAvailable,
            isOn: display.haloPulsesWithBeat,
            look: display.haloBeatLook,
            canPulse: canPulse,
            needsGlowWithMusic: canPulse && !display.haloFollowsMusic,
            glowIsOff: glowIsOff,
            cannotHear: cannotHear,
            canRunNow: IslandBeatRules.allowsPulse(policy),
            reduceMotion: reduceMotion,
            dimsFlashingLights: dimsFlashingLights
        )
    }
}

/// The lights on the glow page: the switch "Pulse with the beat", the two
/// looks as pictures of a made-up beat, and the notes that say what macOS
/// asks and what a setting of its own does to the lights. Nothing here
/// listens to the Mac's sound unless the switch is flipped.
struct OnboardingLightsRow: View {
    let context: OnboardingPageContext

    private var beat: OnboardingBeatReading { context.state.beat }

    private static let cardHeight: CGFloat = 74

    var body: some View {
        if beat.isAvailable {
            VStack(spacing: 6) {
                HStack(alignment: .top, spacing: 10) {
                    switchCard
                    ForEach(IslandBeatLook.allCases) { look in lookCard(look) }
                }
                VStack(spacing: 3) {
                    ForEach(Self.noteKeys(for: beat), id: \.self) { note($0) }
                }
            }
        }
    }

    /// Settings' caption for macOS saying no to hearing the Mac's sound.
    static let cannotHearKey = "settings.appearance.nook.halo.beat.cannotHear"

    /// The notes under the row, at most two, which keeps the page its room. The
    /// first says what stops the lights or, with nothing stopping them, what
    /// macOS asks, and once macOS has refused it is Settings' caption for
    /// that. A second says what is holding the lights back at the moment: Low
    /// Power Mode or heat, or with neither, "Dim flashing lights". Reduce
    /// Motion stops the lights altogether, which leaves nothing to add.
    static func noteKeys(for beat: OnboardingBeatReading) -> [String] {
        guard beat.isAvailable else { return [] }
        if beat.reduceMotion { return ["onboarding.look.beat.reduceMotion"] }
        if !beat.canPulse {
            return [beat.glowIsOff ? "onboarding.look.beat.needsGlow" : "onboarding.look.beat.needsMusic"]
        }
        var keys = [beat.cannotHear ? cannotHearKey : "onboarding.look.beat.note"]
        if !beat.canRunNow {
            keys.append("onboarding.look.beat.held")
        } else if beat.dimsFlashingLights {
            keys.append("onboarding.look.beat.dimFlashing")
        }
        return keys
    }

    /// The card's line under the switch's name. While Glow with music is off,
    /// it says that switching the pulse on switches that on too.
    private var switchLine: String {
        guard beat.needsGlowWithMusic else { return context.t("onboarding.look.beat.text") }
        return context.lang.t(
            "onboarding.look.beat.text.withMusic",
            context.t("settings.appearance.nook.halo.music.title")
        )
    }

    private func note(_ key: String) -> some View {
        Text(context.t(key))
            .font(.system(size: 11))
            .foregroundStyle(OnboardingStyle.faintText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The switch, as a card the way the swipe switch is on the opening page.
    private var switchCard: some View {
        let title = context.t("settings.appearance.nook.halo.beat.title")
        return OnboardingChoiceCard(isSelected: beat.isOn, showsTick: false) {
            context.actions.setBeatPulse(!beat.isOn)
        } content: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(OnboardingStyle.primaryText)
                    Text(switchLine)
                        .font(.system(size: 11.5))
                        .foregroundStyle(OnboardingStyle.secondaryText)
                        .lineSpacing(1.5)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                OnboardingSwitchArt(isOn: beat.isOn)
            }
            .padding(.horizontal, 14)
            .frame(maxHeight: .infinity)
        }
        .frame(height: Self.cardHeight)
        .disabled(!beat.canPulse)
        .opacity(beat.canPulse ? 1 : 0.45)
        .accessibilityLabel(title)
        .accessibilityValue(context.t(beat.isOn ? "onboarding.opening.swipe.on" : "onboarding.opening.swipe.off"))
    }

    /// One look, drawn playing a made-up beat. A pick writes the look for the
    /// display, which takes effect while the pulse is on.
    private func lookCard(_ look: IslandBeatLook) -> some View {
        let title = context.t(look.titleKey)
        return OnboardingChoiceCard(isSelected: beat.look == look, showsTick: false) {
            context.actions.setBeatLook(look)
        } content: {
            VStack(spacing: 0) {
                OnboardingBeatPicture(
                    look: look,
                    restartKey: beat.isOn ? 1 : 0,
                    reduceMotion: beat.reduceMotion,
                    dimsFlashingLights: beat.dimsFlashingLights
                )
                    .scaleEffect(0.52, anchor: .top)
                    .frame(width: 100, height: 48, alignment: .top)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OnboardingStyle.primaryText)
                    .padding(.top, 2)
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
        }
        .frame(width: 126, height: Self.cardHeight)
        .accessibilityLabel(title)
    }
}
