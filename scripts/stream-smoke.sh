#!/usr/bin/env bash
# End-to-end check of a running stream. Usage: scripts/stream-smoke.sh <host> [port] [pin]
# With a PIN it also takes one real photo on the host and reads it back.
# Without a PIN it makes exactly 2 wrong-PIN attempts (lockout is 5).
set -uo pipefail
HOST="${1:?usage: scripts/stream-smoke.sh <host> [port] [pin]}"; PORT="${2:-8090}"; PIN="${3:-}"
BASE="http://$HOST:$PORT"
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (expected $3, got $2)"; fail=1; fi; }

check "status 200" "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/status")" 200
frames=$(curl -s --max-time 3 "$BASE/stream" | grep -ac "Content-Type: image/jpeg")
[ "$frames" -ge 10 ] && echo "ok   stream ($frames frames in 3 s)" || { echo "FAIL stream ($frames frames in 3 s)"; fail=1; }
check "photo without PIN" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/photo")" 401
check "photo cross-origin" "$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'X-MicroCAM-PIN: 0' -H 'Origin: https://evil.example' "$BASE/photo")" 403
check "GET photo" "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/photo")" 405
check "captures without PIN" "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/captures/..%2F..%2Fetc%2Fpasswd")" 401
check "OPTIONS" "$(curl -s -o /dev/null -w '%{http_code}' -X OPTIONS "$BASE/photo")" 405
if [ -n "$PIN" ]; then
    check "traversal" "$(curl -s -o /dev/null -w '%{http_code}' -H "X-MicroCAM-PIN: $PIN" "$BASE/captures/..%2F..%2Fetc%2Fpasswd")" 404
    body=$(curl -s -X POST -H "X-MicroCAM-PIN: $PIN" -H 'Content-Type: application/json' -d '{}' "$BASE/photo")
    echo "$body" | grep -q '"name"' && echo "ok   remote photo: $body" || { echo "FAIL remote photo: $body"; fail=1; }
    url=$(echo "$body" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p' | sed 's#\\/#/#g')
    check "fetch photo" "$(curl -s -o /dev/null -w '%{http_code}' -H "X-MicroCAM-PIN: $PIN" "$BASE$url")" 200
fi
exit $fail
