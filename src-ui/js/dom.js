/* Taskora — dom & tiện ích thuần (không phụ thuộc state) */
export const invoke = (cmd, args) => window.__TAURI__.core.invoke(cmd, args);
/// View gửi lên backend — backend không biết "stats"/"settings" cho các lệnh act/…
/// → quy về inbox (đếm theo view không ảnh hưởng).
export const viewWire = v => (v && (v.type === "stats" || v.type === "settings")) ? { type: "inbox" } : v;
export const $ = (sel, root) => (root || document).querySelector(sel);
export const $$ = (sel, root) => [...(root || document).querySelectorAll(sel)];
export const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
export const hi = (text, q) => {
  const e = esc(text);
  if (!q) return e;
  const qe = esc(q).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return e.replace(new RegExp("(" + qe + ")", "ig"), "<mark>$1</mark>");
};
export const pick = arr => arr[Math.floor(Math.random() * arr.length)];
export const parseYmd = s => { const [y, m, d] = s.split("-").map(Number); return Date.UTC(y, m - 1, d); };
export const fmtViDate = d => d.toLocaleDateString("vi-VN", { weekday: "short", day: "numeric", month: "numeric", year: "numeric" });
export const fmtViTime = d => d.toLocaleString("vi-VN", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });
export const strip = s => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
export function isTyping() {
  const a = document.activeElement;
  return a && (a.tagName === "INPUT" || a.tagName === "TEXTAREA" || a.tagName === "SELECT" || a.isContentEditable);
}

export function splitISOLocal(iso) { const [y, m, d] = String(iso).slice(0, 10).split("-").map(Number); return { y, m, d }; }
export function makeISOLocal(y, m0, d) { return `${y}-${String(m0 + 1).padStart(2, "0")}-${String(d).padStart(2, "0")}`; }
export function addDaysLocalISO(iso, n) { const { y, m, d } = splitISOLocal(iso); const dt = new Date(y, m - 1, d + n); return makeISOLocal(dt.getFullYear(), dt.getMonth(), dt.getDate()); }
export function lastDayOfMonth(y, m0) { return new Date(y, m0 + 1, 0).getDate(); }
export function localISODate() { const n = new Date(); return makeISOLocal(n.getFullYear(), n.getMonth(), n.getDate()); }
export function viDayMonth(iso) { const { y, m, d } = splitISOLocal(iso); return `${String(d).padStart(2, "0")}/${String(m).padStart(2, "0")}/${y}`; }
export function viDowShort(iso) { const { y, m, d } = splitISOLocal(iso); return ["CN", "T2", "T3", "T4", "T5", "T6", "T7"][new Date(y, m - 1, d).getDay()]; }
export function viFullDayMonth(iso) { const { y, m, d } = splitISOLocal(iso); return `${["Chủ Nhật", "Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy"][new Date(y, m - 1, d).getDay()]}, ${viDayMonth(iso)}`; }

/* ─────────── MODALS ─────────── */
export function openModal(html) {
  const m = $("#modal");
  m.innerHTML = `<div class="modal-backdrop" data-close-modal="1"></div><div class="modal-panel">${html}</div>`;
  // lớp phủ nền mờ phía sau (giữ .overlay flex center)
  m.hidden = false;
}
export function closeModal() { const m = $("#modal"); m.hidden = true; m.innerHTML = ""; }
