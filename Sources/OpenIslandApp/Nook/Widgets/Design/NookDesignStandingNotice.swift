import Foundation

/// A line that stays in the card for as long as its cause does.
struct NookDesignStandingNotice: Equatable, Sendable {
    let text: String
    /// True when pressing the line opens Settings.
    let opensSettings: Bool
}

/// A button that asks twice, as the palette editor's delete does: the first
/// press asks, the second does it.
struct NookDesignTwoStepAsk: Equatable, Sendable {
    private(set) var isAsking = false

    /// True when this press is the one to act on.
    mutating func press() -> Bool {
        if isAsking {
            isAsking = false
            return true
        }
        isAsking = true
        return false
    }

    mutating func cancel() { isAsking = false }
}
