import SwiftUI

/// The two buttons a recording's tile shows when the pointer is over it: the
/// next things people do with a recording. A GIF is made from the Convert
/// chip in the tray's header or the right click menu, not from the tile. The
/// right click menu has these too, and is all the small card has.
enum NookTrayRecordingAction: CaseIterable, Identifiable, Sendable {
    case smaller
    case showInFinder

    var id: Self { self }

    var symbol: String {
        switch self {
        case .smaller: "arrow.down.right.and.arrow.up.left"
        case .showInFinder: "folder"
        }
    }

    /// The help text on the button, which also names it for VoiceOver.
    var helpKey: String {
        switch self {
        case .smaller: "nook.tray.recording.smaller"
        case .showInFinder: "nook.tray.recording.showInFinder"
        }
    }

    /// The buttons a tile shows, in order: both on a recording, the one thing
    /// the tray hard links in, and none on any other file or on the small
    /// card, which has no room for them.
    static func offered(for item: NookTrayItem, size: NookWidgetSize) -> [NookTrayRecordingAction] {
        item.linkedFrom != nil && size != .small ? allCases : []
    }
}

extension NookTrayStore {
    /// What a button on a recording's tile does. Smaller starts the 1080p
    /// copy, and Show in Finder goes to the recording in Movies/Hangover.
    func perform(_ action: NookTrayRecordingAction, on item: NookTrayItem) {
        switch action {
        case .smaller: convert(item, action: .smallerVideo(.p1080))
        case .showInFinder: revealInFinder(item)
        }
    }
}

/// The buttons, in a row over the bottom of a tile's icon.
struct NookTrayRecordingButtons: View {
    var store: NookTrayStore
    let item: NookTrayItem
    let actions: [NookTrayRecordingAction]

    /// Small enough for both to sit on the narrowest tile with room between.
    static let buttonSize: CGFloat = 14

    var body: some View {
        HStack(spacing: 2) {
            ForEach(actions) { action in
                let help = LanguageManager.shared.t(action.helpKey)
                Button {
                    store.perform(action, on: item)
                } label: {
                    Image(systemName: action.symbol)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: Self.buttonSize, height: Self.buttonSize)
                        .background(Circle().fill(Color.black.opacity(0.72)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(help)
                .accessibilityLabel(help)
            }
        }
    }
}
