/* Taskora — Cửa sổ THÔNG BÁO riêng (notify.html)
   TÁCH khỏi cửa sổ app chính: frameless, trong suốt, luôn nổi ở góc dưới-phải,
   kích thước cửa sổ do Rust tự co giãn theo số thẻ (notify_layout) — vùng trong suốt
   không chiếm chuột của desktop.
   Luồng: main window → invoke("notify_push") → Rust emit("notify:arrival") →
   engine vẽ thẻ (≤3 cùng lúc, phần dư xếp hàng) · tự ẩn + thanh tiến trình ·
   hover tạm dừng · phát âm theo cấu hình trong Cài đặt → Thông báo ·
   nút hành động → invoke("notify_action") → main window chạy closure (Hoàn tác…).
   Lỗi dữ liệu (storage_error) luôn hiện và không tự ẩn. */
import { $, esc, invoke } from "./dom.js";
import { applyAccent, covOf } from "./accent.js";
import { synthChime } from "./chime.js";

const MAX_VISIBLE = 3;
const QUEUE_CAP = 10;
const LEAVE_MS = 180;
const HIDE_CHOICES = [3, 5, 8, 10];
const FORCE_ON = new Set(["storage_error"]);
const KIND_SET = new Set(["focus_done", "break_done", "due_today", "overdue", "storage_error", "import_merged", "info", "error"]);
const ICONS = {
  focus_done: "#i-check-circle-fill",
  break_done: "#i-clock",
  due_today: "#i-calendar-check",
  overdue: "#i-warning",
  storage_error: "#i-warning",
  import_merged: "#i-check-circle",
  info: "#i-info",
  error: "#i-warning",
};
const iconFor = kind => ICONS[kind] || ((kind === "error" || kind === "storage_error") ? "#i-warning" : "#i-info");

let prefs = null;          // bản prefs MỚI NHẤT (tải lại ở mỗi thông báo)
const queue = [];
let visible = 0;

/* ── đọc prefs & áp dụng theme/accent cho chính cửa sổ này ── */
async function loadPrefs() {
  try { prefs = await invoke("notify_prefs"); } catch { prefs = null; }
  return prefs;
}
function applyPrefsToDocument(p) {
  if (!p) return;
  const root = document.documentElement;
  root.dataset.theme = p.dark ? "dark" : "light";
  document.body.classList.toggle("perf", !!p.perf_mode);
  document.body.classList.toggle("reduce-motion", !!p.reduce_motion);
  root.style.setProperty("--cov", covOf(p.acrylic_alpha).toFixed(3));
  try { applyAccent(p.accent); } catch { /* accent lỗi → giữ mặc định */ }
}
const prefFor = (p, kind) => {
  const x = (p && p.notify_prefs && p.notify_prefs[kind]) || {};
  return { on: x.on !== false, sound: typeof x.sound === "string" ? x.sound : "default" };
};
const customSoundFor = (p, kind) => (p && p.notify_custom_sounds && p.notify_custom_sounds[kind]) || null;
const hideSecs = p => {
  const v = Number(p && p.notify_hide_secs);
  return HIDE_CHOICES.includes(v) ? v : 5;
};
function shouldShow(p, kind) {
  if (!p) return true; // không đọc được prefs → hiện thẻ, còn hơn nuốt câm
  if (p.notify_enabled === false) return false;
  const { on } = prefFor(p, kind);
  return on || FORCE_ON.has(kind);
}
function soundFor(p, kind) {
  const { sound } = prefFor(p, kind);
  if (sound === "none") return null;
  if (sound === "soft" || sound === "wind") return { builtIn: sound };
  if (sound === "custom") {
    const uri = customSoundFor(p, kind);
    return uri ? { custom: uri } : { builtIn: "soft" };
  }
  if (kind === "focus_done") {
    const s = (p && p.chime) || "soft";
    if (s === "none") return null;
    return { builtIn: s === "wind" ? "wind" : "soft" };
  }
  return { builtIn: "soft" };
}
function playSound(p, kind, silent) {
  if (silent) return;                 /* caller yêu cầu yên (sound:"none") */
  if (!p || p.notify_sound_on === false) return;
  const snd = soundFor(p, kind);
  if (!snd) return;
  if (snd.builtIn) { synthChime(snd.builtIn); return; }
  try { const a = new Audio(snd.custom); a.volume = 0.9; const pr = a.play && a.play(); if (pr && pr.catch) pr.catch(() => {}); } catch { /* bỏ qua */ }
}

/* ── đo chồng thẻ → báo Rust co/phóng/ẩn cửa sổ ── */
function syncLayout() {
  requestAnimationFrame(() => {
    const cards = [...document.querySelectorAll(".notify-card")];
    let h = 20; // đệm 10px trên + dưới
    if (cards.length) {
      let sum = 0;
      for (const c of cards) sum += c.getBoundingClientRect().height + 10;
      h = sum - 10 + 20;
    }
    invoke("notify_layout", { height: Math.round(h) }).catch(() => {});
  });
}

/* ── chồng thẻ & tự ẩn ── */
function dismiss(card, done) {
  if (!card || card.dataset.leaving === "1") { done && done(); return; }
  card.dataset.leaving = "1";
  card.classList.remove("notify-in", "notify-hover");
  card.classList.add("notify-out");
  setTimeout(() => { card.remove(); done && done(); syncLayout(); }, LEAVE_MS);
}

function spawnCard(item) {
  const stack = $("#notify-stack");
  if (!stack) return;
  const p = prefs;
  const card = document.createElement("div");
  card.className = `notify-card notify-${item.kind}`;
  card.setAttribute("role", (item.kind === "error" || item.kind === "storage_error") ? "alert" : "status");
  const noAutoHide = item.kind === "storage_error" || !(p && p.notify_autohide);
  const dur = noAutoHide ? Infinity : hideSecs(p) * 1000;
  const bodyHtml = item.body ? `<div class="notify-text">${esc(item.body)}</div>` : "";
  const actionsHtml = (item.actions || []).map((a, i) => `<button type="button" class="notify-action" data-i="${i}">${esc(a.label)}</button>`).join("");
  card.innerHTML = `
    <div class="notify-ic"><svg class="ic"><use href="${iconFor(item.kind)}"/></svg></div>
    <div class="notify-body">
      <div class="notify-title">${esc(item.title)}</div>
      ${bodyHtml}
      ${actionsHtml ? `<div class="notify-actions">${actionsHtml}</div>` : ""}
    </div>
    <button class="notify-x" type="button" aria-label="Đóng thông báo"><svg class="ic small"><use href="#i-x"/></svg></button>
    ${noAutoHide ? "" : `<div class="notify-progress" aria-hidden="true"><i></i></div>`}`;
  stack.prepend(card);

  let remaining = dur, last = null, raf = null, hidden = false;
  const bar = card.querySelector(".notify-progress > i");
  /* trừ chỗ ngay khi BẮT ĐẦU đóng (không chờ animation) — clearAll xoá thẻ giữa chừng
     sẽ không làm lệch bộ đếm, thẻ mới spawn đúng giới hạn 3 */
  const close = () => {
    if (card.dataset.closed === "1") return;
    card.dataset.closed = "1";
    visible = Math.max(0, visible - 1);
    dismiss(card, () => pumpQueue());
  };
  card.querySelector(".notify-x").addEventListener("click", close);
  (item.actions || []).forEach((a, i) => {
    card.querySelector(`.notify-action[data-i="${i}"]`)?.addEventListener("click", () => {
      invoke("notify_action", { id: a.id }).catch(() => {});
      close();
    });
  });

  const tick = ts => {
    if (hidden) return;
    if (last == null) last = ts;
    const delta = ts - last; last = ts;
    if (Number.isFinite(remaining)) {
      remaining -= delta;
      if (bar) bar.style.transform = `scaleX(${Math.max(0, remaining / dur)})`;
      if (remaining <= 0) { close(); return; }
    }
    raf = requestAnimationFrame(tick);
  };
  card.addEventListener("mouseenter", () => { hidden = true; cancelAnimationFrame(raf); card.classList.add("notify-hover"); });
  card.addEventListener("mouseleave", () => { if (hidden) { hidden = false; last = null; raf = requestAnimationFrame(tick); } card.classList.remove("notify-hover"); });
  if (Number.isFinite(dur)) raf = requestAnimationFrame(tick); else if (bar) bar.style.transform = "scaleX(1)";

  requestAnimationFrame(() => card.classList.add("notify-in"));
  playSound(p, item.kind, item.silent);
  visible += 1;
  syncLayout();
}

function pumpQueue() {
  while (visible < MAX_VISIBLE && queue.length) spawnCard(queue.shift());
}

/** Nhận một thông báo (từ event notify:arrival) — đọc prefs tươi rồi quyết định hiện/ẩn. */
async function handleArrival(payload) {
  if (!payload) return;
  const p = await loadPrefs();
  applyPrefsToDocument(p);
  const kind = KIND_SET.has(payload.kind) ? payload.kind : "info";
  if (!shouldShow(p, kind)) return;
  const item = {
    kind,
    title: String(payload.title ?? ""),
    body: String(payload.body ?? ""),
    silent: !!payload.silent,
    actions: Array.isArray(payload.actions)
      ? payload.actions.slice(0, 4).map(a => ({ id: Number(a.id) || 0, label: String(a.label ?? "") }))
      : [],
  };
  if (visible >= MAX_VISIBLE) { if (queue.length < QUEUE_CAP) queue.push(item); return; }
  spawnCard(item);
}

/** Xóa toàn bộ thẻ + hàng đợi (nút "Đặt lại cài đặt" gọi qua notify_clear). */
function clearAll() {
  const stack = $("#notify-stack");
  if (stack) stack.innerHTML = "";
  queue.length = 0;
  visible = 0;
  syncLayout();
}

/* ── INIT: gắn listener TRƯỚC, rồi báo READY để Rust xả pending ── */
async function init() {
  applyPrefsToDocument(await loadPrefs());
  const listen = window.__TAURI__?.event?.listen;
  try { await listen?.("notify:arrival", e => { handleArrival(e && e.payload); }); } catch { /* môi trường không hỗ trợ event */ }
  try { await listen?.("notify:clear", () => clearAll()); } catch { /* bỏ qua */ }
  try { await invoke("notify_ready"); } catch { /* bỏ qua */ }
  syncLayout(); // chưa có thẻ → báo Rust ẩn cửa sổ
}
if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", () => { init(); });
else init();

export { handleArrival, clearAll };
