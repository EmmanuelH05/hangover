import Observation
import SwiftUI

/// Carries a demo script's typing into the field it is meant for (D65). A
/// field's view takes the hook `.demoTyping(_:text:focus:submit:)`. In the
/// demo mode the hook writes each key press into the field's own draft, the
/// way a key press changes it, and calls the field's own submit on Return.
/// Outside the demo mode there is no typist, and the hook adds nothing to
/// the view.
@MainActor
@Observable
final class DemoTypist {
    /// The typist of this demo run. Nil outside the demo mode.
    private(set) static var current: DemoTypist?

    /// Makes the typist the hooks talk to. Only `DemoMode.activate()`
    /// calls it.
    static func install() -> DemoTypist {
        if let current { return current }
        let typist = DemoTypist()
        current = typist
        return typist
    }

    /// What one field is told, as plain values its hook watches.
    struct Line: Equatable, Sendable {
        var text = ""
        /// Counts the key presses. A change tells the hook to copy `text`.
        var keys = 0
        /// Counts the clicks into the field.
        var focuses = 0
        /// Counts the presses of Return.
        var returns = 0
    }

    private(set) var lines: [DemoTypingField: Line] = [:]
    /// The hooks on screen now, for each field.
    @ObservationIgnored private var hooks: [DemoTypingField: Set<UUID>] = [:]

    func line(_ field: DemoTypingField) -> Line {
        lines[field] ?? Line()
    }

    /// Whether a field of this kind is on screen to take the typing.
    func isOnScreen(_ field: DemoTypingField) -> Bool {
        !(hooks[field]?.isEmpty ?? true)
    }

    func attach(_ field: DemoTypingField, hook: UUID) {
        hooks[field, default: []].insert(hook)
    }

    func detach(_ field: DemoTypingField, hook: UUID) {
        hooks[field]?.remove(hook)
    }

    /// The click into the field. Nothing is typed yet.
    func focus(_ field: DemoTypingField) {
        var line = line(field)
        line.text = ""
        line.focuses += 1
        lines[field] = line
    }

    /// One key press: `text` is what the field holds after it.
    func type(_ text: String, into field: DemoTypingField) {
        var line = line(field)
        line.text = text
        line.keys += 1
        lines[field] = line
    }

    /// Return in the field. False when no field of that kind is on screen,
    /// and the caller then saves the text through the field's service.
    @discardableResult
    func submit(_ field: DemoTypingField) -> Bool {
        guard isOnScreen(field) else { return false }
        var line = line(field)
        line.returns += 1
        lines[field] = line
        return true
    }
}

extension View {
    /// Lets the demo mode type into this field (D65). `text` is the field's
    /// own draft and `submit` the function its Return calls. `focus` is the
    /// field's focus when it has one already. Outside the demo mode this
    /// changes nothing.
    func demoTyping(
        _ field: DemoTypingField,
        text: Binding<String>,
        focus: FocusState<Bool>.Binding? = nil,
        submit: @escaping () -> Void
    ) -> some View {
        modifier(DemoTypingHook(field: field, text: text, focus: focus, typist: DemoTypist.current, submit: submit))
    }
}

/// The hook. With no typist, which is every launch but a demo run, it hands
/// the field back as it was.
struct DemoTypingHook: ViewModifier {
    let field: DemoTypingField
    @Binding var text: String
    let focus: FocusState<Bool>.Binding?
    let typist: DemoTypist?
    let submit: () -> Void

    func body(content: Content) -> some View {
        if let typist {
            content.modifier(DemoTypingLiveHook(field: field, text: $text, focus: focus, typist: typist, submit: submit))
        } else {
            content
        }
    }
}

/// The hook in a demo run.
private struct DemoTypingLiveHook: ViewModifier {
    let field: DemoTypingField
    @Binding var text: String
    let focus: FocusState<Bool>.Binding?
    var typist: DemoTypist
    let submit: () -> Void

    @State private var id = UUID()
    @FocusState private var ownFocus: Bool

    func body(content: Content) -> some View {
        let line = typist.line(field)
        Group {
            if focus == nil {
                content.focused($ownFocus)
            } else {
                content
            }
        }
        .onAppear { typist.attach(field, hook: id) }
        .onDisappear { typist.detach(field, hook: id) }
        .onChange(of: line.focuses) { _, _ in
            if let focus { focus.wrappedValue = true } else { ownFocus = true }
        }
        .onChange(of: line.keys) { _, _ in text = typist.line(field).text }
        .onChange(of: line.returns) { _, _ in submit() }
    }
}
