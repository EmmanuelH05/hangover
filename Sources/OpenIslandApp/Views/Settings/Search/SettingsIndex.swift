import SwiftUI

/// One setting as the search finds it (D84, S2): where it lives and the
/// keys of the words it is matched on. A row that can be found marks
/// itself with `.settingsAnchor(entry)`; `SettingsIndexTests` holds the
/// index and the anchors together, which is how a new setting joins by
/// declaring one entry and anchoring its row.
struct SettingsEntry: Identifiable, Hashable, Sendable {
    /// Dotted and stable: `general.launchAtLogin`, `nook.todo.app.asana`.
    let id: String
    let tab: SettingsTab
    /// The name key of the sub-page the setting lives on, such as the
    /// Personalization sub-pages, nil for the tab's own pane.
    let subpage: String?
    let titleKey: String
    let descriptionKey: String?
    /// True when the row only shows while the agents switch is on (D41).
    let needsAgents: Bool

    init(_ id: String, tab: SettingsTab, subpage: String? = nil, title: String, description: String? = nil, needsAgents: Bool = false) {
        self.id = id
        self.tab = tab
        self.subpage = subpage
        titleKey = title
        descriptionKey = description
        self.needsAgents = needsAgents
    }
}

/// Every setting the search knows, one static array per tab, assembled
/// here. The arrays are filled from the panes.
enum SettingsIndex {
    /// Every entry, whether or not its row is on offer right now.
    static let all: [SettingsEntry] = general + setup + display + sound + appearance + nook + watch + about

    private static let byID: [String: SettingsEntry] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    /// The entries the search reads: everything but the rows of a widget
    /// this copy does not offer (Link to MP3 lives in the dev copy, D64).
    static var entries: [SettingsEntry] {
        NookLinkAudioOffer.isOffered ? all : all.filter { !$0.id.hasPrefix("nook.linkAudio.") && $0.id != "nook.widget.linkAudio" }
    }

    /// The row to scroll to when an entry's own row is not on screen: a
    /// setting under a switch that is off, or a setup row of an app that
    /// is not on, scrolls to the row that holds it. The entry's own row
    /// still wins when it is there.
    static let fallbacks: [String: String] = [
        "appearance.glow.single": "appearance.glow", "appearance.glow.reset": "appearance.glow",
        "appearance.glow.status": "appearance.glow", "appearance.glow.question": "appearance.glow",
        "appearance.glow.completed": "appearance.glow", "appearance.glow.running": "appearance.glow",
        "appearance.glow.notice": "appearance.glow", "appearance.glow.music": "appearance.glow",
        "appearance.glow.followsMusic": "appearance.glow", "appearance.glow.beat": "appearance.glow",
        "appearance.glow.beatLook": "appearance.glow.beat", "appearance.glow.laserMode": "appearance.glow.beat",
        "appearance.glow.reach": "appearance.glow.beat", "appearance.glow.laserReach": "appearance.glow.beat",
        "appearance.glow.laserCount": "appearance.glow.beat",
        "appearance.closedMusic.reclaim": "appearance.closedMusic", "appearance.closedMusic.dot": "appearance.closedMusic",
        "appearance.closedMusic.track": "appearance.closedMusic", "appearance.closedMusic.nextEvent": "appearance.closedMusic",
        "appearance.closedMusic.notices": "appearance.closedMusic",
        "watch.pairingCode": "watch.notifications", "watch.refreshCode": "watch.notifications",
        "watch.revoke": "watch.notifications",
        "nook.todo.reminders.list": "nook.todo.app.reminders",
        "nook.todo.notion.token": "nook.todo.app.notion", "nook.todo.notion.database": "nook.todo.app.notion",
        "nook.todo.ticktick.token": "nook.todo.app.ticktick", "nook.todo.ticktick.list": "nook.todo.app.ticktick",
        "nook.todo.asana.token": "nook.todo.app.asana", "nook.todo.asana.workspace": "nook.todo.app.asana",
        "nook.todo.monday.token": "nook.todo.app.monday", "nook.todo.monday.board": "nook.todo.app.monday",
        "nook.todo.canvas.host": "nook.todo.app.canvas", "nook.todo.canvas.token": "nook.todo.app.canvas",
        "nook.todo.remind": "nook.widget.todo", "nook.notes.folder": "nook.notes.saveTo",
        "nook.notes.saveTo": "nook.widget.notes", "nook.notes.hotkey": "nook.widget.notes",
        "nook.calendar.nextUp": "nook.widget.calendar",
        "nook.nowPlaying.gif": "nook.widget.media", "nook.nowPlaying.visualizer": "nook.widget.media",
        "nook.nowPlaying.scale": "nook.widget.media", "nook.nowPlaying.offsetX": "nook.widget.media",
        "nook.nowPlaying.offsetY": "nook.widget.media",
        "nook.tray.clipboard": "nook.widget.tray", "nook.tray.revealFolder": "nook.widget.tray",
        "nook.tray.clear": "nook.widget.tray",
        "nook.timer.length": "nook.widget.timer", "nook.timer.sound": "nook.widget.timer",
        "nook.timer.pomodoro.work": "nook.widget.timer", "nook.timer.pomodoro.shortBreak": "nook.widget.timer",
        "nook.timer.pomodoro.longBreak": "nook.widget.timer", "nook.timer.pomodoro.rounds": "nook.widget.timer",
        "nook.mirror.camera": "nook.widget.mirror", "nook.mirror.clearDecorations": "nook.widget.mirror",
        "nook.photoBooth.caption": "nook.widget.mirror", "nook.photoBooth.countdown": "nook.widget.mirror",
        "nook.photoBooth.sound": "nook.widget.mirror", "nook.photoBooth.folder": "nook.widget.mirror",
        "nook.photoBooth.layout": "nook.widget.mirror", "nook.photoBooth.theme": "nook.widget.mirror",
        "nook.weather.city": "nook.widget.weather", "nook.weather.unit": "nook.widget.weather",
        "nook.design.format": "nook.widget.design", "nook.design.savePicks": "nook.widget.design",
        "nook.design.keepPicking": "nook.widget.design", "nook.design.hotkey": "nook.widget.design",
        "nook.design.openEditor": "nook.widget.design", "nook.design.revealFolder": "nook.widget.design",
        "nook.design.clearReferences": "nook.widget.design",
        "nook.record.includeIsland": "nook.widget.record", "nook.record.hotkey": "nook.widget.record",
        "nook.record.openFolder": "nook.widget.record",
        "nook.linkAudio.folder": "nook.widget.linkAudio", "nook.linkAudio.findKey": "nook.widget.linkAudio",
    ]

    static let general: [SettingsEntry] = [
        .init("general.agents", tab: .general, title: "settings.general.agents.toggle", description: "settings.general.agents.note"),
        .init("general.launchAtLogin", tab: .general, title: "settings.general.launchAtLogin"),
        .init("general.monitor", tab: .general, title: "settings.general.monitor"),
        .init("general.language", tab: .general, title: "settings.general.language"),
        .init("general.keepOpenUntilDecision", tab: .general, title: "settings.general.keepOpenUntilDecision", needsAgents: true),
        .init("general.showDockIcon", tab: .general, title: "settings.general.showDockIcon"),
        .init("general.linksFromOtherApps", tab: .general, title: "settings.general.linksFromOtherApps", description: "settings.general.linksFromOtherApps.note"),
        .init("general.openTrigger", tab: .general, title: "settings.general.openTrigger", description: "settings.general.openTrigger.files"),
        .init("general.swipeGestures", tab: .general, title: "settings.general.swipeGestures", description: "onboarding.tips.swipeAway.text"),
        .init("general.hapticFeedback", tab: .general, title: "settings.general.hapticFeedback"),
        .init("general.completionReply", tab: .general, title: "settings.general.completionReply", needsAgents: true),
        .init("general.suppressFrontmostNotifications", tab: .general, title: "settings.general.suppressFrontmostNotifications", needsAgents: true),
        .init("general.agentHotkeys", tab: .general, title: "settings.general.agentHotkeys", description: "settings.general.agentHotkeys.note", needsAgents: true),
        .init("general.agentHotkeys.approve", tab: .general, title: "settings.general.agentHotkeys.approve", needsAgents: true),
        .init("general.agentHotkeys.deny", tab: .general, title: "settings.general.agentHotkeys.deny", needsAgents: true),
        .init("general.agentHotkeys.reset", tab: .general, title: "settings.general.agentHotkeys.reset", needsAgents: true),
    ]

    static let setup: [SettingsEntry] = [
        .init("setup.claudeConfigDir", tab: .setup, title: "setup.claudeConfigDir.title", description: "setup.claudeConfigDir.footer"),
        .init("setup.hooks", tab: .setup, title: "setup.section.hooks"),
        .init("setup.usageBridge", tab: .setup, title: "setup.usageBridge"),
        .init("setup.showCodexUsage", tab: .setup, title: "settings.general.showCodexUsage"),
        .init("setup.permissions", tab: .setup, title: "setup.permissionsTitle", description: "setup.permissionsDesc"),
        .init("setup.diagnostics", tab: .setup, title: "setup.section.diagnostics"),
        .init("setup.remote", tab: .setup, title: "setup.remote.title", description: "setup.remote.note"),
        .init("setup.installAll", tab: .setup, title: "setup.installAll"),
    ]

    static let display: [SettingsEntry] = [
        .init("display.position", tab: .display, title: "settings.display.position"),
    ]

    static let sound: [SettingsEntry] = [
        .init("sound.mute", tab: .sound, title: "settings.sound.mute"),
        .init("sound.select", tab: .sound, title: "settings.sound.selectSound", needsAgents: true),
    ]

    static let appearance: [SettingsEntry] = [
        .init("appearance.profile", tab: .appearance, title: "settings.appearance.profile.title", description: "settings.appearance.profile.note"),
        .init("appearance.templates", tab: .appearance, title: "settings.appearance.templates.title", description: "settings.appearance.templates.note"),
        .init("appearance.rightSlot", tab: .appearance, title: "settings.appearance.rightSlot.title", description: "settings.appearance.rightSlot.note"),
        .init("appearance.centerLabel", tab: .appearance, title: "settings.appearance.centerLabel.title", description: "settings.appearance.centerLabel.note", needsAgents: true),
        .init("appearance.leftSlot", tab: .appearance, title: "settings.appearance.nook.leftSlot.title", description: "settings.appearance.nook.leftSlot.note"),
        .init("appearance.closedMusic", tab: .appearance, title: "settings.appearance.nook.closed.title", description: "settings.appearance.nook.closed.note"),
        .init("appearance.closedMusic.reclaim", tab: .appearance, title: "settings.appearance.nook.reclaim.title", description: "settings.appearance.nook.reclaim.note", needsAgents: true),
        .init("appearance.closedMusic.dot", tab: .appearance, title: "settings.appearance.nook.dot.title", description: "settings.appearance.nook.dot.note", needsAgents: true),
        .init("appearance.closedMusic.track", tab: .appearance, title: "settings.appearance.nook.track.title", description: "settings.appearance.nook.track.note"),
        .init("appearance.closedMusic.nextEvent", tab: .appearance, title: "settings.appearance.nook.nextEvent.title", description: "settings.appearance.nook.nextEvent.note"),
        .init("appearance.closedMusic.notices", tab: .appearance, title: "settings.appearance.nook.notices.title", description: "settings.appearance.nook.notices.note"),
        .init("appearance.glow", tab: .appearance, title: "settings.appearance.nook.halo.title", description: "settings.appearance.nook.halo.note"),
        .init("appearance.glow.single", tab: .appearance, title: "settings.appearance.nook.halo.single.title", description: "settings.appearance.nook.halo.single.note"),
        .init("appearance.glow.reset", tab: .appearance, title: "settings.appearance.nook.halo.reset"),
        .init("appearance.glow.status", tab: .appearance, title: "settings.appearance.nook.halo.moment.approval", needsAgents: true),
        .init("appearance.glow.question", tab: .appearance, title: "settings.appearance.nook.halo.moment.question", needsAgents: true),
        .init("appearance.glow.completed", tab: .appearance, title: "settings.appearance.nook.halo.moment.completed", needsAgents: true),
        .init("appearance.glow.running", tab: .appearance, title: "settings.appearance.nook.halo.moment.running", needsAgents: true),
        .init("appearance.glow.notice", tab: .appearance, title: "settings.appearance.nook.halo.moment.notice", description: "settings.appearance.nook.halo.notice.own"),
        .init("appearance.glow.music", tab: .appearance, title: "settings.appearance.nook.halo.moment.music", description: "settings.appearance.nook.halo.music.artwork"),
        .init("appearance.glow.followsMusic", tab: .appearance, title: "settings.appearance.nook.halo.music.title", description: "settings.appearance.nook.halo.music.note"),
        .init("appearance.glow.beat", tab: .appearance, title: "settings.appearance.nook.halo.beat.title", description: "settings.appearance.nook.halo.beat.note"),
        .init("appearance.glow.beatLook", tab: .appearance, title: "settings.appearance.nook.halo.beat.look"),
        .init("appearance.glow.laserMode", tab: .appearance, title: "settings.appearance.nook.halo.beat.mode"),
        .init("appearance.glow.reach", tab: .appearance, title: "settings.appearance.nook.halo.beat.reach"),
        .init("appearance.glow.laserReach", tab: .appearance, title: "settings.appearance.nook.halo.beat.laserReach"),
        .init("appearance.glow.laserCount", tab: .appearance, title: "settings.appearance.nook.halo.beat.laserCount"),
        .init("appearance.accent", tab: .appearance, title: "settings.appearance.accent.title", description: "settings.appearance.accent.note"),
        .init("appearance.openedLook", tab: .appearance, title: "settings.appearance.openedLook.title", description: "settings.appearance.openedLook.note"),
        .init("appearance.usageDisplay", tab: .appearance, title: "settings.appearance.usageDisplay.title", description: "settings.appearance.usageDisplay.note", needsAgents: true),
        .init("appearance.stateIndicator", tab: .appearance, title: "settings.appearance.stateIndicator.title", description: "settings.appearance.stateIndicator.note", needsAgents: true),
        .init("appearance.sessionGroup", tab: .appearance, title: "settings.appearance.sessionGroup.title", description: "settings.appearance.sessionGroup.note", needsAgents: true),
        .init("appearance.sessionSort", tab: .appearance, title: "settings.appearance.sessionSort.title", description: "settings.appearance.sessionSort.note", needsAgents: true),
        .init("appearance.staleThreshold", tab: .appearance, title: "settings.appearance.staleThreshold.title", description: "settings.appearance.staleThreshold.note", needsAgents: true),
        .init("appearance.openedPage", tab: .appearance, title: "settings.appearance.nook.opened.title", description: "settings.appearance.nook.opened.note", needsAgents: true),
        .init("appearance.compactBar", tab: .appearance, title: "settings.appearance.nook.compactBar.title", description: "settings.appearance.nook.compactBar.note", needsAgents: true),
        .init("appearance.agentsBar", tab: .appearance, title: "settings.appearance.nook.agentsBar.title", description: "settings.appearance.nook.agentsBar.note", needsAgents: true),
        .init("appearance.widgets", tab: .appearance, title: "settings.appearance.nook.widgets.title", description: "settings.appearance.nook.widgets.note"),
        .init("appearance.calendarStyle", tab: .appearance, title: "settings.appearance.nook.calendarStyle.title", description: "settings.appearance.nook.calendarStyle.note"),
        .init("appearance.calendars", tab: .appearance, title: "settings.appearance.nook.calendars.title", description: "settings.appearance.nook.calendars.note"),
    ]

    static let nook: [SettingsEntry] = [
        .init("nook.widget.media", tab: .nook, title: "settings.nook.widget.media"),
        .init("nook.widget.calendar", tab: .nook, title: "settings.nook.widget.calendar"),
        .init("nook.widget.todo", tab: .nook, title: "settings.nook.widget.todo"),
        .init("nook.widget.notes", tab: .nook, title: "settings.nook.widget.notes"),
        .init("nook.widget.tray", tab: .nook, title: "settings.nook.widget.tray"),
        .init("nook.widget.timer", tab: .nook, title: "settings.nook.widget.timer"),
        .init("nook.widget.mirror", tab: .nook, title: "settings.nook.widget.mirror"),
        .init("nook.widget.weather", tab: .nook, title: "nook.weather.title"),
        .init("nook.widget.record", tab: .nook, title: "nook.record.title"),
        .init("nook.widget.design", tab: .nook, title: "nook.design.title"),
        .init("nook.widget.linkAudio", tab: .nook, title: "nook.linkAudio.title"),
        .init("nook.arrange", tab: .nook, title: "settings.nook.arrange.title", description: "settings.nook.arrange.note"),
        .init("nook.perDisplay", tab: .nook, title: "settings.nook.perDisplay.title", description: "settings.nook.perDisplay.note", needsAgents: true),
        .init("nook.focusSuppressesCompletions", tab: .nook, title: "settings.nook.focusSuppresses.title", needsAgents: true),
        .init("nook.meetingSuppressesCompletions", tab: .nook, title: "settings.nook.meetingSuppresses.title", description: "settings.nook.meetingSuppresses.note", needsAgents: true),
        .init("nook.nowPlaying.gif", tab: .nook, title: "settings.nook.gif.choose"),
        .init("nook.nowPlaying.visualizer", tab: .nook, title: "settings.nook.gif.visualizer"),
        .init("nook.nowPlaying.scale", tab: .nook, title: "settings.nook.gif.scale"),
        .init("nook.nowPlaying.offsetX", tab: .nook, title: "settings.nook.gif.offsetX"),
        .init("nook.nowPlaying.offsetY", tab: .nook, title: "settings.nook.gif.offsetY"),
        .init("nook.calendar.nextUp", tab: .nook, title: "nook.calendar.settings.nextUp"),
        .init("nook.todo.remind", tab: .nook, title: "nook.todo.due.remind", description: "nook.todo.due.remind.note"),
        .init("nook.todo.app.reminders", tab: .nook, title: "nook.todo.source.reminders", description: "nook.todo.source.reminders.subtitle"),
        .init("nook.todo.app.notion", tab: .nook, title: "nook.todo.source.notion", description: "nook.todo.source.notion.subtitle"),
        .init("nook.todo.app.ticktick", tab: .nook, title: "nook.todo.source.ticktick", description: "nook.todo.source.ticktick.subtitle"),
        .init("nook.todo.app.asana", tab: .nook, title: "nook.todo.source.asana", description: "nook.todo.source.asana.subtitle"),
        .init("nook.todo.app.monday", tab: .nook, title: "nook.todo.source.monday", description: "nook.todo.source.monday.subtitle"),
        .init("nook.todo.app.canvas", tab: .nook, title: "nook.todo.source.canvas", description: "nook.todo.source.canvas.subtitle"),
        .init("nook.todo.reminders.list", tab: .nook, title: "nook.todo.reminders.list"),
        .init("nook.todo.notion.token", tab: .nook, title: "nook.todo.notion.token.placeholder", description: "nook.todo.notion.token.help"),
        .init("nook.todo.notion.database", tab: .nook, title: "nook.todo.notion.database"),
        .init("nook.todo.ticktick.token", tab: .nook, title: "nook.todo.ticktick.token.placeholder", description: "nook.todo.ticktick.token.help"),
        .init("nook.todo.ticktick.list", tab: .nook, title: "nook.todo.ticktick.list"),
        .init("nook.todo.asana.token", tab: .nook, title: "nook.todo.asana.token.label"),
        .init("nook.todo.asana.workspace", tab: .nook, title: "nook.todo.asana.place.label", description: "nook.todo.asana.scope"),
        .init("nook.todo.monday.token", tab: .nook, title: "nook.todo.monday.token.label"),
        .init("nook.todo.monday.board", tab: .nook, title: "nook.todo.monday.place.label", description: "nook.todo.monday.scope"),
        .init("nook.todo.canvas.host", tab: .nook, title: "nook.todo.canvas.host.label"),
        .init("nook.todo.canvas.token", tab: .nook, title: "nook.todo.canvas.token.label"),
        .init("nook.notes.saveTo", tab: .nook, title: "nook.notes.settings.saveTo"),
        .init("nook.notes.folder", tab: .nook, title: "nook.notes.settings.folder", description: "nook.notes.settings.folder.note"),
        .init("nook.notes.hotkey", tab: .nook, title: "nook.notes.settings.hotkey", description: "nook.notes.settings.hotkey.note"),
        .init("nook.tray.clipboard", tab: .nook, title: "nook.tray.settings.clipboard", description: "nook.tray.settings.clipboard.note"),
        .init("nook.tray.revealFolder", tab: .nook, title: "nook.tray.settings.revealFolder"),
        .init("nook.tray.clear", tab: .nook, title: "nook.tray.settings.clear"),
        .init("nook.timer.length", tab: .nook, title: "nook.timer.settings.length"),
        .init("nook.timer.sound", tab: .nook, title: "nook.timer.settings.sound"),
        .init("nook.timer.pomodoro.work", tab: .nook, title: "nook.timer.pomodoro.settings.work", description: "nook.timer.pomodoro.settings.note"),
        .init("nook.timer.pomodoro.shortBreak", tab: .nook, title: "nook.timer.pomodoro.settings.shortBreak"),
        .init("nook.timer.pomodoro.longBreak", tab: .nook, title: "nook.timer.pomodoro.settings.longBreak"),
        .init("nook.timer.pomodoro.rounds", tab: .nook, title: "nook.timer.pomodoro.settings.rounds"),
        .init("nook.mirror.camera", tab: .nook, title: "nook.mirror.settings.camera", description: "nook.mirror.settings.note"),
        .init("nook.mirror.clearDecorations", tab: .nook, title: "nook.mirror.decorations.settings.clear"),
        .init("nook.photoBooth.caption", tab: .nook, title: "nook.photoBooth.settings.caption"),
        .init("nook.photoBooth.countdown", tab: .nook, title: "nook.photoBooth.settings.countdown"),
        .init("nook.photoBooth.sound", tab: .nook, title: "nook.photoBooth.settings.sound"),
        .init("nook.photoBooth.folder", tab: .nook, title: "nook.photoBooth.settings.folder", description: "nook.photoBooth.settings.note"),
        .init("nook.photoBooth.layout", tab: .nook, title: "nook.photoBooth.settings.layout"),
        .init("nook.photoBooth.theme", tab: .nook, title: "nook.photoBooth.settings.theme"),
        .init("nook.weather.city", tab: .nook, title: "nook.weather.settings.city", description: "nook.weather.settings.privacy"),
        .init("nook.weather.unit", tab: .nook, title: "nook.weather.settings.unit"),
        .init("nook.design.format", tab: .nook, title: "nook.design.settings.format"),
        .init("nook.design.savePicks", tab: .nook, title: "nook.design.settings.savePicks", description: "nook.design.settings.savePicks.note"),
        .init("nook.design.keepPicking", tab: .nook, title: "nook.design.settings.keepPicking", description: "nook.design.settings.keepPicking.note"),
        .init("nook.design.hotkey", tab: .nook, title: "nook.design.settings.hotkey", description: "nook.design.settings.hotkey.note"),
        .init("nook.design.openEditor", tab: .nook, title: "nook.design.settings.openEditor"),
        .init("nook.design.revealFolder", tab: .nook, title: "nook.design.settings.revealFolder"),
        .init("nook.design.clearReferences", tab: .nook, title: "nook.design.settings.clearReferences"),
        .init("nook.record.includeIsland", tab: .nook, title: "nook.record.settings.includeIsland", description: "nook.record.settings.includeIsland.note"),
        .init("nook.record.hotkey", tab: .nook, title: "nook.record.settings.hotkey", description: "nook.record.settings.hotkey.note"),
        .init("nook.record.openFolder", tab: .nook, title: "nook.record.settings.openFolder", description: "nook.record.settings.folder.note"),
        .init("nook.linkAudio.folder", tab: .nook, title: "nook.linkAudio.settings.folder", description: "nook.linkAudio.settings.caption"),
        .init("nook.linkAudio.findKey", tab: .nook, title: "nook.linkAudio.settings.findKey", description: "nook.linkAudio.settings.findKeyCaption"),
        .init("nook.power.notices", tab: .nook, title: "nook.power.settings.notices"),
        .init("nook.power.test", tab: .nook, title: "nook.power.settings.test"),
        .init("nook.volume.notice", tab: .nook, title: "nook.volume.settings.notice"),
        .init("nook.volume.test", tab: .nook, title: "nook.volume.settings.test"),
        .init("nook.volume.keys", tab: .nook, title: "nook.volume.settings.keys", description: "nook.volume.settings.keys.note"),
    ]

    static let watch: [SettingsEntry] = [
        .init("watch.notifications", tab: .watch, title: "settings.watch.notifications.title", description: "settings.watch.notifications.note"),
        .init("watch.pairingCode", tab: .watch, title: "settings.watch.pairingCode.title", description: "settings.watch.pairingCode.note"),
        .init("watch.refreshCode", tab: .watch, title: "settings.watch.refreshCode"),
        .init("watch.revoke", tab: .watch, title: "settings.watch.revoke"),
    ]

    static let about: [SettingsEntry] = [
        .init("about.checkForUpdates", tab: .about, title: "settings.about.checkForUpdates"),
        .init("about.installAutomatically", tab: .about, title: "settings.about.installAutomatically", description: "settings.about.installAutomatically.description"),
        .init("about.showWelcomeTour", tab: .about, title: "onboarding.settings.show"),
        .init("about.sendFeedback", tab: .about, title: "feedback.button"),
        .init("about.sourceCode", tab: .about, title: "settings.about.sourceCode"),
        .init("about.license", tab: .about, title: "settings.about.license"),
        .init("about.upstream", tab: .about, title: "settings.about.upstream"),
        .init("about.quitApp", tab: .about, title: "settings.about.quitApp"),
    ]

    static func entry(_ id: String) -> SettingsEntry? {
        byID[id]
    }
}

// MARK: - Jumping to a setting

/// A result that was opened: the pane scrolls to the entry and outlines
/// it for a moment (S5).
struct SettingsJump: Equatable, Sendable {
    let entry: SettingsEntry
    let at: Date

    /// How long the outline stays.
    static let highlightDuration: TimeInterval = 2
}

private struct SettingsJumpKey: EnvironmentKey {
    static let defaultValue: SettingsJump? = nil
}

extension EnvironmentValues {
    /// The result just opened, for the pane that holds it.
    var settingsJump: SettingsJump? {
        get { self[SettingsJumpKey.self] }
        set { self[SettingsJumpKey.self] = newValue }
    }
}

/// Marks a row as the one an entry stands for: gives it the entry's id to
/// scroll to and draws the paper outline while a jump names it.
private struct SettingsAnchorModifier: ViewModifier {
    let entry: SettingsEntry
    @Environment(\.settingsJump) private var jump
    @State private var isHighlighted = false

    func body(content: Content) -> some View {
        content
            .id(entry.id)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(V6Palette.paper, lineWidth: 1.5)
                    .padding(-4)
                    .opacity(isHighlighted ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .onChange(of: jump, initial: true) { _, jump in
                guard let jump, jump.entry.id == entry.id,
                      Date().timeIntervalSince(jump.at) < SettingsJump.highlightDuration else {
                    isHighlighted = false
                    return
                }
                isHighlighted = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(SettingsJump.highlightDuration))
                    withAnimation(.easeOut(duration: 0.4)) { isHighlighted = false }
                }
            }
    }
}

/// Scrolls the pane to the entry a jump names, once the pane has laid out.
private struct SettingsScrollsToJumpModifier: ViewModifier {
    @Environment(\.settingsJump) private var jump
    let proxy: ScrollViewProxy

    /// The form lays its rows out a moment after the tab is shown.
    private static let delay: Duration = .milliseconds(250)

    func body(content: Content) -> some View {
        content
            .task(id: jump) {
                // A pane shown again later must not go back to an old
                // jump; only a fresh one scrolls.
                guard let jump, Date().timeIntervalSince(jump.at) < SettingsJump.highlightDuration else { return }
                try? await Task.sleep(for: Self.delay)
                guard !Task.isCancelled else { return }
                withAnimation {
                    // The row that holds the setting first, then the
                    // setting's own row, which wins when it is on screen
                    // and is a no-op when it is not.
                    if let fallback = SettingsIndex.fallbacks[jump.entry.id] {
                        proxy.scrollTo(fallback, anchor: .center)
                    }
                    proxy.scrollTo(jump.entry.id, anchor: .center)
                }
            }
    }
}

extension View {
    /// The row a search result opens: scrolled to and outlined (S5).
    func settingsAnchor(_ entry: SettingsEntry) -> some View {
        modifier(SettingsAnchorModifier(entry: entry))
    }

    /// On a pane's `Form` inside a `ScrollViewReader`: follows a jump to
    /// one of the pane's anchors.
    func settingsScrollsToJump(_ proxy: ScrollViewProxy) -> some View {
        modifier(SettingsScrollsToJumpModifier(proxy: proxy))
    }
}
