import Foundation

/// What an agent shortcut does to the request the island is showing.
enum AgentHotkeyAction: String, CaseIterable, Identifiable, Sendable {
    case approve
    case deny

    var id: String { rawValue }

    /// Localizable key for the row in Settings.
    var titleKey: String { "settings.general.agentHotkeys.\(rawValue)" }

    var other: AgentHotkeyAction { self == .approve ? .deny : .approve }
}

/// Modifier keys of a shortcut.
struct AgentHotkeyModifiers: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let control = AgentHotkeyModifiers(rawValue: 1 << 0)
    static let option = AgentHotkeyModifiers(rawValue: 1 << 1)
    static let shift = AgentHotkeyModifiers(rawValue: 1 << 2)
    static let command = AgentHotkeyModifiers(rawValue: 1 << 3)

    /// The symbols in the order macOS menus write them.
    var symbols: String {
        var text = ""
        if contains(.control) { text += "⌃" }
        if contains(.option) { text += "⌥" }
        if contains(.shift) { text += "⇧" }
        if contains(.command) { text += "⌘" }
        return text
    }

    var count: Int { rawValue.nonzeroBitCount }
}

/// One shortcut: a physical key and the modifiers held with it.
struct AgentHotkeyCombo: Hashable, Sendable {
    /// Virtual key code, which names a position on the keyboard and not a
    /// letter.
    var keyCode: UInt16
    var modifiers: AgentHotkeyModifiers

    /// "⌃⌥Y". `keyName` supplies the key's label, which lets the app use
    /// the current keyboard layout and tests use the US one.
    func displayText(keyName: (UInt16) -> String? = AgentHotkeyKeyboard.usName) -> String {
        modifiers.symbols + (keyName(keyCode) ?? "Key \(keyCode)")
    }

    /// Saved form, "modifiers:keyCode".
    var storageValue: String { "\(modifiers.rawValue):\(keyCode)" }

    init(keyCode: UInt16, modifiers: AgentHotkeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(storageValue: String) {
        let parts = storageValue.split(separator: ":")
        guard parts.count == 2,
              let rawModifiers = Int(parts[0]), rawModifiers >= 0, rawModifiers < 16,
              let keyCode = UInt16(parts[1]) else {
            return nil
        }
        self.init(keyCode: keyCode, modifiers: AgentHotkeyModifiers(rawValue: rawModifiers))
    }
}

/// Where keys sit on an ANSI keyboard, and what the US layout prints on
/// them.
enum AgentHotkeyKeyboard {
    static let keyY: UInt16 = 16
    static let keyN: UInt16 = 45
    static let escape: UInt16 = 53

    /// Key codes of the four main rows, left to right.
    private static let rows: [[UInt16]] = [
        [50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24],
        [12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30],
        [0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39],
        [6, 7, 8, 9, 11, 45, 46, 43, 47, 44],
    ]

    /// How far each row starts from the left edge, in key widths. The rows
    /// are staggered, which decides which keys touch.
    private static let rowOffsets: [Double] = [0, 1.5, 1.75, 2.25]

    private static let rowLabels: [[String]] = [
        ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="],
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'"],
        ["Z", "X", "C", "V", "B", "N", "M", ",", ".", "/"],
    ]

    private static let namedKeys: [UInt16: String] = [
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc", 76: "Enter",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    /// Row and horizontal center of a key, for the keys in the main rows.
    static func position(of keyCode: UInt16) -> (row: Int, x: Double)? {
        for (row, codes) in rows.enumerated() {
            if let column = codes.firstIndex(of: keyCode) {
                return (row, rowOffsets[row] + Double(column))
            }
        }
        return nil
    }

    /// The label a key carries whatever the layout: Return, Space, arrows
    /// and function keys.
    static func fixedName(for keyCode: UInt16) -> String? {
        namedKeys[keyCode]
    }

    /// The key's label on the US layout.
    static func usName(for keyCode: UInt16) -> String? {
        if let name = namedKeys[keyCode] { return name }
        for (row, codes) in rows.enumerated() {
            if let column = codes.firstIndex(of: keyCode) {
                return rowLabels[row][column]
            }
        }
        return nil
    }

    /// Whether two keys are the same key or touch each other. A finger
    /// that slips off one lands on the other.
    static func areNeighbours(_ first: UInt16, _ second: UInt16) -> Bool {
        if first == second { return true }
        guard let a = position(of: first), let b = position(of: second) else { return false }
        let distance = abs(a.x - b.x)
        switch abs(a.row - b.row) {
        case 0: return distance <= 1
        case 1: return distance < 1
        default: return false
        }
    }
}

/// Why a shortcut cannot be used.
enum AgentHotkeyProblem: Equatable, Sendable {
    /// Fewer than two modifier keys, or neither Control nor Option.
    case needsModifiers
    /// Its key is the other shortcut's key or sits next to it.
    case tooCloseToOther

    var messageKey: String {
        switch self {
        case .needsModifiers: "settings.general.agentHotkeys.problem.needsModifiers"
        case .tooCloseToOther: "settings.general.agentHotkeys.problem.tooClose"
        }
    }
}

/// The two shortcuts and whether each is switched on.
struct AgentHotkeySettings: Equatable, Sendable {
    static let defaultApprove = AgentHotkeyCombo(keyCode: AgentHotkeyKeyboard.keyY, modifiers: [.control, .option])
    static let defaultDeny = AgentHotkeyCombo(keyCode: AgentHotkeyKeyboard.keyN, modifiers: [.control, .option])

    var approve = AgentHotkeySettings.defaultApprove
    var deny = AgentHotkeySettings.defaultDeny
    var isApproveEnabled = true
    var isDenyEnabled = true

    func combo(for action: AgentHotkeyAction) -> AgentHotkeyCombo {
        action == .approve ? approve : deny
    }

    func isEnabled(_ action: AgentHotkeyAction) -> Bool {
        action == .approve ? isApproveEnabled : isDenyEnabled
    }

    mutating func setCombo(_ combo: AgentHotkeyCombo, for action: AgentHotkeyAction) {
        if action == .approve { approve = combo } else { deny = combo }
    }

    mutating func setEnabled(_ isEnabled: Bool, for action: AgentHotkeyAction) {
        if action == .approve { isApproveEnabled = isEnabled } else { isDenyEnabled = isEnabled }
    }
}

/// A request for approval the island can answer.
struct AgentHotkeyCandidate: Equatable, Sendable {
    var sessionID: String
    var requestID: UUID
    /// False for a request the agent wants approved where it runs. The
    /// island can still deny it.
    var canApprove = true
}

/// One request shown as the island's single card.
struct AgentHotkeyCard: Equatable, Sendable {
    var sessionID: String
    var requestID: UUID
}

/// What the island is doing when a shortcut is pressed.
struct AgentHotkeyContext: Equatable, Sendable {
    /// The request the island shows as its single card, with its buttons
    /// on screen. Nil when the island is closed, shows its list, the Nook
    /// or another kind of card, and when the card is folded.
    var card: AgentHotkeyCard?
    /// The request on the single card when the user has folded its buttons
    /// away.
    var foldedCard: AgentHotkeyCard?
    /// When that request became the card on screen. Never when it arrived.
    var cardShownAt: Date?
    /// When a press last approved or denied a request.
    var lastDecisionAt: Date?
    /// Requests the island can answer, in the order it lists them.
    var waiting: [AgentHotkeyCandidate]
    /// When the key went down.
    var now: Date
}

/// What a press does.
enum AgentHotkeyDecision: Equatable, Sendable {
    /// No agent is waiting. The press does nothing.
    case ignore
    /// A request is waiting and is not the card on screen. Show it as the
    /// card and decide nothing.
    case reveal(sessionID: String)
    /// The request only just came on screen, or a press only just decided
    /// another. The press does nothing.
    case tooSoon
    /// Approve or deny this request.
    case act(sessionID: String, requestID: UUID)
    /// The approve key was pressed for the card of a request the agent
    /// wants approved where it runs. The press does nothing.
    case needsTerminal(sessionID: String)
}

/// Pure rules for the agent shortcuts.
enum AgentHotkeyRules {
    /// How long a request has to be the card on screen before a shortcut
    /// can decide it, and how long after one decision the next can follow.
    /// A second press meant for the request before it must not land on the
    /// one that took its place.
    static let minimumVisibleTime: TimeInterval = 0.6

    /// What stops one shortcut from being used, apart from the other one.
    static func problem(with combo: AgentHotkeyCombo) -> AgentHotkeyProblem? {
        let hasControlOrOption = !combo.modifiers.isDisjoint(with: [.control, .option])
        return hasControlOrOption && combo.modifiers.count >= 2 ? nil : .needsModifiers
    }

    /// What stops `combo` from being used for `action` beside the shortcut
    /// the other action already has.
    static func problem(
        with combo: AgentHotkeyCombo,
        for action: AgentHotkeyAction,
        in settings: AgentHotkeySettings
    ) -> AgentHotkeyProblem? {
        if let problem = problem(with: combo) { return problem }
        let other = settings.combo(for: action.other)
        return AgentHotkeyKeyboard.areNeighbours(combo.keyCode, other.keyCode) ? .tooCloseToOther : nil
    }

    /// The shortcuts that may be registered: switched on, well formed, not
    /// taken by macOS, and with keys apart from each other.
    static func usable(
        _ settings: AgentHotkeySettings,
        systemShortcuts: Set<AgentHotkeyCombo> = []
    ) -> [AgentHotkeyAction: AgentHotkeyCombo] {
        var result: [AgentHotkeyAction: AgentHotkeyCombo] = [:]
        for action in AgentHotkeyAction.allCases where settings.isEnabled(action) {
            let combo = settings.combo(for: action)
            guard problem(with: combo) == nil, !systemShortcuts.contains(combo) else { continue }
            result[action] = combo
        }
        if let approve = result[.approve], let deny = result[.deny],
           AgentHotkeyKeyboard.areNeighbours(approve.keyCode, deny.keyCode) {
            return [:]
        }
        return result
    }

    /// A press decides a request only when that exact request is the
    /// single card on screen, and only once `minimumVisibleTime` has passed
    /// since it became that card and since the last decision. A request in
    /// the open list is never decided, in the top row or anywhere else: a
    /// row can be scrolled away or folded, and the list moves the next
    /// request up the moment one is decided. Such a request is shown as the
    /// card first. A card whose buttons are folded away is opened again
    /// before any other request is shown.
    static func decision(in context: AgentHotkeyContext) -> AgentHotkeyDecision {
        func isWaiting(_ card: AgentHotkeyCard) -> Bool {
            context.waiting.contains { $0.sessionID == card.sessionID && $0.requestID == card.requestID }
        }

        if let card = context.card, isWaiting(card) {
            guard let shownAt = context.cardShownAt else { return .tooSoon }
            let since = max(shownAt, context.lastDecisionAt ?? .distantPast)
            guard context.now.timeIntervalSince(since) >= minimumVisibleTime else { return .tooSoon }
            return .act(sessionID: card.sessionID, requestID: card.requestID)
        }
        if let folded = context.foldedCard, isWaiting(folded) {
            return .reveal(sessionID: folded.sessionID)
        }
        guard let next = context.waiting.first else { return .ignore }
        return .reveal(sessionID: next.sessionID)
    }

    /// What a press of `action` does. It follows `decision(in:)` with one
    /// exception: the approve key never decides a request the agent wants
    /// approved where it runs. The deny key decides it as it does any other.
    static func decision(for action: AgentHotkeyAction, in context: AgentHotkeyContext) -> AgentHotkeyDecision {
        let decision = decision(in: context)
        guard action == .approve, case let .act(sessionID, requestID) = decision else { return decision }
        let candidate = context.waiting.first { $0.sessionID == sessionID && $0.requestID == requestID }
        return candidate?.canApprove == true ? decision : .needsTerminal(sessionID: sessionID)
    }

    /// Whether this request is the one a press would decide: the card on
    /// screen, and one the island can answer. Its card names the keys.
    static func isOnCard(sessionID: String, requestID: UUID, in context: AgentHotkeyContext) -> Bool {
        guard let card = context.card, card.sessionID == sessionID, card.requestID == requestID else {
            return false
        }
        return context.waiting.contains { $0.sessionID == sessionID && $0.requestID == requestID }
    }
}

/// The keys an approval card names beside its buttons.
struct AgentHotkeyHint: Equatable, Sendable {
    var approve: String?
    var deny: String?

    var isEmpty: Bool { approve == nil && deny == nil }

    /// Height the line of keys adds under the approval buttons.
    static let lineHeight: CGFloat = 20
}

/// Whether a shortcut is ready, for Settings.
enum AgentHotkeyStatus: Equatable, Sendable {
    /// Switched off in Settings.
    case off
    /// The app has not asked macOS yet (tests and harness runs).
    case inactive
    /// macOS accepted it. It works while an agent is waiting.
    case ready
    /// macOS refused it, with its error code.
    case failed(code: Int32)
    /// A macOS shortcut of its own already uses these keys.
    case usedBySystem
    /// The saved shortcut breaks a rule.
    case invalid(AgentHotkeyProblem)
}
