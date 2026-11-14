/* Taskora — phím tắt toàn cục: logic thuần (không DOM).
   Định dạng chuẩn: "Ctrl+Alt+T" — token nối bằng `+`, thứ tự Ctrl → Alt → Shift → Win → KEY.
   Phím chính: A–Z | 0–9 | F1–F12. Cần ≥ 1 modifier. */

const MODS = { control: "Ctrl", ctrl: "Ctrl", alt: "Alt", shift: "Shift", meta: "Win", super: "Win", win: "Win", cmd: "Win", command: "Win" };
const MOD_ORDER = ["Ctrl", "Alt", "Shift", "Win"];

function normalizeKey(u) {
  if (u.length === 1 && /^[A-Z0-9]$/.test(u)) return u;
  const m = /^F([1-9]|1[0-2])$/.exec(u);
  if (m) return "F" + Number(m[1]);
  return null;
}

/** Chuẩn hoá chuỗi thô → "Ctrl+Alt+T"; trả null nếu không hợp lệ. */
export function normalizeSpec(raw) {
  if (!raw) return null;
  const mods = [];
  let key = null;
  for (const part of String(raw).split("+")) {
    const t = part.trim();
    if (!t) continue;
    const u = t.toUpperCase();
    const mod = MODS[u.toLowerCase()];
    if (mod) { if (!mods.includes(mod)) mods.push(mod); continue; }
    const k = normalizeKey(u);
    if (!k) return null;
    if (key) return null; // hai phím chính
    key = k;
  }
  if (!mods.length || !key) return null;
  mods.sort((a, b) => MOD_ORDER.indexOf(a) - MOD_ORDER.indexOf(b));
  return [...mods, key].join("+");
}

export function validateSpec(spec) {
  return normalizeSpec(spec) !== null;
}

/** Dựng tổ hợp từ một KeyboardEvent (hoặc object giống {ctrlKey, altKey, shiftKey, metaKey, key}).
   Trả null nếu chỉ có modifier (chưa có phím chính). */
export function comboFromEvent(e) {
  const mods = [];
  if (e.ctrlKey) mods.push("Ctrl");
  if (e.altKey) mods.push("Alt");
  if (e.shiftKey) mods.push("Shift");
  if (e.metaKey) mods.push("Win");
  let key = null;
  const k = e.key;
  if (typeof k === "string") {
    if (/^F([1-9]|1[0-2])$/i.test(k)) key = k.toUpperCase();
    else if (k.length === 1 && /^[a-z0-9]$/i.test(k)) key = k.toUpperCase();
  }
  if (!key) return null; // modifier-only hoặc phím ngoài A–Z/0–9/F1–F12
  if (!mods.length) return { error: "modifier", spec: null }; // có phím chính nhưng thiếu modifier
  return { error: null, spec: [...mods, key].join("+") };
}
