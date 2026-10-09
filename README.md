# Hangover

Hangover is a Mac app that lives in the notch at the top of your screen (or
in the top bar on a display with no notch). It keeps your AI coding agents,
your music and your day within reach, and stays out of the way the rest of
the time.

It is free software, based on [Open Island](https://github.com/Octane0411/open-vibe-island).
See [Credit and license](#credit-and-license).

## What it does

**Agents.** The island shows what your coding agents are doing and brings
their questions to you.

- Live sessions for Claude Code, Codex, Cursor, Gemini CLI, OpenCode, Kimi,
  Grok, Qoder, Qwen Code, Factory, CodeBuddy, Pi and Oh My Pi. Each one is
  connected from Settings, under Setup, and only when you click.
- Approve, deny or answer a request from the island, or with two global
  shortcuts (Control-Option-Y and Control-Option-N by default).
- Jump back to the terminal or editor the agent runs in.
- A short "what it did" line when an agent finishes.

**The Nook.** A page of widgets you can arrange, resize and switch off.

- Now playing, with a scrub bar and a speaker picker.
- Calendar in five looks, with an event editor and a Join button for meetings.
- To-do list from Reminders or from a Notion database.
- Quick notes, kept in a Markdown file.
- A file tray with sharing, AirDrop, zip and image conversion, and an
  optional clipboard history kept in memory only.
- Focus timer with pomodoro rounds.
- Mirror: your camera on demand, with a ring light, frames, stickers and a
  photo booth that saves a strip as a PDF.
- Weather tile, off by default.

**Look and feel.** A status glow with color themes, templates, a wider or
squarer opened island, per-display settings for a MacBook notch and an
external screen, and a welcome tour on first launch. English, Simplified
Chinese and Traditional Chinese.

**Links.** Shortcuts, Raycast and scripts can drive the island with
`hangover://` links, for example `hangover://timer/start?minutes=25`.

What Hangover keeps and what it sends is in [PRIVACY_POLICY.md](PRIVACY_POLICY.md).

## Requirements

- macOS 14 or later.
- The download is built for Apple silicon. On an Intel Mac, build from source.

## Install

Hangover is **not notarized by Apple**. Its author is not in the Apple
Developer Program, and the download is ad-hoc signed. macOS cannot tell you
who made it, and it will refuse to open the app the first time. You can
still open it, with the steps Apple gives for an app from an unknown
developer. Only do this for a copy you downloaded from this repository's
releases page.

1. Download `Hangover.zip` from the
   [releases page](https://github.com/EmmanuelH05/hangover/releases) and
   double-click it to unpack it.
2. Move `Hangover` to your Applications folder.
3. Double-click `Hangover`. macOS shows a warning and does not open it.
   Click **Done**. Do not move it to the Trash.
4. Open the Apple menu, choose **System Settings**, and click **Privacy &
   Security** in the sidebar.
5. Scroll down to **Security**. A line there says Hangover was blocked.
   Click **Open Anyway**. The button is there for about an hour after
   step 3.
6. macOS asks once more. Confirm, and enter your login password if it asks.

Hangover opens, and from then on it opens like any other app. You do not
need to change any other security setting, and you should not turn
Gatekeeper off.

Apple's own pages for these steps:
[Open a Mac app from an unknown developer](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac)
and [Safely open apps on your Mac](https://support.apple.com/en-us/102445).

If macOS says the app is damaged and shows no **Open Anyway** button,
download it again, or build from source.

Two more things follow from the missing notarization:

- Hangover does not update itself. A new version is a new download.
- macOS ties the permissions you grant (camera, calendar, automation and
  the others) to the exact build. After you install a new version, expect
  to grant them again.

## Build from source

An app you build yourself is not a download, and macOS opens it without the
warning above. You need Xcode 26 or its command line tools (Swift 6.2).

```bash
git clone --recurse-submodules https://github.com/EmmanuelH05/hangover.git
cd hangover
swift build
swift test
```

To make the app:

```bash
OPEN_ISLAND_SKIP_SMOKE_TEST=true zsh scripts/package-app.sh
```

This writes `output/package/Hangover.app` and `output/package/Hangover.zip`.
Move the app to your Applications folder and open it. Without
`OPEN_ISLAND_SKIP_SMOKE_TEST=true` the script also starts the packaged app
for three seconds to check that it launches.

For day-to-day development, `zsh scripts/launch-dev-app.sh` builds a debug
copy, installs it as "Open Island Dev" in `~/Applications` and starts it.
`zsh scripts/harness.sh ci` runs the string lint, the docs check, the tests
and a build.

The code is one Swift package with four targets. Internal names still say
`OpenIsland`, on purpose: the hooks installed in your agents' settings point
at them. [docs/index.md](docs/index.md) lists the design documents, which
were written for the upstream project and mostly still use its name.
`README.zh-CN.md` is the upstream project's Chinese README and has not been
rewritten for Hangover.

## Credit and license

Hangover is a changed version of
[Open Island](https://github.com/Octane0411/open-vibe-island) by Octane0411
and its contributors. [NOTICE.md](NOTICE.md) says what was changed and when,
and lists the other software in the app.

Hangover is free software under the
[GNU General Public License, version 3](LICENSE), the same license as Open
Island. You may use it, change it and pass it on under that license. It
comes with no warranty. The complete source code is at
https://github.com/EmmanuelH05/hangover.

Weather data by [Open-Meteo.com](https://open-meteo.com/).
