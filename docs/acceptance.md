# microCAM acceptance — bench Mac

Status: **in progress** — rows 2, 2a, 4 (recording case) and 6 measured on the bench Mac on 2026-09-30; the rest pending.

Date: … · macOS … · commit … · Cam Link 4K, 1920×1080 @ 60 fps

| # | Scenario | Target | Measured | Pass |
|---|----------|--------|----------|------|
| 1 | Plugable Digital Viewer, preview (baseline) | — | … % CPU, … MB | — |
| 2 | microCAM preview, no adjustments | low single-digit % CPU | 2026-09-30, bench Mac, Cam Link 1080p60, macOS 26.5: ~12 % with only `NSCameraReactionEffectsEnabled` off (sample showed Reactions hand-gesture detection on every frame); ~7.7 % with `NSCameraReactionEffectGesturesEnabledDefault` off too, no detection left in the sample | partly: better than the baseline, above target |
| 2a | Format chosen in Settings is kept (e.g. 640×480 @ 25 fps) | photos have that size; stays after window hide/show | 2026-09-30, bench Mac: before the fix the session reset it to 1920×1080 @ 60 (photo 1920×1080, UVCAssistant ~22 %); with the device lock held, photo 640×480, UVCAssistant ~5.5 % | yes |
| 3 | microCAM preview, adjustments on | clearly below baseline | | |
| 4 | Window minimized / covered | ~0 % | while recording the camera must keep running: before 0.1.2 a minimized window lost ~1 300 frames/min (App Nap + an undrawn preview layer); fixed, see row 6 | preview-only case pending |
| 5 | Screen locked 1 min | ~0 % | | |
| 6 | 60 min recording, no adjustments, narration | frames ≥ 99.5 % of duration×fps, dropped 0, A/V Δ ≤ 0.2 s | 2026-09-30, 0.1.2 build, HEVC 1080p60, USB microphone, window minimized most of the time: 72:11 min, 3.44 GB, 259 376 of 259 879 frames (99.81 %; ~500 missing, mostly in two bursts, the app's counter saw far fewer, so most were lost before the app), A/V Δ 0.011 s, microCAM 22–25 % CPU, memory 205 → 220 MB | yes |
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
  "Sleduje N" in the toolbar, CPU with and without a viewer on the real camera.
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
