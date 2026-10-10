# Hangover Privacy Policy

**Last updated: 2026-10-09. Applies to Hangover 1.0.5.**

Hangover is a Mac app that lives in the notch. It shows your coding agents,
your music and a page of small widgets. This page says what the app keeps,
what it sends and what it asks macOS for. Each statement was checked against
the source code, which is public: https://github.com/EmmanuelH05/hangover

## The short version

- There is no account, no analytics, no telemetry, no crash reporting and no
  advertising. The app has no server of its own.
- Almost everything stays on your Mac.
- Two widgets talk to a service on the internet, and only after you turn them
  on: the weather tile (Open-Meteo) and the to-do widget, when you set its
  source to Notion or TickTick.
- About once a day the app asks GitHub whether there is a new version.
- One feature talks to your own iPhone or Apple Watch over your local
  network, and only after you turn it on.

## What stays on your Mac

| What | Where it is kept |
|------|------------------|
| Settings and layout | macOS preferences for the app (UserDefaults). |
| Agent sessions | The app reads the session files your agents already write in their own folders, and what their hooks report. It keeps a small list of tracked sessions in `~/Library/Application Support/open-island/`. |
| Hook messages | An agent's hook hands its event to the app through a local socket on this Mac (in `~/Library/Application Support/OpenIsland/` or `/tmp`). |
| Claude Code usage | If you install the usage bridge, Claude Code writes its rate limit numbers to `/tmp/open-island-rl.json`, and the app reads them there. |
| Clipboard history | In memory only, and off until you turn it on. Nothing is written to disk or to the log, and turning it off forgets every copy. Copies marked as concealed or transient by a password manager are never read. |
| Tray files | Copies of the files you drop on the island, in `~/Library/Application Support/OpenIsland/Tray/`. |
| Photo booth strips | PDF files in `Pictures/Hangover Photo Booth`, or in a folder you pick. |
| The camera picture | Shown live in the mirror and nowhere else. It is recorded only when you start the photo booth, and then only as the strip above. The mirror records no sound. |
| Mirror frames and stickers | In the app's preferences. |
| Quick notes | Lines added to one Markdown file: `~/Library/Application Support/OpenIsland/Notes/Quick Notes.md`, or a file you pick. When you pick Apple Notes in Settings, each note is added to a note called Quick Notes in your Notes app, and the app keeps the last 20 in its preferences to list them. |
| Calendar events and reminders | Read from, and written to, the Calendar and Reminders data already on your Mac, through macOS. The app keeps no copy of its own. |
| Weather | The last report and the city you typed, in the app's preferences. |
| Notion or TickTick tasks | A copy of the last loaded tasks in `~/Library/Application Support/OpenIsland/Todo/`. Your Notion or TickTick token is kept in the macOS Keychain. |
| Diagnostic messages | Written to the macOS log on this Mac. They are not sent anywhere. |

## What leaves your Mac, and when

### Weather tile (off by default)

While the weather widget is switched on, the app asks
[Open-Meteo](https://open-meteo.com/) for a forecast. A request carries the
coordinates of your city rounded to two decimals, which is roughly one
kilometer. When you type a city in Settings, its name and a two-letter
language code go to Open-Meteo's place search. No request is made while the
widget is off. The app never uses Location Services. Like any web request,
these show your IP address to Open-Meteo.

### Notion to-do source (off by default)

If you pick Notion as the source of the to-do widget and give the app a
Notion integration token, the app talks to `api.notion.com` with that token.
It reads the database you chose, and it creates and updates tasks there when
you add one, complete one or edit its notes. Nothing is sent to Notion until
you pick it and connect it.

### TickTick to-do source (off by default)

If you pick TickTick as the source of the to-do widget and give the app a
TickTick API token, the app talks to `api.ticktick.com` with that token. It
reads the names of your lists and the open tasks of the list you chose, and
it creates and updates tasks there when you add one, complete one or edit its
notes. Nothing is sent to TickTick until you pick it and connect it.

### iPhone and Apple Watch relay (off by default)

If you turn the relay on in Settings, the Mac announces itself on your local
network with Bonjour and accepts connections from devices you pair with a
four digit code. A paired device is sent the agent events the island shows:
the agent's name, the request or question and its options, a summary, and
the working folder. The device can send back an approval, a denial or an
answer. This traffic stays on your local network. It is plain HTTP and is
not encrypted, which means other devices on the same network could read it.
Paired devices are forgotten when the app quits.

### Remote agents over SSH (only if you set it up)

You can run an agent on another machine and forward its hook events to this
Mac through an SSH connection you configure yourself. Its events, and what
you answer, then travel inside that connection.

### Links you click

Joining a meeting, opening the source code or the license from the About
pane, and opening a link in an agent's message open that address in your
browser or meeting app. The app does not fetch images or anything else named
in an agent's message.

### Updates

From version 1.0.1 Hangover checks for a new version about once a day. It
reads one file, `appcast.xml`, from this project's repository on GitHub.
When that file lists a newer version, the app offers it and, if you accept,
downloads it from this project's releases on GitHub.

The request carries what any web request carries: your IP address, and the
app's name and version. No identifier of yours is sent, and the update
framework (Sparkle) sends no profile of your Mac. Every update is signed
with a key only the author holds, and the app refuses one that is not.
Version 1.0.0 and builds made for development never check.

## What the app writes into other apps' settings

Connecting an agent adds Hangover's hook to that agent's own settings file,
for example `~/.claude/settings.json`. The Setup tab names the file for each
agent. This happens only when you click, and you can remove the hook from
the same tab. For an agent you connected, the app puts a missing hook back
when it starts. The hook program itself is copied to
`~/Library/Application Support/OpenIsland/bin/`.

The app reads, and never changes, Claude Code's permission rules, the
process list, and the Warp terminal's local database when it looks for the
terminal tab an agent runs in.

## What the app asks macOS for

Every item is optional. macOS asks, not the app, and you can change your
answer in System Settings, under Privacy & Security.

| Permission | Used for | Asked when |
|------------|----------|------------|
| Camera | The mirror and its photo booth. | The first time you turn the mirror on. |
| Calendars | The calendar widget, the notice before an event, and the Join button for a meeting. | The first time the calendar widget is shown in an island you opened, or when you turn that widget on in Settings. Not at launch. |
| Reminders | The to-do widget, while Reminders is its source. | The first time the to-do widget is shown in an island you opened, or when you turn it on in Settings. Not at launch. |
| Automation | Finding the terminal window an agent runs in, jumping to it, and typing your reply there. Used with Terminal, iTerm, Ghostty and System Events. Also used with Notes, to add a quick note, and only after you pick Apple Notes as where notes go. | When an agent session is live and the app first looks for its window, and again for a jump or a reply. |
| Accessibility | Handling the volume and brightness keys itself, if you turn that option on. Switching tabs in the Warp terminal. | When you turn the key option on, or when a jump needs it. |
| Local Network | The iPhone and Apple Watch relay. | macOS 15 and later may ask when you turn the relay on. |
| Paste from other apps | Clipboard history. | macOS 15.4 and later lets you limit which apps read the clipboard. The app follows that setting, and stops reading by itself when macOS is set to ask every time. |

The app does not ask for the microphone, your location, your contacts, your
Photos library or screen recording.

## Other people's software

The weather data comes from Open-Meteo. The to-do source can be Notion or
TickTick.
Their own privacy policies apply to what you send them.

## Changes

A change to what the app keeps or sends will be listed here with a new date.

## Contact

Questions about this policy go in an issue at https://github.com/EmmanuelH05/hangover/issues
