# microCAM — design

Date: 2026-09-29
Status: approved in conversation, pending written-spec review

## Purpose

microCAM is a small native macOS app for viewing, photographing and recording a
microscope camera at a board-repair bench. It replaces Plugable Digital Viewer,
which runs on Apple Silicon only through Rosetta, uses ~20 % CPU and ~340 MB RAM
continuously while left open for days, and produces stuttering videos after a
while.

The primary machine is **bench Mac** (Apple Silicon, macOS 26). The camera is a
Mechanic Super HD 8K connected over HDMI to an **Elgato Cam Link 4K**, which
macOS exposes as a standard UVC/AVFoundation device (1920×1080, up to 60 fps;
formats `420v`/`yuvs`). Nothing in the app is specific to this camera; any
AVFoundation video device must work.

### Success criteria

1. Live preview with no image adjustments uses low single-digit % CPU on
   bench Mac (baseline: Digital Viewer ~20 %).
2. When the window is minimized or fully occluded, the screen is locked or the
   Mac sleeps, the capture session is stopped and CPU use is ~0.
3. A 60-minute 1080p60 recording with microphone audio has no dropped frames
   (verified with `ffprobe` frame count vs. duration × fps), both without and
   with image adjustments enabled.
4. With jobs enabled (default), every photo and video is filed under a
   repair-order folder (or `_Nezařazeno`) so that a later CRM upload needs no
   manual file picking. With jobs disabled, files go directly into the root
   folder.
5. The app stays small: no third-party dependencies in v1, a focused feature
   set, and nothing running when it is not needed.

### Non-goals (v1)

- Windows or Linux support.
- CRM upload (phase 2, see below).
- Rotation, full-screen mode, freeze frame, annotations, customizable shortcuts.
- Uploading videos anywhere; videos are exported manually (YouTube, TikTok, …).

## Architecture

Swift + SwiftUI/AppKit on AVFoundation, Core Image and Metal. Minimum macOS 14.
Swift Package layout following `an existing print-agent app`:

- `MicroCAMCore` — pure logic, no AVFoundation UI: job codes, file naming,
  storage layout, moving files between jobs, settings model, adjustment
  parameters, timelapse scheduling. Fully unit-tested.
- `MicroCAMApp` — the app: capture engine, preview, recording, UI.
- `MicroCAMCoreTests` — unit tests for `MicroCAMCore`.

A script builds a signed `.app` bundle (ad-hoc signing is sufficient for local
use; camera and microphone usage descriptions in `Info.plist`).

### Components

**CaptureEngine** — owns the `AVCaptureSession`.
- Device discovery (`AVCaptureDevice.DiscoverySession`, external + built-in),
  hot-plug via connect/disconnect notifications.
- Selects device, `activeFormat` and frame rate; remembers the last choice per
  device.
- Audio input from the selected microphone, added only while recording.
- Lifecycle: stops the session when the window is minimized or its
  `occlusionState` is not visible, on screen lock and on system sleep; restarts
  on return. Never stops while recording.

**Preview** — two rendering paths, chosen automatically:
- *Passthrough* (all adjustments neutral): `AVCaptureVideoPreviewLayer`. No
  frame touches the CPU.
- *Adjusted*: `AVCaptureVideoDataOutput` → `CIImage` → adjustment filter chain
  → rendered by a `CIContext` backed by Metal directly into an `MTKView`
  drawable. No `CGImage` creation, no GPU→CPU readback.
- Digital zoom (scroll / pinch) and pan (drag) are view transforms on the
  preview only. Photos and videos are always full frame.
- Grid overlay (rule of thirds or fine grid, configurable color) is a separate
  layer, toggled with `G`; never recorded.

**Photo capture** — takes the latest frame, applies the current adjustments
(same filter chain as the preview), encodes JPEG at the configured quality and
writes it to the active job folder. Shortcut: `Space`.

**Recorder** — two paths matching the preview:
- *Passthrough*: `AVCaptureMovieFileOutput` with the camera and microphone
  inputs; hardware encoder; HEVC or H.264 per settings. No size or duration
  limit.
- *Adjusted*: `AVAssetWriter` fed from the data output; frames are rendered by
  the Metal `CIContext` into buffers from the adaptor's pixel-buffer pool, audio
  sample buffers appended alongside; `expectsMediaDataInRealTime = true`.
- The path is fixed at recording start; changing adjustments mid-recording
  updates the image only in the adjusted path (switching path mid-file is not
  supported; the UI states this).
- While recording, an `IOPMAssertion` prevents idle system sleep.
- Shortcut: `R` start/stop. The window shows elapsed time and a red indicator.

**Timelapse** — takes a photo every N seconds/minutes for a total duration,
into the active job folder. Secondary control, off by default.

**Jobs & storage (`MicroCAMCore`)**
- Active job: a free-text order code (e.g. `PR-260042`, `260042`) or "no job".
  Codes are validated/sanitized for use as folder names.
- Layout: `<root>/<code>/` and `<root>/_Nezařazeno/`.
- File names: `<code>_<yyyy-MM-dd_HH-mm-ss>[_n].jpg|.mov`. Files without a
  job live in `_Nezařazeno/` and use the `bez-zakazky_` prefix (the folder
  name is for the user, the prefix keeps file names ASCII). A numeric suffix
  resolves collisions.
- Jobs disabled (setting): no job folders; files are written directly to
  `<root>/microcam_<yyyy-MM-dd_HH-mm-ss>[_n].jpg|.mov`.
- Reassign: moving selected files to another job physically moves and renames
  them. Moves are atomic per file; failures are reported, never silently lost.
- **Folders by media type are the user's choice.** By default photos, videos
  and timelapse shots of one job share one folder; the only subfolders microCAM
  creates are job folders (and `_Nezařazeno/`), and with jobs disabled none at
  all. The setting "Sort by type" (off by default) adds `Fotky/`, `Videa/`,
  `Časosběr/` inside the job folder (or inside the root when jobs are
  disabled). The side panel and "Move to job…" work the same in both modes;
  a moved file keeps its type folder.
- The root folder is **chosen by the user on first launch** (folder picker,
  pre-filled with `~/Pictures/microCAM`) and can be changed in Settings. The
  app never picks a location silently. On bench Mac the user points it into
  iCloud Drive (`Repairs/Fotodokumentace/…`) so photos keep being backed up.
- The main window does not show the save path (it only takes space). A
  toolbar folder button opens the current save folder in Finder; the full path
  is shown in Settings → Storage next to "Change…" and "Show in Finder".

**Side panel** — thumbnails of the active job's photos and videos, newest
first, generated lazily and cached in memory with a small limit. Multi-select →
"Move to job…". Double-click opens the file in the default app. Selecting two
photos enables **Compare**: side-by-side view with a slider mode.

**Image adjustments** — brightness, contrast, saturation, white balance
(temperature + tint), gamma, sharpening; Reset. Stored as a preset per camera
(keyed by device unique ID) and applied automatically when that camera is
selected.

## Settings

| Section | Items |
|---|---|
| Device | camera, format (resolution, fps), microphone |
| Image | adjustments, per-camera preset, reset |
| Storage | root folder, sort by type (off), JPEG quality, video codec (HEVC / H.264), video quality |
| Timelapse | interval, total duration |
| Preview | grid type, grid color |
| Jobs | use jobs (on); when off, the job field and "Move to job…" are hidden and all files go straight into the root folder with the `microcam_` prefix |
| Behaviour | pause camera when window is hidden (on), prevent sleep while recording (on) |
| CRM (phase 2) | enable CRM integration (**off by default**); CRM URL, device pairing. When off, no CRM button, menu item or setting beyond this toggle is shown |

Settings persist in `UserDefaults`. Fixed shortcuts in v1: `Space` photo,
`R` record, `G` grid, `0` reset zoom; listed in the Help menu.

## Error handling

- Camera missing or disconnected: preview shows a clear message and a device
  picker; reconnect resumes automatically.
- Disconnect during recording: the file is finalized with what was captured and
  the user is told.
- Camera/microphone permission denied: message with a button to open System
  Settings.
- Storage root unavailable (e.g. iCloud folder missing): photos/recording are
  blocked with an error; nothing is written to an unexpected location.
- Disk space below a threshold before/while recording: warning; recording is
  stopped cleanly if space runs out.

## Testing

- Unit tests (`swift test`) for `MicroCAMCore`: code sanitization, file naming
  and collisions, storage layout, moving files between jobs (incl. failure
  cases), settings/preset encoding, timelapse scheduling.
- Manual acceptance on bench Mac, recorded in `docs/acceptance.md`:
  - CPU/energy of passthrough preview, adjusted preview, hidden window, versus
    Digital Viewer (Activity Monitor / `top`).
  - 60-minute 1080p60 recording with audio in both paths; `ffprobe` frame count
    and A/V sync check.
  - Unplug/replug Cam Link, sleep/wake, screen lock during preview and
    recording.

## Phase 2 — CRM upload (not in v1)

the CRM already supports this without new server features:
- Jobs are identified by `Job.code` (`{prefix}-{yy}{nnnn}`), looked up via
  `job.getByCode`.
- Photos upload via `job.uploadAttachmentFromBase64` on the API-key tRPC
  endpoint (`/api/ai/trpc`), with `photoCategory: REPAIR_PROGRESS`,
  `capturedAt`, `idempotencyKey`; images ≤ 10 MB (JPEG from 1080p fits easily).
- Device pairing and a Keychain-stored token can follow the
  `apps/print-agent-mac` pattern.
- Photos uploaded by microCAM must not become customer-visible automatically;
  verify how `source` maps to `customerVisible` before implementing.

v1 prepares for this only through the per-job folder layout and file naming.

CRM upload requires jobs to be enabled; files without a job code
(`_Nezařazeno/`, `microcam_…`) are never uploaded. The CRM toggle is disabled
while jobs are off.

The integration is optional and **off by default**, so microCAM stays a plain
camera app for anyone without the CRM. The upload button appears only
when it is enabled and paired.
