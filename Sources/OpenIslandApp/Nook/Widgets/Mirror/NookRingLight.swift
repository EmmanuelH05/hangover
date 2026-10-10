import AppKit
import SwiftUI

/// Shape and size rules for the ring light. A plain enum and not part of a
/// view, which keeps them callable from tests without the main actor.
enum NookRingLightLayout {
    /// Share of the screen's shorter side the band takes.
    static let thicknessRatio: CGFloat = 0.1
    static let minThickness: CGFloat = 64
    static let maxThickness: CGFloat = 140

    /// Warm white, close to a bulb. Pure white reads blue on a face. The
    /// light's color unless the user picks another tint.
    static let color = NookRingLightTint.warmWhite.color

    /// How thick the band of light is on a screen of this size.
    static func thickness(for screenSize: CGSize) -> CGFloat {
        let shorterSide = min(screenSize.width, screenSize.height)
        return min(max(shorterSide * thicknessRatio, minThickness), maxThickness)
    }

    /// The inner edge is rounded, which makes the light read as a ring and
    /// not as a picture frame.
    static func innerCornerRadius(thickness: CGFloat) -> CGFloat {
        thickness * 0.5
    }

    /// The band along the edges of `rect`: the whole rect with a rounded
    /// hole in the middle. Fill it with the even-odd rule.
    static func path(in rect: CGRect, thickness: CGFloat) -> Path {
        var path = Path()
        path.addRect(rect)
        let hole = rect.insetBy(dx: thickness, dy: thickness)
        guard hole.width > 0, hole.height > 0 else { return path }
        let radius = innerCornerRadius(thickness: thickness)
        path.addRoundedRect(in: hole, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        return path
    }
}

/// The color of the ring light (D31). Every tint is close to white: the
/// light is there to show a face, and a strong color would paint it.
enum NookRingLightTint: String, CaseIterable, Identifiable, Sendable {
    /// The light it always had.
    case warmWhite
    case daylight
    case candle
    case peach
    case rose
    case lavender
    case mint
    case sky

    /// Where the choice is saved. One choice for every display.
    static let storageKey = "nook.mirror.ringLightTint"

    var id: String { rawValue }

    /// The key of the name Settings shows.
    var titleKey: String { "nook.mirror.ringLight.tint.\(rawValue)" }

    /// Red, green and blue in 0...1.
    var components: (red: Double, green: Double, blue: Double) {
        switch self {
        case .warmWhite: (1.0, 0.965, 0.9)
        case .daylight: (0.93, 0.96, 1.0)
        case .candle: (1.0, 0.86, 0.68)
        case .peach: (1.0, 0.84, 0.76)
        case .rose: (1.0, 0.8, 0.86)
        case .lavender: (0.88, 0.84, 1.0)
        case .mint: (0.82, 1.0, 0.9)
        case .sky: (0.8, 0.92, 1.0)
        }
    }

    var color: Color {
        let parts = components
        return Color(red: parts.red, green: parts.green, blue: parts.blue)
    }

    /// The saved tint, or warm white when nothing or something unknown is
    /// saved.
    static func resolve(_ raw: String?) -> NookRingLightTint {
        raw.flatMap(NookRingLightTint.init(rawValue:)) ?? .warmWhite
    }
}

/// The band of light drawn across the whole screen.
struct NookRingLightView: View {
    let thickness: CGFloat
    var tint: NookRingLightTint = .warmWhite

    var body: some View {
        GeometryReader { geometry in
            NookRingLightLayout.path(in: CGRect(origin: .zero, size: geometry.size), thickness: thickness)
                .fill(tint.color, style: FillStyle(eoFill: true))
                // A soft inner edge, which lets the light fall off into the
                // screen the way a real ring light does.
                .shadow(color: tint.color.opacity(0.55), radius: thickness * 0.25)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The light as the window shows it: in the saved tint, and following the
/// setting while it is lit.
private struct NookRingLightLiveView: View {
    let thickness: CGFloat

    @AppStorage(NookRingLightTint.storageKey) private var tintRaw = NookRingLightTint.warmWhite.rawValue

    var body: some View {
        NookRingLightView(thickness: thickness, tint: .resolve(tintRaw))
    }
}

/// The ring light's color as a row of swatches, for the Mirror settings.
struct NookRingLightTintRow: View {
    @AppStorage(NookRingLightTint.storageKey) private var tintRaw = NookRingLightTint.warmWhite.rawValue

    private static let swatch: CGFloat = 18

    private var lang: LanguageManager { .shared }

    var body: some View {
        let selected = NookRingLightTint.resolve(tintRaw)
        LabeledContent(lang.t("nook.mirror.ringLight.tint")) {
            HStack(spacing: 8) {
                ForEach(NookRingLightTint.allCases) { tint in
                    Button {
                        tintRaw = tint.rawValue
                    } label: {
                        Circle()
                            .fill(tint.color)
                            .frame(width: Self.swatch, height: Self.swatch)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                            .padding(3)
                            .overlay(
                                Circle().strokeBorder(Color.accentColor.opacity(tint == selected ? 1 : 0), lineWidth: 2)
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(lang.t(tint.titleKey))
                    .accessibilityLabel(lang.t(tint.titleKey))
                    .accessibilityAddTraits(tint == selected ? .isSelected : [])
                }
            }
        }
    }
}

/// The ring light for the mirror: a bright band around the edge of the
/// screen that lights the face in front of it. It is a window of its own
/// that takes no clicks, sits just under the island, and asks to be left
/// out of screen recordings and screen shares.
@MainActor
final class NookRingLight {
    static let shared = NookRingLight()

    private var panel: NSPanel?
    private var isLit = false
    /// Counts show and hide calls. A fade that finishes after a newer call
    /// must not order the window out from under it.
    private var generation = 0

    /// Called when displays are added, removed or resized while the light
    /// is on. The app model answers by presenting the light again, which
    /// fits it to the island's screen as it is now.
    var onScreensChanged: (() -> Void)?

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isLit else { return }
                self.onScreensChanged?()
            }
        }
    }

    /// Lights the screen the island is on, or puts the light out.
    func setLit(_ lit: Bool, on screen: NSScreen?) {
        guard let screen, lit else {
            hide()
            return
        }
        show(on: screen)
    }

    private func show(on screen: NSScreen) {
        generation += 1
        isLit = true
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.setFrame(screen.frame, display: true)
        panel.contentView = NSHostingView(
            rootView: NookRingLightLiveView(thickness: NookRingLightLayout.thickness(for: screen.frame.size))
        )
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        fade(panel, to: 1, completion: nil)
    }

    private func hide() {
        guard isLit, let panel else { return }
        generation += 1
        isLit = false
        let token = generation
        fade(panel, to: 0) { [weak self] in
            guard let self, self.generation == token else { return }
            panel.orderOut(nil)
        }
    }

    private func fade(_ panel: NSPanel, to alpha: CGFloat, completion: (@MainActor () -> Void)?) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard !reduceMotion else {
            panel.alphaValue = alpha
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Motion.ringLightFade
            panel.animator().alphaValue = alpha
        }, completionHandler: {
            Task { @MainActor in completion?() }
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        // One step under the island, which keeps the island and the mirror
        // in front of the light.
        panel.level = DemoMode.raised(NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // A light for the room, not for the people watching a shared screen.
        // This asks capture to leave the window out. Newer capture paths
        // may not honor it.
        panel.sharingType = .none
        return panel
    }
}
