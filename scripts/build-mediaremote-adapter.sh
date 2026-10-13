#!/bin/zsh
# Builds the MediaRemoteAdapter framework from the vendored sources
# (Vendor/mediaremote-adapter, BSD-3-Clause) without CMake. The perl launcher
# in that repo dlopen()s the framework binary, which is why it has to be laid
# out as `MediaRemoteAdapter.framework/MediaRemoteAdapter` and be code-signed.
#
# Output: .build/mediaremote-adapter/{MediaRemoteAdapter.framework,mediaremote-adapter.pl}

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
src="$repo_root/Vendor/mediaremote-adapter"
out="$repo_root/.build/mediaremote-adapter"
fw="$out/MediaRemoteAdapter.framework"

if [ ! -f "$src/bin/mediaremote-adapter.pl" ]; then
  echo "Vendored adapter missing. Run: git submodule update --init" >&2
  exit 1
fi

# A framework in the layout macOS expects: the binary and an Info.plist under
# Versions/A, and links at the top. A bare folder with only the binary in it
# signs, but its binary does not verify by itself, and Apple's notary service
# checks every binary by itself ("The signature of the binary is invalid").
# The link at the top keeps the path the perl launcher loads.
rm -rf "$fw"
version_dir="$fw/Versions/A"
mkdir -p "$version_dir/Resources"

sources=("$src"/src/adapter/*.m "$src"/src/private/*.m "$src"/src/utility/*.m)

clang -fobjc-arc -fvisibility=default -dynamiclib \
  -arch arm64 -mmacosx-version-min=14.0 \
  -I"$src/include" -I"$src/src" \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name "@rpath/MediaRemoteAdapter.framework/MediaRemoteAdapter" \
  -o "$version_dir/MediaRemoteAdapter" \
  "${sources[@]}"

cat > "$version_dir/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MediaRemoteAdapter</string>
    <key>CFBundleIdentifier</key>
    <string>app.openisland.MediaRemoteAdapter</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MediaRemoteAdapter</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
</dict>
</plist>
PLIST

ln -sfn A "$fw/Versions/Current"
ln -sfn Versions/Current/MediaRemoteAdapter "$fw/MediaRemoteAdapter"
ln -sfn Versions/Current/Resources "$fw/Resources"

codesign --force --sign - "$fw" >/dev/null 2>&1
command cp "$src/bin/mediaremote-adapter.pl" "$out/mediaremote-adapter.pl"

echo "built $fw"
