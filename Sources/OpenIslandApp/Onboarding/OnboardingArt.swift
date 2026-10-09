import SwiftUI

/// Sizes and colors the welcome tour shares. Everything in the tour is
/// plain SwiftUI: shapes, text and buttons with their own style. No AppKit
/// control is used, which lets `ImageRenderer` draw every page for the
/// snapshots.
enum OnboardingStyle {
    static let windowSize = CGSize(width: 860, height: 560)
    static let sidePadding: CGFloat = 30
    static let textWidth: CGFloat = 560
    static let cardCornerRadius: CGFloat = 14

    static let ink = V6Palette.ink
    static let paper = V6Palette.paper
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.62)
    static let faintText = Color.white.opacity(0.42)
    static let cardFill = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.1)
    static let selectedFill = Color.white.opacity(0.11)

    /// The colors the glow starts with: waiting for approval, finished and
    /// working. Only the pictures in the tour use these.
    static let waiting = Color(red: 231 / 255, green: 167 / 255, blue: 98 / 255)
    static let finished = Color(red: 111 / 255, green: 185 / 255, blue: 130 / 255)
    static let working = Color(red: 110 / 255, green: 167 / 255, blue: 255 / 255)
}

/// The closed island as a picture: a black pill with activity bars on the
/// left, a count on the right and a glow under it.
struct OnboardingPillArt: View {
    var width: CGFloat = 220
    var height: CGFloat = 34
    var glow: Color? = OnboardingStyle.waiting
    /// 0 to 1. How strong the glow is drawn.
    var glowStrength: Double = 0.7
    var showsContent = true

    var body: some View {
        HStack(spacing: 0) {
            if showsContent {
                OnboardingBarsArt(color: glow ?? OnboardingStyle.paper.opacity(0.8))
                    .frame(width: height * 0.5, height: height * 0.42)
                Spacer(minLength: 0)
                Text("×3")
                    .font(.system(size: height * 0.34, weight: .semibold, design: .monospaced))
                    .foregroundStyle(OnboardingStyle.paper.opacity(0.8))
            }
        }
        .padding(.horizontal, height * 0.4)
        .frame(width: width, height: height)
        .background(Capsule().fill(Color.black))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        .background {
            if let glow {
                Capsule()
                    .fill(glow.opacity(glowStrength))
                    .frame(width: width * 0.94, height: height * 0.9)
                    .blur(radius: height * (0.3 + 0.35 * glowStrength))
                    .offset(y: height * 0.16)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Three activity bars, still.
struct OnboardingBarsArt: View {
    var color: Color
    private static let levels: [CGFloat] = [0.5, 1, 0.7]

    var body: some View {
        GeometryReader { proxy in
            let gap = proxy.size.width * 0.16
            let barWidth = (proxy.size.width - gap * 2) / 3
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(Self.levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth, height: proxy.size.height * level)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
        }
    }
}

/// The top of a screen with its menu bar and the island in the notch. The
/// first page's picture.
struct OnboardingScreenArt: View {
    var glow: Color? = OnboardingStyle.waiting
    var glowStrength: Double = 0.75
    /// False draws the island without the activity bars and the count,
    /// which are an agent's.
    var showsContent = true

    private static let cornerRadius: CGFloat = 22
    private static let menuBarHeight: CGFloat = 38

    var body: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(
                topLeadingRadius: Self.cornerRadius,
                topTrailingRadius: Self.cornerRadius,
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.1), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: Self.cornerRadius,
                    topTrailingRadius: Self.cornerRadius,
                    style: .continuous
                )
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom))
            )

            menuBar
            OnboardingPillArt(
                width: 250,
                height: Self.menuBarHeight - 4,
                glow: glow,
                glowStrength: glowStrength,
                showsContent: showsContent
            )
        }
        .accessibilityHidden(true)
    }

    /// Menu titles on the left and status items on the right, as blank marks.
    private var menuBar: some View {
        HStack(spacing: 10) {
            ForEach(Array([14.0, 38, 26, 30].enumerated()), id: \.offset) { _, width in
                Capsule().fill(Color.white.opacity(0.22)).frame(width: width, height: 6)
            }
            Spacer(minLength: 0)
            ForEach(Array([12.0, 12, 18, 34].enumerated()), id: \.offset) { _, width in
                Capsule().fill(Color.white.opacity(0.22)).frame(width: width, height: 6)
            }
        }
        .padding(.horizontal, 22)
        .frame(height: Self.menuBarHeight)
    }
}

/// One key of a shortcut, with the word that is printed on the key.
struct OnboardingKeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(OnboardingStyle.primaryText)
            .padding(.horizontal, 7)
            .frame(minWidth: 24, minHeight: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
            )
    }
}

/// A shortcut as a row of key caps.
struct OnboardingKeyCaps: View {
    let caps: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                OnboardingKeyCap(label: cap)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caps.joined(separator: " "))
    }
}

/// The filled button that moves the tour on.
struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(OnboardingStyle.ink)
            .padding(.horizontal, 18)
            .frame(height: 34)
            .background(Capsule().fill(OnboardingStyle.paper.opacity(configuration.isPressed ? 0.8 : 1)))
            .contentShape(Capsule())
    }
}

/// The quiet button beside it: Back, and the small actions on a page.
struct OnboardingSecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 34

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(OnboardingStyle.primaryText)
            .padding(.horizontal, 16)
            .frame(height: height)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.16 : 0.1)))
            .contentShape(Capsule())
    }
}

/// A card the user picks one of. The picked one carries a ring and a tick.
struct OnboardingChoiceCard<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: OnboardingStyle.cardCornerRadius, style: .continuous)
                        .fill(isSelected ? OnboardingStyle.selectedFill : OnboardingStyle.cardFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OnboardingStyle.cardCornerRadius, style: .continuous)
                        .strokeBorder(
                            isSelected ? OnboardingStyle.paper.opacity(0.9) : OnboardingStyle.cardStroke,
                            lineWidth: isSelected ? 1.5 : 1
                        )
                )
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(OnboardingStyle.paper)
                            .padding(9)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: OnboardingStyle.cardCornerRadius, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
