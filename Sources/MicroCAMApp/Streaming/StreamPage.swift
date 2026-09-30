import MicroCAMCore

/// The whole viewer page: no external assets, no build step.
///
/// Layout: a small status chip top-left and a dock of floating panels at the
/// bottom (drawing tools above the main actions), so everything stays within
/// thumb reach on a phone in portrait. Phones in landscape get the same
/// panels as a vertical rail on the right, beside the 16:9 image. Every
/// control is at least 44 px and the safe-area insets are respected.
/// `scripts/stream-page-shots.py` renders it on phone, tablet and desktop.
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
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover">
<meta name="theme-color" content="#07080a">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<title>microCAM – živě</title>
<style>
:root{
  --bg:#07080a;--panel:rgba(22,24,29,.84);--raised:rgba(255,255,255,.07);--raised-hi:rgba(255,255,255,.14);
  --on:#eef0f4;--on-ink:#0b0c0f;--line:rgba(255,255,255,.09);--text:#eef0f4;--muted:#9aa3b2;--accent:#ff3b30;
  --hit:44px;--gap:4px;--edge:12px;--reserve-b:0px;--reserve-r:0px;
  --st:env(safe-area-inset-top,0px);--sr:env(safe-area-inset-right,0px);
  --sb:env(safe-area-inset-bottom,0px);--sl:env(safe-area-inset-left,0px);
}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
html,body{margin:0;position:fixed;inset:0;overflow:hidden;background:var(--bg);color:var(--text);
  font:15px/1.25 -apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif;
  -webkit-user-select:none;user-select:none;-webkit-touch-callout:none;
  touch-action:none;overscroll-behavior:none;-webkit-text-size-adjust:100%}
/* the image is centred in the space the main panel leaves free, so it never sits under the controls */
#stage{position:fixed;top:0;left:0;right:var(--reserve-r);bottom:var(--reserve-b);display:flex;align-items:center;justify-content:center}
#stage img{max-width:100%;max-height:100%;display:block;-webkit-user-drag:none}
#ink{position:fixed;touch-action:none;pointer-events:none}
body.drawing #ink{pointer-events:auto;cursor:crosshair}
svg{width:22px;height:22px;flex:none;fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}

/* ---- status chip ---- */
#status{position:fixed;top:calc(var(--st) + var(--edge));left:calc(var(--sl) + var(--edge));
  display:flex;align-items:center;gap:8px;height:30px;padding:0 12px 0 10px;border-radius:15px;
  background:rgba(22,24,29,.62);border:1px solid var(--line);
  -webkit-backdrop-filter:blur(14px);backdrop-filter:blur(14px);
  font-size:12px;font-weight:600;letter-spacing:.06em;text-transform:uppercase;color:var(--muted);transition:opacity .35s}
#status .dot{width:8px;height:8px;border-radius:50%;background:var(--accent);box-shadow:0 0 0 3px rgba(255,59,48,.18)}
#status .job{color:var(--text);letter-spacing:.02em;text-transform:none;font-size:13px;padding-left:9px;border-left:1px solid var(--line)}
body.frozen #status .dot{background:#fff;box-shadow:none}
body.offline #status .dot{background:var(--muted);box-shadow:none}
@media (prefers-reduced-motion:no-preference){
  body:not(.frozen):not(.offline) #status .dot{animation:pulse 2.4s ease-in-out infinite}
  @keyframes pulse{50%{box-shadow:0 0 0 5px rgba(255,59,48,0)}}
}

/* ---- dock of floating panels ---- */
#dock{position:fixed;left:0;right:0;bottom:0;display:flex;flex-direction:column;align-items:center;gap:8px;
  padding:0 calc(var(--sr) + var(--edge)) calc(var(--sb) + var(--edge)) calc(var(--sl) + var(--edge));
  pointer-events:none;transition:opacity .35s}
.panel{display:flex;align-items:center;gap:var(--gap);padding:5px;border-radius:28px;max-width:100%;
  background:var(--panel);border:1px solid var(--line);pointer-events:auto;
  -webkit-backdrop-filter:blur(20px) saturate(1.4);backdrop-filter:blur(20px) saturate(1.4);
  box-shadow:inset 0 1px 0 rgba(255,255,255,.06),0 14px 36px rgba(0,0,0,.45)}
.group{display:flex;align-items:center;gap:var(--gap)}
.sep{width:1px;height:26px;background:var(--line);margin:0 4px;flex:none}
button,.btn{appearance:none;border:0;margin:0;font:inherit;color:var(--text);cursor:pointer;text-decoration:none;
  display:inline-flex;align-items:center;justify-content:center;gap:7px;flex:none;
  min-width:var(--hit);height:var(--hit);padding:0 13px;border-radius:999px;background:transparent;
  font-weight:600;white-space:nowrap;touch-action:manipulation;transition:background .15s,opacity .15s,transform .1s}
button.icon,.btn.icon{width:var(--hit);padding:0}
@media (hover:hover){button:hover:not(:disabled),.btn:hover{background:var(--raised-hi)}}
button:active:not(:disabled),.btn:active{transform:scale(.94)}
button:focus-visible,.btn:focus-visible{outline:2px solid #fff;outline-offset:2px}
button.on,button.on:hover{background:var(--on)!important;color:var(--on-ink)}
button:disabled{opacity:.38;cursor:default}
/* the main action reads as a shutter: solid red with a thin inner ring */
button.primary{background:var(--accent);color:#fff;padding:0 24px;height:52px;border-radius:999px;font-size:16px;
  letter-spacing:.01em;box-shadow:inset 0 0 0 2px rgba(255,255,255,.22),0 8px 22px rgba(255,59,48,.32)}
@media (hover:hover){button.primary:hover:not(:disabled){background:#ff5247}}
/* WebKit greys out disabled text; keep the words white and dim the whole button instead */
button:disabled{color:var(--text)}
button.primary:disabled{opacity:1;background:rgba(255,59,48,.28);color:rgba(255,255,255,.55);
  -webkit-text-fill-color:rgba(255,255,255,.55);box-shadow:inset 0 0 0 1px rgba(255,59,48,.35)}
#photo{min-width:148px}
.chip-color{width:24px;height:24px;border-radius:50%;background:var(--c,#ff3b30);box-shadow:0 0 0 2px rgba(255,255,255,.9)}
#colorBtn[aria-expanded=true]{background:var(--raised-hi)}
.swatch{width:var(--hit);padding:0}
.swatch i{width:26px;height:26px;border-radius:50%;background:var(--c)}
.swatch.on,.swatch.on:hover{background:transparent!important}
.swatch.on i{box-shadow:0 0 0 3px #16181d,0 0 0 5px #fff}
.hidden{display:none!important}
body.idle #dock,body.idle #status{opacity:0;pointer-events:none}
body.idle #dock .panel{pointer-events:none}
body.image-only #dock,body.image-only #status,body.image-only #ink{display:none!important}

/* narrow phones: secondary buttons show icons only, the main action keeps its words */
@media (max-width:520px){ .lbl{display:none} #draw{width:var(--hit);padding:0} }
/* the smallest phones (320 px): tighter spacing, no dividers */
@media (max-width:360px){ :root{--gap:2px;--edge:8px} .sep{display:none} #photo{min-width:132px} }

#offline{position:fixed;inset:0;display:flex;align-items:center;justify-content:center;padding:24px;text-align:center;
  color:var(--muted);font-size:17px;background:rgba(0,0,0,.55)}
#toast{position:absolute;left:50%;bottom:calc(100% + 10px);transform:translateX(-50%);
  width:max-content;max-width:calc(100vw - 2 * var(--edge) - var(--sl) - var(--sr));
  padding:9px 16px;border-radius:14px;background:var(--panel);border:1px solid var(--line);
  -webkit-backdrop-filter:blur(20px);backdrop-filter:blur(20px);font-size:14px;font-weight:600;text-align:center;
  opacity:0;transition:opacity .25s;pointer-events:none}
#toast.show{opacity:1}
/* file names go on their own line and never break mid-name */
#toast small{display:block;margin-top:2px;font-size:12px;font-weight:500;color:var(--muted);
  white-space:nowrap;overflow:hidden;text-overflow:ellipsis;font-variant-numeric:tabular-nums}

/* ---- PIN panel ---- */
#pinDialog{position:fixed;inset:0;z-index:10;display:flex;justify-content:center;align-items:flex-start;
  padding:calc(var(--st) + min(12vh, 88px)) calc(var(--sr) + 16px) 16px calc(var(--sl) + 16px);
  background:rgba(4,5,7,.62);-webkit-backdrop-filter:blur(8px);backdrop-filter:blur(8px)}
.card{width:min(360px,100%);padding:22px 20px 18px;border-radius:28px;background:rgba(24,26,32,.96);
  border:1px solid var(--line);box-shadow:inset 0 1px 0 rgba(255,255,255,.06),0 24px 60px rgba(0,0,0,.55)}
.card h2{margin:0 0 6px;font-size:18px;font-weight:700;letter-spacing:-.01em}
.card p{margin:0 0 16px;color:var(--muted);font-size:14px;line-height:1.4}
#pinInput{display:block;width:100%;height:58px;margin:0;border-radius:16px;border:1px solid var(--line);
  background:rgba(255,255,255,.06);color:var(--text);text-align:center;outline:none;
  font:600 26px/1 ui-monospace,"SF Mono",Menlo,monospace;letter-spacing:.4em;text-indent:.4em;
  -webkit-user-select:text;user-select:text;touch-action:manipulation;transition:border-color .15s,background .15s}
#pinInput::placeholder{color:rgba(255,255,255,.18)}
#pinInput:focus{border-color:rgba(255,255,255,.45);background:rgba(255,255,255,.09)}
#pinInput:disabled{opacity:.5}
.card.error #pinInput{border-color:#ff6961}
#pinNote{min-height:20px;margin:8px 2px 10px;font-size:13px;font-weight:600;color:#ff6961;font-variant-numeric:tabular-nums}
.card .row{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.card .row button{height:50px;width:100%;border-radius:999px;font-size:16px}
.card .row button.primary{padding:0}
#pinCancel{background:var(--raised)}
@media (hover:hover){#pinCancel:hover{background:var(--raised-hi)}}

/* ---- phones in landscape: a vertical rail on the right, beside the image ---- */
@media (orientation:landscape) and (max-height:500px){
  :root{--edge:8px}
  /* main actions at the right edge under the thumb, drawing tools and colours to their left */
  #dock{top:0;bottom:0;left:auto;flex-direction:row;justify-content:flex-end;align-items:center;
    padding:calc(var(--st) + var(--edge)) calc(var(--sr) + var(--edge)) calc(var(--sb) + var(--edge)) 0}
  .panel,.group{flex-direction:column}
  .sep{width:26px;height:1px;margin:3px 0}
  .lbl{display:none}
  #draw{width:var(--hit);padding:0}
  button.primary{width:64px;height:64px;min-width:0;padding:0;flex-direction:column;gap:1px;font-size:11px}
  #photo{min-width:0}
  #toast{position:fixed;left:50%;top:calc(var(--st) + var(--edge));bottom:auto;max-width:60vw}
  #pinDialog{padding-top:calc(var(--st) + 10px)}
  .card{padding:16px 18px 14px}
  .card p{margin-bottom:10px}
  #pinInput{height:50px}
  #pinNote{margin:6px 2px 8px}
  .card .row button{height:46px}
}
@media (orientation:landscape) and (max-height:340px){ :root{--gap:2px} .sep{display:none} }
</style>
</head>
<body>
<div id="stage"><img id="live" alt=""><img id="shot" class="hidden" alt=""></div>
<canvas id="ink"></canvas>
<div id="offline" class="hidden">Připojuji se k mikroskopu…</div>
<div id="status"><span class="dot"></span><span id="stateLabel">Živě</span><span id="job" class="job hidden"></span></div>
<div id="dock">
  <div id="toast" role="status" aria-live="polite"></div>
  <div id="swatches" class="panel hidden" aria-label="Barva">
    <button class="swatch on" data-color="#ff3b30" style="--c:#ff3b30" aria-label="Červená"><i></i></button>
    <button class="swatch" data-color="#ffd60a" style="--c:#ffd60a" aria-label="Žlutá"><i></i></button>
    <button class="swatch" data-color="#30d158" style="--c:#30d158" aria-label="Zelená"><i></i></button>
    <button class="swatch" data-color="#0a84ff" style="--c:#0a84ff" aria-label="Modrá"><i></i></button>
  </div>
  <div id="palette" class="panel hidden" aria-label="Kreslení">
    <button class="icon on" data-tool="arrow" aria-label="Šipka" title="Šipka"><svg viewBox="0 0 24 24"><path d="M5 19 19 5M9 5h10v10"/></svg></button>
    <button class="icon" data-tool="ellipse" aria-label="Kruh" title="Kruh"><svg viewBox="0 0 24 24"><ellipse cx="12" cy="12" rx="8.5" ry="7"/></svg></button>
    <button class="icon" data-tool="pen" aria-label="Pero" title="Pero"><svg viewBox="0 0 24 24"><path d="M3 15c2.5-5 4.5-7 6-5s1 6 3.5 6S17 9 21 8"/></svg></button>
    <span class="sep"></span>
    <button id="colorBtn" class="icon" aria-label="Barva" title="Barva"><span class="chip-color"></span></button>
    <span class="sep"></span>
    <button id="undo" class="icon" aria-label="Vrátit poslední tah" title="Vrátit poslední tah"><svg viewBox="0 0 24 24"><path d="M9 14 4 9l5-5"/><path d="M4 9h10a6 6 0 0 1 0 12h-3"/></svg></button>
    <button id="clear" class="icon" aria-label="Smazat kresbu" title="Smazat kresbu"><svg viewBox="0 0 24 24"><path d="M4 7h16M10 11v6M14 11v6M6 7l1 12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-12M9 7V4h6v3"/></svg></button>
  </div>
  <div id="controls" class="panel">
    <span id="liveTools" class="group">
      <button id="draw" aria-label="Kreslit" title="Kreslit do obrazu"><svg viewBox="0 0 24 24"><path d="M4 20h4L19 9a2.8 2.8 0 0 0-4-4L4 16v4Z"/><path d="m13.5 6.5 4 4"/></svg><span class="lbl">Kreslit</span></button>
      <button id="photo" class="primary" title="Vyfotit do zakázky"><svg viewBox="0 0 24 24"><path d="M4 8h3l2-3h6l2 3h3a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1Z"/><circle cx="12" cy="13" r="3.5"/></svg><span>Vyfotit</span></button>
    </span>
    <span id="shotTools" class="group hidden">
      <button id="back" aria-label="Zpět na živý obraz" title="Zpět na živý obraz"><svg viewBox="0 0 24 24"><path d="M15 5 8 12l7 7"/></svg><span class="lbl">Živý obraz</span></button>
      <button id="save" class="primary" title="Uložit kresbu do nové fotky u zakázky"><svg viewBox="0 0 24 24"><path d="m5 12.5 4.5 4.5L19 7.5"/></svg><span>Uložit<span class="lbl"> k zakázce</span></span></button>
      <a id="download" class="btn" download aria-label="Stáhnout" title="Stáhnout"><svg viewBox="0 0 24 24"><path d="M12 4v11M7 10.5l5 5 5-5M5 20h14"/></svg><span class="lbl">Stáhnout</span></a>
    </span>
    <button id="fs" class="icon" aria-label="Celá obrazovka" title="Celá obrazovka"><svg viewBox="0 0 24 24"><path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/></svg></button>
  </div>
</div>
<div id="pinDialog" class="hidden" role="dialog" aria-modal="true" aria-labelledby="pinTitle">
  <form id="pinForm" class="card" autocomplete="off">
    <h2 id="pinTitle">PIN pro focení</h2>
    <p>Zadej PIN z microCAMu na počítači s kamerou (Nastavení → Přenos).</p>
    <input id="pinInput" name="pin" type="password" inputmode="numeric" pattern="[0-9]*" autocomplete="one-time-code"
           minlength="4" maxlength="8" placeholder="••••" aria-describedby="pinNote">
    <div id="pinNote" aria-live="polite"></div>
    <div class="row">
      <button id="pinCancel" type="button">Zrušit</button>
      <button id="pinOk" type="submit" class="primary" disabled>Potvrdit</button>
    </div>
  </form>
</div>
<script>
const MODE = "__MODE__", EMBEDDED = __EMBEDDED__;
const $ = id => document.getElementById(id);
const live = $("live"), shot = $("shot"), ink = $("ink"), ctx = ink.getContext("2d");
let tool = "arrow", color = "#ff3b30", drawing = false, shapes = [], current = null, frozen = null, offline = false;

if (MODE === "imageOnly") document.body.classList.add("image-only");
// iPhone Safari has no element full screen; the viewer app has its own.
const root = document.documentElement;
if (EMBEDDED || !(root.requestFullscreen || root.webkitRequestFullscreen)) $("fs").classList.add("hidden");
// No page zoom or scroll: pinch and double-tap would move the image under the drawing.
document.addEventListener("gesturestart", e => e.preventDefault());
document.addEventListener("dblclick", e => e.preventDefault());

// ---- live stream with automatic reconnect ----
function startStream() { live.src = "/stream?t=" + Date.now(); }
function stopStream() { live.removeAttribute("src"); }
live.addEventListener("load", () => { setOffline(false); layout(); });
live.addEventListener("error", () => { if (!frozen) { setOffline(true); setTimeout(startStream, 1500); } });
function setOffline(v) {
  offline = v;
  $("offline").classList.toggle("hidden", !v);
  document.body.classList.toggle("offline", v);
  setState();
}
function setState() {
  $("stateLabel").textContent = frozen ? "Fotka" : offline ? "Nepřipojeno" : "Živě";
  document.body.classList.toggle("frozen", !!frozen);
}

async function poll() {
  try {
    const r = await fetch("/status", { cache: "no-store" });
    const s = await r.json();
    $("job").textContent = s.job || "";
    $("job").classList.toggle("hidden", !s.job);
    $("photo").disabled = !s.photoEnabled;
    $("photo").title = s.photoEnabled ? "Vyfotit do zakázky"
      : "Focení je vypnuté – v microCAMu na počítači s kamerou není nastavený PIN (Nastavení → Přenos)";
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
window.addEventListener("orientationchange", () => setTimeout(layout, 250));
shot.addEventListener("load", layout);
// Keep the image clear of the main panel and, while drawing, of the tools: above them in
// portrait, beside the rail in landscape. The colour popover is transient and may overlap.
function reserve() {
  const rail = getComputedStyle($("dock")).flexDirection === "row";
  const rects = ["palette", "controls"].map(id => $(id).getBoundingClientRect()).filter(r => r.width > 0);
  const off = MODE === "imageOnly" || !rects.length;
  const top = Math.min(...rects.map(r => r.top)), left = Math.min(...rects.map(r => r.left));
  root.style.setProperty("--reserve-b", off || rail ? "0px" : (innerHeight - top + 8) + "px");
  root.style.setProperty("--reserve-r", off || !rail ? "0px" : (innerWidth - left + 8) + "px");
  layout();
}
// Deferred to the next frame: resizing inside the observer callback would loop.
let relayout = 0;
function scheduleReserve() { cancelAnimationFrame(relayout); relayout = requestAnimationFrame(reserve); }
if (window.ResizeObserver) {
  new ResizeObserver(scheduleReserve).observe($("controls"));
  new ResizeObserver(scheduleReserve).observe($("palette"));
  new ResizeObserver(scheduleReserve).observe($("stage"));
}
window.addEventListener("resize", scheduleReserve);

function norm(e) {
  const r = ink.getBoundingClientRect();
  return { x: Math.min(Math.max((e.clientX - r.left) / r.width, 0), 1),
           y: Math.min(Math.max((e.clientY - r.top) / r.height, 0), 1) };
}
ink.addEventListener("pointerdown", e => {
  if (!drawing) return;
  e.preventDefault();
  ink.setPointerCapture(e.pointerId);
  showSwatches(false);
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
  $("undo").disabled = $("clear").disabled = !shapes.length;
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
  $("draw").setAttribute("aria-pressed", v);
  $("palette").classList.toggle("hidden", !v);
  if (!v) showSwatches(false);
  scheduleReserve();
  wake();
}
function showSwatches(v) {
  $("swatches").classList.toggle("hidden", !v);
  $("colorBtn").setAttribute("aria-expanded", v);
}
$("draw").onclick = () => setDrawing(!drawing);
$("undo").onclick = () => { shapes.pop(); redraw(); };
$("clear").onclick = () => { shapes = []; redraw(); };
$("colorBtn").onclick = () => showSwatches($("swatches").classList.contains("hidden"));
document.querySelectorAll("[data-tool]").forEach(b => b.onclick = () => {
  tool = b.dataset.tool;
  document.querySelectorAll("[data-tool]").forEach(x => x.classList.toggle("on", x === b));
});
document.querySelectorAll("[data-color]").forEach(b => b.onclick = () => {
  color = b.dataset.color;
  document.querySelectorAll("[data-color]").forEach(x => x.classList.toggle("on", x === b));
  document.querySelector(".chip-color").style.setProperty("--c", color);
  showSwatches(false);
});
$("fs").onclick = () => {
  if (document.fullscreenElement || document.webkitFullscreenElement) (document.exitFullscreen || document.webkitExitFullscreen).call(document);
  else (root.requestFullscreen || root.webkitRequestFullscreen).call(root);
};

// ---- photo, annotated copy ----
function toast(text, file) {
  const t = $("toast"); t.textContent = text;
  if (file) { const s = document.createElement("small"); s.textContent = file; t.append(s); }
  t.classList.add("show");
  clearTimeout(toast.timer); toast.timer = setTimeout(() => t.classList.remove("show"), 2600);
}
// ---- PIN: asked in a panel, remembered in localStorage once the camera computer accepts it ----
const PIN_KEY = "microcamPin";
let pinDone = null, pinTimer = 0;
const validPin = v => /^[0-9]{4,8}$/.test(v);
function pinNote(text, error) {
  $("pinNote").textContent = text || "";
  $("pinForm").classList.toggle("error", !!error);
}
/// Shows the panel; resolves with the PIN, or null when cancelled. `state` is
/// {wrong: true} after a refused PIN or {locked: seconds, pin} during the lockout.
function askPin(state) {
  const input = $("pinInput");
  clearInterval(pinTimer);
  input.disabled = false;
  input.value = state && state.pin || "";
  pinNote(state && state.wrong ? "Špatný PIN. Zkus to znovu." : "", state && state.wrong);
  if (state && state.locked) {
    let left = state.locked;
    input.disabled = true;
    const tick = () => {
      if (left <= 0) {
        clearInterval(pinTimer); input.disabled = false;
        pinNote("Můžeš to zkusit znovu.", false); pinChanged(); input.focus(); return;
      }
      pinNote("Příliš mnoho špatných pokusů. Znovu za " + left + " s.", true);
      left -= 1;
    };
    tick(); pinTimer = setInterval(tick, 1000);
  }
  pinChanged();
  $("pinDialog").classList.remove("hidden");
  if (!input.disabled) setTimeout(() => input.focus(), 30);
  return new Promise(resolve => { pinDone = resolve; });
}
function closePin(value) {
  clearInterval(pinTimer);
  $("pinDialog").classList.add("hidden");
  $("pinInput").blur();
  const done = pinDone; pinDone = null;
  if (done) done(value);
}
function pinChanged() {
  const input = $("pinInput"), digits = input.value.replace(/[^0-9]/g, "").slice(0, 8);
  if (digits !== input.value) input.value = digits;
  $("pinOk").disabled = input.disabled || !validPin(digits);
}
// Typing again clears the "wrong PIN" note (the input is disabled during a lockout).
$("pinInput").addEventListener("input", () => { pinChanged(); if ($("pinForm").classList.contains("error")) pinNote("", false); });
$("pinForm").addEventListener("submit", e => {
  e.preventDefault();
  const v = $("pinInput").value;
  if (!$("pinOk").disabled && validPin(v)) closePin(v);
});
$("pinCancel").onclick = () => closePin(null);
document.addEventListener("keydown", e => { if (e.key === "Escape" && pinDone) closePin(null); });

/// Runs a remote action with the PIN header. Asks for the PIN when none is
/// stored, again after a wrong one, and shows the lockout in the panel.
/// Returns the accepted response, or null (cancelled or reported by a toast).
async function withPin(send) {
  let p = localStorage.getItem(PIN_KEY), state = null;
  for (;;) {
    if (!p || state) { p = await askPin(state); if (!p) return null; }
    let r;
    try { r = await send(p); } catch (e) { toast("Počítač s kamerou není dostupný"); return null; }
    if (r.status === 401) { localStorage.removeItem(PIN_KEY); state = { wrong: true }; continue; }
    if (r.status === 429) {
      const j = await r.json().catch(() => ({}));
      state = { locked: Math.max(1, j.retryAfter || 60), pin: p }; continue;
    }
    localStorage.setItem(PIN_KEY, p);
    if (r.status === 403) { toast("Tahle akce je v microCAMu na počítači s kamerou vypnutá"); return null; }
    if (!r.ok) { toast("Chyba " + r.status); return null; }
    return r;
  }
}
async function post(path, body) {
  const r = await withPin(p => fetch(path, { method: "POST",
    headers: { "X-MicroCAM-PIN": p, "Content-Type": "application/json" }, body: JSON.stringify(body || {}) }));
  return r && r.json();
}
// Job photos need the PIN header, so they are fetched and shown as blob URLs.
let shotURL = null, downloadURL = null;
async function fetchCapture(ref) {
  const r = await withPin(p => fetch(ref.url, { headers: { "X-MicroCAM-PIN": p }, cache: "no-store" }));
  if (!r) return null;
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
  $("download").href = url; $("download").download = ref.name;
  setState(); setDrawing(true);
  toast("Vyfoceno", ref.name);
};
$("save").onclick = async () => {
  if (!shapes.length) { toast("Nejdřív něco nakresli"); return; }
  if ($("save").disabled) return;   // one annotated copy per click, even on a double click
  $("save").disabled = true;
  try {
    const ref = await post("/annotated", { source: frozen.name, shapes });
    if (!ref) return;
    await setDownload(ref);
    toast("Uloženo k zakázce", ref.name);
  } finally { $("save").disabled = false; }
};
$("back").onclick = () => {
  frozen = null; shapes = []; redraw();
  shot.classList.add("hidden"); live.classList.remove("hidden");
  $("shotTools").classList.add("hidden"); $("liveTools").classList.remove("hidden");
  setState(); setDrawing(false); startStream();
};

// ---- hide the controls when idle; any touch or mouse movement brings them back ----
let idleTimer;
function wake() {
  document.body.classList.remove("idle");
  clearTimeout(idleTimer);
  idleTimer = setTimeout(() => { if (!drawing && !frozen) document.body.classList.add("idle"); }, 3000);
}
["pointermove", "pointerdown", "keydown"].forEach(ev => window.addEventListener(ev, wake));

redraw(); startStream(); poll(); wake();
</script>
</body>
</html>
"""#
}
