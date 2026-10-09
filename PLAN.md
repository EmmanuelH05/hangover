# Nook build plan

Open Island is a native macOS notch app for AI coding agents. This fork (branch `nook`) adds the features of NotchNook, a defunct paid notch app, for one user. Everything here is personal-use, GPL-3.0 like upstream.

Read `DECISIONS.md` next to this file before writing anything. It fixes every boundary between tasks.

## How the Nook is wired (already built, do not change)

- `Sources/OpenIslandApp/Nook/NookModel.swift` owns preferences, the widget registry and one service per widget: `media`, `calendar`, `reminders`, `notes`, `tray`, `timer`, `power`. `NookModel.start()` calls each service's `start(nook:)` once at app launch. `AppModel.nook` is the single instance.
- The opened island has two pages: the upstream agent list and the Nook page (`Nook/Views/NookPanelView.swift`). The Nook page stacks one card per entry in `nook.enabledWidgets`, in order, each at its card's `static let height`. The window height is computed from those heights before layout, which is why heights are static.
- The closed notch has two "wings" next to the physical notch. `NookModel.closedActivity` decides what they show, in priority order: a transient notice (`showTransient`), then a running timer (`timer.closedText`), then music (album art + GIF). Widgets never draw on the closed notch directly; they call `nook.showTransient(...)` or expose `closedText`.
- Settings → Nook (`Nook/Views/NookSettingsPane.swift`) is a `Form`. It renders each widget's settings view, which must be one or more `Section`s.
- The media widget is finished (`Nook/Media/`, `Nook/Views/NookMediaViews.swift`). Use `NookMediaCard` as the reference for card style: `NookCardBackground()` behind, `NookCardHeader` on top when the card lists things, white text at 0.85 / 0.6 / 0.35 opacity for primary / secondary / muted, 14pt horizontal and 12pt vertical padding, `.frame(maxWidth: .infinity)`.

## Rules for every task

- You own exactly one folder: `Sources/OpenIslandApp/Nook/Widgets/<Name>/`. Replace the stub files there. You may add files inside that folder. Do not edit any file outside it.
- Keep every type name and member listed in `DECISIONS.md` for your widget. Other code already calls them.
- Swift 6.2 strict concurrency. Services are `@MainActor @Observable final class`. Anything crossing from a callback or background queue to the main actor must be `Sendable` (use value types) and hop with `Task { @MainActor in ... }`.
- Native Apple frameworks only (EventKit, AVFoundation, IOKit, CoreAudio, AppKit, SwiftUI). No new package dependencies. No Python.
- No telemetry, no network calls, no cloud. Local-first.
- Permission prompts: the dev app's Info.plist already has `NSCameraUsageDescription`, `NSCalendarsFullAccessUsageDescription`, `NSRemindersFullAccessUsageDescription`. Request access with the macOS 14 APIs (`requestFullAccessToEvents`, `requestFullAccessToReminders`, `AVCaptureDevice.requestAccess`). Handle denied / not determined states with a one-line message in the card and a button that opens System Settings privacy pane (`x-apple.systempreferences:com.apple.preference.security?Privacy_<Calendars|Reminders|Camera>`).
- The check is `swift build` from the repo root. It must pass with no errors. Fix warnings in your own files.
- Do not run the app, do not run `scripts/launch-dev-app.sh`, do not install agent hooks, do not commit.
- Write plain code comments. Keep them short.

## Tasks

### Calendar (`Nook/Widgets/Calendar/`)

Service `NookCalendarService`: request full calendar access on `start(nook:)`; load events from the start of today through 7 days ahead from all calendars; refresh on `.EKEventStoreChanged` and every 5 minutes; expose `events: [NookCalendarEvent]` (your own struct: id, title, start, end, isAllDay, calendarColor as `Color`, location) sorted by start, `authorization: EKAuthorizationStatus`, `func refresh()`. Skip declined events.

Card `NookCalendarCard` (height 120): header "Calendar" with today's date on the right. Then the next three events that have not ended: a colored dot, title, and a time column ("in 25 min" when it starts within an hour, otherwise "10:00"). All-day events show "All day". When nothing is left today, show the next day's first event with its weekday. Empty state: "Nothing coming up".

Next-up notices: when an event starts in 10 minutes and again at 2 minutes, call `nook.showTransient(symbol: "calendar", text: "<title> in 10 min", tint: <calendar color>, duration: .seconds(6))`. Fire each once per event (keep a set of fired keys). Use a one-minute `Timer` on the main run loop.

Settings `NookCalendarSettings`: a `Section("Calendar")` with a toggle for the next-up notices (persist in `UserDefaults` under `nook.calendar.nextUpEnabled`, default on) and a "Refresh" button. Show the authorization status in one line with an "Open System Settings" button when access is denied.

### Todo (`Nook/Widgets/Todo/`)

Service `NookRemindersService`: request full reminders access on `start(nook:)`; expose `items: [NookTodoItem]` (your struct: id, title, dueDate, isCompleted, listName) for incomplete reminders in the chosen list, sorted by due date then creation; `lists: [NookReminderList]` (id, title, color); `selectedListID: String?` persisted under `nook.todo.listID` (nil = default reminders list); `func add(_ title: String)`, `func complete(_ id: String)`, `func refresh()`. Refresh on `.EKEventStoreChanged`.

Card `NookTodoCard` (height 140): header "Todo" with the list name on the right. A text field at the top ("Add a reminder", return key adds, clears the field). Below, up to four items: a circle button that completes the item with a short fade, the title, and a due label on the right ("Today", "Tomorrow", weekday, or "Oct 9") in red when overdue. Empty state: "All clear".

Settings `NookTodoSettings`: `Section("Todo")` with a `Picker` for the reminders list and the authorization line as in Calendar.

### Notes (`Nook/Widgets/Notes/`)

Quick capture into the user's Obsidian vault, not an in-app store.

Service `NookNotesService`: `fileURL` persisted under `nook.notes.path`, default a Markdown file in the app's own folder under Application Support (create the file with a `# Quick Notes` heading if missing). `func append(_ text: String)` appends a line `- **YYYY-MM-DD HH:mm** text` (single line, newlines in the text become spaces). `entries: [NookNoteEntry]` (id, date, text) is the last 20 lines that match that pattern, newest first; re-read the file on `start(nook:)`, after each append, and when the file changes on disk (DispatchSource on the file descriptor, re-arm after rename since Obsidian replaces files). `func delete(_ id:)` removes that line.

Card `NookNotesCard` (height 120): header "Notes" with the file name on the right. A text field ("Jot something, return to save") that appends and clears. Below, the last three entries, each the time in monospace and the text on one line, with a small × on hover that deletes it.

Settings `NookNotesSettings`: `Section("Notes")` showing the path, a "Choose file…" `NSOpenPanel` limited to `.md`, and "Reveal in Finder".

### File tray (`Nook/Widgets/Tray/`)

Store `NookTrayStore`: items live in `~/Library/Application Support/OpenIsland/Tray/` (copy dropped files in; keep an `index.json` with id, original filename, stored path, added date). `items: [NookTrayItem]`. `handleDrop(_ providers: [NSItemProvider]) -> Bool` is already called when files are dropped on the closed notch; accept `public.file-url` providers, copy each file, return true if any were taken. `func remove(_ id:)`, `func clear()`, `func revealInFinder(_ id:)`.

Card `NookTrayCard` (height 90): header "File tray" with the count on the right. A horizontal row of up to six item tiles: the file icon from `NSWorkspace.shared.icon(forFile:)` at 32pt and the name under it at 9pt, one line, middle-truncated. Each tile is draggable out with `.onDrag` providing the stored file URL, so dropping it into Finder or another app copies the file. A × on hover removes the item. The whole card is also a drop target (`.onDrop(of: [.fileURL])`). Empty state: "Drop files here or on the notch".

Settings `NookTraySettings`: `Section("File tray")` with the item count, "Reveal tray folder", and "Clear tray".

### Focus timer (`Nook/Widgets/Timer/`)

Service `NookFocusTimer`: `remaining: TimeInterval`, `isRunning: Bool`, `preset: TimeInterval` (default 25 minutes; persist under `nook.timer.preset`), `func start()`, `func pause()`, `func reset()`, `func set(preset:)`. Tick with a one-second `Timer` on the main run loop and compute remaining from an end date, not by decrementing, so it stays accurate. `closedText: String?` returns "mm:ss" while running or paused with time left, nil when idle. When it reaches zero: stop, play `NSSound(named: "Glass")`, and call `nook.showTransient(symbol: "timer", text: "Timer done", tint: .orange, duration: .seconds(6))`.

Card `NookTimerCard` (height 96): remaining time in a large monospaced font on the left (e.g. 28pt), three preset chips (15, 25, 50) in the middle that set the preset when idle, and Start/Pause plus Reset buttons on the right. A thin progress line under the time.

Settings `NookTimerSettings`: `Section("Focus timer")` with a `Stepper` for the default minutes and a toggle for the end sound (persist under `nook.timer.soundEnabled`, default on).

### Mirror (`Nook/Widgets/Mirror/`)

No service. Card `NookMirrorCard` (height 150): an `NSViewRepresentable` hosting `AVCaptureVideoPreviewLayer` on an `AVCaptureSession` with the default video device, `videoGravity = .resizeAspectFill`, horizontally mirrored, corners rounded to 12pt. Start the session on appear and stop it on disappear, on a background queue (`AVCaptureSession.startRunning` blocks). Request camera access first; show the denied / not determined message with the System Settings button instead of a black box. Keep the session in a small `@MainActor` controller object owned by the view's `@State` so it survives re-renders.

Settings `NookMirrorSettings`: `Section("Mirror")` with a `Picker` of available video devices (persist the unique ID under `nook.mirror.deviceID`) and a note that the camera runs only while the island is open on the Nook page.

### Battery and headphones (`Nook/Widgets/Power/`)

Service `NookPowerMonitor` (no card): on `start(nook:)`, register `IOPSNotificationCreateRunLoopSource` and track whether the Mac is on AC and the battery percentage (`IOPSCopyPowerSourcesInfo`). When the charger connects, call `nook.showTransient(symbol: "bolt.fill", text: "Charging · 78%", tint: .green)`; when it disconnects, `symbol: "battery.75"` (pick the battery symbol for the level) with `text: "On battery · 78%"`, tint white. Also listen for the default output device changing (`AudioObjectAddPropertyListenerBlock` on `kAudioObjectSystemObject` for `kAudioHardwarePropertyDefaultOutputDevice`). When the new device's transport type is Bluetooth, show `symbol: "airpodspro"` if the name contains "AirPods", otherwise `"headphones"`, with `text: "<device name> connected"`. Ignore the first callback at launch. Persist an enable toggle under `nook.power.enabled` (default on).

Settings `NookPowerSettings`: `Section("Battery and headphones")` with that toggle and a "Test notice" button that shows a sample transient.

## Wave 3: resizable widgets and edit mode

Contract: DECISIONS.md D15. Foundation (sizes, grid rules, saved order and sizes per display, edit-mode flag, card height functions, static grid page) is committed. Builders:

- Grid: drag-and-drop edit mode on the island page (`Nook/Views/NookPanelView.swift`, new `NookWidgetGrid.swift`, `NookWidgetEditChrome.swift`).
- One builder per card for small and large layouts: media, calendar, todo, notes, tray, timer (plus typed durations), mirror.

## Wave 4: settings editor

- Personalization section 08 becomes the same grid with placeholder tiles, drag to reorder and resize, plus the shelf.

## Motion and halo (waves 5 to 7)

Contract: DECISIONS.md D16. Approved plan copied below.


## Context

mannie wants the Personalization tab and the notch to move like Apple's own UI (smooth springs, no snapping) and wants color animation around the notch. He chose a **status halo**: one soft color glow at a time around the closed pill, for all four moments (agent waiting, agent finished, agent running, notices and music).

Why it feels choppy today (verified in code):
- The island window's height follows its content through a synchronous `setFrame` (`OverlayPanelController.positionPanel`), and the black surface takes its height from the window (`IslandPanelView.notchContent`). Every size change snaps the shape in one frame. Nothing that resizes the window runs inside an animation.
- Some actions resize two to four times (`showAgentsPage`, `addWidget`, every resize-grip step).
- Page switch is an `if/else` with no transition. On close, the content is swapped (notification card becomes the list or the Nook page) while it is still fading.
- The closed pill (pure black) and the opened surface (ink #0d0d0f) cross-fade as two different blacks.
- `UnifiedBars` removes and re-adds its Core Animation loops on every layout, which restarts the wave.
- Personalization: only the music chip animates. Cards, chips, toggles and the profile switch cut instantly, with no hover or press feedback. The preview runs a useless 4 Hz `TimelineView`. Its animation key holds only slot widths, which means equal-width swaps cut hard. The whole pane re-renders on every click and every 2 s auto-cycle. Every Nook preference tap writes about 16 UserDefaults keys and repositions the real island, even for the profile not on screen.
- No Reduce Motion, Low Power or thermal checks exist anywhere.

## Approach

### 1. Shared motion vocabulary (new `Sources/OpenIslandApp/Motion/Motion.swift`)
Named animations built on Apple's macOS 14 springs: `islandOpen`, `islandClose`, `islandPop`, `islandResize` (`.smooth(0.36, extraBounce: 0.04)`), `pageSwitch`, `morph` (replaces the five unnamed `timingCurve(0.4,0,0.2,1,0.45)`), `contentSwap` and `selection` (`.snappy`), `hover`, `press`, `reflow`, `lift`, `editToggle`, plus halo timings. Also `withMotion(_:_:)`, `PressableButtonStyle` (scale 0.97), `.hoverHighlight(...)`, `.motionAnimation(_:value:)`, and Reduce Motion fallbacks (short ease, opacity-only transitions). The rule is springs for anything interruptible and curves only for fades.

### 2. Island size: grow first, shrink after (approach B)
- Coalesce refreshes. `OverlayUICoordinator.scheduleLayoutRefresh()` runs one refresh per run-loop turn instead of one per change.
- The panel controller resolves an `IslandOpenedLayout { headerHeight, contentHeight, shapeHeight }` from the existing height logic.
  - **Growing:** `setFrame` first (with `disableScreenUpdatesUntilFlush`), then the shape springs into the new room.
  - **Shrinking:** the shape springs first, and the window shrinks about 0.5 s later. A pure `IslandPanelSizing.resizeStep` decides which case applies.
  - Display changes apply at once.
- `IslandPanelView` reads `model.islandOpenedLayout` for the shape, header and content heights, inside `withAnimation(Motion.islandResize)`. Its `GeometryReader` is then used for width only.
- Opening publishes the layout before `notchStatus`, which lets the open spring land on the right size.
- Hit-testing (`contentRect`, `NotchHostingView.hitTest`, `isPointInExpandedArea`) follows the visible shape. During the brief shrink delay, clicks below the island go through the existing close-and-repost path.
- Rejected: a permanently screen-tall window (approach A). It would swallow clicks, scrolls, drags and cursors of the apps underneath.
- Related fixes:
  - **Page switch:** blur-replace transition, and an animated header symbol.
  - **Mid-close swap:** snapshot what was on screen on `notchClose` (`closingPresentation`). The view keeps drawing it while it fades. `notchOpenReason` still clears immediately, which keeps the existing tests passing.
  - **One black surface:** `V6ClosedPill(drawsBackground: false)` on the island, with the pop and hover scale moved to the shared container. The surface now morphs closed to open.
  - **Edit mode:** fix the 8 pt gap in `NookPanelView.preferredHeight`.
  - **External displays:** use `islandClosedHeight` on both the window and header sides, removing the extra black space.
  - Make `OverlayPlacementDiagnostics` Equatable and assign it only when it changes.
  - Correct the stale "window is always max size" comments.
  - Add tracing: `OPEN_ISLAND_TRACE_OVERLAY` logging, `OSSignposter` around refresh and setFrame, and a frame-change count in the harness report.

### 3. Personalization smoothness
- **One card component:** `PersonalizationCard` (tile and row layouts) replaces the four copy-pasted card chromes in `AppearanceSettingsPane`. It has animated fill levels (rest, hover, selected), a selection ring that slides between cards with `matchedGeometryEffect`, press scale, and a checkmark with a bounce effect.
- **Other components:** `MonoChip`, a section header, and a toggle row whose enabled or disabled state animates.
- **Every selection animates:** each model write goes through `withMotion(.selection)`, and the profile switch uses `.morph`.
- **Preview:**
  - Remove the 4 Hz `TimelineView`.
  - The `V6ClosedPill` animation key now covers the content, not only the widths.
  - Slot swaps blur-replace, numbers use `.numericText()`, and the label interpolates.
  - Transitions clip to the pill shape.
  - The external and MacBook bodies merge into one, which makes the layout switch a morph instead of a cut. The notch mock fades and scales.
  - Cache the GIF (`NSCache`, decoded off the main thread) so it is never decoded again mid-animation.
- **Cost:**
  - Each section becomes its own child view with narrow inputs.
  - The preview owns its own cycle state, which means the 2 s auto-cycle re-renders only the preview.
  - `SessionListPanelPreview` becomes Equatable.
  - `NookModel` writes only the changed keys and repositions the island only when the edited profile is the active one.
- **Layout editor and grid:**
  - Reflow is keyed on `placements`, which means resizes animate too.
  - Tiles scale and fade in and out on add and remove.
  - The S/M/L highlight slides.
  - Animate: edit-mode dimming and overlays, the insertion highlight, the chip lift (without breaking pointer tracking), the shelf, and empty-state swaps.

### 4. Status halo
- **Pure resolver** (`Island/IslandHaloModel.swift`, in the style of `NookClosedActivity.resolve`). It turns inputs into `IslandHaloState { color, motion, restOpacity, radius, drop }`, one color at a time. Priority:
  1. Style off.
  2. Island open: only the flash shows.
  3. Approval: orange (231,167,98), breathing over 2.0 s.
  4. Question: yellow (255,213,138), breathing over 2.6 s.
  5. Finished: green (111,185,130), a 1.2 s flash.
  6. Notice: its own tint, steady. Timer is orange, charging green, event soon the calendar color, AirPods white. These tints already flow through `showTransient`.
  7. Music: the album art's color, slow drift.
  8. Running: blue (110,167,255), faint drift.
  9. Idle: nothing.
- **Intensity:** Subtle (default) or Vivid metrics. They fit inside the window's existing 18 pt and 22 pt transparent insets.
- **Motion policy:** `IslandMotionPolicy` plus `SystemMotionMonitor`.
  - Reduce Motion: breathing and drift become steady, and the flash becomes one fade.
  - Low Power or a serious thermal state: the running and music glows turn off.
  - Critical thermal state: only a steady glow while an agent waits.
- **Events:**
  - Completion: `IslandHaloController.noteCompletion()` is called from `applyTrackedEvent` when a session completes.
  - Waiting and running: read from the session phases.
  - Notices: read from `nook.transient?.tint`.
  - Music: read from the new `NookArtworkTintService`. It computes a dominant hue from a 24 px thumbnail off the main thread, cached for the last 8 tracks. Gray artwork returns no tint.
- **Rendering:** `Views/IslandHaloView.swift` is a Core Animation layer: a shadow following the pill path, rasterized, and transparent to clicks.
  - It is idempotent: applying the same state never restarts an animation.
  - Color cross-fades start from the color currently on screen.
  - The layer stores its resting opacity, which lets harness screenshots show it.
  - It is attached behind the transitioning surface.
- **Settings preview:** `Views/IslandHaloPreview.swift` is a pure SwiftUI copy, built with `phaseAnimator` and `keyframeAnimator`.
- **Settings:**
  - New per-display preferences: `haloStyle` (Off, Subtle, Vivid; default Subtle) and `haloFollowsMusic`.
  - A new Personalization section, "05 · Status glow". It has style cards, a "Glow with music" toggle, and a note shown when Reduce Motion is on.
  - The preview stage shows the halo, and its chips become idle, running, waiting, done and music.
  - Strings in en, zh-Hans and zh-Hant.
- **Harness hooks:** `OPEN_ISLAND_HALO=approval|question|flash|running|notice:RRGGBB|music:RRGGBB|off` and `OPEN_ISLAND_MOTION_POLICY` force states for screenshots.

### 5. UnifiedBars
- Store the last applied state, so `update` does nothing when nothing changed.
- `layout()` sets geometry only.
- Mode changes spring the bar paths.
- Loops start on a global phase grid, which means re-adding one never visibly restarts it.
- A tint-ready API.
- `isPaused` freezes the bars while the pill is hidden behind the opened island. The visualizer and GIF also pause then.

## Build (crew, worktree mode, checkpoint commit per wave on `nook`)

**Wave 0, boss:**
- `Motion.swift` (complete).
- Stub types:
  - `IslandHaloModel`, `IslandHaloController`, `SystemMotionMonitor`.
  - `IslandOpenedLayout`, `IslandOpenedPresentation`.
  - `NookArtworkTintService`.
- Halo fields in `NookDisplayPreferences`.
- Wiring placeholders in `NookModel`, `OverlayUICoordinator` and `AppModel` (`AppModel+Halo.swift`).
- `UnifiedBars.isPaused`.
- An empty `nookHaloSection`.
- D16 in DECISIONS.md recording these contracts.
- Commit, then create the worktrees.

**Wave 1, eight builders in parallel:**

| Task | Owns |
|---|---|
| T1 settings components | new `Views/Settings/PersonalizationComponents.swift` and a render test |
| T2 halo logic | `IslandHaloModel`, `SystemMotionMonitor`, harness scenarios, tests |
| T3 halo renderers | new `IslandHaloView` and `IslandHaloPreview`, tests |
| T4 Nook data | `NookArtworkTint`, `NookModel` (persist changed keys only, active-profile gate), `NookDisplayPreferences`, tests |
| T5 bars | `UnifiedBars`, `PerformancePolicyTests` |
| T6 sizing, AppKit side | `OverlayPanelController`, `OverlayUICoordinator`, `OverlayDisplayConfiguration`, `IslandOpenedLayout`, the harness recorder, sizing tests |
| T7 grid and editor | `NookWidgetGrid`, `NookWidgetEditChrome`, `NookLayoutEditor`, `NookPanelView`, tests |
| T8 closed pill | `V6NotchContent`, `V6ClosedPillShape`, `NookMediaViews`, `NookClosedActivity`, tests |

**Wave 2, three builders:**

| Task | Owns |
|---|---|
| T9 island view | `IslandPanelView`: layout and presentation, page transition, single surface, halo attach, content reveal, literal swaps |
| T10 Personalization pane | `AppearanceSettingsPane` plus new `Views/Settings/ClosedPreviewSection.swift`: child sections, new components, preview with halo |
| T11 Nook sections and strings | `NookPersonalizationSections` (child views, real halo section) and the three `Localizable.strings` |

**Wave 3, boss:**
- Merge and run `swift build` and `swift test`.
- Run the verification below.
- Tune the halo numbers.
- Review pass (`pr-review-toolkit` style adversarial review).
- Commit, relaunch the dev app, and update PLAN.md.

## Verification

1. **Unit tests (Swift Testing):**
   - Sizing: clamp, Nook cap, `resizeStep` grow, shrink and dead zone, visible rect, external header height.
   - Refresh coalescing.
   - Close snapshot: the reason is nil while the presentation stays a notification.
   - Halo priority table, open state showing the flash only, and Reduce Motion and Low Power behavior.
   - Artwork tint on generated images: solid red, red and black split, grayscale returns nil.
   - `persistChanges` writes only one key.
   - Edit-mode `preferredHeight`.
   - Bars phase alignment.
   - Pill content key: date and battery at equal width produce different keys.
2. **Strings:** `zsh scripts/lint-strings.sh`.
3. **Harness screenshots:**
   - Scenarios `closedApproval`, `closedQuestion` and `closedRunning`.
   - `OPEN_ISLAND_HALO=flash`, `music:FF2D55` and `notice:34C759`.
   - `OPEN_ISLAND_MOTION_POLICY=reduced`.
   - `approvalCard` and `sessionList`, checking for no bottom gap.
   - The Nook page with and without edit mode.
   - `scripts/smoke-all-scenarios.sh`.
4. **Settings renders:** offscreen `ImageRenderer` PNGs of card states, halo style cards and halo preview states.
5. **Frame pacing:**
   - With `OPEN_ISLAND_TRACE_OVERLAY=1` and `log stream`, expect at most one grow per action and a shrink about 0.5 s later, with no `setFrame` between states of the same height.
   - Watch CPU while an agent waits for a minute. It should stay near idle, because Core Animation runs in WindowServer.
   - The motion itself only proves out by eye. A 60 fps screen recording of hover-open, page toggle, notification arrival, grip resize and close-during-notification needs mannie's screen.

## Risks and out of scope

- **Risks:**
  - Growing the window may tear for one frame. The fallback is growing in 24 pt steps.
  - The 0.5 s shrink delay leaves a strip that catches clicks. Left clicks pass through; scrolls there are lost.
  - The halo near the notch wings can sit over menu-bar items. This is why the radius stays small, the glow is offset downward, and Subtle is the default.
  - Blur effects cost GPU on older Macs. They are gated by the motion policy.
- **Out of scope:**
  - Rainbow or multi-color glow, and color inside the pill.
  - An always-max window, and AppKit frame animation.
  - Row animations inside the agents list and inside cards.
  - An error color (no such agent state exists).
  - Haptics and sounds.
  - Per-moment halo toggles beyond style and music.
