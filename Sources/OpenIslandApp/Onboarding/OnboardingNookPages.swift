import SwiftUI

// The two pages about the Nook, the page with the widgets: which widgets
// are on, and a starting layout for them. Both are live pages (D44): the
// real island at the top of the screen is their preview. Each is a
// narrow column of choices and one line that points at the island.

// MARK: - 6. Widgets

/// One row a widget: its picture, its name and its switch. The real island
/// shows the widgets that are on, and a card under the list spotlights the
/// widget whose row was clicked.
struct OnboardingWidgetsPage: View {
    let context: OnboardingPageContext

    private var state: OnboardingState { context.state }

    private static let rowHeight: CGFloat = 38

    var body: some View {
        OnboardingPageScaffold(
            page: .widgets,
            context: context,
            title: context.t("onboarding.widgets.title"),
            text: context.t("onboarding.widgets.body"),
            footnote: context.t("onboarding.widgets.note"),
            gap: 12
        ) {
            VStack(spacing: 12) {
                OnboardingLiveLine(text: context.t("onboarding.live.line"))

                VStack(spacing: 0) {
                    ForEach(Array(NookWidgetKind.allCases.enumerated()), id: \.element) { index, kind in
                        if index > 0 { OnboardingDivider() }
                        row(kind)
                    }
                }
                .background(OnboardingCardBackground())

                OnboardingSpotlightCard(
                    kind: state.spotlight,
                    isOn: state.showsWidget(state.spotlight),
                    context: context
                )
            }
        }
    }

    /// A widget's row: the left of it selects the widget for the spotlight,
    /// the switch at the right turns it on or off. On puts the widget on
    /// this display's page, off switches it off for the app.
    private func row(_ kind: NookWidgetKind) -> some View {
        let isOn = state.showsWidget(kind)
        let isSelected = state.spotlight == kind
        let name = context.t("onboarding.nook.widget.\(kind.rawValue)")
        return HStack(spacing: 0) {
            Button {
                context.actions.spotlightWidget(kind)
            } label: {
                HStack(spacing: 10) {
                    OnboardingSymbolPlate(
                        symbol: kind.systemImage,
                        size: 26,
                        tint: isOn ? OnboardingStyle.paper : OnboardingStyle.faintText
                    )
                    Text(name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isOn ? OnboardingStyle.primaryText : OnboardingStyle.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                }
                .padding(.leading, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(name)
            .accessibilityValue(context.t("onboarding.widgets.\(kind.rawValue)"))
            .accessibilityHint(context.t("onboarding.widgets.spotlight.hint"))
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Button {
                context.actions.setWidget(kind, !isOn)
            } label: {
                OnboardingSwitchArt(isOn: isOn)
                    .padding(.horizontal, 10)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(context.lang.t("onboarding.widgets.switch", name))
            .accessibilityValue(context.t(isOn ? "onboarding.widgets.switch.on" : "onboarding.widgets.switch.off"))
        }
        .frame(height: Self.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? OnboardingStyle.selectedFill : Color.clear)
                .padding(3)
        )
    }
}

// MARK: - 7. Layout

/// A card for each layout on offer, drawn as the page it makes in quiet
/// grays, and what the layout in use is best for. Picking one applies it to
/// the real island.
struct OnboardingLayoutPage: View {
    let context: OnboardingPageContext

    private var state: OnboardingState { context.state }

    private static let cardHeight: CGFloat = 68
    private static let thumbSize = CGSize(width: 72, height: 52)

    var body: some View {
        let templates = PersonalizationTemplate.offeredInTour(agentsEnabled: state.agentsEnabled)
        OnboardingPageScaffold(
            page: .layout,
            context: context,
            title: context.t("onboarding.layout.title"),
            text: context.t("onboarding.layout.body"),
            footnote: context.t("onboarding.layout.note"),
            gap: 12
        ) {
            VStack(spacing: 12) {
                OnboardingLiveLine(text: context.t("onboarding.live.line"))

                VStack(spacing: 8) {
                    if Self.offersOwnCard(state) { ownCard }
                    ForEach(templates) { template in card(template) }
                }

                description
            }
        }
    }

    /// The card for the user's own layout shows while the display is on
    /// it, and while the tour holds it to go back to.
    static func offersOwnCard(_ state: OnboardingState) -> Bool {
        state.shownTemplate == nil || state.canKeepOwnLayout
    }

    /// The name of the layout in use and what it is best for.
    private var description: some View {
        let text = state.shownTemplate.map { TemplateText($0, lang: context.lang, showsAgents: state.agentsEnabled) }
        return VStack(alignment: .leading, spacing: 5) {
            Text(text?.title ?? context.t("onboarding.layout.own.title"))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(OnboardingStyle.primaryText)
            Text(text?.bestFor ?? context.t("onboarding.layout.own.text"))
                .font(.system(size: 12))
                .foregroundStyle(OnboardingStyle.secondaryText)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var ownCard: some View {
        let title = context.t("onboarding.layout.own.card")
        let isSelected = state.shownTemplate == nil
        return OnboardingChoiceCard(isSelected: isSelected, showsTick: false) {
            context.actions.keepOwnLayout()
        } content: {
            cardBody(title: title, isSelected: isSelected) {
                thumb(state.ownLayoutPlacements, calendarStyle: state.calendarStyle)
            }
        }
        .frame(height: Self.cardHeight)
        .accessibilityLabel(title)
    }

    private func card(_ template: PersonalizationTemplate) -> some View {
        let text = TemplateText(template.id, lang: context.lang, showsAgents: state.agentsEnabled)
        let isSelected = state.shownTemplate == template.id
        return OnboardingChoiceCard(isSelected: isSelected, showsTick: false) {
            context.actions.applyTemplate(template)
        } content: {
            cardBody(title: text.title, isSelected: isSelected) {
                thumb(
                    template.widgets.filter { state.enabledWidgets.contains($0.kind) },
                    calendarStyle: template.nook.calendarStyle
                )
            }
        }
        .frame(height: Self.cardHeight)
        .accessibilityLabel(text.spokenSummary)
    }

    private func thumb(_ placements: [NookWidgetPlacement], calendarStyle: NookCalendarStyle) -> some View {
        OnboardingLayoutThumb(
            placements: placements,
            calendarStyle: calendarStyle,
            name: { context.t("onboarding.nook.widget.\($0.rawValue)") },
            size: Self.thumbSize
        )
    }

    /// The miniature beside the name. The tick of the picked card sits at
    /// the end of the row, off the miniature.
    private func cardBody<Picture: View>(
        title: String,
        isSelected: Bool,
        @ViewBuilder picture: () -> Picture
    ) -> some View {
        HStack(spacing: 12) {
            picture()
                .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OnboardingStyle.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OnboardingStyle.paper)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
    }
}
