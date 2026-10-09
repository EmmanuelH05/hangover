import Foundation
import Testing
@testable import OpenIslandApp

/// The name a user reads is Hangover. The upstream name may appear only
/// where the app credits the project it is based on.
struct HangoverBrandTests {
    static let languages: [String] = ["en", "zh-Hans", "zh-Hant"]

    /// Keys whose text names the upstream project on purpose.
    static let creditKeys: Set<String> = ["settings.about.credit", "settings.about.upstream"]

    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func table(_ language: String) throws -> [String: String] {
        let url = repoRoot.appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
        return try #require(NSDictionary(contentsOf: url) as? [String: String], "\(language) did not load")
    }

    static func text(of file: String) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(file), encoding: .utf8)
    }

    @Test func theAppIsCalledHangoverInEveryLanguage() throws {
        let expected: String = "Hangover"
        #expect(AppBrand.name == expected)
        for language in Self.languages {
            let table = try Self.table(language)
            #expect(table["app.name"] == expected, "\(language) names the app \(table["app.name"] ?? "nothing")")
        }
    }

    @Test func noStringNamesTheUpstreamAppOutsideTheCredit() throws {
        let upstream: String = "open island"
        // "the open island" is the island while it is open, not a name.
        let plainWords: Set<String> = ["onboarding.done.where"]
        for language in Self.languages {
            let table = try Self.table(language)
            let named = table
                .filter { $0.value.lowercased().contains(upstream) }
                .map(\.key)
                .filter { !Self.creditKeys.contains($0) && !plainWords.contains($0) }
                .sorted()
            let none: [String] = []
            #expect(named == none, "\(language) still says Open Island in \(named)")
        }
    }

    @Test func theSettingsWindowAndThePhotoFolderCarryTheName() {
        let title: String = "Hangover Settings"
        let folder: String = "Hangover Photo Booth"
        #expect(AppBrand.settingsWindowTitle == title)
        #expect(NookPhotoBoothStore.folderName == folder)
    }

    // MARK: Credit and license

    @Test func theAboutPaneCreditsTheUpstreamProjectAndNamesTheLicenseInEveryLanguage() throws {
        let licenseWords: [String: String] = [
            "en": "GNU General Public License, version 3",
            "zh-Hans": "GNU 通用公共许可证第 3 版",
            "zh-Hant": "GNU 通用公共授權條款第 3 版",
        ]
        for language in Self.languages {
            let table = try Self.table(language)
            let credit = try #require(table["settings.about.credit"], "\(language) has no credit")
            #expect(credit.contains(AppBrand.name), "\(language) credit does not name Hangover")
            #expect(credit.contains(AppBrand.upstreamName), "\(language) credit does not name Open Island")
            #expect(credit.contains(try #require(licenseWords[language])), "\(language) credit does not name the license")
            for key in ["settings.about.sourceCode", "settings.about.license", "settings.about.upstream"] {
                #expect(!(table[key] ?? "").isEmpty, "\(language) is missing \(key)")
            }
        }
    }

    @Test func theLinksLeadToHangoverAndTheCreditToUpstream() {
        let source: String = "https://github.com/EmmanuelH05/hangover"
        let releases: String = "https://github.com/EmmanuelH05/hangover/releases"
        let upstream: String = "https://github.com/Octane0411/open-vibe-island"
        let license: String = "https://www.gnu.org/licenses/gpl-3.0.html"
        #expect(AppBrand.sourceCodeURL.absoluteString == source)
        #expect(AppBrand.releasesURL.absoluteString == releases)
        #expect(AppBrand.upstreamURL.absoluteString == upstream)
        #expect(AppBrand.licenseWebURL.absoluteString == license)
    }

    @Test func theLicenseRowOpensTheCopyInTheAppWhenThereIsOne() {
        let copy = URL(fileURLWithPath: "/Applications/Sample.app/Contents/Resources/LICENSE.txt")
        #expect(AppBrand.licenseURL(bundledCopy: copy) == copy)
        #expect(AppBrand.licenseURL(bundledCopy: nil) == AppBrand.licenseWebURL)
    }

    @Test func theLicenseAndTheNoticeShipWithTheSourceAndThePackage() throws {
        let license = try Self.text(of: "LICENSE")
        #expect(license.contains("GNU GENERAL PUBLIC LICENSE"))
        #expect(license.contains("Version 3, 29 June 2007"))

        let notice = try Self.text(of: "NOTICE.md")
        #expect(notice.contains(AppBrand.upstreamName))
        #expect(notice.contains(AppBrand.upstreamURL.absoluteString))
        #expect(notice.contains(AppBrand.sourceCodeURL.absoluteString))
        #expect(notice.contains("has been changed"))
        #expect(notice.contains("GNU General Public License"))

        // The package script puts both in the bundle, under the name the
        // About pane looks for.
        let script = try Self.text(of: "scripts/package-app.sh")
        #expect(script.contains("Contents/Resources/\(AppBrand.bundledLicenseFileName)"))
        #expect(script.contains("Contents/Resources/NOTICE.md"))
    }
}
