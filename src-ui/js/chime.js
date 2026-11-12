/* Taskora — Chime Web Audio (offline). Tách lõi synth khỏi gate âm thanh. */
import { S } from "./state.js";

/* lõi synth — phát 3 nốt theo kiểu âm (soft|wind). Không đọc setting. */
export function synthChime(style) {
  try {
    const Ctx = window.AudioContext || window.webkitAudioContext;
    if (!Ctx) return;
    const ctx = synthChime._ctx || (synthChime._ctx = new Ctx());
    const wind = style === "wind";
    const notes = wind ? [1318.51, 1567.98, 2093.0] : [784, 659.25, 523.25]; // soft: G5 E5 C5 · wind: E6 G6 C7
    const t0 = ctx.currentTime + 0.01;
    notes.forEach((f, idx) => {
      const o = ctx.createOscillator(), g = ctx.createGain();
      o.type = "sine"; o.frequency.value = f;
      const t = t0 + idx * (wind ? 0.38 : 0.32);
      const peak = wind ? 0.15 : 0.22, tail = wind ? 1.5 : 0.55;
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(peak, t + 0.03);
      g.gain.exponentialRampToValueAtTime(0.0001, t + tail);
      o.connect(g).connect(ctx.destination);
      o.start(t); o.stop(t + tail + 0.05);
    });
  } catch { /* môi trường không hỗ trợ âm thanh — im lặng là được */ }
}

/* Chuông cuối phiên — tôn trọng sound_on (công tắc tổng âm phiên) + kiểu chuông đã chọn. */
export function playChime(style, on) {
  if (on === false) return;
  style = style || (S.snap && S.snap.settings && S.snap.settings.chime) || "soft";
  if (style === "none") return;
  if (on === undefined && S.snap && S.snap.settings && S.snap.settings.sound_on === false) return;
  synthChime(style);
}
