#!/usr/bin/env bash
# Build microCAM.app (universal). Ad-hoc signed by default; for a release,
# SIGN_IDENTITY="Developer ID Application: …" signs it with the hardened
# runtime (scripts/release.sh does that and notarizes).
set -euo pipefail
cd "$(dirname "$0")/.."
# Universal: runs on Apple Silicon and on Intel Macs (e.g. an older Mac used only as a viewer).
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/MicroCAMApp"
APP="build/microCAM.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MicroCAMApp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# App icon, compiled by scripts/make-icon.sh (Assets.car for macOS 26, .icns for older).
cp Resources/AppIcon.icns Resources/Assets.car "$APP/Contents/Resources/"
# Translations: one <lang>.lproj per language (Localizable.strings, InfoPlist.strings).
cp -R Resources/*.lproj "$APP/Contents/Resources/"
# Sparkle (updates), with its helpers; ditto keeps the framework's symlinks.
mkdir -p "$APP/Contents/Frameworks"
ditto "$(dirname "$BIN")/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/MicroCAMApp"

# Inside out, as Sparkle's documentation asks. The hardened runtime only with
# a real identity: under it an ad-hoc app can't load an ad-hoc framework.
IDENTITY="${SIGN_IDENTITY:--}"
FLAGS=(--force --sign "$IDENTITY")
[ "$IDENTITY" != "-" ] && FLAGS+=(--options runtime --timestamp)
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
codesign "${FLAGS[@]}" "$SPARKLE/XPCServices/Installer.xpc"
codesign "${FLAGS[@]}" --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
codesign "${FLAGS[@]}" "$SPARKLE/Autoupdate"
codesign "${FLAGS[@]}" "$SPARKLE/Updater.app"
codesign "${FLAGS[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
codesign "${FLAGS[@]}" --entitlements Resources/microCAM.entitlements "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
