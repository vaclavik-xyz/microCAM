#!/usr/bin/env python3
"""End-to-end check of a running microCAM MCP server (Python 3 stdlib only).

Usage: MICROCAM_MCP_TOKEN=<token> scripts/mcp-smoke.py <host> [port] [--write] [--lockout] [--save DIR]

The token comes from the environment so it stays out of shell history.
Read-only by default: initialize, tools/list, server/discover, get_status,
capture_frame, list_captures, get_capture, bad arguments and a wrong token.
  --write    also take_photo, start/stop_recording (3 s) and set_job (when jobs
             are on); this saves files on the camera Mac.
  --lockout  send wrong tokens until this address is locked out (5 minutes!).
  --save DIR write the returned images there.
"""
import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

parser = argparse.ArgumentParser(usage=__doc__)
parser.add_argument("host")
parser.add_argument("port", nargs="?", default="8091")
parser.add_argument("--write", action="store_true")
parser.add_argument("--lockout", action="store_true")
parser.add_argument("--save")
opts = parser.parse_args()
if "MICROCAM_MCP_TOKEN" not in os.environ:
    sys.exit(__doc__)
save_dir = opts.save
URL = f"http://{opts.host}:{opts.port}/mcp"
TOKEN = os.environ["MICROCAM_MCP_TOKEN"]
MODERN = "2026-07-28"
failed = False
next_id = 0


def check(name, ok, detail=""):
    global failed
    print(("ok   " if ok else "FAIL ") + name + (f"  ({detail})" if detail else ""))
    failed |= not ok


def post(body, token=TOKEN, headers=None):
    h = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
    if token is not None:
        h["Authorization"] = f"Bearer {token}"
    h.update(headers or {})
    req = urllib.request.Request(URL, data=json.dumps(body).encode(), headers=h, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return r.status, dict(r.headers), (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, dict(e.headers), json.loads(raw)
        except ValueError:
            return e.code, dict(e.headers), raw.decode(errors="replace")


def rpc(method, params=None, version="2025-06-18"):
    global next_id
    next_id += 1
    body = {"jsonrpc": "2.0", "id": next_id, "method": method}
    if params is not None:
        body["params"] = params
    return post(body, headers={"MCP-Protocol-Version": version})


def call(name, arguments=None):
    status, _, body = rpc("tools/call", {"name": name, "arguments": arguments or {}})
    result = (body or {}).get("result", {})
    return status, result


def text_of(result):
    return " ".join(c.get("text", "") for c in result.get("content", []) if c.get("type") == "text")


def images_of(result, label):
    images = [c for c in result.get("content", []) if c.get("type") == "image"]
    for i, image in enumerate(images):
        if save_dir:
            os.makedirs(save_dir, exist_ok=True)
            path = os.path.join(save_dir, f"{label}{'-' + str(i) if i else ''}.jpg")
            with open(path, "wb") as f:
                f.write(base64.b64decode(image["data"]))
    return images


status, _, body = rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                     "clientInfo": {"name": "mcp-smoke", "version": "1"}})
check("initialize", status == 200 and body["result"]["protocolVersion"] == "2025-06-18",
      f"server {body['result']['serverInfo']}" if status == 200 else status)
status, _, _ = post({"jsonrpc": "2.0", "method": "notifications/initialized"})
check("notification → 202", status == 202, status)
try:
    urllib.request.urlopen(urllib.request.Request(URL, headers={"Authorization": f"Bearer {TOKEN}"}), timeout=10)
    get_status = 200
except urllib.error.HTTPError as e:
    get_status = e.code
check("GET → 405", get_status == 405, get_status)

status, _, body = rpc("tools/list")
tools = [t["name"] for t in body["result"]["tools"]] if status == 200 else []
check("tools/list", "capture_frame" in tools, ", ".join(tools))

status, _, body = post({"jsonrpc": "2.0", "id": 99, "method": "server/discover",
                        "params": {"_meta": {"io.modelcontextprotocol/protocolVersion": MODERN,
                                             "io.modelcontextprotocol/clientCapabilities": {}}}},
                       headers={"MCP-Protocol-Version": MODERN, "Mcp-Method": "server/discover"})
check("server/discover (modern)", status == 200 and body["result"]["resultType"] == "complete",
      body["result"]["supportedVersions"] if status == 200 else body)

status, result = call("get_status")
s = result.get("structuredContent", {})
check("get_status", status == 200 and not result.get("isError"),
      f"camera={s.get('camera')} format={(s.get('format') or {}).get('label')} "
      f"recording={s.get('recording')} folder={s.get('folder')} job={s.get('job')}")

started = time.time()
status, result = call("capture_frame", {"max_size": 800})
images = images_of(result, "capture_frame")
check("capture_frame", status == 200 and len(images) == 1 and not result.get("isError"),
      f"{text_of(result)} {len(images[0]['data']) * 3 // 4 if images else 0} bytes in {time.time() - started:.2f} s")

status, result = call("capture_frame", {"max_size": 5})
check("bad argument → tool error", result.get("isError") is True, text_of(result))
status, _, body = rpc("tools/call", {"name": "format_disk", "arguments": {}})
check("unknown tool → -32602", body.get("error", {}).get("code") == -32602, body.get("error", {}).get("message"))

if opts.write:
    status, result = call("take_photo")
    images = images_of(result, "take_photo")
    check("take_photo", not result.get("isError") and len(images) == 1, text_of(result))
    status, result = call("start_recording")
    check("start_recording", not result.get("isError"), text_of(result))
    status, result = call("start_recording")
    check("start_recording again → tool error", result.get("isError") is True, text_of(result))
    time.sleep(3)
    status, result = call("stop_recording")
    check("stop_recording", not result.get("isError"), text_of(result))
    status, result = call("stop_recording")
    check("stop_recording again → tool error", result.get("isError") is True, text_of(result))
    if "set_job" in tools:
        job = s.get("job") or ""
        status, result = call("set_job", {"job": "PR-SMOKE-1"})
        check("set_job", not result.get("isError"), text_of(result))
        status, result = call("set_job", {"job": "../nope"})
        check("set_job invalid → tool error", result.get("isError") is True, text_of(result))
        status, result = call("set_job", {"job": job})
        check("set_job back", not result.get("isError"), text_of(result))
    else:
        status, result = call("set_job", {"job": "PR-1"})
        check("set_job without jobs → tool error", result.get("isError") is True, text_of(result))

status, result = call("list_captures", {"limit": 5})
captures = result.get("structuredContent", {}).get("captures", [])
check("list_captures", status == 200 and not result.get("isError"),
      "; ".join(f"{c['name']} {c['kind']} {c['sizeBytes']} B" for c in captures))
photo = next((c for c in captures if c["kind"] != "video"), None)
if photo:
    status, result = call("get_capture", {"name": photo["name"], "max_size": 400})
    check("get_capture photo", len(images_of(result, "get_capture")) == 1, photo["name"])
video = next((c for c in captures if c["kind"] == "video"), None)
if video:
    status, result = call("get_capture", {"name": video["name"]})
    check("get_capture video = metadata only",
          not images_of(result, "video") and result.get("structuredContent", {}).get("kind") == "video", video["name"])
status, result = call("get_capture", {"name": "../../etc/passwd"})
check("get_capture outside the folder → tool error", result.get("isError") is True, text_of(result))

status, headers, body = post({"jsonrpc": "2.0", "id": 1, "method": "ping"}, token="wrong")
check("wrong token → 401", status == 401, f"WWW-Authenticate: {headers.get('WWW-Authenticate')}")
check("token not echoed", TOKEN not in json.dumps(body))

if opts.lockout:
    codes = [post({"jsonrpc": "2.0", "id": 1, "method": "ping"}, token="wrong")[0] for _ in range(5)]
    status, headers, _ = post({"jsonrpc": "2.0", "id": 1, "method": "ping"})
    check("locked out, even with the right token → 429", status == 429,
          f"wrong: {codes}, Retry-After: {headers.get('Retry-After')}")

print("FAILED" if failed else "all ok")
sys.exit(1 if failed else 0)
