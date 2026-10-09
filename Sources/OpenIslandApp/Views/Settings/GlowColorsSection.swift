import SwiftUI

/// The color part of "05 · Status glow": the themes, one color for
/// everything, a color per moment and the reset (D31).
///
/// The body reads only the edited display's glow colors and hands them to
/// an equatable editor, which keeps a tap elsewhere in the pane from
/// re-rendering the color wells.
struct GlowColorsSection: View {
    let nook: NookModel
    let profile: IslandAppearanceDisplayProfile
    /// False leaves out the moments that are an agent's: approval,
    /// question, finished and working (D41).
    var showsAgents = true

    var body: some View {
        let preferences = nook.displayPreferences(for: profile)
        GlowColorsEditor(
            nook: nook,
            profile: profile,
            colors: preferences.haloColors,
            isGlowOn: preferences.haloStyle != .off,
            showsAgents: showsAgents
        )
        .equatable()
    }
}

extension IslandHaloMoment {
    /// True for a moment only an agent brings about.
    var needsAgents: Bool {
        switch self {
        case .approval, .question, .completed, .running: true
        case .notice, .music: false
        }
    }

    /// The moments Settings lists a color for.
    static func shown(agentsEnabled: Bool) -> [IslandHaloMoment] {
        agentsEnabled ? allCases : allCases.filter { !$0.needsAgents }
    }
}

private struct GlowColorsEditor: View, Equatable {
    let nook: NookModel
    let profile: IslandAppearanceDisplayProfile
    let colors: IslandHaloColors
    let isGlowOn: Bool
    let showsAgents: Bool

    private var lang: LanguageManager { .shared }

    nonisolated static func == (lhs: GlowColorsEditor, rhs: GlowColorsEditor) -> Bool {
        lhs.nook === rhs.nook && lhs.profile == rhs.profile && lhs.colors == rhs.colors
            && lhs.isGlowOn == rhs.isGlowOn && lhs.showsAgents == rhs.showsAgents
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlowThemeGrid(
                selectedID: colors.usesSingleColor ? nil : IslandHaloTheme.matching(colors.palette)?.id,
                title: { lang.t($0.titleKey) },
                pick: { theme in
                    update(animated: true) {
                        $0.palette = theme.palette
                        $0.usesSingleColor = false
                    }
                }
            )

            PersonalizationToggleRow(
                title: lang.t("settings.appearance.nook.halo.single.title"),
                note: lang.t("settings.appearance.nook.halo.single.note"),
                isOn: Binding(
                    get: { colors.usesSingleColor },
                    set: { isOn in update(animated: true) { $0.usesSingleColor = isOn } }
                )
            )

            if colors.usesSingleColor {
                singleColorRow
            } else {
                momentRows
            }

            MonoChip(title: lang.t("settings.appearance.nook.halo.reset"), selected: false) {
                update(animated: true) { $0 = .standard }
            }
            .disabled(colors == .standard)
            .opacity(colors == .standard ? 0.45 : 1)
        }
        .allowsHitTesting(isGlowOn)
        .disabled(!isGlowOn)
        .opacity(isGlowOn ? 1 : 0.45)
        .motionAnimation(Motion.toggleEnable, value: isGlowOn)
    }

    // MARK: One color

    private var singleColorRow: some View {
        GlowRowCard {
            HStack(spacing: 10) {
                GlowColorWell(
                    title: lang.t("settings.appearance.nook.halo.single.title"),
                    color: colors.singleColor,
                    set: { color in update(animated: false) { $0.singleColor = color } }
                )
                Text(lang.t("settings.appearance.nook.halo.single.color"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.88))
                Spacer(minLength: 8)
                HStack(spacing: 7) {
                    ForEach(IslandHaloColors.singleColorSuggestions, id: \.self) { suggestion in
                        GlowSwatchButton(color: suggestion, selected: colors.singleColor == suggestion) {
                            update(animated: true) { $0.singleColor = suggestion }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: A color per moment

    private var momentRows: some View {
        let moments = IslandHaloMoment.shown(agentsEnabled: showsAgents)
        return GlowRowCard {
            VStack(spacing: 0) {
                ForEach(moments) { moment in
                    if moment != moments.first {
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 1)
                    }
                    momentRow(moment)
                }
            }
        }
    }

    private func momentRow(_ moment: IslandHaloMoment) -> some View {
        let follows = followsItsSource(moment)
        return HStack(spacing: 10) {
            GlowColorWell(
                title: lang.t(Self.titleKey(for: moment)),
                color: colors.palette.color(for: moment) ?? Self.suggestion(for: moment),
                set: { color in update(animated: false) { $0.palette.setColor(color, for: moment) } }
            )
            .disabled(follows)
            .opacity(follows ? 0.35 : 1)
            Text(lang.t(Self.titleKey(for: moment)))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.88))
            Spacer(minLength: 8)
            if let key = Self.sourceToggleKey(for: moment) {
                Toggle(lang.t(key), isOn: Binding(
                    get: { follows },
                    set: { isOn in update(animated: true) { Self.setFollowsSource(isOn, moment: moment, in: &$0.palette) } }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    /// A notice that keeps the color it comes with, or music that takes the
    /// album art's. The other moments always use their own color.
    private func followsItsSource(_ moment: IslandHaloMoment) -> Bool {
        switch moment {
        case .notice: colors.palette.notice == nil
        case .music: colors.palette.musicUsesArtwork
        default: false
        }
    }

    private static func setFollowsSource(_ follows: Bool, moment: IslandHaloMoment, in palette: inout IslandHaloPalette) {
        palette.setFollowsSource(follows, for: moment)
    }

    private static func suggestion(for moment: IslandHaloMoment) -> IslandHaloRGB {
        moment == .music ? IslandHaloPalette.suggestedMusic : IslandHaloPalette.suggestedNotice
    }

    private static func titleKey(for moment: IslandHaloMoment) -> String {
        "settings.appearance.nook.halo.moment.\(moment.rawValue)"
    }

    private static func sourceToggleKey(for moment: IslandHaloMoment) -> String? {
        switch moment {
        case .notice: "settings.appearance.nook.halo.notice.own"
        case .music: "settings.appearance.nook.halo.music.artwork"
        default: nil
        }
    }

    // MARK: Writing

    /// A drag in the color panel writes many times a second, which is why
    /// a color well writes without an animation and a tap writes with one.
    private func update(animated: Bool, _ change: (inout IslandHaloColors) -> Void) {
        if animated {
            withMotion(Motion.selection) {
                nook.updateDisplayPreferences(for: profile) { change(&$0.haloColors) }
            }
        } else {
            nook.updateDisplayPreferences(for: profile) { change(&$0.haloColors) }
        }
    }
}

// MARK: - Pieces

/// The theme cards. The grid owns the selection ring's namespace, which
/// lets the ring slide between themes and never jump to another row of
/// cards in the pane.
struct GlowThemeGrid: View {
    let selectedID: String?
    let title: (IslandHaloTheme) -> String
    let pick: (IslandHaloTheme) -> Void

    @Namespace private var ring

    private static let columns = [GridItem(.adaptive(minimum: 104), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: 10) {
            ForEach(IslandHaloTheme.all) { theme in
                PersonalizationCard(
                    title: title(theme),
                    selected: selectedID == theme.id,
                    ringNamespace: ring,
                    ringGroup: "nook.halo.theme",
                    action: { pick(theme) }
                ) {
                    GlowThemeSwatches(colors: theme.swatches)
                }
            }
        }
    }
}

/// A theme's colors as a row of overlapping dots, each with a little of its
/// own glow.
struct GlowThemeSwatches: View {
    let colors: [IslandHaloRGB]

    private static let dot: CGFloat = 14

    var body: some View {
        HStack(spacing: -3) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                Circle()
                    .fill(color.color)
                    .frame(width: Self.dot, height: Self.dot)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.55), lineWidth: 1))
                    .shadow(color: color.color.opacity(0.55), radius: 4)
            }
        }
    }
}

/// The card chrome the Personalization switch rows use, around rows of its
/// own.
private struct GlowRowCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

/// A system color well for one glow color. The picked color is rounded to
/// what the settings can hold before it is kept.
private struct GlowColorWell: View {
    let title: String
    let color: IslandHaloRGB
    let set: (IslandHaloRGB) -> Void

    var body: some View {
        ColorPicker(
            title,
            selection: Binding(
                get: { color.color },
                set: { picked in
                    guard let rgb = IslandHaloRGB(picked)?.quantized, rgb != color else { return }
                    set(rgb)
                }
            ),
            supportsOpacity: false
        )
        .labelsHidden()
    }
}

/// A round swatch that picks a ready color.
private struct GlowSwatchButton: View {
    let color: IslandHaloRGB
    let selected: Bool
    let action: () -> Void

    private static let size: CGFloat = 18

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color.color)
                .frame(width: Self.size, height: Self.size)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.4), lineWidth: 1))
                .padding(3)
                .overlay(
                    Circle().strokeBorder(V6Palette.paper.opacity(selected ? 0.9 : 0), lineWidth: 1.5)
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .motionAnimation(Motion.selection, value: selected)
        .accessibilityLabel("#\(color.hex)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
