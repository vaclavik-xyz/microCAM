#!/usr/bin/env python3
"""Screenshots and layout checks of the stream page on phones, tablet and desktop.

Usage: scripts/stream-page-shots.py <base-url> <out-dir> [--pin 1234]

Run against the demo stream (see README, MICROCAM_DEMO_STREAM_PORT) — with --pin
it also takes a photo, annotates it and saves the copy, so never point it with
a PIN at a real bench. Needs Python Playwright with WebKit and Chromium.
For every device and state (live, drawing, annotated photo) it checks that each
visible control lies fully inside the viewport, is at least 44 px and does not
overlap another control, and it writes <device>-<state>.png.
"""
import argparse
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

DEVICES = ["iPhone SE", "iPhone SE landscape", "iPhone 15 Pro Max", "iPhone 15 Pro Max landscape",
           "iPad (gen 7)", "iPad (gen 7) landscape", "Desktop 1440"]

CONTROLS = """() => [...document.querySelectorAll('#dock button, #dock a.btn, #status')]
  .filter(e => e.offsetParent !== null && getComputedStyle(e).visibility !== 'hidden')
  .map(e => { const r = e.getBoundingClientRect();
              return {id: e.id || e.dataset.tool || e.dataset.color || e.className, x: r.left, y: r.top,
                      w: r.width, h: r.height, chip: e.id === 'status'}; })"""


def check(page, name):
    page.wait_for_timeout(450)  # let button transitions settle before measuring and shooting
    vw, vh = page.viewport_size["width"], page.viewport_size["height"]
    boxes = page.evaluate(CONTROLS)
    problems = []
    for b in boxes:
        if b["x"] < 0 or b["y"] < 0 or b["x"] + b["w"] > vw + 0.5 or b["y"] + b["h"] > vh + 0.5:
            problems.append(f"{b['id']} outside the viewport {b}")
        if not b["chip"] and (b["w"] < 44 or b["h"] < 44):
            problems.append(f"{b['id']} smaller than 44 px ({b['w']:.0f}×{b['h']:.0f})")
    for i, a in enumerate(boxes):
        for b in boxes[i + 1:]:
            if a["x"] < b["x"] + b["w"] - 0.5 and b["x"] < a["x"] + a["w"] - 0.5 \
                    and a["y"] < b["y"] + b["h"] - 0.5 and b["y"] < a["y"] + a["h"] - 0.5:
                problems.append(f"{a['id']} overlaps {b['id']}")
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("base")
    ap.add_argument("out")
    ap.add_argument("--pin")
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
            ctx = browser.new_context(**opts)
            page = ctx.new_page()
            errors = []
            page.on("pageerror", lambda e: errors.append(str(e)))
            page.goto(args.base, wait_until="commit")
            page.wait_for_timeout(2500)
            slug = name.replace(" ", "_").replace("(", "").replace(")", "")

            try:
                page.mouse.move(10, 10)
                ok &= check(page, f"{name} live")
                page.screenshot(path=str(out / f"{slug}-1-live.png"))

                tap(page, "#draw")
                draw(page)
                tap(page, "#colorBtn")
                ok &= check(page, f"{name} drawing")
                page.screenshot(path=str(out / f"{slug}-2-drawing.png"))
                tap(page, "[data-color='#ffd60a']")

                if args.pin:
                    page.once("dialog", lambda d: d.accept(args.pin))
                    tap(page, "#photo")
                    page.wait_for_selector("#shot:not(.hidden)", timeout=10_000)
                    page.wait_for_timeout(1200)
                    draw(page)
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
