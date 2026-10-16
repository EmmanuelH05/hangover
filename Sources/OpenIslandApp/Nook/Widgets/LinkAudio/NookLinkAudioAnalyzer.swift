import Foundation

/// Finds the key and tempo of a saved download. The app uses
/// `NookLinkAudioSystemAnalyzer`. A test hands in a fake, which keeps every
/// test off real audio files and real decoding.
protocol NookLinkAudioAnalyzing: Sendable {
    /// What can be found out about the song at `file`. `title` and
    /// `description` are the video's own. It never throws: a file that cannot
    /// be read has nothing found about it.
    func analyze(file: URL, title: String?, description: String?) async -> NookLinkAudioFindings
}

/// The rule for what is written down and what is worked out.
enum NookLinkAudioAnalysis {
    /// Whether a key the tags leave out is guessed from the sound. It is not
    /// (D66). On 52 free beats from YouTube whose producers wrote the key, the
    /// guesser was right 5 times in 9 even at a margin of 0.20, and a wrong
    /// key in a file name is worse than none. The guesser stays, for the eval
    /// test and a better method.
    static let guessesKeyFromSound = false

    /// A key or a tempo that the uploader wrote is taken as exact. A missing
    /// tempo is guessed from the sound `decode` returns, as is a missing key
    /// when `guessesKey` is on. A guess says it is one.
    /// `decode` is called only when something is left to guess: a video that
    /// gives both is never decoded. A cancel is looked for after the decode and
    /// between the two guesses, and what was found until then is returned.
    static func findings(
        tags: NookLinkAudioTagReading,
        sampleRate: Double,
        guessesKey: Bool = guessesKeyFromSound,
        decode: () -> [Float]?
    ) -> NookLinkAudioFindings {
        var findings = NookLinkAudioFindings(
            key: tags.key.map { NookLinkAudioFound(value: $0, isGuess: false) },
            bpm: tags.bpm.map { NookLinkAudioFound(value: $0, isGuess: false) }
        )
        let wantsKey = guessesKey && findings.key == nil
        guard wantsKey || findings.bpm == nil, let samples = decode(), !Task.isCancelled else { return findings }
        if wantsKey, let guess = NookLinkAudioKeyGuesser.guess(samples: samples, sampleRate: sampleRate) {
            findings.key = NookLinkAudioFound(value: guess.key, isGuess: true)
        }
        guard !Task.isCancelled else { return findings }
        if findings.bpm == nil, let guess = NookLinkAudioTempoGuesser.guess(samples: samples, sampleRate: sampleRate) {
            findings.bpm = NookLinkAudioFound(value: guess.bpm, isGuess: true)
        }
        return findings
    }
}

/// Reads the tags, then decodes and analyzes the file off the main actor.
struct NookLinkAudioSystemAnalyzer: NookLinkAudioAnalyzing {
    func analyze(file: URL, title: String?, description: String?) async -> NookLinkAudioFindings {
        // A cancel that came before the start leaves nothing to do.
        guard !Task.isCancelled else { return NookLinkAudioFindings() }
        let tags = NookLinkAudioTags.read(title: title, description: description)
        // The heavy part runs on a task of its own, which keeps the main actor
        // free. A cancel of the caller reaches it, and it stops at the next
        // chunk of the decode and before the next guess.
        let work = Task.detached(priority: .utility) {
            NookLinkAudioAnalysis.findings(tags: tags, sampleRate: NookLinkAudioDecoder.sampleRate) {
                try? NookLinkAudioDecoder.decode(file)
            }
        }
        return await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
    }
}

/// An analyzer that finds nothing, for a model on a store of its own.
struct NookLinkAudioRefusingAnalyzer: NookLinkAudioAnalyzing {
    func analyze(file: URL, title: String?, description: String?) async -> NookLinkAudioFindings {
        NookLinkAudioFindings()
    }
}
