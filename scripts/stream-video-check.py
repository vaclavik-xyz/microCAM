#!/usr/bin/env python3
"""Plays the live stream in Chromium and WebKit and measures it.

Usage: scripts/stream-video-check.py <base-url> [--seconds 8]

Run against the demo stream with motion (MICROCAM_DEMO_STREAM_PORT and
MICROCAM_DEMO_MOTION=1, see README). For each browser it reports which feed
the page chose (video or mjpeg), the frames shown per second, how far the
player is behind the newest frame it has, and that ?mjpeg=1 still gets the
JPEG stream. Fails when the video feed isn't used, shows under 20 fps or
stays more than 0.5 s behind. Needs Python Playwright with WebKit and Chromium.
"""
import argparse
import sys

from playwright.sync_api import sync_playwright

MEASURE = """async (seconds) => {
  const v = document.getElementById('video');
  let frames = 0, behind = [];
  const count = () => { frames++; v.requestVideoFrameCallback(count); };
  v.requestVideoFrameCallback(count);
  const timer = setInterval(() => { const b = v.buffered; if (b.length) behind.push(b.end(b.length - 1) - v.currentTime); }, 200);
  await new Promise(r => setTimeout(r, seconds * 1000));
  clearInterval(timer);
  behind.sort((a, b) => a - b);
  return { fps: frames / seconds, width: v.videoWidth, height: v.videoHeight,
           behindMedian: behind[behind.length >> 1] || 0, behindMax: behind[behind.length - 1] || 0 };
}"""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("url")
    parser.add_argument("--seconds", type=float, default=8)
    args = parser.parse_args()
    ok = True
    with sync_playwright() as p:
        for name in ["chromium", "webkit"]:
            browser = getattr(p, name).launch()
            page = browser.new_page(viewport={"width": 1280, "height": 800})
            page.goto(args.url)
            page.wait_for_function("document.body.dataset.feed && !document.body.classList.contains('offline')"
                                   " && (document.body.dataset.feed !== 'video' || document.getElementById('video').currentTime > 0)",
                                   timeout=15000)
            feed = page.evaluate("document.body.dataset.feed")
            result = page.evaluate(MEASURE, args.seconds) if feed == "video" else {}
            good = feed == "video" and result["fps"] >= 20 and result["behindMedian"] <= 0.5
            ok &= good
            print(f"{'ok  ' if good else 'FAIL'} {name}: feed={feed} " + " ".join(
                f"{k}={v:.2f}" if isinstance(v, float) else f"{k}={v}" for k, v in result.items()))
            page.goto(args.url + ("&" if "?" in args.url else "?") + "mjpeg=1")
            page.wait_for_function("document.body.dataset.feed === 'mjpeg' && document.getElementById('live').naturalWidth > 0",
                                   timeout=15000)
            print(f"ok   {name}: ?mjpeg=1 plays the JPEG stream")
            browser.close()
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
