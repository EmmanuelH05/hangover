import SwiftUI

/// The welcome tour's window content: the page that is up and, under it,
/// how far along the tour is, Skip, the progress dots, Back and Next.
/// Return moves on, Escape skips and the left and right arrows turn the
/// pages.
struct OnboardingView: View {
    var tour: OnboardingTour
    let lang: LanguageManager
    /// Called when the page that is up changes, for the window to hold the
    /// island and move (D44).
    var onPageChange: () -> Void = {}
    /// Called when something that sets the opened island's footprint changed
    /// (its look, or the kind of display), for the window to dock again.
    var onFootprintChange: () -> Void = {}
    /// The accent color the app is set to (D62). A snapshot leaves it out
    /// and draws today's look.
    var accent: () -> HangoverAccentTint = { .standard }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// True for `OnboardingKeyRule.settle` after the kit's loupe went away.
    @State private var isSettlingKeys = false

    private static let barHeight: CGFloat = 62
    private static let progressHeight: CGFloat = 2

    /// The view takes the size of the window it is in. A snapshot gives it
    /// one with a frame.
    var body: some View {
        let pages = tour.pages
        let step = tour.step
        // The total is the length of the list the user picked, counted as it
        // stands now. Until a length is picked there is none to count.
        let total = tour.stepCount
        let isCompact = tour.page.isLive
        VStack(spacing: 0) {
            OnboardingPageView(
                page: tour.page,
                context: OnboardingPageContext(
                    state: tour.state,
                    actions: tour.actions,
                    lang: lang,
                    step: step,
                    stepCount: total
                )
            )
            .id(tour.page)
            .transition(pageTransition)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            navigation(pages: pages, step: step, total: total, isCompact: isCompact)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
        .environment(\.colorScheme, .dark)
        .environment(\.hangoverAccent, accent())
        .animation(reduceMotion ? Motion.reducedFallback : Motion.pageSwitch, value: tour.page)
        .onChange(of: tour.page) { onPageChange() }
        .onChange(of: tour.state.features.design.isSampling) { wasSampling, isSampling in
            guard wasSampling, !isSampling else { return }
            isSettlingKeys = true
            Task {
                try? await Task.sleep(for: OnboardingKeyRule.settle)
                isSettlingKeys = false
            }
        }
        .onChange(of: tour.state.openedLook) { onFootprintChange() }
        .onChange(of: tour.state.displayProfile) { onFootprintChange() }
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
                endRadius: 540
            )
        }
    }

    /// The narrow window has no room for the dots: the line over the bar and
    /// the step count on the page say how far along the tour is.
    private func navigation(pages: [OnboardingPage], step: Int, total: Int?, isCompact: Bool) -> some View {
        let takesKeys = OnboardingKeyRule.takesKeys(
            isSampling: tour.state.features.design.isSampling,
            isSettling: isSettlingKeys
        )
        return ZStack {
            // The buttons that carry on to a longer tour take the room the
            // dots have in the middle of the bar, and the last page needs no
            // dots to say where it is.
            if !isCompact, tour.carryOnLengths.isEmpty { dots(pages, total: total) }

            HStack(spacing: 8) {
                Button(lang.t("onboarding.nav.skip")) { tour.skip() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(OnboardingStyle.secondaryText)
                    .keyboardShortcut(OnboardingKeyRule.shortcut(for: .escape, takesKeys: takesKeys))

                Spacer(minLength: 0)

                Button(lang.t("onboarding.nav.back")) { tour.back() }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                    .disabled(tour.isFirstPage)
                    .opacity(tour.isFirstPage ? 0.35 : 1)
                    .keyboardShortcut(OnboardingKeyRule.shortcut(for: .leftArrow, takesKeys: takesKeys))
                    .background(rightArrowKey(takesKeys: takesKeys))

                // A last page offers the longer tours: the main one after the
                // short, everything after either.
                ForEach(tour.carryOnLengths) { length in
                    Button(lang.t(length.carryOnKey)) { tour.carryOn(to: length) }
                        .buttonStyle(OnboardingSecondaryButtonStyle())
                }

                Button(lang.t(tour.isLastPage ? "onboarding.nav.finish" : "onboarding.nav.next")) { tour.next() }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .disabled(!tour.canGoNext)
                    .opacity(tour.canGoNext ? 1 : 0.35)
                    .keyboardShortcut(OnboardingKeyRule.shortcut(for: .returnKey, takesKeys: takesKeys))
            }
        }
        .padding(.horizontal, isCompact ? OnboardingStyle.compactSidePadding : OnboardingStyle.sidePadding)
        .frame(height: Self.barHeight)
        .background(alignment: .top) { progress(step: step, count: total) }
    }

    /// A thin line along the top of the bar, filled as far as the tour has
    /// come. The dots say which page; the line says how much is left. With
    /// no length picked there is nothing to measure it against.
    private func progress(step: Int, count: Int?) -> some View {
        let fraction = count.map { Self.progressFraction(step: step, count: $0) } ?? 0
        return Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: Self.progressHeight)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(OnboardingStyle.paper.opacity(0.75))
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .accessibilityHidden(true)
    }

    /// How much of the line is filled on page `step` of `count`.
    static func progressFraction(step: Int, count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(min(max(step, 0), count)) / CGFloat(count)
    }

    /// The right arrow turns a page and never ends the tour: only the last
    /// page's button and Return do that.
    private func rightArrowKey(takesKeys: Bool) -> some View {
        Button("") {
            if !tour.isLastPage { tour.next() }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(OnboardingKeyRule.shortcut(for: .rightArrow, takesKeys: takesKeys))
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    /// One dot a page. The page that is up is drawn longer, and a dot is a
    /// button to its page.
    private func dots(_ pages: [OnboardingPage], total: Int?) -> some View {
        HStack(spacing: 5) {
            ForEach(Array(pages.enumerated()), id: \.element) { index, page in
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
                .accessibilityLabel(
                    total.map { lang.t("onboarding.nav.page", index + 1, $0) }
                        ?? lang.t("onboarding.nav.page.open", index + 1)
                )
                .accessibilityAddTraits(page == tour.page ? .isSelected : [])
            }
        }
    }
}
