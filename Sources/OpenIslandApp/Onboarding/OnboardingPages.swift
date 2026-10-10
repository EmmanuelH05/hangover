import SwiftUI

/// What every page of the tour is handed: the app's state, what its
/// buttons do, the language, and where the page stands in this run.
@MainActor
struct OnboardingPageContext {
    let state: OnboardingState
    let actions: OnboardingActions
    let lang: LanguageManager
    /// This page's place in the run, counted from one.
    var step = 1
    /// How many pages this run walks.
    var stepCount = OnboardingPage.allCases.count

    func t(_ key: String) -> String { lang.t(key) }
}

/// One page of the welcome tour. A page is a function of the tour's state
/// and draws nothing but SwiftUI, which keeps it the same in the window
/// and in a snapshot.
struct OnboardingPageView: View {
    let page: OnboardingPage
    let context: OnboardingPageContext

    var body: some View {
        Group {
            switch page {
            case .welcome: OnboardingWelcomePage(context: context)
            case .purpose: OnboardingPurposePage(context: context)
            case .opening: OnboardingOpeningPage(context: context)
            case .closed: OnboardingClosedPage(context: context)
            case .agents: OnboardingAgentsPage(context: context)
            case .widgets: OnboardingWidgetsPage(context: context)
            case .features: OnboardingFeaturesPage(context: context)
            case .todos: OnboardingTodosPage(context: context)
            case .notes: OnboardingNotesPage(context: context)
            case .weather: OnboardingWeatherPage(context: context)
            case .layout: OnboardingLayoutPage(context: context)
            case .arrange: OnboardingArrangePage(context: context)
            case .opened: OnboardingOpenedPage(context: context)
            case .look: OnboardingGlowPage(context: context)
            case .permissions: OnboardingPermissionsPage(context: context)
            case .integrations: OnboardingIntegrationsPage(context: context)
            case .tips: OnboardingTipsPage(context: context)
            case .done: OnboardingDonePage(context: context)
            }
        }
        .padding(.horizontal, page.isLive ? OnboardingStyle.compactSidePadding : OnboardingStyle.sidePadding)
        // Room for the window's own buttons at the top left.
        .padding(.top, 32)
        .padding(.bottom, 12)
    }
}

/// The one plain line a live page has where a drawn preview would be: it
/// points at the real island at the top of the screen (D44).
struct OnboardingLiveLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "arrow.up")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(OnboardingStyle.paper)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(OnboardingStyle.primaryText.opacity(0.9))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OnboardingCardBackground())
        .accessibilityElement(children: .combine)
    }
}

/// The skeleton every page shares (D43): which part of the tour this is and
/// how far along, a title that is a plain question or statement, a sentence
/// or two, the page's own picture and choices, and one line that says where
/// the choice can be changed later.
struct OnboardingPageScaffold<Content: View>: View {
    let page: OnboardingPage
    let context: OnboardingPageContext
    let title: String
    let text: String
    var footnote: String?
    /// Room between the heading and the page's content.
    var gap: CGFloat = 16
    @ViewBuilder var content: () -> Content

    @Environment(\.nookDrawsStill) private var drawsStill

    var body: some View {
        if page.isLive {
            compactBody
        } else {
            wideBody
        }
    }

    /// A live page in the narrow window: the chapter and step, the title,
    /// a sentence or two, the choices in one column that scrolls when the
    /// window is shorter than the page, and the footnote.
    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Self.eyebrow(page, context).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(OnboardingStyle.faintText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(OnboardingStyle.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(OnboardingStyle.secondaryText)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            scrolling {
                content()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.vertical, 2)
            }
            .padding(.top, gap)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if let footnote {
                OnboardingNote(text: footnote)
                    .font(.system(size: 11))
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// The choices of a live page scroll when the window is shorter than
    /// they are. A snapshot draws them in place and cuts them at the
    /// bottom: a scroll view is an AppKit view, which `ImageRenderer`
    /// leaves blank.
    @ViewBuilder
    private func scrolling<Body: View>(@ViewBuilder _ body: () -> Body) -> some View {
        if drawsStill {
            body()
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                .clipped()
        } else {
            ScrollView(.vertical, showsIndicators: false) { body() }
        }
    }

    private var wideBody: some View {
        VStack(spacing: 0) {
            OnboardingHeading(eyebrow: Self.eyebrow(page, context), title: title, text: text)
            content()
                .padding(.top, gap)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if let footnote {
                OnboardingNote(text: footnote)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 680)
                    .padding(.top, 8)
            }
        }
    }

    /// "Basics · Step 2 of 11".
    static func eyebrow(_ page: OnboardingPage, _ context: OnboardingPageContext) -> String {
        let chapter = context.lang.t(page.chapter.titleKey)
        let step = context.lang.t("onboarding.step", context.step, context.stepCount)
        return "\(chapter) · \(step)"
    }
}

/// A page's chapter line, its headline and the sentence or two under it.
struct OnboardingHeading: View {
    var eyebrow: String?
    let title: String
    let text: String
    var titleSize: CGFloat = 26

    var body: some View {
        VStack(spacing: 7) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(OnboardingStyle.faintText)
            }
            Text(title)
                .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                .foregroundStyle(OnboardingStyle.primaryText)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(OnboardingStyle.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: OnboardingStyle.textWidth)
        }
    }
}

/// A quiet line of small print.
struct OnboardingNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(OnboardingStyle.faintText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The plate behind a list or a block of text.
struct OnboardingCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: OnboardingStyle.cardCornerRadius, style: .continuous)
            .fill(OnboardingStyle.cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: OnboardingStyle.cardCornerRadius, style: .continuous)
                    .strokeBorder(OnboardingStyle.cardStroke, lineWidth: 1)
            )
    }
}

/// The hairline between two rows of a list.
struct OnboardingDivider: View {
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
    }
}

/// A symbol on a small rounded plate: the picture of a row or a tip.
struct OnboardingSymbolPlate: View {
    let symbol: String
    var size: CGFloat = 30
    var tint: Color = OnboardingStyle.paper

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.43, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(Color.white.opacity(0.09))
            )
            .accessibilityHidden(true)
    }
}
