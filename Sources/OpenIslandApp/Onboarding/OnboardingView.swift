import SwiftUI

/// The welcome tour's window content: the page that is up and, under it,
/// Skip, the progress dots, Back and Next. Return moves on, Escape skips
/// and the left and right arrows turn the pages.
struct OnboardingView: View {
    var tour: OnboardingTour
    let lang: LanguageManager

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let barHeight: CGFloat = 66

    var body: some View {
        VStack(spacing: 0) {
            OnboardingPageView(page: tour.page, state: tour.state, actions: tour.actions, lang: lang)
                .id(tour.page)
                .transition(pageTransition)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            navigation
        }
        .frame(width: OnboardingStyle.windowSize.width, height: OnboardingStyle.windowSize.height)
        .background(background)
        .environment(\.colorScheme, .dark)
        .animation(reduceMotion ? Motion.reducedFallback : Motion.pageSwitch, value: tour.page)
    }

    /// A fade with a short slide. With Reduce Motion, the fade alone.
    private var pageTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(x: 12))
    }

    private var background: some View {
        ZStack {
            OnboardingStyle.ink
            RadialGradient(
                colors: [Color.white.opacity(0.07), .clear],
                center: .top,
                startRadius: 0,
                endRadius: OnboardingStyle.windowSize.width * 0.6
            )
        }
    }

    private var navigation: some View {
        ZStack {
            dots

            HStack(spacing: 8) {
                Button(lang.t("onboarding.nav.skip")) { tour.skip() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(OnboardingStyle.secondaryText)
                    .keyboardShortcut(.cancelAction)

                Spacer(minLength: 0)

                Button(lang.t("onboarding.nav.back")) { tour.back() }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                    .disabled(tour.flow.isFirstPage)
                    .opacity(tour.flow.isFirstPage ? 0.35 : 1)
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .background(rightArrowKey)

                Button(lang.t(tour.flow.isLastPage ? "onboarding.nav.finish" : "onboarding.nav.next")) { tour.next() }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, OnboardingStyle.sidePadding)
        .frame(height: Self.barHeight)
        .background(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
        }
    }

    /// The right arrow turns a page and never ends the tour: only the last
    /// page's button and Return do that.
    private var rightArrowKey: some View {
        Button("") {
            if !tour.flow.isLastPage { tour.next() }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.rightArrow, modifiers: [])
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    /// One dot a page. The page that is up is drawn longer, and a dot is a
    /// button to its page.
    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingPage.allCases) { page in
                Button {
                    tour.go(to: page)
                } label: {
                    Capsule()
                        .fill(page == tour.page ? OnboardingStyle.paper : Color.white.opacity(0.22))
                        .frame(width: page == tour.page ? 18 : 6, height: 6)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(lang.t("onboarding.nav.page", page.rawValue + 1, OnboardingPage.allCases.count))
                .accessibilityAddTraits(page == tour.page ? .isSelected : [])
            }
        }
    }
}
