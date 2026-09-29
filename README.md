# microCAM

Small native macOS app for a microscope camera at the repair bench: live
preview, photos, long recordings with narration, timelapse, and files sorted
per repair order. Works with any camera macOS sees (USB/UVC, HDMI capture
cards such as Elgato Cam Link).

## Screenshots

Screenshots are not committed (they show photos of customer boards). Generate
them locally into `docs/screenshots/` (git-ignored) with
`scripts/make-screenshots.sh <photos>` — demo mode, no camera or permissions
needed; see the script header for the expected photo folder layout.

## Build and install

    scripts/make-app.sh              # build/microCAM.app (Apple Silicon, ad-hoc signed)
    scripts/deploy-bench.sh       # copy to bench Mac:/Applications

Requires macOS 14+ and Xcode command-line tools. Ad-hoc signing means macOS
may ask for camera/microphone access again after an update.

## Using it

- Space – photo · R – record/stop · G – grid · 0 – reset zoom
- Scroll or pinch to zoom the preview, drag to pan (photos and videos are always full frame)
- Toolbar: photo, record, timelapse, image adjustments (saved per camera)
- Side panel: captures of the active job; double-click opens, "Přesunout…" moves to another job, "Porovnat" compares two photos

## Integrations

- **Sdílet** (side panel, always available): the macOS share sheet — AirDrop,
  Mail, Messages, Notes and any app that accepts files.
- **Webhook** (Settings → Integrace, off by default): selected captures are
  sent one by one as `multipart/form-data` `POST` to your URL:

  | field | value |
  |---|---|
  | `file` | the JPEG / MOV (`image/jpeg`, `video/quicktime`) |
  | `job` | repair-order code from the file name (omitted without a job) |
  | `kind` | `photo`, `video` or `timelapse` |
  | `capturedAt` | ISO 8601 from the file name |
  | `idempotencyKey` | SHA-256 of the file (also the `Idempotency-Key` header) |

  An optional token is sent as `Authorization: Bearer <token>` and stored in
  the Keychain. Any 2xx counts as success. Videos are sent only when
  "Posílat i videa" is on. Works with an own server, n8n, Make, Zapier, or a
  receiving endpoint in the CRM.

## Where files go

You choose the root folder on first launch; microCAM never picks one itself.

    <root>/PR-260042/PR-260042_2026-09-29_14-03-12.jpg
    <root>/_Nezařazeno/bez-zakazky_2026-09-29_14-05-00.mov

Settings → Ukládání: turn jobs off (everything goes into `<root>` as
`microcam_…`) or turn on sorting by type (`Fotky/`, `Videa/`, `Časosběr/`).
Nothing is ever overwritten; same-second captures get `_2`, `_3`.

Recordings are written to `~/Library/Application Support/microCAM/Recording/`
and moved into place when finished. If microCAM finds a leftover file there on
launch (crash, power loss) it opens that folder; the file is playable up to
the last 10 seconds.

## Development

    swift test        # MicroCAMCore unit tests

Design: `docs/superpowers/specs/2026-09-29-microcam-design.md`.
Measured results: `docs/acceptance.md`.
