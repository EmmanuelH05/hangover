import Foundation

/// What the uploader wrote about a song's key and tempo.
struct NookLinkAudioTagReading: Equatable, Sendable {
    var key: NookMusicalKey?
    var bpm: Int?
}

/// Reads a key and a tempo out of a video's title and description, the way
/// free beats write them: `Key: C Sharp Minor | Bpm: 127`, `Key: E Minor` over
/// `BPM: 139`, `F#m 140 BPM`.
///
/// A key and its value have to stand on the same line. The text is the
/// uploader's, which means it can be about anything, and a blank beats a
/// wrong answer: a name such as `Key Glock`, a hashtag, a tag list, a `Key:`
/// with nothing after it on its line and a tempo outside 50 to 250 all read
/// as nothing. Two different values in one video read as nothing too.
///
/// A key counts in one of two ways. It follows the word `Key` on its line, or
/// it stands on a line that also gives a tempo, as in `F#m 140 BPM`. A key by
/// itself, such as `A minor` in a title, is left alone: `A Major Problem` is not
/// a key. Without a sharp or a flat in it, a loose key also has to stand next to
/// the tempo with only blanks and marks such as `|` or `-` between them, which
/// keeps `Em type beat 140 BPM` (Eminem) from being E minor.
enum NookLinkAudioTags {
    /// The slowest and the fastest tempo a tag may give.
    static let bpmRange = 50...250
    /// Only this many lines, and this much of each, are read.
    static let maxLines = 400
    static let maxLineLength = 1_000

    static func read(title: String?, description: String?) -> NookLinkAudioTagReading {
        let lines = lines(of: [title, description])
        var keys: [NookMusicalKey] = []
        var tempos: [Int] = []
        for line in lines {
            let here = bpmMatches(in: line)
            tempos += here.map(\.value)
            keys += labeledKeys(in: line)
            if !here.isEmpty { keys += looseKeys(in: line, nextTo: here.map(\.range)) }
        }
        return NookLinkAudioTagReading(key: single(keys), bpm: single(tempos))
    }

    /// The one value every mention agrees on, or nil.
    private static func single<Value: Hashable>(_ values: [Value]) -> Value? {
        let distinct = Set(values)
        return distinct.count == 1 ? distinct.first : nil
    }

    private static func lines(of texts: [String?]) -> [String] {
        var result: [String] = []
        for text in texts {
            guard let text else { continue }
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { result.append(String(trimmed.prefix(maxLineLength))) }
                if result.count >= maxLines { return result }
            }
        }
        return result
    }

    // MARK: Tempo

    // A number of two or three digits, with no digit, point, comma or hash in front of it (a thousands
    // separator, a decimal or a tag), and not the end of a range such as `140-150`.
    private static let beforeNumber = #"(?<![\d.,#])(?<!\d[-\u2013\u2014/])"#
    // Not the start of a longer number or of a range.
    private static let afterNumber = #"(?![\d]|[-\u2013\u2014/]\d)"#
    private static let number = #"(\d{2,3})(?:[.,](\d{1,2}))?"#

    private static let numberThenBPM = regex(
        beforeNumber + number + #"[ \t]*(?i:bpm)(?![\p{L}\p{N}])"#
    )
    private static let bpmThenNumber = regex(
        #"(?<![\p{L}\p{N}#])(?i:bpm)(?![\p{L}\p{N}])[ \t]*[:=\-\u2013\u2014]?[ \t]*"# + number + afterNumber
    )

    /// A tempo found on a line and where its text stands.
    struct TempoMatch: Equatable {
        var value: Int
        var range: NSRange
    }

    /// Every tempo on the line that is inside `bpmRange`.
    static func bpms(in line: String) -> [Int] {
        bpmMatches(in: line).map(\.value)
    }

    static func bpmMatches(in line: String) -> [TempoMatch] {
        var found: [TempoMatch] = []
        for expression in [numberThenBPM, bpmThenNumber] {
            for match in expression.matches(in: line, range: fullRange(of: line)) {
                guard let whole = text(of: match, group: 1, in: line), var value = Double(whole) else { continue }
                if let fraction = text(of: match, group: 2, in: line), let part = Double("0." + fraction) {
                    value += part
                }
                let rounded = Int(value.rounded())
                if bpmRange.contains(rounded) { found.append(TempoMatch(value: rounded, range: match.range)) }
            }
        }
        return found
    }

    // MARK: Key

    // The letter of the tonic, an accidental, then the mode. The accidental is
    // `#`, `♯`, `♭`, a `b` right after the letter, or the words sharp and
    // flat. The mode is minor, major, min, maj, or a lowercase `m`. A capital
    // `M` alone is not taken for major, since it reads as FM or AM too.
    // What follows must not go on as a word or a number: `Em7` is not read.
    private static func core(letters: String) -> String {
        "(?<letter>[\(letters)])"
            + #"(?<accidental>#|♯|♭|b|[ \t-]?(?i:sharp)|[ \t-]?(?i:flat))?"#
            + #"(?<mode>[ \t]?(?i:minor|major|min|maj)|m)"#
            + #"(?![\p{L}\p{N}#♯♭])"#
    }

    private static let upperCore = regex(core(letters: "A-G"))
    private static let anyCaseCore = regex(core(letters: "A-Ga-g"))

    // The word Key, then a colon, an equals sign, a dash, `of` or `is` or nothing but blanks, then the key.
    private static let label = regex(
        #"(?<![\p{L}\p{N}#@$_])(?i:key)(?![\p{L}\p{N}])[ \t]*(?<separator>[:=\-\u2013\u2014]|(?i:of|is)(?![\p{L}\p{N}]))?[ \t]*["“'(\[]?"#
    )

    // A key on a line with a tempo, with nothing letter-like in front of it.
    private static let looseUpper = regex(#"(?<![\p{L}\p{N}#@$_/'’.])"# + core(letters: "A-G"))

    /// The keys that follow the word `Key` on the line. A lowercase letter is
    /// taken for the tonic only after a colon, an equals sign or a dash.
    static func labeledKeys(in line: String) -> [NookMusicalKey] {
        var found: [NookMusicalKey] = []
        for match in label.matches(in: line, range: fullRange(of: line)) {
            let separator = text(of: match, group: "separator", in: line) ?? ""
            let allowsLowercase = separator == ":" || separator == "=" || separator == "-" || separator == "\u{2013}" || separator == "\u{2014}"
            let expression = allowsLowercase ? anyCaseCore : upperCore
            let start = match.range.location + match.range.length
            let rest = NSRange(location: start, length: (line as NSString).length - start)
            guard let keyMatch = expression.firstMatch(in: line, options: .anchored, range: rest),
                  let key = key(from: keyMatch, in: line)
            else { continue }
            found.append(key)
        }
        return found
    }

    /// The keys written without the word `Key`, such as `F#m` or `Bb major`.
    /// `tempos` are the places of the tempos on the line. A key with no sharp
    /// or flat counts only when it stands right beside one of them.
    static func looseKeys(in line: String, nextTo tempos: [NSRange]) -> [NookMusicalKey] {
        looseUpper.matches(in: line, range: fullRange(of: line)).compactMap { match in
            let hasAccidental = match.range(withName: "accidental").location != NSNotFound
            if !hasAccidental, !tempos.contains(where: { isBeside(match.range, $0, in: line) }) { return nil }
            return key(from: match, in: line)
        }
    }

    private static let joiners = regex(#"^[ \t|,/•·:;@(){}\[\]~+&*\-\u2013\u2014]*$"#)

    /// True when only blanks and joining marks stand between the two places.
    private static func isBeside(_ first: NSRange, _ second: NSRange, in line: String) -> Bool {
        let (left, right) = first.location <= second.location ? (first, second) : (second, first)
        let gapStart = left.location + left.length
        guard gapStart <= right.location else { return false }
        let gap = (line as NSString).substring(with: NSRange(location: gapStart, length: right.location - gapStart))
        return joiners.firstMatch(in: gap, range: fullRange(of: gap)) != nil
    }

    private static func key(from match: NSTextCheckingResult, in line: String) -> NookMusicalKey? {
        guard let letter = text(of: match, group: "letter", in: line)?.uppercased(),
              let base = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11][letter],
              let mode = text(of: match, group: "mode", in: line)?.trimmingCharacters(in: .whitespaces)
        else { return nil }
        var shift = 0
        if let accidental = text(of: match, group: "accidental", in: line)?.lowercased() {
            if accidental.contains("#") || accidental.contains("♯") || accidental.contains("sharp") {
                shift = 1
            } else {
                shift = -1
            }
        }
        let isMinor = mode == "m" || mode.lowercased().hasPrefix("min")
        return NookMusicalKey(tonic: base + shift, mode: isMinor ? .minor : .major)
    }

    // MARK: Helpers

    private static func regex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure("The tag reader's pattern does not compile: \(pattern)")
        }
    }

    private static func fullRange(of text: String) -> NSRange {
        NSRange(location: 0, length: (text as NSString).length)
    }

    private static func text(of match: NSTextCheckingResult, group: Int, in line: String) -> String? {
        let range = match.range(at: group)
        guard range.location != NSNotFound else { return nil }
        return (line as NSString).substring(with: range)
    }

    private static func text(of match: NSTextCheckingResult, group name: String, in line: String) -> String? {
        let range = match.range(withName: name)
        guard range.location != NSNotFound else { return nil }
        return (line as NSString).substring(with: range)
    }
}
