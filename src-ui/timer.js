/* Taskora — Cửa sổ Đồng hồ: mirror từ Rust focus engine (wall-clock, event focus:change) */
const T_CIRC = 2 * Math.PI * 52;
const invoke = (cmd, args) => window.__TAURI__.core.invoke(cmd, args);
const $ = (s) => document.querySelector(s);

let T = null; // payload hiện tại

function remainingNow() {
  if (!T) return 0;
  if (T.endsAtMs == null) return T.remainingSecs || 0;
  return Math.max(0, Math.ceil((T.endsAtMs - Date.now()) / 1000));
}

function fmt(secs) {
  const m = Math.floor(secs / 60), r = secs % 60;
  return `${String(m).padStart(2, "0")}:${String(r).padStart(2, "0")}`;
}

function applyPayload(p) {
  if (!p) return;
  T = p;
  render();
}

function render() {
  const main = $("#t-main"), empty = $("#t-empty"), done = $("#t-done");
  const isBreak = T && T.mode !== "focus";
  const showDone = T && T.active && T.phaseDone && !isBreak;
  const showMain = T && T.active && !showDone && !(T.phaseDone && isBreak);

  empty.hidden = !!(T && T.active);
  done.hidden = !showDone;
  main.hidden = !(showMain || (T && T.active && T.phaseDone && isBreak));

  if (!T || !T.active) return;

  /* mode label */
  const modeEl = $("#t-mode");
  modeEl.textContent = isBreak
    ? (T.mode === "break_long" ? "Nghỉ dài" : "Nghỉ ngắn")
    : "Tập trung";

  if (showMain || (T.phaseDone && isBreak)) {
    /* ring */
    const rem = remainingNow();
    const total = T.totalSecs || 1;
    const prog = $("#t-prog");
    prog.style.strokeDasharray = String(T_CIRC);
    prog.style.strokeDashoffset = String(T_CIRC * (1 - Math.max(0, Math.min(1, rem / total))));
    $("#t-time").textContent = fmt(rem);
    $("#t-title").textContent = isBreak ? "Đứng dậy, uống nước, nhìn xa" : (T.taskTitle || "Phiên tập trung");
    const pauseBtn = $("#t-pause"), stopBtn = $("#t-stop");
    pauseBtn.hidden = isBreak;
    pauseBtn.textContent = T.paused ? "Tiếp tục" : "Tạm dừng";
    stopBtn.textContent = isBreak ? "Bỏ qua nghỉ →" : "Dừng";
    $("#t-reset").hidden = false;
  }

  if (showDone) {
    const sub = $("#t-done-sub");
    if (T.nextBreakLong) {
      sub.textContent = "Đã đến lúc nghỉ dài — bạn xứng đáng";
      $("#t-done-break").textContent = `Nghỉ dài ${T.longBreakMin ?? 15}:00`;
    } else {
      sub.textContent = `Nghỉ ${T.breakMin ?? 5} phút — đứng dậy, uống nước, nhìn ra xa`;
      $("#t-done-break").textContent = `Nghỉ ${T.breakMin ?? 5}:00`;
    }
  }
}

/* tick hiển thị — thời gian vẫn lấy từ endsAtMs (wall-clock) */
setInterval(() => {
  if (T && T.active && !T.phaseDone) renderRingOnly();
}, 500);
function renderRingOnly() {
  const isBreak = T.mode !== "focus";
  const rem = remainingNow();
  const total = T.totalSecs || 1;
  const prog = $("#t-prog");
  if (!$("#t-main").hidden) {
    prog.style.strokeDashoffset = String(T_CIRC * (1 - Math.max(0, Math.min(1, rem / total))));
    $("#t-time").textContent = fmt(rem);
  }
}

/* chime khi chính cửa sổ này gây chuyển phase (chống chuông đúp) */
function playChime(style, on) {
  if (on === false || style === "none") return;
  try {
    const Ctx = window.AudioContext || window.webkitAudioContext;
    if (!Ctx) return;
    const ctx = playChime._ctx || (playChime._ctx = new Ctx());
    const wind = style === "wind";
    const notes = wind ? [1318.51, 1567.98, 2093.0] : [784, 659.25, 523.25];
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
  } catch { /* im lặng */ }
}

function wasZero() {
  return T && T.active && !T.phaseDone && T.endsAtMs != null && remainingNow() <= 0;
}

async function completeTick() {
  if (!wasZero()) return;
  try {
    const p = await invoke("focus_complete");
    if (p && p.transitioned) playChime(p.chime, p.soundOn !== false);
    applyPayload(p);
  } catch { /* bỏ qua */ }
}
setInterval(completeTick, 500);

/* sự kiện từ engine (cửa sổ chính cũng nghe như vậy) */
try {
  window.__TAURI__?.event?.listen?.("focus:change", (e) => applyPayload(e.payload));
} catch { /* bỏ qua */ }

/* nút bấm */
$("#t-pause").addEventListener("click", async () => { try { applyPayload(await invoke("focus_pause_toggle")); } catch {} });
$("#t-reset").addEventListener("click", async () => { try { applyPayload(await invoke("focus_reset")); } catch {} });
$("#t-stop").addEventListener("click", async () => { try { await invoke("focus_stop"); } catch {} });
$("#t-done-stop").addEventListener("click", async () => { try { await invoke("focus_stop"); } catch {} });
$("#t-done-break").addEventListener("click", async () => { try { applyPayload(await invoke("focus_break_start")); } catch {} });
$("#t-close").addEventListener("click", async () => { try { await invoke("focus_timer_close"); } catch {} });
$("#t-open-main").addEventListener("click", async () => { try { await invoke("focus_open_main"); } catch {} });
$("#t-pin").addEventListener("click", async () => {
  try {
    const pinned = await invoke("focus_timer_pin");
    $("#t-pin").setAttribute("aria-pressed", String(!!pinned));
  } catch {}
});

/* Escape — đóng cửa sổ Đồng hồ (phiên vẫn chạy) */
window.addEventListener("keydown", (e) => {
  if (e.key === "Escape") { e.preventDefault(); invoke("focus_timer_close").catch(() => {}); }
});

/* khởi động: theme + state hiện tại */
(async () => {
  try {
    const snap = await invoke("snapshot");
    const dark = snap?.settings?.dark !== false;
    document.documentElement.dataset.theme = dark ? "dark" : "light";
  } catch { /* mặc định dark */ }
  try { applyPayload(await invoke("focus_state")); } catch { T = null; render(); }
})();
