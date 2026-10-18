import SwiftUI

/// The chip at the trailing edge of the add field while two or more apps
/// are on (T6, T12). It names the app a typed task goes to and opens a menu
/// of the apps that are on and take tasks, with a check on the current one.
/// Canvas is never in the menu (T14).
struct NookTodoAddChip: View {
    var hub: NookTodoHub

    var body: some View {
        let current = hub.addKind
        let lang = LanguageManager.shared
        Menu {
            ForEach(hub.addableKinds) { kind in
                Button {
                    hub.setAddKind(kind)
                } label: {
                    if kind == current {
                        Label(lang.t(kind.nameKey), systemImage: "checkmark")
                    } else {
                        Text(lang.t(kind.nameKey))
                    }
                }
            }
        } label: {
            NookTodoAddChipLabel(kind: current)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(lang.t(current.nameKey))
    }
}

/// What the chip looks like: a 6 pt dot in the app's color, its name and a
/// chevron, in a small capsule.
struct NookTodoAddChipLabel: View {
    let kind: NookTodoSourceKind

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(kind.dotColor)
                .frame(width: 6, height: 6)
            Text(LanguageManager.shared.t(kind.nameKey))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(.white.opacity(0.1)))
        .contentShape(Capsule())
    }
}
