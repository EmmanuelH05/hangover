import SwiftUI

/// Sizes of the all-files strip, in a plain enum and not the View: a closure
/// in a View static traps when a nonisolated test reads it.
///
/// The strip has one fixed height, because the window is sized from it
/// (`NookPageExtras`): the header, then three rows of roomy tiles in view.
/// More files than that scroll.
enum NookTrayAllFilesLayout {
    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 12
    static let headerHeight: CGFloat = 28
    /// The gap between the header and the first row.
    static let headerGap: CGFloat = 10
    /// One roomy tile: its icon, the gap and one line of its name.
    static let tileHeight: CGFloat = 56
    static let rowSpacing: CGFloat = 8
    static let columnSpacing: CGFloat = 6
    /// Eight a row at the widest island (O3); a narrower island holds fewer,
    /// the large card's rule.
    static let maxColumns = 8
    static let rowsInView = 3
    static let scrollBarWidth: CGFloat = 4
    /// Between the grid and the scroll bar.
    static let scrollBarGap: CGFloat = 10

    /// The room for the rows in view.
    static var bodyHeight: CGFloat {
        let rows = CGFloat(rowsInView)
        return rows * tileHeight + (rows - 1) * rowSpacing
    }

    static var height: CGFloat {
        headerHeight + headerGap + bodyHeight + verticalPadding * 2
    }

    static var pageHeight: CGFloat { height + NookWidgetLayout.rowSpacing }

    /// Roomy tiles that fit beside the scroll bar in a strip `width` wide
    /// inside its padding, at most eight.
    static func columns(forWidth width: CGFloat) -> Int {
        let room = width - scrollBarGap - scrollBarWidth
        return min(maxColumns, NookTrayRowLayout.slots(width: room, tileWidth: NookTrayTileMetrics.roomy.width))
    }

    /// The height of all the rows together, which is what the scroll bar
    /// measures the view against.
    static func contentHeight(forFileCount count: Int, columns: Int) -> CGFloat {
        let columns = max(1, columns)
        let rows = (count + columns - 1) / columns
        guard rows > 0 else { return 0 }
        return CGFloat(rows) * tileHeight + CGFloat(rows - 1) * rowSpacing
    }

    /// The thumb's height and its distance from the top of the track, for a
    /// scroll `offset` points down. Nil when everything fits and no bar
    /// shows.
    static func thumb(contentHeight: CGFloat, viewHeight: CGFloat, offset: CGFloat) -> (height: CGFloat, top: CGFloat)? {
        guard contentHeight > viewHeight + 0.5, viewHeight > 0 else { return nil }
        let thumbHeight = max(16, viewHeight * viewHeight / contentHeight)
        let travel = viewHeight - thumbHeight
        let reach = contentHeight - viewHeight
        let fraction = min(1, max(0, offset / reach))
        return (thumbHeight, travel * fraction)
    }
}

/// Every file in the tray, shown above the cards at the page's full width
/// the way the GIF options and the Convert strip are. The tiles are the
/// card's own: they drag out and keep Convert and the right-click menu.
struct NookTrayAllFilesStrip: View {
    let tray: NookTrayStore
    @State private var offset: CGFloat = 0
    @Environment(\.nookDrawsStill) private var drawsStill

    private typealias Layout = NookTrayAllFilesLayout

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.headerGap) {
            header
            fileList
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NookCardBackground())
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: NookTrayHeaderLayout.gap) {
            HStack(spacing: 4) {
                Image(systemName: NookTrayTab.files.symbol)
                Text(LanguageManager.shared.t("nook.tray.allFiles.title").uppercased())
                    .tracking(0.6)
                    .lineLimit(1)
                    .fixedSize()
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.8))
            Text("\(tray.items.count)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
            Spacer(minLength: 8)
            doneButton
        }
        .frame(height: Layout.headerHeight)
    }

    private var doneButton: some View {
        let title = LanguageManager.shared.t("nook.tray.allFiles.done")
        return Button {
            tray.hideAllFiles()
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(Capsule().fill(Color.white.opacity(0.1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    // MARK: Files

    private var fileList: some View {
        GeometryReader { proxy in
            fileList(columns: Layout.columns(forWidth: proxy.size.width))
        }
        .frame(height: Layout.bodyHeight)
    }

    private func fileList(columns: Int) -> some View {
        let content = Layout.contentHeight(forFileCount: tray.items.count, columns: columns)
        let thumb = NookScrollOffset.isTracked
            ? Layout.thumb(contentHeight: content, viewHeight: Layout.bodyHeight, offset: offset)
            : nil
        return HStack(alignment: .top, spacing: Layout.scrollBarGap) {
            if drawsStill {
                // A picture of the strip cannot draw a scroll view's
                // contents, which leaves it at the top, clipped.
                tiles(columns: columns)
                    .frame(height: Layout.bodyHeight, alignment: .top)
                    .clipped()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    tiles(columns: columns)
                }
                .nookScrollOffset(.vertical, into: $offset)
            }
            if let thumb {
                scrollBar(thumb)
            }
        }
        .frame(height: Layout.bodyHeight)
    }

    /// Every file in rows of `columns`, the last row's gaps kept to hold its
    /// tiles in their columns. Lazy: only the rows in view are built.
    private func tiles(columns: Int) -> some View {
        let rows = stride(from: 0, to: tray.items.count, by: columns).map {
            Array(tray.items[$0..<min($0 + columns, tray.items.count)])
        }
        return LazyVStack(spacing: Layout.rowSpacing) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: Layout.columnSpacing) {
                    ForEach(rows[index]) { item in
                        NookTrayTile(store: tray, item: item, metrics: .roomy)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(0..<(columns - rows[index].count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                .frame(height: Layout.tileHeight, alignment: .top)
            }
        }
    }

    private func scrollBar(_ thumb: (height: CGFloat, top: CGFloat)) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(0.06))
            .frame(width: Layout.scrollBarWidth)
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.35))
                    .frame(height: thumb.height)
                    .offset(y: thumb.top)
            }
    }
}
