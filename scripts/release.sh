#!/usr/bin/env bash
# Publish a release: Developer ID build with the hardened runtime, notarized
# and stapled, zipped, signed for Sparkle (EdDSA), appcast.xml, GitHub release.
# Run on main with a clean tree, after bumping the version in Info.plist and
# adding its section to CHANGELOG.md ("## 0.2.0 — …").
#
# One-time setup on the release Mac:
#   - "Developer ID Application" certificate in the login keychain
#   - xcrun notarytool store-credentials microcam-notary   (Apple ID + app-specific password)
#   - the Sparkle EdDSA private key in ~/.config/microcam/sparkle-ed25519.key
#     (or SPARKLE_KEY_FILE), mode 600. Created with
#     .build/sparkle-tools/bin/generate_keys --account microcam, exported with
#     -x; its public key is SUPublicEDKey in Resources/Info.plist. A file,
#     because macOS blocks Sparkle's tools from the keychain in scripts. Back it
#     up: without it no installed copy can be updated.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
TAG="v$VERSION"
REPO="vaclavik-xyz/microCAM"
IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-microcam-notary}"
SPARKLE_VERSION="2.10.0"   # keep in sync with Package.swift
TOOLS=".build/sparkle-tools"
KEY_FILE="${SPARKLE_KEY_FILE:-$HOME/.config/microcam/sparkle-ed25519.key}"

[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "Run on main." >&2; exit 1; }
git diff --quiet && git diff --cached --quiet || { echo "Commit your changes first." >&2; exit 1; }
[ -n "$(plutil -extract SUPublicEDKey raw Resources/Info.plist)" ] || { echo "SUPublicEDKey is empty (see setup above)." >&2; exit 1; }
[ -r "$KEY_FILE" ] || { echo "No Sparkle key at $KEY_FILE (see setup above)." >&2; exit 1; }
NOTES="$(awk -v v="$VERSION" '$0 ~ "^## "v" " {on=1; next} on && /^## / {exit} on' CHANGELOG.md)"
[ -n "$NOTES" ] || { echo "CHANGELOG.md has no section for $VERSION." >&2; exit 1; }
gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 && { echo "$TAG already exists." >&2; exit 1; }

if [ ! -x "$TOOLS/bin/sign_update" ]; then
    mkdir -p "$TOOLS"
    curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" | tar -xJ -C "$TOOLS"
fi

swift test
SIGN_IDENTITY="$IDENTITY" scripts/make-app.sh

OUT="build/release"
rm -rf "$OUT" && mkdir -p "$OUT"
ZIP="$OUT/microCAM-$VERSION.zip"
ditto -c -k --keepParent build/microCAM.app "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple build/microCAM.app
spctl --assess --type execute --verbose build/microCAM.app
# Zip again: the published archive must contain the stapled ticket.
rm "$ZIP" && ditto -c -k --keepParent build/microCAM.app "$ZIP"

# Release notes shown by the updater, next to the archive with the same name.
printf '%s\n' "$NOTES" > "$OUT/microCAM-$VERSION.txt"
"$TOOLS/bin/generate_appcast" --ed-key-file "$KEY_FILE" --embed-release-notes \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" "$OUT"

git tag "$TAG" && git push origin "$TAG"
gh release create "$TAG" "$ZIP" "$OUT/appcast.xml" --repo "$REPO" --title "microCAM $VERSION" --notes "$NOTES"
echo "Released $TAG"
