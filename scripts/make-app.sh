#!/usr/bin/env bash
# Build microCAM.app (Apple Silicon, ad-hoc signed, personal use; no notarization).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/MicroCAMApp"
APP="build/microCAM.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MicroCAMApp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built: $APP"
