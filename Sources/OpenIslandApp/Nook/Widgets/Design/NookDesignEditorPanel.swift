import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The palette editor's window. A floating, non-activating panel: it can
/// take the keyboard for the fields in it while the app the user is
/// working in stays the front app. Unlike a reference panel it is a place
/// to type, which is why a click in it gives it the keyboard.
final class NookDesignEditorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Escape closes the editor.
    override func cancelOperation(_ sender: Any?) {
        close()
    }

    /// AppKit spends the first click on a window that is not key on
    /// making it key, unless the view under it accepts first mouse, and
    /// the views inside a scroll view do not. Becoming key before the
    /// click is looked at delivers it. The island's own panel does the
    /// same.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !isKeyWindow {
            makeKey()
        }
        super.sendEvent(event)
    }
}

/// Opens the palette editor and runs its file dialogs. Only a real launch
/// makes one.
@MainActor
final class NookDesignEditorPanelController: NSObject, NookDesignEditorPresenting, NSWindowDelegate {
    private var panel: NookDesignEditorPanel?

    func show(_ kit: NookDesignKit) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let size = NookDesignPaletteEditor.idealSize
        let panel = NookDesignEditorPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = LanguageManager.shared.t("nook.design.editor.title")
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.animationBehavior = Motion.prefersReducedMotion ? .none : .utilityWindow
        panel.minSize = NookDesignPaletteEditor.minimumSize
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.backgroundColor = NSColor(V6Palette.ink)

        let editor = NookDesignPaletteEditor(
            kit: kit,
            onImport: { [weak self, weak kit] in
                guard let kit else { return }
                self?.chooseImport(for: kit)
            },
            onExport: { [weak self, weak kit] ids in
                guard let kit else { return }
                self?.chooseExport(of: ids, for: kit)
            }
        )
        let hosting = NSHostingView(rootView: editor)
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.delegate = self
        panel.setContentSize(size)
        Self.place(panel)
        self.panel = panel
        // The user asked for the editor, and it is a place to type.
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.close()
    }

    func windowWillClose(_ notification: Notification) {
        panel?.delegate = nil
        panel = nil
    }

    // MARK: File dialogs

    /// The app is seldom the front app, and a file dialog opened behind
    /// another app's windows would be lost. It comes forward for the
    /// dialog, the way it does to choose a GIF.
    private func chooseImport(for kit: NookDesignKit) {
        let dialog = NSOpenPanel()
        dialog.allowedContentTypes = [.json]
        dialog.allowsMultipleSelection = false
        dialog.canChooseDirectories = false
        dialog.message = LanguageManager.shared.t("nook.design.editor.import.help")
        NSApp.activate(ignoringOtherApps: true)
        if let url = run(dialog, for: kit) {
            kit.importPalettes(fromFileAt: url)
        }
        panel?.makeKeyAndOrderFront(nil)
    }

    private func chooseExport(of ids: [UUID], for kit: NookDesignKit) {
        let chosen = kit.palettes.library.palettes.filter { ids.contains($0.id) }
        guard !chosen.isEmpty else { return }
        let dialog = NSSavePanel()
        dialog.allowedContentTypes = [.json]
        dialog.canCreateDirectories = true
        dialog.nameFieldStringValue = NookDesignPaletteExchange.fileName(
            for: chosen,
            fallback: LanguageManager.shared.t("nook.design.editor.exportName")
        )
        NSApp.activate(ignoringOtherApps: true)
        if let url = run(dialog, for: kit) {
            kit.exportPalettes(ids, to: url)
        }
        panel?.makeKeyAndOrderFront(nil)
    }

    /// Runs a file dialog and returns the file it chose. The dialog is a
    /// system window on a level below the open island's, and the island can
    /// be held open (the mirror, the tour). It is counted as a system window
    /// while it is up, the way the tour's folder chooser is (D52), which
    /// steps an open island below it.
    private func run(_ dialog: NSSavePanel, for kit: NookDesignKit) -> URL? {
        kit.nook?.systemPromptBegan()
        defer { kit.nook?.systemPromptEnded() }
        return dialog.runModal() == .OK ? dialog.url : nil
    }

    // MARK: Private

    /// In the middle of the screen the pointer is on.
    private static func place(_ panel: NSPanel) {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return panel.center() }
        let size = panel.frame.size
        panel.setFrameOrigin(CGPoint(
            x: (visible.midX - size.width / 2).rounded(),
            y: (visible.midY - size.height / 2).rounded()
        ))
    }
}

extension NookDesignServices {
    /// The real services, for a real launch.
    static func system() -> NookDesignServices {
        NookDesignServices(
            sampler: NookDesignSystemColorSampler(),
            presenter: NookDesignReferencePanelController(),
            editor: NookDesignEditorPanelController(),
            pictureClipboard: NookDesignSystemPictureClipboard(),
            hotkeyRegistrar: NookDesignCarbonHotkey(),
            linkOpener: NookDesignSystemLinkOpener()
        )
    }
}
