import Foundation
import Testing
@testable import OpenIslandApp

// The long tour's pages and the strings of the lengths. Every page of
// `OnboardingMore` stands on code, and a page whose code is renamed fails
// here first.

// MARK: - What each page stands on

struct OnboardingMoreProofTests {
    private static let proofs = OnboardingMore.allCases.flatMap { $0.proofs }

    @Test(arguments: proofs)
    func theCodeBehindALongPageIsStillThere(proof: OnboardingProof) throws {
        let source = try HangoverBrandTests.text(of: proof.file)
        #expect(source.contains(proof.text), "\(proof.file) no longer has: \(proof.text)")
    }

    @Test func everyPageHasAtLeastOneProof() {
        for more in OnboardingMore.allCases {
            #expect(!more.proofs.isEmpty, "\(more) has no proof")
        }
    }

    @Test func theLongTourAddsSeventeenPagesAndEachHasItsOwn() {
        #expect(OnboardingMore.allCases.count == 17, "the mirror, its booth, the weather, Record, Convert, the accent, and ten more")
        #expect(OnboardingMore.allCases.map(\.page) == OnboardingPage.allCases.filter(\.isLongOnly))
        #expect(Set(OnboardingMore.allCases.map(\.page)).count == OnboardingMore.allCases.count)
        #expect(OnboardingPage.shown(length: .long, agentsEnabled: true).compactMap(\.more) == OnboardingMore.allCases)
        #expect(OnboardingPage.shown(length: .long, agentsEnabled: false).compactMap(\.more).count == 14)
        #expect(OnboardingMore.allCases.filter(\.needsAgents) == [.usage, .quiet, .phone])
    }

    /// The pages come in the order the island shows them: the widgets that start off,
    /// then its closed lights and notices, then what the open island and the agents do,
    /// then the Mac around it.
    @Test func theyAreToldWhatTheIslandShowsFirstAndTheMacLast() {
        #expect(OnboardingMore.allCases == [
            .mirror, .booth, .weather, .record, .convert, .lights, .accent, .power, .volume, .usage, .quiet, .phone,
            .screens, .sounds, .links, .startup, .updates,
        ])
    }

    @Test func thePagesWithANoteAreTheOnesWithSomethingToKnowFirst() {
        #expect(OnboardingMore.allCases.filter(\.hasNote) == [.mirror, .weather, .record, .lights, .volume, .usage, .phone, .links])
    }

    /// A page only tells. The one button opens Settings through the door the
    /// agents page has, and nothing on a long page asks macOS for anything.
    @Test func onlyTheUsagePageHasAButtonAndItOpensSettings() {
        #expect(OnboardingMore.allCases.filter(\.opensSettings) == [.usage])
    }
}

// MARK: - The strings

struct OnboardingLengthStringsTests {
    private static var keys: [String] {
        var keys = ["onboarding.length.title", "onboarding.length.body", "onboarding.length.note"]
        keys += OnboardingLength.allCases.flatMap { [$0.titleKey, $0.textKey] + $0.pointKeys }
        keys += OnboardingLength.allCases.dropFirst().map(\.carryOnKey)
        keys += [
            "onboarding.length.steps", "onboarding.step.open", "onboarding.nav.page.open",
            "onboarding.done.again", "onboarding.more.showSettings",
        ]
        for more in OnboardingMore.allCases {
            keys += [more.titleKey, more.textKey, more.whereKey]
            if more.hasNote { keys.append(more.noteKey) }
        }
        return keys
    }

    @Test(arguments: HangoverBrandTests.languages)
    func everyKeyOfTheLengthsIsInEveryLanguage(language: String) throws {
        let table = try HangoverBrandTests.table(language)
        for key in Self.keys {
            #expect(!(table[key] ?? "").isEmpty, "\(language) is missing \(key)")
        }
    }

    /// A page without a note has no key for one, in any language.
    @Test func aPageWithoutANoteHasNoNoteString() throws {
        for language in HangoverBrandTests.languages {
            let table = try HangoverBrandTests.table(language)
            for more in OnboardingMore.allCases where !more.hasNote {
                #expect(table[more.noteKey] == nil, "\(language) has a note for \(more)")
            }
        }
    }

    @Test func theCardsSayWhatTheOwnerWrote() throws {
        let english = try HangoverBrandTests.table("en")
        #expect(english["onboarding.length.short.title"] == "Not too much right now")
        #expect(english["onboarding.length.short.text"] == "A quick look at the essentials")
        #expect(english["onboarding.length.medium.title"] == "A little, but not a lot")
        #expect(english["onboarding.length.medium.text"] == "The main tour")
        #expect(english["onboarding.length.long.title"] == "All the time in the world")
        #expect(english["onboarding.length.long.text"] == "Every feature, one at a time")
        #expect(english["onboarding.length.title"] == "How much time do you have?")
        #expect(english["onboarding.length.steps"] == "%lld steps")
    }

    /// Each card has three short lines under its description, which fit the
    /// card's width without clipping.
    @Test func eachCardHasThreeShortLines() throws {
        for language in HangoverBrandTests.languages {
            let table = try HangoverBrandTests.table(language)
            for length in OnboardingLength.allCases {
                #expect(length.pointKeys.count == 3)
                for key in length.pointKeys {
                    let line = try #require(table[key], "\(language) is missing \(key)")
                    #expect(line.count <= 40, "\(language) \(key) is \(line.count) characters")
                }
            }
        }
    }

    /// A length is told in pages, never in minutes, and the welcome page
    /// does not promise a time any more.
    @Test func theTourNeverNamesAnAmountOfTime() throws {
        for language in HangoverBrandTests.languages {
            let table = try HangoverBrandTests.table(language)
            for key in Self.keys + ["onboarding.welcome.note"] {
                let value = try #require(table[key]).lowercased()
                #expect(!value.contains("minute") && !value.contains("分钟") && !value.contains("分鐘"), "\(language) \(key)")
            }
        }
    }

    @Test func theNewWordsAreWrittenPlainly() throws {
        let english = try HangoverBrandTests.table("en")
        for key in Self.keys {
            let value = try #require(english[key])
            #expect(value.range(of: "\\bso\\b", options: [.regularExpression, .caseInsensitive]) == nil, "\(key) uses the banned word")
            #expect(!value.contains("\u{2014}") && !value.contains("\u{2013}"), "\(key) has a dash")
            #expect(!value.lowercased().contains("hook"), "\(key) says hook")
        }
    }

    /// The tabs of the Settings window, by the names their sidebar gives
    /// them in English. Two of the labels are written in the code itself.
    private static func settingsTabNames() throws -> Set<String> {
        let english = try HangoverBrandTests.table("en")
        var names: Set<String> = []
        for tab in SettingsTab.allCases {
            switch tab {
            case .nook: names.insert("Nook")
            case .watch: names.insert("Watch")
            default: names.insert(try #require(english["settings.tab.\(tab.rawValue)"]))
            }
        }
        return names
    }

    /// Every "Settings, X tab" a long page says names a tab that is there.
    @Test func aPageSaysWhereItsFeatureIsTurnedOnInSettings() throws {
        let english = try HangoverBrandTests.table("en")
        let tabs = try Self.settingsTabNames()
        let named = try NSRegularExpression(pattern: "Settings, ([A-Za-z]+) tab")
        for more in OnboardingMore.allCases {
            let place = try #require(english[more.whereKey])
            #expect(place.hasPrefix("Settings, "), "\(more): \(place)")
            let keys = [more.whereKey, more.textKey] + (more.hasNote ? [more.noteKey] : [])
            for key in keys {
                let value = try #require(english[key])
                let range = NSRange(value.startIndex..., in: value)
                for match in named.matches(in: value, range: range) {
                    let tab = (Range(match.range(at: 1), in: value)).map { String(value[$0]) } ?? ""
                    #expect(tabs.contains(tab), "\(key) names the \(tab) tab, which Settings does not have")
                }
            }
            // The where line always names a tab.
            #expect(named.firstMatch(in: place, range: NSRange(place.startIndex..., in: place)) != nil, "\(more): \(place)")
        }
    }

    /// A pop-up the app skips is not held back for later: the page says it is
    /// not shown, as Settings says it is silenced, in every language.
    @Test func theQuietPageSaysTheCompletionPopUpIsNotShownAndNeverThatItWaits() throws {
        let english = try #require(try HangoverBrandTests.table("en")[OnboardingMore.quiet.textKey])
        #expect(english.contains("is not shown"))
        #expect(!english.lowercased().contains("wait"))
        for language in ["zh-Hans", "zh-Hant"] {
            let value = try #require(try HangoverBrandTests.table(language)[OnboardingMore.quiet.textKey])
            #expect(value.contains("不会显示") || value.contains("不會顯示"), "\(language): \(value)")
            #expect(!value.contains("等一等"), "\(language) says the pop-up waits")
        }
    }

    /// With the agents off, a page that is walked says nothing of agents.
    @Test func theLongPagesThatAreWalkedWithTheAgentsOffSayNothingOfThem() throws {
        let english = try HangoverBrandTests.table("en")
        for more in OnboardingPage.shown(length: .long, agentsEnabled: false).compactMap(\.more) {
            let keys = [more.titleKey, more.textKey, more.whereKey] + (more.hasNote ? [more.noteKey] : [])
            for key in keys {
                let value = try #require(english[key]).lowercased()
                #expect(!value.contains("agent"), "\(key) says agent with the agents off")
            }
        }
    }

    @Test func theLastPageSaysItsTourCanBeRunAgainFromSettings() throws {
        let english = try HangoverBrandTests.table("en")
        let line = try #require(english["onboarding.done.again"])
        #expect(line.contains("Settings, under About"))
        // The entry it names exists, in the About tab.
        let settings = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Views/SettingsView.swift")
        #expect(settings.contains("model.showWelcomeTour()"))
        #expect(settings.contains("onboarding.settings.show"))
        #expect(english["onboarding.settings.show"] == "Show the welcome tour")
    }
}
