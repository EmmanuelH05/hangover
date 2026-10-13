import Foundation
import Testing
@testable import OpenIslandApp

// The link rule: `http` or `https` with a host, at most 2,048 characters,
// no spaces or control characters, no user or password. Everything else is
// refused with a reason, and only a link that passed can reach `yt-dlp`.

@Suite struct NookLinkAudioLinkTests {
    private func accepted(_ text: String) -> String? {
        if case let .success(link) = NookLinkAudioLink.check(text) { return link.text }
        return nil
    }

    private func refusal(_ text: String) -> NookLinkAudioLinkRefusal? {
        if case let .failure(reason) = NookLinkAudioLink.check(text) { return reason }
        return nil
    }

    // MARK: Taken

    @Test(arguments: [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "http://example.com",
        "https://example.com/",
        "https://soundcloud.com/artist/track-name?si=abc#t=30",
        "HTTPS://EXAMPLE.COM/Path",
        "Http://example.com",
        "https://example.com:8080/a",
        "https://localhost:3000/x",
        "https://192.168.0.1/audio.mp3",
        "https://[2001:db8::1]/a",
        "https://[2001:db8::1]:8443/a",
        "https://bücher.de/hörbuch",
        "https://例え.jp/音楽",
        "https://sub.domain.example.co.uk./a",
        "https://my_host.example.com/a",
        "https://www.youtube.com/@channel",
        "https://example.com/p?email=a@b.com",
        "https://example.com/a#frag@x",
        "https://example.com/a;b=$(c)&d=`e`",
    ])
    func aWebLinkIsTakenAsItIs(_ text: String) {
        #expect(accepted(text) == text)
    }

    @Test func blanksAroundALinkAreTrimmedAndNothingElseIsChanged() {
        #expect(accepted("  https://example.com/a?b=1&c=2  ") == "https://example.com/a?b=1&c=2")
        #expect(accepted("\nhttps://example.com/a\n") == "https://example.com/a")
        #expect(accepted("\t https://example.com/a \r\n") == "https://example.com/a")
    }

    // MARK: Length

    @Test func theLimitIsTwoThousandAndFortyEightCharacters() {
        let head = "https://example.com/"
        let exact = head + String(repeating: "a", count: 2_048 - head.count)
        let over = exact + "a"
        #expect(exact.count == 2_048)
        #expect(accepted(exact) == exact)
        #expect(refusal(over) == .tooLong)
    }

    @Test func theLimitCountsScalarsAndCombiningMarksDoNotHideLength() {
        let head = "https://example.com/"
        let marks = String(repeating: "e\u{0301}", count: 1_100)
        #expect((head + marks).count < 2_048)
        #expect((head + marks).unicodeScalars.count > 2_048)
        #expect(refusal(head + marks) == .tooLong)
    }

    @Test func aHugeTextIsRefusedBeforeItIsScanned() {
        let huge = "https://example.com/" + String(repeating: "a", count: NookLinkAudioLink.maxInputBytes)
        #expect(refusal(huge) == .tooLong)
    }

    // MARK: Empty

    @Test(arguments: ["", " ", "   \n\t  ", "\u{00A0}"])
    func nothingIsRefusedAsEmpty(_ text: String) {
        #expect(refusal(text) == .empty)
    }

    // MARK: Not a web link

    @Test(arguments: [
        "example.com",
        "www.example.com/watch",
        "//example.com/a",
        "ftp://example.com/a.mp3",
        "file:///etc/passwd",
        "javascript:alert(1)",
        "data:text/html,hello",
        "mailto:a@b.com",
        "ssh://example.com",
        "http:/example.com",
        "http:example.com",
        "http://",
        "https://",
        "https:///path",
        "https://?x=1",
        "https://#frag",
        "https://:80/a",
        "https://exa<mple.com/a",
        "https://exa%6Dple.com/a",
        "https://exa\\mple.com/a",
        "https://example.com:99999/a",
        "https://example.com:port/a",
        "https://example.com:/a:",
        "https://[not-an-address]/a",
        "https://[2001:db8::1/a",
        "https://..com/a",
        "hello world",
        "not a link at all",
    ])
    func anythingButAWebLinkIsRefused(_ text: String) {
        #expect(refusal(text) != nil, "\(text) was taken")
    }

    // MARK: Dashes

    @Test(arguments: [
        "-x",
        "--exec=touch /tmp/x",
        "-o /tmp/evil",
        "--config-location /tmp/c",
        "--",
        "-",
        "  --exec x",
        "-https://example.com",
        "--proxy=https://example.com",
        "-\u{200B}-exec",
    ])
    func textThatStartsWithADashIsRefusedBeforeItCouldBeReadAsAnOption(_ text: String) {
        #expect(refusal(text) != nil, "\(text) was taken")
        #expect(accepted(text) == nil)
    }

    @Test func aLinkWithADashLaterOnIsFine() {
        #expect(accepted("https://example.com/-x") == "https://example.com/-x")
        #expect(accepted("https://ex-ample.com/--a?b=-c") == "https://ex-ample.com/--a?b=-c")
    }

    // MARK: Blanks and control characters

    @Test(arguments: [
        "https://example.com/a b",
        "https://exa mple.com",
        "https://example.com/a\tb",
        "https://example.com/a\nb",
        "https://example.com/a\rb",
        "https://example.com/a\u{0000}b",
        "https://example.com/a\u{0007}b",
        "https://example.com/a\u{001B}[0m",
        "https://example.com/a\u{007F}b",
        "https://example.com/a\u{00A0}b",
        "https://example.com/a\u{200B}b",
        "https://example.com/a\u{202E}b",
        "https://example.com/a\u{2028}b",
        "https://example.com/a\u{FEFF}b",
        "https://example.com/a\u{E000}b",
        "https://example.com\nhttps://other.com",
    ])
    func aBlankOrAControlCharacterInsideIsRefused(_ text: String) {
        #expect(refusal(text) == .hasBlankOrControl, "\(text.debugDescription)")
    }

    // MARK: Credentials

    @Test(arguments: [
        "https://user@example.com/a",
        "https://user:pass@example.com/a",
        "https://:pass@example.com/a",
        "https://@example.com/a",
        "http://a@b@example.com",
        "https://example.com@evil.com/a",
        "https://example.com\\@evil.com/a",
        "https://user@[2001:db8::1]/a",
    ])
    func aUserOrPasswordInFrontOfTheHostIsRefused(_ text: String) {
        #expect(refusal(text) == .hasCredentials, "\(text)")
    }

    // MARK: The reason

    @Test func eachReasonHasALineToShow() {
        let reasons: [NookLinkAudioLinkRefusal] = [.empty, .tooLong, .notAWebLink, .hasBlankOrControl, .hasCredentials]
        #expect(Set(reasons.map(\.noticeKey)).count == reasons.count)
        for reason in reasons {
            #expect(LanguageManager.shared.t(reason.noticeKey) != reason.noticeKey)
        }
    }

    @Test func theFirstThingWrongIsTheReasonGiven() {
        #expect(refusal("hello world") == .notAWebLink, "not a link comes before a space")
        #expect(refusal("https://user@example.com/a b") == .hasBlankOrControl)
        #expect(refusal("ftp://user@example.com") == .notAWebLink)
    }
}
