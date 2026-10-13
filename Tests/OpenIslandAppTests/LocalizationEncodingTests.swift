import Foundation
import Testing

/// The three `.strings` files hold the text they mean to hold. A line that
/// was read as Latin-1 and written back as UTF-8 still parses and still
/// passes the key checks, and shows garbage in the app: three lines of the
/// tour's widgets page shipped that way in both Chinese files.
@Suite struct LocalizationEncodingTests {
    private static let languages = ["en", "zh-Hans", "zh-Hant"]

    private static func text(of language: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Every line number that holds a character from `range`.
    private static func lines(of text: String, holding range: ClosedRange<UInt32>) -> [Int] {
        text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { index, line in
            line.unicodeScalars.contains { range.contains($0.value) } ? index + 1 : nil
        }
    }

    @Test func noFileHoldsTheControlCharactersADoubleEncodingLeaves() throws {
        // Text encoded twice always carries characters from U+0080 to U+009F,
        // which no language here uses.
        for language in Self.languages {
            let found = Self.lines(of: try Self.text(of: language), holding: 0x80...0x9F)
            #expect(found.isEmpty, "\(language): lines \(found) look encoded twice")
        }
    }

    @Test func theChineseFilesHoldNoAccentedLatinLetters() throws {
        // Chinese text encoded twice turns into runs of letters such as the
        // ones from U+00C0 to U+00FF. Neither Chinese file has a use for them.
        for language in ["zh-Hans", "zh-Hant"] {
            let found = Self.lines(of: try Self.text(of: language), holding: 0xC0...0xFF)
            #expect(found.isEmpty, "\(language): lines \(found) look encoded twice")
        }
    }
}
