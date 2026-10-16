import SwiftUI

/// Sizes of the GIF sheet. They live in a plain enum and not in the View,
/// because a closure in a View static traps when a nonisolated test reads
/// it.
enum NookGIFSheetLayout {
    static let rowSpacing: CGFloat = 6
    static let controlGap: CGFloat = 8
    static let titleHeight: CGFloat = 16
    /// The line under the title that says what a GIF is and where it goes.
    static let explainHeight: CGFloat = 14
    static let controlHeight: CGFloat = 22
    static let buttonHeight: CGFloat = 24
    /// The room between a segmented control's edge and its pill.
    static let segmentInset: CGFloat = 2
    static let buttonPadding: CGFloat = 12

    /// The height the sheet needs when both controls sit side by side and
    /// the size line fits beside the buttons: the title, the line under it,
    /// the controls and the buttons, with the gaps between. A card that shows the sheet
    /// needs at least this much under its header. The two minute sentence
    /// is wider than that line, so it drops to a row of its own and the
    /// sheet grows by about 20 points.
    static var wideHeight: CGFloat {
        titleHeight + explainHeight + controlHeight + buttonHeight + rowSpacing * 3
    }
}

/// How far the sheet has got in reading the video.
enum NookGIFSheetLoad: Equatable, Sendable {
    case loading
    case loaded(NookGIFSource)
    case unreadable
}

/// What the sheet says and whether Make is on, kept apart from the view so
/// tests reach it without building one.
enum NookGIFSheetRules {
    enum Status: Equatable {
        case loading
        case unreadable
        case tooLong
        case ready(estimatedBytes: Int64)
    }

    static func status(
        load: NookGIFSheetLoad,
        options: NookGIFOptions,
        maxDuration: TimeInterval = NookGIFMaker.maxDuration
    ) -> Status {
        switch load {
        case .loading:
            return .loading
        case .unreadable:
            return .unreadable
        case .loaded(let source):
            guard source.duration <= maxDuration else { return .tooLong }
            let bytes = NookGIFMaker.estimatedBytes(duration: source.duration, sourceSize: source.size, options: options)
            return .ready(estimatedBytes: bytes)
        }
    }

    /// True when Make works: the video was read and fits, and no conversion
    /// is still reading it (`isWaiting`).
    static func canMake(_ status: Status, isWaiting: Bool = false) -> Bool {
        guard !isWaiting else { return false }
        if case .ready = status { return true }
        return false
    }

    /// "Make a GIF from lecture.mov". The video is named, which tells people
    /// what the options are for; with no name it is the plain title.
    static func title(sourceName: String?) -> String {
        let lang = LanguageManager.shared
        guard let sourceName else { return lang.t("nook.gif.title") }
        return lang.t("nook.gif.titleFrom", sourceName)
    }

    /// The Localizable key for a width's name.
    static func titleKey(for width: NookGIFOptions.Width) -> String {
        switch width {
        case .small: "nook.gif.width.small"
        case .medium: "nook.gif.width.medium"
        case .large: "nook.gif.width.large"
        }
    }

    /// "4.2 MB", the way Finder writes a size.
    static func sizeText(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}

/// The GIF options the tray shows in place of its list: a width, a frame
/// rate, the size the GIF will be, and Cancel and Make. It reads the video
/// once for its length and size, which feed the estimate and the two
/// minute limit.
struct NookGIFSheet: View {
    let sourceURL: URL
    /// The video's name as the tray shows it, for the title.
    let sourceName: String?
    let onMake: (NookGIFOptions) -> Void
    let onCancel: () -> Void
    /// The name of the file a conversion is still running on, when that is
    /// the video. Make waits for it and says so.
    let waitingOn: String?

    private let maxDuration: TimeInterval
    private let isPreloaded: Bool
    @Environment(\.hangoverAccent) private var accent
    @State private var options: NookGIFOptions
    @State private var load: NookGIFSheetLoad

    init(
        sourceURL: URL,
        sourceName: String? = nil,
        waitingOn: String? = nil,
        onMake: @escaping (NookGIFOptions) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.sourceURL = sourceURL
        self.sourceName = sourceName
        self.waitingOn = waitingOn
        self.onMake = onMake
        self.onCancel = onCancel
        maxDuration = NookGIFMaker.maxDuration
        isPreloaded = false
        _options = State(initialValue: NookGIFOptions())
        _load = State(initialValue: .loading)
    }

    /// A sheet that already knows its video, which is how the render tests
    /// draw it: `ImageRenderer` never runs the task that reads the file.
    init(
        sourceURL: URL,
        sourceName: String? = nil,
        load: NookGIFSheetLoad,
        options: NookGIFOptions = NookGIFOptions(),
        maxDuration: TimeInterval = NookGIFMaker.maxDuration,
        waitingOn: String? = nil,
        onMake: @escaping (NookGIFOptions) -> Void = { _ in },
        onCancel: @escaping () -> Void = {}
    ) {
        self.sourceURL = sourceURL
        self.sourceName = sourceName
        self.waitingOn = waitingOn
        self.onMake = onMake
        self.onCancel = onCancel
        self.maxDuration = maxDuration
        isPreloaded = true
        _options = State(initialValue: options)
        _load = State(initialValue: load)
    }

    private var status: NookGIFSheetRules.Status {
        NookGIFSheetRules.status(load: load, options: options, maxDuration: maxDuration)
    }

    var body: some View {
        let lang = LanguageManager.shared
        VStack(alignment: .leading, spacing: NookGIFSheetLayout.rowSpacing) {
            VStack(alignment: .leading, spacing: 0) {
                Text(NookGIFSheetRules.title(sourceName: sourceName))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(height: NookGIFSheetLayout.titleHeight, alignment: .leading)
                Text(lang.t("nook.gif.explain"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: NookGIFSheetLayout.explainHeight, alignment: .leading)
            }
            .padding(.bottom, NookGIFSheetLayout.rowSpacing)
            controls
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: sourceURL) { await readVideo() }
    }

    private func readVideo() async {
        guard !isPreloaded else { return }
        load = .loading
        if let source = await NookGIFMaker.inspect(sourceURL) {
            load = .loaded(source)
        } else {
            load = .unreadable
        }
    }

    // MARK: Controls

    /// The two controls side by side, or one over the other in a card too
    /// narrow for both.
    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: NookGIFSheetLayout.controlGap) {
                widthControl
                rateControl
            }
            VStack(spacing: NookGIFSheetLayout.rowSpacing) {
                widthControl
                rateControl
            }
        }
    }

    private var widthControl: some View {
        let lang = LanguageManager.shared
        return NookGIFSegments(
            segments: NookGIFOptions.Width.allCases.map { width in
                NookGIFSegments<NookGIFOptions.Width>.Segment(
                    value: width,
                    title: lang.t(NookGIFSheetRules.titleKey(for: width)),
                    help: lang.t("nook.gif.width.help", width.rawValue)
                )
            },
            selection: $options.width
        )
    }

    private var rateControl: some View {
        let lang = LanguageManager.shared
        return NookGIFSegments(
            segments: NookGIFOptions.frameRates.map { rate in
                NookGIFSegments<Int>.Segment(
                    value: rate,
                    title: lang.t("nook.gif.fps", rate),
                    help: lang.t("nook.gif.fps", rate)
                )
            },
            selection: $options.framesPerSecond
        )
    }

    // MARK: Footer

    /// The size line with Cancel and Make beside it, or the buttons under
    /// the line in a card too narrow for both.
    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: NookGIFSheetLayout.controlGap) {
                statusLine(isSingleLine: true)
                Spacer(minLength: NookGIFSheetLayout.controlGap)
                buttons
            }
            VStack(alignment: .leading, spacing: NookGIFSheetLayout.rowSpacing) {
                statusLine(isSingleLine: false)
                HStack(spacing: NookGIFSheetLayout.controlGap) {
                    Spacer(minLength: 0)
                    buttons
                }
            }
        }
    }

    private func statusLine(isSingleLine: Bool) -> some View {
        let (text, color) = statusText
        return Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(isSingleLine ? 1 : 2)
            .fixedSize(horizontal: isSingleLine, vertical: true)
            .frame(maxWidth: isSingleLine ? nil : .infinity, alignment: .leading)
    }

    private var statusText: (String, Color) {
        let lang = LanguageManager.shared
        switch status {
        case .loading:
            return (lang.t("nook.gif.estimate.loading"), .white.opacity(0.35))
        case .unreadable:
            return (lang.t("nook.gif.unreadable"), .orange)
        case .tooLong:
            return (lang.t("nook.gif.tooLong"), .orange)
        case .ready(let bytes):
            return (lang.t("nook.gif.estimate", NookGIFSheetRules.sizeText(bytes: bytes)), .white.opacity(0.6))
        }
    }

    private var buttons: some View {
        let lang = LanguageManager.shared
        let canMake = NookGIFSheetRules.canMake(status, isWaiting: waitingOn != nil)
        let waitHelp = waitingOn.map { NookConvertRules.waitText(forBusyFileNamed: $0) } ?? ""
        return HStack(spacing: NookGIFSheetLayout.controlGap) {
            Button(action: onCancel) {
                Text(lang.t("nook.gif.cancel"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, NookGIFSheetLayout.buttonPadding)
                    .frame(height: NookGIFSheetLayout.buttonHeight)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                onMake(options)
            } label: {
                Text(lang.t("nook.gif.make"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent.textOnHighlight(.white))
                    .padding(.horizontal, NookGIFSheetLayout.buttonPadding)
                    .frame(height: NookGIFSheetLayout.buttonHeight)
                    .background(Capsule().fill(accent.highlight(.orange)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canMake)
            .opacity(canMake ? 1 : 0.4)
            .help(waitHelp)
        }
    }
}

/// A row of choices with the picked one filled, like the pills in the
/// design kit. The sheet uses one for the width and one for the frame rate.
private struct NookGIFSegments<Value: Hashable>: View {
    struct Segment {
        let value: Value
        let title: String
        let help: String
    }

    let segments: [Segment]
    @Binding var selection: Value
    @Environment(\.hangoverAccent) private var accent

    var body: some View {
        HStack(spacing: NookGIFSheetLayout.segmentInset) {
            ForEach(segments, id: \.value) { segment in
                segmentButton(segment)
            }
        }
        .padding(NookGIFSheetLayout.segmentInset)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(Color.white.opacity(0.1)))
        .motionAnimation(Motion.selection, value: selection)
    }

    private func segmentButton(_ segment: Segment) -> some View {
        let isSelected = segment.value == selection
        let height = NookGIFSheetLayout.controlHeight - NookGIFSheetLayout.segmentInset * 2
        return Button {
            selection = segment.value
        } label: {
            Text(segment.title)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isSelected ? accent.textOnHighlight(.black) : Color.white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(Capsule().fill(isSelected ? accent.highlight(.orange) : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(segment.help)
        .accessibilityLabel(segment.help)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
