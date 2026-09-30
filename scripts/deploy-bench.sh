#!/usr/bin/env bash
# Deploy to bench Mac:/Applications (see scripts/deploy.sh).
exec "$(dirname "$0")/deploy.sh" bench-mac /Applications
