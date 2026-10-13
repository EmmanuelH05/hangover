import SwiftUI

extension NookDesignKit {
    /// A press on the card's pill. It writes the setting the switch in
    /// Settings writes, and both read it back from here.
    func toggleKeepsPicking() {
        keepsPicking.toggle()
    }

    /// What the card's pill says for the setting as it is now.
    var keepPickingPillText: String {
        LanguageManager.shared.t(keepsPicking ? "nook.design.keepPill.on" : "nook.design.keepPill.off")
    }
}

/// The pill in the card's top row that turns "Keep picking until Escape" on
/// and off. Off it reads as a question, on it is filled with the accent.
struct NookDesignKeepPill: View {
    @Environment(\.hangoverAccent) private var accent
    var kit: NookDesignKit

    /// Short on purpose: the card's small size has a line of its own for it
    /// with 52 points of the card left below that.
    static let height: CGFloat = 16

    var body: some View {
        let isOn = kit.keepsPicking
        let text = kit.keepPickingPillText
        let help = LanguageManager.shared.t("nook.design.action.pickKeep")
        Button {
            kit.toggleKeepsPicking()
        } label: {
            Text(text)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(isOn ? accent.textOnHighlight(.black) : accent.highlight(.orange))
                .padding(.horizontal, 5)
                .frame(height: Self.height)
                .background(Capsule().fill(isOn ? accent.highlight(.orange) : Color.white.opacity(0.1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .motionAnimation(Motion.hover, value: isOn)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityValue(text)
        .accessibilityAddTraits(.isToggle)
    }
}
