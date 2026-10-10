import SwiftUI

/// The place field of the weather page: the one plain text field in the
/// tour besides the to-dos secret. The typed text lives in this view's own
/// `@State`, goes to `onSearch` on Return or the button, and leaves with the
/// field. A snapshot may draw the field blank, because a `TextField` is an
/// AppKit view.
struct OnboardingPlaceField: View {
    let placeholder: String
    let buttonTitle: String
    let isBusy: Bool
    let onSearch: (String) -> Void

    @State private var draft = ""

    private var isBlank: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(OnboardingStyle.primaryText)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(OnboardingStyle.cardStroke, lineWidth: 1)
                )
                .onSubmit(submit)
            Button(buttonTitle, action: submit)
                .buttonStyle(OnboardingSecondaryButtonStyle(height: 28))
                .disabled(isBlank || isBusy)
                .opacity(isBlank || isBusy ? 0.5 : 1)
        }
        .onDisappear { draft = "" }
    }

    private func submit() {
        guard !isBlank, !isBusy else { return }
        onSearch(draft)
    }
}

/// A found place as a plain button: its name over the region and country,
/// which is what tells two cities of one name apart.
private struct OnboardingPlaceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(configuration.isPressed ? 0.14 : 0.08))
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// The tour's page for where the user is, shown only while the weather
/// widget is on the page: a search for a city, the places it found as
/// buttons, Fahrenheit or Celsius, and a tick that says the place is set.
/// A pick and a unit go through the calls Settings makes (D44). The real
/// island shows the weather card filling in.
struct OnboardingWeatherPage: View {
    let context: OnboardingPageContext

    /// True after Change was pressed over a place that is already set.
    @State private var isChanging = false

    private var weather: OnboardingWeatherSetup { context.state.weather }

    var body: some View {
        OnboardingPageScaffold(
            page: .weather,
            context: context,
            title: context.t("onboarding.weather.title"),
            text: context.t("onboarding.weather.body"),
            footnote: context.t("onboarding.weather.note"),
            gap: 12
        ) {
            VStack(alignment: .leading, spacing: 12) {
                OnboardingLiveLine(text: context.t("onboarding.live.line"))
                placeCard
                if weather.place == nil || isChanging { search }
                units
            }
        }
        .onChange(of: weather.place) { isChanging = false }
    }

    // MARK: The place

    /// The tick: what is saved, or what to do.
    private var placeCard: some View {
        let place = weather.place
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: place == nil ? "circle" : "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(place == nil ? OnboardingStyle.faintText : OnboardingStyle.paper)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.t(place == nil ? "onboarding.weather.unset" : "onboarding.weather.set"))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(OnboardingStyle.primaryText.opacity(place == nil ? 0.85 : 1))
                    if let place {
                        Text(place.label)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(OnboardingStyle.primaryText)
                    }
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if let key = weather.forecastKey {
                Text(context.t(key))
                    .font(.system(size: 11.5))
                    .foregroundStyle(OnboardingStyle.secondaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Button(context.t(isChanging ? "onboarding.weather.keep" : "onboarding.weather.change")) {
                    isChanging.toggle()
                }
                .buttonStyle(OnboardingSecondaryButtonStyle(height: 28))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OnboardingCardBackground())
        .accessibilityElement(children: .contain)
        .accessibilityValue(context.t(place == nil ? "onboarding.arrange.todo" : "onboarding.arrange.done"))
    }

    // MARK: Search

    private var search: some View {
        VStack(alignment: .leading, spacing: 8) {
            OnboardingPlaceField(
                placeholder: context.t("nook.weather.settings.search.placeholder"),
                buttonTitle: context.t("nook.weather.settings.search"),
                isBusy: weather.isSearching
            ) { text in context.actions.searchWeather(text) }
            status
            VStack(spacing: 5) {
                ForEach(weather.results) { place in
                    Button { context.actions.chooseWeatherPlace(place) } label: { placeLabel(place) }
                        .buttonStyle(OnboardingPlaceButtonStyle())
                }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if weather.isSearching {
            line(context.t("nook.weather.settings.searching"), isProblem: false)
        } else if let key = weather.searchProblemKey {
            line(context.t(key), isProblem: weather.search != .noMatch)
        }
    }

    private func line(_ text: String, isProblem: Bool) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(isProblem ? OnboardingStyle.waiting : OnboardingStyle.secondaryText)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func placeLabel(_ place: NookWeatherPlace) -> some View {
        let detail = [place.region, place.country]
            .compactMap { $0 }
            .filter { !$0.isEmpty && $0 != place.name }
            .joined(separator: ", ")
        return VStack(alignment: .leading, spacing: 1) {
            Text(place.name)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(OnboardingStyle.primaryText)
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(OnboardingStyle.secondaryText)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Unit

    private var units: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(context.t("onboarding.weather.unit"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OnboardingStyle.primaryText)
            HStack(spacing: 6) {
                ForEach(NookTemperatureUnit.allCases) { unit in
                    Button(context.t("nook.weather.settings.unit.\(unit.rawValue)")) {
                        context.actions.setWeatherUnit(unit)
                    }
                    .buttonStyle(OnboardingPickButtonStyle(isChosen: weather.unit == unit))
                }
            }
        }
    }
}
