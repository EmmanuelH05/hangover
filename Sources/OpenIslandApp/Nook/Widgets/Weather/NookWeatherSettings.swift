import SwiftUI

/// Settings for the weather tile: the city, the unit and where the data
/// comes from. Renders inside the Nook settings `Form`.
struct NookWeatherSettings: View {
    var nook: NookModel

    @State private var query = ""

    private var lang: LanguageManager { .shared }

    var body: some View {
        let weather = nook.weather
        let isOn = nook.isWidgetEnabled(.weather)
        Section(lang.t("nook.weather.title")) {
            LabeledContent(lang.t("nook.weather.settings.city")) {
                HStack {
                    Text(weather.place?.label ?? lang.t("nook.weather.settings.city.none"))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if weather.place != nil {
                        Button(lang.t("nook.weather.settings.city.remove")) { weather.clearPlace() }
                    }
                }
            }
            HStack {
                TextField(lang.t("nook.weather.settings.search.placeholder"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(search)
                Button(lang.t("nook.weather.settings.search"), action: search)
                    .disabled(!isOn || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .disabled(!isOn)
            if !isOn {
                Text(lang.t("nook.weather.settings.off"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            results(weather)
            Picker(lang.t("nook.weather.settings.unit"), selection: Binding(
                get: { weather.unit },
                set: { weather.unit = $0 }
            )) {
                Text(lang.t("nook.weather.settings.unit.fahrenheit")).tag(NookTemperatureUnit.fahrenheit)
                Text(lang.t("nook.weather.settings.unit.celsius")).tag(NookTemperatureUnit.celsius)
            }
            .pickerStyle(.segmented)
            Link(lang.t("nook.weather.credit"), destination: NookWeatherClient.creditURL)
                .font(.caption)
            Text(lang.t("nook.weather.settings.privacy"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func results(_ weather: NookWeatherService) -> some View {
        switch weather.searchStatus {
        case .searching:
            Text(lang.t("nook.weather.settings.searching"))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .noMatch:
            Text(lang.t("nook.weather.settings.noMatch"))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(.offline):
            Text(lang.t("nook.weather.failed.offline"))
                .font(.caption)
                .foregroundStyle(.orange)
        case .failed:
            Text(lang.t("nook.weather.failed.server"))
                .font(.caption)
                .foregroundStyle(.orange)
        case .idle:
            ForEach(weather.searchResults) { place in
                Button {
                    weather.setPlace(place)
                    query = ""
                } label: {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(.secondary)
                        Text(place.label)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func search() {
        nook.weather.search(query, language: lang.language.resolvedCode)
    }
}
