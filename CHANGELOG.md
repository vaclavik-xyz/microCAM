# Changelog

## 0.5.3 — 2026-10-02

- The live stream is smooth on Wi-Fi: *Settings → Stream → Stream quality*
  is *Smooth* by default (1280 px, a third of the data), so a viewer gets
  about 15 frames a second instead of 4. *Sharp* sends full HD as before,
  for a fast network. Photos and videos keep full quality.
- The stream page keeps the picture's size while you draw: text sizes and
  colours open over it, and on a wide screen the tools and main actions
  share one row. With a mouse the buttons are smaller.
- *Take photo* on the stream page is hidden while no PIN is set on the
  camera computer, instead of showing a button that can't work.
- Viewer mode has native tools: *Draw* and *Take photo* in the window
  toolbar, the same drawing tools as on the camera Mac, and *Live view* and
  *Save as photo* after a photo. The subtitle shows live, photo or offline
  and the job.

## 0.5.2 — 2026-10-02

- Viewer: *Connect* to a camera computer found on the network did nothing.
  It connects now, and if the camera computer can't be reached the viewer
  says so and tries again.
- Release notes in the update window show as formatted text, not with
  asterisks.

## 0.5.1 — 2026-10-02

- The sidebar button is back next to the window buttons. In a narrow window
  0.5.0 moved it into the » menu at the right.
- Toolbar buttons are now chosen in *Settings → Preview* instead of
  *Customize Toolbar…*. *Image adjustments…* (⌘I) and *Timelapse…* (⌘⇧T)
  open even when their button is off.

## 0.5.0 — 2026-10-02

Your toolbar, Shortcuts and a phone for the overview shot.

- Customize the toolbar: right-click it and choose *Customize Toolbar…* to
  remove or move any button. Everything stays in the menu bar with its
  shortcut.
- *Settings → Preview* can hide the resolution under the camera name.
  Recording, timelapse and an agent at work still show there, and the
  recording dot is red now.
- Shortcuts actions: *Take photo*, *Start recording*, *Stop recording* and
  *Set job*, for the Shortcuts app, Spotlight and Siri, e.g. on a Stream
  Deck or a foot pedal. A photo or video comes back as a file the shortcut
  can send on.
- *File → Import from iPhone or iPad → Take Photo* saves a picture from the
  phone into the current folder: the whole device next to the microscope
  detail.
- With jobs on, *Find a job* at the top of the side panel lists older jobs
  with their file count and last day; a click switches to one.

## 0.4.0 — 2026-10-01

Drawing and text, live on the Mac and on photos.

- Draw on the live picture on the Mac: *Draw* in the toolbar (`D`, ⌘D)
  shows arrow, circle, pen, text, a pointer that fades after 2.5 s, four
  colours, undo and *Clear all* at the bottom of the preview. The drawing
  stays on its spot when you zoom. While something is drawn, a photo saves
  the original and a copy with the drawing (`…_2.jpg`), also for photos
  from another device or an AI agent; timelapse shots stay clean.
- Text in drawings on the stream page: the **T** tool places a label where
  you tap, in three sizes and the drawing colours. Tap a label to edit it,
  drag it to move it. Saved photos show it exactly there, with a dark
  outline so it reads on any board.
- Mark up photos right in microCAM: *Mark up…* in the side panel (right
  click, or the pen button for one selected photo) opens the system Markup
  editor with arrows, shapes, text and loupe. *Done* saves a new copy next
  to the photo (`…_2.jpg`); the original stays untouched.
- Space in the side panel opens the selected photos and videos in Quick
  Look, full size, and the arrow keys move on. With nothing selected, and
  anywhere else in the window, Space still takes a photo.

## 0.3.0 — 2026-10-01

AI agents can use the microscope.

- MCP server for AI agents (*Settings → Integrations*, off by default).
  Agents on other computers on your network can check the camera, look at
  the live picture without saving it, take photos, list and open recent
  captures, start and stop recording and set the job. *Copy configuration*
  gives the address and token ready for any MCP client. Requests need the
  token from Settings; an address that sends a wrong token 5 times is locked
  out for 5 minutes. What an agent does shows over the preview, and the
  window subtitle says *Agent is watching* while it pulls frames.
- On a phone in landscape, *Take photo* on the stream page fits its round
  button.

## 0.2.0 — 2026-09-30

Signed releases that update themselves, and a tidier main window.

- Releases are signed with Developer ID and notarized by Apple. macOS no
  longer warns on first launch and keeps the camera and microphone
  permission across updates.
- microCAM updates itself with Sparkle: *microCAM → Check for Updates…*,
  and automatic checks in *Settings → General*. It asks before installing.
  Coming from 0.1.x, install 0.2.0 by hand once.

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
- The About window has a short description, links to the source code and
  to report a problem, and the copyright; the Help menu links to GitHub.
- Cameras can be renamed in *Settings → Device*; an empty name brings back
  the camera's own.
- The status bar is gone. Messages show briefly over the picture, and errors
  stay until closed.
- Camera menu items have standard ⌘ shortcuts shown by macOS (⌘T photo,
  ⌘R record, ⌘' grid, ⌘+ / ⌘− / ⌘0 zoom, ⌘⇧T timelapse, ⌘I adjustments); the quick
  single keys still work.
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
