import SwiftUI

/// The link side of the card. Small shows the favorites and the most recent
/// few links as one-line rows. Medium and large add a field to type or
/// paste a link into, the collections as chips and the whole list, which
/// scrolls when there are more links than rows.
struct NookDesignLinksTab: View {
    var kit: NookDesignKit
    @Environment(\.nookWidgetSize) private var size
    @Environment(\.nookDesignIsStill) private var isStill

    var body: some View {
        let showsControls = size != .small
        VStack(alignment: .leading, spacing: 6) {
            if let naming = kit.linkNaming {
                NookDesignLinkNameRow(kit: kit, naming: naming)
                    .id(naming)
                    .frame(height: 24)
            } else if showsControls {
                controls
            }
            if kit.linkNaming == nil || showsControls {
                list(showsAll: showsControls)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The field, and the collection chips beside it at medium or under it
    /// at large.
    @ViewBuilder
    private var controls: some View {
        if size == .large {
            NookDesignLinkQuickAdd(kit: kit)
                .frame(height: 24)
            NookDesignLinkChips(kit: kit)
        } else {
            HStack(spacing: 8) {
                NookDesignLinkQuickAdd(kit: kit, showsButton: false)
                    .frame(minWidth: 232, maxWidth: 260)
                NookDesignLinkChips(kit: kit)
            }
            .frame(height: 22)
        }
    }

    private func list(showsAll: Bool) -> some View {
        let library = kit.links.library
        let links = library.orderedLinks(in: showsAll ? kit.activeLinkCollectionID : nil)
        let rowHeight = NookDesignLinkLayout.rowHeight(for: size)
        let spacing = NookDesignLinkLayout.rowSpacing(for: size)
        return GeometryReader { proxy in
            if links.isEmpty {
                emptyState(hasLinks: !library.links.isEmpty)
            } else {
                let capacity = NookDesignCardLayout.rowCapacity(height: proxy.size.height, rowHeight: rowHeight, spacing: spacing)
                if showsAll, !isStill, links.count > capacity {
                    ScrollView(.vertical, showsIndicators: false) {
                        rows(links, rowHeight: rowHeight, spacing: spacing)
                    }
                } else {
                    rows(Array(links.prefix(max(1, capacity))), rowHeight: rowHeight, spacing: spacing)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func rows(_ links: [NookDesignLink], rowHeight: CGFloat, spacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(links) { link in
                NookDesignLinkRow(kit: kit, link: link, height: rowHeight, showsHost: size != .small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func emptyState(hasLinks: Bool) -> some View {
        let lang = LanguageManager.shared
        let key = hasLinks
            ? "nook.design.links.empty.collection"
            : (size == .small ? "nook.design.links.empty.short" : "nook.design.links.empty.long")
        return Text(lang.t(key))
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.4))
            .lineLimit(size == .small ? 3 : 2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Sizes of the Links tab's rows. Pure, for the tests and the views.
enum NookDesignLinkLayout {
    static func rowHeight(for size: NookWidgetSize) -> CGFloat { size == .small ? 20 : 22 }
    static func rowSpacing(for size: NookWidgetSize) -> CGFloat { size == .small ? 4 : 3 }
}

// MARK: - A row

/// One link on one line: a mark, its name, and the Figma label or the host.
/// A click opens it. A right click lists the rest.
private struct NookDesignLinkRow: View {
    var kit: NookDesignKit
    let link: NookDesignLink
    let height: CGFloat
    let showsHost: Bool
    @Environment(\.nookDesignIsStill) private var isStill

    var body: some View {
        let lang = LanguageManager.shared
        let button = Button {
            kit.openLink(link.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: link.isFavorite ? "star.fill" : "link")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(link.isFavorite ? Color.yellow : Color.white.opacity(0.35))
                    .frame(width: 12)
                    .accessibilityHidden(true)
                Text(link.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                trailing
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lang.t("nook.design.action.openLink", link.name))

        if isStill {
            button
        } else {
            button
                .hoverHighlight(cornerRadius: 6)
                .help(link.url)
                .contextMenu { NookDesignLinkMenu(kit: kit, link: link) }
        }
    }

    /// The tick of a link just copied, else the Figma label, else the host.
    @ViewBuilder
    private var trailing: some View {
        if kit.justCopiedID == link.id {
            Image(systemName: "checkmark")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.green)
                .transition(.opacity)
        } else if let address = link.address, let figma = NookDesignLinkRules.figma(for: address) {
            NookDesignFigmaLabel(kind: figma.kind, isCompact: !showsHost)
        } else if showsHost, let host = link.address?.host {
            Text(host)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 120, alignment: .trailing)
        }
    }
}

/// The small "Figma" label, with the kind in plain words after it when the
/// path says which kind it is. Text only: nothing of the brand is drawn.
struct NookDesignFigmaLabel: View {
    let kind: NookDesignFigmaKind?
    var isCompact = false

    var body: some View {
        let lang = LanguageManager.shared
        let figma = lang.t("nook.design.links.figma")
        let text = kind.map { "\(figma) · \(lang.t($0.titleKey))" } ?? figma
        Text(isCompact ? figma : text)
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(height: 15)
            .background(Capsule().fill(Color.white.opacity(0.1)))
            .accessibilityLabel(text)
    }
}

// MARK: - The row's menu

/// Open, Copy link, Rename, Move to collection, Favorite or Unfavorite,
/// Delete.
private struct NookDesignLinkMenu: View {
    var kit: NookDesignKit
    let link: NookDesignLink

    var body: some View {
        let lang = LanguageManager.shared
        Button(lang.t("nook.design.action.open")) { kit.openLink(link.id) }
        Button(lang.t("nook.design.action.copyLink")) {
            withMotion(Motion.selection) { _ = kit.copyLink(link.id) }
        }
        Button(lang.t("nook.design.action.rename")) { kit.beginNaming(.renamingLink(link.id)) }
        Menu(lang.t("nook.design.action.moveToCollection")) {
            if link.collectionID != nil {
                Button(lang.t("nook.design.links.noCollection")) {
                    withMotion(Motion.reflow) { _ = kit.moveLink(link.id, to: nil) }
                }
            }
            ForEach(kit.links.collections.filter { $0.id != link.collectionID }) { collection in
                Button(NookDesignLinkText.name(of: collection)) {
                    withMotion(Motion.reflow) { _ = kit.moveLink(link.id, to: collection.id) }
                }
            }
            Divider()
            Button(lang.t("nook.design.action.newCollection")) { kit.beginNaming(.newCollection(forLink: link.id)) }
        }
        Button(lang.t(link.isFavorite ? "nook.design.action.unfavorite" : "nook.design.action.favorite")) {
            withMotion(Motion.reflow) { kit.toggleLinkFavorite(link.id) }
        }
        Divider()
        Button(lang.t("nook.design.action.deleteLink")) {
            withMotion(Motion.reflow) { kit.deleteLink(link.id) }
        }
    }
}

/// Words for things that may have no name.
enum NookDesignLinkText {
    static func name(of collection: NookDesignLinkCollection) -> String {
        collection.name.isEmpty ? LanguageManager.shared.t("nook.design.links.collection.untitled") : collection.name
    }
}

// MARK: - Collections

/// "All" and every collection as a chip, the lit one filtering the list.
/// A right click on a collection renames or deletes it. They sit in a plain
/// row while they all fit, and scroll sideways when they do not.
private struct NookDesignLinkChips: View {
    var kit: NookDesignKit
    @Environment(\.nookDesignIsStill) private var isStill

    var body: some View {
        let collections = kit.links.collections
        Group {
            if isStill {
                chips(Array(collections.prefix(3)))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ViewThatFits(in: .horizontal) {
                    chips(collections)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ScrollView(.horizontal, showsIndicators: false) {
                        chips(collections)
                    }
                }
            }
        }
        .frame(height: 22)
    }

    private func chips(_ collections: [NookDesignLinkCollection]) -> some View {
        let selected = kit.activeLinkCollectionID
        let lang = LanguageManager.shared
        return HStack(spacing: 5) {
            Button {
                withMotion(Motion.selection) { kit.selectLinkCollection(nil) }
            } label: {
                NookDesignChipLabel(text: lang.t("nook.design.links.all"), isOn: selected == nil)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected == nil ? .isSelected : [])
            ForEach(collections) { collection in
                let name = NookDesignLinkText.name(of: collection)
                let chip = Button {
                    withMotion(Motion.selection) { kit.selectLinkCollection(collection.id) }
                } label: {
                    NookDesignChipLabel(text: NookDesignCardLayout.chipText(name), isOn: collection.id == selected)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
                .accessibilityAddTraits(collection.id == selected ? .isSelected : [])
                if isStill {
                    chip
                } else {
                    chip.contextMenu {
                        Button(lang.t("nook.design.action.renameCollection")) {
                            kit.beginNaming(.renamingCollection(collection.id))
                        }
                        Button(lang.t("nook.design.action.deleteCollection")) {
                            withMotion(Motion.reflow) { kit.deleteCollection(collection.id) }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Typing a link

/// A field that takes a link and adds it on Return. While it holds text
/// that is not added, the island stays open (D20).
private struct NookDesignLinkQuickAdd: View {
    var kit: NookDesignKit
    /// The Add button shows where there is room. Return adds either way.
    var showsButton = true
    @State private var text = ""

    var body: some View {
        let lang = LanguageManager.shared
        HStack(spacing: 6) {
            NookDesignField(text: $text, prompt: lang.t("nook.design.links.add.prompt"), onSubmit: add)
            if showsButton {
                Button(action: add) {
                    NookDesignChipLabel(text: lang.t("nook.design.add.button"), isOn: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .buttonStyle(.plain)
                .help(lang.t("nook.design.links.add.help"))
            }
        }
        .onChange(of: text) { _, typed in kit.nook?.setDraft(.designLink, isUnsaved: NookDraft.isUnsaved(typed)) }
        .onDisappear { kit.nook?.setDraft(.designLink, isUnsaved: false) }
    }

    /// A link that was added, or was there already, empties the field. One
    /// that was refused stays, which leaves it to be fixed.
    private func add() {
        switch kit.addLink(text: text) {
        case .added, .duplicate:
            text = ""
        case .refused, .full, .nothingToPaste, .notAllowed, .unavailable:
            break
        }
    }
}

// MARK: - Asking for a name

/// The field a link's name, a new collection's name or a collection's new
/// name is typed into. Return keeps it and Escape leaves it as it was.
private struct NookDesignLinkNameRow: View {
    var kit: NookDesignKit
    let naming: NookDesignLinkNaming
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        let lang = LanguageManager.shared
        HStack(spacing: 6) {
            NookDesignField(text: $text, prompt: lang.t(promptKey), onSubmit: commit)
                .focused($isFocused)
                .onKeyPress(.escape) {
                    kit.cancelNaming()
                    return .handled
                }
            Button(action: commit) {
                NookDesignChipLabel(text: lang.t("nook.design.action.done"), isOn: true)
            }
            .buttonStyle(.plain)
        }
        .onAppear {
            text = kit.namingSeed(for: naming)
            isFocused = true
        }
        .onChange(of: text) { _, typed in
            kit.nook?.setDraft(.designLinkName, isUnsaved: NookDesignNames.isUnsaved(typed, saved: kit.namingSeed(for: naming), limit: NookDesignLinkRules.maxNameLength))
        }
        .onDisappear { kit.nook?.setDraft(.designLinkName, isUnsaved: false) }
    }

    private var promptKey: String {
        switch naming {
        case .renamingLink: "nook.design.links.namePrompt"
        case .newCollection, .renamingCollection: "nook.design.links.collectionPrompt"
        }
    }

    private func commit() {
        if kit.commitNaming(text) { kit.nook?.setDraft(.designLinkName, isUnsaved: false) }
    }
}
