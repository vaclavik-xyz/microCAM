# Live annotations, stages 1–2 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Text in annotations (web photo annotation + renderer) and live drawing on the Mac over the preview, with annotated photo copies.

**Architecture:** `AnnotationShape` gains `text`/`pointer` kinds and optional `id`/`author`/`text`/`fontSize`; per-shape sanitizing moves onto the shape so the photo endpoint and the new `AnnotationBoard` share it. `AnnotationRenderer` gets a context-level `draw` used both for files and for the Mac overlay (what you see is what the photo gets). The Mac overlay is an `NSView` above the preview that maps normalized image points through `PreviewGeometry` (aspect fit + `ZoomState`), both pure and tested in `MicroCAMCore`.

**Tech Stack:** Swift 6 / SwiftPM, CoreGraphics + CoreText (renderer), AppKit + SwiftUI (overlay, palette), vanilla JS in `StreamPage.swift`, Python Playwright (`scripts/stream-page-shots.py`).

**Spec:** `docs/superpowers/specs/2026-10-01-live-annotations-design.md` (stages 3–4 are not built here, but the model is shaped for them).

## Global Constraints

- No new dependencies (Sparkle stays the only one). `swift test` must pass.
- Pure logic in `Sources/MicroCAMCore` with unit tests; `Sources/MicroCAMApp` stays thin.
- Every new UI text in English and Czech: `Resources/{en,cs}.lproj/Localizable.strings` and every language of `STRINGS` in `StreamPage.swift`. Czech uses "ty"; English sentence case; no hard-coded Czech in Swift.
- Coordinates normalized to the image (0…1, origin top-left).
- Text: ≤ 200 characters, trimmed, required for `.text`; `fontSize` fraction of image height clamped 0.015…0.12; one point = top-left corner.
- Limits stay: 200 shapes, 5 000 points; pointer trails ≤ 200 points, ≤ 5 pointers; pointers expire 2.5 s after their last point and are never rendered into files.
- Empty board: no overlay drawing, no timers.
- Webhook/API field names are not renamed; `/annotated` stays backward compatible (old JSON without `id`/`author`/`text`/`fontSize` decodes).
- Never commit machine names, Tailscale addresses or tailnet host names.

## Review Focus

1. **Old `/annotated` JSON** (no `id`, `author`, `text`, `fontSize`) must decode and render as before → test in Task 1.
2. **Text near the right/bottom edge** must stay fully inside the photo, not be cut off → `AnnotationTextLayout.origin` test in Task 2 and the same clamp in JS.
3. **Zoomed preview:** a click at a view point must map to the same image point the overlay draws there, at any zoom/pan and window aspect → `PreviewGeometry` round-trip tests in Task 6.
4. **Typing on the Mac while drawing:** D, R, G, 0 and Space typed into the text field must go into the text, and Esc must cancel the text, not leave drawing mode → `ShortcutAction` test (editing text → nil) in Task 6; `KeyboardMonitor` already treats `NSText` first responders as editing.
5. **Timelapse / empty board photos** must stay single clean files → `photoShapes(for:)` test in Task 5.

---

## Decisions beyond the spec (ledger)

| # | Decision | Why |
|---|---|---|
| D1 | Text sizes: small 0.03, medium 0.045 (default), large 0.07 of image height (`AnnotationTextSize`). | Readable on 1080p–4K boards; inside the spec's 0.015…0.12 clamp. |
| D2 | Text layout constants shared by Swift and JS: line box = 1.2 × size, baseline 0.9 × size below the top, outline = 0.12 × size (drawn under the fill, dark `#000` at 75 %). The text box is shifted so it stays inside the image. | Same position in browser and file; nothing is cut off at the edge. |
| D3 | Text sanitizing: newlines/tabs become spaces, other control characters (Cc, Cf except ZWJ) are removed, whitespace trimmed, cut to 200 characters (grapheme clusters); empty → shape dropped. | Single-line labels; no invisible junk in files. |
| D4 | `id`/`author` accepted only as 1–64 chars of `[A-Za-z0-9_-]`, otherwise dropped (nil). The board assigns a UUID when `id` is missing and rejects shapes without an author. | Safe for stage 3 SSE ids; backward compatible for `/annotated`. |
| D5 | Web: text tool also works in live mode (local drawing, as the other tools); the editor font is at least 16 px while typing (iOS would zoom and a 6 px field is unusable), the shape keeps its real size. | Same tools in both modes; usable on phones. |
| D6 | Web text size: a small panel with three "A" buttons appears above the palette while the T tool is active (reserved like the palette, so it never covers the image). Separators hide below 400 px width / 380 px landscape height so seven tools fit the iPhone SE. | 44 px targets without overflowing the smallest phone. |
| D7 | Mac palette: arrow, circle, pen, text, pointer · 4 colours · text size (only with the text tool) · undo · Clear all. **Delete mine** (spec: "delete own") is implemented in the core (`deleteAll(by:)`) but its button waits for stage 3: with only the Mac drawing it would do exactly what Clear all does. | HIG: no duplicate controls. |
| D8 | Mac: no ⌘Z for drawing undo (it would steal ⌘Z from the text field in the same window); undo is the palette button. The Camera menu gets *Draw* (⌘D, checkmark) and *Clear drawing*, so palette actions are reachable from the menu bar. | HIG menu rule; no shortcut conflicts. |
| D9 | Drawing off keeps the board visible (and still in photos); only the palette hides. Esc leaves drawing mode unless a text is being typed (then Esc cancels the text). | Spec: shapes stay until deleted; photos carry them. |
| D10 | In-progress strokes live only in the overlay until mouse-up; pointer strokes are written to the board on every move (same id), as stage 3 will stream them. | Matches the stage 3 protocol. |
| D11 | Pointer fade: full opacity until 2.0 s after the last point, then linear to 0 at 2.5 s. A 30 Hz timer runs only while pointers exist. | Visible fade, zero cost otherwise. |
| D12 | Photo with drawing: the original is saved first, then the copy is rendered from the saved JPEG (same path as `/annotated`); shapes are snapshotted when the photo is taken. Web/MCP callers still get the original's name. Toast: "Saved: A, with drawing: B" (and the remote/agent variants). | Original never altered; API unchanged. |
| D13 | Board is cleared when the selected camera id changes (not when the same camera reconnects). | Spec: cleared on camera change. |
| D14 | Mac cursor: crosshair while drawing, I-beam with the text tool; clicking an existing text with the T tool edits it, dragging it moves it. | Same as the web tool. |

---

## File structure

- Modify `Sources/MicroCAMCore/Streaming/Annotation.swift` — shape model, sanitizing, text layout, renderer.
- Create `Sources/MicroCAMCore/Streaming/AnnotationBoard.swift` — the board.
- Create `Sources/MicroCAMCore/PreviewGeometry.swift` — image ↔ view mapping with zoom.
- Modify `Sources/MicroCAMCore/ShortcutAction.swift` — D and Esc.
- Modify `Sources/MicroCAMApp/Streaming/StreamPage.swift` — T tool, sizes, STRINGS.
- Create `Sources/MicroCAMApp/Preview/AnnotationOverlayView.swift` — overlay, mouse, text editor.
- Create `Sources/MicroCAMApp/Views/DrawingPalette.swift` — SwiftUI palette.
- Modify `PreviewContainerView.swift`, `ContentView.swift`, `MicroCAMApp.swift`, `AppModel.swift`, `KeyboardMonitor.swift`, `DemoMode.swift`.
- Tests: `AnnotationTests.swift`, new `AnnotationBoardTests.swift`, `PreviewGeometryTests.swift`, `ShortcutActionTests.swift`.
- Scripts: `scripts/stream-page-shots.py` (text state), `scripts/make-screenshots.sh` (unchanged unless needed).
- Docs: `README.md`, `CHANGELOG.md`, this plan.

---

# Stage 1 — text in annotations

### Task 1: Shape model and sanitizing

**Files:** Modify `Sources/MicroCAMCore/Streaming/Annotation.swift`; Test `Tests/MicroCAMCoreTests/AnnotationTests.swift`

**Interfaces — Produces:**
```swift
public struct AnnotationShape {
    public enum Kind: String, Codable, Sendable { case arrow, ellipse, pen, text, pointer }
    public var id: String?; public var author: String?; public var text: String?; public var fontSize: Double?
    public init(kind:points:color:width:id:author:text:fontSize:)   // new params default nil
    public static let maxTextLength = 200
    public static let fontSizeRange: ClosedRange<Double> = 0.015...0.12
    public static let maxPointerPoints = 200
    public static func cleanText(_ raw: String?) -> String?      // D3
    public static func cleanID(_ raw: String?) -> String?        // D4
    public func sanitized(pointBudget: Int) -> AnnotationShape?  // nil = drop
}
public enum AnnotationTextSize: String, CaseIterable, Sendable { case small, medium, large; public var fontSize: Double }
```
`AnnotationRequest.sanitized()` calls `shape.sanitized(pointBudget:)` and subtracts `points.count`.

- [ ] **Step 1: failing tests** — add to `AnnotationTests`:
```swift
func testOldJSONWithoutNewFieldsDecodes() throws {
    let json = #"{"source":"a.jpg","shapes":[{"kind":"arrow","points":[{"x":0,"y":0},{"x":1,"y":1}],"color":"#ff0000","width":0.01}]}"#
    let r = try JSONDecoder().decode(AnnotationRequest.self, from: Data(json.utf8)).sanitized()
    XCTAssertEqual(r.shapes.count, 1); XCTAssertNil(r.shapes[0].id); XCTAssertNil(r.shapes[0].text)
}
func testTextShapeSanitizing() {
    let long = String(repeating: "é", count: 250)
    let s = AnnotationShape(kind: .text, points: [.init(x: 1.4, y: -0.2), .init(x: 0.5, y: 0.5)], color: "#ffd60a",
                            width: 0.006, text: "  C12\tshort\n\u{0007}ed  ", fontSize: 0.5)
    let clean = s.sanitized(pointBudget: 10)!
    XCTAssertEqual(clean.points, [.init(x: 1, y: 0)])
    XCTAssertEqual(clean.text, "C12 short ed")
    XCTAssertEqual(clean.fontSize, 0.12)
    XCTAssertEqual(AnnotationShape.cleanText(long)?.count, 200)
    XCTAssertNil(AnnotationShape(kind: .text, points: [.init(x: 0, y: 0)], color: "#fff000", width: 0.01,
                                 text: " \n\u{0007} ").sanitized(pointBudget: 10))
    XCTAssertEqual(AnnotationShape(kind: .text, points: [.init(x: 0, y: 0)], color: "#fff000", width: 0.01,
                                   text: "x").sanitized(pointBudget: 10)?.fontSize, AnnotationTextSize.medium.fontSize)
    XCTAssertEqual(AnnotationShape(kind: .text, points: [.init(x: 0, y: 0)], color: "#fff000", width: 0.01,
                                   text: "x", fontSize: 0.001).sanitized(pointBudget: 10)?.fontSize, 0.015)
}
func testTextOnNonTextShapeIsDroppedAndIDsAreChecked() {
    let s = AnnotationShape(kind: .pen, points: [.init(x: 0, y: 0), .init(x: 1, y: 1)], color: "#123456", width: 0.01,
                            id: "abc-1_2", author: "bad id!", text: "x", fontSize: 0.05).sanitized(pointBudget: 10)!
    XCTAssertEqual(s.id, "abc-1_2"); XCTAssertNil(s.author); XCTAssertNil(s.text); XCTAssertNil(s.fontSize)
    XCTAssertNil(AnnotationShape.cleanID(String(repeating: "a", count: 65)))
}
func testPointerKeepsItsLatestPoints() {
    let pts = (0..<300).map { AnnotationPoint(x: Double($0) / 300, y: 0.5) }
    let s = AnnotationShape(kind: .pointer, points: pts, color: "#ff3b30", width: 0.006).sanitized(pointBudget: 5_000)!
    XCTAssertEqual(s.points.count, 200); XCTAssertEqual(s.points.last, pts.last)
}
```
- [ ] **Step 2:** `swift test --filter AnnotationTests` → FAIL (no `.text`, no new init params).
- [ ] **Step 3: implement** — `Kind` gains `text, pointer`; new optional stored properties (synthesized Codable uses `decodeIfPresent` for optionals); `cleanText`: map each `Character` — `\n`, `\r`, `\t` → space; drop characters whose scalars are all in `CharacterSet.controlCharacters` (keeping U+200D); trim `.whitespacesAndNewlines`; `String(prefix(200))`; empty → nil. `cleanID`: regex `^[A-Za-z0-9_-]{1,64}$`. `sanitized(pointBudget:)`: clamp points; `.text` → first point only, needs `cleanText`, `fontSize` clamped (default medium), otherwise `text`/`fontSize` = nil; `.pointer` → suffix(200); `.arrow/.ellipse` → first+last; `.pen` as before; needs ≥ 2 points for non-text and `count <= pointBudget`; width/colour clamp as before; `id`/`author` through `cleanID`.
- [ ] **Step 4:** tests pass (old sanitizing tests too).
- [ ] **Step 5:** commit `feat(core): text and pointer annotation shapes with ids`.

### Task 2: Text layout and rendering

**Files:** Modify `Annotation.swift`; Test `AnnotationTests.swift`

**Interfaces — Produces:**
```swift
public enum AnnotationTextLayout {
    public static let lineHeight = 1.2, baseline = 0.9, outline = 0.12   // × font size (D2)
    /// Top-left of the text box in pixels (origin top-left), shifted so a box of
    /// `textWidth` × lineHeight·font stays inside `size`.
    public static func origin(_ point: AnnotationPoint, textWidth: CGFloat, fontPixels: CGFloat, in size: CGSize) -> CGPoint
    public static func font(pixels: CGFloat) -> CTFont        // system font, semibold
    public static func width(of text: String, fontPixels: CGFloat) -> CGFloat
    /// Box of a text shape in image pixels (origin top-left); nil for other kinds.
    public static func frame(of shape: AnnotationShape, in size: CGSize) -> CGRect?
}
extension AnnotationRenderer {
    /// Draws into a context whose image area is (0,0,size) with origin bottom-left.
    /// `pointerOpacity` 0 skips a pointer (files always pass 0).
    public static func draw(_ shapes: [AnnotationShape], in ctx: CGContext, size: CGSize,
                            pointerOpacity: (AnnotationShape) -> CGFloat = { _ in 0 })
}
```
- [ ] **Step 1: failing tests**
```swift
func testTextOriginStaysInsideTheImage() {
    let size = CGSize(width: 200, height: 100)
    let o = AnnotationTextLayout.origin(.init(x: 0.95, y: 0.98), textWidth: 60, fontPixels: 10, in: size)
    XCTAssertEqual(o.x, 140, accuracy: 0.001); XCTAssertEqual(o.y, 88, accuracy: 0.001)
    XCTAssertEqual(AnnotationTextLayout.origin(.init(x: 0.1, y: 0.2), textWidth: 60, fontPixels: 10, in: size), CGPoint(x: 20, y: 20))
    // wider than the image: starts at the left edge
    XCTAssertEqual(AnnotationTextLayout.origin(.init(x: 0.5, y: 0), textWidth: 400, fontPixels: 10, in: size).x, 0)
}
func testTextIsRenderedInItsColourWithinItsFrameAndSizeIsUnchanged() {
    let shape = AnnotationShape(kind: .text, points: [.init(x: 0.9, y: 0.9)], color: "#00ff00", width: 0.006,
                                text: "HHHH", fontSize: 0.3)
    let out = AnnotationRenderer.render([shape], onto: whiteImage(400, 200))!
    XCTAssertEqual(out.width, 400); XCTAssertEqual(out.height, 200)
    let frame = AnnotationTextLayout.frame(of: shape, in: CGSize(width: 400, height: 200))!
    XCTAssertLessThanOrEqual(frame.maxX, 400); XCTAssertLessThanOrEqual(frame.maxY, 200)
    var green = 0
    for x in stride(from: Int(frame.minX), to: Int(frame.maxX), by: 2) {
        for y in stride(from: Int(frame.minY), to: Int(frame.maxY), by: 2) {
            let p = pixel(out, x, y); if p[1] > 200 && p[0] < 80 && p[2] < 80 { green += 1 }
        }
    }
    XCTAssertGreaterThan(green, 20)
    XCTAssertGreaterThan(pixel(out, 10, 10)[0], 240)   // far from the text: untouched
}
func testPointersAreNeverRenderedIntoFiles() {
    let p = AnnotationShape(kind: .pointer, points: [.init(x: 0, y: 0.5), .init(x: 1, y: 0.5)], color: "#ff0000", width: 0.05)
    let out = AnnotationRenderer.render([p], onto: whiteImage(100, 100))!
    XCTAssertGreaterThan(pixel(out, 50, 50)[1], 240)
}
```
- [ ] **Step 2:** FAIL.
- [ ] **Step 3: implement.** `origin`: `x = min(max(p.x*W, 0), max(W - textWidth, 0))`, `y = min(max(p.y*H, 0), max(H - lineHeight*font, 0))`. `font(pixels:)`: `CTFontCreateUIFontForLanguage(.system, px, nil)` → descriptor copy with `kCTFontTraitsAttribute: [kCTFontWeightTrait: 0.3]`. `width`: `CTLineGetTypographicBounds` of an attributed string. `render` = create context, draw image, `draw(shapes, in: ctx, size:)`. `draw`: existing strokes; `.pointer` drawn like `.pen` with `ctx.setAlpha(opacity)` only when opacity > 0; `.text`: font px = `fontSize*H`, origin via `origin`, baseline in bottom-left coords `y = H - (o.y + baseline*px)`; `ctx.textMatrix = .identity`; stroke pass (`setTextDrawingMode(.stroke)`, line width `outline*px*2` — half of it is under the fill, so the visible outline is ≈ 12 % —, colour black α 0.75, round joins), then fill pass in the shape colour; both via `CTLineDraw` at `textPosition`.
- [ ] **Step 4:** pass. **Step 5:** commit `feat(core): render text annotations with an outline`.

### Task 3: Web T tool

**Files:** Modify `Sources/MicroCAMApp/Streaming/StreamPage.swift`, `scripts/stream-page-shots.py`

- [ ] **Step 1 (test first):** extend `stream-page-shots.py`: after `draw(page)` in drawing state, add `add_text(page, "C12 short")` = tap `[data-tool=text]`, click at (0.3, 0.2) of `#ink`, `page.keyboard.type(...)`, press Enter, assert `page.evaluate("shapes.some(s => s.kind === 'text' && s.text === 'C12 short')")`, check that `#sizes` is visible, then `check(page, f"{name} text")` and screenshot `{slug}-2b-text.png`; in the photo state add text before `#save`. Add `#sizes` to the panel list of `check`. Run against the demo stream → FAIL (no text tool).
- [ ] **Step 2: implement in the page:**
  - Palette: `<button class="icon" data-tool="text" data-i18n-aria="text" data-i18n-title="text">` with a "T" glyph SVG after pen.
  - `#sizes` panel (hidden unless tool is text): three `.icon` buttons `data-size="small|medium|large"` with an "A" in 13/17/22 px, aria/title `textSmall/textMedium/textLarge`. `reserve()` includes `sizes`.
  - CSS: `@media (max-width:400px){.sep{display:none}}`, landscape `max-height:380px` hides separators; `#textEditor` = absolutely positioned `<input maxlength=200>` with `user-select:text`, transparent background, colour = current colour, `font: 600 max(16px, size)px system-ui`, `-webkit-text-stroke` none, a thin outline border.
  - JS constants mirror D2: `const LINE = 1.2, BASE = 0.9, OUTLINE = 0.12, SIZES = {small: .03, medium: .045, large: .07}`.
  - `drawShape` for `text`: `ctx.font = "600 " + px + "px -apple-system,BlinkMacSystemFont,system-ui,sans-serif"`; origin clamped like `AnnotationTextLayout.origin` with `measureText(...).width`; `strokeText` with `lineWidth = OUTLINE*px*2`, `strokeStyle = "rgba(0,0,0,.75)"`, `lineJoin="round"`, then `fillText` at baseline `y + BASE*px`. Skip the shape being edited.
  - `textAt(p)`: last text shape whose box (same origin math) contains `p` (in canvas px).
  - pointerdown with tool text: if a text is hit → `dragging = {shape, start, orig}`; else remember the point. pointermove moves the dragged text (`points[0]` += delta, clamped). pointerup: if dragged less than 4 px → `openEditor(existing)`; if no hit → `openEditor(null, p)`.
  - `openEditor(shape, p)`: positions the input at the shape's origin in CSS px (`ink` rect), `value = shape?.text || ""`, focuses. Enter → commit; Escape → cancel (`e.stopPropagation()` so the PIN handler ignores it); `blur` → commit. Commit: trimmed text empty → delete the edited shape (or add nothing); else update/add `{kind:"text", points:[p], color, width:0.006, text, fontSize: SIZES[size]}`. Changing colour or size while editing applies to the edited text.
  - `finish()` ignores text; undo pops the last shape including text; `setDrawing(false)` and `back`/`photo` commit an open editor first.
  - STRINGS (en/cs): `"text": "Text"/"Text"`, `"textSize": "Text size"/"Velikost textu"`, `"textSmall": "Small text"/"Malý text"`, `"textMedium": "Medium text"/"Střední text"`, `"textLarge": "Large text"/"Velký text"`, `"textPlaceholder": "Type a label"/"Napiš popisek"`. Add `text` to `streamSameAsEnglish["cs"]`.
- [ ] **Step 3:** `swift test` (LocalizationTests) green; build + run the demo stream (`MICROCAM_DEMO_STREAM_PORT=8790 MICROCAM_DEMO_STREAM_PIN=2468`) and `scripts/stream-page-shots.py http://127.0.0.1:8790/ <run>/web-en --pin 2468` and `--locale cs-CZ` → `all ok`. Look at the text screenshots.
- [ ] **Step 4:** commit `feat(stream): text tool for annotations on the web page`.

### Task 4: Stage 1 docs

- [ ] README "Web UI": text tool (T, tap to place, Enter/tap elsewhere to finish, Esc cancels, drag to move, three sizes). CHANGELOG Unreleased entry. Commit `docs: text in web annotations`.

---

# Stage 2 — drawing on the Mac

### Task 5: `AnnotationBoard`

**Files:** Create `Sources/MicroCAMCore/Streaming/AnnotationBoard.swift`; Test `Tests/MicroCAMCoreTests/AnnotationBoardTests.swift`

**Interfaces — Produces:**
```swift
public final class AnnotationBoard: @unchecked Sendable {   // NSLock inside
    public static let bench = "bench"
    public static let pointerLifetime: TimeInterval = 2.5
    public static let pointerFade: TimeInterval = 0.5
    public static let maxPointers = 5
    public static let historyLimit = 500
    public enum Change: Equatable, Sendable { case add(AnnotationShape), update(AnnotationShape), delete(String), clear }
    public struct Revisioned: Equatable, Sendable { public let revision: Int; public let change: Change }
    public enum Delta: Equatable, Sendable { case changes([Revisioned]), snapshot(revision: Int, shapes: [AnnotationShape]) }
    public init()
    public var revision: Int { get }
    public var shapes: [AnnotationShape] { get }        // drawing order, pointers included
    public var persistent: [AnnotationShape] { get }    // without pointers
    public var isEmpty: Bool { get }
    public var hasPointers: Bool { get }
    @discardableResult public func add(_ shape: AnnotationShape, now: Date = Date()) -> AnnotationShape?
    @discardableResult public func delete(id: String, by author: String) -> Bool
    @discardableResult public func undo(by author: String) -> AnnotationShape?
    @discardableResult public func deleteAll(by author: String) -> Int
    @discardableResult public func clearAll(by author: String) -> Bool
    public func changes(since revision: Int) -> Delta
    @discardableResult public func prune(now: Date = Date()) -> Bool
    public func pointerOpacity(id: String, now: Date = Date()) -> Double   // D11
    public func photoShapes(for kind: CaptureKind) -> [AnnotationShape]  // persistent for .photo, [] otherwise
}
```
Rules: `add` sanitizes with the budget `maxPoints − points of other persistent shapes` (pointers: own cap); rejects no author; assigns a UUID when `id` is nil; same id → update in place only for the same author and kind (else nil); new persistent shape rejected at 200; a 6th pointer evicts the oldest (`.delete` change); pointer `lastUpdate = now`. `delete`: own or bench. `undo`: removes the author's most recently **added** persistent shape. `clearAll`: bench only, removes everything, one `.clear`. Each change bumps `revision` by 1 and appends to a history capped at `historyLimit`. `changes(since:)`: `since == revision` → `.changes([])`; within history → the later changes; older than history or `since > revision` → `.snapshot`. `prune`: drops pointers with `now − lastUpdate ≥ 2.5` (a `.delete` each). Opacity: 1 until `lifetime − fade`, then linear to 0.

- [ ] **Step 1: failing tests** (all in `AnnotationBoardTests`): ownership (viewer cannot delete bench shape; bench can delete viewer shape; viewer can delete own), `clearAll` only bench, `undo` own-only and ignores pointers, `deleteAll(by:)`, revisions increment once per change, `changes(since:)` returns exact missed changes / empty / snapshot when too old (historyLimit+10 adds) and when ahead, pointer update in place keeps order and one shape, pointer expiry at 2.5 s via `prune(now:)`, opacity 1 at 1.9 s, 0.5 at 2.25 s, 0 at 2.5 s, 6th pointer evicts the oldest, 201st persistent shape rejected, point budget across shapes (4 999 + 2 points → second rejected), shape without author rejected, missing id gets one, update by another author rejected, `photoShapes(for: .timelapse)` empty and `(for: .photo)` excludes pointers, concurrent adds from 8 threads end with a consistent count (`DispatchQueue.concurrentPerform`).
- [ ] **Step 2:** FAIL (no type). **Step 3:** implement. **Step 4:** pass. **Step 5:** commit `feat(core): annotation board with ownership, revisions and pointer expiry`.

### Task 6: `PreviewGeometry` and shortcuts

**Files:** Create `Sources/MicroCAMCore/PreviewGeometry.swift`; Modify `ShortcutAction.swift`; Tests `PreviewGeometryTests.swift`, `ShortcutActionTests.swift`

**Interfaces — Produces:**
```swift
public struct PreviewGeometry: Equatable, Sendable {
    public init(viewSize: CGSize, contentSize: CGSize?, zoom: ZoomState)
    /// The picture in view coordinates (origin bottom-left) after aspect fit and zoom.
    public var imageRect: CGRect { get }
    public func viewPoint(_ p: AnnotationPoint) -> CGPoint
    public func imagePoint(_ v: CGPoint) -> AnnotationPoint      // clamped to 0…1
    public func containsImage(_ v: CGPoint) -> Bool
}
ShortcutAction: + case toggleDrawing, leaveDrawing
static func from(characters:hasModifiers:isEditingText:inSidePanel:hasSelection:isDrawing: Bool = false)
    // "d" → .toggleDrawing; "\u{1b}" → .leaveDrawing only when isDrawing (else nil so Esc keeps its system meaning)
```
`imageRect` = aspect-fit rect of `contentSize` in `viewSize` (whole view when nil), `.applying(zoom.absoluteTransform(viewSize:))`.
- [ ] **Step 1: failing tests:** fit letterbox (16:9 in 1000×1000 → y 218.75…781.25), `viewPoint(0,0)` is the top-left of `imageRect`, round trip `imagePoint(viewPoint(p)) ≈ p` for zoom 1 and zoom 3 at anchor (0.8, 0.3), a point outside the picture clamps; shortcuts: `d` → toggleDrawing, `D` too, Esc drawing → leaveDrawing, Esc not drawing → nil, `d` while editing text → nil, Esc while editing → nil.
- [ ] **Step 2–4:** FAIL → implement → pass. **Step 5:** commit `feat(core): preview geometry and drawing shortcuts`.

### Task 7: Overlay, palette and wiring on the Mac

**Files:** Create `Preview/AnnotationOverlayView.swift`, `Views/DrawingPalette.swift`; Modify `PreviewContainerView.swift`, `ContentView.swift`, `MicroCAMApp.swift`, `AppModel.swift`, `KeyboardMonitor.swift`, `Resources/*/Localizable.strings`

**Interfaces:**
- `AppModel`: `let board = AnnotationBoard()`; `@Published private(set) var boardRevision = 0`; `@Published var isDrawing = false`; `@Published var drawTool: AnnotationShape.Kind = .arrow`; `@Published var drawColor = "#ff3b30"`; `@Published var textSize = AnnotationTextSize.medium`; `static let drawColors = ["#ff3b30", "#ffd60a", "#30d158", "#0a84ff"]`; `func boardChanged()` (sets `boardRevision`, tells the overlay); `func undoDrawing()`, `func clearDrawing()`; `handle(.toggleDrawing / .leaveDrawing)`. `KeyboardMonitor` gets `isDrawing: () -> Bool`.
- `AnnotationOverlayView(board:onChange:)`: `var isDrawing`, `tool`, `color`, `textSize`, `contentSize`, `zoom` (set by the container in `applyZoom`); `func boardChanged()`; `func commitText()`; `func beginText(at: AnnotationPoint)` (demo).
- Behaviour: `isHidden = board.isEmpty && !isDrawing && current == nil`; `hitTest` returns nil unless drawing; `draw(_:)` concatenates `geometry.imageRect` origin + scale and calls `AnnotationRenderer.draw(board.shapes + [current], in:size: imageRect.size, pointerOpacity:)`; clip to the view. mouseDown/Dragged/Up build `current` in image points (`imagePoint`), commit on mouseUp with `author: bench` (arrows/ellipses need > 0.005 movement, as on the web); pointer: `board.add` on every drag (same id); 30 Hz timer only while `board.hasPointers` (prune + redraw, stops itself). scroll/magnify pass to the container (default responder chain). Text: `NSTextField` (borderless, semibold, the shape colour, placeholder "Type a label") placed at the text's origin; Enter commits, Esc cancels (delegate `doCommandBy` `cancelOperation`), losing focus commits; clicking a text with the T tool edits it; dragging it moves it (update in place). Cursor rects: crosshair / I-beam.
- `DrawingPalette`: capsule of `.regularMaterial` at the bottom of the preview: tool buttons (SF Symbols `arrow.up.right`, `circle`, `scribble`, `textformat`, `hand.point.up.left`) with `.help`, selected tool highlighted; 4 colour circles; text size picker (menu, only with text tool); undo (`arrow.uturn.backward`, disabled when nothing own); Clear all (`trash`, disabled when empty); Done (`xmark`, `.help("Stop drawing (Esc)")`).
- `ContentView`: toolbar `Toggle(isOn: $model.isDrawing) { Label("Draw", systemImage: "pencil.tip.crop.circle") }.toggleStyle(.button).help("Draw on the picture (D)")` in the primary-action group; palette in the preview `ZStack` when drawing; toast bottom padding 80 while drawing.
- Menu (Camera): `Toggle("Draw", isOn: $model.isDrawing).keyboardShortcut("d")`, `Button("Clear drawing")` disabled when empty. Help alert gains "D – draw on the picture, Esc – stop drawing".
- Strings (en = key; cs): Draw=Kreslit; "Draw on the picture (D)"="Kreslit do obrazu (D)"; Arrow=Šipka; Circle=Kruh; Pen=Pero; Text=Text (add to `sameAsEnglish`); Pointer=Ukazovátko; "Pointer – fades after a moment"="Ukazovátko – za chvíli zmizí"; Red/Yellow/Green/Blue=Červená/Žlutá/Zelená/Modrá; "Text size"="Velikost textu"; Small/Medium/Large=Malý/Střední/Velký; "Undo last drawing"="Vrátit poslední kresbu"; "Clear all drawings"="Smazat všechny kresby"; "Clear drawing"="Smazat kresbu"; "Stop drawing (Esc)"="Ukončit kreslení (Esc)"; "Type a label"="Napiš popisek"; "D – draw on the picture, Esc – stop drawing"="D – kreslit do obrazu, Esc – ukončit kreslení"; "Drawing"="Kreslení".
- Camera change: `selectCamera` completion clears the board when the device id differs from the board's camera (D13).
- [ ] Steps: implement; `swift test` (LocalizationTests catches missing keys); `scripts/make-app.sh`; demo run with a drawing step (Task 9) → screenshots; commit `feat(app): draw on the live picture on the Mac`.

### Task 8: Photos carry the drawing

**Files:** Modify `AppModel.swift` (+ strings)

- `takePhoto`: `let shapes = board.photoShapes(for: kind)` before capturing; on success with non-empty shapes, call `renderAnnotatedCopy(of: url, shapes:)` (refactored out of `saveAnnotatedCopy`, returns `Result<URL, Error>` on the main actor without messaging) and then show one toast naming both files: `"Saved: \(name), with drawing: \(copy)"`, `"Photo from another device saved: \(name), with drawing: \(copy)"`, `"An agent took a photo: \(name), with drawing: \(copy)"` (cs: "Uloženo: %@, s kresbou: %@", "Uložena fotka z jiného zařízení: %@, s kresbou: %@", "Agent vyfotil: %@, s kresbou: %@"); a failed copy reports `"Drawing not saved"` but the original stays and the completion still succeeds with the original. `saveAnnotatedCopy` keeps its behaviour on top of the shared helper.
- Test: the decision (`photoShapes`) is covered in Task 5; the file pair is verified in the demo (Task 9: both files exist, the copy differs from the original).
- Commit `feat(app): photos save an annotated copy while something is drawn`.

### Task 9: Demo steps and live verification

**Files:** Modify `Sources/MicroCAMApp/Demo/DemoMode.swift`

- After "3. zoom and grid": `3b-drawing` — `model.isDrawing = true`, tool text, add an ellipse, an arrow and a text shape ("C12") and a pointer to `model.board` (author bench), capture the main window with the palette; `3c-text-editing` — `previewView.annotationView.beginText(at:)` with a typed value, capture, commit; `3d-annotated-photo` — `model.takePhoto()`, wait, capture the toast; check both files exist (log to stderr if not); then `clearDrawing()`, `isDrawing = false`.
- Run `scripts/make-screenshots.sh <photos> en <run>/mac-en` and `cs`; inspect images. Stream shots: Task 3 command in en and cs → `all ok`.
- Commit `chore(demo): screenshots of drawing on the Mac`.

### Task 10: Stage 2 docs

- README: Highlights (drawing on the live picture), shortcut table row `D` / `⌘ D` draw, Esc stop drawing; a "Drawing on the picture" bullet in *The window*; CHANGELOG Unreleased. Commit `docs: drawing on the Mac`.

### Finish

- `swift test`, final whole-branch review, push, PR against `main` via `gh` (no merge, no release).
