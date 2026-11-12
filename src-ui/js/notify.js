/* Taskora — Hệ thống thông báo đẩy (thay hoàn toàn toast).
   - Đúng giao diện app (dùng biến CSS var — theme/accent/acrylic/perf/reduce-motion)
   - Auto-hide có progress bar + fade-out; hover tạm dừng; ✕ luôn đóng được
   - Tối đa 3 thẻ hiện cùng lúc; phần dư xếp hàng (≤10)
   - Âm thanh: mặc định theo loại · 3 nốt / Chuông gió / Không / Tùy chỉnh (base64 data URI)
   Engine đọc thẳng S.snap.settings mỗi lần bắn → không cần đồng bộ tay. */
import { $, $$, esc, hi, invoke } from "./dom.js";
import { S } from "./state.js";
import { synthChime } from "./chime.js";

const MAX_VISIBLE = 3;
const QUEUE_CAP = 10;
const LEAVE_MS = 180;

/* Registry các loại thông báo — dùng chung cho engine và UI cài đặt */
export const NOTIFY_KINDS = [
  { key: "focus_done",    label: "Phiên tập trung hoàn thành", desc: "Khi đồng hồ phiên về 0 (kèm nút “Nghỉ …” / “Dừng”)", icon: "#i-check-circle-fill" },
  { key: "break_done",    label: "Hết giờ nghỉ",               desc: "Khi phiên nghỉ kết thúc (kèm nút “Tập trung tiếp”)", icon: "#i-clock" },
  { key: "due_today",     label: "Tóm tắt việc đến hạn",       desc: "Mỗi ngày khi mở app mà hôm nay có việc đến hạn",   icon: "#i-calendar-check" },
  { key: "overdue",       label: "Việc quá hạn",               desc: "Khi mở app phát hiện có việc quá hạn",             icon: "#i-warning" },
  { key: "storage_error", label: "Lỗi dữ liệu",                desc: "Nhập/khôi phục/gộp dữ liệu thất bại — không tự ẩn", icon: "#i-warning" },
  { key: "import_merged", label: "Gộp dữ liệu xong",           desc: "Khi gộp dữ liệu portable hoàn tất",                icon: "#i-check-circle" },
];
const KIND_SET = new Set([...NOTIFY_KINDS.map(k => k.key), "info", "error"]);
const FORCE_ON = new Set(["storage_error"]); /* lỗi dữ liệu không cho tắt */
const HIDE_CHOICES = [3, 5, 8, 10];

function settings() { return (S.snap && S.snap.settings) || {}; }
export function notifyEnabled() { return settings().notify_enabled !== false; }
export function notifyAutohide() { return settings().notify_autohide !== false; }
export function notifyHideSecs() {
  const v = Number(settings().notify_hide_secs);
  return HIDE_CHOICES.includes(v) ? v : 5;
}
export function notifySoundOn() { return settings().notify_sound_on !== false; }
export function prefFor(kind) {
  const p = (settings().notify_prefs || {})[kind] || {};
  return { on: p.on !== false, sound: typeof p.sound === "string" ? p.sound : "default" };
}
export function customSoundFor(kind) { return (settings().notify_custom_sounds || {})[kind] || null; }

/* ── âm thanh ── */
export function notifySoundFor(kind) {
  const { sound } = prefFor(kind);
  if (sound === "none") return null;
  if (sound === "soft" || sound === "wind") return { builtIn: sound };
  if (sound === "custom") {
    const uri = customSoundFor(kind);
    return uri ? { custom: uri } : { builtIn: "soft" };
  }
  /* "default" — focus_done kêu theo chuông phiên, còn lại theo 3 nốt */
  if (kind === "focus_done") {
    const s = settings().chime;
    return (s === "none" || s === "wind") ? (s === "wind" ? { builtIn: "wind" } : null) : { builtIn: "soft" };
  }
  return { builtIn: "soft" };
}
function playNotifySound(kind) {
  if (!notifySoundOn()) return;
  const snd = notifySoundFor(kind);
  if (!snd) return;
  if (snd.builtIn) { synthChime(snd.builtIn); return; }
  try { const a = new Audio(snd.custom); a.volume = 0.9; const pr = a.play && a.play(); if (pr && pr.catch) pr.catch(() => {}); } catch { /* bỏ qua */ }
}
export function previewNotifySound(kind, soundOverride) {
  const snd = soundOverride !== undefined
    ? (soundOverride === "none" ? null
      : soundOverride === "custom" ? (customSoundFor(kind) ? { custom: customSoundFor(kind) } : { builtIn: "soft" })
      : soundOverride === "default"
        ? (kind === "focus_done" ? { builtIn: settings().chime === "none" ? null : (settings().chime || "soft") } : { builtIn: "soft" })
        : { builtIn: soundOverride })
    : notifySoundFor(kind);
  if (!snd) return;
  if (snd.builtIn) { synthChime(snd.builtIn); return; }
  try { const a = new Audio(snd.custom); a.volume = 0.9; const pr = a.play && a.play(); if (pr && pr.catch) pr.catch(() => {}); } catch { /* bỏ qua */ }
}

/* ── trình chiếu ── */
let seq = 0;
const queue = [];
let visible = 0;

function ensureStack() {
  let stack = document.getElementById("notify-stack");
  if (!stack) {
    stack = document.createElement("div");
    stack.id = "notify-stack";
    stack.setAttribute("aria-live", "polite");
    document.body.appendChild(stack);
  }
  return stack;
}

const ICON_FALLBACK = "#i-info";
function iconFor(kind) {
  const k = NOTIFY_KINDS.find(k => k.key === kind);
  return (k && k.icon) || (kind === "error" || kind === "storage_error" ? "#i-warning" : ICON_FALLBACK);
}

function spawnCard(item) {
  const stack = ensureStack();
  const card = document.createElement("div");
  card.className = `notify-card notify-${item.kind}`;
  card.setAttribute("role", item.kind === "error" || item.kind === "storage_error" ? "alert" : "status");
  const noAutoHide = item.kind === "storage_error" || !notifyAutohide();
  const dur = noAutoHide ? Infinity : notifyHideSecs() * 1000;
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
  const close = () => dismiss(card, () => { visible -= 1; pumpQueue(); });
  card.querySelector(".notify-x").addEventListener("click", close);
  (item.actions || []).forEach((a, i) => {
    card.querySelector(`.notify-action[data-i="${i}"]`)?.addEventListener("click", () => { try { a.onClick && a.onClick(); } catch (e) { console.error(e); } close(); });
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
  playNotifySound(item.kind);
  visible += 1;
}

function dismiss(card, done) {
  if (!card || card.dataset.leaving === "1") { done && done(); return; }
  card.dataset.leaving = "1";
  card.classList.remove("notify-in", "notify-hover");
  card.classList.add("notify-out");
  setTimeout(() => { card.remove(); done && done(); }, LEAVE_MS);
}

function pumpQueue() {
  while (visible < MAX_VISIBLE && queue.length) {
    const item = queue.shift();
    spawnCard(item);
  }
}

/** Bắn một thông báo. kind: xem NOTIFY_KINDS (+ "info" | "error"). */
export function notify({ kind = "info", title = "", body = "", actions = [], sound } = {}) {
  if (!KIND_SET.has(kind)) kind = "info";
  if (!notifyEnabled()) return;
  const pref = prefFor(kind);
  if (!pref.on && !FORCE_ON.has(kind)) return;
  const item = { id: ++seq, kind, title: String(title), body: String(body ?? ""), actions, sound };
  if (visible >= MAX_VISIBLE) {
    if (queue.length < QUEUE_CAP) queue.push(item);
    return;
  }
  spawnCard(item);
}

/** Dọn mọi thẻ (khi đặt lại cài đặt / chuyển dạng hiển thị lớn). */
export function clearNotifications() {
  const stack = document.getElementById("notify-stack");
  if (stack) stack.innerHTML = "";
  queue.length = 0; visible = 0;
}

/** true nếu loại này thực sự phát âm theo cấu hình hiện tại — engine phiên dùng để fallback chuông cũ. */
export function willNotifySoundFor(kind) {
  if (!notifyEnabled() || !notifySoundOn()) return false;
  if (!prefFor(kind).on && !FORCE_ON.has(kind)) return false;
  return !!notifySoundFor(kind);
}
