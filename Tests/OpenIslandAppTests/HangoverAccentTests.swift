import AppKit
import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

/// A system accent a test sets by hand. The real one is never read here.
@MainActor
final class FakeSystemAccent: SystemAccentProviding {
    var color: IslandHaloRGB?
    private(set) var reads = 0

    init(_ color: IslandHaloRGB?) {
        self.color = color
    }

    func currentAccent() -> IslandHaloRGB? {
        reads += 1
        return color
    }
}

/// Waits a few turns of the main actor for a notice to land.
@MainActor
private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// The accent color (D62): what each choice resolves to, where it is kept,
/// how System follows macOS, and what every fixed color has to clear.
/// Fakes only: no window, no real system color, no real settings.
@MainActor
@Suite struct HangoverAccentTests {
    private static let teal = IslandHaloRGB(rgb: 0x12B5A6)
    private static let plum = IslandHaloRGB(rgb: 0x9B4DCA)

    /// An accent model on a store in memory, a made up system color and a
    /// notification center nothing else posts to.
    private static func accentModel(
        defaults: UserDefaults = MemoryDefaults(),
        system: IslandHaloRGB? = nil
    ) -> (HangoverAccentModel, FakeSystemAccent, NotificationCenter) {
        let fake = FakeSystemAccent(system)
        let center = NotificationCenter()
        return (HangoverAccentModel(defaults: defaults, provider: fake, center: center), fake, center)
    }

    // MARK: - The choices

    @Test func theChoicesComeInTheOrderSettingsListsThem() {
        #expect(HangoverAccentChoice.allCases == [
            .standard, .system, .blue, .purple, .pink, .red, .orange, .yellow, .green, .graphite,
        ])
        #expect(HangoverAccentChoice.fixed == [.blue, .purple, .pink, .red, .orange, .yellow, .green, .graphite])
    }

    @Test func theStoredNamesNeverChange() {
        // A rename would send everyone who picked that color back to Default.
        #expect(HangoverAccentChoice.allCases.map(\.rawValue) == [
            "classic", "system", "blue", "purple", "pink", "red", "orange", "yellow", "green", "graphite",
        ])
    }

    @Test(arguments: [
        (HangoverAccentChoice.blue, "0091FF"),
        (.purple, "DB34F2"),
        (.pink, "FF375F"),
        (.red, "FF4245"),
        (.orange, "FF9230"),
        (.yellow, "FFD600"),
        (.green, "30D158"),
        (.graphite, "98989D"),
    ])
    func aFixedChoiceResolvesToApplesColorOfThatName(choice: HangoverAccentChoice, hex: String) {
        // Whatever macOS is set to makes no difference to a fixed color.
        #expect(HangoverAccent.resolve(choice: choice, system: Self.teal)?.hex == hex)
        #expect(HangoverAccent.resolve(choice: choice, system: nil)?.hex == hex)
    }

    @Test func defaultResolvesToNoColorWhichIsTodaysLook() {
        #expect(HangoverAccent.resolve(choice: .standard, system: nil) == nil)
        #expect(HangoverAccent.resolve(choice: .standard, system: Self.teal) == nil)
        #expect(HangoverAccentChoice.standard.fixedColor == nil)
        #expect(HangoverAccentChoice.system.fixedColor == nil)
    }

    @Test func systemResolvesToWhatMacOSIsSetTo() {
        #expect(HangoverAccent.resolve(choice: .system, system: Self.teal) == Self.teal)
        #expect(HangoverAccent.resolve(choice: .system, system: Self.plum) == Self.plum)
        // No reading yet: today's look, never a color made up here.
        #expect(HangoverAccent.resolve(choice: .system, system: nil) == nil)
    }

    // MARK: - Readability

    @Test func contrastIsTheWCAGRatio() {
        let white = IslandHaloRGB(rgb: 0xFFFFFF)
        let black = IslandHaloRGB(rgb: 0x000000)
        #expect(abs(HangoverAccent.contrast(white, black) - 21) < 0.001)
        #expect(abs(HangoverAccent.contrast(black, white) - 21) < 0.001)
        #expect(abs(HangoverAccent.contrast(white, white) - 1) < 0.001)
    }

    @Test(arguments: HangoverAccentChoice.fixed)
    func everyFixedColorClearsTheFloorAgainstInk(choice: HangoverAccentChoice) throws {
        // The same number answers both uses: the accent as a ring or a
        // glyph on ink, and the accent as a fill under ink text.
        let color = try #require(choice.fixedColor)
        let contrast = HangoverAccent.contrast(color, HangoverAccent.ink)
        #expect(HangoverAccent.contrastFloor == 4.5)
        #expect(contrast >= HangoverAccent.contrastFloor, "\(choice.rawValue) reads \(contrast) against ink")
    }

    @Test(arguments: HangoverAccentChoice.fixed)
    func textOnEveryFixedColorIsInk(choice: HangoverAccentChoice) throws {
        let color = try #require(choice.fixedColor)
        #expect(HangoverAccent.textTone(on: color) == .ink)
        let onFill = HangoverAccentTint(rgb: color).textOnHighlight(.white)
        #expect(IslandHaloRGB(onFill)?.hex == HangoverAccent.ink.hex)
    }

    @Test func textOnADarkSystemColorIsWhite() {
        // macOS can be set to a color no fixed choice is as dark as.
        let navy = IslandHaloRGB(rgb: 0x1B2A6B)
        #expect(HangoverAccent.textTone(on: navy) == .white)
        #expect(IslandHaloRGB(HangoverAccentTint(rgb: navy).textOnHighlight(.black))?.hex == "FFFFFF")
    }

    @Test func textOnAnyFillClearsFourToOneInTheBetterTone() {
        // Ink or white, whichever reads better: the worst gray there is
        // still clears 4.4 to 1.
        let white = IslandHaloRGB(rgb: 0xFFFFFF)
        for step in 0...255 {
            let gray = IslandHaloRGB.rgb255(step, step, step)
            let best = max(HangoverAccent.contrast(gray, HangoverAccent.ink), HangoverAccent.contrast(gray, white))
            #expect(best >= 4.4, "gray \(step) reads \(best)")
            #expect(HangoverAccent.contrast(gray, HangoverAccent.textTone(on: gray).rgb) == best)
        }
    }

    @Test func aHighlightsOwnOpacityGoesAwayWithAnAccent() {
        // An opacity that belongs to today's look is handed in with the
        // color. Default keeps it, and an accent draws at full strength.
        let own = Color(.sRGB, red: 0, green: 0, blue: 0).opacity(0.88)
        #expect(HangoverAccentTint.standard.textOnHighlight(own) == own)
        #expect(HangoverAccentTint.standard.highlight(own) == own)
        let tint = HangoverAccentTint(rgb: Self.teal)
        #expect(tint.textOnHighlight(own) == HangoverAccent.ink.color)
        #expect(tint.highlight(own) == Self.teal.color)
    }

    @Test func aPlainCountdownTakesTheColorItIsGivenAndARoundKeepsItsOwn() {
        let plain = Color(.sRGB, red: 0.07, green: 0.71, blue: 0.65)
        #expect(NookPomodoroLook.tint(for: nil, plain: plain) == plain)
        for phase in [NookPomodoroPhase.work, .shortBreak, .longBreak] {
            let round = NookPomodoroState(phase: phase, round: 1)
            #expect(NookPomodoroLook.tint(for: round, plain: plain) == NookPomodoroLook.tint(for: round))
            #expect(NookPomodoroLook.tint(for: round, plain: plain) != plain)
        }
    }

    @Test func inkIsTheIslandsSurface() {
        #expect(HangoverAccent.ink.hex == "0D0D0F")
        #expect(IslandHaloRGB(V6Palette.ink)?.hex == "0D0D0F")
        #expect(IslandHaloRGB(V6Palette.paper)?.hex == IslandPaint.paper.hex)
    }

    // MARK: - A picked thing is a fill

    @Test func onDefaultAPickedThingKeepsItsTextColorAndGetsNoFill() {
        let own = Color(.sRGB, red: 1, green: 0.5, blue: 0)
        #expect(HangoverAccentTint.standard.pickedFill == nil)
        #expect(HangoverAccentTint.standard.pickedText(own) == own)
    }

    @Test(arguments: HangoverAccentChoice.fixed)
    func todayInTheCalendarStandsThreeToOneFromAnOrdinaryDay(choice: HangoverAccentChoice) throws {
        // Today is its number on a circle of the accent. An ordinary day
        // has no circle: the same spot is the card, or the white wash of a
        // picked day, which is the lightest thing a mark sits on.
        let accent = try #require(choice.fixedColor)
        let tint = HangoverAccentTint(rgb: accent)
        #expect(tint.pickedFill == accent.color)
        #expect(HangoverAccent.pickedFloor == 3)
        for surface in [HangoverAccent.ink, HangoverAccent.lightestSurface] {
            let contrast = HangoverAccent.contrast(accent, surface)
            #expect(contrast >= HangoverAccent.pickedFloor, "\(choice.rawValue) reads \(contrast) on \(surface.hex)")
        }
        // The number on the circle.
        let number = HangoverAccent.textTone(on: accent).rgb
        #expect(tint.pickedText(.orange) == number.color)
        #expect(HangoverAccent.contrast(number, accent) >= HangoverAccent.contrastFloor)
    }

    @Test(arguments: HangoverAccentChoice.fixed)
    func theCurrentSizeChipStandsThreeToOneFromTheOthers(choice: HangoverAccentChoice) throws {
        // The three sizes sit in a capsule of black at 0.4 over the widget.
        // The current one is filled with the accent and the others are not.
        let accent = try #require(choice.fixedColor)
        for widget in [HangoverAccent.ink, HangoverAccent.lightestSurface] {
            let others = IslandPaint(rgb: IslandPaint.black, opacity: 0.4).over(widget)
            let contrast = HangoverAccent.contrast(accent, others)
            #expect(contrast >= HangoverAccent.pickedFloor, "\(choice.rawValue) reads \(contrast)")
        }
    }

    @Test(arguments: HangoverAccentChoice.fixed)
    func aPickedAnswerStandsThreeToOneFromTheOthersAndBeatsTheHoveredOne(choice: HangoverAccentChoice) throws {
        let accent = try #require(choice.fixedColor)
        let tint = HangoverAccentTint(rgb: accent)
        let ink = HangoverAccent.ink
        typealias Look = IslandQuestionOptionLook

        let pickedFill = Look.fill(isSelected: true, isHovered: false, accent: tint).over(ink)
        let hoveredFill = Look.fill(isSelected: false, isHovered: true, accent: tint).over(ink)
        let restFill = Look.fill(isSelected: false, isHovered: false, accent: tint).over(ink)
        // The picked row is brighter than the one under the pointer, which
        // paper at 0.10 was not for a gray accent.
        #expect(HangoverAccent.luminance(pickedFill) > HangoverAccent.luminance(hoveredFill) * 1.5)

        // Its ring is what says picked: 3 to 1 against the same spot on a
        // row at rest and on the hovered row, at the alpha really drawn.
        let pickedRing = Look.stroke(isSelected: true, isHovered: false, accent: tint).over(pickedFill)
        for other in [restFill, hoveredFill] {
            let contrast = HangoverAccent.contrast(pickedRing, other)
            #expect(contrast >= HangoverAccent.pickedFloor, "\(choice.rawValue) ring reads \(contrast)")
        }
        let hoveredRing = Look.stroke(isSelected: false, isHovered: true, accent: tint).over(hoveredFill)
        #expect(HangoverAccent.luminance(pickedRing) > HangoverAccent.luminance(hoveredRing))

        // The numbered badge: the accent itself against the badge of a row
        // at rest, and the number on it at 4.5 to 1.
        let pickedBadge = Look.badgeFill(isSelected: true, accent: tint).over(pickedFill)
        let restBadge = Look.badgeFill(isSelected: false, accent: tint).over(restFill)
        #expect(HangoverAccent.contrast(pickedBadge, restBadge) >= HangoverAccent.pickedFloor)
        let number = Look.badgeText(isSelected: true, accent: tint).over(pickedBadge)
        let badgeContrast = HangoverAccent.contrast(number, pickedBadge)
        #expect(badgeContrast >= HangoverAccent.contrastFloor, "\(choice.rawValue) badge reads \(badgeContrast)")
    }

    @Test func onDefaultAnAnswerIsDrawnWithTheNumbersItAlwaysHad() {
        typealias Look = IslandQuestionOptionLook
        let tint = HangoverAccentTint.standard
        let paper = IslandPaint.paper
        let white = HangoverAccent.white
        #expect(Look.fill(isSelected: true, isHovered: false, accent: tint) == IslandPaint(rgb: paper, opacity: 0.10))
        #expect(Look.fill(isSelected: true, isHovered: true, accent: tint) == IslandPaint(rgb: paper, opacity: 0.10))
        #expect(Look.fill(isSelected: false, isHovered: true, accent: tint) == IslandPaint(rgb: white, opacity: 0.065))
        #expect(Look.fill(isSelected: false, isHovered: false, accent: tint) == IslandPaint(rgb: white, opacity: 0.028))
        #expect(Look.stroke(isSelected: true, isHovered: false, accent: tint) == IslandPaint(rgb: paper, opacity: 0.36))
        #expect(Look.stroke(isSelected: false, isHovered: true, accent: tint) == IslandPaint(rgb: white, opacity: 0.13))
        #expect(Look.stroke(isSelected: false, isHovered: false, accent: tint) == IslandPaint(rgb: white, opacity: 0.045))
        #expect(Look.badgeFill(isSelected: true, accent: tint) == IslandPaint(rgb: paper, opacity: 0.88))
        #expect(Look.badgeFill(isSelected: false, accent: tint) == IslandPaint(rgb: white, opacity: 0.045))
        #expect(Look.badgeText(isSelected: true, accent: tint) == IslandPaint(rgb: IslandPaint.black, opacity: 0.82))
        #expect(Look.badgeText(isSelected: false, accent: tint) == IslandPaint(rgb: paper, opacity: 0.42))
        // Rows that are not picked never take the accent.
        let teal = HangoverAccentTint(rgb: Self.teal)
        #expect(Look.fill(isSelected: false, isHovered: true, accent: teal) == Look.fill(isSelected: false, isHovered: true, accent: tint))
        #expect(Look.stroke(isSelected: false, isHovered: false, accent: teal) == Look.stroke(isSelected: false, isHovered: false, accent: tint))
        #expect(Look.badgeText(isSelected: false, accent: teal) == Look.badgeText(isSelected: false, accent: tint))
    }

    @Test func aPaintOverASurfaceIsMixedByItsOpacity() {
        let white = IslandPaint(rgb: HangoverAccent.white, opacity: 0.5).over(IslandPaint.black)
        #expect(white.hex == "808080")
        #expect(IslandPaint(rgb: Self.teal).over(HangoverAccent.ink) == Self.teal)
        #expect(IslandPaint(rgb: Self.teal, opacity: 0).over(HangoverAccent.ink) == HangoverAccent.ink)
    }

    // MARK: - Which window is tinted

    @Test func onlySettingsTintsItsWindowAndOnlyForAFixedColor() throws {
        // Default and System leave every standard control as macOS draws it.
        #expect(HangoverAccent.settingsRootTint(choice: .standard) == nil)
        #expect(HangoverAccent.settingsRootTint(choice: .system) == nil)
        for choice in HangoverAccentChoice.fixed {
            #expect(HangoverAccent.settingsRootTint(choice: choice) == choice.fixedColor)
        }
    }

    @Test func theModelHandsSettingsNoTintForClassicAndForSystem() {
        let (accent, _, _) = Self.accentModel(system: Self.teal)
        let model = AppModel(defaults: MemoryDefaults(), accent: accent)
        accent.system.start()
        defer { accent.system.stop() }

        // A new model starts on purple, which does tint the window.
        #expect(model.settingsRootTint != nil)
        accent.choice = .standard
        #expect(model.settingsRootTint == nil)
        #expect(model.settingsProminentLabel == nil)

        accent.choice = .system
        // The app's own highlights take the system's color. The window does not.
        #expect(model.accentTint.rgb == Self.teal)
        #expect(model.settingsRootTint == nil)
        #expect(model.settingsProminentLabel == nil)

        accent.choice = .green
        #expect(model.settingsRootTint == IslandHaloRGB(rgb: 0x30D158).color)
        // White on Apple's green is about 2 to 1. The label takes ink.
        #expect(model.settingsProminentLabel == HangoverAccent.ink.color)
    }

    @Test(arguments: HangoverAccentChoice.fixed)
    func aProminentButtonsLabelReadsOnEveryFixedTint(choice: HangoverAccentChoice) throws {
        let tint = try #require(HangoverAccent.settingsRootTint(choice: choice))
        let label = HangoverAccent.textTone(on: tint).rgb
        #expect(HangoverAccent.contrast(label, tint) >= HangoverAccent.contrastFloor)
    }

    /// The island and the tour have plain buttons that must never take the
    /// accent, such as the photo booth's. A tint on either window would
    /// reach them. Only a text field is tinted there, for its caret.
    @Test func theIslandAndTheTourSetNoWindowTint() throws {
        let app = Self.repoRoot.appendingPathComponent("Sources/OpenIslandApp", isDirectory: true)
        for path in ["Views/IslandPanelView.swift", "Onboarding/OnboardingView.swift"] {
            let text = try String(contentsOf: app.appendingPathComponent(path), encoding: .utf8)
            #expect(text.contains(".environment(\\.hangoverAccent,"), "\(path) lost the accent")
            let tinted = text.split(separator: "\n").filter { line in
                line.contains(".tint(") && ["accent", "Accent", "RootTint"].contains(where: line.contains)
            }
            #expect(tinted.isEmpty, "\(path) tints its window: \(tinted)")
        }
        let settings = try String(contentsOf: app.appendingPathComponent("Views/SettingsView.swift"), encoding: .utf8)
        let tints = settings.split(separator: "\n").filter { $0.contains(".tint(") }
        #expect(tints.map { $0.trimmingCharacters(in: .whitespaces) } == [".tint(model.settingsRootTint)"])
    }

    @Test func aViewsOwnTintIsOnlyForATextFieldsCaret() throws {
        // Every `.tint(accent.controlTint)` sits right under a text field.
        let app = Self.repoRoot.appendingPathComponent("Sources/OpenIslandApp", isDirectory: true)
        var found = 0
        for file in Self.swiftFiles(under: app) {
            let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() where line.contains(".tint(accent.controlTint)") {
                found += 1
                let above = lines[max(0, index - 3)..<index].joined(separator: "\n")
                let isField = ["TextField(", "SecureField(", "TextEditor("].contains(where: above.contains)
                #expect(isField, "\(file.lastPathComponent):\(index + 1) tints something that is no text field")
            }
        }
        #expect(found == 7)
    }

    // MARK: - Where it is kept

    @Test func nothingSavedReadsAsTheStartColorWhichIsPurple() {
        #expect(HangoverAccent.load(from: MemoryDefaults()) == .start)
        #expect(HangoverAccentChoice.start == .purple)
    }

    @Test(arguments: HangoverAccentChoice.allCases)
    func aChoiceSurvivesASaveAndALoad(choice: HangoverAccentChoice) {
        let defaults = MemoryDefaults()
        HangoverAccent.save(choice, to: defaults)
        #expect(defaults.string(forKey: HangoverAccent.defaultsKey) == choice.rawValue)
        #expect(HangoverAccent.load(from: defaults) == choice)
    }

    @Test(arguments: ["teal", "", "Blue", "BLUE", "system "])
    func anUnknownSavedValueReadsAsTheStartColor(saved: String) {
        let defaults = MemoryDefaults()
        defaults.set(saved, forKey: HangoverAccent.defaultsKey)
        #expect(HangoverAccent.load(from: defaults) == .start)
    }

    @Test func aSavedValueOfTheWrongTypeReadsAsTheStartColor() {
        let defaults = MemoryDefaults()
        defaults.set(3, forKey: HangoverAccent.defaultsKey)
        #expect(HangoverAccent.load(from: defaults) == .start)
    }

    // MARK: - The model

    @Test func aNewModelStartsOnPurpleAndWritesNothing() {
        let defaults = MemoryDefaults()
        let (accent, fake, _) = Self.accentModel(defaults: defaults, system: Self.teal)
        let model = AppModel(defaults: defaults, accent: accent)
        #expect(model.accent.choice == .purple)
        #expect(model.accentTint.rgb?.hex == "DB34F2")
        #expect(defaults.object(forKey: HangoverAccent.defaultsKey) == nil)
        #expect(fake.reads == 0)
    }

    @Test func aModelBuiltWithoutAnAccentKeepsItsOwnInTheSameStore() {
        let defaults = MemoryDefaults()
        defaults.set("pink", forKey: HangoverAccent.defaultsKey)
        let model = AppModel(defaults: defaults)
        #expect(model.accent.choice == .pink)
        // Nothing read the system's color: the monitor was never started.
        #expect(!model.accent.system.isFollowing)
        #expect(model.accent.system.accent == nil)
    }

    @Test func theChoiceSurvivesARelaunch() {
        let defaults = MemoryDefaults()
        let (first, _, _) = Self.accentModel(defaults: defaults)
        first.choice = .pink
        #expect(defaults.string(forKey: HangoverAccent.defaultsKey) == "pink")
        #expect(first.tint.rgb?.hex == "FF375F")

        let (second, _, _) = Self.accentModel(defaults: defaults)
        #expect(second.choice == .pink)
        #expect(AppModel(defaults: defaults, accent: second).accentTint.rgb?.hex == "FF375F")
    }

    @Test func nothingReadsTheSystemsColorBeforeTheMonitorIsStarted() {
        let (accent, fake, _) = Self.accentModel(system: Self.teal)
        accent.choice = .system
        #expect(fake.reads == 0)
        #expect(!accent.system.isFollowing)
        // System with no reading is today's look.
        #expect(accent.tint == .standard)
    }

    @Test func theModelFollowsTheSystemsNoticeThatColorsChanged() async {
        let (accent, fake, center) = Self.accentModel(system: Self.teal)
        let model = AppModel(defaults: MemoryDefaults(), accent: accent)
        accent.choice = .system
        accent.system.start()
        defer { accent.system.stop() }
        #expect(model.accentTint.rgb == Self.teal)

        fake.color = Self.plum
        center.post(name: NSColor.systemColorsDidChangeNotification, object: nil)
        #expect(await eventually { model.accentTint.rgb == Self.plum })

        // A fixed color does not move with macOS.
        accent.choice = .red
        fake.color = Self.teal
        center.post(name: NSColor.systemColorsDidChangeNotification, object: nil)
        #expect(await eventually { accent.system.accent == Self.teal })
        #expect(model.accentTint.rgb?.hex == "FF4245")
    }

    // MARK: - Following macOS

    @Test func theMonitorReadsOnceWhenStartedAndOnceMoreAtMost() {
        let fake = FakeSystemAccent(Self.teal)
        let monitor = SystemAccentMonitor(provider: fake, center: NotificationCenter())
        #expect(monitor.accent == nil)
        #expect(fake.reads == 0)

        monitor.start()
        #expect(monitor.accent == Self.teal)
        #expect(monitor.isFollowing)
        #expect(fake.reads == 1)

        // A second start adds no second listener and reads nothing.
        monitor.start()
        #expect(fake.reads == 1)
    }

    @Test func theMonitorFollowsTheSystemsNoticeThatColorsChanged() async {
        let fake = FakeSystemAccent(Self.teal)
        let center = NotificationCenter()
        let monitor = SystemAccentMonitor(provider: fake, center: center)
        monitor.start()

        fake.color = Self.plum
        // Nothing polls: the color is still the old one until macOS says.
        #expect(monitor.accent == Self.teal)
        center.post(name: NSColor.systemColorsDidChangeNotification, object: nil)
        #expect(await eventually { monitor.accent == Self.plum })
        #expect(fake.reads == 2)

        // A notice heard once starts one read, not two.
        center.post(name: NSColor.systemColorsDidChangeNotification, object: nil)
        #expect(await eventually { fake.reads == 3 })
        #expect(monitor.accent == Self.plum)
    }

    @Test func aStoppedMonitorHearsNothingAndKeepsItsLastReading() async {
        let fake = FakeSystemAccent(Self.teal)
        let center = NotificationCenter()
        let monitor = SystemAccentMonitor(provider: fake, center: center)
        monitor.start()
        monitor.stop()
        #expect(!monitor.isFollowing)
        #expect(monitor.accent == Self.teal)

        fake.color = Self.plum
        center.post(name: NSColor.systemColorsDidChangeNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(monitor.accent == Self.teal)
        #expect(fake.reads == 1)

        // Stopping twice is fine, and a start after a stop follows again.
        monitor.stop()
        monitor.start()
        #expect(monitor.accent == Self.plum)
        center.post(name: NSColor.systemColorsDidChangeNotification, object: nil)
        #expect(await eventually { fake.reads == 3 })
        monitor.stop()
    }

    @Test func aNoticeOnAnotherCenterChangesNothing() async {
        let fake = FakeSystemAccent(Self.teal)
        let monitor = SystemAccentMonitor(provider: fake, center: NotificationCenter())
        monitor.start()
        fake.color = Self.plum
        NotificationCenter().post(name: NSColor.systemColorsDidChangeNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(monitor.accent == Self.teal)
        #expect(fake.reads == 1)
    }

    @Test func theSystemChoiceFollowsTheMonitor() async {
        let fake = FakeSystemAccent(Self.teal)
        let center = NotificationCenter()
        let monitor = SystemAccentMonitor(provider: fake, center: center)
        monitor.start()
        #expect(HangoverAccent.resolve(choice: .system, system: monitor.accent) == Self.teal)

        fake.color = nil
        center.post(name: NSColor.systemColorsDidChangeNotification, object: nil)
        #expect(await eventually { monitor.accent == nil })
        #expect(HangoverAccent.resolve(choice: .system, system: monitor.accent) == nil)
    }

    // MARK: - What a view gets

    @Test func aHighlightKeepsItsOwnColorOnDefaultAndTakesTheAccentOtherwise() {
        let own = Color(.sRGB, red: 1, green: 0.5, blue: 0)
        #expect(IslandHaloRGB(HangoverAccentTint.standard.highlight(own))?.hex == "FF8000")
        #expect(HangoverAccentTint.standard.controlTint == nil)

        let tint = HangoverAccentTint(rgb: Self.teal)
        #expect(IslandHaloRGB(tint.highlight(own))?.hex == Self.teal.hex)
        #expect(tint.controlTint.flatMap(IslandHaloRGB.init)?.hex == Self.teal.hex)
    }

    @Test func aViewOutsideEveryRootDrawsTodaysLook() {
        #expect(EnvironmentValues().hangoverAccent == .standard)
    }

    // MARK: - Strings

    /// Every string the accent added.
    private static let stringKeys = [
        "settings.appearance.accent.title",
        "settings.appearance.accent.note",
        "settings.appearance.accent.sample.today",
        "settings.appearance.accent.sample.todo",
        "settings.appearance.accent.sample.button",
    ] + HangoverAccentChoice.allCases.map(\.titleKey)

    @Test(arguments: ["en", "zh-Hans", "zh-Hant"])
    func everyNewStringIsInEveryLanguage(language: String) throws {
        let url = Self.repoRoot
            .appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
        let strings = try #require(NSDictionary(contentsOf: url) as? [String: String], "\(language) did not load")
        #expect(Self.stringKeys.count == 15)
        for key in Self.stringKeys {
            let text = strings[key] ?? ""
            #expect(!text.isEmpty, "\(language) is missing \(key)")
            #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"), "\(key) in \(language) has a dash")
        }
    }

    // MARK: - No highlight goes around the accent

    /// What a line may hold of the system's accent and still pass: the
    /// fallback handed to `highlight(`, and nothing else.
    private static let handedToHighlight = /\.highlight\(\s*(Color)?\.accentColor\s*\)/

    /// `.tint` handed to something that takes a style, as in
    /// `.foregroundStyle(.tint)`. A property named tint, the `.tint(color)`
    /// modifier and an enum's `.tint` case in a comparison are something else.
    private static let tintAsAStyle = try! NSRegularExpression(
        pattern: #"\b(foregroundStyle|foregroundColor|fill|stroke|strokeBorder|background|border|shadow)\([^)]*?(?<![\w\)\]])(?<![=!]=\s)(?<![=!]=)\.tint\b(?!\s*\()"#
    )

    /// Why a line draws the system's accent directly, or nil when it does not.
    static func goesAroundTheAccent(_ line: String) -> String? {
        let rest = line.replacing(handedToHighlight, with: "")
        if rest.contains("accentColor") || rest.contains("controlAccentColor") { return "the system's accent" }
        let range = NSRange(rest.startIndex..., in: rest)
        if tintAsAStyle.firstMatch(in: rest, range: range) != nil { return "the tint as a style" }
        return nil
    }

    @Test func theScanKnowsWhatGoesAroundTheAccent() {
        // Caught.
        #expect(Self.goesAroundTheAccent("    .foregroundStyle(Color.accentColor)") != nil)
        #expect(Self.goesAroundTheAccent("    .fill(.accentColor.opacity(0.2))") != nil)
        #expect(Self.goesAroundTheAccent("    .foregroundStyle(.tint)") != nil)
        #expect(Self.goesAroundTheAccent("    .fill(.tint.opacity(0.3))") != nil)
        #expect(Self.goesAroundTheAccent("    let c = NSColor.controlAccentColor") != nil)
        // A line that calls `highlight(` and also draws the accent beside it.
        #expect(Self.goesAroundTheAccent("    x.highlight(.white).overlay(Color.accentColor)") != nil)
        #expect(Self.goesAroundTheAccent("    accent.highlight(Color.accentColor).shadow(color: .accentColor, radius: 2)") != nil)
        // Passed.
        #expect(Self.goesAroundTheAccent("    .foregroundStyle(accent.highlight(Color.accentColor))") == nil)
        #expect(Self.goesAroundTheAccent("    .stroke(model.accentTint.highlight(.accentColor).opacity(0.35))") == nil)
        #expect(Self.goesAroundTheAccent("    .tint(accent.controlTint)") == nil)
        #expect(Self.goesAroundTheAccent("    .tint(.white.opacity(0.7))") == nil)
        #expect(Self.goesAroundTheAccent("    leading: .symbol(transient.symbol, transient.tint)") == nil)
        #expect(Self.goesAroundTheAccent("    NookPomodoroLook.tint(for: round)") == nil)
        #expect(Self.goesAroundTheAccent("    .fill(V6Palette.paper.opacity(option == .tint ? 0.55 : 0.22))") == nil)
        #expect(Self.goesAroundTheAccent("    items: [.animatedDot, .bar, .glyph, .tint].map {") == nil)
        #expect(Self.goesAroundTheAccent("    .foregroundStyle(isOn ? .tint : .secondary)") != nil)
    }

    /// A highlight drawn with the system's accent directly would ignore the
    /// user's choice. Every line of the app passes the rule above but the
    /// two files below.
    @Test func noViewDrawsTheSystemsAccentDirectly() throws {
        let allowed = [
            // The one read of the system's accent, behind the protocol.
            "Personalization/HangoverAccent.swift",
            // An event with no calendar: a calendar's color, never the accent.
            "Nook/Widgets/Calendar/NookCalendarService.swift",
        ]
        let root = Self.repoRoot.appendingPathComponent("Sources/OpenIslandApp", isDirectory: true)
        let files = Self.swiftFiles(under: root)
        #expect(files.count > 100, "the sources were not found")

        var offenders: [String] = []
        for file in files {
            let path = file.path.replacingOccurrences(of: root.path + "/", with: "")
            if allowed.contains(path) { continue }
            let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() {
                // A comment may say the words.
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                if let reason = Self.goesAroundTheAccent(String(line)) {
                    offenders.append("\(path):\(index + 1) (\(reason))")
                }
            }
        }
        #expect(offenders.isEmpty, "these lines skip the user's accent: \(offenders)")
    }

    private static func swiftFiles(under root: URL) -> [URL] {
        FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
    }

    /// `Tests/OpenIslandAppTests/<this file>` sits three levels below the root.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
