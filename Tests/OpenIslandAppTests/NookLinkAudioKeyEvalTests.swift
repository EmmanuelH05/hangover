import Foundation
import Testing
@testable import OpenIslandApp

// The measuring stick for the key and tempo guessers. It runs only when
// OPEN_ISLAND_KEY_EVAL_DIR names a folder, which a normal `swift test` never
// has, and then it reads the sound files in it and prints how the guesses
// compare with the labels in `labels.tsv`.
//
//   OPEN_ISLAND_KEY_EVAL_DIR=/path/to/beats swift test --filter NookLinkAudioKeyEvalTests
//
// `labels.tsv` has one line per file, tab separated: the file name, the key
// (`C# minor`, `Bb major`, `Am`, or empty) and the tempo (`127`, or empty).
// A first line that starts with `file` is a header and is skipped. Any sound
// file `AVAudioFile` reads is fine. The folder is only read from.

@Suite struct NookLinkAudioKeyEvalTests {
    static let folder = ProcessInfo.processInfo.environment["OPEN_ISLAND_KEY_EVAL_DIR"]

    struct Label {
        let file: String
        let key: NookMusicalKey?
        let bpm: Int?
    }

    @Test(.enabled(if: NookLinkAudioKeyEvalTests.folder != nil))
    func printsHowTheGuessesCompareWithTheLabels() throws {
        let directory = URL(fileURLWithPath: try #require(Self.folder), isDirectory: true)
        let labelsText = try String(contentsOf: directory.appendingPathComponent("labels.tsv"), encoding: .utf8)
        let labels = Self.labels(in: labelsText)
        #expect(!labels.isEmpty, "labels.tsv has no lines")

        var keyTally = KeyTally()
        var tempoTally = TempoTally()
        for label in labels {
            let url = directory.appendingPathComponent(label.file)
            guard let samples = try? NookLinkAudioDecoder.decode(url) else {
                print("eval  \(label.file): could not be read")
                continue
            }
            var line = "eval  \(label.file)"
            if let wanted = label.key {
                let scores = NookLinkAudioKeyGuesser.scores(samples: samples, sampleRate: NookLinkAudioDecoder.sampleRate)
                let guess = NookLinkAudioKeyGuesser.guess(samples: samples, sampleRate: NookLinkAudioDecoder.sampleRate)
                keyTally.add(wanted: wanted, guess: guess?.key)
                let shown = guess.map { $0.key.englishName } ?? "none"
                let best = scores.map { "\($0.best.key.englishName) margin \(Self.number($0.margin)) significance \(Self.number($0.significance))" } ?? "no sound"
                line += "  key wanted \(wanted.englishName), said \(shown) (best \(best))"
            }
            if let wanted = label.bpm {
                let reading = NookLinkAudioTempoGuesser.reading(samples: samples, sampleRate: NookLinkAudioDecoder.sampleRate)
                let guess = NookLinkAudioTempoGuesser.guess(samples: samples, sampleRate: NookLinkAudioDecoder.sampleRate)
                tempoTally.add(wanted: wanted, guess: guess?.bpm)
                let shown = guess.map { "\($0.bpm)" } ?? "none"
                let best = reading.map { "\(Self.number($0.bpm)) clarity \(Self.number($0.clarity))" } ?? "no sound"
                line += "  bpm wanted \(wanted), said \(shown) (best \(best))"
            }
            print(line)
        }
        print(keyTally.summary)
        print(tempoTally.summary)
    }

    // MARK: Labels

    static func labels(in text: String) -> [Label] {
        text.components(separatedBy: .newlines).enumerated().compactMap { index, line in
            let fields = line.components(separatedBy: "\t")
            guard let file = fields.first?.trimmingCharacters(in: .whitespaces), !file.isEmpty else { return nil }
            if index == 0, file.lowercased() == "file" { return nil }
            let keyText = fields.count > 1 ? fields[1].trimmingCharacters(in: .whitespaces) : ""
            let bpmText = fields.count > 2 ? fields[2].trimmingCharacters(in: .whitespaces) : ""
            let key = keyText.isEmpty ? nil : NookLinkAudioTags.read(title: nil, description: "Key: \(keyText)").key
            return Label(file: file, key: key, bpm: Int(bpmText.split(separator: ".").first ?? ""))
        }
    }

    static func number(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    // MARK: Tallies

    /// How the keys compare. A guess is exact, the relative key (the same
    /// notes, the other mode), a fifth away in the same mode, or another miss.
    struct KeyTally {
        var exact = 0
        var relative = 0
        var fifth = 0
        var other = 0
        var abstained = 0

        var total: Int { exact + relative + fifth + other + abstained }

        mutating func add(wanted: NookMusicalKey, guess: NookMusicalKey?) {
            guard let guess else { abstained += 1; return }
            if guess == wanted {
                exact += 1
            } else if guess == wanted.relative {
                relative += 1
            } else if guess.mode == wanted.mode, [5, 7].contains((guess.tonic - wanted.tonic + 12) % 12) {
                fifth += 1
            } else {
                other += 1
            }
        }

        var summary: String {
            "eval  KEY of \(total): exact \(exact), relative major/minor mixup \(relative), "
                + "off by a fifth \(fifth), other misses \(other), abstains \(abstained)"
        }
    }

    /// How the tempos compare: exact, within 2 beats a minute, half or double
    /// (within 2 of the double, or within 1 of the half), another miss.
    struct TempoTally {
        var exact = 0
        var withinTwo = 0
        var halfOrDouble = 0
        var other = 0
        var abstained = 0

        var total: Int { exact + withinTwo + halfOrDouble + other + abstained }

        mutating func add(wanted: Int, guess: Int?) {
            guard let guess else { abstained += 1; return }
            if guess == wanted {
                exact += 1
            } else if abs(guess - wanted) <= 2 {
                withinTwo += 1
            } else if abs(guess - 2 * wanted) <= 2 || abs(2 * guess - wanted) <= 2 {
                halfOrDouble += 1
            } else {
                other += 1
            }
        }

        var summary: String {
            "eval  TEMPO of \(total): exact \(exact), within 2 \(withinTwo), "
                + "half or double \(halfOrDouble), other misses \(other), abstains \(abstained)"
        }
    }
}

// The tallies and the labels file, tested on made-up data. These run in every `swift test`.
@Suite struct NookLinkAudioKeyEvalHelpersTests {
    private typealias Eval = NookLinkAudioKeyEvalTests

    @Test func theKeyTallySortsAGuessIntoOneBucket() {
        var tally = Eval.KeyTally()
        let cMinor = NookMusicalKey(tonic: 0, mode: .minor)
        tally.add(wanted: cMinor, guess: cMinor)
        tally.add(wanted: cMinor, guess: NookMusicalKey(tonic: 3, mode: .major))
        tally.add(wanted: cMinor, guess: NookMusicalKey(tonic: 7, mode: .minor))
        tally.add(wanted: cMinor, guess: NookMusicalKey(tonic: 5, mode: .minor))
        tally.add(wanted: cMinor, guess: NookMusicalKey(tonic: 1, mode: .minor))
        tally.add(wanted: cMinor, guess: nil)
        #expect(tally.exact == 1)
        #expect(tally.relative == 1)
        #expect(tally.fifth == 2)
        #expect(tally.other == 1)
        #expect(tally.abstained == 1)
        #expect(tally.total == 6)
    }

    @Test func theTempoTallySortsAGuessIntoOneBucket() {
        var tally = Eval.TempoTally()
        tally.add(wanted: 140, guess: 140)
        tally.add(wanted: 140, guess: 142)
        tally.add(wanted: 70, guess: 140)
        tally.add(wanted: 140, guess: 70)
        tally.add(wanted: 140, guess: 100)
        tally.add(wanted: 140, guess: nil)
        #expect(tally.exact == 1)
        #expect(tally.withinTwo == 1)
        #expect(tally.halfOrDouble == 2)
        #expect(tally.other == 1)
        #expect(tally.abstained == 1)
    }

    @Test func theLabelsFileIsReadWithItsHeaderBlanksAndWordings() {
        let text = "file\tkey\tbpm\nA.mp3\tC# minor\t127\nB.mp3\t\t90\nC.mp3\tBb\t\nD.mp3\tAm\t140.0\n\n"
        let labels = Eval.labels(in: text)
        #expect(labels.map(\.file) == ["A.mp3", "B.mp3", "C.mp3", "D.mp3"])
        #expect(labels[0].key == NookMusicalKey(tonic: 1, mode: .minor))
        #expect(labels[0].bpm == 127)
        #expect(labels[1].key == nil && labels[1].bpm == 90)
        #expect(labels[2].key == nil, "a key with no mode is no label")
        #expect(labels[3].key == NookMusicalKey(tonic: 9, mode: .minor))
        #expect(labels[3].bpm == 140)
    }
}
