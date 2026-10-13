import SwiftUI

// MARK: - The long tour's pages

/// One feature the main tour does not teach, as a page (`OnboardingMore`):
/// a title, a line that says what it does, a picture, its switches, and a line
/// that says where it lives in Settings. A feature that is a plain setting has
/// its switch here, read from the app and written through the door Settings
/// uses. A feature that needs setup has a button that opens its tab of
/// Settings. Nothing is switched on by the page: a switch is the user's flip,
/// and macOS is asked only by the flip that needs it (the volume keys).
struct OnboardingMorePage: View {
    let page: OnboardingPage
    let context: OnboardingPageContext

    private static let pictureSize = CGSize(width: 600, height: 236)
    /// A page with controls keeps the picture short, which leaves them room.
    private static let compactPictureHeight: CGFloat = 112
    private static let controlWidth: CGFloat = 640

    var body: some View {
        if let more = page.more {
            OnboardingPageScaffold(
                page: page,
                context: context,
                title: context.t(more.titleKey),
                text: context.t(more.textKey),
                footnote: more.hasNote ? context.t(more.noteKey) : nil,
                gap: 30
            ) {
                VStack(spacing: more.hasControls ? 12 : 20) {
                    picture(more)
                    if more == .lights {
                        OnboardingLightsRow(context: context)
                            .frame(maxWidth: Self.controlWidth)
                    }
                    ForEach(more.switches) { item in
                        OnboardingMoreSwitchRow(context: context, item: item)
                            .frame(maxWidth: Self.controlWidth)
                    }
                    whereLine(more)
                    if more.opensSettings {
                        Button(context.t("onboarding.more.showSettings")) {
                            context.actions.showAllAgents()
                        }
                        .buttonStyle(OnboardingSecondaryButtonStyle())
                    }
                    if let tab = more.settingsTab {
                        Button(context.t("onboarding.more.showSettings")) {
                            context.actions.openSettings(tab)
                        }
                        .buttonStyle(OnboardingSecondaryButtonStyle())
                    }
                }
            }
        }
    }

    /// The charger notice is drawn on the closed island. The others stand on
    /// their symbol.
    @ViewBuilder
    private func picture(_ more: OnboardingMore) -> some View {
        ZStack {
            OnboardingCardBackground()
            switch more {
            case .lights:
                OnboardingBeatPicture(
                    look: .lasers,
                    reduceMotion: context.state.beat.reduceMotion,
                    dimsFlashingLights: context.state.beat.dimsFlashingLights
                )
                    .frame(width: 240, height: 100, alignment: .center)
            case .power:
                OnboardingScreenArt(marks: 1) {
                    OnboardingPillArt(
                        width: 150,
                        height: 28,
                        glow: OnboardingStyle.finished,
                        glowStrength: 0.6,
                        left: .nothing,
                        right: .battery
                    )
                    .padding(.top, 3)
                }
                .scaleEffect(0.75)
                .frame(width: 195, height: 105)
            default:
                OnboardingSymbolPlate(symbol: more.symbol, size: 88)
            }
        }
        .frame(
            width: Self.pictureSize.width,
            height: more.hasControls ? Self.compactPictureHeight : Self.pictureSize.height
        )
    }

    /// Where the feature is turned on, in the words the integrations page
    /// uses for a place in Settings.
    private func whereLine(_ more: OnboardingMore) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: "gearshape")
                .font(.system(size: 11, weight: .semibold))
            Text(context.t(more.whereKey))
                .font(.system(size: 13, weight: .medium))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(OnboardingStyle.primaryText.opacity(0.85))
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .accessibilityElement(children: .combine)
    }
}
