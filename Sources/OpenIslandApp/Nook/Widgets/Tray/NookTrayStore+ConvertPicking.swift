import Foundation

/// Convert mode for the tray: the Convert chip in the card's header turns on
/// picking, a click on a file that has conversions opens the Convert strip
/// for it (`NookConvertStrip`), and a choice there starts the conversion.
/// The state itself, `isPickingToConvert` and `convertSourceItem`, is
/// declared in `NookTrayStore.swift`, because a stored property cannot live
/// in an extension.
extension NookTrayStore {
    // MARK: - Picking

    /// The Convert chip: turns picking on, or off when it is already on.
    func togglePickingToConvert() {
        if isPickingToConvert {
            cancelPickingToConvert()
        } else {
            beginPickingToConvert()
        }
    }

    /// Starts waiting for a click on a file. Nothing starts without files
    /// to choose from, or while the clipboard is the tab on show.
    func beginPickingToConvert() {
        guard tab == .files, !items.isEmpty else { return }
        isPickingToConvert = true
    }

    func cancelPickingToConvert() {
        isPickingToConvert = false
    }

    /// True when the file has something to be turned into. The name decides,
    /// which is cheap enough to ask for every tile on every draw.
    func canPickToConvert(_ item: NookTrayItem) -> Bool {
        !NookConvertRules.actions(forFileNamed: item.originalName).isEmpty
    }

    /// A click on a file while picking. A file with conversions opens the
    /// strip for it and ends picking. Any other file does nothing, and
    /// picking goes on. False when nothing was picked.
    @discardableResult
    func pickToConvert(_ item: NookTrayItem) -> Bool {
        guard isPickingToConvert,
              items.contains(where: { $0.id == item.id }),
              canPickToConvert(item) else {
            return false
        }
        isPickingToConvert = false
        convertSourceItem = item
        return true
    }

    // MARK: - The strip

    /// What a button in the Convert strip does: starts the conversion, or
    /// opens the GIF options for Make GIF, and closes the strip. Nil when
    /// no job was started. A choice the file is not offered, or one made
    /// while a conversion still reads the file, does nothing and leaves the
    /// strip open.
    @discardableResult
    func chooseConversion(_ action: NookConvertAction, for item: NookTrayItem) -> Task<Void, Never>? {
        let job = convert(item, action: action)
        let opensGIFOptions = action == .makeGIF && gifSourceItem?.id == item.id
        if job != nil || opensGIFOptions { convertSourceItem = nil }
        return job
    }

    /// Closes the strip without making anything.
    func cancelConvertStrip() {
        convertSourceItem = nil
    }

    /// The file that keeps the strip's buttons off, nil when they can run.
    /// The strip names this file while it waits.
    var convertBlocker: NookTrayItem? {
        convertSourceItem.flatMap { busyItem(among: [$0]) }
    }

    // MARK: - Ending

    /// Called once `item` is gone from the list: its strip closes, and
    /// picking ends when there is nothing left to pick.
    func convertModeDidRemove(_ item: NookTrayItem) {
        if convertSourceItem?.id == item.id { convertSourceItem = nil }
        if items.isEmpty { isPickingToConvert = false }
    }

    /// Picking and the strip both end, as when the tray is cleared.
    func endConvertMode() {
        isPickingToConvert = false
        convertSourceItem = nil
    }
}
