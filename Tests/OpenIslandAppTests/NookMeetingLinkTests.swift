import AppKit
import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Joining a meeting from the island: which text in an event counts as a
/// meeting link, when the Join bar offers it, and what Join opens. Nothing
/// here opens a real link; every open goes to a recorder.
@Suite struct NookMeetingLinkTests {
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)
    private static let zoom = URL(string: "https://ucla.zoom.us/j/93812345678")!

    private static func event(
        _ id: String = "standup",
        startsIn offset: TimeInterval = 0,
        length: TimeInterval = 3600,
        link: URL? = zoom,
        isAllDay: Bool = false
    ) -> NookCalendarEvent {
        let begins = start.addingTimeInterval(offset)
        return NookCalendarEvent(
            id: id,
            title: "Standup",
            start: begins,
            end: begins.addingTimeInterval(length),
            isAllDay: isAllDay,
            calendarColor: .blue,
            location: nil,
            meetingURL: link
        )
    }

    // MARK: Finding a link

    @Test(arguments: [
        ("https://zoom.us/j/93812345678", "zoom.us"),
        ("https://ucla.zoom.us/j/93812345678?pwd=QWxhZGRpbjpvcGVu", "ucla.zoom.us"),
        ("https://us02web.zoom.us/my/standup.room", "us02web.zoom.us"),
        ("https://meet.google.com/abc-defg-hij", "meet.google.com"),
        ("https://teams.microsoft.com/l/meetup-join/19%3ameeting_NjA5%40thread.v2/0?context=%7b%22Tid%22%3a%221%22%7d", "teams.microsoft.com"),
        ("https://teams.live.com/meet/9312345678901", "teams.live.com"),
        ("https://acme.webex.com/meet/someone", "acme.webex.com"),
        ("https://acme.webex.com/acme/j.php?MTID=m0123456789abcdef", "acme.webex.com"),
        ("https://facetime.apple.com/join#v=1&p=AbCdEf&k=GhIjKl", "facetime.apple.com"),
    ])
    func aRealLinkOfEachServiceIsFound(text: String, host: String) throws {
        let url = try #require(NookMeetingLink.find(in: [text]))

        #expect(url.host == host)
        #expect(url.scheme == "https")
        #expect(NookMeetingLink.isAllowed(url))
    }

    @Test func aLinkBuriedInNotesIsFoundWithoutThePunctuationAroundIt() {
        let notes = """
        Agenda is attached, see you there.

        Join Zoom Meeting
        https://ucla.zoom.us/j/93812345678?pwd=abc123.
        Meeting ID: 938 1234 5678
        """
        let bracketed = "Dial in: <https://meet.google.com/abc-defg-hij>, or come to Royce 190"

        #expect(NookMeetingLink.find(in: [nil, "Royce 190", notes])?.absoluteString
            == "https://ucla.zoom.us/j/93812345678?pwd=abc123")
        #expect(NookMeetingLink.find(in: [bracketed])?.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test func theFirstFieldWithALinkWins() {
        let found = NookMeetingLink.find(in: [
            "https://example.com/agenda",
            "https://meet.google.com/abc-defg-hij",
            "Backup room: https://zoom.us/j/111222333",
        ])

        #expect(found?.host == "meet.google.com")
    }

    @Test(arguments: [
        "https://example.com/agenda",
        "https://docs.google.com/document/d/1AbC/edit",
        "Room 4, Boelter Hall",
        "https://google.com/meet",
        "zoom at noon",
        // The service's front page is not a meeting.
        "https://zoom.us",
        "https://zoom.us/",
        "https://meet.google.com",
        "",
    ])
    func anOrdinaryLinkOrPlainTextIsNotAMeeting(text: String) {
        #expect(NookMeetingLink.find(in: [text]) == nil)
    }

    @Test(arguments: [
        "https://zoom.us.evil.example/j/93812345678",
        "https://evilzoom.us/j/93812345678",
        "https://meet.google.com.evil.example/abc-defg-hij",
        "https://teams.microsoft.com.evil.example/l/meetup-join/1",
        "https://zoom.us@evil.example/j/93812345678",
        "https://evil.example/zoom.us/j/93812345678",
        "https://evil.example/?next=https://zoom.us/j/93812345678",
        "https://user:secret@zoom.us/j/93812345678",
        "ftp://zoom.us/j/93812345678",
    ])
    func aLookAlikeHostGetsNoButton(text: String) {
        #expect(NookMeetingLink.find(in: [text]) == nil)
    }

    @Test(arguments: [
        "javascript:alert('zoom.us/j/1')",
        "file:///Users/someone/zoom.us/j/1",
        "evilapp://zoom.us/join?confno=1",
        "x-apple.systempreferences:com.apple.preference.security zoom.us",
        "zoommtg://zoom.us/join?confno=1 then run file:///bin/sh",
        "data:text/html,<script>location='https://zoom.us/j/1'</script>",
        "msteams-evil:/l/meetup-join/1 teams.microsoft.com",
    ])
    func whateverIsFoundInHostileTextIsAlwaysSafeToOpen(text: String) {
        guard let url = NookMeetingLink.find(in: [text]) else { return }
        let scheme = url.scheme?.lowercased() ?? ""

        #expect(NookMeetingLink.isAllowed(url))
        #expect(scheme == "https" || NookMeetingLink.appSchemes.contains(scheme))
    }

    @Test func aPlainHttpOrBareLinkToAMeetingServiceComesBackAsHttps() {
        #expect(NookMeetingLink.find(in: ["http://zoom.us/j/93812345678"])?.absoluteString
            == "https://zoom.us/j/93812345678")
        #expect(NookMeetingLink.find(in: ["Join at zoom.us/j/93812345678 today"])?.absoluteString
            == "https://zoom.us/j/93812345678")
    }

    @Test func aKnownMeetingAppLinkIsFound() {
        let zoomApp = NookMeetingLink.find(in: ["Open zoommtg://zoom.us/join?confno=93812345678&pwd=abc."])
        let teamsApp = NookMeetingLink.find(in: ["msteams:/l/meetup-join/19:meeting_NjA5@thread.v2/0"])

        #expect(zoomApp?.absoluteString == "zoommtg://zoom.us/join?confno=93812345678&pwd=abc")
        #expect(teamsApp?.scheme == "msteams")
    }

    @Test(arguments: [
        "zoommtg://zoom.us/join?confno=93812345678&pwd=abc",
        "zoommtg://ucla.zoom.us/join?action=join&confno=93812345678",
        "zoomus://zoom.us/join?confno=93812345678",
        "zoommtg://www.zoomgov.com/join?confno=1601234567",
        "ZOOMMTG://Zoom.US/join?confno=93812345678",
        "msteams:/l/meetup-join/19:meeting_NjA5@thread.v2/0",
        "msteams://teams.microsoft.com/l/meetup-join/19%3ameeting_NjA5%40thread.v2/0?context=%7b%22Tid%22%3a%221%22%7d",
        "msteams://teams.live.com/l/meetup-join/9312345678901",
    ])
    func aMeetingAppLinkThatOnlyJoinsIsFoundAndOpened(text: String) throws {
        let found = try #require(NookMeetingLink.find(in: ["Join here: \(text) and bring notes"]))
        var opened: [URL] = []

        #expect(found.absoluteString == text)
        #expect(NookMeetingLink.open(found, using: { opened.append($0) }))
        #expect(opened == [found])
    }

    /// The scheme of a meeting app is not enough. These all carry one, and
    /// none of them is a plain join: another host, a call or a chat, or a
    /// path that is not the join path.
    @Test(arguments: [
        "zoommtg://evil.example/join?confno=1&pwd=x&zc=0&uname=victim",
        "msteams:/l/call/0/0?users=attacker@evil.example",
        "msteams:/l/chat/0/0?users=attacker@evil.example&message=hello",
        "zoomus://anything.at.all/whatever?x=...",
        "zoommtg://evil.example/join?confno=1",
        "zoommtg://user@evil.example/join?confno=1",
        "zoommtg:join?confno=1",
        "zoomus:///join?confno=1",
        "msteams:/l/meetup-join/",
        "msteams:/l/meetup-join/../chat/0/0?users=attacker@evil.example",
        "msteams:/l/meetup-join/%2e%2e/chat/0/0?users=attacker@evil.example",
        "msteams:/l/meetup-join/%2E%2E/call/0/0",
        "msteams:/l/meetup-join/a/./../../chat/0/0",
        "msteams:/l/%6deetup-join/19:meeting_NjA5@thread.v2/0",
        "msteams:/l/app/00000000-0000-0000-0000-000000000000",
        "msteams:/l/file/00000000?fileType=docx",
        "msteams:l/meetup-join/19:meeting_NjA5@thread.v2/0",
        "msteams://evil.example/l/meetup-join/19:meeting_NjA5@thread.v2/0",
    ])
    func aMeetingAppLinkThatIsNotAPlainJoinIsRefused(text: String) throws {
        let url = try #require(URL(string: text))
        var opened: [URL] = []

        #expect(NookMeetingLink.find(in: [text]) == nil)
        #expect(NookMeetingLink.safeURL(from: url) == nil)
        #expect(!NookMeetingLink.open(url, using: { opened.append($0) }))
        #expect(opened.isEmpty)
    }

    /// The same, for links whose text also holds a real meeting host. The
    /// app link itself is never opened. Whatever else is found in the text
    /// has to stand as a meeting link in its own right.
    @Test(arguments: [
        "zoommtg://zoom.us.evil.example/join?confno=1",
        "zoommtg://zoom.us%2f.evil.example/join?confno=1",
        "zoommtg://evil.example%2f.zoom.us/join?confno=1",
        "zoommtg://user@zoom.us/join?confno=1",
        "zoommtg://user:secret@zoom.us/join?confno=1",
        "zoommtg://zoom.us:8443/join?confno=1",
        "zoommtg://zoom.us/start?confno=1",
        "zoommtg://zoom.us/%6aoin?confno=1",
        "zoommtg://zoom.us/join/../start?confno=1",
        "zoommtg://zoom.us/join/extra?confno=1",
        "zoommtg://zoom.us?confno=1",
        "zoomus://teams.microsoft.com/join?confno=1",
        "msteams://zoom.us/l/meetup-join/19:meeting_NjA5@thread.v2/0",
        "msteams://teams.microsoft.com.evil.example/l/meetup-join/1",
        "msteams://teams.microsoft.com/l/call/0/0?users=attacker@evil.example",
        "msteams://teams.microsoft.com/l/meetup-join/../chat/0/0",
    ])
    func aCraftedAppLinkBesideARealHostNameIsNeverOpened(text: String) throws {
        let url = try #require(URL(string: text))
        var opened: [URL] = []

        #expect(NookMeetingLink.safeURL(from: url) == nil)
        #expect(!NookMeetingLink.open(url, using: { opened.append($0) }))
        #expect(opened.isEmpty)
        if let found = NookMeetingLink.find(in: [text]) {
            #expect(found != url)
            #expect(found.scheme == "https")
            #expect(NookMeetingLink.isAllowed(found))
        }
    }

    /// A host is read as it was written. "evil.example%2f.zoom.us" decodes
    /// to a name that ends in ".zoom.us" and is still not Zoom's.
    @Test(arguments: ["%2f", "%5c", "%23", "%3f", "%00", "%09", "%20", "%2F", "%40", "%2e", "%25"])
    func aPercentEncodedHostIsNeverAMeetingHost(escape: String) throws {
        let text = "https://evil.example\(escape).zoom.us/j/93812345678"
        let url = try #require(URL(string: text))
        var opened: [URL] = []

        #expect(NookMeetingLink.find(in: [text]) == nil)
        #expect(NookMeetingLink.find(in: ["Join at \(text) today"]) == nil)
        #expect(NookMeetingLink.safeURL(from: url) == nil)
        #expect(!NookMeetingLink.open(url, using: { opened.append($0) }))
        #expect(opened.isEmpty)
    }

    @Test(arguments: [
        "https://zoom.us./j/93812345678",
        "https://zoom_us.zoom.us/j/93812345678",
        "https://xn--zom-sed.us/j/93812345678",
        "https://[::1]/zoom.us/j/93812345678",
    ])
    func aHostThatIsNotPlainLettersDigitsDotsAndHyphensOnAKnownNameIsRefused(text: String) throws {
        let url = try #require(URL(string: text))

        #expect(NookMeetingLink.safeURL(from: url) == nil)
    }

    // MARK: Opening

    @Test func onlyAKnownMeetingLinkIsEverOpened() throws {
        var opened: [URL] = []
        let good = try #require(URL(string: "https://ucla.zoom.us/j/93812345678"))
        let appLink = try #require(URL(string: "zoommtg://zoom.us/join?confno=1"))
        let refused = [
            "http://zoom.us/j/93812345678",
            "https://example.com/j/93812345678",
            "https://zoom.us.evil.example/j/1",
            "file:///Applications/Calculator.app",
            "x-apple.systempreferences:com.apple.preference.security",
        ]

        let openedGood = NookMeetingLink.open(good, using: { opened.append($0) })
        let openedAppLink = NookMeetingLink.open(appLink, using: { opened.append($0) })
        #expect(openedGood)
        #expect(openedAppLink)
        for text in refused {
            let url = try #require(URL(string: text))
            let openedRefused = NookMeetingLink.open(url, using: { opened.append($0) })
            #expect(!openedRefused, "\(text) was opened")
        }

        #expect(opened == [good, appLink])
    }

    // MARK: When the Join bar shows

    @Test(arguments: [
        (-660.0, false),   // eleven minutes ahead
        (-600.0, true),    // ten minutes ahead: the first notice
        (-60.0, true),
        (0.0, true),
        (840.0, true),     // fourteen minutes in
        (900.0, false),    // fifteen minutes in: the row keeps its mark
        (10_800.0, false),
    ] as [(TimeInterval, Bool)])
    func theJoinBarShowsFromTenMinutesBeforeToFifteenMinutesIn(sinceStart: TimeInterval, shows: Bool) {
        let meeting = Self.event()
        let now = Self.start.addingTimeInterval(sinceStart)

        #expect(NookMeetingPrompt.isOpen(for: meeting, now: now) == shows)
    }

    @Test func aShortMeetingStopsBeingOfferedWhenItEnds() {
        let short = Self.event(length: 10 * 60)
        let noLength = Self.event(length: 0)

        #expect(NookMeetingPrompt.isOpen(for: short, now: Self.start.addingTimeInterval(9 * 60)))
        #expect(!NookMeetingPrompt.isOpen(for: short, now: Self.start.addingTimeInterval(10 * 60)))
        // An event with no length still gets the late window.
        #expect(NookMeetingPrompt.isOpen(for: noLength, now: Self.start.addingTimeInterval(5 * 60)))
    }

    @Test func eventsWithoutALinkAndAllDayEventsAreNeverOffered() {
        let noLink = Self.event(link: nil)
        let allDay = Self.event(isAllDay: true)

        #expect(NookMeetingPrompt.current(events: [noLink, allDay], now: Self.start) == nil)
    }

    @Test func theEarliestOpenMeetingIsOfferedAndAPutAwayOneIsSkipped() {
        let first = Self.event("first", startsIn: -5 * 60)
        let second = Self.event("second", startsIn: 4 * 60)
        let later = Self.event("later", startsIn: 3 * 3600)

        #expect(NookMeetingPrompt.current(events: [later, second, first], now: Self.start)?.id == "first")
        #expect(NookMeetingPrompt.current(events: [later, second, first], now: Self.start, dismissed: ["first"])?.id
            == "second")
        #expect(NookMeetingPrompt.current(
            events: [later, second, first], now: Self.start, dismissed: ["first", "second"]
        ) == nil)
    }

    @Test(arguments: [(90.0, 2), (60.0, 1), (1.0, 1), (0.0, 0), (-30.0, 0), (-90.0, -1), (-180.0, -3)])
    func minutesToTheStartRoundTowardTheStart(secondsAhead: TimeInterval, expected: Int) {
        let minutes = NookMeetingPrompt.minutesUntilStart(Self.start.addingTimeInterval(secondsAhead), now: Self.start)

        #expect(minutes == expected)
    }

    @Test func theBarSaysWhenInWords() {
        let lang = LanguageManager.shared
        let ahead = NookJoinText.when(start: Self.start.addingTimeInterval(4 * 60), now: Self.start)
        let now = NookJoinText.when(start: Self.start, now: Self.start.addingTimeInterval(20))
        let late = NookJoinText.when(start: Self.start, now: Self.start.addingTimeInterval(3 * 60 + 5))

        #expect(ahead == lang.t("nook.calendar.join.in", 4))
        #expect(now == lang.t("nook.calendar.join.now"))
        #expect(late == lang.t("nook.calendar.join.ago", 3))
    }

    // MARK: On the model

    @Test @MainActor func joiningOpensTheLinkOnceAndPutsTheBarAway() {
        let nook = NookModel()
        var opened: [URL] = []
        var resizes = 0
        nook.openURL = { opened.append($0) }
        nook.onDisplayPreferencesChanged = { resizes += 1 }
        let meeting = Self.event()

        nook.refreshMeetingPrompt(now: Self.start, events: [meeting])
        #expect(nook.meetingPrompt?.id == meeting.id)
        // The bar appearing resizes the island once. Asking again does not.
        nook.refreshMeetingPrompt(now: Self.start.addingTimeInterval(60), events: [meeting])
        #expect(resizes == 1)

        nook.joinMeeting(meeting)
        #expect(opened == [Self.zoom])
        #expect(nook.meetingPrompt == nil)
        #expect(resizes == 2)

        // The next minute's tick does not bring it back.
        nook.refreshMeetingPrompt(now: Self.start.addingTimeInterval(120), events: [meeting])
        #expect(nook.meetingPrompt == nil)
    }

    @Test @MainActor func puttingTheBarAwayOpensNothingAndOffersTheNextMeeting() {
        let nook = NookModel()
        var opened: [URL] = []
        nook.openURL = { opened.append($0) }
        let first = Self.event("first", startsIn: -60)
        let second = Self.event("second", startsIn: 5 * 60)

        nook.refreshMeetingPrompt(now: Self.start, events: [first, second])
        nook.dismissMeetingPrompt(for: first)
        #expect(nook.meetingPrompt == nil)

        nook.refreshMeetingPrompt(now: Self.start, events: [first, second])
        #expect(nook.meetingPrompt?.id == "second")
        #expect(opened.isEmpty)
    }

    @Test @MainActor func anEventCarryingSomeOtherLinkIsNeverOpened() {
        let nook = NookModel()
        var opened: [URL] = []
        nook.openURL = { opened.append($0) }
        // The finder would never produce this. Join checks again anyway.
        let hostile = Self.event(link: URL(string: "https://zoom.us.evil.example/j/1"))
        #expect(hostile.meetingURL != nil)

        nook.refreshMeetingPrompt(now: Self.start, events: [hostile])
        nook.joinMeeting(hostile)

        #expect(opened.isEmpty)
        #expect(nook.meetingPrompt?.id == hostile.id)
    }

    // MARK: Page height

    @Test @MainActor func theJoinBarAddsItsHeightAndOneRowGapToThePage() {
        let placements = [NookWidgetPlacement(kind: .calendar, size: .medium)]
        let expected: CGFloat = 46
        let without = NookPanelView.preferredHeight(for: placements, calendarStyle: .strip, isEditing: false)
        let with = NookPanelView.preferredHeight(
            for: placements, calendarStyle: .strip, isEditing: false, extras: NookPageExtras(showsJoinBar: true)
        )
        let emptyPage = NookPanelView.preferredHeight(
            for: [], calendarStyle: .strip, isEditing: false, extras: NookPageExtras(showsJoinBar: true)
        ) - NookPanelView.preferredHeight(for: [], calendarStyle: .strip, isEditing: false)

        #expect(NookJoinBarLayout.pageHeight == expected)
        #expect(with - without == expected)
        #expect(emptyPage == expected)
    }

    // MARK: Strings

    @Test func everyJoinStringExistsInEveryLanguage() throws {
        let keys = [
            "nook.calendar.join", "nook.calendar.join.help", "nook.calendar.join.in",
            "nook.calendar.join.now", "nook.calendar.join.ago", "nook.calendar.join.hide",
        ]
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        for language in ["en", "zh-Hans", "zh-Hant"] {
            let url = root.appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String], "\(language) did not load")
            for key in keys {
                #expect(!(table[key] ?? "").isEmpty, "\(language) is missing \(key)")
            }
        }
    }
}
