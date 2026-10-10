#!/bin/bash
# Renders Resources/AppIcon.svg into Resources/AppIcon.icns. Run after editing the SVG and commit both files;
# builds only copy the .icns, so they don't need a renderer. Uses headless Google Chrome for the SVG (no Homebrew
# or Python dependency) and macOS's own sips + iconutil for the sizes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVG="$ROOT/Resources/AppIcon.svg"
ICNS="$ROOT/Resources/AppIcon.icns"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

[[ -x "$CHROME" ]] || { echo "Google Chrome not found at $CHROME (set CHROME=<path to a Chromium binary>)" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/botrecord-icon.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

MASTER="$WORK/icon-1024.png"
# Headless Chrome writes the screenshot but doesn't always exit afterwards: wait for the file, then stop it.
"$CHROME" --headless --disable-gpu --no-first-run --no-default-browser-check --hide-scrollbars \
    --default-background-color=00000000 --user-data-dir="$WORK/chrome" --window-size=1024,1024 \
    --screenshot="$MASTER" "file://$SVG" >/dev/null 2>&1 &
CHROME_PID=$!
for _ in $(seq 1 30); do
    [[ -s "$MASTER" ]] && break
    sleep 1
done
sleep 1 # let Chrome finish writing
kill "$CHROME_PID" 2>/dev/null || true
pkill -f "$WORK/chrome" 2>/dev/null || true
[[ -s "$MASTER" ]] || { echo "Chrome didn't render $SVG within 30 s" >&2; exit 1; }

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ICNS"
cp "$MASTER" "$ROOT/docs/images/app-icon.png"
echo "Wrote $ICNS"
