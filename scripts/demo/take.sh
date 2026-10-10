#!/bin/zsh
# Runs one demo script in the dev copy and records only that app's windows
# to <out-dir>/<script>.mov, with the script's step times in <script>.log.
# The recorder is built on first use. Nothing but the app's own windows can
# end up in the movie, and it works with the screen locked.
#
# usage: scripts/demo/take.sh <tour|use|closed|looks> <seconds> <out-dir> <backdrop.jpg>
set -euo pipefail
NAME=$1
SECONDS_TO_RECORD=$2
OUT=$3
BACKDROP=$4
HERE=${0:a:h}
APP="$HOME/Applications/Open Island Dev.app/Contents/MacOS/OpenIslandApp"
RECORDER="$OUT/record"

mkdir -p "$OUT"
if [[ ! -x "$RECORDER" || "$HERE/record.swift" -nt "$RECORDER" ]]; then
    swiftc -O -swift-version 5 "$HERE/record.swift" -o "$RECORDER"
fi
rm -f "$OUT/$NAME.mov" "$OUT/$NAME.log"
OPEN_ISLAND_DEMO=1 OPEN_ISLAND_DEMO_BACKDROP="$BACKDROP" OPEN_ISLAND_DEMO_SCRIPT="$NAME" "$APP" >"$OUT/$NAME.log" 2>&1 &
APP_PID=$!
/bin/sleep 1.2
"$RECORDER" $APP_PID "$SECONDS_TO_RECORD" "$OUT/$NAME.mov"
wait $APP_PID 2>/dev/null || true
