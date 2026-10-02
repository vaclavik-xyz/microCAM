#!/usr/bin/env bash
# Build microCAM.app (universal). Ad-hoc signed by default; for a release,
# SIGN_IDENTITY="Developer ID Application: …" signs it with the hardened
# runtime (scripts/release.sh does that and notarizes).
set -euo pipefail
cd "$(dirname "$0")/.."
# Universal: runs on Apple Silicon and on Intel Macs (e.g. an older Mac used only as a viewer).
ARCHS=(--arch arm64 --arch x86_64)
# The Shortcuts actions (App Intents) need metadata that Xcode normally
# generates: the compiler records the intents' constant values, then
# appintentsmetadataprocessor turns them into Metadata.appintents.
mkdir -p build
PROTOCOLS="$PWD/build/appintents-protocols.json"
echo '["AppIntent","AppEntity","AppEnum","AppShortcutsProvider","AppShortcutProviding","EntityQuery","TransientEntity","DynamicOptionsProvider","AnyResolverProviding","AppIntentsPackage"]' > "$PROTOCOLS"
CONST=(-Xswiftc -emit-const-values -Xswiftc -Xfrontend -Xswiftc -const-gather-protocols-file -Xswiftc -Xfrontend -Xswiftc "$PROTOCOLS")
swift build -c release "${ARCHS[@]}" "${CONST[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" "${CONST[@]}" --show-bin-path)/MicroCAMApp"
APP="build/microCAM.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MicroCAMApp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# App icon, compiled by scripts/make-icon.sh (Assets.car for macOS 26, .icns for older).
cp Resources/AppIcon.icns Resources/Assets.car "$APP/Contents/Resources/"
# Translations: one <lang>.lproj per language (Localizable.strings, InfoPlist.strings).
cp -R Resources/*.lproj "$APP/Contents/Resources/"
# Shortcuts metadata, from the arm64 slice (the intents are the same on both).
CONSTVALS="$(find .build/apple -path '*Release/MicroCAMApp.build/Objects-normal/arm64/*' -name '*.swiftconstvalues' | head -1)"
[ -n "$CONSTVALS" ] || { echo "No const values for App Intents" >&2; exit 1; }
echo "$PWD/$CONSTVALS" > build/appintents-constvals.txt
find "$PWD/Sources/MicroCAMApp" -name '*.swift' > build/appintents-sources.txt
xcrun appintentsmetadataprocessor --quiet-warnings --no-app-shortcuts-localization \
    --output "$APP/Contents/Resources" \
    --toolchain-dir "$(dirname "$(dirname "$(dirname "$(xcrun --find swift)")")")" \
    --module-name MicroCAMApp --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
    --xcode-version "$(xcodebuild -version | awk '/Build version/ { print $3 }')" \
    --platform-family macOS --deployment-target 14.0 --target-triple arm64-apple-macos14.0 \
    --source-file-list build/appintents-sources.txt --swift-const-vals-list build/appintents-constvals.txt >/dev/null
[ -d "$APP/Contents/Resources/Metadata.appintents" ] || { echo "Metadata.appintents missing" >&2; exit 1; }
# Sparkle (updates), with its helpers; ditto keeps the framework's symlinks.
mkdir -p "$APP/Contents/Frameworks"
ditto "$(dirname "$BIN")/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/MicroCAMApp"

# Inside out, as Sparkle's documentation asks. The hardened runtime only with
# a real identity: under it an ad-hoc app can't load an ad-hoc framework.
IDENTITY="${SIGN_IDENTITY:--}"
# Local ad-hoc builds never update themselves: without the public key the
# updater stays off, so a development build isn't replaced by a release.
[ "$IDENTITY" = "-" ] && plutil -replace SUPublicEDKey -string "" "$APP/Contents/Info.plist"
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
