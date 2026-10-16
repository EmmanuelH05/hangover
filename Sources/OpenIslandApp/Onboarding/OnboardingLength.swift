import Foundation

/// How long a run of the welcome tour is. The user picks one on the page
/// after the welcome page, "How much time do you have?", and the pages that
/// follow are a pure function of the pick (`OnboardingPage.shown`). Every
/// length holds the pages of the one before it.
enum OnboardingLength: String, CaseIterable, Identifiable, Comparable, Sendable {
    /// A quick look at the essentials.
    case short
    /// The main tour: the pages of the tour as it was before there were
    /// lengths.
    case medium
    /// Every feature, one at a time: the main tour and a page for each
    /// feature it does not teach (`OnboardingMore`).
    case long

    var id: String { rawValue }

    private var rank: Int {
        switch self {
        case .short: 0
        case .medium: 1
        case .long: 2
        }
    }

    static func < (lhs: OnboardingLength, rhs: OnboardingLength) -> Bool {
        lhs.rank < rhs.rank
    }

    /// The card's name on the question page, and the line under it.
    var titleKey: String { "onboarding.length.\(rawValue).title" }
    var textKey: String { "onboarding.length.\(rawValue).text" }

    /// The three short lines under the card that say what the tour walks
    /// through. Each is a page or a few pages of the list the length gives.
    var pointKeys: [String] {
        (1...3).map { "onboarding.length.\(rawValue).point\($0)" }
    }

    /// The button on a last page that carries on to this length.
    var carryOnKey: String { "onboarding.nav.carry.\(rawValue)" }

    /// The lengths a run of this one can carry on to, shortest first.
    var longer: [OnboardingLength] {
        Self.allCases.filter { $0 > self }
    }
}

extension OnboardingPage {
    /// The shortest length that walks this page. The short tour is the
    /// pages the app cannot be used well without: what it is, what it is
    /// for, how it opens, what the closed island shows, which widgets are
    /// on, what macOS may ask, and the last page. The main tour is every
    /// page that existed before the lengths, and the long tour adds the
    /// pages of `OnboardingMore`.
    var shortestLength: OnboardingLength {
        switch self {
        case .welcome, .length, .purpose, .opening, .closed, .widgets, .permissions, .done:
            .short
        case .agents, .features, .layout, .arrange, .todos, .notes, .weather, .opened, .look, .integrations, .tips:
            .medium
        case .mirror, .booth, .weatherCard, .record, .convert, .lights, .accent, .power, .volume, .usage, .quiet, .phone, .screens, .sounds,
             .links, .startup, .updates:
            .long
        }
    }

    /// True for the pages only the long tour walks.
    var isLongOnly: Bool { shortestLength == .long }
}

extension OnboardingGrant {
    /// The widgets whose first use makes macOS ask for something the
    /// permissions page names: the camera for the mirror, Calendar for the
    /// calendar, Reminders for the to-dos, and Screen Recording and the
    /// microphone for Record. The short tour walks the permissions page while
    /// one of them is on the page, and while the agents are on, which is when
    /// it has its Automation row. The longer tours always walk it.
    static let widgetsAskingMacOS: Set<NookWidgetKind> = [.mirror, .calendar, .todo, .record]
}
