/**
 * Taskora — jsdom smoke harness (không cần Tauri thật).
 * Chạy:  npm i --no-save jsdom@24 && node scripts/smoke.mjs
 * Kiểm: boot sạch, phiên bản About, nhóm Cài đặt mới (Khay & phím tắt), accordion,
 *       seg đóng cửa sổ, autostart toggle, ask-close modal, capture phím tắt, tray events.
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { JSDOM } from "jsdom";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const SRC = join(ROOT, "src-ui");
const html = readFileSync(join(SRC, "index.html"), "utf8");

const dom = new JSDOM(html, { url: "https://taskora.local/", runScripts: "outside-only", pretendToBeVisual: true });
const { window } = dom;
const g = globalThis;
g.window = window; g.document = window.document;
try { Object.defineProperty(g, "navigator", { value: window.navigator, configurable: true }); } catch {}
for (const k of ["localStorage","CustomEvent","Event","KeyboardEvent","HTMLElement","Node","FileReader","DataTransfer","MutationObserver","DocumentFragment","DOMParser","Image","Blob","URL","FormData"]) g[k] = window[k];
g.requestAnimationFrame = (cb) => setTimeout(cb, 0); g.cancelAnimationFrame = clearTimeout;
g.getComputedStyle = window.getComputedStyle.bind(window);
g.IntersectionObserver = class { observe() {} unobserve() {} disconnect() {} };
g.Audio = class { play() { return Promise.resolve(); } pause() {} set src(v) {} get volume() { return 1; } };

const calls = [];
const settingsState = {
  dark: true, accent: "#6366f1", transparent: true, acrylic_alpha: 110, reduce_motion: false,
  sort: "Manual", hide_completed: false, qa_preview: true, backup_on_exit: false, perf_mode: false,
  adhd_mode: false, sound_on: true, focus_min: 25, break_min: 5, long_break_min: 15, long_break_every: 4,
  auto_start_break: false, auto_start_focus: false, eye_reminder: true, chime: "soft",
  focus_clock_display: "window", focus_auto_open_timer: true,
  notify_enabled: true, notify_autohide: true, notify_hide_secs: 5, notify_sound_on: true,
  notify_prefs: {}, notify_custom_sounds: {},
  close_behavior: "ask", hidden_on_autostart: true, global_hotkey: "Ctrl+Alt+T",
  global_hotkey_enabled: true, close_hint_shown: false, last_view: "inbox",
};
const mkSnap = () => ({
  tasks: [], lists: [], settings: { ...settingsState },
  counts: { inbox: 0, today: 3, upcoming: 0, starred: 0, completed: 0, trash: 0, active: 2, overdue: 1, done_today: 0, focus_today: 0, focus_week: 0, by_list: [] },
  today: "2026-11-09", undo_len: 0, redo_len: 0, flash: null, last_added: null, step_presets: [],
});
const listenMap = new Map();
const mockInvoke = async (cmd, args) => {
  calls.push([cmd, args]);
  switch (cmd) {
    case "snapshot": return mkSnap();
    case "visible_ids": return [];
    case "update_settings": Object.assign(settingsState, args?.patch || {}); return mkSnap();
    case "set_close_behavior": settingsState.close_behavior = args?.behavior; return mkSnap();
    case "global_hotkey_status": return { enabled: settingsState.global_hotkey_enabled, hotkey: settingsState.global_hotkey, active: true };
    case "set_global_hotkey": if (args?.spec === "Ctrl+Alt+X") throw "Tổ hợp bị chiếm"; settingsState.global_hotkey = args?.spec; return { enabled: true, hotkey: args?.spec, active: true };
    case "set_global_hotkey_enabled": settingsState.global_hotkey_enabled = !!args?.enabled; return { enabled: !!args?.enabled, hotkey: settingsState.global_hotkey, active: !!args?.enabled };
    case "autostart_get": return false;
    case "autostart_set": return !!args?.enabled;
    case "close_choice": return null;
    case "fx_status": return "Acrylic (mock)";
    case "transparency_status": return { supported: true, enabled: true };
    case "storage_startup": return { mode: "default", dir: "C:\\Temp", portable: false, exe_dir_writable: true, moved: false, orphan_portable: null, legacy_dir: null, legacy_tasks: 0, legacy_lists: 0 };
    case "storage_info": return { mode: "default", dir: "C:\\Temp", portable: false, exe_dir_writable: true };
    default: return mkSnap();
  }
};
window.__TAURI__ = { core: { invoke: mockInvoke }, event: { listen: mockListen }, dialog: { open: async () => null } };
async function mockListen(event, cb) { listenMap.set(event, cb); return () => {}; }

await import(join(SRC, "js/main.js"));
const t0 = Date.now();
while (Date.now() - t0 < 5000 && !calls.some(([c]) => c === "snapshot")) await new Promise(r => setTimeout(r, 20));
await new Promise(r => setTimeout(r, 150));

const $ = (s) => window.document.querySelector(s);
let pass = 0, fail = 0;
const ok = (name, cond) => { console.log((cond ? "PASS" : "FAIL") + " " + name); cond ? pass++ : fail++; };

ok("không có .fatal overlay", !$(".fatal"));
ok("snapshot đã được gọi", calls.some(([c]) => c === "snapshot"));
ok("brand-ver = v2.12.1", ($(".brand-ver")?.textContent || "") === "v2.12.1");
const trayGroup = document.querySelector("#sg-tray");
ok("nhóm Khay & phím tắt tồn tại", !!trayGroup);
ok("nhóm Khay chứa seg đóng cửa sổ chính", !!trayGroup?.contains(document.querySelector("#set-close-behavior")));
ok("nhóm Khay chứa autostart", !!trayGroup?.contains(document.querySelector("#set-autostart")));
ok("nhóm Khay chứa hotkey", !!trayGroup?.contains(document.querySelector("#set-hotkey-enabled")));
ok("Giao diện không còn lifecycle rows", !document.querySelector("#sg-appearance")?.contains(document.querySelector("#set-autostart")));
ok("badge nhóm Khay = '5 dòng'", (document.querySelector("#sg-tray-head .settings-group-count")?.textContent || "").includes("5"));
const tg = trayGroup.querySelector(".settings-group-head");
tg.click();
ok("click head thu nhóm Khay", trayGroup.classList.contains("is-collapsed") && tg.getAttribute("aria-expanded") === "false");
tg.click();
ok("click head mở lại nhóm Khay", !trayGroup.classList.contains("is-collapsed"));
ok("ADHD nằm trong Tập trung", document.querySelector("#sg-focus")?.contains(document.querySelector("#set-adhd")));
ok("set-sound nằm trong Tập trung", document.querySelector("#sg-focus")?.contains(document.querySelector("#set-sound")));
ok("status hotkey là fx-pill is-ok", ($("#hotkey-status").className || "").includes("fx-pill") && ($("#hotkey-status").className || "").includes("is-ok"));
const askCb = listenMap.get("main:ask-close");
ok("listener main:ask-close đã đăng ký", typeof askCb === "function");
calls.length = 0;
askCb();
await new Promise(r => setTimeout(r, 50));
ok("modal Đóng Taskora? hiện", !$("#modal").hidden && $("#modal").innerHTML.includes("Đóng Taskora?"));
ok("nút Thu vào khay đang focus", window.document.activeElement && window.document.activeElement.dataset.askChoice === "tray");
const rem = $("#ask-remember"); rem.checked = false;
$('[data-ask-choice="tray"]').click();
await new Promise(r => setTimeout(r, 120));
ok("close_choice(tray) được gọi", calls.some(([c, a]) => c === "close_choice" && a.choice === "tray"));
ok("không ghi nhớ → set_close_behavior KHÔNG được gọi", !calls.some(([c]) => c === "set_close_behavior"));

calls.length = 0;
askCb(); await new Promise(r => setTimeout(r, 50));
$("#ask-remember").checked = true;
$('[data-ask-choice="exit"]').click(); await new Promise(r => setTimeout(r, 120));
const iSet = calls.findIndex(([c, a]) => c === "set_close_behavior" && a.behavior === "exit");
const iExit = calls.findIndex(([c, a]) => c === "close_choice" && a.choice === "exit");
ok("ghi nhớ exit → set_close_behavior gọi trước close_choice", iSet !== -1 && iExit !== -1 && iSet < iExit);

const todayCb = listenMap.get("tray:today");
todayCb && todayCb();
await new Promise(r => setTimeout(r, 50));
ok("tray:today không crash", true);

// toggle hotkey TẮT → nút Đổi… không gọi IPC
{
  const hke2 = $("#set-hotkey-enabled");
  hke2.checked = false; hke2.dispatchEvent(new window.Event("change", { bubbles: true }));
  await new Promise(r => setTimeout(r, 80));
  calls.length = 0;
  $("#set-hotkey-change").click();
  await new Promise(r => setTimeout(r, 60));
  window.document.dispatchEvent(new window.KeyboardEvent("keydown", { key: "q", ctrlKey: true, altKey: true, bubbles: true, cancelable: true }));
  await new Promise(r => setTimeout(r, 80));
  ok("hotkey đang tắt → không gọi set_global_hotkey", !calls.some(([c]) => c === "set_global_hotkey"));
  hke2.checked = true; hke2.dispatchEvent(new window.Event("change", { bubbles: true }));
  await new Promise(r => setTimeout(r, 80));
}

calls.length = 0;
$("#set-hotkey-change").click();
await new Promise(r => setTimeout(r, 30));
window.document.dispatchEvent(new window.KeyboardEvent("keydown", { key: "q", ctrlKey: true, altKey: true, bubbles: true, cancelable: true }));
await new Promise(r => setTimeout(r, 120));
ok("capture Ctrl+Alt+Q → set_global_hotkey(Ctrl+Alt+Q)", calls.some(([c, a]) => c === "set_global_hotkey" && a.spec === "Ctrl+Alt+Q"));

calls.length = 0;
$("#set-hotkey-change").click();
await new Promise(r => setTimeout(r, 30));
window.document.dispatchEvent(new window.KeyboardEvent("keydown", { key: "x", ctrlKey: true, altKey: true, bubbles: true, cancelable: true }));
await new Promise(r => setTimeout(r, 120));
ok("tổ hợp bị chiếm → vẫn gọi set_global_hotkey", calls.some(([c, a]) => c === "set_global_hotkey" && a.spec === "Ctrl+Alt+X"));

$("#set-autostart").checked = true;
$("#set-autostart").dispatchEvent(new window.Event("change", { bubbles: true }));
await new Promise(r => setTimeout(r, 80));
ok("autostart_set(true) được gọi", calls.some(([c, a]) => c === "autostart_set" && a.enabled === true));
ok("hàng ẩn autostart hiện sau khi bật", $("#set-hidden-autostart-row").hidden === false);

console.log(`DONE — ${pass} pass, ${fail} fail`);
process.exit(fail ? 1 : 0);
