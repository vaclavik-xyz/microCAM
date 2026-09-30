# Live annotations — design

Date: 2026-10-01
Status: approved in conversation, pending written-spec review

## Purpose

Today annotations exist only on the stream page: shapes drawn over the live
picture stay in that one browser and vanish when a photo is taken, and a frozen
photo can be annotated and saved as a copy (`…_2.jpg`). The Mac itself can't
draw at all (PR #7 adds system Markup for finished photos).

The goal: the technician circles a spot in the live picture, and a customer or
colleague watching the stream sees it at once and can point back; a photo taken
then carries the annotation. Plus text in annotations everywhere.

## Decisions (from the conversation)

1. **Who draws on the live picture:** everyone — a shared board. Viewers in
   *Watch, draw and take photos* mode draw too, and the Mac sees their shapes.
2. **Video:** a setting *Annotations in videos*, off by default.
3. **Lifetime:** normal shapes stay until deleted; a **pointer** tool leaves a
   trail that fades after ~2.5 s.
4. **Permission:** a setting *Viewers can draw* (Settings → Stream), on by
   default, only in *Watch, draw and take photos* mode, no PIN. Remote photos
   keep needing the PIN. The Mac can switch viewer drawing off from its palette.
5. **Deleting:** everyone can undo and delete their own shapes; only the Mac
   can *Clear all*.
6. **Scope now:** the whole design is written down so the model is right from
   the start, but only stages 1–2 are planned and built. Stage 3 waits until the
   stream has been used in practice; stage 4 maybe never.

## Stages

| Stage | What | Ships alone |
|---|---|---|
| 1 | Text in annotations (web photo annotation, renderer) | yes |
| 2 | Live drawing on the Mac: board model, palette over the preview, annotated photo copies | yes |
| 3 | Shared board: server channel, web live drawing shared, viewer permissions | yes |
| 4 | Annotations in videos | yes |

## Model (MicroCAMCore)

`AnnotationShape` (existing) gains:

- `kind`: `arrow`, `ellipse`, `pen` (existing), **`text`**, **`pointer`**.
- `id` (string, client-generated UUID) and `author` (string: a random id per
  browser kept in localStorage, `"bench"` for the Mac). Optional in the JSON for
  backward compatibility with the photo endpoint.
- `text` (string, ≤ 200 characters, trimmed; required for `.text`) and
  `fontSize` (fraction of the image height, clamped 0.015…0.12). A text shape has
  one point: its top-left corner.

Coordinates stay normalized to the image (0…1, origin top-left), so shapes stay
on the board when the preview is zoomed and fit any output size.

`AnnotationRenderer` draws text in the shape colour with a dark outline (stroke
≈ 12 % of the font size) so it reads on any board; system font, semibold. Pointer
shapes are never rendered into files.

`AnnotationBoard` (new, pure, thread-safe, fully unit-tested):

- `add(_:)` (sanitized, same limits as today: 200 shapes, 5 000 points),
  `delete(id:by:)` and `undo(by:)` (own shapes only; `"bench"` may delete any),
  `clearAll(by:)` (only `"bench"`), `persistent` (all shapes except pointers).
- `revision` increments on every change; `changes(since:)` returns what a client
  missed or `.snapshot` when too old.
- Pointers expire `pointerLifetime` (2.5 s) after their last point; `prune(now:)`
  drops them. A pointer stroke is updated in place (same id) while it moves.
- Knows nothing of networking or UI.

## Stage 1 — text

- Web photo annotation gets a **T** tool: tap/click places a text field at that
  point, Enter or tapping elsewhere commits, Escape cancels. Tapping an existing
  text with the T tool edits it; dragging it moves it. Colour from the current
  swatch; size from a small/medium/large choice.
- `/annotated` accepts text shapes; the renderer draws them.
- Tests: sanitizing text (length, empty, control characters), renderer output
  size unchanged, text within bounds.

## Stage 2 — drawing on the Mac

- Toolbar button **Draw** (key `D`, menu *Camera → Draw* ⌘D) toggles a palette
  floating at the bottom of the preview: arrow, circle, pen, text, pointer,
  4 colours, undo, delete own, **Clear all**. Esc leaves drawing mode. While
  drawing, drags draw instead of panning; scroll/pinch still zoom.
- An overlay (SwiftUI `Canvas` or a CAShapeLayer view) draws the board above the
  preview in image coordinates, following the zoom transform; nothing is drawn
  and no timer runs when the board is empty.
- **Photos:** when `board.persistent` is non-empty, a photo (button, Space, web,
  MCP agent) saves the original and, next to it, a copy with the annotations
  (`CaptureFileNamer.editedCopyURL`, `…_2.jpg`). Timelapse shots stay clean. The
  toast names both files.
- The board lives in `AppModel` (one per app); it is cleared when the camera
  changes. Nothing is persisted across launches.

## Stage 3 — shared board

Transport: **Server-Sent Events** for board updates plus small POSTs, on the
existing stream server. Chosen over burning shapes into the MJPEG frames (per-frame
cost, lag, no smooth pointer) and over WebSockets (framing to implement without
dependencies, no gain).

- `GET /annotations/events` — `text/event-stream`: first a `snapshot` event
  (revision + shapes), then `change` events (`add`/`update`/`delete`/`clear` with
  the new revision). Heartbeat comment every 15 s. On reconnect the client sends
  `Last-Event-ID` and gets the missed changes or a snapshot.
- `POST /annotations` (add or update own shape), `DELETE /annotations/<id>`
  (own), `POST /annotations/undo`. Allowed only in controls mode with *Viewers can
  draw* on; otherwise 403. Per-address rate limit (e.g. 30 requests/s, pointer
  updates coalesced client-side to ~20/s). Same access policy as the stream
  (local network and Tailscale only).
- Finished shapes are sent on pointer-up; only the pointer streams its points.
- Web: live mode draws into the shared board; undo/delete act on own shapes;
  *Clear* on the web deletes own shapes (label says so). When drawing is not
  allowed the tools are hidden and the board is shown read-only.
- Mac palette: switch *Viewers can draw*; the window subtitle shows *Viewer is
  drawing* briefly when a viewer adds a shape.
- The Viewer app (WKWebView) gets all of this from the page.
- No SSE connection → no work; the board is kept only in memory.

## Stage 4 — annotations in videos

- Setting *Annotations in videos* (Settings → Storage, video section), off.
- When on and the board has persistent shapes, the recorder uses the GPU path
  (`AdjustmentPipeline`) and composites the board, pre-rendered to a CIImage
  whenever `revision` changes (not per frame). Pointers are included in video.
- When off, or the board is empty, recording is unchanged (zero-copy path).

## Performance and limits

- Empty board: no overlay drawing, no timers, no SSE traffic.
- Pointer trails: capped at 200 points each, 5 pointers.
- Board changes are applied on the main queue; the renderer runs off it.

## Testing

- Core: `AnnotationBoard` (ownership, clear-all rights, revisions,
  `changes(since:)`, pointer expiry, limits), text sanitizing and rendering,
  SSE event encoding, request validation.
- Stream: `scripts/stream-page-shots.py` gains the text tool and, for stage 3,
  two browser contexts checking that a shape drawn in one appears in the other.
- Mac: demo-mode screenshots of the palette and an annotated photo copy.

## Out of scope

- Tracking the board when it moves under the microscope.
- Saving the board across launches, per-job boards, history.
- Named authors or cursors of other viewers.
