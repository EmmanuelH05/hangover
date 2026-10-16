import SwiftUI

/// A part of the idle card, for saying what shares a row.
enum NookRecordSetupPart: Hashable, Sendable {
    /// The card's name, or the last result's line where there is no row for it.
    case title
    /// Standard or High.
    case quality
    /// Full screen, Window or Area.
    case capture
    /// Face cam, Voice and Mac sound.
    case switches
    case record
    /// The last result, in a row of its own with room for two lines.
    case status
}

/// Pure layout rules for the Record card. A plain enum on purpose: the
/// window-sizing math and the tests call it off the main actor, and a closure
/// in a View static would trap there.
///
/// Every size is a column of rows. The height is what the rows and the gaps
/// between them add up to, so a row cannot be added without the card growing
/// with it. Every row runs the card's whole width: what shares a row is spread
/// from one edge to the other, and what has a row to itself is stretched.
enum NookRecordCardLayout {
    static let verticalPadding: CGFloat = 12
    /// The title row, as tall as the quality choice that shares it.
    static let headerHeight: CGFloat = 16
    static let controlHeight: CGFloat = 26
    static let buttonHeight: CGFloat = 28
    static let statusHeight: CGFloat = 26

    static func spacing(for size: NookWidgetSize) -> CGFloat {
        switch size {
        case .small: 8
        case .medium: 5
        case .large: 7.5
        }
    }

    /// The rows of the setup view from top to bottom, and what is on each.
    ///
    /// - Small: the capture choice, the three switches and the button, each on
    ///   a row of its own and stretched across it. It has no header and no
    ///   quality choice, for want of room.
    /// - Medium: a header that turns into the last result's line, with the
    ///   quality choice at its right; the capture choice at the left of one row
    ///   and the switches at its right; the button below, full width.
    /// - Large: the header and quality choice, the capture choice, the switches
    ///   and the button each across a row, and a line for the last result.
    static func setupRows(for size: NookWidgetSize) -> [[NookRecordSetupPart]] {
        switch size {
        case .small: [[.capture], [.switches], [.record]]
        case .medium: [[.title, .quality], [.capture, .switches], [.record]]
        case .large: [[.title, .quality], [.capture], [.switches], [.record], [.status]]
        }
    }

    static func height(of part: NookRecordSetupPart) -> CGFloat {
        switch part {
        case .title, .quality: headerHeight
        case .capture, .switches: controlHeight
        case .record: buttonHeight
        case .status: statusHeight
        }
    }

    /// One height per row of `setupRows`: the tallest part on it.
    static func rowHeights(for size: NookWidgetSize) -> [CGFloat] {
        setupRows(for: size).map { row in row.map(height(of:)).max() ?? 0 }
    }

    /// Room the rows need, without the card's padding.
    static func contentHeight(for size: NookWidgetSize) -> CGFloat {
        let rows = rowHeights(for: size)
        return rows.reduce(0, +) + spacing(for: size) * CGFloat(rows.count - 1)
    }

    /// The small card has no line for a result. A failure takes the place of the
    /// capture choice there, and stays until the next press of Record or a tap
    /// on it, so a notice for something else cannot cover it. A plain "saved" is
    /// not a failure: the tray tile says it.
    static func smallCardShowsStatus(_ status: NookRecordStatusLine?) -> Bool {
        status?.isWarning == true
    }

    /// Cancel shows through the whole count and through the start after it,
    /// when the engine is asking for permission or waiting on a picture.
    /// Nothing may leave a person with no way out of a start that hangs.
    static func showsCancel(secondsLeft: Int) -> Bool {
        secondsLeft >= 0
    }

    /// The count and the clock are larger on the large card, which has the
    /// room, and the buttons grow with them.
    static func countFontSize(for size: NookWidgetSize) -> CGFloat {
        size == .large ? 48 : 34
    }

    static func clockFontSize(for size: NookWidgetSize) -> CGFloat {
        size == .large ? 30 : 20
    }

    static func roundButtonSize(for size: NookWidgetSize) -> CGSize {
        size == .large ? CGSize(width: 44, height: 34) : CGSize(width: 30, height: controlHeight)
    }

    /// A switch scaled down a little, for a row that is short of room.
    static func switchHeight(isCompact: Bool) -> CGFloat {
        isCompact ? controlHeight - 2 : controlHeight
    }

    static func switchPadding(isCompact: Bool) -> CGFloat {
        isCompact ? 6 : 8
    }

    /// Height at each size. Small rows always use the grid's shared height.
    static func height(for size: NookWidgetSize) -> CGFloat {
        switch size {
        case .small: NookWidgetLayout.smallHeight
        case .medium, .large: contentHeight(for: size) + verticalPadding * 2
        }
    }
}

/// A line about the last recording: what it came to, or why it did not.
struct NookRecordStatusLine: Equatable {
    var text: String
    var isWarning: Bool

    /// What the card says about where the last recording ended up. Nil while
    /// there is nothing to say.
    static func of(_ phase: NookRecordPhase) -> NookRecordStatusLine? {
        let lang = LanguageManager.shared
        switch phase {
        case let .failed(failure):
            let notice = NookRecordNotice.failed(failure, lang: lang)
            return NookRecordStatusLine(text: notice.text, isWarning: notice.isWarning)
        case let .finished(_, endedBy, notes):
            let notice = NookRecordNotice.saved(endedBy: endedBy, notes: notes, lang: lang)
            return NookRecordStatusLine(text: notice.text, isWarning: notice.isWarning)
        case .idle, .countdown, .recording, .paused, .saving:
            return nil
        }
    }
}

extension NookRecordCapture {
    var symbol: String {
        switch self {
        case .fullScreen: "display"
        case .window: "macwindow"
        case .area: "rectangle.dashed"
        }
    }
}

/// The Record widget's tile on the Nook page. Idle it is the setup: what to
/// capture, the three switches, the quality and a red Record button. Once
/// pressed it is the count, then the elapsed time with Pause and Stop.
///
/// The card never changes height; the sizes come from `NookRecordCardLayout`.
struct NookRecordCard: View {
    var nook: NookModel
    @Environment(\.nookWidgetSize) private var size

    static func height(for size: NookWidgetSize) -> CGFloat {
        NookRecordCardLayout.height(for: size)
    }

    var body: some View {
        let record = nook.record
        content(record)
            .padding(.horizontal, 14)
            .padding(.vertical, NookRecordCardLayout.verticalPadding)
            // Fill the cell the grid gives us; the grid owns the outer height.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(NookCardBackground())
            // A long press enters edit mode before the button lets go. That
            // release must not also start a recording.
            .disabled(nook.isEditingLayout)
    }

    @ViewBuilder
    private func content(_ record: NookRecordModel) -> some View {
        switch record.phase {
        case .idle, .finished, .failed:
            NookRecordSetupView(
                size: size,
                options: Binding(get: { record.options }, set: { record.options = $0 }),
                status: NookRecordStatusLine.of(record.phase),
                onRecord: { Task { await record.toggleFromUser() } },
                onDismissStatus: { record.dismissResult() }
            )
        case let .countdown(secondsLeft):
            NookRecordCountdownView(size: size, secondsLeft: secondsLeft, onCancel: { Task { await record.stop() } })
        case .recording, .paused:
            NookRecordLiveView(size: size, record: record)
        case .saving:
            NookRecordWaitView(titleKey: "nook.record.state.saving")
        }
    }
}

// MARK: - Setup

/// The idle card. It takes plain values, which is what lets the Settings
/// preview draw it from sample ones.
private struct NookRecordSetupView: View {
    let size: NookWidgetSize
    @Binding var options: NookRecordOptions
    let status: NookRecordStatusLine?
    let onRecord: () -> Void
    var onDismissStatus: () -> Void = {}

    private var spacing: CGFloat { NookRecordCardLayout.spacing(for: size) }

    var body: some View {
        switch size {
        case .small: small
        case .medium: medium
        case .large: large
        }
    }

    /// The capture choice, the switches and the button, each across its row.
    private var small: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if NookRecordCardLayout.smallCardShowsStatus(status), let status {
                NookRecordSmallStatus(status: status, onDismiss: onDismissStatus)
                    .frame(height: NookRecordCardLayout.controlHeight)
            } else {
                NookRecordCaptureControl(selection: $options.capture, labels: .none, fillsWidth: true)
                    .frame(height: NookRecordCardLayout.controlHeight)
            }
            NookRecordSwitchRow(options: $options, showsTitles: false, fillsWidth: true)
                .frame(height: NookRecordCardLayout.controlHeight)
            NookRecordButton(showsTitle: true, action: onRecord)
        }
    }

    /// The capture choice at the left of one row and the switches at its right.
    /// Where a language needs more room than the row has, the switches lose
    /// their names, then shrink a little, and the capture choice drops the
    /// name of the one that is chosen, before the row gives up being one row.
    private var medium: some View {
        VStack(alignment: .leading, spacing: spacing) {
            NookRecordHeaderRow(status: status, quality: $options.quality)
                .frame(height: NookRecordCardLayout.headerHeight)
            ViewThatFits(in: .horizontal) {
                mediumTopRow(captureLabels: .selectedOnly, switchTitles: true, isCompact: false)
                mediumTopRow(captureLabels: .selectedOnly, switchTitles: false, isCompact: false)
                mediumTopRow(captureLabels: .none, switchTitles: false, isCompact: true)
            }
            .frame(height: NookRecordCardLayout.controlHeight)
            NookRecordButton(showsTitle: true, action: onRecord)
        }
    }

    private func mediumTopRow(captureLabels: NookRecordCaptureLabels, switchTitles: Bool, isCompact: Bool) -> some View {
        HStack(spacing: 8) {
            NookRecordCaptureControl(selection: $options.capture, labels: captureLabels)
            Spacer(minLength: 0)
            NookRecordSwitchRow(options: $options, showsTitles: switchTitles, isCompact: isCompact)
        }
    }

    /// Each row runs across the card. With no result to report the last row is
    /// not there, and its room goes into the gaps between the others. The
    /// button stays at the foot of the card and no band is left empty.
    private var large: some View {
        VStack(alignment: .leading, spacing: 0) {
            NookRecordHeaderRow(status: nil, quality: $options.quality)
                .frame(height: NookRecordCardLayout.headerHeight)
            Spacer(minLength: spacing)
            ViewThatFits(in: .horizontal) {
                NookRecordCaptureControl(selection: $options.capture, labels: .all, fillsWidth: true)
                NookRecordCaptureControl(selection: $options.capture, labels: .selectedOnly, fillsWidth: true)
            }
            .frame(height: NookRecordCardLayout.controlHeight)
            Spacer(minLength: spacing)
            ViewThatFits(in: .horizontal) {
                NookRecordSwitchRow(options: $options, showsTitles: true, fillsWidth: true)
                NookRecordSwitchRow(options: $options, showsTitles: false, fillsWidth: true)
            }
            .frame(height: NookRecordCardLayout.controlHeight)
            Spacer(minLength: spacing)
            NookRecordButton(showsTitle: true, action: onRecord)
            if let status {
                Spacer(minLength: spacing)
                NookRecordStatusText(status: status)
                    .frame(height: NookRecordCardLayout.statusHeight, alignment: .top)
            }
        }
    }
}

/// A failure on the small card, in the place of the capture choice. A tap clears
/// it and brings the choice back.
private struct NookRecordSmallStatus: View {
    let status: NookRecordStatusLine
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(status.text)
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(status.text)
        .accessibilityLabel(status.text)
    }
}

/// The card's title row. With a result to report it takes the title's place
/// at the medium size, which has no row to spare.
private struct NookRecordHeader: View {
    let status: NookRecordStatusLine?

    var body: some View {
        if let status {
            HStack(spacing: 6) {
                Image(systemName: status.isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    .font(.system(size: 10, weight: .semibold))
                Text(status.text)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .foregroundStyle(status.isWarning ? Color.orange : Color.white.opacity(0.5))
            .help(status.text)
        } else {
            NookCardHeader(title: LanguageManager.shared.t("nook.record.title"), systemImage: "record.circle")
        }
    }
}

/// The title row with the quality choice at its right end, which keeps the
/// choice on the card and the row full.
private struct NookRecordHeaderRow: View {
    let status: NookRecordStatusLine?
    @Binding var quality: NookRecordQuality

    var body: some View {
        HStack(spacing: 8) {
            NookRecordHeader(status: status)
            NookRecordQualityControl(selection: $quality)
        }
    }
}

/// The last result under the button, centered under it, with room for two lines.
private struct NookRecordStatusText: View {
    let status: NookRecordStatusLine

    var body: some View {
        Text(status.text)
            .font(.system(size: 10.5))
            .foregroundStyle(status.isWarning ? Color.orange : Color.white.opacity(0.5))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }
}

/// Which capture choices carry their name beside the symbol.
private enum NookRecordCaptureLabels {
    case none
    case selectedOnly
    case all

    func showsTitle(isSelected: Bool) -> Bool {
        switch self {
        case .none: false
        case .selectedOnly: isSelected
        case .all: true
        }
    }
}

/// Full screen, Window, Area. The chosen one is lit; where room is short the
/// others are symbols alone. With `fillsWidth` the three share the width
/// equally, where a row has the card's whole width to fill.
private struct NookRecordCaptureControl: View {
    @Binding var selection: NookRecordCapture
    let labels: NookRecordCaptureLabels
    var fillsWidth = false

    var body: some View {
        let lang = LanguageManager.shared
        HStack(spacing: 2) {
            ForEach(NookRecordCapture.allCases) { capture in
                let isSelected = selection == capture
                Button {
                    withMotion(Motion.selection) { selection = capture }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: capture.symbol)
                            .font(.system(size: 11, weight: .semibold))
                        if labels.showsTitle(isSelected: isSelected) {
                            Text(lang.t(capture.titleKey))
                                .font(.system(size: 10.5, weight: .semibold))
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.55))
                    .padding(.horizontal, 8)
                    .frame(minWidth: 28, maxWidth: fillsWidth ? .infinity : nil, maxHeight: .infinity)
                    .background(
                        Capsule().fill(Color.white.opacity(isSelected ? 0.18 : 0))
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(lang.t(capture.titleKey))
                .accessibilityLabel(lang.t(capture.titleKey))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .fixedSize(horizontal: !fillsWidth, vertical: true)
    }
}

/// Standard or High, small enough to share the title's row.
private struct NookRecordQualityControl: View {
    @Binding var selection: NookRecordQuality

    var body: some View {
        let lang = LanguageManager.shared
        HStack(spacing: 1) {
            ForEach(NookRecordQuality.allCases) { quality in
                let isSelected = selection == quality
                Button {
                    withMotion(Motion.selection) { selection = quality }
                } label: {
                    Text(lang.t(quality.titleKey))
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.55))
                        .padding(.horizontal, 8)
                        .frame(maxHeight: .infinity)
                        .background(Capsule().fill(Color.white.opacity(isSelected ? 0.18 : 0)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(1)
        .frame(height: NookRecordCardLayout.headerHeight)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .fixedSize()
    }
}

/// Face cam, Voice and Mac sound. With `fillsWidth` the three share the width
/// equally. `isCompact` scales them down a little for a row short of room.
private struct NookRecordSwitchRow: View {
    @Binding var options: NookRecordOptions
    let showsTitles: Bool
    var fillsWidth = false
    var isCompact = false

    var body: some View {
        // One window can never hold the bubble, so the switch is off and out of
        // reach there, and says why.
        let faceCam = NookRecordRules.faceCamSwitch(capture: options.capture, wanted: options.faceCam)
        HStack(spacing: 4) {
            NookRecordSwitch(
                symbol: "person.crop.circle", titleKey: "nook.record.toggle.faceCam",
                isOn: Binding(get: { faceCam.isOn }, set: { options.faceCam = $0 }),
                isEnabled: faceCam.isEnabled, helpKey: faceCam.helpKey, showsTitle: showsTitles,
                fillsWidth: fillsWidth, isCompact: isCompact
            )
            NookRecordSwitch(
                symbol: "mic", titleKey: "nook.record.toggle.voice", isOn: $options.voice, showsTitle: showsTitles,
                fillsWidth: fillsWidth, isCompact: isCompact
            )
            NookRecordSwitch(
                symbol: "speaker.wave.2", titleKey: "nook.record.toggle.macSound", isOn: $options.macSound, showsTitle: showsTitles,
                fillsWidth: fillsWidth, isCompact: isCompact
            )
        }
        .fixedSize(horizontal: !fillsWidth, vertical: true)
    }
}

private struct NookRecordSwitch: View {
    let symbol: String
    let titleKey: String
    @Binding var isOn: Bool
    var isEnabled = true
    /// Shown instead of the title when the switch is out of reach.
    var helpKey: String?
    let showsTitle: Bool
    var fillsWidth = false
    var isCompact = false

    var body: some View {
        let title = LanguageManager.shared.t(titleKey)
        Button {
            withMotion(Motion.selection) { isOn.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                if showsTitle {
                    Text(title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white.opacity(isOn ? 0.95 : 0.45))
            .padding(.horizontal, NookRecordCardLayout.switchPadding(isCompact: isCompact))
            .frame(
                minWidth: isCompact ? 26 : 28,
                maxWidth: fillsWidth ? .infinity : nil,
                minHeight: NookRecordCardLayout.switchHeight(isCompact: isCompact)
            )
            .background(Capsule().fill(Color.white.opacity(isOn ? 0.18 : 0.07)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(helpKey.map { LanguageManager.shared.t($0) } ?? title)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// The red Record button. It has a row to itself and runs the card's width.
private struct NookRecordButton: View {
    let showsTitle: Bool
    let action: () -> Void

    var body: some View {
        let title = LanguageManager.shared.t("nook.record.button.record")
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "record.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                if showsTitle {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: NookRecordCardLayout.buttonHeight, maxHeight: NookRecordCardLayout.buttonHeight)
            .background(Capsule().fill(Color.red.opacity(0.85)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(title)
    }
}

// MARK: - Count, recording, saving

private struct NookRecordCountdownView: View {
    let size: NookWidgetSize
    let secondsLeft: Int
    let onCancel: () -> Void

    var body: some View {
        let lang = LanguageManager.shared
        HStack(spacing: 12) {
            if secondsLeft > 0 {
                Text("\(secondsLeft)")
                    .font(.system(size: NookRecordCardLayout.countFontSize(for: size), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            } else {
                // The count is over and the engine is starting.
                ProgressView().controlSize(.small)
                Text(lang.t("nook.record.state.starting"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
            if NookRecordCardLayout.showsCancel(secondsLeft: secondsLeft) {
                NookRecordTextButton(titleKey: "nook.record.button.cancel", action: onCancel)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

/// The wait for the file to close. It has nothing for a right side and sits in
/// the middle of the card.
private struct NookRecordWaitView: View {
    let titleKey: String

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            ProgressView().controlSize(.small)
            Text(LanguageManager.shared.t(titleKey))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }
}

/// The elapsed time with Pause or Resume, and Stop. Where the clock and the
/// buttons cannot share a row the clock is centered above them and the two
/// buttons share the width.
private struct NookRecordLiveView: View {
    let size: NookWidgetSize
    var record: NookRecordModel

    var body: some View {
        let lang = LanguageManager.shared
        let isPaused: Bool = if case .paused = record.phase { true } else { false }
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                clock(isPaused: isPaused)
                Spacer(minLength: 0)
                buttons(isPaused: isPaused, lang: lang, fillsWidth: false)
            }
            VStack(spacing: 8) {
                clock(isPaused: isPaused)
                buttons(isPaused: isPaused, lang: lang, fillsWidth: true)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func clock(isPaused: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isPaused ? Color.yellow : Color.red)
                .frame(width: 8, height: 8)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(NookRecordClock.text(NookRecordClock.elapsed(record.phase, now: context.date)))
                    .font(.system(size: NookRecordCardLayout.clockFontSize(for: size), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
        }
    }

    private func buttons(isPaused: Bool, lang: LanguageManager, fillsWidth: Bool) -> some View {
        HStack(spacing: 6) {
            NookRecordRoundButton(
                size: size,
                symbol: isPaused ? "play.fill" : "pause.fill",
                label: lang.t(isPaused ? "nook.record.button.resume" : "nook.record.button.pause"),
                tint: Color.white.opacity(0.16),
                fillsWidth: fillsWidth
            ) {
                if isPaused { record.resume() } else { record.pause() }
            }
            NookRecordRoundButton(
                size: size,
                symbol: "stop.fill",
                label: lang.t("nook.record.button.stop"),
                tint: Color.red.opacity(0.85),
                fillsWidth: fillsWidth
            ) {
                Task { await record.stop() }
            }
        }
    }
}

private struct NookRecordRoundButton: View {
    let size: NookWidgetSize
    let symbol: String
    let label: String
    let tint: Color
    var fillsWidth = false
    let action: () -> Void

    var body: some View {
        let buttonSize = NookRecordCardLayout.roundButtonSize(for: size)
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size == .large ? 13 : 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: fillsWidth ? nil : buttonSize.width, height: buttonSize.height)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .background(Capsule().fill(tint))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct NookRecordTextButton: View {
    let titleKey: String
    let action: () -> Void

    var body: some View {
        let title = LanguageManager.shared.t(titleKey)
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 12)
                .frame(height: NookRecordCardLayout.controlHeight)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(title)
    }
}

// MARK: - Sample

extension NookRecordCard {
    /// A still picture of the card for the Settings preview, which never
    /// reads the user's own choices.
    static func sample(size: NookWidgetSize) -> some View {
        NookRecordSampleContent(size: size)
    }
}

private struct NookRecordSampleContent: View {
    let size: NookWidgetSize

    var body: some View {
        NookRecordSetupView(
            size: size,
            options: .constant(NookRecordOptions()),
            status: nil,
            onRecord: {}
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
