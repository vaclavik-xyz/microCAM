# microCAM acceptance — bench Mac

Status: **pending** — measurements scheduled on bench Mac for 2026-09-30.

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
