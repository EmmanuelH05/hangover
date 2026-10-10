import SwiftUI

/// Sizes and colors the welcome tour shares. Everything in the tour is
/// plain SwiftUI: shapes, text and buttons with their own style. No AppKit
/// control is used, which lets `ImageRenderer` draw every page for the
/// snapshots.
enum OnboardingStyle {
    /// Grown from 860 by 560 (D43): every choice page now carries a preview
    /// next to its choices.
    static let windowSize = CGSize(width: 900, height: 640)
    static let sidePadding: CGFloat = 32
    /// The side padding of the narrow window a live page is in (D44).
    static let compactSidePadding: CGFloat = 20
    static let textWidth: CGFloat = 620
    static let cardCornerRadius: CGFloat = 14
    /// Width a page's content has between the side paddings.
    static var contentWidth: CGFloat { windowSize.width - sidePadding * 2 }

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
    /// The album color the pictures use where music is playing.
    static let album = Color(red: 255 / 255, green: 92 / 255, blue: 138 / 255)
}

/// What one side of the drawn island shows.
enum OnboardingPillSide: Equatable, Sendable {
    case nothing
    /// The activity bars.
    case bars
    /// The count of agent sessions.
    case count
    /// One dot for each agent.
    case agents
    case date
    case battery
    /// The time left until the next event.
    case countdown
    /// The temperature over a weather symbol.
    case weather
    /// The time left on the focus timer.
    case timer
    /// A check mark and the open tasks.
    case todos
    /// One tile for each agent session.
    case grid
    /// The album art of what is playing.
    case art
}

/// The closed island as a picture: a black pill with something on each
/// side and a glow under it.
struct OnboardingPillArt: View {
    var width: CGFloat = 220
    var height: CGFloat = 34
    var glow: Color? = OnboardingStyle.waiting
    /// 0 to 1. How strong the glow is drawn.
    var glowStrength: Double = 0.7
    var left: OnboardingPillSide = .bars
    var right: OnboardingPillSide = .count

    /// The sides a pill shows where the page does not ask about them:
    /// agents with the switch on, music with it off.
    static func sides(agentsEnabled: Bool) -> (left: OnboardingPillSide, right: OnboardingPillSide) {
        agentsEnabled ? (.bars, .count) : (.art, .nothing)
    }

    var body: some View {
        HStack(spacing: 0) {
            OnboardingPillSideArt(side: left, height: height, tint: glow)
            Spacer(minLength: 0)
            OnboardingPillSideArt(side: right, height: height, tint: glow)
        }
        .padding(.horizontal, height * 0.36)
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

/// One side of the drawn pill, sized from the pill's height.
struct OnboardingPillSideArt: View {
    let side: OnboardingPillSide
    let height: CGFloat
    var tint: Color?

    private static let dotColors: [Color] = [.orange, OnboardingStyle.working, OnboardingStyle.finished]

    var body: some View {
        switch side {
        case .nothing:
            Color.clear.frame(width: 1, height: 1)
        case .bars:
            OnboardingBarsArt(color: tint ?? OnboardingStyle.paper.opacity(0.8))
                .frame(width: height * 0.5, height: height * 0.42)
        case .count:
            Text("×3")
                .font(.system(size: height * 0.34, weight: .semibold, design: .monospaced))
                .foregroundStyle(OnboardingStyle.paper.opacity(0.8))
        case .agents:
            HStack(spacing: height * 0.09) {
                ForEach(Array(Self.dotColors.enumerated()), id: \.offset) { _, color in
                    Circle().fill(color).frame(width: height * 0.2, height: height * 0.2)
                }
            }
        case .date:
            VStack(spacing: 0) {
                Rectangle().fill(Color.red).frame(height: height * 0.14)
                Text("14")
                    .font(.system(size: height * 0.3, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: height * 0.56, height: height * 0.56)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: height * 0.13, style: .continuous))
        case .battery:
            Text("82")
                .font(.system(size: height * 0.34, weight: .bold, design: .monospaced))
                .foregroundStyle(OnboardingStyle.paper)
        case .countdown:
            Text("12m")
                .font(.system(size: height * 0.32, weight: .semibold, design: .monospaced))
                .foregroundStyle(OnboardingStyle.paper.opacity(0.85))
        case .weather:
            stacked(symbol: "cloud.sun.fill", text: "72°", tint: OnboardingStyle.paper)
        case .timer:
            stacked(symbol: "timer", text: "24m", tint: .orange)
        case .todos:
            stacked(symbol: "checkmark.circle", text: "5", tint: OnboardingStyle.paper)
        case .grid:
            // Two rows of tiles, which tells it from the single row of dots.
            let colors = Self.dotColors + [Color.white.opacity(0.22)]
            VStack(spacing: height * 0.06) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: height * 0.06) {
                        ForEach(0..<2, id: \.self) { column in
                            RoundedRectangle(cornerRadius: height * 0.05, style: .continuous)
                                .fill(colors[row * 2 + column])
                                .frame(width: height * 0.2, height: height * 0.2)
                        }
                    }
                }
            }
        case .art:
            RoundedRectangle(cornerRadius: height * 0.14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [OnboardingStyle.album, Color.purple.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: height * 0.56, height: height * 0.56)
        }
    }
}

extension OnboardingPillSideArt {
    /// A small symbol over a short text, as the pill draws weather, the
    /// timer and the to-dos.
    private func stacked(symbol: String, text: String, tint: Color) -> some View {
        VStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: height * 0.3, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: height * 0.32, weight: .bold, design: .rounded))
                .foregroundStyle(OnboardingStyle.paper.opacity(0.9))
        }
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

/// The top of a screen with its menu bar, and whatever hangs from the
/// middle of its top edge: the closed island or the opened one. The stage
/// every preview in the tour stands on.
struct OnboardingScreenArt<Island: View>: View {
    var menuBarHeight: CGFloat = 30
    var cornerRadius: CGFloat = 18
    /// How many marks the menu bar draws on each side, counted from the
    /// screen's edge. A wide island leaves room for fewer.
    var marks = 4
    /// True draws the whole screen as a framed plate, for a tall island
    /// that reaches the bottom of the picture. False draws the top of a
    /// screen that fades out below.
    var isFramed = false
    @ViewBuilder var island: () -> Island

    var body: some View {
        ZStack(alignment: .top) {
            shape
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.1), Color.white.opacity(isFramed ? 0.05 : 0.015)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    shape
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                        .mask(
                            LinearGradient(
                                colors: [.white, isFramed ? .white.opacity(0.6) : .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )

            menuBar
            island()
        }
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: cornerRadius,
            bottomLeadingRadius: isFramed ? cornerRadius : 0,
            bottomTrailingRadius: isFramed ? cornerRadius : 0,
            topTrailingRadius: cornerRadius,
            style: .continuous
        )
    }

    /// Menu titles on the left and status items on the right, as blank marks.
    private var menuBar: some View {
        HStack(spacing: 8) {
            ForEach(Array([10.0, 26, 18, 22].prefix(marks).enumerated()), id: \.offset) { _, width in
                Capsule().fill(Color.white.opacity(0.2)).frame(width: width, height: 5)
            }
            Spacer(minLength: 0)
            ForEach(Array([9.0, 9, 14, 24].suffix(marks).enumerated()), id: \.offset) { _, width in
                Capsule().fill(Color.white.opacity(0.2)).frame(width: width, height: 5)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: menuBarHeight)
    }
}

/// The opened island as a small drawing: the black shape that drops from
/// the top of the screen, its buttons, an agent's request when asked for,
/// and a tile for each widget. Used where the picture is small. The pages
/// that ask about widgets draw the real sample cards.
struct OnboardingOpenedArt: View {
    var width: CGFloat = 200
    var widgets: [NookWidgetKind] = [.media, .calendar, .todo, .notes]
    /// Draws an agent's request above the widgets.
    var showsAgentCard = false

    private static let tileHeight: CGFloat = 30
    private static let gap: CGFloat = 5

    var body: some View {
        VStack(spacing: Self.gap) {
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(Color.white.opacity(0.16)).frame(width: 7, height: 7)
                }
            }
            .frame(height: 12)

            if showsAgentCard { agentCard }

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: Self.gap) {
                    ForEach(row, id: \.self) { kind in tile(kind) }
                    if row.count == 1 { Color.clear.frame(height: Self.tileHeight) }
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.top, 4)
        .padding(.bottom, 9)
        .frame(width: width)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16, style: .continuous)
                .fill(Color.black)
        )
        .overlay(
            UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .accessibilityHidden(true)
    }

    /// Two tiles a row.
    private var rows: [[NookWidgetKind]] {
        stride(from: 0, to: widgets.count, by: 2).map { Array(widgets[$0..<min($0 + 2, widgets.count)]) }
    }

    private func tile(_ kind: NookWidgetKind) -> some View {
        HStack(spacing: 5) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.8))
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 3) {
                Capsule().fill(Color.white.opacity(0.32)).frame(width: 34, height: 3.5)
                Capsule().fill(Color.white.opacity(0.16)).frame(width: 22, height: 3.5)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity)
        .frame(height: Self.tileHeight)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.09)))
    }

    /// An agent asking for an OK: its dot, what it asks and two buttons.
    private var agentCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle().fill(OnboardingStyle.waiting).frame(width: 6, height: 6)
                Capsule().fill(Color.white.opacity(0.4)).frame(width: 46, height: 3.5)
                Capsule().fill(Color.white.opacity(0.18)).frame(width: 30, height: 3.5)
                Spacer(minLength: 0)
            }
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 12)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(OnboardingStyle.paper)
                    .frame(height: 12)
            }
        }
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(OnboardingStyle.waiting.opacity(0.5), lineWidth: 0.8)
        )
    }
}

/// Draws content laid out at its real size, made smaller to fit a box.
/// The widget page's sample cards are built at the island's real size,
/// which is wider than any picture in the tour.
struct OnboardingScaledPreview<Content: View>: View {
    /// The size the content lays itself out at.
    let natural: CGSize
    /// The room the picture has.
    let box: CGSize
    @ViewBuilder var content: () -> Content

    /// Never made larger than life.
    static func scale(natural: CGSize, box: CGSize) -> CGFloat {
        guard natural.width > 0, natural.height > 0 else { return 1 }
        return min(box.width / natural.width, box.height / natural.height, 1)
    }

    var body: some View {
        let scale = Self.scale(natural: natural, box: box)
        content()
            .frame(width: natural.width, height: natural.height, alignment: .top)
            .scaleEffect(scale, anchor: .top)
            .frame(width: natural.width * scale, height: natural.height * scale, alignment: .top)
            .accessibilityHidden(true)
    }
}

/// The opened island on its widget page, with the app's own sample cards,
/// hanging from the top of a drawn screen and made smaller to fit. With
/// `showsScreen` false the island stands alone and fills the picture.
struct OnboardingNookPreview: View {
    let placements: [NookWidgetPlacement]
    let calendarStyle: NookCalendarStyle
    let profile: IslandAppearanceDisplayProfile
    var look: IslandOpenedLook = .standard
    let emptyTitle: String
    /// The whole picture: the screen and the island in it.
    let size: CGSize
    var showsScreen = true

    private static let menuBarHeight: CGFloat = 22
    /// Room kept at each side of the island, which leaves the screen it
    /// hangs from in the picture.
    private static let sideMargin: CGFloat = 44
    private static let bottomMargin: CGFloat = 18

    /// The size the island's page is laid out at before it is made smaller.
    static func naturalSize(
        placements: [NookWidgetPlacement],
        calendarStyle: NookCalendarStyle,
        profile: IslandAppearanceDisplayProfile,
        look: IslandOpenedLook
    ) -> CGSize {
        let width = min(IslandOpenedMetrics.resolve(look: look, profile: profile).panelWidth, PreviewNookPanel.maxWidth)
        let page = NookPanelView.preferredHeight(for: placements, calendarStyle: calendarStyle, isEditing: false)
        return CGSize(width: width, height: PreviewNookPanel.headHeight + page + PreviewNookPanel.footHeight)
    }

    var body: some View {
        let natural = Self.naturalSize(
            placements: placements, calendarStyle: calendarStyle, profile: profile, look: look
        )
        if showsScreen {
            OnboardingScreenArt(menuBarHeight: Self.menuBarHeight, marks: 1, isFramed: true) {
                island(natural: natural, box: CGSize(
                    width: size.width - Self.sideMargin * 2,
                    height: size.height - Self.bottomMargin
                ))
            }
            .frame(width: size.width, height: size.height)
        } else {
            island(natural: natural, box: size)
                .frame(width: size.width, height: size.height, alignment: .top)
        }
    }

    private func island(natural: CGSize, box: CGSize) -> some View {
        OnboardingScaledPreview(natural: natural, box: box) {
            PreviewNookPanel(
                placements: placements,
                calendarStyle: calendarStyle,
                profile: profile,
                look: look,
                showsAgentsBar: false,
                emptyTitle: emptyTitle
            )
        }
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

/// A card the user picks one of. The picked one carries a ring and a tick,
/// unless the card draws its own tick (`showsTick` false).
struct OnboardingChoiceCard<Content: View>: View {
    let isSelected: Bool
    var showsTick = true
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
                    if isSelected, showsTick {
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

/// A switch drawn in SwiftUI: a track and a knob that slides. A system
/// switch would come out blank in a snapshot.
struct OnboardingSwitchArt: View {
    let isOn: Bool

    private static let size = CGSize(width: 38, height: 22)
    private static let knobInset: CGFloat = 3

    var body: some View {
        Capsule()
            .fill(isOn ? OnboardingStyle.finished : Color.white.opacity(0.16))
            .frame(width: Self.size.width, height: Self.size.height)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .padding(Self.knobInset)
            }
            .accessibilityHidden(true)
    }
}
