import Foundation

/// What the island and the card say about a recording that was saved. The
/// notch notice and the card's status line read the same sentence.
struct NookRecordNotice: Equatable, Sendable {
    var symbol: String
    var text: String
    /// True when something went less than well: the card shows it in orange.
    var isWarning: Bool

    static func saved(endedBy end: NookRecordEnd, notes: NookRecordNotes = [], lang: LanguageManager) -> NookRecordNotice {
        let base = ending(end, lang: lang)
        guard !notes.isEmpty else { return base }
        var sentences = [base.text]
        if notes.contains(.noVoice) { sentences.append(lang.t("nook.record.notice.noVoice")) }
        if notes.contains(.droppedFrames) {
            // The advice to try Standard goes only to a recording made at High.
            if notes.contains(.suggestStandard) {
                sentences.append(lang.t("nook.record.notice.droppedFrames"))
            } else {
                sentences.append(lang.t("nook.record.notice.droppedFramesPlain"))
            }
        }
        return NookRecordNotice(
            symbol: "exclamationmark.triangle.fill", text: sentences.joined(separator: " "), isWarning: true
        )
    }

    private static func ending(_ end: NookRecordEnd, lang: LanguageManager) -> NookRecordNotice {
        switch end {
        case .user:
            NookRecordNotice(symbol: "record.circle", text: lang.t("nook.record.notice.saved"), isWarning: false)
        case .lowDisk:
            NookRecordNotice(symbol: "exclamationmark.triangle.fill", text: lang.t("nook.record.notice.lowDisk"), isWarning: true)
        case .system:
            NookRecordNotice(symbol: "exclamationmark.triangle.fill", text: lang.t("nook.record.notice.system"), isWarning: true)
        case let .writeError(atSeconds):
            // The failure says when and why; the second sentence says the file is safe.
            NookRecordNotice(
                symbol: "exclamationmark.triangle.fill",
                text: NookRecordFailure.writerFailed(atSeconds: atSeconds).sentence(lang) + " " + lang.t("nook.record.notice.keptPartial"),
                isWarning: true
            )
        }
    }

    static func failed(_ failure: NookRecordFailure, lang: LanguageManager) -> NookRecordNotice {
        NookRecordNotice(symbol: "exclamationmark.triangle.fill", text: failure.sentence(lang), isWarning: true)
    }
}
