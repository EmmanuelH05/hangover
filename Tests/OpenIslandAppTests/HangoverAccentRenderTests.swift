import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// The accent color reaching real pixels (D62). The views that draw a
/// highlight are drawn offscreen with `ImageRenderer`, three ways:
///
/// - with an accent a test made up, to find that accent in the picture;
/// - with Default, to find none of it;
/// - with Default again, to find the color the view drew before the accent
///   existed. That color is not written down here as a number: the old
///   expression, as it stood in the source before the feature, is drawn
///   beside the view and the two are compared, which holds on any macOS.
///
/// No window, and never the system's own accent.
@MainActor
@Suite struct HangoverAccentRenderTests {
    /// A color nothing in the app draws by itself.
    private static let teal = IslandHaloRGB(rgb: 0x12B5A6)
    private static let tealTint = HangoverAccentTint(rgb: teal)
    private static let scale: CGFloat = 2
    /// How far a channel may be off and still count as the same color.
    private static let tolerance = 2.5 / 255

    // MARK: - Drawing

    private func bitmap<Content: View>(
        size: CGSize,
        accent: HangoverAccentTint,
        @ViewBuilder _ content: () -> Content
    ) throws -> NSBitmapImageRep {
        let view = content()
            .frame(width: size.width, height: size.height)
            .background(V6Palette.ink)
            .environment(\.colorScheme, .dark)
            .environment(\.nookDrawsStill, true)
            .environment(\.hangoverAccent, accent)
        let renderer = ImageRenderer(content: view)
        renderer.scale = Self.scale
        let image = try #require(renderer.nsImage, "the view did not draw")
        let data = try #require(image.tiffRepresentation)
        return try #require(NSBitmapImageRep(data: data))
    }

    private func count(in bitmap: NSBitmapImageRep, where matches: (NSColor) -> Bool) -> Int {
        var found = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if matches(color) { found += 1 }
            }
        }
        return found
    }

    /// Teal, full or laid over ink: little red, and a little more green
    /// than blue, which Apple's blue and green are not.
    private static func leansTeal(_ color: NSColor) -> Bool {
        color.redComponent < 0.3 && color.greenComponent > 0.5
            && color.blueComponent > 0.45 && color.greenComponent > color.blueComponent
    }

    /// How many pixels of a view, drawn on ink, lean teal.
    private func tealPixels<Content: View>(
        size: CGSize,
        accent: HangoverAccentTint,
        @ViewBuilder _ content: () -> Content
    ) throws -> Int {
        count(in: try bitmap(size: size, accent: accent, content), where: Self.leansTeal)
    }

    private func bothLooks<Content: View>(
        size: CGSize,
        @ViewBuilder _ content: () -> Content
    ) throws -> (standard: Int, accented: Int) {
        (
            try tealPixels(size: size, accent: .standard, content),
            try tealPixels(size: size, accent: Self.tealTint, content)
        )
    }

    /// The color a stack of flat layers comes to on ink, bottom first.
    private func flat(_ layers: [Color]) throws -> NSColor {
        let bitmap = try bitmap(size: CGSize(width: 8, height: 8), accent: .standard) {
            ZStack { ForEach(Array(layers.enumerated()), id: \.offset) { _, layer in layer } }
        }
        return try #require(bitmap.colorAt(x: 8, y: 8)?.usingColorSpace(.sRGB))
    }

    /// How many pixels of a view on Default are the color `layers` come to.
    private func pixelsOnDefault<Content: View>(
        size: CGSize,
        ofTheColor layers: [Color],
        @ViewBuilder _ content: () -> Content
    ) throws -> Int {
        let wanted = try flat(layers)
        return count(in: try bitmap(size: size, accent: .standard, content)) { color in
            abs(color.redComponent - wanted.redComponent) <= Self.tolerance
                && abs(color.greenComponent - wanted.greenComponent) <= Self.tolerance
                && abs(color.blueComponent - wanted.blueComponent) <= Self.tolerance
        }
    }

    // MARK: - Settings

    @Test func theSampleInSettingsShowsThePickAtOnce() throws {
        let size = CGSize(width: 520, height: 56)
        let looks = try bothLooks(size: size) {
            AccentSample(today: "Today", todo: "Checked off", button: "Start")
        }
        #expect(looks.standard == 0)
        // The scrub bar, the date, the tick and the button.
        #expect(looks.accented > 800)
        // On Default its button is the Nook's orange.
        let orange = try pixelsOnDefault(size: size, ofTheColor: [.orange]) {
            AccentSample(today: "Today", todo: "Checked off", button: "Start")
        }
        #expect(orange > 800)
    }

    @Test func aSelectedCardsRingTakesTheAccentAndAnUnselectedOneDrawsNone() throws {
        let size = CGSize(width: 140, height: 110)
        let selected = try bothLooks(size: size) {
            PersonalizationCard(title: "Blue", selected: true, action: {}) { Color.clear }
        }
        #expect(selected.standard == 0)
        #expect(selected.accented > 300)

        let unselected = try tealPixels(size: size, accent: Self.tealTint) {
            PersonalizationCard(title: "Blue", selected: false, action: {}) { Color.clear }
        }
        #expect(unselected == 0)

        // Before: `cardShape.strokeBorder(V6Palette.paper.opacity(0.9), lineWidth: 1.5)`
        // over a selected tile's fill, white at 0.07.
        let before = try pixelsOnDefault(size: size, ofTheColor: [.white.opacity(0.07), V6Palette.paper.opacity(0.9)]) {
            PersonalizationCard(title: "Blue", selected: true, action: {}) { Color.clear }
        }
        #expect(before > 100)
    }

    @Test func aSelectedChipIsFilledWithTheAccent() throws {
        let size = CGSize(width: 120, height: 40)
        let selected = try bothLooks(size: size) {
            MonoChip(title: "Running", selected: true, action: {})
        }
        #expect(selected.standard == 0)
        #expect(selected.accented > 500)

        let unselected = try tealPixels(size: size, accent: Self.tealTint) {
            MonoChip(title: "Running", selected: false, action: {})
        }
        #expect(unselected == 0)

        // Before: `if selected { return V6Palette.paper }`.
        let before = try pixelsOnDefault(size: size, ofTheColor: [V6Palette.paper]) {
            MonoChip(title: "Running", selected: true, action: {})
        }
        #expect(before > 500)
    }

    @Test func aFixedChoicesSwatchIsItsOwnColorWhateverTheAccentIs() throws {
        // The swatches are what the user picks from: the current accent
        // must never repaint them.
        let size = CGSize(width: 40, height: 40)
        for choice in HangoverAccentChoice.fixed {
            let found = try tealPixels(size: size, accent: Self.tealTint) {
                AccentSwatch(choice: choice, systemColor: nil)
            }
            #expect(found == 0, "\(choice.rawValue)'s swatch took the accent")
        }
        let standard = try tealPixels(size: size, accent: Self.tealTint) {
            AccentSwatch(choice: .standard, systemColor: nil)
        }
        #expect(standard == 0)
    }

    @Test func theSystemSwatchShowsWhatMacOSIsSetTo() throws {
        let size = CGSize(width: 40, height: 40)
        let read = try tealPixels(size: size, accent: .standard) {
            AccentSwatch(choice: .system, systemColor: Self.teal)
        }
        let unread = try tealPixels(size: size, accent: .standard) {
            AccentSwatch(choice: .system, systemColor: nil)
        }
        #expect(read > 500)
        #expect(unread == 0)
    }

    @Test func theSampleScrubBarInSettingsTakesTheAccent() throws {
        let size = CGSize(width: 200, height: 20)
        let looks = try bothLooks(size: size) { NookSampleProgress(fraction: 0.5) }
        #expect(looks.standard == 0)
        #expect(looks.accented > 400)
        // Before: `.fill(Color.white.opacity(0.8))` on a track of white at 0.15.
        let before = try pixelsOnDefault(size: size, ofTheColor: [.white.opacity(0.15), .white.opacity(0.8)]) {
            NookSampleProgress(fraction: 0.5)
        }
        #expect(before > 400)
    }

    // MARK: - The welcome tour

    @Test func theToursPickedCardAndItsMainButtonTakeTheAccent() throws {
        let cardSize = CGSize(width: 160, height: 100)
        let card = try bothLooks(size: cardSize) {
            OnboardingChoiceCard(isSelected: true, action: {}) { Color.clear }
        }
        #expect(card.standard == 0)
        #expect(card.accented > 300)
        // Before: `OnboardingStyle.paper.opacity(0.9)` at 1.5 over
        // `OnboardingStyle.selectedFill`, white at 0.11.
        let ring = try pixelsOnDefault(size: cardSize, ofTheColor: [.white.opacity(0.11), V6Palette.paper.opacity(0.9)]) {
            OnboardingChoiceCard(isSelected: true, action: {}) { Color.clear }
        }
        #expect(ring > 100)

        let buttonSize = CGSize(width: 140, height: 50)
        let button = try bothLooks(size: buttonSize) {
            Button("Next") {}.buttonStyle(OnboardingPrimaryButtonStyle())
        }
        #expect(button.standard == 0)
        #expect(button.accented > 1_000)
        // Before: `Capsule().fill(OnboardingStyle.paper.opacity(1))`.
        let paper = try pixelsOnDefault(size: buttonSize, ofTheColor: [V6Palette.paper]) {
            Button("Next") {}.buttonStyle(OnboardingPrimaryButtonStyle())
        }
        #expect(paper > 1_000)
    }

    // MARK: - The island: calendar

    @Test func todayIsANumberOnDefaultAndACircleOfTheAccentOtherwise() throws {
        let size = CGSize(width: 40, height: 40)
        let font = Font.system(size: 15, weight: .semibold)
        let looks = try bothLooks(size: size) {
            NookDayNumber(text: "28", isToday: true, font: font, diameter: 22)
        }
        #expect(looks.standard == 0)
        // A 22 point circle at 2x, less the number on it.
        #expect(looks.accented > 900)

        let ordinary = try tealPixels(size: size, accent: Self.tealTint) {
            NookDayNumber(text: "28", isToday: false, font: font, diameter: 22)
        }
        #expect(ordinary == 0)

        // Before: `.foregroundStyle(isToday ? Color.orange : Color.white.opacity(0.85))`
        // and no circle. The strokes of the digits are the Nook's orange.
        let orange = try pixelsOnDefault(size: size, ofTheColor: [.orange]) {
            NookDayNumber(text: "28", isToday: true, font: font, diameter: 22)
        }
        #expect(orange > 20)
        let plain = try pixelsOnDefault(size: size, ofTheColor: [.white.opacity(0.85)]) {
            NookDayNumber(text: "28", isToday: false, font: font, diameter: 22)
        }
        #expect(plain > 20)
    }

    @Test func inTheEventEditorsMonthTodayTakesTheAccentAndThePickedDayStaysWhite() throws {
        let size = CGSize(width: 180, height: 170)
        let today = Date()
        // Three days on is always in the six weeks the month draws.
        let other = try #require(Calendar.current.date(byAdding: .day, value: 3, to: today))
        let month = { NookMiniMonth(visibleMonth: .constant(today), picked: other, onPick: { _ in }) }

        let looks = try bothLooks(size: size) { month() }
        #expect(looks.standard == 0)
        #expect(looks.accented > 150)

        // Before: `Circle().fill(isPicked ? Color.white.opacity(0.9) : Color.clear)`.
        // The picked day keeps that circle with an accent set and without.
        let white: [Color] = [.white.opacity(0.9)]
        #expect(try pixelsOnDefault(size: size, ofTheColor: white) { month() } > 150)
        let pickedWithAccent = count(in: try bitmap(size: size, accent: Self.tealTint) { month() }) { color in
            color.redComponent > 0.85 && color.greenComponent > 0.85 && color.blueComponent > 0.85
        }
        #expect(pickedWithAccent > 150)
    }

    // MARK: - The island: music, to-dos, timer

    @Test func theScrubBarsPlayedPartTakesTheAccent() throws {
        let media = MediaRemoteService()
        let size = CGSize(width: 260, height: 40)
        let bar = {
            NookScrubBar(state: NookMediaSamples.track(isPlaying: false, duration: 200, elapsed: 100), media: media)
                .frame(width: 240)
        }
        let looks = try bothLooks(size: size) { bar() }
        #expect(looks.standard == 0)
        #expect(looks.accented > 300)
        // Before: `Capsule().fill(Color.white.opacity(0.85))` on a track of
        // white at 0.14.
        let played: [Color] = [.white.opacity(0.14), .white.opacity(0.85)]
        #expect(try pixelsOnDefault(size: size, ofTheColor: played) { bar() } > 300)
    }

    @Test func theTickOfATaskJustCheckedOffTakesTheAccent() throws {
        let size = CGSize(width: 30, height: 30)
        let looks = try bothLooks(size: size) { NookTodoTick(isChecked: true) }
        #expect(looks.standard == 0)
        #expect(looks.accented > 100)
        // A task not checked off is an empty circle and never the accent.
        #expect(try tealPixels(size: size, accent: Self.tealTint) { NookTodoTick(isChecked: false) } == 0)
        // Before: `.foregroundStyle(.white.opacity(0.6))`, checked or not.
        let dimWhite: [Color] = [.white.opacity(0.6)]
        #expect(try pixelsOnDefault(size: size, ofTheColor: dimWhite) { NookTodoTick(isChecked: true) } > 100)
    }

    @Test func aPlainCountdownsLineTakesTheAccentAndAPomodoroRoundsDoesNot() throws {
        let size = CGSize(width: 200, height: 20)
        let plain = try bothLooks(size: size) { NookTimerProgressLine(progress: 0.5, pomodoro: nil) }
        #expect(plain.standard == 0)
        #expect(plain.accented > 400)

        let round = try tealPixels(size: size, accent: Self.tealTint) {
            NookTimerProgressLine(progress: 0.5, pomodoro: NookPomodoroState(phase: .shortBreak, round: 1))
        }
        #expect(round == 0)

        // Before: `.fill(NookPomodoroLook.tint(for: timer.pomodoro))`, which
        // is orange for a plain countdown.
        let orange = try pixelsOnDefault(size: size, ofTheColor: [.orange]) {
            NookTimerProgressLine(progress: 0.5, pomodoro: nil)
        }
        #expect(orange > 400)
    }

    @Test func theTimersMainButtonTakesTheAccentAndItsQuietOneDoesNot() throws {
        let size = CGSize(width: 100, height: 40)
        let main = try bothLooks(size: size) {
            Button("Start") {}.buttonStyle(NookTimerButtonStyle(prominent: true, width: 56))
        }
        #expect(main.standard == 0)
        #expect(main.accented > 1_000)

        let quiet = try tealPixels(size: size, accent: Self.tealTint) {
            Button("Reset") {}.buttonStyle(NookTimerButtonStyle(prominent: false, width: 56))
        }
        #expect(quiet == 0)

        // Before: `Capsule().fill(prominent ? Color.orange : ...)`.
        let orange = try pixelsOnDefault(size: size, ofTheColor: [.orange]) {
            Button("Start") {}.buttonStyle(NookTimerButtonStyle(prominent: true, width: 56))
        }
        #expect(orange > 1_000)
    }

    // MARK: - The island: layout editor

    @Test func theCurrentSizeChipIsFilledWithTheAccent() throws {
        let size = CGSize(width: 200, height: 100)
        let overlay = {
            NookWidgetEditOverlay(
                placement: NookWidgetPlacement(kind: .media, size: .medium),
                isHighlighted: false,
                reorder: DragGesture(),
                onResize: { _ in },
                onRemove: {}
            )
        }
        let looks = try bothLooks(size: size) { overlay() }
        #expect(looks.standard == 0)
        // A 22 point square at 2x, less its letter and its round corners.
        #expect(looks.accented > 1_000)

        // Before: `.fill(Color.orange.opacity(0.2))` in a capsule of black
        // at 0.4.
        let before = try pixelsOnDefault(size: size, ofTheColor: [.black.opacity(0.4), .orange.opacity(0.2)]) { overlay() }
        #expect(before > 800)
    }

    @Test func theLayoutEditorsDoneButtonTakesTheAccent() throws {
        let size = CGSize(width: 420, height: 70)
        let shelf = {
            NookWidgetShelf(
                addable: [],
                order: [.media],
                tileFrames: [:],
                insertionTarget: .constant(nil),
                onAdd: { _ in },
                onAddAt: { _, _ in },
                onDone: {}
            )
        }
        let looks = try bothLooks(size: size) { shelf() }
        #expect(looks.standard == 0)
        #expect(looks.accented > 300)
        // Before: `.background(Capsule().fill(Color.orange))`.
        #expect(try pixelsOnDefault(size: size, ofTheColor: [.orange]) { shelf() } > 300)
    }

    // MARK: - The island: agents

    /// A question's answer, drawn from the same numbers the card uses.
    private func answer(isSelected: Bool, isHovered: Bool = false) -> some View {
        AnswerRow(isSelected: isSelected, isHovered: isHovered)
    }

    private struct AnswerRow: View {
        let isSelected: Bool
        let isHovered: Bool
        @Environment(\.hangoverAccent) private var accent

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            HStack {
                IslandQuestionOptionBadge(number: 1, isSelected: isSelected)
                Spacer()
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 11)
            .background(shape.fill(IslandQuestionOptionLook.fill(isSelected: isSelected, isHovered: isHovered, accent: accent).color))
            .overlay(shape.strokeBorder(IslandQuestionOptionLook.stroke(isSelected: isSelected, isHovered: isHovered, accent: accent).color))
            .frame(width: 200)
        }
    }

    @Test func aPickedAnswerAndItsBadgeTakeTheAccent() throws {
        let size = CGSize(width: 220, height: 50)
        let picked = try bothLooks(size: size) { answer(isSelected: true) }
        #expect(picked.standard == 0)
        // The badge is the accent itself: 22 by 20 points at 2x, less the number.
        #expect(picked.accented > 1_200)

        // Rows at rest and under the pointer never take it.
        #expect(try tealPixels(size: size, accent: Self.tealTint) { answer(isSelected: false) } == 0)
        #expect(try tealPixels(size: size, accent: Self.tealTint) { answer(isSelected: false, isHovered: true) } == 0)

        // Before: the row was `V6Palette.paper.opacity(0.10)` and the badge
        // `V6Palette.paper.opacity(0.88)` on it.
        let row = try pixelsOnDefault(size: size, ofTheColor: [V6Palette.paper.opacity(0.10)]) { answer(isSelected: true) }
        #expect(row > 5_000)
        let badge = try pixelsOnDefault(
            size: size,
            ofTheColor: [V6Palette.paper.opacity(0.10), V6Palette.paper.opacity(0.88)]
        ) { answer(isSelected: true) }
        #expect(badge > 1_200)
    }

    @Test func theIslandsMainButtonTakesTheAccentAndTheOthersDoNot() throws {
        let size = CGSize(width: 140, height: 50)
        let main = try bothLooks(size: size) {
            Button("Allow") {}.buttonStyle(IslandActionButtonStyle(kind: .primary))
        }
        #expect(main.standard == 0)
        #expect(main.accented > 1_500)

        for kind in [IslandActionButtonStyle.Kind.secondary, .warning] {
            let found = try tealPixels(size: size, accent: Self.tealTint) {
                Button("Deny") {}.buttonStyle(IslandActionButtonStyle(kind: kind))
            }
            #expect(found == 0)
        }

        // Before: `return V6Palette.paper.opacity(pressedFactor)`, which is
        // paper itself while the button is not pressed.
        let paper = try pixelsOnDefault(size: size, ofTheColor: [V6Palette.paper]) {
            Button("Allow") {}.buttonStyle(IslandActionButtonStyle(kind: .primary))
        }
        #expect(paper > 1_500)
    }

    // MARK: - The design kit

    /// The kit came before the accent and drew its highlights in orange
    /// whatever was picked: a purple accent left "Equip the switch?" orange.
    @Test func theDesignKitsSwitchedOnChipsTakeTheAccent() throws {
        let size = CGSize(width: 120, height: 40)
        let chip = try bothLooks(size: size) { NookDesignChipLabel(text: "Hex", isOn: true) }
        #expect(chip.standard == 0)
        #expect(chip.accented > 300)
        let quiet = try bothLooks(size: size) { NookDesignChipLabel(text: "Hex", isOn: false) }
        #expect(quiet.accented == 0)

        let button = try bothLooks(size: size) {
            NookDesignIconButton(symbol: "eyedropper", label: "Pick", isOn: true) {}
        }
        #expect(button.standard == 0)
        #expect(button.accented > 300)
        // On the look the app came with, the chip is the orange it always was.
        let orange = try pixelsOnDefault(size: size, ofTheColor: [.orange]) {
            NookDesignChipLabel(text: "Hex", isOn: true)
        }
        #expect(orange > 300)
    }

    @Test func theDesignKitsDropTargetTakesTheAccent() throws {
        let size = CGSize(width: 240, height: 90)
        let drop = try bothLooks(size: size) { NookDesignDropHighlight(isCompact: false) }
        #expect(drop.standard == 0)
        #expect(drop.accented > 300)
    }
}
