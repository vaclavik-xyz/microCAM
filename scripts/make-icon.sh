#!/usr/bin/env bash
# Compile Resources/AppIcon.icon (Icon Composer format) into Resources/Assets.car
# and Resources/AppIcon.icns. Needs Xcode 26 (actool); the compiled files are
# committed, so building the app needs only the command-line tools.
# macOS 26 draws an icon without an Assets.car inside a grey frame; older
# macOS versions use AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)"
xcrun actool "$PWD/Resources/AppIcon.icon" --compile "$OUT" --platform macosx \
  --minimum-deployment-target 14.0 --app-icon AppIcon \
  --output-partial-info-plist "$OUT/partial.plist" >/dev/null
cp "$OUT/Assets.car" "$OUT/AppIcon.icns" Resources/
# favicon.png (256 px) in the repo root: tools that show a project's icon
# (e.g. a dashboard of coding agents) look for it there.
iconutil -c iconset "$OUT/AppIcon.icns" -o "$OUT/AppIcon.iconset"
cp "$OUT/AppIcon.iconset/icon_128x128@2x.png" favicon.png
echo "Updated Resources/Assets.car, Resources/AppIcon.icns and favicon.png"
