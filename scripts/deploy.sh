#!/usr/bin/env bash
# Copy build/microCAM.app to <host>:<dir> (default ~/Applications), quitting a
# running copy first and re-registering it so Info.plist changes apply.
# Usage: scripts/deploy.sh <ssh-host> [/Applications]
set -euo pipefail
cd "$(dirname "$0")/.."
HOST="${1:?usage: scripts/deploy.sh <ssh-host> [dir]}"
DIR="${2:-Applications}"
test -d build/microCAM.app || { echo "run scripts/make-app.sh first" >&2; exit 1; }
ssh "$HOST" 'osascript -e "tell application \"microCAM\" to quit" >/dev/null 2>&1 || true; sleep 1'
ssh "$HOST" "mkdir -p \"$DIR\""
rsync -a --delete build/microCAM.app "$HOST:$DIR/"
ssh "$HOST" "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f \"$DIR/microCAM.app\""
echo "Deployed to $HOST:$DIR/microCAM.app — launch: ssh $HOST 'open \"$DIR/microCAM.app\"'"
