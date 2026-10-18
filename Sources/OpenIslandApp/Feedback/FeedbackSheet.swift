import SwiftUI

/// The Send feedback sheet (F7, S8). Its words come through
/// `LanguageManager.shared.t`, which tracks the app's language.
struct FeedbackSheet: View {
    var presenter: FeedbackPresenter

    var body: some View {
        let lang = LanguageManager.shared
        @Bindable var presenter = presenter

        VStack(alignment: .leading, spacing: 0) {
            Text(lang.t("feedback.title"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Text(lang.t("feedback.line"))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 3)

            label(lang.t("feedback.what")).padding(.top, 14)
            Picker("", selection: $presenter.draft.kind) {
                ForEach(FeedbackKind.allCases, id: \.self) { kind in
                    Text(lang.t(kind.titleKey)).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 5)

            label(lang.t("feedback.tell")).padding(.top, 12)
            TextEditor(text: $presenter.draft.text)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 90)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .padding(.top, 5)

            Toggle(isOn: $presenter.draft.includesDetails) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang.t("feedback.details"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                    Text(lang.t("feedback.details.line", presenter.details.line))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .toggleStyle(.switch)
            .padding(.top, 12)

            Group {
                if presenter.outcome == .copied {
                    Text(lang.t("feedback.copied", presenter.address))
                        .foregroundStyle(V6Palette.paper)
                } else {
                    Text(lang.t("feedback.mail.line"))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .font(.system(size: 10))
            .padding(.top, 10)

            HStack(spacing: 8) {
                Spacer()
                Button(lang.t("feedback.cancel")) { presenter.dismiss() }
                    .buttonStyle(UpdateCardButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
                Button(lang.t("feedback.open")) { presenter.send() }
                    .buttonStyle(UpdateCardButtonStyle(prominent: true))
                    // Command-Return, not Return: a plain Return in the
                    // text box starts a new line and must not open Mail.
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.top, 10)
        }
        .padding(16)
        .frame(width: 520)
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.white.opacity(0.45))
    }
}
