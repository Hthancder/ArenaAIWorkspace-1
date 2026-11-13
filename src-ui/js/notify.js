/* Taskora — CỔNG GỬI thông báo sang cửa sổ THÔNG BÁO riêng (notify.html)
   Cửa sổ chính KHÔNG vẽ thẻ nữa — nó chỉ:
     1) kiểm tra cấu hình (master toggle + bật/tắt theo loại) → quyết định có gửi
     2) đăng ký closure cho nút hành động (Hoàn tác…) theo id — closure không đi
        qua được ranh giới cửa sổ, nên cửa sổ Thông báo chỉ gửi ngược id qua
        "notify:action" → main window chạy closure tại đây
   Việc vẽ/tự ẩn/âm thanh/đo chiều cao cửa sổ do js/notify-window.js trong cửa sổ riêng. */
import { invoke } from "./dom.js";
import { S } from "./state.js";
import { synthChime } from "./chime.js";

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

/* Âm thanh theo cấu hình — dùng cho preview trong Cài đặt (cửa sổ chính phát thử) */
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

/** true nếu loại này thực sự phát âm theo cấu hình hiện tại — engine phiên dùng để fallback chuông cũ. */
export function willNotifySoundFor(kind) {
  if (!notifyEnabled() || !notifySoundOn()) return false;
  if (!prefFor(kind).on && !FORCE_ON.has(kind)) return false;
  return !!notifySoundFor(kind);
}

/* ── bus nút hành động: closure ở lại cửa sổ chính, chỉ id đi/về ── */
let actSeq = 0;
const actRegistry = new Map();
const ACT_CAP = 100;
let busBound = false;
function ensureActionBus() {
  if (busBound) return;
  busBound = true;
  try {
    window.__TAURI__?.event?.listen?.("notify:action", e => {
      const id = e && e.payload && e.payload.id;
      const fn = actRegistry.get(id);
      if (fn !== undefined) {
        actRegistry.delete(id);
        if (typeof fn === "function") { try { fn(); } catch (err) { console.error(err); } }
      }
    });
  } catch { /* môi trường không hỗ trợ event */ }
}

/** Bắn một thông báo sang cửa sổ THÔNG BÁO. kind: xem NOTIFY_KINDS (+ "info" | "error").
    sound: "none" = hiện thẻ nhưng không kêu (áp cho MỌI loại). */
export function notify({ kind = "info", title = "", body = "", actions = [], sound } = {}) {
  if (!KIND_SET.has(kind)) kind = "info";
  if (!notifyEnabled()) return;
  const pref = prefFor(kind);
  if (!pref.on && !FORCE_ON.has(kind)) return;
  ensureActionBus();
  const payloadActions = [];
  for (const a of (actions || []).slice(0, 4)) {
    const label = String((a && a.label) ?? "").trim().slice(0, 48);
    if (!label) continue;
    const id = ++actSeq;
    if (actRegistry.size >= ACT_CAP) actRegistry.delete(actRegistry.keys().next().value); /* rơi cái cũ nhất */
    actRegistry.set(id, a.onClick);
    payloadActions.push({ id, label });
  }
  invoke("notify_push", { kind, title: String(title), body: String(body ?? ""), actions: payloadActions, sound: sound === "none" ? "none" : undefined }).catch(() => {});
}

/** Xóa mọi thẻ đang hiện (khi đặt lại cài đặt / chuyển dạng hiển thị lớn). */
export function clearNotifications() {
  actRegistry.clear();
  invoke("notify_clear").catch(() => {});
}
