import Foundation
import SwiftUI

/// Shows a short notice in the closed notch when the volume changes or
/// mutes, whoever changed it: the keys, the menu bar, another app. It
/// listens to CoreAudio, which needs no permission. No card.
///
/// It also owns `keys`, the optional takeover of the volume and brightness
/// keys that keeps Apple's own popup away.
@MainActor
final class NookVolumeMonitor {
    static let noticeKey = "nook.volume.notice"
    /// Shorter than other notices: a key held down sends many in a row and
    /// the last one should not linger.
    static let noticeSeconds: TimeInterval = 1.6
    /// A new output often settles its volume right after it takes over
    /// (headphones syncing theirs). Changes this soon after the switch are
    /// taken as the new baseline and not announced, which also keeps them
    /// from covering the headphones notice.
    static let settleSeconds: TimeInterval = 2

    let keys: NookMediaKeys

    private(set) weak var nook: NookModel?
    private let hardware: any NookAudioHardware
    private let defaults: UserDefaults
    private let now: () -> Date
    private var started = false
    private var last: NookVolumeReading?
    private var lastShown: Date?
    private var outputChangedAt: Date?

    private var lang: LanguageManager { .shared }

    init(
        hardware: any NookAudioHardware = CoreAudioHardware.shared,
        keys: NookMediaKeys? = nil,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.hardware = hardware
        self.defaults = defaults
        self.now = now
        self.keys = keys ?? NookMediaKeys(
            hardware: hardware,
            brightness: NookDisplayBrightness.shared,
            trust: NookSystemAccessibilityTrust(),
            filter: NookEventTapKeyFilter(),
            defaults: defaults
        )
    }

    var isNoticeEnabled: Bool {
        defaults.object(forKey: Self.noticeKey) as? Bool ?? true
    }

    func start(nook: NookModel) {
        self.nook = nook
        guard !started else { return }
        started = true
        hardware.addListener { [weak self] change in
            self?.hardwareChanged(change)
        }
        hardware.start()
        // Baseline first, which keeps launch from announcing the volume.
        last = read()
        keys.onBrightness = { [weak self] value in
            self?.showBrightness(value)
        }
        keys.onVolumeKey = { [weak self] in
            self?.showAfterKey()
        }
        keys.start()
    }

    private func read() -> NookVolumeReading? {
        guard let device = hardware.defaultOutputID() else { return nil }
        return NookVolumeReading(
            deviceID: device,
            volume: hardware.volume(of: device),
            isMuted: hardware.isMuted(device) ?? false
        )
    }

    private func hardwareChanged(_ change: NookAudioChange) {
        switch change {
        case .devices:
            return
        case .defaultOutput:
            // Another output has its own volume. That is not a change to announce.
            last = read()
            outputChangedAt = now()
        case .level:
            guard let reading = read() else { return }
            let content = NookVolumeNotice.content(from: last, to: reading)
            last = reading
            // A key the app kept is making this change and announces it
            // itself, in `showAfterKey`.
            if keys.isApplyingKey { return }
            if let outputChangedAt, now().timeIntervalSince(outputChangedAt) < Self.settleSeconds { return }
            // With the keys taken over, Apple's popup is gone and this
            // notice is the only sign of the change.
            guard let content, isNoticeEnabled || keys.status == .active else { return }
            show(symbol: content.symbol, text: text(for: content))
        }
    }

    private func text(for content: NookVolumeNoticeContent) -> String {
        if content.isMuted { return lang.t("nook.volume.muted") }
        return content.percent.map { "\($0)%" } ?? lang.t("nook.volume.unmuted")
    }

    /// A volume or mute key the app kept from macOS. Apple's popup is gone
    /// and this notice is the only sign of the press, which is why it shows
    /// even when the level did not move (the top or the bottom of the
    /// range) and even right after an output switch.
    private func showAfterKey() {
        guard let reading = read() else { return }
        last = reading
        let content = NookVolumeNotice.content(for: reading)
        show(symbol: content.symbol, text: text(for: content))
    }

    private func showBrightness(_ value: Float) {
        let percent = NookVolumeNotice.percent(value)
        show(symbol: percent < 34 ? "sun.min.fill" : "sun.max.fill", text: "\(percent)%")
    }

    /// A key held down sends a stream of changes. Only the first pops the
    /// island; the rest change the text in place.
    private func show(symbol: String, text: String) {
        let moment = now()
        let isFollowUp = lastShown.map { moment.timeIntervalSince($0) < Self.noticeSeconds } ?? false
        lastShown = moment
        nook?.showTransient(
            symbol: symbol,
            text: text,
            duration: .seconds(Self.noticeSeconds),
            pops: !isFollowUp
        )
    }

    /// The notice the Settings test button shows.
    func showSample() {
        show(symbol: NookVolumeNotice.symbol(percent: 62, isMuted: false), text: "62%")
    }
}
