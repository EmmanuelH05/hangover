import Foundation

/// Personalization templates on the live models. The rules are pure
/// functions of `PersonalizationSetup`; this only copies one display's setup
/// out of the models and back.
extension AppModel {
    /// The template this display's setup equals right now, if any.
    func appliedTemplateID(for profile: IslandAppearanceDisplayProfile) -> PersonalizationTemplate.ID? {
        personalizationSetup(for: profile).appliedTemplateID
    }

    /// Replaces this display's Personalization setup with `template` and
    /// keeps what was there for `undoTemplate(for:)`.
    func applyTemplate(_ template: PersonalizationTemplate, for profile: IslandAppearanceDisplayProfile) {
        let applied = personalizationSetup(for: profile).applying(template, keeping: templateUndo[profile])
        adopt(applied.setup, for: profile)
        templateUndo[profile] = applied.undo
    }

    /// True while this display sits on a template and an earlier setup is
    /// held for it. The link hides once the user changes anything, because
    /// the setup on screen is then their own.
    func canUndoTemplate(for profile: IslandAppearanceDisplayProfile) -> Bool {
        templateUndo[profile] != nil && appliedTemplateID(for: profile) != nil
    }

    /// Puts back the setup this display had before its template.
    func undoTemplate(for profile: IslandAppearanceDisplayProfile) {
        guard canUndoTemplate(for: profile), let undo = templateUndo[profile] else { return }
        adopt(personalizationSetup(for: profile).undoing(undo), for: profile)
        templateUndo[profile] = nil
    }

    /// Widgets of this display's template that are switched off in the Nook
    /// tab and therefore missing from its page. Empty off a template.
    func templateWidgetsSwitchedOff(for profile: IslandAppearanceDisplayProfile) -> [NookWidgetKind] {
        guard let id = appliedTemplateID(for: profile),
              let template = PersonalizationTemplate.all.first(where: { $0.id == id }) else { return [] }
        return template.widgetsSwitchedOff(enabled: nook.enabledWidgets)
    }

    /// What this display would be with `template` on it. Nothing is applied.
    func templateSetup(
        _ template: PersonalizationTemplate,
        for profile: IslandAppearanceDisplayProfile
    ) -> PersonalizationSetup {
        personalizationSetup(for: profile).applying(template, keeping: nil).setup
    }

    /// This display's setup right now.
    func personalizationSetup(for profile: IslandAppearanceDisplayProfile) -> PersonalizationSetup {
        PersonalizationSetup(
            appearance: appearancePreferences(for: profile),
            nook: nook.displayPreferences(for: profile)
        )
    }

    /// Writes a setup back. Each model skips the write when nothing changed
    /// and saves only the fields that did.
    private func adopt(_ setup: PersonalizationSetup, for profile: IslandAppearanceDisplayProfile) {
        nook.updateDisplayPreferences(for: profile) { $0 = setup.nook }
        updateAppearancePreferences(for: profile) { $0 = setup.appearance }
    }
}
