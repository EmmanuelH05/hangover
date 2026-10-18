#!/bin/zsh
# One command to look at the UX fixes: builds the dev copy, records the
# `check` demo script in it (the app drives itself, with a drawn pointer, on
# sample content and an in-memory store), then cuts one still per step out of
# the movie. Nothing of yours is read or written, and no real player is sent
# an Apple Event: the sample player answers shuffle and repeat.
#
# usage: scripts/demo/check.sh [out-dir]
# writes: <out-dir>/check.mov, <out-dir>/check.log, <out-dir>/stills/NN-<step>.png
set -euo pipefail
setopt null_glob
HERE=${0:a:h}
ROOT=${HERE:h:h}
OUT=${1:-$ROOT/output/check}
BACKDROP="$OUT/backdrop.jpg"
SECONDS_TO_RECORD=70

mkdir -p "$OUT/stills"
rm -f "$OUT"/stills/*.png
if [[ ! -f "$BACKDROP" ]]; then
    ffmpeg -loglevel error -y -f lavfi -i "color=c=0x14161a:s=2560x1600" -frames:v 1 "$BACKDROP"
fi

# The dev copy, fresh. The launcher starts it; the demo wants the screen to itself.
zsh "$ROOT/scripts/launch-dev-app.sh" --skip-setup >"$OUT/build.log" 2>&1
pkill -9 -f "Open Island Dev" 2>/dev/null || true

# The island opens on hover and closes when the real pointer leaves it, and
# the tour's window comes forward only while nothing else is being used: a
# hand on the mouse during the run closes the island and hides the tour.
echo "Recording for $SECONDS_TO_RECORD s. Leave the mouse and keyboard alone until it says done, or lock the screen."
/bin/sleep 5

zsh "$HERE/take.sh" check "$SECONDS_TO_RECORD" "$OUT" "$BACKDROP"

# One still a step, taken 0.9 s after its door ran, when the animation has
# settled. The log's times count from the app's launch; the recorder started
# 1.2 s after it.
i=0
while read -r _ at name; do
    i=$((i + 1))
    t=$(( at - 1.2 + 0.9 ))
    (( t < 0 )) && t=0
    ffmpeg -loglevel error -y -ss "$(printf '%.2f' $t)" -i "$OUT/check.mov" -frames:v 1 "$OUT/stills/$(printf '%02d' $i)-$name.png"
done < <(grep -E '^DEMO [0-9]' "$OUT/check.log")

echo "movie:  $OUT/check.mov"
echo "stills: $OUT/stills ($i)"
