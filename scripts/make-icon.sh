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
echo "Updated Resources/Assets.car and Resources/AppIcon.icns"
