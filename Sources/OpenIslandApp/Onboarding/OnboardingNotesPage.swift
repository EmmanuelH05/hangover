import SwiftUI

/// What the notes page says about each place a quick note can go (D40,
/// D44). The line beside a case says where it comes from.
enum OnboardingNotesGuide {
    /// The place's name, as Settings words it ("Markdown file", "Apple
    /// Notes").
    static func titleKey(for destination: NookNotesDestination) -> String {
        "onboarding.notes.\(destination.rawValue).title"
    }

    /// The one line on a place's card.
    static func textKey(for destination: NookNotesDestination) -> String {
        "onboarding.notes.\(destination.rawValue).text"
    }

    static func symbol(for destination: NookNotesDestination) -> String {
        switch destination {
        case .file: "doc.text"
        case .appleNotes: "note.text"
        }
    }

    /// The label of the button under the try-it step: the file in Finder,
    /// or the Notes app.
    static func showKey(for destination: NookNotesDestination) -> String {
        destination == .file ? "onboarding.notes.show.file" : "onboarding.notes.show.appleNotes"
    }
}

/// The tour's page for where quick notes go, shown only while the notes
/// widget is on the page: a card for each place, what the pick means, and
/// one step that ticks when a note is saved on the real island (D44). A
/// pick writes the preference Settings writes; the folder is chosen in the
/// system panel the app opens, never in this page.
struct OnboardingNotesPage: View {
    let context: OnboardingPageContext

    private var state: OnboardingState { context.state }

    var body: some View {
        OnboardingPageScaffold(
            page: .notes,
            context: context,
            title: context.t("onboarding.notes.title"),
            text: context.t("onboarding.notes.body"),
            footnote: context.t("onboarding.notes.note"),
            gap: 12
        ) {
            VStack(alignment: .leading, spacing: 12) {
                OnboardingLiveLine(text: context.t("onboarding.live.line"))

                VStack(spacing: 8) {
                    ForEach(NookNotesDestination.allCases) { destination in card(destination) }
                }

                detail
                tryIt
            }
        }
    }

    private func card(_ destination: NookNotesDestination) -> some View {
        let name = context.t(OnboardingNotesGuide.titleKey(for: destination))
        return OnboardingChoiceCard(isSelected: state.notesDestination == destination) {
            context.actions.setNotesDestination(destination)
        } content: {
            HStack(spacing: 11) {
                OnboardingSymbolPlate(symbol: OnboardingNotesGuide.symbol(for: destination), size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(OnboardingStyle.primaryText)
                    Text(context.t(OnboardingNotesGuide.textKey(for: destination)))
                        .font(.system(size: 11.5))
                        .foregroundStyle(OnboardingStyle.secondaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 13)
            // Room for the tick of the picked card.
            .padding(.trailing, 30)
            .frame(maxHeight: .infinity)
        }
        .frame(height: 68)
        .accessibilityLabel(name)
    }

    // MARK: What the pick means

    @ViewBuilder
    private var detail: some View {
        switch state.notesDestination {
        case .file: fileDetail
        case .appleNotes: appleNotesDetail
        }
    }

    private var fileDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(context.t("onboarding.notes.file.where"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OnboardingStyle.primaryText)
            Text(state.notesFilePath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(OnboardingStyle.secondaryText)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(OnboardingCardBackground())
                .accessibilityLabel(state.notesFilePath)
            Button(context.t("onboarding.notes.file.choose")) { context.actions.chooseNotesFolder() }
                .buttonStyle(OnboardingSecondaryButtonStyle(height: 28))
            Text(context.t("onboarding.notes.file.any"))
                .font(.system(size: 11.5))
                .foregroundStyle(OnboardingStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var appleNotesDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(context.lang.t("onboarding.notes.appleNotes.where", NookAppleNotesLine.noteTitle))
                .font(.system(size: 12.5))
                .foregroundStyle(OnboardingStyle.primaryText.opacity(0.88))
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
            Text(context.t("onboarding.notes.appleNotes.ask"))
                .font(.system(size: 11.5))
                .foregroundStyle(OnboardingStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Try it

    private var tryIt: some View {
        let isDone = state.hasSavedNote
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isDone ? OnboardingStyle.paper : OnboardingStyle.faintText)
                    .frame(width: 18)
                Text(context.t(isDone ? "onboarding.notes.try.done" : "onboarding.notes.try"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(OnboardingStyle.primaryText.opacity(isDone ? 1 : 0.85))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(context.t(isDone ? "onboarding.arrange.done" : "onboarding.arrange.todo"))

            Button(context.t(OnboardingNotesGuide.showKey(for: state.notesDestination))) {
                context.actions.showNotes()
            }
            .buttonStyle(OnboardingSecondaryButtonStyle(height: 28))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OnboardingCardBackground())
    }
}
