# microCAM acceptance — bench Mac

Status: **pending** — measurements scheduled on the bench Mac for 2026-09-30.

Date: … · macOS … · commit … · Cam Link 4K, 1920×1080 @ 60 fps

| # | Scenario | Target | Measured | Pass |
|---|----------|--------|----------|------|
| 1 | Plugable Digital Viewer, preview (baseline) | — | … % CPU, … MB | — |
| 2 | microCAM preview, no adjustments | low single-digit % CPU | | |
| 3 | microCAM preview, adjustments on | clearly below baseline | | |
| 4 | Window minimized / covered | ~0 % | | |
| 5 | Screen locked 1 min | ~0 % | | |
| 6 | 60 min recording, no adjustments, narration | frames ≥ 99.5 % of duration×fps, dropped 0, A/V Δ ≤ 0.2 s | | |
| 7 | 60 min recording, adjustments on, narration | same as 6 | | |
| 8 | Cam Link unplugged mid-recording | file finalized and playable | | |
| 9 | Sleep/wake, unplug/replug during preview | image recovers without relaunch | | |
| 10 | Photo within same second ×2, timelapse + photo | distinct files, nothing overwritten | | |
| 11 | Storage root missing | clear error, nothing written | | |
| 12 | Memory after 8 h open (preview on, mostly idle) | stable, no growth trend | | |
| 13 | Stream on, no viewer | CPU same as #2 | | |
| 14 | Stream, 1 viewer in Safari (reception Mac) | + a few % CPU on bench, smooth image | | |
| 15 | Viewer mode on the reception Mac (Intel) | auto-connects, CPU on the reception Mac noted | | |
| 16 | Remote photo + annotated copy | files in job folder, original untouched | | |
| 17 | `stream-smoke.sh <bench-host> 8090` | all ok | | |
| 18 | Slow viewer (iPhone on weak Wi-Fi) + second viewer | second viewer and bench preview stay smooth | | |

### Streaming — pending on device

Rows 13–18 and the manual checks from the streaming plan (Tasks 6–8) need a
camera Mac and the viewer devices; none ran yet. Pending on device:

- Second Mac / bench Mac: incoming-connection and local-network prompts,
  "Sleduje N" in the status bar, CPU with and without a viewer on the real camera.
- Safari on Mac and iPad: page checks 1–6 (fade, drawing with touch, PIN
  prompt and lockout message, Jen obraz → 403, reconnect after a bench restart).
- Reception Mac (Intel): viewer mode — Bonjour discovery, auto-reconnect after
  relaunch, manual Tailscale URL, full screen on a chosen display, switch back
  to Kamera.

Checked locally without a camera (demo mode, 127.0.0.1, 3840×2160 still at
10 fps; 2026-09-30): `stream-smoke.sh` all ok, remote photo and annotated
copy (`…_2.jpg`) written next to the original, page flow in headless Chrome.
CPU of the demo process (includes its own frame feed and preview): ~3 % with
no viewer, ~7 % with one viewer.
