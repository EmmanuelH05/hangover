import AppKit
import SwiftUI

/// Holds the AppKit view behind one tray tile. The system share picker
/// needs a real view to hang off, and SwiftUI does not hand one out.
@MainActor
final class NookTrayAnchorBox {
    weak var view: NSView?
}

/// An invisible view that fills the tile and reports itself to the box.
struct NookTrayShareAnchor: NSViewRepresentable {
    let box: NookTrayAnchorBox

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        box.view = view
    }
}

/// Puts up the system share picker for a tray file, and sends a file
/// straight to AirDrop. Says when the picker goes up and comes down, which
/// is what keeps the island open under it.
@MainActor
final class NookTraySharePresenter: NSObject, NSSharingServicePickerDelegate {
    var onOpenChange: ((Bool) -> Void)?

    /// Kept while it is up. The picker does not hold itself.
    private var picker: NSSharingServicePicker?

    /// False when there is no window to show the picker in.
    func showPicker(for url: URL, from view: NSView?) -> Bool {
        guard let view, view.window != nil else { return false }
        let picker = NSSharingServicePicker(items: [url])
        picker.delegate = self
        self.picker = picker
        onOpenChange?(true)
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        return true
    }

    /// False when AirDrop cannot take the file, for example when it is
    /// switched off.
    func airDrop(_ url: URL) -> Bool {
        guard let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: [url]) else {
            return false
        }
        // AirDrop opens a window of its own. The app has no Dock icon and
        // is seldom in front, which would leave that window behind others.
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: [url])
        return true
    }

    /// Called with a service when one was picked and with nil when the
    /// picker was dismissed. Either way it is down.
    nonisolated func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        didChoose service: NSSharingService?
    ) {
        Task { @MainActor [weak self] in
            self?.picker = nil
            self?.onOpenChange?(false)
        }
    }
}
