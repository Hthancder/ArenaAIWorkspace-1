/* Taskora — Accent color engine: dùng chung cho cửa sổ chính & cửa sổ Thông báo.
   Chỉ đọc/ghi biến trên document.documentElement nên an toàn ở mọi cửa sổ webview. */
export const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
export const covOf = a => clamp((Number(a ?? 110) - 40) / 130, 0, 1); // 0 = trong suốt nhất, 1 = phủ kín nhất
export const hexToRgb = hex => { const n = parseInt(String(hex).replace("#", ""), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; };
export function rgbToHsl(r, g, b) {
  r /= 255; g /= 255; b /= 255;
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn, l = (mx + mn) / 2;
  let h = 0, s = 0;
  if (d) {
    s = d / (1 - Math.abs(2 * l - 1));
    if (mx === r) h = ((g - b) / d) % 6; else if (mx === g) h = (b - r) / d + 2; else h = (r - g) / d + 4;
    h *= 60; if (h < 0) h += 360;
  }
  return [h, s * 100, l * 100];
}
export function hslToHex(h, s, l) {
  s /= 100; l /= 100;
  const c = (1 - Math.abs(2 * l - 1)) * s, x = c * (1 - Math.abs(((h / 60) % 2) - 1)), m = l - c / 2;
  let r, g, b;
  if (h < 60) { r = c; g = x; b = 0; } else if (h < 120) { r = x; g = c; b = 0; } else if (h < 180) { r = 0; g = c; b = x; }
  else if (h < 240) { r = 0; g = x; b = c; } else if (h < 300) { r = x; g = 0; b = c; } else { r = c; g = 0; b = x; }
  const to = v => Math.round((v + m) * 255).toString(16).padStart(2, "0");
  return "#" + to(r) + to(g) + to(b);
}
export function applyAccent(hex) {
  const m = /^#?([0-9a-fA-F]{6})$/.exec(String(hex || "").trim());
  if (!m) return;
  const v = "#" + m[1].toLowerCase();
  const [r, g, b] = hexToRgb(v);
  const [h, s, l] = rgbToHsl(r, g, b);
  const dark = document.documentElement.dataset.theme !== "light";
  const accent2 = hslToHex(h, clamp(s + 4, 8, 100), clamp(l + 12, 12, 88));
  const accentDeep = hslToHex(h, clamp(s + 10, 8, 100), clamp(l - 12, 6, 80));
  const ink = dark ? hslToHex(h, clamp(s, 10, 100), clamp(l + 40, 30, 90)) : hslToHex(h, clamp(s, 10, 100), clamp(l - 30, 10, 45));
  const [r2, g2, b2] = hexToRgb(accent2);
  const el = document.documentElement;
  el.style.setProperty("--accent", v);
  el.style.setProperty("--accent-2", accent2);
  el.style.setProperty("--accent-deep", accentDeep);
  el.style.setProperty("--accent-rgb", `${r},${g},${b}`);
  el.style.setProperty("--accent-2-rgb", `${r2},${g2},${b2}`);
  el.style.setProperty("--accent-ink", ink);
  el.style.setProperty("--bg-h", String(Math.round(h)));
  el.style.setProperty("--bg-s", clamp(s, 35, 78).toFixed(1) + "%");
  el.style.setProperty("--bg-ds", clamp(s * 0.55, 22, 48).toFixed(1) + "%");
}
