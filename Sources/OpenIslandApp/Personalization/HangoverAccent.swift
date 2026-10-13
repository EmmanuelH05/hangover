import AppKit
import SwiftUI

/// The accent color the user picked (D62). One choice for the whole app, not
/// one per display: it colors what is a highlight or a selected state, in
/// the island, in Settings and in the welcome tour.
enum HangoverAccentChoice: String, CaseIterable, Identifiable, Sendable {
    /// The look Hangover came with, named Classic in Settings: paper in
    /// Settings and the tour, orange in the Nook. Each highlight keeps the
    /// color it always had.
    case standard = "classic"
    /// The accent color picked in macOS System Settings, followed live.
    case system
    case blue
    case purple
    case pink
    case red
    case orange
    case yellow
    case green
    case graphite

    var id: String { rawValue }

    var titleKey: String { "settings.appearance.accent.choice.\(rawValue)" }

    /// Apple's color of that name as it draws on a dark surface, read from
    /// `NSColor.system*` under the dark appearance on macOS 26. Nil for the
    /// two choices that are not one fixed color.
    var fixedColor: IslandHaloRGB? {
        switch self {
        case .standard, .system: nil
        case .blue: IslandHaloRGB(rgb: 0x0091FF)
        case .purple: IslandHaloRGB(rgb: 0xDB34F2)
        case .pink: IslandHaloRGB(rgb: 0xFF375F)
        case .red: IslandHaloRGB(rgb: 0xFF4245)
        case .orange: IslandHaloRGB(rgb: 0xFF9230)
        case .yellow: IslandHaloRGB(rgb: 0xFFD600)
        case .green: IslandHaloRGB(rgb: 0x30D158)
        case .graphite: IslandHaloRGB(rgb: 0x98989D)
        }
    }

    /// The choices that are one fixed color, in the order Settings lists them.
    static let fixed: [HangoverAccentChoice] = allCases.filter { $0.fixedColor != nil }

    /// What an install starts with, and what an update gives a user who
    /// never picked. The owner's choice: purple for everyone, in place of
    /// the orange the Nook came with.
    static let start: HangoverAccentChoice = .purple
}

/// The one place that says what the accent is: how a choice becomes a
/// color, where the choice is kept, and what an accent has to be readable on.
enum HangoverAccent {
    static let defaultsKey = "app.accentColor"

    /// The start color unless something else was picked. A value this build
    /// does not know, such as one a newer build wrote, reads as the start
    /// color too.
    static func load(from defaults: UserDefaults) -> HangoverAccentChoice {
        defaults.string(forKey: defaultsKey).flatMap(HangoverAccentChoice.init(rawValue:)) ?? .start
    }

    static func save(_ choice: HangoverAccentChoice, to defaults: UserDefaults) {
        defaults.set(choice.rawValue, forKey: defaultsKey)
    }

    /// The color a choice gives. Nil is today's look, where each highlight
    /// keeps the color it always had. System with no reading of the system's
    /// color yet is today's look too.
    static func resolve(choice: HangoverAccentChoice, system: IslandHaloRGB?) -> IslandHaloRGB? {
        switch choice {
        case .standard: nil
        case .system: system
        default: choice.fixedColor
        }
    }

    /// The tint the Settings window hands to SwiftUI, and the only window
    /// tint there is: a fixed color, and nil for Default and for System.
    ///
    /// A window tint reaches far more than highlights. It colors switches,
    /// checkboxes, sliders, segmented pickers, progress bars and prominent
    /// buttons, and it draws the label of a default style button in the
    /// tint. It does not reach menus, menu pickers, steppers or links. The
    /// island and the tour have plain buttons that must never take the
    /// accent (the photo booth's, the camera notice's), which is why they
    /// set no window tint and tint only their text fields, for the caret.
    /// Under System, macOS already draws its own accent on every standard
    /// control, and a tint on top would only repaint button labels.
    static func settingsRootTint(choice: HangoverAccentChoice) -> IslandHaloRGB? {
        choice.fixedColor
    }

    // MARK: Readability

    /// The island's own surface, which every highlight sits on.
    static let ink = IslandHaloRGB(rgb: 0x0D0D0F)

    /// The least contrast a fixed accent has against ink. An accent is a
    /// ring or a glyph on ink, and it is a fill under ink text: one number
    /// covers both, because contrast reads the same in both directions.
    static let contrastFloor = 4.5

    /// The least contrast a picked thing has against the same spot on its
    /// unpicked neighbor, which is what tells the two apart.
    static let pickedFloor = 3.0

    /// The WCAG contrast ratio of two colors, from 1 to 21.
    static func contrast(_ first: IslandHaloRGB, _ second: IslandHaloRGB) -> Double {
        let lighter = max(luminance(first), luminance(second))
        let darker = min(luminance(first), luminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Whether text on a fill of this color reads better dark or light.
    /// Every fixed accent takes ink. The system's accent can be anything,
    /// and a dark one takes white.
    static func textTone(on fill: IslandHaloRGB) -> TextTone {
        contrast(fill, ink) >= contrast(fill, white) ? .ink : .white
    }

    enum TextTone: Equatable, Sendable {
        case ink
        case white

        var rgb: IslandHaloRGB { self == .ink ? HangoverAccent.ink : HangoverAccent.white }
    }

    static let white = IslandHaloRGB(rgb: 0xFFFFFF)

    static func luminance(_ color: IslandHaloRGB) -> Double {
        func linear(_ component: Double) -> Double {
            component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }
}

/// What a view asks for the accent. It travels in the environment from the
/// island's root, the Settings window and the welcome tour, and a view
/// outside all three draws today's look.
struct HangoverAccentTint: Equatable, Sendable {
    /// Nil is today's look.
    let rgb: IslandHaloRGB?

    static let standard = HangoverAccentTint(rgb: nil)

    /// The accent, or the color this highlight has always had. An opacity
    /// that belongs to today's look goes inside the argument, which draws
    /// the accent itself at full strength.
    func highlight(_ standard: Color) -> Color {
        rgb?.color ?? standard
    }

    /// The color of text that sits on a fill drawn with `highlight`: the
    /// one of ink and white that reads better on the accent, or the color
    /// this text has always had.
    func textOnHighlight(_ standard: Color) -> Color {
        guard let rgb else { return standard }
        return HangoverAccent.textTone(on: rgb).rgb.color
    }

    /// With an accent set, a picked thing is a fill and not a text color:
    /// a gray accent on a number would read as dimmed beside white ones.
    /// Nil on Default, where the mark stays the text color it always was.
    var pickedFill: Color? { rgb?.color }

    /// The text of a picked thing: the color it always had on Default, and
    /// with an accent the tone that reads on `pickedFill`.
    func pickedText(_ standard: Color) -> Color {
        textOnHighlight(standard)
    }

    /// The tint a text field takes, for its caret. Nil leaves it as macOS
    /// draws it.
    var controlTint: Color? { rgb?.color }
}

extension EnvironmentValues {
    @Entry var hangoverAccent: HangoverAccentTint = .standard
}

extension View {
    /// Draws in `color`, or leaves the view as it is for nil.
    @ViewBuilder
    func foregroundStyle(ifSet color: Color?) -> some View {
        if let color { foregroundStyle(color) } else { self }
    }
}

// MARK: - The system's accent

/// Reads the accent color picked in macOS System Settings. A protocol, which
/// lets a test hand in a color of its own and never read the real one.
@MainActor
protocol SystemAccentProviding {
    /// The color as it draws on a dark surface. Nil when it has no sRGB form.
    func currentAccent() -> IslandHaloRGB?
}

/// The real reading. With System Settings on Multicolor this is blue, which
/// is what macOS returns.
struct LiveSystemAccent: SystemAccentProviding {
    func currentAccent() -> IslandHaloRGB? {
        var reading: IslandHaloRGB?
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            guard let color = NSColor.controlAccentColor.usingColorSpace(.sRGB) else { return }
            reading = IslandHaloRGB(
                red: Double(color.redComponent),
                green: Double(color.greenComponent),
                blue: Double(color.blueComponent)
            ).quantized
        }
        return reading
    }
}

/// Holds the system's accent and follows it. macOS says when the color
/// changed, which means no timer and no polling. Nothing is read before
/// `start()`, and a model built for a test never calls it.
@MainActor
@Observable
final class SystemAccentMonitor {
    private(set) var accent: IslandHaloRGB?

    @ObservationIgnored private let provider: any SystemAccentProviding
    @ObservationIgnored private let center: NotificationCenter
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    /// True between `start()` and `stop()`.
    var isFollowing: Bool { observer != nil }

    init(provider: any SystemAccentProviding, center: NotificationCenter = .default) {
        self.provider = provider
        self.center = center
    }

    /// Called once from AppModel at launch. Reads the color and then
    /// follows the system's own notice that colors changed. Calling it
    /// again while it follows does nothing.
    func start() {
        guard observer == nil else { return }
        refresh()
        // `queue: .main` delivers on the main thread, which lets the handler
        // assume main-actor isolation.
        observer = center.addObserver(
            forName: NSColor.systemColorsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Stops following. The last reading is kept.
    func stop() {
        guard let observer else { return }
        center.removeObserver(observer)
        self.observer = nil
    }

    private func refresh() {
        let reading = provider.currentAccent()
        // Only a real change is written, which keeps a repeated notice from
        // waking every view that draws the accent.
        if accent != reading { accent = reading }
    }
}

/// The accent color as the app holds it: the choice, where it is kept, and
/// the system's color for the System choice. `AppModel` owns one. A test
/// builds its own with a store in memory, a made up system color and a
/// notification center nothing else posts to.
@MainActor
@Observable
final class HangoverAccentModel {
    /// Default until something else is picked. A change is saved at once.
    var choice: HangoverAccentChoice {
        didSet {
            guard choice != oldValue else { return }
            HangoverAccent.save(choice, to: defaults)
        }
    }

    /// What macOS is set to. It reads nothing until the app starts it.
    @ObservationIgnored let system: SystemAccentMonitor
    @ObservationIgnored private let defaults: UserDefaults

    init(
        defaults: UserDefaults,
        provider: (any SystemAccentProviding)? = nil,
        center: NotificationCenter = .default
    ) {
        self.defaults = defaults
        choice = HangoverAccent.load(from: defaults)
        system = SystemAccentMonitor(provider: provider ?? LiveSystemAccent(), center: center)
    }

    /// What the island, Settings and the tour put in their environment.
    var tint: HangoverAccentTint {
        HangoverAccentTint(rgb: HangoverAccent.resolve(choice: choice, system: system.accent))
    }
}
