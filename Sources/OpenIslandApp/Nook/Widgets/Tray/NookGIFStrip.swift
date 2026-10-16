import SwiftUI

/// Sizes of the GIF options strip, in a plain enum and not the View: a
/// closure in a View static traps when a nonisolated test reads it.
enum NookGIFStripLayout {
    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 12
    /// Room for the sheet with both controls side by side, plus the row
    /// the two minute sentence drops to when a clip is too long.
    static let tooLongRow: CGFloat = 20

    static var height: CGFloat {
        NookGIFSheetLayout.wideHeight + tooLongRow + verticalPadding * 2
    }

    static var pageHeight: CGFloat { height + NookWidgetLayout.rowSpacing }
}

/// The tray's GIF options, shown above the cards at the page's full width
/// the way the event editor is (D68). A tray card at any size is too short
/// for them.
struct NookGIFStrip: View {
    let tray: NookTrayStore
    let source: NookTrayItem

    var body: some View {
        NookGIFSheet(
            sourceURL: tray.storedURL(for: source),
            sourceName: source.originalName,
            waitingOn: tray.gifBlocker?.originalName,
            onMake: { tray.startGIF(options: $0) },
            onCancel: { tray.cancelGIF() }
        )
        .padding(.horizontal, NookGIFStripLayout.horizontalPadding)
        .padding(.vertical, NookGIFStripLayout.verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NookCardBackground())
    }
}
