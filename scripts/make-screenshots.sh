#!/usr/bin/env bash
# Render README screenshots in demo mode — no camera needed. Still photos
# stand in for the live image and the app captures its own windows into
# docs/screenshots/. Needs a logged-in GUI session.
#
# Usage: scripts/make-screenshots.sh <photos>
#   <photos>/frames/*.jpg    "live" images, in order: main, adjustments, zoom, timelapse
#   <photos>/library/*.jpg   photos shown in the side panel of the demo job
#   <photos>/compare/before.jpg, after.jpg   pair for the before/after screenshots
set -euo pipefail
cd "$(dirname "$0")/.."
PHOTOS="$(cd "${1:?usage: scripts/make-screenshots.sh <photos>}" && pwd)"
OUT="$PWD/docs/screenshots"
JOB="PR-260412"
# A readable path for the Settings screenshot; refuse to touch an existing folder.
ROOT="$HOME/Pictures/microCAM demo"
[ -e "$ROOT" ] && { echo "$ROOT already exists, remove it first" >&2; exit 1; }
mkdir -p "$ROOT/$JOB" "$OUT"

# Side-panel library, named like real captures.
cp "$PHOTOS/compare/before.jpg" "$ROOT/$JOB/${JOB}_2026-09-25_13-40-00.jpg"
cp "$PHOTOS/compare/after.jpg" "$ROOT/$JOB/${JOB}_2026-09-25_13-55-00.jpg"
minute=0
for f in "$PHOTOS"/library/*.jpg; do
    minute=$((minute + 1))
    cp "$f" "$ROOT/$JOB/${JOB}_2026-09-25_14-$(printf %02d "$minute")-00.jpg"
done
if command -v ffmpeg >/dev/null; then
    first_frame="$(ls "$PHOTOS"/frames/*.jpg | head -1)"
    ffmpeg -loglevel error -loop 1 -i "$first_frame" -t 2 -r 30 -pix_fmt yuv420p \
        -c:v h264_videotoolbox "$ROOT/$JOB/${JOB}_2026-09-25_14-30-00.mov"
fi

scripts/make-app.sh >/dev/null
frames="$(ls "$PHOTOS"/frames/*.jpg | paste -sd: -)"
# `open` (not exec) so the app is properly activated and windows look focused.
open -W -n build/microCAM.app \
    --env MICROCAM_DEMO_FRAMES="$frames" \
    --env MICROCAM_DEMO_ROOT="$ROOT" \
    --env MICROCAM_DEMO_JOB="$JOB" \
    --env MICROCAM_DEMO_COMPARE="$ROOT/$JOB/${JOB}_2026-09-25_13-40-00.jpg:$ROOT/$JOB/${JOB}_2026-09-25_13-55-00.jpg" \
    --env MICROCAM_DEMO_SHOTS="$OUT"
rm -rf "${ROOT:?}"
# Keep the repo small: 2400 px JPEGs instead of full-resolution PNGs.
for png in "$OUT"/*.png; do
    sips -Z 2400 -s format jpeg -s formatOptions 82 "$png" --out "${png%.png}.jpg" >/dev/null
    rm -f "$png"
done
ls -1 "$OUT"
