import Foundation

/// Editing the Nook page layout for one display profile. The island's edit
/// mode passes the active profile; the Personalization editor passes the
/// profile being edited there.
extension NookModel {
    /// Widgets on the page for this profile, in order, with sizes.
    func widgetPlacements(for profile: IslandAppearanceDisplayProfile) -> [NookWidgetPlacement] {
        displayPreferences(for: profile).placements(enabled: enabledWidgets)
    }

    /// Widgets that could be added on this profile: switched off in the
    /// Nook tab or hidden on this display.
    func addableWidgets(for profile: IslandAppearanceDisplayProfile) -> [NookWidgetKind] {
        let shown = Set(widgetPlacements(for: profile).map(\.kind))
        return NookWidgetKind.allCases.filter { !shown.contains($0) }
    }

    /// Moves a widget to `index` among the widgets on the page. Widgets not
    /// on the page keep their relative order after the visible ones.
    func moveWidget(_ kind: NookWidgetKind, to index: Int, for profile: IslandAppearanceDisplayProfile) {
        let visible = widgetPlacements(for: profile).map(\.kind)
        guard visible.contains(kind) else { return }
        let reordered = NookWidgetLayout.moving(kind, to: index, in: visible)
        guard reordered != visible else { return }
        updateDisplayPreferences(for: profile) { preferences in
            let rest = preferences.normalizedWidgetOrder.filter { !reordered.contains($0) }
            preferences.widgetOrder = reordered + rest
        }
    }

    func setWidgetSize(_ kind: NookWidgetKind, _ size: NookWidgetSize, for profile: IslandAppearanceDisplayProfile) {
        updateDisplayPreferences(for: profile) { preferences in
            preferences.widgetSizes[kind] = size == .medium ? nil : size
        }
    }

    /// Takes a widget off this display's page. The Nook tab switch stays
    /// on, so other displays keep it.
    func hideWidget(_ kind: NookWidgetKind, for profile: IslandAppearanceDisplayProfile) {
        updateDisplayPreferences(for: profile) { preferences in
            preferences.hiddenWidgets.insert(kind)
        }
    }

    /// Puts a widget on this display's page at `index` (the end when nil).
    /// A widget that was off in the Nook tab is switched on there and
    /// hidden on the other displays, which keeps the add per display.
    func addWidget(_ kind: NookWidgetKind, at index: Int? = nil, for profile: IslandAppearanceDisplayProfile) {
        if !isWidgetEnabled(kind) {
            for other in IslandAppearanceDisplayProfile.allCases where other != profile {
                updateDisplayPreferences(for: other) { $0.hiddenWidgets.insert(kind) }
            }
            setWidget(kind, enabled: true)
        }
        updateDisplayPreferences(for: profile) { preferences in
            preferences.hiddenWidgets.remove(kind)
        }
        let count = widgetPlacements(for: profile).count
        moveWidget(kind, to: index ?? count, for: profile)
    }
}

extension NookModel {
    /// Puts this display's widget order and sizes back to the defaults.
    /// Hidden widgets stay hidden.
    func resetWidgetLayout(for profile: IslandAppearanceDisplayProfile) {
        updateDisplayPreferences(for: profile) { preferences in
            preferences.widgetOrder = NookWidgetKind.allCases
            preferences.widgetSizes = [:]
        }
    }
}
