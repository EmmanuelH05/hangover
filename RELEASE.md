# Releasing Hangover 1.0

What is left before version 1.0, in order. Steps marked **OWNER** need the
owner's accounts, eyes or decisions. Commands are run from the repository
root, `~/code/open-vibe-island`, unless a step says otherwise.

Decided already: Hangover is free. Version 1.0 ships ad-hoc signed, with no
Developer ID and no notarization. The source lives at
https://github.com/EmmanuelH05/hangover, which is public,
with the code on `main`. One thing is left for the owner: cut a release
with the zip.

## Where things stand

`scripts/package-app.sh` was run on 2026-10-09 with no signing identity and
no notary profile, and without starting the app. It made:

- `output/package/Hangover.app`: version 1.0.0, identifier
  `com.emmanuelhernandez.hangover`, Apple silicon only, link scheme
  `hangover`, no update feed.
- `output/package/Hangover.zip`: about 10.8 MB. A copy taken out of it with
  `unzip` or with `ditto` still passes `codesign --verify --deep --strict`.
- No disk image: `create-dmg` is not installed, and the zip is the release.

The signature is **ad-hoc**: `Signature=adhoc`, no team, no hardened
runtime, no entitlements. `spctl --assess` rejects it, which is what a
build that is not notarized gets.

That run was made on the `hangover` branch before it met Hangover's new
icon on `nook`. The package takes whatever icon files are committed, and a
build after the merge carries the new one.

## A and B. Making the source public: done

Done on 2026-10-09.

- The tracked files no longer carry a home folder path or a personal folder
  name, and the notes widget no longer looks for a file in one user's own
  folder.
- The public repository holds the upstream project's history plus Hangover
  as one commit on top of it. The commit by commit history of the fork is
  kept out of it, because its diffs carry those paths. It stays in the local
  checkout on the `nook` branch and in a private repository,
  `EmmanuelH05/hangover-dev`.
- New work goes to the public repository as a further commit on its
  `main`, made from the tree of `nook`.
- The privacy policy points questions at the repository's issues. Add an
  email address there if you want one.

## C. Build and release the app (OWNER)

9. Build from exactly what is on GitHub, with the submodule in place.

   ```bash
   git status --short
   git submodule update --init
   OPEN_ISLAND_SKIP_SMOKE_TEST=true zsh scripts/package-app.sh
   ```

   `git status --short` must print nothing. Leave `OPEN_ISLAND_SIGN_IDENTITY`
   and `OPEN_ISLAND_NOTARY_PROFILE` unset.

10. Check the result and take its checksum for the release notes.

    ```bash
    codesign --verify --deep --strict --verbose=2 output/package/Hangover.app
    codesign -dv output/package/Hangover.app 2>&1 | grep -E "Identifier|Signature"
    shasum -a 256 output/package/Hangover.zip
    ```

11. Make the release, as a draft. `--target main` makes GitHub create the
    tag on that commit.

    ```bash
    gh release create v1.0.0 output/package/Hangover.zip \
      --repo EmmanuelH05/hangover --target main --draft \
      --title "Hangover 1.0.0" \
      --notes "Not notarized. macOS refuses the first open. The README's Install section has the steps. SHA-256 of Hangover.zip: PASTE_IT_HERE"
    ```

12. Test the download the way a stranger gets it. In a browser, download
    `Hangover.zip` from the draft release, unpack it, and follow the Install
    steps in `README.md` word for word. This was not tested: nothing here
    was allowed to open the app. If macOS says "damaged" and shows no Open
    Anyway button, stop and do not publish.

13. Publish.

    ```bash
    gh release edit v1.0.0 --repo EmmanuelH05/hangover --draft=false
    ```

## D. Open engineering items

None of these blocks the steps above. Each should be fixed or accepted.

14. **Shared with upstream Open Island.** Hangover uses the same
    `~/Library/Application Support/OpenIsland` and `open-island` folders,
    the same hook program path and the same bridge socket. A user with both
    apps installed would see them clash. See them with:

    ```bash
    grep -rn "OpenIsland\"\|open-island" Sources/OpenIslandCore/BridgeTransport.swift Sources/OpenIslandCore/HooksBinaryLocator.swift Sources/OpenIslandCore/CodexSessionTracking.swift
    ```

    Renaming them needs a migration for hooks already installed.

15. **The disk image background is still the upstream project's picture**
    (`Assets/Brand/dmg-background.png` and `dmg-background@2x.png`). Only a
    build with `create-dmg` installed uses it. The zip, which is the
    release, does not. The app icon is Hangover's own, made by
    `scripts/make-hangover-icon.swift`. Package with the committed files:
    do not run `scripts/generate_brand_icons.py` and do not set
    `OPEN_ISLAND_REGENERATE_BRAND_ASSETS`.

16. **The Chinese strings have not been read by a native reader.** That
    includes the ones written for this release: `settings.about.credit`,
    `settings.about.sourceCode`, `settings.about.license`,
    `settings.about.upstream` and `onboarding.permissions.calendar.note`.

    ```bash
    grep -n "settings.about\.\|onboarding.permissions.calendar.note" Sources/OpenIslandApp/Resources/zh-Han*.lproj/Localizable.strings
    ```

17. **The phone and watch companion was never built.** The sources in
    `ios/` type check at best, still say Open Island, and were never run on
    a device. The Mac side of the relay is plain HTTP with a four digit
    pairing code. Hide the relay switch for 1.0 or accept it.

    ```bash
    xcodebuild -project ios/OpenIslandMobile.xcodeproj -list
    ```

18. **Brightness uses a private Apple API** (`DisplayServices`), only when
    the key takeover is on. Fine outside the Mac App Store, and it rules the
    Mac App Store out.

19. **Apple silicon only.** The package and the now playing adapter are
    built for arm64. `OPEN_ISLAND_UNIVERSAL=true` makes the app universal
    and leaves the adapter arm64 only, which means no now playing on Intel.
    `scripts/build-mediaremote-adapter.sh` needs a second `-arch`.

20. **Permissions after an update.** An ad-hoc build's identity is its code
    hash, which is what macOS keeps a permission against.

    ```bash
    codesign -d -r- output/package/Hangover.app
    ```

    prints `designated => cdhash H"..."`, and the hash changes when the code
    does. A user should expect to grant camera, calendar, automation and
    accessibility again after each new version. What macOS does at that
    moment was not watched on a real update.

21. **The package script's own launch check.** Without
    `OPEN_ISLAND_SKIP_SMOKE_TEST=true` it starts the packaged app for three
    seconds, with the real settings of `com.emmanuelhernandez.hangover` and
    the shared socket, next to a running dev app.

22. **Two apps, one scheme.** The dev bundle and the release bundle both
    register `hangover://`. On a Mac with both, macOS picks one.

23. **A release install starts fresh.** The new bundle identifier means new
    settings, new permissions and a new Keychain item for Notion. Nothing is
    carried over from "Open Island Dev".

24. **Still upstream's words.** 30 files under `docs/`, `ios/`, `.github/`
    and the contributor guides name Open Island, and `docs/releasing.md`,
    `docs/packaging.md` and `docs/release-signing.md` describe upstream's
    release flow. `README.zh-CN.md` is upstream's.

    ```bash
    git grep -c "Open Island" -- docs CONTRIBUTING.md CONTRIBUTING.zh-CN.md AGENTS.md CLAUDE.md README.zh-CN.md .github ios
    ```

25. **Names left in other apps' files on purpose.** The Codex marker
    "Managed by Open Island" (it recognizes older installs), the comments in
    the installed status line scripts and in the bundled OpenCode and Pi
    plugins, and the Grok hooks file `open-island.json`. Sample sessions in
    the Settings previews are still named `open-island`.

26. **"Check for Updates…" in About is always greyed out.** Hide it, or
    wire it when Hangover has a feed (section F).

27. **The release workflow is upstream's.** `.github/workflows/release.yml`
    now runs only when started by hand, and must be rewritten before use.
    CI's package job starts the app on GitHub's runner and installs
    `create-dmg` and Pillow there.

28. **Not exercised.** The Developer ID branch of `scripts/package-app.sh`,
    the Local Network usage text, and Reminders under the hardened runtime
    were written from Apple's documentation and never run.

29. **Open items already in `DECISIONS.md`:** the ring light on a real
    screen recording (D18), an approval that can land on a newer request
    (D29), the photo booth on a real camera (D33).

    ```bash
    grep -n "Open:\|Never run\|not checked" DECISIONS.md
    ```

## E. Later: Developer ID and notarization (OWNER)

Not part of 1.0. Without them, users get the first-open warning and the
manual steps in the README, they grant permissions again after every update
(item 20), and the app cannot update itself.

30. Join the Apple Developer Program at https://developer.apple.com/programs/
    (paid, yearly).

31. Create a "Developer ID Application" certificate in Xcode, under
    Settings, Accounts, Manage Certificates. Then check it is there:

    ```bash
    security find-identity -v -p codesigning
    ```

32. Store a notary profile. The password is an app-specific password from
    https://account.apple.com.

    ```bash
    xcrun notarytool store-credentials "hangover-notary" \
      --apple-id "YOUR_APPLE_ID" --team-id "YOUR_TEAM_ID"
    ```

33. Package, signed and notarized.

    ```bash
    OPEN_ISLAND_SIGN_IDENTITY="Developer ID Application: YOUR NAME (YOUR_TEAM_ID)" \
    OPEN_ISLAND_NOTARY_PROFILE="hangover-notary" \
    OPEN_ISLAND_SKIP_SMOKE_TEST=true zsh scripts/package-app.sh
    ```

34. Check that Gatekeeper accepts it.

    ```bash
    spctl --assess --type execute -vv output/package/Hangover.app
    xcrun stapler validate output/package/Hangover.app
    ```

## F. Automatic updates: on from 1.0.1

The packaged release carries Hangover's feed address and public key, and
Sparkle checks the feed once a day (D36). The dev build carries neither and
never checks. Version 1.0.0 has no updater: its users download once more by
hand.

The signing key was made on 2026-10-09 with
`generate_keys --account hangover`. Its private half is in the owner's
login Keychain and nowhere else. **OWNER:** keep a copy somewhere safe.
Without it no installed copy accepts another update.

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account hangover -x hangover-update-key.txt
```

Move that file off this Mac and never put it in the repository.

To publish an update:

1. Build it with the new version number.

   ```bash
   OPEN_ISLAND_VERSION=1.0.4 zsh scripts/package-app.sh
   ```

2. Sign the zip. This prints the signature and the length.

   ```bash
   .build/artifacts/sparkle/Sparkle/bin/sign_update --account hangover output/package/Hangover.zip
   ```

3. Add an item to `appcast.xml` with the version, the build number from the
   bundle's `CFBundleVersion`, the signature, the length and the download
   address `https://github.com/EmmanuelH05/hangover/releases/download/v<version>/Hangover.zip`.
4. Publish the commit to the public repository, then post the release with
   the same zip. The feed is read from the `main` branch.

Not done: nobody has watched one version update itself to the next. The
first real test is the update after 1.0.1.
