import AppKit
import SwiftUI

/// Something that knows where a control is on screen.
@MainActor
protocol DemoTargetFrameSource: AnyObject {
    /// The part of the control that shows, in AppKit's screen space (the
    /// origin at the bottom left of the main display). Nil while it is not
    /// on screen.
    var demoScreenFrame: CGRect? { get }
}

/// Where each tagged control is (D65). A control tags itself with
/// `.demoTarget(_:)`, and the drawn pointer asks here for the frame of the
/// control a step presses. Only the demo mode makes a registry: on any
/// other launch `current` is nil and a tag adds nothing to its view.
@MainActor
final class DemoTargetRegistry {
    /// The registry of this demo run. Nil outside the demo mode.
    private(set) static var current: DemoTargetRegistry?

    /// Makes the registry the tags report to. Only `DemoMode.activate()`
    /// calls it.
    static func install() -> DemoTargetRegistry {
        if let current { return current }
        let registry = DemoTargetRegistry()
        current = registry
        return registry
    }

    private struct Entry {
        weak var source: (any DemoTargetFrameSource)?
    }

    /// The tagged views of each target, oldest first.
    private var entries: [DemoTarget: [Entry]] = [:]
    /// Frames worked out by the app rather than read off a view, such as
    /// the closed island's.
    private var providers: [DemoTarget: () -> CGRect?] = [:]

    func add(_ source: any DemoTargetFrameSource, for target: DemoTarget) {
        var list = (entries[target] ?? []).filter { $0.source != nil && $0.source !== source }
        list.append(Entry(source: source))
        entries[target] = list
    }

    func remove(_ source: any DemoTargetFrameSource, for target: DemoTarget) {
        entries[target] = entries[target]?.filter { $0.source != nil && $0.source !== source }
    }

    func provide(_ target: DemoTarget, frame: @escaping () -> CGRect?) {
        providers[target] = frame
    }

    /// The frame of the control on screen now. When two views carry the
    /// tag, such as the same button in the island and in Settings, the
    /// newest one that shows wins.
    func frame(of target: DemoTarget) -> CGRect? {
        if let provider = providers[target] {
            return Self.usable(provider())
        }
        for entry in (entries[target] ?? []).reversed() {
            if let frame = Self.usable(entry.source?.demoScreenFrame) { return frame }
        }
        return nil
    }

    /// The middle of the control, where the pointer goes.
    func point(of target: DemoTarget) -> CGPoint? {
        frame(of: target).map { CGPoint(x: $0.midX, y: $0.midY) }
    }

    private static func usable(_ frame: CGRect?) -> CGRect? {
        guard let frame, !frame.isNull, !frame.isEmpty else { return nil }
        return frame
    }
}

// MARK: - The tag

extension View {
    /// Tells the demo mode where this control is (D65). Outside the demo
    /// mode it adds nothing: no view, no registry and no work. The target
    /// is worked out only in a demo run.
    func demoTarget(_ target: @autoclosure () -> DemoTarget) -> some View {
        modifier(DemoTargetTag(registry: DemoTargetRegistry.current, target: target))
    }
}

/// The tag. With no registry, which is every launch but a demo run, it
/// hands the view back as it was.
struct DemoTargetTag: ViewModifier {
    let registry: DemoTargetRegistry?
    let target: DemoTarget?

    init(registry: DemoTargetRegistry?, target: () -> DemoTarget) {
        self.registry = registry
        self.target = registry == nil ? nil : target()
    }

    func body(content: Content) -> some View {
        if let registry, let target {
            content.background(DemoTargetProbe(target: target, registry: registry))
        } else {
            content
        }
    }
}

/// An empty view the size of the tagged control. It reports itself while
/// it is in a window and never takes a click.
struct DemoTargetProbe: NSViewRepresentable {
    let target: DemoTarget
    let registry: DemoTargetRegistry

    func makeNSView(context: Context) -> DemoTargetProbeView {
        DemoTargetProbeView(target: target, registry: registry)
    }

    func updateNSView(_ view: DemoTargetProbeView, context: Context) {
        view.retarget(target)
    }

    static func dismantleNSView(_ view: DemoTargetProbeView, coordinator: ()) {
        view.leave()
    }
}

final class DemoTargetProbeView: NSView, DemoTargetFrameSource {
    private(set) var target: DemoTarget
    private weak var registry: DemoTargetRegistry?

    init(target: DemoTarget, registry: DemoTargetRegistry) {
        self.target = target
        self.registry = registry
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            registry?.remove(self, for: target)
        } else {
            registry?.add(self, for: target)
        }
    }

    /// A row that moved up the list carries another target now.
    func retarget(_ new: DemoTarget) {
        guard new != target else { return }
        registry?.remove(self, for: target)
        target = new
        if window != nil { registry?.add(self, for: target) }
    }

    func leave() {
        registry?.remove(self, for: target)
    }

    /// The part of the control a scroll view or the window does not cut
    /// off. `visibleRect` alone is not enough: inside the island's scroll
    /// view it gives the whole visible page in the control's own space, which
    /// put every control at the middle of the island.
    nonisolated static func shownPart(bounds: CGRect, visible: CGRect) -> CGRect? {
        let shown = visible.intersection(bounds)
        return shown.isNull || shown.isEmpty ? nil : shown
    }

    var demoScreenFrame: CGRect? {
        guard let window, window.isVisible, !isHiddenOrHasHiddenAncestor else { return nil }
        guard let shown = Self.shownPart(bounds: bounds, visible: visibleRect) else { return nil }
        let inWindow = convert(shown, to: nil)
        let content = window.contentView.map { $0.convert($0.bounds, to: nil) } ?? inWindow
        let clipped = inWindow.intersection(content)
        guard !clipped.isNull, !clipped.isEmpty else { return nil }
        return window.convertToScreen(clipped)
    }
}
