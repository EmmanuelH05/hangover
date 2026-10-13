import AppKit
import Foundation

/// Reads the clipboard for the Paste button. Nothing is read until the
/// button is pressed.
@MainActor
protocol NookLinkAudioClipboard: AnyObject {
    /// Whether macOS lets the app read what other apps copied, asks each
    /// time, or refuses. Looking never raises the alert.
    var access: NookClipboardAccess { get }
    /// The text on the clipboard, or nil when it holds none. A copied
    /// address from a browser counts as text.
    func readText() -> String?
}

/// The general pasteboard.
@MainActor
final class NookLinkAudioSystemClipboard: NookLinkAudioClipboard {
    private let pasteboard: NSPasteboard

    init(_ pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var access: NookClipboardAccess { NookSystemPasteboard(pasteboard).access }

    func readText() -> String? {
        pasteboard.string(forType: .string) ?? pasteboard.string(forType: .URL)
    }
}

/// A clipboard that holds nothing, for a model on a store of its own.
@MainActor
final class NookLinkAudioEmptyClipboard: NookLinkAudioClipboard {
    var access: NookClipboardAccess { .allowed }
    func readText() -> String? { nil }
}

/// What a press of Paste came to.
enum NookLinkAudioPasteResult: Equatable, Sendable {
    /// The clipboard held text, and it was handed to `submit`.
    case submitted(NookLinkAudioSubmit)
    /// macOS keeps the app from reading it. Nothing was read.
    case notAllowed
    /// The clipboard had no text, or macOS said no at its alert.
    case nothing
}

extension NookLinkAudioService {
    /// Reads the clipboard because the user pressed Paste, and saves what
    /// is on it when it is a link. Like the tray's history it looks at what
    /// macOS allows first, and a read macOS refuses is not made. A read that
    /// makes macOS ask counts as a system prompt while it waits, which steps
    /// the island below the alert (D52).
    @discardableResult
    func pasteAndSave() -> NookLinkAudioPasteResult {
        refreshTools()
        guard canSubmit else {
            show(.toolsMissing)
            return .submitted(.toolsMissing)
        }
        let access = clipboard.access
        guard access != .denied else {
            show(.pasteNotAllowed)
            return .notAllowed
        }
        let asks = access == .asks
        if asks { nook?.systemPromptBegan() }
        let text = clipboard.readText()
        if asks { nook?.systemPromptEnded() }
        guard let text else {
            show(asks ? .pasteMaybeRefused : .pasteNothing)
            return .nothing
        }
        return .submitted(submit(text))
    }
}
