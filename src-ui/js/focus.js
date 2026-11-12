/* Taskora — Đồng hồ phiên: engine UI, ring, chip, breathing, 20-20-20 */
import { $, hi, invoke } from "./dom.js";
import { CIRC, F, S, clockDisplay, s_isAdhd, taskById } from "./state.js";
import { playChime } from "./chime.js";
import { notify, willNotifySoundFor } from "./notify.js";
import { confettiBurst } from "./fx.js";
import { postSnap, refresh } from "./snapshot.js";


export function applyFocusPayload(p) {
  if (!p) return;
  F.active = !!p.active;
  F.mode = p.mode || "focus";
  F.taskId = p.taskId ?? null;
  F.taskTitle = p.taskTitle || "";
  F.totalSecs = p.totalSecs || 1500;
  F.endsAtMs = p.endsAtMs ?? null;
  F.remainingSecs = p.remainingSecs ?? F.totalSecs;
  F.paused = !!p.paused;
  F.phaseDone = !!p.phaseDone;
  F.cycleCount = p.cycleCount || 0;
  F.nextBreakLong = !!p.nextBreakLong;
  F.soundOn = p.soundOn !== false;
  F.chime = p.chime || "soft";
  renderFocus();
}

export function focusRemainingNow() {
  if (F.endsAtMs == null) return F.remainingSecs;
  return Math.max(0, Math.ceil((F.endsAtMs - Date.now()) / 1000));
}

export function drawFocusRing(rem) {
  rem = rem ?? focusRemainingNow();
  const p = $("#focus-prog");
  const total = F.totalSecs || 1;
  if (p) {
    p.style.strokeDasharray = String(CIRC);
    p.style.strokeDashoffset = String(CIRC * (1 - Math.max(0, Math.min(1, rem / total))));
  }
  const m = Math.floor(rem / 60), r = rem % 60;
  const t = $("#focus-time"); if (t) t.textContent = `${String(m).padStart(2, "0")}:${String(r).padStart(2, "0")}`;
  const nowEl = $("#focus-now");
  if (nowEl) nowEl.textContent = `Bây giờ là ${new Date().toLocaleTimeString("vi-VN", { hour: "2-digit", minute: "2-digit" })}`;
}

export const focusEyeHide = () => { const e = $("#eye-pill"); if (e) e.hidden = true; clearInterval(eyeTimer); };

export function renderFocus() {
  const s = S.snap && S.snap.settings ? S.snap.settings : {};
  const focusMin = s.focus_min ?? 25, breakMin = s.break_min ?? 5, longBreakMin = s.long_break_min ?? 15;
  const every = s.long_break_every ?? 4;
  const isBreak = F.mode !== "focus";
  const rem = focusRemainingNow();
  drawFocusRing(rem);
  /* vòng ring ↔ vòng thở */
  const ringWrap = document.querySelector(".focus-ring-wrap");
  const breath = $("#focus-breath");
  if (isBreak) {
    if (ringWrap) ringWrap.style.display = "none";
    if (breath) breath.hidden = false;
    startBreath();
  } else {
    if (ringWrap) ringWrap.style.display = "";
    if (breath) breath.hidden = true;
    stopBreath();
  }
  const hint = $("#focus-hint"), title = $("#focus-title");
  const pauseBtn = $("#focus-pause"), stopBtn = $("#focus-stop"), resetBtn = $("#focus-reset");
  const controls = $("#focus-controls"), done = $("#focus-done");
  const doneSub = $("#focus-done-sub"), breakBtn = $("#focus-break");
  if (isBreak) {
    if (hint) hint.textContent = "Nghỉ thật — đứng dậy, uống nước, nhìn xa";
    if (title) title.textContent = F.mode === "break_long" ? `Nghỉ dài ${longBreakMin} phút` : `Nghỉ ngắn ${breakMin} phút`;
    if (controls) controls.hidden = false;
    if (done) done.hidden = true;
    if (pauseBtn) pauseBtn.hidden = true;
    if (stopBtn) stopBtn.textContent = "Bỏ qua nghỉ →";
    if (resetBtn) resetBtn.hidden = false;
  } else if (F.phaseDone) {
    if (hint) hint.textContent = `${focusMin} phút tập trung — não bạn xứng đáng được nghỉ`;
    if (title) title.textContent = F.taskTitle;
    if (controls) controls.hidden = true;
    if (done) done.hidden = false;
    if (breakBtn) {
      const long = F.nextBreakLong;
      breakBtn.textContent = long ? `Nghỉ dài ${longBreakMin}:00` : `Nghỉ ${breakMin}:00`;
      breakBtn.classList.toggle("btn-save", long);
      breakBtn.classList.toggle("btn-ghost", !long);
    }
    if (doneSub) doneSub.textContent = F.nextBreakLong
      ? `Xong ${every} phiên rồi — nghỉ dài xứng đáng`
      : `Nghỉ ${breakMin} phút — đứng dậy, uống nước, nhìn ra xa`;
  } else {
    if (hint) hint.textContent = "Đúng việc này thôi — mọi thứ khác có thể đợi";
    if (title) title.textContent = F.taskTitle;
    if (controls) controls.hidden = false;
    if (done) done.hidden = true;
    if (pauseBtn) { pauseBtn.hidden = false; pauseBtn.textContent = F.paused ? "Tiếp tục" : "Tạm dừng"; }
    if (stopBtn) stopBtn.textContent = "Dừng lại — không sao";
    if (resetBtn) resetBtn.hidden = false;
  }
  /* overlay đóng/mở theo engine + loại hiển thị đã chọn (window: không bao giờ un-hide) */
  const cd = clockDisplay();
  const ov = $("#focus-overlay");
  const show = (F.active || F.phaseDone) && cd !== "window";
  if (ov) {
    if (show && ov.hidden) ov.hidden = false;
    else if (!show && !ov.hidden) ov.hidden = true;
  }
  renderFocusChip();
  /* nghỉ xong → toast + dừng engine (overlay đóng ở cả hai cửa sổ qua event) */
  const breakDone = F.phaseDone && F.mode !== "focus";
  if (breakDone && !F.breakDoneFlag) {
    F.breakDoneFlag = true;
    notify({ kind: "break_done", title: "Hết giờ nghỉ ✦", body: "Việc tiếp theo nhé", actions: [{ label: "Tập trung tiếp", onClick: () => { const tid = F.taskId; focusStop(true); if (tid != null && taskById(tid)) focusStart(tid); } }] });
    focusStop(true);
  } else if (!breakDone) {
    F.breakDoneFlag = false;
  }
}

export function focusTickStart() {
  clearInterval(F.timer);
  F.timer = setInterval(() => {
    if (!F.active) return;
    const rem = focusRemainingNow();
    const ov = $("#focus-overlay");
    if (ov && !ov.hidden) drawFocusRing(rem);
    renderFocusChip();
    const s = S.snap && S.snap.settings ? S.snap.settings : {};
    if (F.mode === "focus" && !F.eyeShown && !F.paused && s.eye_reminder !== false && (F.totalSecs - rem) >= 1200) showEyePill();
    if (rem <= 0 && !F.phaseDone && F.endsAtMs != null && !F.completing) {
      F.completing = true;
      invoke("focus_complete")
        .then(p => {
          if (p && p.transitioned) {
            if (p.completedFocus) {
              const willSnd = willNotifySoundFor("focus_done");
              const breakLabel = `Nghỉ ${p.breakMin ?? 5}:00`;
              notify({ kind: "focus_done", title: "Phiên tập trung hoàn thành", body: "Đứng dậy, uống nước, nhìn ra xa ~6m", actions: [{ label: breakLabel, onClick: () => focusBreakStart() }, { label: "Dừng", onClick: () => focusStop(true) }] });
              if (!willSnd && p.soundOn !== false) playChime(p.chime, true);
              refresh();
              if (s_isAdhd()) confettiBurst(window.innerWidth / 2, Math.max(120, window.innerHeight / 2 - 80));
            } else if (p.soundOn !== false) {
              playChime(p.chime, true);
            }
          }
          focusSync(); /* đọc lại trạng thái thật mới nhất — tránh payload cũ ghi đè nếu user vừa bấm Reset */
        })
        .catch(() => {})
        .finally(() => { F.completing = false; });
    }
  }, 500);
}

export const focusSync = () => invoke("focus_state").then(applyFocusPayload).catch(() => {});

export async function focusStart(taskId) {
  const t = taskById(taskId);
  if (!t) return;
  F.eyeShown = false;
  focusEyeHide();
  try { postSnap(await invoke("focus_start", { taskId })); }
  catch { notify({ kind: "error", title: "Không bắt đầu được phiên tập trung" }); return; }
  focusSync();
  focusTickStart();
  /* cửa sổ Đồng hồ luôn mở khi bắt đầu phiên (spec A.3 — một công tắc duy nhất) */
  invoke("focus_open_timer").catch(e => {
    const msg = typeof e === "string" ? e : (e && (e.message || e.toString())) || "không rõ lý do";
    notify({ kind: "error", title: "Không mở được cửa sổ Đồng hồ", body: msg });
  });
}

export function focusStop(silent) {
  const wasBreak = F.mode !== "focus";
  focusEyeHide();
  invoke("focus_stop").then(s => { postSnap(s); focusSync(); }).catch(() => {});
  if (wasBreak && !silent) notify({ kind: "info", title: "Về lại việc thôi ✦", sound: "none" });
}

export function focusTogglePause() {
  if (!F.active || F.phaseDone) return;
  invoke("focus_pause_toggle").then(applyFocusPayload).catch(() => {});
}

export function focusReset() {
  if (!F.active) return;
  F.eyeShown = false;
  focusEyeHide();
  invoke("focus_reset").then(applyFocusPayload).catch(() => {});
}

export function focusBreakStart() {
  invoke("focus_break_start").then(applyFocusPayload).catch(() => {});
}

/* VÒNG THỞ khi nghỉ — điều tiết thần kinh, không phải đếm ngược */
export let breathTimer = null, breathInhale = true;
export function startBreath() {
  stopBreath(); breathInhale = true;
  const set = () => { const el = $("#focus-breath-text"); if (el) el.textContent = breathInhale ? "Hít vào… (4 giây)" : "Thở ra… thật chậm (6 giây)"; };
  set();
  breathTimer = setInterval(() => { breathInhale = !breathInhale; set(); }, 5000);
}
export function stopBreath() { clearInterval(breathTimer); breathTimer = null; }

/* 20-20-20 — một lần mỗi phiên, đúng mốc 20:00 */
export let eyeTimer = null;
export function showEyePill() {
  F.eyeShown = true;
  const pill = $("#eye-pill"), countEl = $("#eye-count");
  if (!pill || !countEl) return;
  let left = 20;
  countEl.textContent = String(left);
  pill.hidden = false;
  clearInterval(eyeTimer);
  eyeTimer = setInterval(() => {
    left -= 1;
    countEl.textContent = String(Math.max(0, left));
    if (left <= 0) { clearInterval(eyeTimer); pill.hidden = true; }
  }, 1000);
  playChime();
}

/* ── chip phiên trên topbar (đồng hồ CHỈ ở cửa sổ riêng) ── */
export function renderFocusChip() {
  const chip = $("#focus-chip");
  if (!chip) return;
  const cd = clockDisplay();
  const show = (F.active || F.phaseDone) && cd !== "overlay";
  if (!show) { chip.hidden = true; return; }
  const rem = focusRemainingNow();
  const mm = Math.floor(rem / 60), ss = String(Math.floor(rem % 60)).padStart(2, "0");
  chip.hidden = false;
  chip.classList.toggle("is-paused", !F.phaseDone && !!F.paused);
  chip.classList.toggle("is-done", !!F.phaseDone);
  const text = chip.querySelector("#focus-chip-text");
  if (text) {
    if (F.phaseDone) text.textContent = "Xong một phiên — bấm để nghỉ";
    else if (F.paused) text.textContent = `❚❚ ${mm}:${ss} · Tạm dừng`;
    else {
      const t = F.taskTitle || "";
      const short = t.length > 26 ? t.slice(0, 25) + "…" : t;
      text.textContent = `● ${mm}:${ss} · ${short}`;
    }
  }
}
