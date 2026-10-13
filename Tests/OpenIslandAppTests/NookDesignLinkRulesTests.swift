import Foundation
import Testing
@testable import OpenIslandApp

/// What counts as a link, what a new link is called, which links are
/// Figma links, and the order the card lists them in. All of it is pure.
@Suite struct NookDesignLinkRulesTests {
    private typealias Rules = NookDesignLinkRules

    private func saved(_ text: String) -> String? {
        try? Rules.address(from: text).get().url
    }

    private func refusal(_ text: String) -> NookDesignLinkRefusal? {
        if case let .failure(reason) = Rules.address(from: text) { return reason }
        return nil
    }

    // MARK: Taken, and saved exactly as written

    @Test(arguments: [
        "https://www.figma.com/design/ABC123/My-File?node-id=12-34&t=XyZ-1#frag",
        "http://example.com", "https://example.com", "https://example.com/", "https://example.com/a/b/c.html",
        "https://example.com/path?b=2&a=1&b=3", "https://example.com/?a=1#top", "https://example.com#top",
        "https://example.com?x", "https://example.com/path#", "https://example.com/a%20b?q=%E2%9C%93",
        "https://example.com:8443/x", "https://example.com:443", "http://localhost:3000", "http://localhost",
        "http://intranet/", "https://a-b_c.example.com", "https://EXAMPLE.com/CamelCase",
    ])
    func aWebLinkIsSavedExactlyAsWritten(text: String) {
        #expect(saved(text) == text)
    }

    @Test func theQueryAndTheFragmentKeepTheirOrderAndTheirCase() {
        let text = "https://www.figma.com/design/KEY/Name?node-id=7-9&p=f&t=aBc#Frame-One"
        let address = try? Rules.address(from: text).get()
        #expect(address?.url == text)
        #expect(address?.path == "/design/KEY/Name")
        let url = Rules.openableURL(for: text)
        #expect(url?.absoluteString == text)
        #expect(url?.query == "node-id=7-9&p=f&t=aBc")
        #expect(url?.fragment == "Frame-One")
    }

    @Test(arguments: ["hTtP://example.com", "HTTP://example.com", "HTTPS://example.com/x", "hTtPs://example.com/x?Y=1"])
    func theSchemeMayBeInAnyCaseAndIsKeptAsWritten(text: String) {
        #expect(saved(text) == text)
    }

    @Test(arguments: ["  https://example.com/x  ", "\nhttps://example.com/x\n", "\t https://example.com/x \r\n", "\u{00A0}https://example.com/x\u{00A0}"])
    func theBlanksAndLineBreaksAroundALinkAreTrimmed(text: String) {
        #expect(saved(text) == "https://example.com/x")
    }

    // MARK: No scheme

    @Test func aHostWithADotGetsHttpsInFront() {
        #expect(saved("example.com") == "https://example.com")
        #expect(saved("www.example.com/a?b=1#c") == "https://www.example.com/a?b=1#c")
        #expect(saved("figma.com/design/KEY/Name?node-id=1-2") == "https://figma.com/design/KEY/Name?node-id=1-2")
        #expect(saved("example.com:8080/x") == "https://example.com:8080/x")
        #expect(saved("  example.com  ") == "https://example.com")
        #expect(saved("Example.COM/Path") == "https://Example.COM/Path")
        #expect(saved("192.168.0.1") == "https://192.168.0.1")
        #expect(saved("10.0.0.1:8080/app") == "https://10.0.0.1:8080/app")
        #expect(saved("example.com.") == "https://example.com.")
    }

    @Test(arguments: ["localhost", "localhost:3000", "intranet", "example", "figma", "hello", "a", "1.5", "3.14", "1.2.3", "10", "10:80"])
    func aBareWordOrNumberIsNotAHost(text: String) {
        #expect(refusal(text) == .notAWebLink, "\(text)")
    }

    @Test func aHostWithADotIsNeededOnlyWhenTheSchemeIsLeftOut() {
        #expect(saved("http://localhost") == "http://localhost")
        #expect(saved("https://intranet/wiki") == "https://intranet/wiki")
        #expect(refusal("localhost") == .notAWebLink)
    }

    // MARK: Hosts: addresses, ports, unicode, trailing dots

    @Test(arguments: [
        "http://192.168.0.1/", "http://192.168.0.1:3000/x", "http://10.0.0.1", "http://127.0.0.1:8080", "http://255.255.255.255/",
        "http://0.0.0.0/", "http://[::1]:8080/x", "http://[::1]/", "http://[2001:db8::1]/path", "https://[fe80::1ff:fe23:4567:890a]/",
    ])
    func anAddressIsAHost(text: String) {
        #expect(saved(text) == text)
    }

    @Test(arguments: [
        "http://999.1.1.1", "http://256.0.0.1/", "http://1.2.3/", "http://1.2.3.4.5/", "http://12345", "http://1/",
        "http://[::1", "http://[]/", "http://[zz::1]/", "http://[::1]x/", "http://[1]/", "http://[::1]:abc/", "http://::1/",
    ])
    func aBrokenAddressIsNotAHost(text: String) {
        #expect(refusal(text) == .notAWebLink, "\(text)")
    }

    @Test(arguments: [
        "https://example.com:0/", "https://example.com:1/", "https://example.com:65535/", "https://example.com:80",
    ])
    func aPortInRangeIsKept(text: String) {
        #expect(saved(text) == text)
    }

    @Test(arguments: [
        "https://example.com:", "https://example.com:/x", "https://example.com:abc/", "https://example.com:65536/",
        "https://example.com:99999", "https://example.com:123456/", "https://example.com:-1/", "https://example.com:8 0/",
        "https://example.com:80:80/", "https://:80/", "example.com:",
    ])
    func aPortOutOfRangeOrMissingIsRefused(text: String) {
        #expect(refusal(text) != nil, "\(text)")
        #expect(saved(text) == nil, "\(text)")
    }

    @Test(arguments: [
        "https://münchen.de/straße", "https://例え.jp/", "https://пример.рф/путь?q=1", "https://bücher.example/", "https://xn--mnchen-3ya.de/",
        "https://caf\u{0065}\u{0301}.example/", "https://hello.世界/",
    ])
    func aUnicodeHostIsTakenAsWritten(text: String) {
        #expect(saved(text) == text)
        #expect(Rules.openableURL(for: text) != nil)
    }

    @Test func aUnicodeHostWithNoSchemeGetsHttpsInFront() {
        #expect(saved("münchen.de") == "https://münchen.de")
        #expect(saved("例え.jp/ページ") == "https://例え.jp/ページ")
    }

    @Test(arguments: [
        "https://exa%6Dple.com", "https://example.com%2F.evil.org/", "https://exa$mple.com", "https://exa<mple.com", "https://exa(mple.com",
        "https://exa\"mple.com", "https://exa'mple.com", "https://exa;mple.com", "https://exa,mple.com", "https://exa=mple.com",
        "https://exa\\mple.com", "https://exa|mple.com", "https://exa^mple.com", "https://exa`mple.com", "https://exa{mple.com",
        "https://exa*mple.com", "https://exa!mple.com", "https://exa+mple.com", "https://exa~mple.com", "https://exa&mple.com",
        "https://exa\u{200B}mple.com", "https://exa\u{200D}mple.com", "https://exa\u{FEFF}mple.com", "https://exa\u{0007}mple.com",
        "https://exa\u{00A0}mple.com", "https://exa\u{2028}mple.com", "https://🎨.example", "https://ex😀mple.com",
    ])
    func aHostWithACharacterAHostCannotHaveIsRefused(text: String) {
        #expect(refusal(text) == .notAWebLink, "\(text)")
    }

    @Test func aTrailingDotIsKeptAndEmptyLabelsAreRefused() {
        #expect(saved("https://example.com./path") == "https://example.com./path")
        #expect(saved("http://localhost./") == "http://localhost./")
        for text in ["https://.example.com", "https://example..com", "https://.", "https://..", "https://example.com..", "http://./"] {
            #expect(refusal(text) == .notAWebLink, "\(text)")
        }
    }

    @Test func aHostMayBeAsLongAsTheRulesAllow() {
        let label = String(repeating: "a", count: 63)
        #expect(saved("https://\(label).com") != nil)
        #expect(refusal("https://\(label)a.com") == .notAWebLink)
        // Five labels of 49 and ".com" make 253 characters, the most a host may have.
        let longName = ([String](repeating: String(repeating: "b", count: 49), count: 5)).joined(separator: ".") + ".com"
        #expect(longName.count == 253)
        #expect(saved("https://\(longName)") != nil)
        #expect(refusal("https://\(longName)x") == .notAWebLink, "254 characters is one too many")
        let tooLongName = ([String](repeating: String(repeating: "b", count: 49), count: 6)).joined(separator: ".")
        #expect(tooLongName.count > 253)
        #expect(refusal("https://\(tooLongName)") == .notAWebLink)
    }

    // MARK: Other schemes and half links

    @Test(arguments: [
        "javascript:alert(1)", "JAVASCRIPT:alert(1)", "JavaScript://%0Aalert(1)", "javascript://example.com/%0Aalert(1)",
        "file:///etc/passwd", "FILE:///Users/me/x", "file://host/share", "file:/etc/passwd",
        "data:text/html,<script>alert(1)</script>", "DATA:text/plain;base64,AAAA", "mailto:a@example.com", "MAILTO:a@example.com",
        "tel:+15551234567", "sms:555", "ftp://example.com/file", "sftp://example.com", "ws://example.com", "wss://example.com",
        "about:blank", "chrome://settings", "x-apple.systempreferences:com.apple.Settings", "figma://file/KEY", "slack://open",
        "vbscript:msgbox(1)", "blob:https://example.com/1234", "view-source:https://example.com", "itms-apps://apps.apple.com/x",
    ])
    func anyOtherSchemeIsRefused(text: String) {
        #expect(refusal(text) == .notAWebLink, "\(text)")
        #expect(saved(text) == nil)
    }

    @Test(arguments: [
        "http://", "https://", "HTTP://", "http:///path", "https:///", "https://?q=1", "https://#frag", "https://:80/",
        "http:example.com", "https:example.com", "http:/example.com", "https:\\\\example.com", "http:\\example.com", "http//example.com",
        "https//example.com", "//example.com", "//example.com/path", "/design/abc", "/", "./a", "../a",
    ])
    func aSchemeWithNoHostIsRefused(text: String) {
        #expect(refusal(text) == .notAWebLink, "\(text)")
    }

    @Test(arguments: ["#", "#frag", "#section.one", "#/design/abc", "?", "?q=1", "?q=a.b", "#https://example.com", "?u=https://example.com"])
    func textThatIsOnlyAFragmentOrAQueryIsRefused(text: String) {
        #expect(refusal(text) == .notAWebLink, "\(text)")
    }

    @Test(arguments: [
        "https://user@example.com", "https://user:pass@example.com/", "http://user:@example.com", "http://:pass@example.com",
        "http://:@example.com", "https://a@b@example.com", "HTTPS://admin:hunter2@example.com:8080/x?y=1#z",
        "https://example.com@evil.example/", "https://example.com:80@evil.example/", "http://@example.com",
    ])
    func aUserNameOrPasswordIsRefused(text: String) {
        #expect(refusal(text) == .hasCredentials, "\(text)")
    }

    @Test func anAtSignAfterTheHostIsJustPartOfThePath() {
        #expect(saved("https://example.com/@user") == "https://example.com/@user")
        #expect(saved("https://example.com/path?email=a@b.com") == "https://example.com/path?email=a@b.com")
        #expect(saved("https://example.com#@x") == "https://example.com#@x")
        // An email address is not a link, and is not told it has a password.
        #expect(refusal("me@example.com") == .notAWebLink)
    }

    // MARK: Marks after a delimiter

    /// A combining mark after a slash, a question mark, a hash, an at sign or
    /// a colon joins them into one Character. The parts of an address are
    /// told apart by scalar. The mark cannot hide a delimiter.
    @Test(arguments: [
        "https://example.com/\u{0301}x", "https://example.com/a/\u{0301}", "https://example.com?\u{0301}=1", "https://example.com#\u{0301}frag",
        "https://example.com/p?q=\u{0301}#\u{0301}", "https://example.com:8080/\u{0301}", "example.com/\u{0301}x",
    ])
    func aMarkAfterADelimiterIsPartOfThePathAndTheAddressIsTaken(text: String) {
        let address = try? Rules.address(from: text).get()
        #expect(address?.host == "example.com", "\(text.debugDescription)")
        #expect(address?.url == (text.hasPrefix("https://") ? text : "https://" + text), "\(text.debugDescription)")
    }

    @Test func aMarkCannotHideTheEndOfTheHostOrAUserName() throws {
        #expect(refusal("https://user@\u{0301}evil.com") == .hasCredentials)
        #expect(refusal("https://a.com@\u{0301}b.com/") == .hasCredentials)
        #expect(refusal("https://evil.com:\u{0301}80/") == .notAWebLink)
        // A mark on the last letter of the host is a letter of the host, and the slash after it ends it.
        #expect(try Rules.address(from: "https://evil.com\u{0301}/path").get().path == "/path")
        let address = try? Rules.address(from: "https://example.com/\u{0301}x").get()
        #expect(address?.host == "example.com")
        #expect(address?.path == "/\u{0301}x")
    }

    @Test func aMarkAfterTheSlashesOfThePathDoesNotChangeWhichKindOfFigmaLinkItIs() {
        #expect(figma("https://www.figma.com/design/\u{0301}K") == NookDesignFigmaLink(kind: .design))
        #expect(name("https://example.com/a/\u{0301}b/c") == "example.com/c")
        #expect(name("https://example.com/a\u{0301}/b") == "example.com/b")
    }

    // MARK: Blanks and text inside

    @Test(arguments: ["", " ", "   ", "\n", "\t", "\r\n", " \n\t ", "\u{00A0}", "\u{2028}", "\u{200B}"])
    func emptyAndBlankTextIsRefusedAsEmpty(text: String) {
        #expect(refusal(text) == .empty, "\(text.debugDescription)")
    }

    @Test(arguments: [
        "https://exa mple.com", "https://example .com", "https:// example.com", "example .com", "two words.com", "https://example.com/a b",
        "https://example.com/a\nb", "https://example.com\nhttps://other.com", "https://example.com\thttps://other.com",
        "https://example.com/a\u{00A0}b", "https://example.com?q=a b", "https://example.com#a b", "see https://example.com",
        "https://example.com is good", "https://exa\tmple.com", "https://example.com/\u{0000}", "https://example.com/\u{001B}x",
        "https://example.com/a\u{200B}b", "https://example.com/\u{FEFF}",
    ])
    func blanksAndControlCharactersInsideAreRefused(text: String) {
        #expect(refusal(text) == .notAWebLink, "\(text.debugDescription)")
    }

    @Test(arguments: ["<https://example.com>", "\"https://example.com\"", "'https://example.com'", "(https://example.com)", "[https://example.com]", "https://example.com>"])
    func aLinkInQuotesOrBracketsIsNotCleanedUp(text: String) {
        #expect(saved(text) == nil, "\(text)")
    }

    // MARK: Length

    private func padded(to count: Int, prefix: String = "https://example.com/") -> String {
        prefix + String(repeating: "a", count: count - prefix.count)
    }

    @Test func aLinkOf2048CharactersIsTakenAndOneMoreIsRefused() {
        let limit = Rules.maxLength
        #expect(limit == 2_048)
        #expect(saved(padded(to: limit)) != nil)
        #expect(padded(to: limit).count == 2_048)
        #expect(refusal(padded(to: limit + 1)) == .tooLong)
        #expect(padded(to: limit + 1).count == 2_049)
        #expect(saved(padded(to: limit - 1)) != nil)
    }

    @Test func theBlanksAroundALongLinkDoNotCountAgainstIt() {
        let limit = Rules.maxLength
        #expect(saved("   " + padded(to: limit) + "\n\n") == padded(to: limit))
        #expect(refusal("   " + padded(to: limit + 1) + "   ") == .tooLong)
    }

    @Test func theLimitIsOnTheLinkAsSavedWhichHasHttpsInFrontWhenTheSchemeWasLeftOut() {
        let limit = Rules.maxLength
        let bare = "example.com/" + String(repeating: "a", count: limit - "https://example.com/".count)
        #expect(bare.count == limit - "https://".count)
        #expect(saved(bare)?.count == limit)
        #expect(refusal(bare + "a") == .tooLong)
    }

    @Test func aHugeTextIsRefusedAtOnceWhateverItHolds() {
        #expect(refusal(String(repeating: "x", count: 10_000)) == .tooLong)
        #expect(refusal("https://example.com/" + String(repeating: "a", count: 1_000_000)) == .tooLong)
        #expect(refusal(String(repeating: " ", count: 100_000) + "https://example.com") == .tooLong)
        #expect(refusal(String(repeating: "\u{0301}", count: 3_000)) != nil)
        // Combining marks are counted one by one, not as one letter.
        #expect(refusal("https://example.com/a" + String(repeating: "\u{0301}", count: 3_000)) == .tooLong)
    }

    @Test func aStorableAddressIsAWholeValidOneAsItIsSaved() {
        #expect(Rules.isStorable("https://example.com/x"))
        #expect(!Rules.isStorable("example.com/x"))
        #expect(!Rules.isStorable(" https://example.com/x"))
        #expect(!Rules.isStorable("https://example.com/x\n"))
        #expect(!Rules.isStorable("javascript:alert(1)"))
        #expect(!Rules.isStorable("file:///etc/passwd"))
        #expect(!Rules.isStorable(""))
        #expect(Rules.openableURL(for: "javascript:alert(1)") == nil)
        #expect(Rules.openableURL(for: "https://user:pw@example.com") == nil)
        #expect(Rules.openableURL(for: "https://example.com/x")?.absoluteString == "https://example.com/x")
    }

    // MARK: Names

    private func name(_ text: String) -> String? {
        (try? Rules.address(from: text).get()).map(Rules.defaultName(for:))
    }

    @Test func aNewLinkIsNamedAfterItsHostAndTheLastPartOfItsPath() {
        #expect(name("https://www.figma.com/design/KEY123/Brand-Kit?node-id=1-2#x") == "www.figma.com/Brand-Kit")
        #expect(name("https://example.com") == "example.com")
        #expect(name("https://example.com/") == "example.com")
        #expect(name("https://example.com/docs") == "example.com/docs")
        #expect(name("https://example.com/docs/") == "example.com/docs")
        #expect(name("https://example.com/a/b/c.html") == "example.com/c.html")
        #expect(name("https://example.com?x=/a/b") == "example.com")
        #expect(name("https://example.com#/a/b") == "example.com")
        #expect(name("https://example.com//double//slash//") == "example.com/slash")
        #expect(name("example.com/path") == "example.com/path")
        #expect(name("http://localhost:3000/app") == "localhost/app")
        #expect(name("http://[::1]:8080/x") == "[::1]/x")
        #expect(name("https://münchen.de/straße") == "münchen.de/straße")
        #expect(name("HTTPS://Example.COM/CamelCase") == "Example.COM/CamelCase")
        #expect(name("https://example.com/a%20b") == "example.com/a%20b")
    }

    @Test func aNameOf80CharactersIsKeptAndOneMoreIsCut() {
        let host = "example.com/"
        let exact = String(repeating: "n", count: Rules.maxNameLength - host.count)
        #expect(name("https://" + host + exact) == host + exact)
        #expect(name("https://" + host + exact)?.count == 80)
        #expect(name("https://" + host + exact + "n") == host + exact)
        #expect(name("https://" + host + exact + "n")?.count == 80)
        #expect(name("https://" + host + exact + "nnnnnnnnnn")?.count == 80)
    }

    @Test func aCutNeverLeavesABlankAtTheEnd() {
        #expect(Rules.cleanName(String(repeating: "a", count: 79) + " tail") == String(repeating: "a", count: 79))
        #expect(Rules.cleanName("  \(String(repeating: "b", count: 80))  ") == String(repeating: "b", count: 80))
        #expect(Rules.cleanName("Line one\r\nline two") == "Line one line two")
        #expect(Rules.cleanName("   ").isEmpty)
        #expect(Rules.cleanName("").isEmpty)
        #expect(Rules.cleanName(String(repeating: "x", count: 81)).count == 80)
    }

    @Test func aVeryLongHostIsCutInTheName() {
        let host = String(repeating: "h", count: 63) + "." + String(repeating: "i", count: 63) + ".com"
        #expect(name("https://\(host)/page")?.count == 80)
    }

    // MARK: Figma

    private func figma(_ text: String) -> NookDesignFigmaLink? {
        (try? Rules.address(from: text).get()).flatMap(Rules.figma(for:))
    }

    @Test(arguments: [
        "https://figma.com/design/KEY/Name", "https://www.figma.com/design/KEY/Name", "https://a.b.figma.com/x", "HTTPS://FIGMA.COM/x",
        "https://Www.Figma.Com/x", "https://figma.com./x", "https://www.figma.com./x", "figma.com/x", "http://figma.com:8080/x", "https://embed.figma.com/design/K",
    ])
    func figmaAndItsSubdomainsAreFigma(text: String) {
        #expect(figma(text) != nil, "\(text)")
    }

    @Test(arguments: [
        "https://notfigma.com/design/K", "https://evilfigma.com/", "https://xfigma.com/", "https://figma.com.evil.org/design/K",
        "https://www.figma.com.evil.org/", "https://figma.co/", "https://figma.community/", "https://figma-com.example/", "https://example.com/figma.com/design/K",
        "https://example.com/?u=figma.com", "https://example.com#figma.com", "https://figma/design/K", "https://sub.figmaa.com/", "https://my-figma.com/",
    ])
    func aHostThatOnlyLooksLikeFigmaIsNotFigma(text: String) {
        #expect(figma(text) == nil, "\(text)")
    }

    @Test func theKindComesFromTheStartOfThePathAndNothingElse() {
        let expected: [(String, NookDesignFigmaKind?)] = [
            ("/design/K/Name", .design), ("/file/K/Name", .file), ("/board/K/Name", .board), ("/proto/K/Name", .proto),
            ("/slides/K/Name", .slides), ("/make/K/Name", .make), ("/design/", .design),
            ("/design", nil), ("/Design/K", nil), ("/DESIGN/K", nil), ("/designs/K", nil), ("/files/K", nil),
            ("/community/file/123", nil), ("/", nil), ("", nil), ("/x/design/K", nil), ("//design/K", nil),
            ("/files", nil), ("/board", nil), ("/boards/K", nil), ("/prototype/K", nil),
        ]
        for (path, kind) in expected {
            #expect(figma("https://www.figma.com" + path) == NookDesignFigmaLink(kind: kind), "\(path)")
        }
    }

    @Test func theQueryAndTheFragmentNeverChooseTheKind() {
        #expect(figma("https://www.figma.com/?next=/design/K") == NookDesignFigmaLink(kind: nil))
        #expect(figma("https://www.figma.com#/design/K") == NookDesignFigmaLink(kind: nil))
        #expect(figma("https://www.figma.com/design/K?next=/board/K#/proto/K") == NookDesignFigmaLink(kind: .design))
    }

    @Test func everyKindHasAPrefixAndAnEnglishNameKey() {
        #expect(NookDesignFigmaKind.allCases.map(\.pathPrefix) == ["/design/", "/file/", "/board/", "/proto/", "/slides/", "/make/"])
        #expect(Set(NookDesignFigmaKind.allCases.map(\.titleKey)).count == NookDesignFigmaKind.allCases.count)
    }

    // MARK: Order

    private let day = Date(timeIntervalSince1970: 1_800_000_000)

    private func link(
        _ name: String, added: Double, opened: Double? = nil, favorite: Bool = false
    ) -> NookDesignLink {
        NookDesignLink(
            id: UUID(), url: "https://example.com/\(name)", name: name, collectionID: nil, isFavorite: favorite,
            addedAt: day.addingTimeInterval(added), lastOpenedAt: opened.map { day.addingTimeInterval($0) }
        )
    }

    private func names(_ links: [NookDesignLink]) -> [String] { Rules.ordered(links).map(\.name) }

    @Test func favoritesComeFirstAndTheRestFollowByTheirLatestMoment() {
        let links = [
            link("old", added: 1), link("fav-old", added: 2, favorite: true), link("new", added: 30),
            link("opened-late", added: 3, opened: 90), link("fav-new", added: 40, favorite: true),
        ]
        #expect(names(links) == ["fav-new", "fav-old", "opened-late", "new", "old"])
    }

    @Test func openingALinkMovesItUpAmongItsOwnGroupOnly() {
        let links = [link("a", added: 1), link("b", added: 2), link("c", added: 3, favorite: true), link("d", added: 4, favorite: true)]
        #expect(names(links) == ["d", "c", "b", "a"])
        let opened = [link("a", added: 1, opened: 100), link("b", added: 2), link("c", added: 3, favorite: true), link("d", added: 4, opened: 5, favorite: true)]
        #expect(names(opened) == ["d", "c", "a", "b"])
        let favoriteOpened = [link("a", added: 1), link("b", added: 2), link("c", added: 3, opened: 50, favorite: true), link("d", added: 4, favorite: true)]
        #expect(names(favoriteOpened) == ["c", "d", "b", "a"])
    }

    @Test func tiesGoByWhenTheyWereAddedThenByTheirPlaceInTheList() {
        // The same moment: the one added later is first.
        #expect(names([link("a", added: 5, opened: 50), link("b", added: 9, opened: 50)]) == ["b", "a"])
        // The same moment and the same day added: the list's own order stays.
        let first = link("a", added: 5)
        var second = link("b", added: 5)
        second.url = "https://example.com/b"
        #expect(Rules.ordered([first, second]).map(\.id) == [first.id, second.id])
        #expect(Rules.ordered([second, first]).map(\.id) == [second.id, first.id])
        // A link opened exactly when another was added ties with it.
        #expect(names([link("added", added: 50), link("opened", added: 10, opened: 50)]) == ["added", "opened"])
    }

    @Test func aLinkOpenedBeforeItWasAddedIsTakenAtWhenItWasAdded() {
        let odd = link("odd", added: 80, opened: 10)
        #expect(odd.recency == day.addingTimeInterval(80))
        #expect(names([link("other", added: 50), odd]) == ["odd", "other"])
    }

    @Test func noLinksOneLinkAndAllEqualLinksKeepTheirOrder() {
        #expect(Rules.ordered([]).isEmpty)
        let one = link("a", added: 1)
        #expect(Rules.ordered([one]) == [one])
        let same = (0..<10).map { index -> NookDesignLink in
            var made = link("l\(index)", added: 7)
            made.name = "l\(index)"
            return made
        }
        #expect(Rules.ordered(same) == same)
        #expect(Rules.ordered(Rules.ordered(same)) == Rules.ordered(same))
    }

    @Test func theSortIsStableForAHundredLinksOfFewMoments() {
        var links: [NookDesignLink] = []
        for index in 0..<100 {
            let opened: Double? = index % 5 == 0 ? Double(index % 4) : nil
            links.append(link("l\(index)", added: Double(index % 3), opened: opened, favorite: index % 7 == 0))
        }
        let ordered: [NookDesignLink] = Rules.ordered(links)
        #expect(ordered.count == 100)
        #expect(Set(ordered.map(\.id)) == Set(links.map(\.id)))
        let favorites = ordered.prefix { $0.isFavorite }
        #expect(favorites.count == links.filter(\.isFavorite).count)
        for (a, b) in zip(ordered, ordered.dropFirst()) where a.isFavorite == b.isFavorite {
            #expect(a.recency >= b.recency)
        }
    }
}
