# Changelog

## 0.1.1 — 2026-09-30

- The camera format chosen in Settings is kept. Before, the capture session
  switched back to its own format (1920×1080 @ 60 fps on a Cam Link) after
  the first pause, so a lower resolution never saved any CPU.
- Opts out of Reactions hand-gesture detection too; macOS ran it on every
  frame although Reactions were off (~12 % → ~8 % CPU at 1080p60).
- MIT license.

## 0.1.0 — 2026-09-30

First release.

- Live preview straight to the GPU; the camera stops while the window is
  hidden, the screen is locked or the Mac sleeps. Opts out of macOS camera
  effects (Reactions, Center Stage).
- Photos, recordings with microphone narration (HEVC or H.264, no length
  limit, crash-safe), timelapse.
- Captures filed per job (repair order), optionally sorted by type; move
  captures to another job later without overwriting anything.
- Image adjustments per camera, digital zoom, grid, before/after compare.
- Share sheet and an optional generic webhook.
- Live stream to a browser or to microCAM on another Mac, with remote photos
  (PIN-protected) and annotations saved as a copy.
- English and Czech, with a language switch in Settings.
- Universal app (Apple Silicon and Intel), macOS 14 or later.
