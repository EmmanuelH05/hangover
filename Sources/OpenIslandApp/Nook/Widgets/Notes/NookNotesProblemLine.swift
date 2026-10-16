import SwiftUI

/// What is wrong with the notes, in a sentence, in the place the user can
/// read it while the island is open (D70): over the editor, and on the card.
/// The closed island's notice is gone after a few seconds and is often never
/// seen. The line offers the buttons that fix the cause, such as choosing
/// another folder.
struct NookNotesProblemLine: View {
    var store: NookNotesStore
    let notice: NookNotesNotice

    /// The sentence for a notice, in the language in use.
    static func sentence(for notice: NookNotesNotice) -> String {
        let lang = LanguageManager.shared
        guard let subject = notice.subject else { return lang.t(notice.problemKey) }
        return lang.t(notice.problemKey, subject)
    }

    var body: some View {
        let lang = LanguageManager.shared
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: notice.symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.orange)
            Text(Self.sentence(for: notice))
                .font(.system(size: 10))
                .foregroundStyle(.orange)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            ForEach(notice.actions, id: \.self) { action in
                Button {
                    store.perform(action)
                } label: {
                    Text(lang.t(action.titleKey))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 7)
                        .frame(height: 16)
                        .background(Capsule().fill(.white.opacity(0.12)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
