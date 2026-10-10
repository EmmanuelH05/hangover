import Foundation

/// What the tour reads of Settings' section "04 · While music plays" on the
/// display in use: the media style and which of its switches are on.
struct OnboardingClosedMusic: Equatable, Sendable {
    var style: NookClosedMediaStyle
    var onOptions: Set<NookClosedMusicOption>

    /// What the app starts with.
    init(_ preferences: NookDisplayPreferences = NookDisplayPreferences()) {
        style = preferences.mediaStyle
        onOptions = Set(NookClosedMusicOption.allCases.filter { preferences[keyPath: $0.keyPath] })
    }
}

/// One tap on the music group. It is applied with the same assignment the
/// cards and switches of Settings make (`nookClosedSection`).
enum OnboardingClosedMusicPick: Equatable, Sendable {
    case style(NookClosedMediaStyle)
    case option(NookClosedMusicOption, isOn: Bool)

    func apply(to preferences: inout NookDisplayPreferences) {
        switch self {
        case .style(let style): preferences.mediaStyle = style
        case .option(let option, let isOn): preferences[keyPath: option.keyPath] = isOn
        }
    }
}

extension AppModel {
    /// Applies the tour's pick on the music group to the display in use.
    func chooseClosedMusic(_ pick: OnboardingClosedMusicPick) {
        nook.updateDisplayPreferences(for: activeAppearanceProfile) { pick.apply(to: &$0) }
    }
}
