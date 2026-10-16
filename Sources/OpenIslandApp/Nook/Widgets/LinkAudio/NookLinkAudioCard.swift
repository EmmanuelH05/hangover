import SwiftUI

/// The Link to MP3 card: a field for a link with a Paste button beside it,
/// then one row for each job. A line under the field says what is wrong
/// with a link or with the setup. With a program missing the field is off
/// and the line names it and the command that gets it.
///
/// Small shows the field and one row, medium two rows, large five. More
/// jobs than rows scroll. The card never changes height.
struct NookLinkAudioCard: View {
    var service: NookLinkAudioService
    private let isStill: Bool
    @Environment(\.nookWidgetSize) private var size
    @State private var text = ""

    init(nook: NookModel) {
        service = nook.linkAudio
        isStill = false
    }

    /// A card on a service of its own, which is how the render tests draw
    /// it. `isStill` swaps what `ImageRenderer` cannot draw for look-alikes.
    init(service: NookLinkAudioService, isStill: Bool = false, text: String = "") {
        self.service = service
        self.isStill = isStill
        _text = State(initialValue: text)
    }

    static func height(for size: NookWidgetSize) -> CGFloat {
        NookLinkAudioCardLayout.height(for: size)
    }

    var body: some View {
        let lang = LanguageManager.shared
        VStack(alignment: .leading, spacing: 6) {
            NookCardHeader(title: lang.t("nook.linkAudio.title"), systemImage: "arrow.down.circle")
            entryRow
            if let line = statusLine {
                Text(line)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            jobList
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // Fill the cell the grid gives us; the grid owns the outer height.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NookCardBackground())
        .onAppear { service.refreshTools() }
        // With the card gone nobody is typing in it.
        .onDisappear { service.nook?.setDraft(.linkAudio, isUnsaved: false) }
    }

    /// The missing-program line comes first: nothing else can be done then.
    private var statusLine: String? {
        let lang = LanguageManager.shared
        if let key = service.toolStatus.missingLineKey { return lang.t(key) }
        return service.problem.map { lang.t($0.messageKey) }
    }

    // MARK: Field

    private var entryRow: some View {
        let lang = LanguageManager.shared
        let isOn = service.canSubmit
        return HStack(spacing: 6) {
            NookLinkAudioField(text: $text, prompt: lang.t("nook.linkAudio.field.prompt"), isStill: isStill, onSubmit: submitTyped)
                .disabled(!isOn)
                .opacity(isOn ? 1 : 0.45)
            Button(action: pasteClipboard) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 10, weight: .semibold))
                    if size != .small {
                        Text(lang.t("nook.linkAudio.paste"))
                            .font(.system(size: 10.5, weight: .semibold))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 8)
                .frame(minWidth: 26, minHeight: 24)
                .background(Capsule().fill(Color.white.opacity(0.1)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!isOn)
            .opacity(isOn ? 1 : 0.45)
            .help(lang.t("nook.linkAudio.paste.help"))
            .accessibilityLabel(lang.t("nook.linkAudio.paste"))
        }
        .frame(height: 24)
        .onChange(of: text) { _, typed in
            service.nook?.setDraft(.linkAudio, isUnsaved: NookDraft.isUnsaved(typed))
            // The line was about the text before this edit.
            service.clearProblem()
        }
    }

    /// A link that was taken empties the field. One that was refused stays,
    /// which leaves it to be fixed.
    private func submitTyped() {
        if case .queued = service.submit(text) { text = "" }
    }

    private func pasteClipboard() {
        service.pasteAndSave()
    }

    // MARK: Jobs

    @ViewBuilder
    private var jobList: some View {
        let jobs = service.jobs
        if jobs.isEmpty {
            Text(LanguageManager.shared.t(size == .small ? "nook.linkAudio.empty.short" : "nook.linkAudio.empty.long"))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(size == .small ? 3 : 2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if isStill {
            // A picture cannot scroll: it shows the rows that fit.
            GeometryReader { proxy in
                rows(Array(jobs.prefix(NookLinkAudioCardLayout.rowCapacity(height: proxy.size.height))))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                rows(jobs)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func rows(_ jobs: [NookLinkAudioJob]) -> some View {
        VStack(alignment: .leading, spacing: NookLinkAudioRow.spacing) {
            ForEach(jobs) { job in
                NookLinkAudioRow(
                    job: job,
                    isCompact: size == .small,
                    onCancel: { service.cancel(job.id) },
                    onShow: { service.showInFinder(job.id) }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// Pure layout rules for the card. A plain enum on purpose: the window-sizing
/// math and the tests call it off the main actor.
enum NookLinkAudioCardLayout {
    static let mediumHeight: CGFloat = 140
    static let largeHeight: CGFloat = 240

    /// Height at each size. Small rows always use the grid's shared height.
    static func height(for size: NookWidgetSize) -> CGFloat {
        switch size {
        case .small: NookWidgetLayout.smallHeight
        case .medium: mediumHeight
        case .large: largeHeight
        }
    }

    /// How many rows fit in `height`, at least one.
    static func rowCapacity(height: CGFloat) -> Int {
        guard height > 0 else { return 1 }
        let step = NookLinkAudioRow.height + NookLinkAudioRow.spacing
        return max(1, Int((height + NookLinkAudioRow.spacing) / step))
    }
}

// MARK: - Field

/// The field for a link. A still copy stands in for the text field, which
/// `ImageRenderer` cannot draw.
private struct NookLinkAudioField: View {
    @Binding var text: String
    let prompt: String
    let isStill: Bool
    let onSubmit: () -> Void

    var body: some View {
        Group {
            if isStill {
                Text(text.isEmpty ? prompt : text)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(text.isEmpty ? 0.35 : 0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(prompt, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
                    .onSubmit(onSubmit)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)
        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.08)))
    }
}

// MARK: - Sample

extension NookLinkAudioCard {
    /// A still picture of the card for the Settings preview, which never
    /// reads the user's own jobs.
    static func sample(size: NookWidgetSize) -> some View {
        NookLinkAudioSampleContent(size: size)
    }
}

private struct NookLinkAudioSampleContent: View {
    let size: NookWidgetSize

    private static let link = try? NookLinkAudioLink.check("https://example.com/track").get()
    /// A key the producer wrote and a guessed tempo. The app guesses no key
    /// from the sound (D66).
    private static let sampleFindings = NookLinkAudioFindings(
        key: NookLinkAudioFound(value: NookMusicalKey(tonic: 9, mode: .minor), isGuess: false),
        bpm: NookLinkAudioFound(value: 92, isGuess: true)
    )

    var body: some View {
        let lang = LanguageManager.shared
        VStack(alignment: .leading, spacing: 6) {
            NookCardHeader(title: lang.t("nook.linkAudio.title"), systemImage: "arrow.down.circle")
            HStack(spacing: 6) {
                Text(lang.t("nook.linkAudio.field.prompt"))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.08)))
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 26, height: 24)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
            }
            if let link = Self.link {
                NookLinkAudioRow(
                    job: NookLinkAudioJob(id: UUID(), link: link, title: "Sample track", phase: .downloading(fraction: 0.4)),
                    isCompact: size == .small
                )
                if size != .small {
                    NookLinkAudioRow(
                        job: NookLinkAudioJob(
                            id: UUID(),
                            link: link,
                            title: "Sample interview",
                            phase: .done(nil),
                            findings: Self.sampleFindings
                        ),
                        isCompact: false
                    )
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }
}
