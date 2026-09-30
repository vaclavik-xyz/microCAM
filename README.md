<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/brand/logo-dark@2x.png">
    <img src="docs/brand/logo-light@2x.png" alt="microCAM" width="360">
  </picture>
</p>

# microCAM

**A small, native macOS app for the microscope camera at a repair bench.**
Live preview, photos, hour-long recordings with narration, timelapse, and
every capture filed under the job it belongs to. A *job* is a repair order:
the ticket or order number you already use for the repair.

![microCAM main window: live microscope image, toolbar and the side panel with the job's photos and videos](docs/images/microcam-window.jpg)

microCAM works with any camera macOS can see: USB/UVC microscopes and HDMI
cameras behind a capture card such as the Elgato Cam Link 4K. It was built
to replace Plugable Digital Viewer on an Apple Silicon Mac. That app is
Intel-only, left running all week it used ~20 % CPU, and its recordings
started to stutter after a while.

The app is in English and Czech and follows the system language; you can
also pick one in *Settings → General → Language*.

## Highlights

- **Light enough to leave open for days.** The preview goes from the camera
  straight to the GPU. The camera stops while the window is hidden, the
  screen is locked or the Mac sleeps. microCAM also opts out of macOS camera
  effects (Reactions, Center Stage) that would otherwise analyse every frame.
- **Recordings that don't stutter.** Hardware HEVC/H.264 encoding, narration
  from any microphone, no length limit. A crash-safe file is written while
  recording.
- **Files sorted per job.** Type the job code (`PR-260412`) and every photo
  and video lands in that job's folder. Misfiled shots can be moved later
  without overwriting anything.
- **Image adjustments per camera:** brightness, contrast, saturation, white
  balance, gamma and sharpening. They apply to the preview, photos and video
  alike, and cost nothing when switched off.
- **Digital zoom, grid, timelapse and before/after compare** (side by side or
  with a slider).
- **Live stream** to a browser or to microCAM on another Mac, with remote
  photos and drawing for showing the customer their board.
- **Integrations:** macOS share sheet, and an optional generic webhook for
  sending captures to your own system (your CRM, n8n, Make, Zapier…).
- **No third-party dependencies.** Swift, SwiftUI/AppKit and Apple
  frameworks only.

## Requirements

- macOS 14 or later, Apple Silicon or Intel
- Xcode command-line tools to build (`xcode-select --install`)

## Install

Download `microCAM-<version>.zip` from
[Releases](https://github.com/vaclavik-xyz/microCAM/releases), unzip it and
move `microCAM.app` to Applications. The app is not notarized, so the first
time open it with right-click → **Open** (or allow it in *System Settings →
Privacy & Security*).

## Build from source

```sh
scripts/make-app.sh                 # → build/microCAM.app (ad-hoc signed)
open build/microCAM.app             # or copy it to /Applications
scripts/deploy.sh <ssh-host> [dir]  # build → another Mac over ssh (universal)
```

Builds are ad-hoc signed, so macOS may ask for camera and microphone access
again after an update.

## Using it

On first launch microCAM asks where to save captures. It never picks a
folder on its own.

| Quick key | Menu shortcut | Action |
|---|---|---|
| `Space` | `⌘ T` | take a photo |
| `R` | `⌘ R` | start or stop recording |
| `G` | `⌘ '` | show or hide the grid |
| | `⌘ +` / `⌘ −` | zoom in / out |
| `0` | `⌘ 0` | reset zoom (or double-click the image) |
| | `⌘ ⇧ T` | timelapse |
| | `⌘ I` | image adjustments |
| scroll / pinch, drag | | zoom the preview, move the image |
| | `⌘ ,` | settings |

The quick keys are ignored while you type in a text field, so a job code
like `PR-2600` never triggers anything; the menu shortcuts work everywhere. Zoom and grid affect only the preview:
photos and videos are always full frame.

The window:

- **Toolbar.** Photo, video and timelapse sit together in the middle. Image
  adjustments and Settings are on the right, and the active job is on the
  left when jobs are on.
- **Side panel.** The captures of the current folder as thumbnails, grouped
  by day. Click selects, ⌘-click adds, ⇧-click selects a range, double-click
  opens, and you can drag a file into another app. The folder name at the top
  opens the folder; share and compare appear at the bottom once you select
  files. The panel remembers its
  width. Hide it with the button next to the window buttons.
- **Title.** The camera (rename it in *Settings → Device*) and its format.
  While recording it shows the running time instead, and the stop button is
  red; a running timelapse shows its progress.
- **Preview.** Short messages like *Saved: …* show at the bottom and hide on their own.
  Errors stay until you close them.

### Where files go

```
<root>/microcam_2026-09-25_14-02-11.jpg               # default: no jobs
<root>/PR-260412/PR-260412_2026-09-25_14-30-00.mov    # jobs on, job PR-260412
<root>/_Unsorted/no-job_2026-09-25_15-00-00.jpg       # jobs on, no job set
```

- Two captures in the same second get `_2`, `_3`. Nothing is ever
  overwritten.
- **Settings → Storage** has two switches:
  - *Use jobs* is off by default, and everything goes straight into
    `<root>` as `microcam_…`. Turn it on to give each job (repair order)
    its own folder; the job is then set from the toolbar.
  - Turn on *Sort by type*, and each job gets `Photos/`, `Videos/` and
    `Timelapse/` subfolders.
- Folder names follow the app language (the Czech names are in
  `Sources/MicroCAMCore/FolderLanguage.swift`). microCAM lists and moves
  files named in any of its languages, so switching the language never
  hides existing captures.
- Recordings are written to `~/Library/Application Support/microCAM/Recording/`
  and moved into place when finished, so iCloud never uploads a half-written
  file. If a leftover file is found after a crash, microCAM opens that folder.

## Integrations

- **Share.** The side panel's share button (AirDrop, Mail, Messages, …) is
  always available.
- **Webhook.** *Settings → Integrations*, off by default. Selected captures
  are sent one by one as a `multipart/form-data` `POST`:

  | Field | Value |
  |---|---|
  | `file` | the JPEG / MOV |
  | `job` | job code from the file name (left out without one) |
  | `kind` | `photo`, `video` or `timelapse` |
  | `capturedAt` | ISO 8601 |
  | `idempotencyKey` | SHA-256 of the file, also sent as the `Idempotency-Key` header |

  An optional token is sent as `Authorization: Bearer …` and kept in the
  Keychain. Any 2xx counts as success. Videos are sent only when *Send videos
  too* is on; uploads stream from disk, so hour-long videos are fine.

## Live stream and viewer

*Settings → Stream*, off by default. It streams the live image to other
devices on the shop network or tailnet. Open `http://<bench-ip>:8090/` in any
browser, or switch microCAM on another Mac to **Viewer** (*Settings → General
→ Mode*); it finds the camera computer via Bonjour.

- *Only watch*: just the picture, for a customer-facing screen.
- *Watch, draw and take photos*: job code, full screen, drawing over the live
  image, and **Take photo**. The photo is taken on the camera computer into
  the active job. Draw on it and **Save to job** saves a copy with the drawing
  (`…_2.jpg`); the original stays untouched. Remote photos need the *PIN for
  photos* set on the camera computer.

The page follows the browser's language (the viewer app passes its own).
Only local-network and Tailscale clients are accepted. Nothing listens while
the stream is off, and nothing is encoded while nobody watches.

## Development

```sh
swift test                          # unit tests (MicroCAMCore) and translation checks
scripts/make-app.sh                 # app bundle
scripts/make-icon.sh                # recompile the app icon (needs Xcode 26)
scripts/make-screenshots.sh <photos> [en|cs] [out-dir]   # screenshots in demo mode (no camera needed)
scripts/stream-smoke.sh <host> [port] [pin]              # check a running stream
scripts/stream-page-shots.py <url> <dir> --pin <pin> [--locale cs-CZ]   # stream page on phones/iPad/desktop (demo stream only)
```

Demo mode without a camera can also serve the stream on 127.0.0.1: set
`MICROCAM_DEMO_STREAM_PORT` (and optionally `MICROCAM_DEMO_STREAM_PIN`,
`MICROCAM_DEMO_STREAM_MODE=imageOnly`). The smoke script adapts to *Only
watch* and to a camera computer without a PIN. The page-shots script (Python
Playwright with WebKit) checks that every control is on screen, at least
44 px and not overlapping, and saves a screenshot per device and state.

- `Sources/MicroCAMCore` holds the pure logic: naming, storage, moving,
  settings, the image pipeline and policies. It is fully unit-tested.
- `Sources/MicroCAMApp` is the thin AVFoundation/SwiftUI layer.
- `Resources/<lang>.lproj` holds the translations.
- Design and plans live in `docs/superpowers/`. Measurements from the bench
  Mac go to `docs/acceptance.md`.
- Logo, app icon and social preview image live in `docs/brand/` (see its
  README for the colours and rules).
- The README image lives in `docs/images/`. `docs/screenshots/` is
  git-ignored because it may contain photos of customer boards.

## Contributing

Bug reports and pull requests are welcome. Keep the app free of third-party
dependencies, put logic that can be tested into `MicroCAMCore` with a test,
and run `swift test` before you open a pull request.

### Localization

English is the source language: texts are written in English in the code,
and every language has a folder in `Resources/`:

- `Localizable.strings`: the app's texts. The key is the English text.
- `InfoPlist.strings`: what macOS shows when it asks for camera, microphone
  and local-network access.

The stream page keeps its texts in the `STRINGS` dictionary in
`Sources/MicroCAMApp/Streaming/StreamPage.swift`.

Every new text must be in every language. `swift test` fails with the file,
line and key when one is missing, empty or left in English by accident.

To add a language (German, `de`, as an example):

1. Copy `Resources/en.lproj` to `Resources/de.lproj` and translate the values
   (the part after `=`). Keep placeholders such as `%@` and `%lld`.
2. Add `<string>de</string>` to `CFBundleLocalizations` in
   `Resources/Info.plist`.
3. Add a `"de": { … }` entry with the same keys to `STRINGS` in
   `StreamPage.swift`.
4. Run `swift test`. If a text should stay the same as in English (a product
   name, for example), add it to `sameAsEnglish` in
   `Tests/LocalizationTests/LocalizationTests.swift`.
5. Build with `scripts/make-app.sh` and check the screens with
   `scripts/make-screenshots.sh <photos> de <out-dir>`.

The language then appears in *Settings → General → Language* by itself.
New folders get English names unless `FolderLanguage`
(`Sources/MicroCAMCore/FolderLanguage.swift`) gets names for the language too.

## License

MIT, see [LICENSE](LICENSE).
