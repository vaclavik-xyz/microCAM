import MicroCAMCore

/// The whole viewer page: no external assets, no build step.
enum StreamPage {
    static func html(mode: StreamMode, embedded: Bool) -> String {
        template
            .replacingOccurrences(of: "__MODE__", with: mode.rawValue)
            .replacingOccurrences(of: "__EMBEDDED__", with: embedded ? "true" : "false")
    }

    private static let template = #"""
<!doctype html>
<html lang="cs">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>microCAM – živě</title>
<style>
:root{--bg:#07080a;--panel:rgba(24,27,33,.78);--line:rgba(255,255,255,.08);--text:#eef0f4;--muted:#9aa3b2;--accent:#ff3b30}
*{box-sizing:border-box}
html,body{margin:0;height:100%;background:var(--bg);color:var(--text);font:15px/1.3 -apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif;overflow:hidden;-webkit-user-select:none;user-select:none}
#stage{position:fixed;inset:0;display:flex;align-items:center;justify-content:center}
#stage img{max-width:100vw;max-height:100vh;display:block}
#ink{position:fixed;touch-action:none;pointer-events:none}
body.drawing #ink{pointer-events:auto;cursor:crosshair}
.bar{position:fixed;left:50%;transform:translateX(-50%);display:flex;align-items:center;gap:6px;padding:6px;border-radius:16px;background:var(--panel);border:1px solid var(--line);-webkit-backdrop-filter:blur(18px);backdrop-filter:blur(18px);box-shadow:0 10px 30px rgba(0,0,0,.35);transition:opacity .35s}
#top{top:14px;padding:8px 14px;font-weight:600;letter-spacing:.2px}
#top small{color:var(--muted);font-weight:500;margin-left:8px}
#bottom{bottom:18px}
button,.btn{appearance:none;border:0;border-radius:11px;padding:9px 13px;background:rgba(255,255,255,.07);color:var(--text);font:inherit;font-weight:560;cursor:pointer;text-decoration:none;display:inline-flex;align-items:center;gap:6px;white-space:nowrap}
button:hover,.btn:hover{background:rgba(255,255,255,.13)}
button:disabled{opacity:.4;cursor:default}
button.on{background:rgba(255,255,255,.22)}
button.primary{background:var(--accent);color:#fff}
.sep{width:1px;height:24px;background:var(--line);margin:0 4px}
.swatch{width:22px;height:22px;padding:0;border-radius:50%;border:2px solid transparent}
.swatch.on{border-color:#fff}
.group{display:flex;gap:6px;align-items:center}
.hidden{display:none!important}
body.idle .bar{opacity:0;pointer-events:none}
body.image-only .bar,body.image-only #ink{display:none!important}
#offline{position:fixed;inset:0;display:flex;align-items:center;justify-content:center;color:var(--muted);font-size:17px;background:rgba(0,0,0,.55)}
#toast{position:fixed;left:50%;bottom:86px;transform:translateX(-50%);padding:9px 14px;border-radius:12px;background:var(--panel);border:1px solid var(--line);opacity:0;transition:opacity .25s;pointer-events:none}
#toast.show{opacity:1}
</style>
</head>
<body>
<div id="stage"><img id="live" alt=""><img id="shot" class="hidden" alt=""></div>
<canvas id="ink"></canvas>
<div id="offline" class="hidden">Připojuji se k mikroskopu…</div>
<div id="top" class="bar"><span id="job">microCAM</span><small id="state">živě</small></div>
<div id="bottom" class="bar">
  <button id="draw" title="Kreslit do obrazu">✏️ Kreslit</button>
  <span id="tools" class="group hidden">
    <button data-tool="arrow" class="on" title="Šipka">➚</button>
    <button data-tool="ellipse" title="Kruh">◯</button>
    <button data-tool="pen" title="Pero">〰︎</button>
    <span class="sep"></span>
    <button class="swatch on" data-color="#ff3b30" style="background:#ff3b30" title="Červená"></button>
    <button class="swatch" data-color="#ffd60a" style="background:#ffd60a" title="Žlutá"></button>
    <button class="swatch" data-color="#30d158" style="background:#30d158" title="Zelená"></button>
    <button class="swatch" data-color="#0a84ff" style="background:#0a84ff" title="Modrá"></button>
    <span class="sep"></span>
    <button id="clear" title="Smazat kresbu">Smazat</button>
  </span>
  <span class="sep"></span>
  <span id="liveTools" class="group"><button id="photo" class="primary" title="Vyfotit na bench Macu">📷 Vyfotit</button></span>
  <span id="shotTools" class="group hidden">
    <button id="save" class="primary">Uložit k zakázce</button>
    <a id="download" class="btn" download>Stáhnout</a>
    <button id="back">Zpět na živý obraz</button>
  </span>
  <button id="fs" title="Celá obrazovka">⛶</button>
</div>
<div id="toast"></div>
<script>
const MODE = "__MODE__", EMBEDDED = __EMBEDDED__;
const $ = id => document.getElementById(id);
const live = $("live"), shot = $("shot"), ink = $("ink"), ctx = ink.getContext("2d");
let tool = "arrow", color = "#ff3b30", drawing = false, shapes = [], current = null, frozen = null, offline = false;

if (MODE === "imageOnly") document.body.classList.add("image-only");
if (EMBEDDED) $("fs").classList.add("hidden");

// ---- live stream with automatic reconnect ----
function startStream() { live.src = "/stream?t=" + Date.now(); }
function stopStream() { live.removeAttribute("src"); }
live.addEventListener("load", () => { setOffline(false); layout(); });
live.addEventListener("error", () => { if (!frozen) { setOffline(true); setTimeout(startStream, 1500); } });
function setOffline(v) { offline = v; $("offline").classList.toggle("hidden", !v); }

async function poll() {
  try {
    const r = await fetch("/status", { cache: "no-store" });
    const s = await r.json();
    $("job").textContent = s.job ? "Zakázka " + s.job : "Bez zakázky";
    $("photo").disabled = !s.photoEnabled;
    $("photo").title = s.photoEnabled ? "Vyfotit na bench Macu" : "Focení je na bench Macu vypnuté (chybí PIN)";
    if (offline && !frozen) startStream();
  } catch (e) { if (!frozen) setOffline(true); }
  setTimeout(poll, 3000);
}

// ---- canvas over the visible image ----
function target() { return frozen ? shot : live; }
function layout() {
  const r = target().getBoundingClientRect(), dpr = window.devicePixelRatio || 1;
  Object.assign(ink.style, { left: r.left + "px", top: r.top + "px", width: r.width + "px", height: r.height + "px" });
  ink.width = Math.max(1, Math.round(r.width * dpr));
  ink.height = Math.max(1, Math.round(r.height * dpr));
  redraw();
}
window.addEventListener("resize", layout);
shot.addEventListener("load", layout);

function norm(e) {
  const r = ink.getBoundingClientRect();
  return { x: Math.min(Math.max((e.clientX - r.left) / r.width, 0), 1),
           y: Math.min(Math.max((e.clientY - r.top) / r.height, 0), 1) };
}
ink.addEventListener("pointerdown", e => {
  if (!drawing) return;
  ink.setPointerCapture(e.pointerId);
  const p = norm(e);
  current = { kind: tool, points: tool === "pen" ? [p] : [p, p], color, width: 0.006 };
});
ink.addEventListener("pointermove", e => {
  if (!current) return;
  const p = norm(e);
  if (current.kind === "pen") current.points.push(p); else current.points[1] = p;
  redraw();
});
function finish() {
  if (!current) return;
  const [a, b] = [current.points[0], current.points[current.points.length - 1]];
  if (current.points.length > 1 && (Math.abs(a.x - b.x) + Math.abs(a.y - b.y) > 0.005 || current.kind === "pen")) shapes.push(current);
  current = null; redraw();
}
ink.addEventListener("pointerup", finish);
ink.addEventListener("pointercancel", finish);

function redraw() {
  ctx.clearRect(0, 0, ink.width, ink.height);
  for (const s of current ? [...shapes, current] : shapes) drawShape(s, ink.width, ink.height);
}
function drawShape(s, W, H) {
  const P = s.points.map(p => [p.x * W, p.y * H]);
  ctx.strokeStyle = s.color; ctx.lineWidth = Math.max(2, s.width * W); ctx.lineCap = "round"; ctx.lineJoin = "round";
  ctx.beginPath();
  if (s.kind === "pen") {
    P.forEach(([x, y], i) => i ? ctx.lineTo(x, y) : ctx.moveTo(x, y));
  } else {
    const a = P[0], b = P[P.length - 1];
    if (s.kind === "ellipse") {
      ctx.ellipse((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, Math.abs(b[0] - a[0]) / 2, Math.abs(b[1] - a[1]) / 2, 0, 0, Math.PI * 2);
    } else {
      ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]);
      const ang = Math.atan2(b[1] - a[1], b[0] - a[0]), h = Math.max(s.width * W * 4, 12);
      for (const side of [Math.PI * 0.85, -Math.PI * 0.85]) {
        ctx.moveTo(b[0], b[1]); ctx.lineTo(b[0] + h * Math.cos(ang + side), b[1] + h * Math.sin(ang + side));
      }
    }
  }
  ctx.stroke();
}

// ---- toolbar ----
function setDrawing(v) {
  drawing = v;
  document.body.classList.toggle("drawing", v);
  $("draw").classList.toggle("on", v);
  $("tools").classList.toggle("hidden", !v);
}
$("draw").onclick = () => setDrawing(!drawing);
$("clear").onclick = () => { shapes = []; redraw(); };
document.querySelectorAll("[data-tool]").forEach(b => b.onclick = () => {
  tool = b.dataset.tool;
  document.querySelectorAll("[data-tool]").forEach(x => x.classList.toggle("on", x === b));
});
document.querySelectorAll("[data-color]").forEach(b => b.onclick = () => {
  color = b.dataset.color;
  document.querySelectorAll("[data-color]").forEach(x => x.classList.toggle("on", x === b));
});
$("fs").onclick = () => {
  const el = document.documentElement;
  if (document.fullscreenElement || document.webkitFullscreenElement) (document.exitFullscreen || document.webkitExitFullscreen).call(document);
  else (el.requestFullscreen || el.webkitRequestFullscreen).call(el);
};

// ---- photo, annotated copy ----
function toast(text) {
  const t = $("toast"); t.textContent = text; t.classList.add("show");
  clearTimeout(toast.timer); toast.timer = setTimeout(() => t.classList.remove("show"), 2600);
}
function pin() {
  let p = localStorage.getItem("microcamPin");
  if (!p) { p = prompt("PIN pro focení (nastavený na bench Macu)"); if (p) localStorage.setItem("microcamPin", p.trim()); }
  return p && p.trim();
}
async function post(path, body) {
  const p = pin(); if (!p) return null;
  let r;
  try {
    r = await fetch(path, { method: "POST", headers: { "X-MicroCAM-PIN": p, "Content-Type": "application/json" },
                            body: JSON.stringify(body || {}) });
  } catch (e) { toast("bench Mac není dostupný"); return null; }
  if (!(await accepted(r))) return null;
  return r.json();
}
/// Shared handling of refused remote actions; false when `r` is an error.
async function accepted(r) {
  if (r.status === 401) { localStorage.removeItem("microcamPin"); toast("Špatný PIN"); return false; }
  if (r.status === 429) {
    const j = await r.json().catch(() => ({}));
    toast("Příliš mnoho pokusů – zkus to za " + (j.retryAfter || 60) + " s"); return false;
  }
  if (r.status === 403) { toast("Tahle akce je na bench Macu vypnutá"); return false; }
  if (!r.ok) { toast("Chyba " + r.status); return false; }
  return true;
}
// Job photos need the PIN header, so they are fetched and shown as blob URLs.
let shotURL = null, downloadURL = null;
async function fetchCapture(ref) {
  const p = pin(); if (!p) return null;   // prompt cancelled: nothing to report
  let r;
  try {
    r = await fetch(ref.url, { headers: { "X-MicroCAM-PIN": p }, cache: "no-store" });
  } catch (e) { toast("bench Mac není dostupný"); return null; }
  if (!(await accepted(r))) return null;
  try { return URL.createObjectURL(await r.blob()); }
  catch (e) { toast("Fotku se nepodařilo načíst"); return null; }
}
async function setDownload(ref) {
  const url = await fetchCapture(ref); if (!url) return;
  if (downloadURL && downloadURL !== shotURL) URL.revokeObjectURL(downloadURL);
  downloadURL = url; $("download").href = url; $("download").download = ref.name;
}
$("photo").onclick = async () => {
  $("photo").disabled = true;
  const ref = await post("/photo");
  $("photo").disabled = false;
  if (!ref) return;
  const url = await fetchCapture(ref);
  if (!url) return;
  if (downloadURL && downloadURL !== shotURL) URL.revokeObjectURL(downloadURL);
  if (shotURL) URL.revokeObjectURL(shotURL);
  frozen = ref; shapes = [];
  shotURL = downloadURL = url;
  shot.src = url;
  shot.classList.remove("hidden"); live.classList.add("hidden"); stopStream();
  $("liveTools").classList.add("hidden"); $("shotTools").classList.remove("hidden");
  $("state").textContent = "fotka " + ref.name;
  $("download").href = url; $("download").download = ref.name; setDrawing(true);
  toast("Uloženo k zakázce: " + ref.name);
};
$("save").onclick = async () => {
  if (!shapes.length) { toast("Nejdřív něco nakresli"); return; }
  if ($("save").disabled) return;   // one annotated copy per click, even on a double click
  $("save").disabled = true;
  try {
    const ref = await post("/annotated", { source: frozen.name, shapes });
    if (!ref) return;
    await setDownload(ref);
    toast("Uloženo s anotací: " + ref.name);
  } finally { $("save").disabled = false; }
};
$("back").onclick = () => {
  frozen = null; shapes = []; redraw();
  shot.classList.add("hidden"); live.classList.remove("hidden");
  $("shotTools").classList.add("hidden"); $("liveTools").classList.remove("hidden");
  $("state").textContent = "živě"; setDrawing(false); startStream();
};

// ---- hide bars when idle ----
let idleTimer;
function wake() {
  document.body.classList.remove("idle");
  clearTimeout(idleTimer);
  idleTimer = setTimeout(() => { if (!drawing && !frozen) document.body.classList.add("idle"); }, 3000);
}
["pointermove", "pointerdown", "keydown"].forEach(ev => window.addEventListener(ev, wake));

startStream(); poll(); wake();
</script>
</body>
</html>
"""#
}
