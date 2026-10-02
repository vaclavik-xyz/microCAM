import MicroCAMCore

/// The whole viewer page: no external assets, no build step.
///
/// Layout: a small status chip top-left and a dock of floating panels at the
/// bottom (drawing tools above the main actions), so everything stays within
/// thumb reach on a phone in portrait. Phones in landscape get the same
/// panels as a vertical rail on the right, beside the 16:9 image; wide
/// screens one row. The image gets the space the tools and main actions leave
/// free; text sizes and colours open over it, so picking a tool never shrinks
/// the picture. Touch controls are at least 44 px, mouse ones 36 px, and the
/// safe-area insets are respected. Without a PIN on the camera computer the
/// photo button is not shown.
/// `scripts/stream-page-shots.py` renders it on phone, tablet and desktop.
///
/// Texts live in the `STRINGS` dictionary of the script, one entry per
/// language (the same languages as the app). The page picks `?lang=` (the
/// viewer app passes its own), then the browser's languages, else English.
/// `LocalizationTests` checks that every language has every key.
enum StreamPage {
    static func html(mode: StreamMode, embedded: Bool) -> String {
        template
            .replacingOccurrences(of: "__MODE__", with: mode.rawValue)
            .replacingOccurrences(of: "__EMBEDDED__", with: embedded ? "true" : "false")
    }

    private static let template = #"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover">
<meta name="theme-color" content="#07080a">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<title>microCAM</title>
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
body.drawing.tool-text #ink{cursor:text}
/* the label being typed: at least 16 px so phones don't zoom, the label itself keeps its size */
#textEditor{position:fixed;z-index:5;margin:0;padding:0 4px;border:1px dashed rgba(255,255,255,.75);border-radius:4px;
  background:rgba(0,0,0,.35);outline:none;font-weight:600;font-family:-apple-system,BlinkMacSystemFont,system-ui,sans-serif;
  text-shadow:0 0 2px #000,0 0 4px #000;-webkit-user-select:text;user-select:text;touch-action:manipulation}
#textEditor::placeholder{color:rgba(255,255,255,.55)}
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
/* drawing tools and main actions: stacked on a phone, one row on a wide screen */
#bar{display:flex;flex-direction:column;align-items:center;gap:8px;max-width:100%}
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
.size b{font-weight:700;line-height:1}
.hidden{display:none!important}
@media (min-width:760px) and (min-height:501px){ #bar{flex-direction:row;align-items:flex-end} }
/* a mouse needs no thumb-sized targets: smaller buttons, more picture */
@media (hover:hover) and (pointer:fine){
  :root{--hit:36px;--edge:10px}
  .panel{padding:4px;border-radius:24px}
  svg{width:20px;height:20px}
  button,.btn{padding:0 11px;font-size:14px}
  button.primary{height:40px;padding:0 18px;font-size:15px}
  #photo{min-width:0}
  .swatch i{width:22px;height:22px}
  .chip-color{width:20px;height:20px}
}
body.idle #dock,body.idle #status{opacity:0;pointer-events:none}
body.idle #dock .panel{pointer-events:none}
body.image-only #dock,body.image-only #status,body.image-only #ink{display:none!important}

/* narrow phones: secondary buttons show icons only, the main action keeps its words */
@media (max-width:520px){ .lbl{display:none} #draw{width:var(--hit);padding:0} }
/* seven drawing tools fit a 375 px phone only without the dividers */
@media (max-width:400px){ .sep{display:none} }
/* the smallest phones (320 px): tighter spacing, no dividers */
@media (max-width:360px){ :root{--gap:2px;--edge:8px} .sep{display:none} #photo{min-width:132px}
  #palette{flex-wrap:wrap;justify-content:center;max-width:calc(4 * var(--hit) + 3 * var(--gap) + 12px);border-radius:26px} }

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
  #bar{flex-direction:row;align-items:center}
  .sep{width:26px;height:1px;margin:3px 0}
  .lbl{display:none}
  #draw{width:var(--hit);padding:0}
  button.primary{width:64px;height:64px;min-width:0;padding:0;flex-direction:column;gap:1px;font-size:11px}
  #photo{min-width:0}
  /* "Take photo" is wider than the round button: wrap it onto two lines inside. */
  button.primary>span{white-space:normal;max-width:54px;line-height:1.05;text-align:center}
  #toast{position:fixed;left:50%;top:calc(var(--st) + var(--edge));bottom:auto;max-width:60vw}
  #pinDialog{padding-top:calc(var(--st) + 10px)}
  .card{padding:16px 18px 14px}
  .card p{margin-bottom:10px}
  #pinInput{height:50px}
  #pinNote{margin:6px 2px 8px}
  .card .row button{height:46px}
}
@media (orientation:landscape) and (max-height:380px){ :root{--gap:2px} .sep{display:none}
  /* seven tools in two columns of four and three */
  /* (a grid: a column-wrapping flexbox would not grow wider) */
  #palette{display:grid;grid-auto-flow:column;grid-template-rows:repeat(4,var(--hit));border-radius:26px} }
</style>
</head>
<body>
<div id="stage"><img id="live" alt=""><img id="shot" class="hidden" alt=""></div>
<canvas id="ink"></canvas>
<input id="textEditor" class="hidden" type="text" maxlength="200" autocomplete="off" autocapitalize="sentences"
       spellcheck="false" enterkeyhint="done" data-i18n-placeholder="textPlaceholder" data-i18n-aria="text">
<div id="offline" class="hidden" data-i18n="offline"></div>
<div id="status"><span class="dot"></span><span id="stateLabel"></span><span id="job" class="job hidden"></span></div>
<div id="dock">
  <div id="toast" role="status" aria-live="polite"></div>
  <div id="swatches" class="panel hidden" data-i18n-aria="color">
    <button class="swatch on" data-color="#ff3b30" style="--c:#ff3b30" data-i18n-aria="red"><i></i></button>
    <button class="swatch" data-color="#ffd60a" style="--c:#ffd60a" data-i18n-aria="yellow"><i></i></button>
    <button class="swatch" data-color="#30d158" style="--c:#30d158" data-i18n-aria="green"><i></i></button>
    <button class="swatch" data-color="#0a84ff" style="--c:#0a84ff" data-i18n-aria="blue"><i></i></button>
  </div>
  <div id="sizes" class="panel hidden" data-i18n-aria="textSize">
    <button class="icon size" data-size="small" data-i18n-aria="textSmall" data-i18n-title="textSmall"><b style="font-size:13px">A</b></button>
    <button class="icon size on" data-size="medium" data-i18n-aria="textMedium" data-i18n-title="textMedium"><b style="font-size:17px">A</b></button>
    <button class="icon size" data-size="large" data-i18n-aria="textLarge" data-i18n-title="textLarge"><b style="font-size:22px">A</b></button>
  </div>
  <div id="bar">
  <div id="palette" class="panel hidden" data-i18n-aria="drawing">
    <button class="icon on" data-tool="arrow" data-i18n-aria="arrow" data-i18n-title="arrow"><svg viewBox="0 0 24 24"><path d="M5 19 19 5M9 5h10v10"/></svg></button>
    <button class="icon" data-tool="ellipse" data-i18n-aria="circle" data-i18n-title="circle"><svg viewBox="0 0 24 24"><ellipse cx="12" cy="12" rx="8.5" ry="7"/></svg></button>
    <button class="icon" data-tool="pen" data-i18n-aria="pen" data-i18n-title="pen"><svg viewBox="0 0 24 24"><path d="M3 15c2.5-5 4.5-7 6-5s1 6 3.5 6S17 9 21 8"/></svg></button>
    <button class="icon" data-tool="text" data-i18n-aria="text" data-i18n-title="text"><svg viewBox="0 0 24 24"><path d="M5 7V4.5h14V7M12 4.5v15M9 19.5h6"/></svg></button>
    <span class="sep"></span>
    <button id="colorBtn" class="icon" data-i18n-aria="color" data-i18n-title="color"><span class="chip-color"></span></button>
    <span class="sep"></span>
    <button id="undo" class="icon" data-i18n-aria="undo" data-i18n-title="undo"><svg viewBox="0 0 24 24"><path d="M9 14 4 9l5-5"/><path d="M4 9h10a6 6 0 0 1 0 12h-3"/></svg></button>
    <button id="clear" class="icon" data-i18n-aria="clear" data-i18n-title="clear"><svg viewBox="0 0 24 24"><path d="M4 7h16M10 11v6M14 11v6M6 7l1 12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-12M9 7V4h6v3"/></svg></button>
  </div>
  <div id="controls" class="panel">
    <span id="liveTools" class="group">
      <button id="draw" data-i18n-aria="draw" data-i18n-title="drawTitle"><svg viewBox="0 0 24 24"><path d="M4 20h4L19 9a2.8 2.8 0 0 0-4-4L4 16v4Z"/><path d="m13.5 6.5 4 4"/></svg><span class="lbl" data-i18n="draw"></span></button>
      <button id="photo" class="primary" data-i18n-title="photoTitle"><svg viewBox="0 0 24 24"><path d="M4 8h3l2-3h6l2 3h3a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1Z"/><circle cx="12" cy="13" r="3.5"/></svg><span data-i18n="photo"></span></button>
    </span>
    <span id="shotTools" class="group hidden">
      <button id="back" data-i18n-aria="backTitle" data-i18n-title="backTitle"><svg viewBox="0 0 24 24"><path d="M15 5 8 12l7 7"/></svg><span class="lbl" data-i18n="back"></span></button>
      <button id="save" class="primary" data-i18n-title="saveTitle"><svg viewBox="0 0 24 24"><path d="m5 12.5 4.5 4.5L19 7.5"/></svg><span><span data-i18n="save"></span><span class="lbl" data-i18n="saveSuffix"></span></span></button>
      <a id="download" class="btn" download data-i18n-aria="download" data-i18n-title="download"><svg viewBox="0 0 24 24"><path d="M12 4v11M7 10.5l5 5 5-5M5 20h14"/></svg><span class="lbl" data-i18n="download"></span></a>
    </span>
    <button id="fs" class="icon" data-i18n-aria="fullScreen" data-i18n-title="fullScreen"><svg viewBox="0 0 24 24"><path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/></svg></button>
  </div>
  </div>
</div>
<div id="pinDialog" class="hidden" role="dialog" aria-modal="true" aria-labelledby="pinTitle">
  <form id="pinForm" class="card" autocomplete="off">
    <h2 id="pinTitle" data-i18n="pinTitle"></h2>
    <p data-i18n="pinText"></p>
    <input id="pinInput" name="pin" type="password" inputmode="numeric" pattern="[0-9]*" autocomplete="one-time-code"
           minlength="4" maxlength="8" placeholder="••••" aria-describedby="pinNote">
    <div id="pinNote" aria-live="polite"></div>
    <div class="row">
      <button id="pinCancel" type="button" data-i18n="cancel"></button>
      <button id="pinOk" type="submit" class="primary" disabled data-i18n="ok"></button>
    </div>
  </form>
</div>
<script>
const MODE = "__MODE__", EMBEDDED = __EMBEDDED__;
const $ = id => document.getElementById(id);

// ---- texts: one entry per language, the same keys in each ----
const STRINGS = {
  "en": {
    "offline": "Connecting to the camera computer…",
    "stateLive": "Live", "statePhoto": "Photo", "stateOffline": "Offline",
    "color": "Color", "red": "Red", "yellow": "Yellow", "green": "Green", "blue": "Blue",
    "drawing": "Drawing", "arrow": "Arrow", "circle": "Circle", "pen": "Pen", "text": "Text",
    "textSize": "Text size", "textSmall": "Small text", "textMedium": "Medium text", "textLarge": "Large text",
    "textPlaceholder": "Type a label",
    "undo": "Undo last stroke", "clear": "Clear drawing",
    "draw": "Draw", "drawTitle": "Draw on the picture",
    "photo": "Take photo", "photoTitle": "Take a photo on the camera Mac",
    "back": "Live view", "backTitle": "Back to the live picture",
    "save": "Save", "saveSuffix": " as photo", "saveTitle": "Save the drawing as a new photo on the camera Mac",
    "download": "Download", "fullScreen": "Full screen",
    "pinTitle": "PIN for photos",
    "pinText": "Enter the PIN from microCAM on the camera computer (Settings → Stream).",
    "cancel": "Cancel", "ok": "OK",
    "pinWrong": "Wrong PIN. Try again.", "pinRetry": "You can try again now.",
    "pinLocked": "Too many wrong tries. Try again in {seconds}\u00a0s.",
    "unreachable": "The camera computer isn't reachable.",
    "actionOff": "This is turned off in microCAM on the camera computer.",
    "error": "Something went wrong (error {code}).",
    "photoLoadFailed": "Couldn't load the photo.",
    "photoTaken": "Photo taken", "drawFirst": "Draw something first", "savedToJob": "Saved as a photo"
  },
  "cs": {
    "offline": "Připojuji se k počítači s kamerou…",
    "stateLive": "Živě", "statePhoto": "Fotka", "stateOffline": "Nepřipojeno",
    "color": "Barva", "red": "Červená", "yellow": "Žlutá", "green": "Zelená", "blue": "Modrá",
    "drawing": "Kreslení", "arrow": "Šipka", "circle": "Kruh", "pen": "Pero", "text": "Text",
    "textSize": "Velikost textu", "textSmall": "Malý text", "textMedium": "Střední text", "textLarge": "Velký text",
    "textPlaceholder": "Napiš popisek",
    "undo": "Vrátit poslední tah", "clear": "Smazat kresbu",
    "draw": "Kreslit", "drawTitle": "Kreslit do obrazu",
    "photo": "Vyfotit", "photoTitle": "Vyfotit na počítači s kamerou",
    "back": "Živý obraz", "backTitle": "Zpět na živý obraz",
    "save": "Uložit", "saveSuffix": " jako fotku", "saveTitle": "Uložit kresbu jako novou fotku na počítači s kamerou",
    "download": "Stáhnout", "fullScreen": "Celá obrazovka",
    "pinTitle": "PIN pro focení",
    "pinText": "Zadej PIN z microCAMu na počítači s kamerou (Nastavení → Přenos).",
    "cancel": "Zrušit", "ok": "Potvrdit",
    "pinWrong": "Špatný PIN. Zkus to znovu.", "pinRetry": "Teď to můžeš zkusit znovu.",
    "pinLocked": "Příliš mnoho špatných pokusů. Znovu za {seconds}\u00a0s.",
    "unreachable": "Počítač s kamerou není dostupný.",
    "actionOff": "Tohle je v microCAMu na počítači s kamerou vypnuté.",
    "error": "Něco se pokazilo (chyba {code}).",
    "photoLoadFailed": "Fotku se nepodařilo načíst.",
    "photoTaken": "Vyfoceno", "drawFirst": "Nejdřív něco nakresli", "savedToJob": "Uloženo jako fotka"
  }
}; // end STRINGS
// ?lang= (the viewer app passes its own), then the browser's languages, else English.
const LANG = [new URLSearchParams(location.search).get("lang"), ...(navigator.languages || [navigator.language])]
  .map(l => (l || "").toLowerCase().split("-")[0]).find(l => STRINGS[l]) || "en";
function t(key, vars) {
  let text = STRINGS[LANG][key] ?? STRINGS.en[key] ?? key;
  for (const [k, v] of Object.entries(vars || {})) text = text.replace("{" + k + "}", v);
  return text;
}
document.documentElement.lang = LANG;
document.querySelectorAll("[data-i18n]").forEach(e => e.textContent = t(e.dataset.i18n));
document.querySelectorAll("[data-i18n-title]").forEach(e => e.title = t(e.dataset.i18nTitle));
document.querySelectorAll("[data-i18n-aria]").forEach(e => e.setAttribute("aria-label", t(e.dataset.i18nAria)));
document.querySelectorAll("[data-i18n-placeholder]").forEach(e => e.placeholder = t(e.dataset.i18nPlaceholder));
const live = $("live"), shot = $("shot"), ink = $("ink"), ctx = ink.getContext("2d");
let tool = "arrow", color = "#ff3b30", drawing = false, shapes = [], current = null, frozen = null, offline = false;
// Text labels: the same numbers as AnnotationTextLayout and AnnotationTextSize in the app, so a
// label lands in the saved photo where it was typed.
const LINE = 1.2, BASE = 0.9, OUTLINE = 0.12, MARGIN = 0.15, SIZES = { small: 0.03, medium: 0.045, large: 0.07 };
const FONT = "-apple-system,BlinkMacSystemFont,system-ui,sans-serif";
let textSize = "medium", editing = null, textDrag = null;

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
  $("stateLabel").textContent = frozen ? t("statePhoto") : offline ? t("stateOffline") : t("stateLive");
  document.body.classList.toggle("frozen", !!frozen);
}

async function poll() {
  try {
    const r = await fetch("/status", { cache: "no-store" });
    const s = await r.json();
    $("job").textContent = s.job || "";
    $("job").classList.toggle("hidden", !s.job);
    // Without a PIN on the camera computer nobody can take a photo: no button.
    $("photo").classList.toggle("hidden", !s.photoEnabled);
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
  placeEditor();
}
window.addEventListener("resize", layout);
window.addEventListener("orientationchange", () => setTimeout(layout, 250));
shot.addEventListener("load", layout);
// Keep the image clear of the main panel and, while drawing, of the tools: above them in portrait and on
// wide screens (one row, so drawing doesn't shrink the picture there), beside the rail in landscape.
// Text sizes and colours are transient popovers and may overlap it.
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
  showSwatches(false);
  const p = norm(e);
  if (tool === "text") {
    // Tapping elsewhere finishes the label being typed.
    if (editing) { commitText(); return; }
    ink.setPointerCapture(e.pointerId);
    const s = textAt(p), b = s && textBox(s, ink.width, ink.height);
    textDrag = { shape: s, start: p, from: s ? { x: b.x / ink.width, y: b.y / ink.height } : p, moved: false };
    return;
  }
  ink.setPointerCapture(e.pointerId);
  current = { kind: tool, points: tool === "pen" ? [p] : [p, p], color, width: 0.006 };
});
ink.addEventListener("pointermove", e => {
  if (textDrag) { moveText(e); return; }
  if (!current) return;
  const p = norm(e);
  if (current.kind === "pen") current.points.push(p); else current.points[1] = p;
  redraw();
});
function finish() {
  if (textDrag) { finishText(); return; }
  if (!current) return;
  const [a, b] = [current.points[0], current.points[current.points.length - 1]];
  if (current.points.length > 1 && (Math.abs(a.x - b.x) + Math.abs(a.y - b.y) > 0.005 || current.kind === "pen")) shapes.push(current);
  current = null; redraw();
}
ink.addEventListener("pointerup", finish);
ink.addEventListener("pointercancel", () => { textDrag = null; finish(); });

// ---- text labels: tap to place, Enter or a tap elsewhere to finish, Esc to cancel;
//      tap a label to edit it, drag it to move it ----
const clamp01 = v => Math.min(Math.max(v, 0), 1);
/// The label's box in canvas pixels, kept inside the picture like the app does.
/// A label too wide for the picture gets a smaller font; the outline and accents keep MARGIN free.
function textBox(s, W, H) {
  let px = s.fontSize * H, w = 0;
  for (let i = 0; i < 5; i++) {
    ctx.font = "600 " + px + "px " + FONT;
    w = ctx.measureText(s.text).width;
    if (w + 2 * MARGIN * px <= W) break;
    px = px * W / (w + 2 * MARGIN * px) * 0.995;
  }
  ctx.font = "600 " + px + "px " + FONT;
  w = ctx.measureText(s.text).width;
  const h = px * LINE, m = MARGIN * px;
  return { x: Math.min(Math.max(s.points[0].x * W, m), Math.max(W - w - m, m)),
           y: Math.min(Math.max(s.points[0].y * H, m), Math.max(H - h - m, m)), w, h, px };
}
function textAt(p) {
  const x = p.x * ink.width, y = p.y * ink.height, pad = 6 * (window.devicePixelRatio || 1);
  for (let i = shapes.length - 1; i >= 0; i--) {
    const s = shapes[i];
    if (s.kind !== "text") continue;
    const b = textBox(s, ink.width, ink.height);
    if (x >= b.x - pad && x <= b.x + b.w + pad && y >= b.y - pad && y <= b.y + b.h + pad) return s;
  }
  return null;
}
function moveText(e) {
  const d = textDrag, p = norm(e), r = ink.getBoundingClientRect();
  if (!d.shape) return;
  const dx = p.x - d.start.x, dy = p.y - d.start.y;
  if (!d.moved && Math.hypot(dx * r.width, dy * r.height) < 4) return;
  d.moved = true;
  d.shape.points = [{ x: clamp01(d.from.x + dx), y: clamp01(d.from.y + dy) }];
  redraw();
}
function finishText() {
  const d = textDrag; textDrag = null;
  if (!d.moved) openEditor(d.shape, d.shape ? d.shape.points[0] : d.start);
}
function sizeName(fontSize) {
  return Object.keys(SIZES).reduce((a, b) => Math.abs(SIZES[b] - fontSize) < Math.abs(SIZES[a] - fontSize) ? b : a);
}
function openEditor(shape, point) {
  editing = { shape, point };
  if (shape) { selectColor(shape.color); selectSize(sizeName(shape.fontSize)); }
  const input = $("textEditor");
  input.value = shape ? shape.text : "";
  input.classList.remove("hidden");
  placeEditor();
  input.focus();
  redraw();
}
/// The editor sits where the label will be drawn, in its colour; it grows with the text.
function placeEditor() {
  if (!editing) return;
  const input = $("textEditor"), r = ink.getBoundingClientRect(), dpr = ink.width / Math.max(r.width, 1);
  const b = textBox({ points: [editing.point], fontSize: SIZES[textSize], text: input.value || "M" }, ink.width, ink.height);
  const size = Math.max(16, b.px / dpr);
  ctx.font = "600 " + size + "px " + FONT;
  const width = Math.min(innerWidth - 8, ctx.measureText(input.value || input.placeholder).width + size + 12);
  Object.assign(input.style, { fontSize: size + "px", height: Math.round(size * LINE + 2) + "px", width: width + "px",
    left: Math.max(4, Math.min(r.left + b.x / dpr - 5, innerWidth - width - 4)) + "px", top: (r.top + b.y / dpr - 1) + "px",
    color });
}
function closeEditor() {
  editing = null;
  $("textEditor").classList.add("hidden");
  $("textEditor").blur();
}
function commitText() {
  if (!editing) return;
  const e = editing, text = [...$("textEditor").value.replace(/\s+/g, " ").trim()].slice(0, 200).join("");
  closeEditor();
  if (e.shape && !text) shapes.splice(shapes.indexOf(e.shape), 1);
  else if (e.shape) Object.assign(e.shape, { text, color, fontSize: SIZES[textSize] });
  else if (text) shapes.push({ kind: "text", points: [e.point], color, width: 0.006, text, fontSize: SIZES[textSize] });
  redraw();
}
function cancelText() { closeEditor(); redraw(); }
$("textEditor").addEventListener("keydown", e => {
  e.stopPropagation();   // Escape here cancels the label, not the PIN panel
  if (e.key === "Enter" && !e.isComposing) { e.preventDefault(); commitText(); }
  else if (e.key === "Escape") { e.preventDefault(); cancelText(); }
});
$("textEditor").addEventListener("input", placeEditor);
$("textEditor").addEventListener("blur", () => setTimeout(commitText, 0));
// Colour and size buttons keep the focus in the editor, so they restyle the label being typed.
document.querySelectorAll("#swatches button, #sizes button, #colorBtn").forEach(b =>
  ["pointerdown", "mousedown"].forEach(ev => b.addEventListener(ev, e => { if (editing) e.preventDefault(); })));

function redraw() {
  ctx.clearRect(0, 0, ink.width, ink.height);
  for (const s of current ? [...shapes, current] : shapes) drawShape(s, ink.width, ink.height);
  $("undo").disabled = $("clear").disabled = !shapes.length;
}
function drawShape(s, W, H) {
  if (s.kind === "text") {
    if (editing && editing.shape === s) return;   // the editor shows it meanwhile
    const b = textBox(s, W, H);
    ctx.lineJoin = "round"; ctx.lineWidth = OUTLINE * b.px * 2; ctx.strokeStyle = "rgba(0,0,0,.75)";
    ctx.textBaseline = "alphabetic";
    ctx.strokeText(s.text, b.x, b.y + BASE * b.px);
    ctx.fillStyle = s.color;
    ctx.fillText(s.text, b.x, b.y + BASE * b.px);
    return;
  }
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
  if (!v) commitText();
  drawing = v;
  document.body.classList.toggle("drawing", v);
  $("draw").classList.toggle("on", v);
  $("draw").setAttribute("aria-pressed", v);
  $("palette").classList.toggle("hidden", !v);
  showSizes();
  if (!v) showSwatches(false);
  scheduleReserve();
  wake();
}
function showSwatches(v) {
  $("swatches").classList.toggle("hidden", !v);
  $("colorBtn").setAttribute("aria-expanded", v);
}
$("draw").onclick = () => setDrawing(!drawing);
function showSizes() { $("sizes").classList.toggle("hidden", !(drawing && tool === "text")); scheduleReserve(); }
$("undo").onclick = () => { commitText(); shapes.pop(); redraw(); };
$("clear").onclick = () => { closeEditor(); shapes = []; redraw(); };
$("colorBtn").onclick = () => showSwatches($("swatches").classList.contains("hidden"));
document.querySelectorAll("[data-tool]").forEach(b => b.onclick = () => {
  if (b.dataset.tool !== "text") commitText();
  tool = b.dataset.tool;
  document.querySelectorAll("[data-tool]").forEach(x => x.classList.toggle("on", x === b));
  document.body.classList.toggle("tool-text", tool === "text");
  showSizes();
});
function selectColor(c) {
  color = c;
  document.querySelectorAll("[data-color]").forEach(x => x.classList.toggle("on", x.dataset.color === c));
  document.querySelector(".chip-color").style.setProperty("--c", color);
  placeEditor();
}
function selectSize(name) {
  textSize = name;
  document.querySelectorAll("[data-size]").forEach(x => x.classList.toggle("on", x.dataset.size === name));
  placeEditor();
}
document.querySelectorAll("[data-color]").forEach(b => b.onclick = () => { selectColor(b.dataset.color); showSwatches(false); });
document.querySelectorAll("[data-size]").forEach(b => b.onclick = () => selectSize(b.dataset.size));
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
  // One panel at a time: a second caller cancels the first one's wait, so no
  // caller is left awaiting a promise that never settles.
  if (pinDone) closePin(null);
  const input = $("pinInput");
  clearInterval(pinTimer);
  input.disabled = false;
  input.value = state && state.pin || "";
  pinNote(state && state.wrong ? t("pinWrong") : "", state && state.wrong);
  if (state && state.locked) {
    let left = state.locked;
    input.disabled = true;
    const tick = () => {
      if (left <= 0) {
        clearInterval(pinTimer); input.disabled = false;
        pinNote(t("pinRetry"), false); pinChanged(); input.focus(); return;
      }
      pinNote(t("pinLocked", { seconds: left }), true);
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
    try { r = await send(p); } catch (e) { toast(t("unreachable")); return null; }
    if (r.status === 401) { localStorage.removeItem(PIN_KEY); state = { wrong: true }; continue; }
    if (r.status === 429) {
      const j = await r.json().catch(() => ({}));
      state = { locked: Math.max(1, j.retryAfter || 60), pin: p }; continue;
    }
    localStorage.setItem(PIN_KEY, p);
    if (r.status === 403) { toast(t("actionOff")); return null; }
    if (!r.ok) { toast(t("error", { code: r.status })); return null; }
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
  catch (e) { toast(t("photoLoadFailed")); return null; }
}
async function setDownload(ref) {
  const url = await fetchCapture(ref); if (!url) return;
  if (downloadURL && downloadURL !== shotURL) URL.revokeObjectURL(downloadURL);
  downloadURL = url; $("download").href = url; $("download").download = ref.name;
}
$("photo").onclick = async () => {
  closeEditor();
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
  toast(t("photoTaken"), ref.name);
};
$("save").onclick = async () => {
  commitText();
  if (!shapes.length) { toast(t("drawFirst")); return; }
  if ($("save").disabled) return;   // one annotated copy per click, even on a double click
  $("save").disabled = true;
  try {
    const ref = await post("/annotated", { source: frozen.name, shapes });
    if (!ref) return;
    await setDownload(ref);
    toast(t("savedToJob"), ref.name);
  } finally { $("save").disabled = false; }
};
$("back").onclick = () => {
  closeEditor();
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
