import SwiftUI

/// The small things the tips page tells (D43). Each one names a gesture
/// the app really has; the line beside a case says where that is in code.
/// A tip shows only when the part of the app it is about is in use: its
/// widget is on the page, or the agents are switched on.
enum OnboardingTip: String, CaseIterable, Identifiable, Sendable {
    /// `IslandClickAction.pin`: a click inside a hover-opened island keeps
    /// it open. With the click trigger, a second click on the notch closes
    /// it (`closeFromNotch`).
    case keepOpen
    /// `IslandPanelView`: files dropped on the closed or the opened island
    /// go to `nook.tray.handleDrop`.
    case dropFiles
    /// `NookWidgetGrid`: a long press or the Edit Widgets menu item starts
    /// editing, a drag reorders, the corner grip resizes.
    case rearrange
    /// `IslandPanelView.openedHeaderButtons`: the page switch, shown while
    /// `AppModel.showsPageSwitch` is true.
    case switchPages
    /// `IslandPanelView`: a tap on a session row calls
    /// `AppModel.jumpToSession`.
    case jump
    /// `NookTodoCard`: the task's name opens its notes page, the circle
    /// completes it.
    case todoNotes
    /// `NookNotesCard`: Return in the field appends the line.
    case quickNotes
    /// `NookMediaCard`: the speaker button opens the list of outputs.
    case speaker
    /// Settings, Nook: "Replace the macOS volume and brightness popups".
    case volume
    /// `IslandPanelView.openedHeaderButtons`: the gear opens Settings. The
    /// tour's button is in the About tab.
    case settings

    var id: String { rawValue }

    /// The most tips a page holds: two rows of four.
    static let pageLimit = 8

    var needsAgents: Bool { self == .switchPages || self == .jump }

    /// The widget the tip is about, which has to be on the page.
    var widget: NookWidgetKind? {
        switch self {
        case .dropFiles: .tray
        case .todoNotes: .todo
        case .quickNotes: .notes
        case .speaker: .media
        case .keepOpen, .rearrange, .switchPages, .jump, .volume, .settings: nil
        }
    }

    var symbol: String {
        switch self {
        case .keepOpen: "pin.fill"
        case .dropFiles: "arrow.down.doc.fill"
        case .rearrange: "square.grid.2x2.fill"
        case .switchPages: "arrow.left.arrow.right"
        case .jump: "terminal.fill"
        case .todoNotes: "checklist"
        case .quickNotes: "note.text"
        case .speaker: "hifispeaker.fill"
        case .volume: "speaker.wave.2.fill"
        case .settings: "gearshape.fill"
        }
    }

    /// The name in the tip's string keys. Keeping the island open is told
    /// in the words of the way the island opens.
    func keyName(openTrigger: IslandOpenTrigger) -> String {
        self == .keepOpen ? "keepOpen.\(openTrigger.rawValue)" : rawValue
    }

    /// The tips a page shows, in the order above, with where Settings is
    /// last. Tips about agents, or about a widget that is off the page, are
    /// left out, and the rest stop at what fits.
    static func shown(agentsEnabled: Bool, widgets: Set<NookWidgetKind>) -> [OnboardingTip] {
        let fitting = allCases.filter { tip in
            guard tip != .settings else { return false }
            if tip.needsAgents, !agentsEnabled { return false }
            if let widget = tip.widget, !widgets.contains(widget) { return false }
            return true
        }
        return Array(fitting.prefix(pageLimit - 1)) + [.settings]
    }
}
