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

mkdir -p "$fw"

sources=("$src"/src/adapter/*.m "$src"/src/private/*.m "$src"/src/utility/*.m)

clang -fobjc-arc -fvisibility=default -dynamiclib \
  -arch arm64 -mmacosx-version-min=14.0 \
  -I"$src/include" -I"$src/src" \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name "@rpath/MediaRemoteAdapter.framework/MediaRemoteAdapter" \
  -o "$fw/MediaRemoteAdapter" \
  "${sources[@]}"

codesign --force --sign - "$fw" >/dev/null 2>&1
command cp "$src/bin/mediaremote-adapter.pl" "$out/mediaremote-adapter.pl"

echo "built $fw"
