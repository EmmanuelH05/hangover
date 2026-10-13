import Foundation

/// What a Paste button got from the clipboard.
enum NookDesignClipboardRead<Value> {
    case got(Value)
    /// macOS keeps the app from reading it. Nothing was read.
    case notAllowed
    /// The clipboard had nothing of the kind, or macOS said no at its alert.
    case nothing
}

extension NookDesignKit {
    /// Reads the clipboard because the user pressed a Paste button, the way
    /// the tray's history does: it looks at what macOS allows first. A read
    /// macOS refuses is not made. A read that makes macOS ask is counted as
    /// a system prompt while it waits, which steps the island below the alert
    /// (D52). When nothing comes back, the line says what is true: the
    /// clipboard was empty only when macOS lets the app see it.
    func readClipboard<Value>(
        from clipboard: any NookDesignPictureClipboard,
        emptyNotice: String,
        _ read: () -> Value?
    ) -> NookDesignClipboardRead<Value> {
        let access = clipboard.access
        guard access != .denied else {
            post("nook.design.notice.pasteNotAllowed", .error)
            return .notAllowed
        }
        let asks = access == .asks
        if asks { nook?.systemPromptBegan() }
        let value = read()
        if asks { nook?.systemPromptEnded() }
        if let value { return .got(value) }
        post(asks ? "nook.design.notice.pasteMaybeRefused" : emptyNotice, .info)
        return .nothing
    }
}
