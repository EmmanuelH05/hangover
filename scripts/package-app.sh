#!/bin/zsh

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Hangover packaging runs only on macOS." >&2
    exit 1
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_name="${OPEN_ISLAND_APP_NAME:-Hangover}"
bundle_identifier="${OPEN_ISLAND_BUNDLE_ID:-com.emmanuelhernandez.hangover}"
version="${OPEN_ISLAND_VERSION:-1.0.1}"
build_number="${OPEN_ISLAND_BUILD_NUMBER:-$(git -C "$repo_root" rev-list --count HEAD 2>/dev/null || echo 1)}"
package_root="${OPEN_ISLAND_PACKAGE_ROOT:-$repo_root/output/package}"
bundle_dir="${OPEN_ISLAND_BUNDLE_DIR:-$package_root/$app_name.app}"
zip_path="${OPEN_ISLAND_ZIP_PATH:-$package_root/$app_name.zip}"
dmg_path="${OPEN_ISLAND_DMG_PATH:-$package_root/$app_name.dmg}"
signing_identity="${OPEN_ISLAND_SIGN_IDENTITY:-}"
notary_profile="${OPEN_ISLAND_NOTARY_PROFILE:-}"

brand_script="$repo_root/scripts/generate_brand_icons.py"
dmg_bg_script="$repo_root/scripts/generate_dmg_background.py"
entitlements_path="$repo_root/config/packaging/OpenIslandApp.entitlements"

cd "$repo_root"

arch_flags=()
if [[ "${OPEN_ISLAND_UNIVERSAL:-false}" == "true" ]]; then
    arch_flags=(--arch arm64 --arch x86_64)
fi

swift build -c release "${arch_flags[@]}" --product OpenIslandApp
swift build -c release "${arch_flags[@]}" --product OpenIslandHooks
swift build -c release "${arch_flags[@]}" --product OpenIslandSetup

build_bin_dir="$(swift build -c release "${arch_flags[@]}" --show-bin-path)"
app_binary="$build_bin_dir/OpenIslandApp"
hooks_binary="$build_bin_dir/OpenIslandHooks"
setup_binary="$build_bin_dir/OpenIslandSetup"
brand_icon="$repo_root/Assets/Brand/OpenIsland.icns"

# Package the committed brand assets instead of re-rendering them: the icon
# generator rewrites tracked PNGs whenever the local Pillow encodes them
# differently, and the DMG background depends on whichever fonts the machine
# has (see scripts/launch-dev-app.sh). Opt in when the brand source changed.
dmg_background="$repo_root/Assets/Brand/dmg-background.png"
if [[ "${OPEN_ISLAND_REGENERATE_BRAND_ASSETS:-false}" == "true" ]]; then
    python3 "$brand_script"
    python3 "$dmg_bg_script"
else
    for asset in "$brand_icon" "$dmg_background"; do
        if [[ ! -f "$asset" ]]; then
            echo "Missing $asset — run scripts/generate_brand_icons.py and scripts/generate_dmg_background.py, or set OPEN_ISLAND_REGENERATE_BRAND_ASSETS=true" >&2
            exit 1
        fi
    done
fi

rm -rf "$bundle_dir" "$zip_path" "$dmg_path"
mkdir -p "$bundle_dir/Contents/MacOS" "$bundle_dir/Contents/Helpers" "$bundle_dir/Contents/Resources" "$bundle_dir/Contents/Frameworks"

cp "$app_binary" "$bundle_dir/Contents/MacOS/OpenIslandApp"
cp "$hooks_binary" "$bundle_dir/Contents/Helpers/OpenIslandHooks"
cp "$setup_binary" "$bundle_dir/Contents/Helpers/OpenIslandSetup"
cp "$brand_icon" "$bundle_dir/Contents/Resources/OpenIsland.icns"

# Copy Sparkle.framework for auto-update support.
sparkle_framework="$repo_root/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ -d "$sparkle_framework" ]]; then
    cp -R "$sparkle_framework" "$bundle_dir/Contents/Frameworks/"
else
    echo "WARNING: Sparkle.framework not found at $sparkle_framework — run 'swift package resolve' first." >&2
fi

# MediaRemote adapter (now playing): built from the vendored sources and
# loaded by /usr/bin/perl at runtime. Without it the packaged app has no
# now playing data. The adapter script builds for arm64 only.
#
# The perl script goes in Resources, where it is sealed as a plain file. In
# Helpers it would count as code and carry its signature in extended
# attributes, which a plain unzip drops.
zsh "$repo_root/scripts/build-mediaremote-adapter.sh" >/dev/null
adapter_dir="$repo_root/.build/mediaremote-adapter"
cp -R "$adapter_dir/MediaRemoteAdapter.framework" "$bundle_dir/Contents/Frameworks/"
cp "$adapter_dir/mediaremote-adapter.pl" "$bundle_dir/Contents/Resources/mediaremote-adapter.pl"

# The GNU GPL asks that everyone given the app is also given the license.
# The About pane opens this copy, and the notice names the upstream project.
cp "$repo_root/LICENSE" "$bundle_dir/Contents/Resources/LICENSE.txt"
cp "$repo_root/NOTICE.md" "$bundle_dir/Contents/Resources/NOTICE.md"

# Copy SPM resource bundle into Contents/Resources/ so the .app root stays
# clean for code signing (no unsealed contents). Our custom
# resource_bundle_accessor.swift searches Bundle.main.resourceURL first.
spm_resource_bundle="$build_bin_dir/OpenIsland_OpenIslandApp.bundle"
if [[ -d "$spm_resource_bundle" ]]; then
    cp -R "$spm_resource_bundle" "$bundle_dir/Contents/Resources/"
else
    echo "WARNING: SPM resource bundle not found at $spm_resource_bundle — app may crash on launch." >&2
fi

chmod +x \
    "$bundle_dir/Contents/MacOS/OpenIslandApp" \
    "$bundle_dir/Contents/Helpers/OpenIslandHooks" \
    "$bundle_dir/Contents/Helpers/OpenIslandSetup"

# Add rpath so the binary can find Sparkle.framework in Contents/Frameworks/.
install_name_tool -add_rpath @loader_path/../Frameworks "$bundle_dir/Contents/MacOS/OpenIslandApp" 2>/dev/null || true

cat > "$bundle_dir/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$app_name</string>
    <key>CFBundleExecutable</key>
    <string>OpenIslandApp</string>
    <key>CFBundleIconFile</key>
    <string>OpenIsland</string>
    <key>CFBundleIdentifier</key>
    <string>$bundle_identifier</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$app_name</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>$bundle_identifier.links</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>hangover</string>
            </array>
        </dict>
    </array>
    <key>CFBundleShortVersionString</key>
    <string>$version</string>
    <key>CFBundleVersion</key>
    <string>$build_number</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/EmmanuelH05/hangover/main/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>G3dIlQPu+1pUh9IOtrMZB39d/ZxZWPnC5PfXMJ1OJaU=</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
    <key>NSAppleEventsUsageDescription</key>
    <string>Hangover uses automation to find your agent's terminal window, jump back to it and send your reply there.</string>
    <key>NSCameraUsageDescription</key>
    <string>The Nook mirror shows your camera inside the notch, and its photo booth takes pictures only when you start it.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>The Nook shows your upcoming calendar events.</string>
    <key>NSRemindersFullAccessUsageDescription</key>
    <string>The Nook todo list reads and writes your Reminders.</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Hangover lets a paired iPhone or Apple Watch on your network see and answer agent requests, only while you have that turned on.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_openisland._tcp</string>
    </array>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

plutil -lint "$bundle_dir/Contents/Info.plist" >/dev/null

# --- Verify bundle structure matches what the app expects at runtime ---
verify_errors=0
for required in \
    "Contents/MacOS/OpenIslandApp" \
    "Contents/Helpers/OpenIslandHooks" \
    "Contents/Helpers/OpenIslandSetup" \
    "Contents/Resources/OpenIsland.icns" \
    "Contents/Resources/OpenIsland_OpenIslandApp.bundle" \
    "Contents/Resources/mediaremote-adapter.pl" \
    "Contents/Resources/LICENSE.txt" \
    "Contents/Resources/NOTICE.md" \
    "Contents/Frameworks/MediaRemoteAdapter.framework/MediaRemoteAdapter" \
; do
    if [[ ! -e "$bundle_dir/$required" ]]; then
        echo "ERROR: missing required file: $required" >&2
        verify_errors=$((verify_errors + 1))
    fi
done

if [[ $verify_errors -gt 0 ]]; then
    echo "Bundle verification failed with $verify_errors error(s)." >&2
    exit 1
fi
echo "Bundle structure verified."

# --- Smoke-test the app outside the repo to catch Bundle.module fallback hacks ---
# SPM's generated resource accessor has a hardcoded fallback to the local .build/
# directory. Running from /tmp ensures the app works without that crutch.
#
# The check starts the packaged app for three seconds. Set
# OPEN_ISLAND_SKIP_SMOKE_TEST=true to package without starting anything.
skip_smoke_test="${OPEN_ISLAND_SKIP_SMOKE_TEST:-false}"
smoke_dir="$(mktemp -d)/smoke-test"
mkdir -p "$smoke_dir"
smoke_app="$smoke_dir/$(basename "$bundle_dir")"
smoke_binary="$smoke_app/Contents/MacOS/OpenIslandApp"
if [[ "$skip_smoke_test" != "true" ]]; then
    # A statement of its own: a copy that fails must stop the script.
    cp -R "$bundle_dir" "$smoke_dir/"
fi
if [[ "$skip_smoke_test" == "true" ]]; then
    echo "Smoke test skipped (OPEN_ISLAND_SKIP_SMOKE_TEST=true). The app was not started."
    rm -rf "$(dirname "$smoke_dir")"
elif [[ -x "$smoke_binary" ]]; then
    # Launch and give it a few seconds — if it crashes, the pid disappears.
    "$smoke_binary" &
    smoke_pid=$!
    sleep 3
    if kill -0 "$smoke_pid" 2>/dev/null; then
        kill "$smoke_pid" 2>/dev/null || true
        wait "$smoke_pid" 2>/dev/null || true
        echo "Smoke test passed — app launched successfully outside repo."
    else
        wait "$smoke_pid" 2>/dev/null || true
        echo "ERROR: app crashed when launched outside the repo directory." >&2
        echo "       This likely means Bundle.module cannot find its resource bundle." >&2
        rm -rf "$(dirname "$smoke_dir")"
        exit 1
    fi
    rm -rf "$(dirname "$smoke_dir")"
else
    echo "WARNING: smoke test skipped — binary not found at $smoke_binary" >&2
fi

sparkle_fw="$bundle_dir/Contents/Frameworks/Sparkle.framework"
adapter_fw="$bundle_dir/Contents/Frameworks/MediaRemoteAdapter.framework"

# Nothing in the bundle may depend on an extended attribute: the zip below
# carries none, which lets any unzip tool give back a bundle whose
# signature still holds.
xattr -cr "$bundle_dir"

if [[ -n "$signing_identity" ]]; then
    # Sign nested code objects inside-out: Sparkle internals → helpers → app.

    if [[ -d "$sparkle_fw" ]]; then
        for xpc in "$sparkle_fw"/Versions/B/XPCServices/*.xpc; do
            [[ -d "$xpc" ]] && codesign --force --options runtime --timestamp --sign "$signing_identity" "$xpc"
        done
        [[ -f "$sparkle_fw/Versions/B/Autoupdate" ]] && \
            codesign --force --options runtime --timestamp --sign "$signing_identity" "$sparkle_fw/Versions/B/Autoupdate"
        [[ -d "$sparkle_fw/Versions/B/Updater.app" ]] && \
            codesign --force --options runtime --timestamp --sign "$signing_identity" "$sparkle_fw/Versions/B/Updater.app"
        codesign --force --options runtime --timestamp --sign "$signing_identity" "$sparkle_fw"
    fi

    # Not run yet: no Developer ID build of the adapter has been made.
    codesign --force --options runtime --timestamp --sign "$signing_identity" "$adapter_fw"

    codesign --force --options runtime --timestamp --sign "$signing_identity" \
        "$bundle_dir/Contents/Helpers/OpenIslandHooks"
    codesign --force --options runtime --timestamp --sign "$signing_identity" \
        "$bundle_dir/Contents/Helpers/OpenIslandSetup"

    codesign \
        --force \
        --options runtime \
        --timestamp \
        --entitlements "$entitlements_path" \
        --sign "$signing_identity" \
        "$bundle_dir"

    codesign --verify --deep --strict --verbose=2 "$bundle_dir"
else
    # No identity: ad-hoc sign, which is how version 1.0 ships. Nested code
    # is signed first, inside out, and a failure stops the script. No
    # hardened runtime and no entitlements here, as before: those are for
    # notarization, which an ad-hoc build cannot have.
    if [[ -d "$sparkle_fw" ]]; then
        for xpc in "$sparkle_fw"/Versions/B/XPCServices/*.xpc; do
            if [[ -d "$xpc" ]]; then codesign --force --sign - "$xpc"; fi
        done
        if [[ -f "$sparkle_fw/Versions/B/Autoupdate" ]]; then
            codesign --force --sign - "$sparkle_fw/Versions/B/Autoupdate"
        fi
        if [[ -d "$sparkle_fw/Versions/B/Updater.app" ]]; then
            codesign --force --sign - "$sparkle_fw/Versions/B/Updater.app"
        fi
        codesign --force --sign - "$sparkle_fw"
    fi
    codesign --force --sign - "$adapter_fw"
    codesign --force --sign - "$bundle_dir/Contents/Helpers/OpenIslandHooks"
    codesign --force --sign - "$bundle_dir/Contents/Helpers/OpenIslandSetup"
    codesign --force --sign - "$bundle_dir"

    codesign --verify --deep --strict --verbose=2 "$bundle_dir"
fi

ditto -c -k --norsrc --noextattr --noqtn --keepParent "$bundle_dir" "$zip_path"

# --- Notarize app bundle (before DMG so the stapled bundle goes into the DMG) ---
if [[ -n "$signing_identity" && -n "$notary_profile" ]]; then
    xcrun notarytool submit "$zip_path" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple -v "$bundle_dir"
    rm -f "$zip_path"
    ditto -c -k --norsrc --noextattr --noqtn --keepParent "$bundle_dir" "$zip_path"
fi

# --- Styled DMG creation ---
# The zip is the release. The disk image is made only when the create-dmg
# tool is installed.
dmg_bg="$repo_root/Assets/Brand/dmg-background@2x.png"
made_dmg=false

if command -v create-dmg >/dev/null 2>&1; then
made_dmg=true
create-dmg \
    --volname "$app_name" \
    --background "$dmg_bg" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 96 \
    --text-size 13 \
    --icon "$app_name.app" 180 210 \
    --hide-extension "$app_name.app" \
    --app-drop-link 480 210 \
    --no-internet-enable \
    "$dmg_path" \
    "$bundle_dir"

# Sign the DMG itself (required before notarization)
if [[ -n "$signing_identity" ]]; then
    codesign \
        --force \
        --sign "$signing_identity" \
        --timestamp \
        "$dmg_path"
fi

# Notarize and staple the DMG
if [[ -n "$signing_identity" && -n "$notary_profile" ]]; then
    xcrun notarytool submit "$dmg_path" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple -v "$dmg_path"
fi
else
    echo "create-dmg is not installed: no disk image was made. The zip is complete without it."
fi

echo "Bundle: $bundle_dir"
echo "Archive: $zip_path"
if [[ "$made_dmg" == "true" ]]; then
    echo "DMG: $dmg_path"
fi
if [[ -n "$signing_identity" ]]; then
    echo "Signed with identity: $signing_identity"
else
    echo "No signing identity configured: the bundle is ad-hoc signed and not notarized."
    echo "macOS will refuse the first open of a downloaded copy. See README.md, Install."
fi

if [[ -n "$notary_profile" ]]; then
    echo "Notary profile: $notary_profile"
fi
