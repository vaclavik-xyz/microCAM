#!/usr/bin/env bash
# End-to-end check of a running stream. Usage: scripts/stream-smoke.sh <host> [port] [pin]
# Reads /status first and adapts: in "Jen obraz" mode, or with no PIN set on the
# bench, remote actions must be refused with 403 and the PIN checks are skipped.
# With controls + PIN on the bench it makes exactly 2 wrong-PIN attempts
# (lockout is 5; the cross-origin check is refused before the PIN is looked at),
# and with a PIN argument it also takes one real photo and reads it back.
set -uo pipefail
HOST="${1:?usage: scripts/stream-smoke.sh <host> [port] [pin]}"; PORT="${2:-8090}"; PIN="${3:-}"
BASE="http://$HOST:$PORT"
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (expected $3, got $2)"; fail=1; fi; }
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

check "status 200" "$(code "$BASE/status")" 200
status=$(curl -s "$BASE/status")
mode=$(echo "$status" | sed -n 's/.*"mode":"\([^"]*\)".*/\1/p')
photo_enabled=$(echo "$status" | grep -q '"photoEnabled":true' && echo yes || echo no)
echo "     mode=$mode photoEnabled=$photo_enabled"
frames=$(curl -s --max-time 3 "$BASE/stream" | grep -ac "Content-Type: image/jpeg")
[ "$frames" -ge 10 ] && echo "ok   stream ($frames frames in 3 s)" || { echo "FAIL stream ($frames frames in 3 s)"; fail=1; }
# The video feed: fragmented MP4 (ftyp first), then a moof per frame.
boxes=$(curl -s --max-time 3 "$BASE/video" | LC_ALL=C grep -aoE 'ftyp|moof')
vframes=$(echo "$boxes" | grep -c moof)
[ "$(echo "$boxes" | head -1)" = "ftyp" ] && [ "$vframes" -ge 30 ] && echo "ok   video ($vframes frames in 3 s)" \
    || { echo "FAIL video ($vframes frames in 3 s)"; fail=1; }
check "OPTIONS" "$(code -X OPTIONS "$BASE/photo")" 405

if [ "$mode" = "imageOnly" ]; then
    echo "skip PIN checks: bench is in Jen obraz mode"
    check "photo disabled" "$(code -X POST "$BASE/photo")" 403
    check "annotated disabled" "$(code -X POST "$BASE/annotated")" 403
    check "captures disabled" "$(code "$BASE/captures/..%2F..%2Fetc%2Fpasswd")" 403
elif [ "$photo_enabled" = "no" ]; then
    echo "skip PIN checks: no PIN set on the bench"
    check "GET photo" "$(code "$BASE/photo")" 405
    check "photo cross-origin" "$(code -X POST -H 'X-MicroCAM-PIN: 0' -H 'Origin: https://evil.example' "$BASE/photo")" 403
    check "photo without bench PIN" "$(code -X POST -H 'X-MicroCAM-PIN: 0000' "$BASE/photo")" 403
    check "captures without bench PIN" "$(code -H 'X-MicroCAM-PIN: 0000' "$BASE/captures/..%2F..%2Fetc%2Fpasswd")" 403
else
    check "GET photo" "$(code "$BASE/photo")" 405
    check "photo cross-origin" "$(code -X POST -H 'X-MicroCAM-PIN: 0' -H 'Origin: https://evil.example' "$BASE/photo")" 403
    check "photo without PIN" "$(code -X POST "$BASE/photo")" 401
    check "captures without PIN" "$(code "$BASE/captures/..%2F..%2Fetc%2Fpasswd")" 401
    if [ -n "$PIN" ]; then
        check "traversal" "$(code -H "X-MicroCAM-PIN: $PIN" "$BASE/captures/..%2F..%2Fetc%2Fpasswd")" 404
        body=$(curl -s -X POST -H "X-MicroCAM-PIN: $PIN" -H 'Content-Type: application/json' -d '{}' "$BASE/photo")
        echo "$body" | grep -q '"name"' && echo "ok   remote photo: $body" || { echo "FAIL remote photo: $body"; fail=1; }
        url=$(echo "$body" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p' | sed 's#\\/#/#g')
        check "fetch photo" "$(code -H "X-MicroCAM-PIN: $PIN" "$BASE$url")" 200
    else
        echo "skip remote photo: no PIN argument"
    fi
fi
exit $fail
