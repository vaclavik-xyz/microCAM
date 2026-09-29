#!/usr/bin/env bash
# Copy build/microCAM.app to bench Mac:/Applications, quitting a running copy first.
set -euo pipefail
cd "$(dirname "$0")/.."
test -d build/microCAM.app || { echo "run scripts/make-app.sh first" >&2; exit 1; }
ssh bench-mac 'osascript -e "tell application \"microCAM\" to quit" >/dev/null 2>&1 || true; sleep 1'
rsync -a --delete build/microCAM.app bench-mac:/Applications/
echo "Deployed. Launch on bench Mac: ssh bench-mac 'open -a microCAM'"
