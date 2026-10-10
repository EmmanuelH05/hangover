import SwiftUI

// The calendar step's picker (D50): the five looks of the calendar widget,
// each drawn by the app's own sample calendar with sample events, one tall
// column of wide cards. A press writes the look for the display the island
// is on, as Settings does, and the choice is kept (it is a choice like a
// layout, not a try-it).

/// The looks the picker offers, in the order Settings shows them, with the
/// string keys of their names and lines.
enum OnboardingCalendarLooks {
    /// Settings' own list: every look at every widget size. At the small
    /// size the real card is the compact list for all five.
    static var all: [NookCalendarStyle] { NookCalendarStyle.allCases }

    /// The name Settings gives the look.
    static func nameKey(_ style: NookCalendarStyle) -> String {
        "settings.appearance.nook.calendarStyle.\(style.rawValue)"
    }

    /// What the look is good for, in one line.
    static func lineKey(_ style: NookCalendarStyle) -> String {
        "onboarding.features.look.\(style.rawValue)"
    }

    static let titleKey = "onboarding.features.look.title"
    static let noteKey = "onboarding.features.look.note"
}

/// One look drawn as the island's calendar card draws it, with sample
/// events. The card is laid out at the width of a medium widget and made
/// smaller to the width the page has.
struct OnboardingCalendarLookPicture: View {
    let style: NookCalendarStyle

    /// The width of a medium calendar card on the opened island.
    static let naturalWidth: CGFloat = 360

    /// The height the real card has at that look.
    static func naturalHeight(_ style: NookCalendarStyle) -> CGFloat {
        NookCalendarCard.height(for: style)
    }

    var body: some View {
        let height = Self.naturalHeight(style)
        Color.clear
            .aspectRatio(Self.naturalWidth / height, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                GeometryReader { geometry in
                    NookSampleCard(kind: .calendar, size: .medium, calendarStyle: style)
                        .frame(width: Self.naturalWidth, height: height)
                        .scaleEffect(geometry.size.width / Self.naturalWidth, anchor: .topLeading)
                }
            }
            .accessibilityHidden(true)
    }
}

/// "Pick its look": the five cards and the line that says the island shows
/// the user's own events once the calendar is allowed.
struct OnboardingCalendarLookPicker: View {
    let context: OnboardingPageContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(context.t(OnboardingCalendarLooks.titleKey).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(OnboardingStyle.faintText)
                .accessibilityAddTraits(.isHeader)
            ForEach(OnboardingCalendarLooks.all) { style in card(style) }
            OnboardingNote(text: context.t(OnboardingCalendarLooks.noteKey))
        }
    }

    private func card(_ style: NookCalendarStyle) -> some View {
        let isSelected = context.state.calendarStyle == style
        let name = context.t(OnboardingCalendarLooks.nameKey(style))
        return OnboardingChoiceCard(isSelected: isSelected, showsTick: false) {
            context.actions.setCalendarStyle(style)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                OnboardingCalendarLookPicture(style: style)
                HStack(spacing: 5) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(OnboardingStyle.paper)
                    }
                    Text(name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(OnboardingStyle.primaryText)
                }
                Text(context.t(OnboardingCalendarLooks.lineKey(style)))
                    .font(.system(size: 11.5))
                    .foregroundStyle(OnboardingStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
        }
        .accessibilityLabel(name)
    }
}
