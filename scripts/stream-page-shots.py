#!/usr/bin/env python3
"""Screenshots and layout checks of the stream page on phones, tablet and desktop.

Usage: scripts/stream-page-shots.py <base-url> <out-dir> [--pin 1234] [--locale cs-CZ]

Run against the demo stream (see README, MICROCAM_DEMO_STREAM_PORT) — with --pin
it also takes a photo, annotates it and saves the copy, so never point it with
a PIN at a real bench. Needs Python Playwright with WebKit and Chromium.
For every device and state (live, self-timer on, PIN panel empty / wrong / locked, drawing,
text label, annotated photo) it checks that each
visible control lies fully inside the viewport, is at least 44 px (36 px with a mouse) and does not
overlap another control, and it writes <device>-<state>.png. --locale sets the
browser language (the page picks its texts from it; default en-US).
"""
import argparse
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

DEVICES = ["iPhone SE", "iPhone SE landscape", "iPhone 15 Pro Max", "iPhone 15 Pro Max landscape",
           "iPad (gen 7)", "iPad (gen 7) landscape", "Desktop 1440"]

# offsetParent is null for position:fixed elements (the status chip), so visibility
# is decided by layout boxes and computed style instead.
CONTROLS = """() => [...document.querySelectorAll(document.getElementById('pinDialog').classList.contains('hidden')
    ? '#dock button, #dock a.btn, #status' : '#pinDialog button, #pinDialog input')]
  .filter(e => e.getClientRects().length > 0 && getComputedStyle(e).visibility !== 'hidden')
  .map(e => { const r = e.getBoundingClientRect();
              return {id: e.id || e.dataset.tool || e.dataset.color || e.className, x: r.left, y: r.top,
                      w: r.width, h: r.height, chip: e.id === 'status'}; })"""


def check(page, name):
    page.wait_for_timeout(450)  # let button transitions settle before measuring and shooting
    vw, vh = page.viewport_size["width"], page.viewport_size["height"]
    boxes = page.evaluate(CONTROLS)
    # 44 px for a finger; with a mouse the page uses 36 px buttons.
    minimum = 36 if page.evaluate("matchMedia('(hover:hover) and (pointer:fine)').matches") else 44
    problems = []
    for b in boxes:
        if b["x"] < 0 or b["y"] < 0 or b["x"] + b["w"] > vw + 0.5 or b["y"] + b["h"] > vh + 0.5:
            problems.append(f"{b['id']} outside the viewport {b}")
        if not b["chip"] and (b["w"] < minimum or b["h"] < minimum):
            problems.append(f"{b['id']} smaller than {minimum} px ({b['w']:.0f}×{b['h']:.0f})")
    for i, a in enumerate(boxes):
        for b in boxes[i + 1:]:
            if a["x"] < b["x"] + b["w"] - 0.5 and b["x"] < a["x"] + a["w"] - 0.5 \
                    and a["y"] < b["y"] + b["h"] - 0.5 and b["y"] < a["y"] + a["h"] - 0.5:
                problems.append(f"{a['id']} overlaps {b['id']}")
    if page.is_visible("#pinDialog"):
        for p in problems:
            print(f"FAIL {name}: {p}")
        return not problems
    image = page.evaluate("""() => { const i = [live, shot].find(e => !e.classList.contains('hidden'));
                                      const r = i.getBoundingClientRect(); return {x: r.left, y: r.top, w: r.width, h: r.height}; }""")
    # Text sizes and colours open over the image on purpose; tools and main actions must not.
    panels = page.evaluate("""() => ['palette', 'controls'].map(id => document.getElementById(id))
      .filter(e => e && !e.classList.contains('hidden'))
      .map(e => { const r = e.getBoundingClientRect(); return {id: e.id, x: r.left, y: r.top, w: r.width, h: r.height}; })""")
    for p in panels:
        if image["w"] and image["x"] < p["x"] + p["w"] - 0.5 and p["x"] < image["x"] + image["w"] - 0.5 \
                and image["y"] < p["y"] + p["h"] - 0.5 and p["y"] < image["y"] + image["h"] - 0.5:
            problems.append(f"image lies under #{p['id']}")
    if not any(b["chip"] for b in boxes) and page.evaluate("!document.body.classList.contains('image-only')"):
        problems.append("status chip not measured")
    for p in problems:
        print(f"FAIL {name}: {p}")
    return not problems


class Unreachable(Exception):
    pass


def tap(page, selector):
    """Click like a thumb would; a control that cannot be reached is a failure."""
    try:
        page.click(selector, timeout=3000)
    except Exception as e:  # noqa: BLE001 — Playwright raises its own TimeoutError
        raise Unreachable(f"cannot tap {selector}: {str(e).splitlines()[0]}") from None


def route_json(page, path, status, body):
    page.unroute(path)
    page.route(path, lambda r: r.fulfill(status=status, content_type="application/json", body=body))


def pin_states(page, name, out, slug):
    """The PIN panel empty, after a wrong PIN and during the lockout. 401/429 are
    faked so the demo server never locks up; Esc must close without a toast."""
    ok = True
    page.evaluate("localStorage.removeItem('microcamPin')")
    tap(page, "#photo")
    page.wait_for_selector("#pinDialog:not(.hidden)", timeout=3000)
    ok &= check(page, f"{name} pin empty")
    page.screenshot(path=str(out / f"{slug}-4-pin-empty.png"))
    route_json(page, "**/photo", 401, '{"error":"pin"}')
    page.fill("#pinInput", "0000")
    page.keyboard.press("Enter")
    page.wait_for_function("document.getElementById('pinForm').classList.contains('error')", timeout=3000)
    ok &= check(page, f"{name} pin wrong")
    page.screenshot(path=str(out / f"{slug}-5-pin-wrong.png"))
    route_json(page, "**/photo", 429, '{"error":"locked","retryAfter":42}')
    page.fill("#pinInput", "1111")
    tap(page, "#pinOk")
    page.wait_for_function("document.getElementById('pinInput').disabled", timeout=3000)
    ok &= check(page, f"{name} pin locked")
    page.screenshot(path=str(out / f"{slug}-6-pin-locked.png"))
    page.unroute("**/photo")
    page.keyboard.press("Escape")
    page.wait_for_timeout(300)
    if page.is_visible("#pinDialog") or page.evaluate("document.getElementById('toast').classList.contains('show')"):
        print(f"FAIL {name}: Esc did not cancel the PIN panel quietly")
        ok = False
    return ok


def draw(page):
    """An arrow, an ellipse and a pen stroke across the middle of the image."""
    box = page.locator("#ink").bounding_box()
    at = lambda fx, fy: (box["x"] + box["width"] * fx, box["y"] + box["height"] * fy)
    for tool, a, b in [("arrow", (0.2, 0.25), (0.45, 0.5)), ("ellipse", (0.55, 0.3), (0.8, 0.7)),
                       ("pen", (0.15, 0.75), (0.5, 0.8))]:
        tap(page, f"[data-tool={tool}]")
        page.mouse.move(*at(*a))
        page.mouse.down()
        for i in range(1, 9):
            fx = a[0] + (b[0] - a[0]) * i / 8
            fy = a[1] + (b[1] - a[1]) * i / 8 + (0.03 if tool == "pen" and i % 2 else 0)
            page.mouse.move(*at(fx, fy))
        page.mouse.up()


def add_text(page, name, label, at=(0.3, 0.2)):
    """The T tool: place a label, type, Enter; tap it again to edit, Esc keeps it;
    drag it to move it. Returns False (and prints why) when something is off."""
    ok = True
    tap(page, "[data-tool=text]")
    if not page.is_visible("#sizes"):
        print(f"FAIL {name}: text sizes not shown with the text tool")
        ok = False
    tap(page, "[data-size=large]")
    box = page.locator("#ink").bounding_box()
    x, y = box["x"] + box["width"] * at[0], box["y"] + box["height"] * at[1]
    page.mouse.click(x, y)
    page.wait_for_selector("#textEditor:not(.hidden)", timeout=3000)
    page.keyboard.type(label)
    page.keyboard.press("Enter")
    page.wait_for_timeout(200)
    count = f"shapes.filter(s => s.kind === 'text' && s.text === {label!r}).length"
    if page.evaluate(count) != 1 or page.is_visible("#textEditor"):
        print(f"FAIL {name}: text label not committed with Enter")
        return False
    # Tap the label again: the editor opens with its text; Escape leaves it as it was.
    page.mouse.click(x + 4, y + 4)
    page.wait_for_selector("#textEditor:not(.hidden)", timeout=3000)
    if page.input_value("#textEditor") != label:
        print(f"FAIL {name}: tapping a label does not edit it")
        ok = False
    page.keyboard.type("zzz")
    page.keyboard.press("Escape")
    page.wait_for_timeout(200)
    if page.evaluate(count) != 1 or page.is_visible("#textEditor") or page.is_visible("#pinDialog"):
        print(f"FAIL {name}: Escape did not cancel the edit")
        ok = False
    # Drag it a little to the right: the same label moves.
    before = page.evaluate(f"shapes.find(s => s.text === {label!r}).points[0].x")
    page.mouse.move(x + 4, y + 4)
    page.mouse.down()
    for i in range(1, 6):
        page.mouse.move(x + 4 + i * 8, y + 4)
    page.mouse.up()
    after = page.evaluate(f"shapes.find(s => s.text === {label!r}).points[0].x")
    # A 200-character label at the right edge must fit the picture, outline included.
    fits = page.evaluate("""() => { const s = {kind: 'text', points: [{x: .9, y: .97}], fontSize: SIZES.large,
                                       text: 'W'.repeat(200)}, b = textBox(s, ink.width, ink.height);
                                    return b.x - b.px * OUTLINE >= 0 && b.x + b.w + b.px * OUTLINE <= ink.width
                                        && b.y + b.h + b.px * OUTLINE <= ink.height; }""")
    if not fits:
        print(f"FAIL {name}: a long label does not fit the picture")
        ok = False
    if not after > before or page.is_visible("#textEditor"):
        print(f"FAIL {name}: dragging a label does not move it")
        ok = False
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("base")
    ap.add_argument("out")
    ap.add_argument("--pin")
    ap.add_argument("--locale", default="en-US")
    args = ap.parse_args()
    out = Path(args.out).expanduser()
    out.mkdir(parents=True, exist_ok=True)
    ok = True
    with sync_playwright() as p:
        webkit, chromium = p.webkit.launch(), p.chromium.launch()
        for name in DEVICES:
            if name == "Desktop 1440":
                browser, opts = chromium, {"viewport": {"width": 1440, "height": 900}}
            else:
                browser, opts = webkit, dict(p.devices[name])
            opts["locale"] = args.locale
            ctx = browser.new_context(**opts)
            page = ctx.new_page()
            errors = []
            page.on("pageerror", lambda e: errors.append(str(e)))
            page.goto(args.base, wait_until="commit")
            page.wait_for_timeout(2500)
            slug = name.replace(" ", "_").replace("(", "").replace(")", "")

            want = args.locale.split("-")[0].lower()
            got = page.evaluate("document.documentElement.lang")
            if got != want and want in page.evaluate("Object.keys(STRINGS)"):
                print(f"FAIL {name}: page language {got}, expected {want}")
                ok = False
            try:
                page.mouse.move(10, 10)
                ok &= check(page, f"{name} live")
                page.screenshot(path=str(out / f"{slug}-1-live.png"))
                # The self-timer at its longest delay is the widest the main actions get; then off again.
                # (Without a PIN on the camera computer there is no photo button and no timer.)
                if page.is_visible("#timer"):
                    for _ in range(3):
                        tap(page, "#timer")
                    ok &= check(page, f"{name} self-timer")
                    page.screenshot(path=str(out / f"{slug}-1b-self-timer.png"))
                    tap(page, "#timer")
                if args.pin:
                    ok &= pin_states(page, name, out, slug)

                tap(page, "#draw")
                draw(page)
                tap(page, "#colorBtn")
                ok &= check(page, f"{name} drawing")
                page.screenshot(path=str(out / f"{slug}-2-drawing.png"))
                tap(page, "[data-color='#ffd60a']")
                ok &= add_text(page, name, "C12 short")
                ok &= check(page, f"{name} text")
                page.screenshot(path=str(out / f"{slug}-2b-text.png"))

                if args.pin:
                    tap(page, "#photo")
                    page.wait_for_selector("#pinDialog:not(.hidden)", timeout=3000)
                    page.fill("#pinInput", args.pin)
                    page.keyboard.press("Enter")
                    page.wait_for_selector("#shot:not(.hidden)", timeout=10_000)
                    page.wait_for_timeout(1200)
                    draw(page)
                    ok &= add_text(page, name, "R7", at=(0.6, 0.15))
                    tap(page, "#save")
                    page.wait_for_timeout(1500)
                    ok &= check(page, f"{name} photo")
                    page.screenshot(path=str(out / f"{slug}-3-photo.png"))
            except Unreachable as e:
                print(f"FAIL {name}: {e}")
                page.screenshot(path=str(out / f"{slug}-unreachable.png"))
                ok = False
            for e in errors:
                print(f"FAIL {name}: page error {e}")
                ok = False
            ctx.close()
            print(f"done {name}")
        webkit.close()
        chromium.close()
    print("all ok" if ok else "problems found")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
