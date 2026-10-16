import Foundation
import Testing
@testable import OpenIslandApp

// What the tag reader takes from a video's title and description, and what
// it leaves alone. A blank beats a wrong answer, which makes the refusals
// matter as much as the readings.

@Suite struct NookLinkAudioTagsTests {
    private func key(_ tonic: Int, _ mode: NookMusicalKey.Mode) -> NookMusicalKey {
        NookMusicalKey(tonic: tonic, mode: mode)
    }

    private func read(_ description: String, title: String? = nil) -> NookLinkAudioTagReading {
        NookLinkAudioTags.read(title: title, description: description)
    }

    // MARK: Keys that are read

    @Test func theFullLineOfAFreeBeatReadsKeyAndTempo() {
        let found = read("Key: C Sharp Minor | Bpm: 127")
        #expect(found == NookLinkAudioTagReading(key: key(1, .minor), bpm: 127))
    }

    @Test func aKeyAndATempoOnTheirOwnLinesAreBothRead() {
        let found = read("Prod. by someone\nKey: E Minor\nBPM: 139\nFollow for more")
        #expect(found == NookLinkAudioTagReading(key: key(4, .minor), bpm: 139))
    }

    @Test(arguments: [
        ("Key - Ebm", 3, NookMusicalKey.Mode.minor),
        ("Key: C#m", 1, .minor),
        ("Key: Cmin", 0, .minor),
        ("Key: F# minor", 6, .minor),
        ("Key: Bb major", 10, .major),
        ("Key: D♯ minor", 3, .minor),
        ("Key: Dmaj", 2, .major),
        ("Key: Ab major", 8, .major),
        ("Key: G# minor", 8, .minor),
        ("Key: E♭ major", 3, .major),
        ("Key: B minor", 11, .minor),
        ("Key: Bm", 11, .minor),
        ("Key: Bbm", 10, .minor),
        ("Key: A Flat Minor", 8, .minor),
        ("Key: F Sharp Major", 6, .major),
        ("Key: C-sharp minor", 1, .minor),
        ("KEY: D MINOR", 2, .minor),
        ("key: c# minor", 1, .minor),
        ("Key: a minor", 9, .minor),
        ("Key = Gm", 7, .minor),
        ("Key of G minor", 7, .minor),
        ("Key is Em", 4, .minor),
        ("Key: (C# minor)", 1, .minor),
        ("Key:C#m", 1, .minor),
        ("Key : D major", 2, .major),
        ("Title [Key: Am]", 9, .minor),
    ])
    func aKeyAfterTheWordKeyIsRead(line: String, tonic: Int, mode: NookMusicalKey.Mode) {
        #expect(read(line).key == key(tonic, mode), "\(line)")
    }

    @Test func sharpsAndFlatsOfTheSameNoteAreTheSameKey() {
        #expect(read("Key: D# minor").key == read("Key: Eb minor").key)
        #expect(read("Key: C# major").key == read("Key: Db major").key)
        #expect(read("Key: Cb major").key == key(11, .major))
        #expect(read("Key: E# minor").key == key(5, .minor))
    }

    @Test func aKeyBesideATempoIsReadWithoutTheWordKey() {
        #expect(read("F#m 140 BPM") == NookLinkAudioTagReading(key: key(6, .minor), bpm: 140))
        #expect(read("140 BPM - Am").key == key(9, .minor))
        #expect(read("[FREE] Drake Type Beat - 'Wake Up' (Dm | 140 BPM)") == NookLinkAudioTagReading(key: key(2, .minor), bpm: 140))
        #expect(read("Bb major | 90 BPM").key == key(10, .major))
        #expect(read("Hard Trap Beat | F# minor | 150 BPM").key == key(6, .minor))
    }

    @Test func aSharpOrFlatKeyOnALineWithATempoNeedsNoNeighbourhood() {
        // With a sharp or a flat it is a key, and it can stand anywhere on the line.
        #expect(read("Prod. Someone - F#m - Hard Trap Beat - 140 BPM").key == key(6, .minor))
    }

    // MARK: Tempos that are read

    @Test(arguments: [
        ("BPM: 139", 139), ("Bpm: 127", 127), ("bpm 100", 100), ("BPM:90", 90), ("140 BPM", 140), ("140bpm", 140),
        ("| 150 BPM |", 150), ("[93 BPM]", 93), ("Tempo 7 | 128 bpm", 128), ("139.5 BPM", 140), ("BPM: 127.0", 127),
        ("139,5 BPM", 140), ("50 BPM", 50), ("250 BPM", 250), ("BPM = 85", 85), ("BPM - 85", 85),
    ])
    func aTempoIsRead(line: String, bpm: Int) {
        #expect(read(line).bpm == bpm, "\(line)")
    }

    @Test func theTitleCountsAsALineToo() {
        let found = read("Key: C Sharp Minor", title: "Wake Up | 127 BPM")
        #expect(found == NookLinkAudioTagReading(key: key(1, .minor), bpm: 127))
        #expect(read("Nothing here", title: "Free Beat [Key: Em] [BPM: 90]") == NookLinkAudioTagReading(key: key(4, .minor), bpm: 90))
    }

    @Test func theSameValueTwiceIsStillOneValue() {
        #expect(read("Key: Em | 140 BPM\nBPM: 140\nKey: E minor") == NookLinkAudioTagReading(key: key(4, .minor), bpm: 140))
    }

    // MARK: What is refused

    @Test(arguments: [
        "Key Glock x Young Dolph Type Beat",
        "Key Glock Type Beat",
        "#keyglocktypebeat",
        "#key #glock #youngdolph #typebeat",
        "Tags: key glock type beat, free beat, rap beat, trap",
        "trap, F#m, hard, dark, drill",
        "Keys: Em",
        "Keyboard in C minor",
        "Key:",
        "Key: ",
        "Key: Unknown",
        "Key: N/A",
        "Key: TBD",
        "Key: C",
        "Key: Cm7",
        "Key: EM",
        "Key: FM radio",
        "Key: A",
        "Key of the city",
        "Monkey: Em",
        "A minor",
        "F# minor",
        "Dm",
    ])
    func textThatIsNotAKeyIsNotRead(line: String) {
        #expect(read(line).key == nil, "\(line)")
    }

    @Test func aKeyLabelWithNothingAfterItDoesNotTakeTheNextLine() {
        #expect(read("Key:\nEm").key == nil)
        #expect(read("Key:\nBPM: 140") == NookLinkAudioTagReading(key: nil, bpm: 140))
        #expect(read("Key: \n\nF# minor\n140 BPM").key == nil)
    }

    @Test func aKeyThatIsNotNextToTheTempoIsNotTakenWithoutTheWordKey() {
        // A major problem is no key. Em is Eminem.
        #expect(read("A Major Problem | 140 BPM") == NookLinkAudioTagReading(key: nil, bpm: 140))
        #expect(read("Em type beat 140 BPM") == NookLinkAudioTagReading(key: nil, bpm: 140))
        #expect(read("Free A minor Type Beat for rappers 140 BPM").key == nil)
    }

    @Test func aKeyNeedsItsOwnLineToGoWithATempo() {
        #expect(read("Dm\n140 BPM") == NookLinkAudioTagReading(key: nil, bpm: 140))
    }

    @Test(arguments: ["BPM: 300", "BPM: 40", "49 BPM", "251 BPM", "0 BPM", "BPM: 999", "BPM: 1400", "1140 BPM", "1,140 BPM", "5 BPM", "BPM: ", "BPM: abc"])
    func aTempoOutsideTheRangeOrNotANumberIsNotRead(line: String) {
        #expect(read(line).bpm == nil, "\(line)")
    }

    @Test func aTempoInATagOrARangeIsNotRead() {
        #expect(read("#140bpm").bpm == nil)
        #expect(read("#trap #140bpm #typebeat").bpm == nil)
        #expect(read("140-150 BPM").bpm == nil)
        #expect(read("BPM: 140-150").bpm == nil)
        #expect(read("140 BPMs").bpm == nil)
        #expect(read("BPMX 140").bpm == nil)
    }

    @Test func twoDifferentAnswersAreNoAnswer() {
        #expect(read("Key: Em\nKey: Am") == NookLinkAudioTagReading(key: nil, bpm: nil))
        #expect(read("140 BPM\n70 BPM").bpm == nil)
        #expect(read("Key: Em | BPM: 140", title: "Another [Am] 90 BPM") == NookLinkAudioTagReading(key: nil, bpm: nil))
        // One bad number does not hide a good one.
        #expect(read("BPM: 300\nBPM: 140").bpm == 140)
    }

    @Test func nothingAtAllIsNothing() {
        #expect(read("") == NookLinkAudioTagReading(key: nil, bpm: nil))
        #expect(NookLinkAudioTags.read(title: nil, description: nil) == NookLinkAudioTagReading(key: nil, bpm: nil))
        #expect(read("\n\n   \n") == NookLinkAudioTagReading(key: nil, bpm: nil))
    }

    // MARK: Descriptions as they come

    @Test func descriptionsTheWayFreeBeatsWriteThem() {
        let withEmoji = "🎹 Key: C# Minor 🥁 BPM: 140\n🔥 Free for non profit use\n📩 Contact: someone@example.com"
        #expect(read(withEmoji) == NookLinkAudioTagReading(key: key(1, .minor), bpm: 140))

        let reversed = "Tempo: 140 BPM | Key: F Minor\nBuy: https://beats.example/b/123"
        #expect(read(reversed) == NookLinkAudioTagReading(key: key(5, .minor), bpm: 140))

        let inTheTitle = read("Prod. by X | A# Minor", title: "[FREE] Lil Baby Type Beat 2025 - \"Bag\" | 142 BPM | A# Minor")
        #expect(inTheTitle == NookLinkAudioTagReading(key: key(10, .minor), bpm: 142))

        let loose = read("Free Beat", title: "Dark Trap Beat 140 BPM A Minor")
        #expect(loose == NookLinkAudioTagReading(key: key(9, .minor), bpm: 140))

        let inline = read("Buy this beat: https://beats.example/b/9 Key: Cm BPM: 128 Prod. by X")
        #expect(inline == NookLinkAudioTagReading(key: key(0, .minor), bpm: 128))
    }

    @Test func descriptionsThatSayNothingOrTooMuchGiveNothing() {
        let noTags = "[FREE] Lil Baby Type Beat 2025 - \"Bag\" | Trap Instrumental\nFollow me on Instagram for more beats."
        #expect(read(noTags) == NookLinkAudioTagReading(key: nil, bpm: nil))

        let emptyKey = "Prod. by X\nKey:\nPlease subscribe and turn on notifications\nLicense: Free for non profit"
        #expect(read(emptyKey) == NookLinkAudioTagReading(key: nil, bpm: nil))

        // A mix of several beats: each line has its own answer, which leaves no one answer.
        let playlist = "0:00 Beat one | Em | 140 BPM\n3:10 Beat two | Gm | 90 BPM\n6:20 Beat three | Dm | 128 BPM"
        #expect(read(playlist) == NookLinkAudioTagReading(key: nil, bpm: nil))
    }

    // MARK: Limits

    @Test func aHugeDescriptionIsReadOnlyToItsLimitAndStaysFast() {
        let filler = String(repeating: "lorem ipsum dolor sit amet\n", count: NookLinkAudioTags.maxLines)
        let found = NookLinkAudioTags.read(title: nil, description: filler + "Key: Em | 140 BPM")
        #expect(found == NookLinkAudioTagReading(key: nil, bpm: nil), "a line past the limit is not read")
        let early = NookLinkAudioTags.read(title: nil, description: "Key: Em | 140 BPM\n" + filler)
        #expect(early == NookLinkAudioTagReading(key: key(4, .minor), bpm: 140))
    }

    @Test func aVeryLongLineIsCutBeforeItIsRead() {
        let long = String(repeating: "x", count: NookLinkAudioTags.maxLineLength) + " Key: Em"
        #expect(read(long).key == nil)
        #expect(read("Key: Em " + long).key == key(4, .minor))
    }

    @Test func aPatternThatCouldBacktrackIsReadInTime() {
        let nasty = String(repeating: "Key ", count: 200) + String(repeating: "1", count: 200) + " BPM"
        let started = Date()
        _ = read(nasty)
        #expect(Date().timeIntervalSince(started) < 2)
    }
}

// A few separators that need characters this file keeps out of its source.
@Suite struct NookLinkAudioTagsSeparatorTests {
    @Test func anEnDashOrAnEmDashAfterTheWordKeyIsASeparator() {
        let en = NookLinkAudioTags.read(title: nil, description: "Key \u{2013} Em")
        let em = NookLinkAudioTags.read(title: nil, description: "Key \u{2014} f# minor")
        #expect(en.key == NookMusicalKey(tonic: 4, mode: .minor))
        #expect(em.key == NookMusicalKey(tonic: 6, mode: .minor))
    }

    @Test func aRangeWithADashIsNoTempo() {
        #expect(NookLinkAudioTags.read(title: nil, description: "140\u{2013}150 BPM").bpm == nil)
        #expect(NookLinkAudioTags.read(title: nil, description: "BPM: 140\u{2014}150").bpm == nil)
    }

    @Test func aTempoAfterADashStillCounts() {
        #expect(NookLinkAudioTags.read(title: nil, description: "Wake Up \u{2013} 140 BPM").bpm == 140)
        #expect(NookLinkAudioTags.read(title: nil, description: "Dm \u{2014} 140 BPM").key == NookMusicalKey(tonic: 2, mode: .minor))
    }
}
