# Changelog

## Unreleased

A tidier main window.

- The side panel is a grid of thumbnails grouped by day and remembers its
  width. Hide it with the sidebar button.
- Photo, video and timelapse are one group in the middle of the toolbar.
  Settings has its own button. The side panel shows the current folder at
  the top (click to open it) and a bar with share, compare and more only
  while files are selected.
- The area around the picture follows the window colour instead of black.
  It stays black in full screen.
- The window title shows the camera and its format. While recording, the
  subtitle shows the running time (and dropped frames) and the stop button
  turns red; the picture itself stays clean. A running timelapse shows its
  progress there too.
- Cameras can be renamed in *Settings → Device*; an empty name brings back
  the camera's own.
- The status bar is gone. Messages show briefly over the picture, and errors
  stay until closed.
- Jobs are off by default. Turn them on in *Settings → Storage*; the active
  job is then set from the toolbar. Existing settings keep their choice.

## 0.1.2 — 2026-09-30

Fixes found in a one-hour test recording on a bench Mac.

- Recordings with sound from a USB microphone failed the moment they
  started. The audio is now captured in a format the writer accepts.
- With the microphone left on "System default", recordings had no sound and
  no warning. They now use the system's default microphone.
- A minimized window no longer drops frames from a recording (it lost about
  a third of them): microCAM opts out of App Nap while recording, running a
  timelapse or streaming to a viewer, and stops feeding the hidden preview.
- The dropped-frame counter also counts frames the camera pipeline drops.
- Error messages include the error code, and a recording is no longer
  deleted when writing fails part-way.

A one-hour 1080p60 recording with narration: 99.8 % of frames, sound in
sync within 11 ms.

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
