import Foundation
@testable import OpenIslandApp

@MainActor
extension OnboardingTour {
    /// Goes to the question page, as a dot does from the welcome page, and
    /// answers it, which is what a test needs before it walks the pages
    /// after it. The tour is left on the question page.
    func answerQuestion(_ length: OnboardingLength = .medium) {
        go(to: .length)
        chooseLength(length)
    }
}

extension OnboardingPage {
    /// The pages of the main tour with everything switched on: the tour as it
    /// was before there were lengths, with the question page after the
    /// welcome page. The long tour has ten more.
    static var mainTour: [OnboardingPage] {
        allCases.filter { !$0.isLongOnly }
    }
}

extension OnboardingRecapRow {
    /// The rows of a recap when the design kit, the lights and the Good to know
    /// switches were not chosen: the three rows that show only while they are
    /// on are left out.
    static var standard: [OnboardingRecapRow] {
        allCases.filter { $0 != .design && $0 != .lights && $0 != .goodToKnow }
    }
}
