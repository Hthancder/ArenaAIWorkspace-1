/* Taskora — Cài đặt: theme/acrylic/storage + bindSettingsEvents + accordion */
import { $, $$, closeModal, esc, hi, invoke, openModal } from "./dom.js";
import { F, S, clockDisplay } from "./state.js";
import { playChime } from "./chime.js";
import { NOTIFY_KINDS, notify, previewNotifySound } from "./notify.js";
import { openAbout, openBackups, openHelp } from "./tasks.js";
import { go, postSnap } from "./snapshot.js";
import { comboFromEvent } from "./hotkey.js";


export let lastTheme = null;
export let themeAnimT = null;
export function applyTheme(dark) {
  const t = dark ? "dark" : "light";
  if (lastTheme && lastTheme !== t) {
    const el = document.documentElement;
    el.classList.add("theme-anim");
    clearTimeout(themeAnimT);
    themeAnimT = setTimeout(() => el.classList.remove("theme-anim"), 480);
  }
  lastTheme = t;
  document.documentElement.dataset.theme = t;
  $("#theme-icon-use")?.setAttribute("href", dark ? "#i-sun" : "#i-moon");
}

import { covOf, applyAccent } from "./accent.js";

/* ─────────── thanh cuộn tự ẩn (g-scroll): hiện khi lăn chuột hoặc rê vào lề ─────────── */
export const G_SCROLLS = () => [...document.querySelectorAll(".g-scroll")];
export function markScrollOn(el) {
  el.classList.add("scroll-on");
  clearTimeout(el._hideT);
  el._hideT = setTimeout(() => el.classList.remove("scroll-on"), 900);
}
document.addEventListener("wheel", e => {
  const sc = e.target && e.target.closest ? e.target.closest(".g-scroll") : null;
  if (sc) markScrollOn(sc);
}, { passive: true });
document.addEventListener("scroll", e => {
  const t = e.target;
  if (t && t.classList && t.classList.contains("g-scroll")) markScrollOn(t);
}, true);
export let edgeRaf = null;
document.addEventListener("mousemove", e => {
  if (edgeRaf) return;
  const x = e.clientX, y = e.clientY;
  edgeRaf = requestAnimationFrame(() => {
    edgeRaf = null;
    for (const el of G_SCROLLS()) {
      if (!el.offsetParent) { el.classList.remove("edge"); continue; }
      const r = el.getBoundingClientRect();
      const insideY = y >= r.top && y <= r.bottom;
      const nearRight = insideY && x >= r.right - 22 && x <= r.right + 6 && x >= r.left - 4;
      el.classList.toggle("edge", !!nearRight);
    }
  });
}, { passive: true });
document.addEventListener("mouseleave", () => G_SCROLLS().forEach(el => el.classList.remove("edge")));

/* OS transparency: kiểm một lần mỗi phiên — không đảm bảo được thì không cho dùng nền trong suốt */
let osTransparencyVerified = false;
/// Trả true lần đầu tiên được gọi — postSnap dùng để chạy check một lần mỗi phiên.
export function markTransparencyChecked() { if (osTransparencyVerified) return false; osTransparencyVerified = true; return true; }

/* trạng thái hiệu ứng Acrylic/Blur (chỉ hiển thị trong Cài đặt) */
export let fxStatusTimer = null;
export function refreshFxStatus() {
  const el = $("#fx-status"); if (!el) return;
  clearTimeout(fxStatusTimer);
  fxStatusTimer = setTimeout(async () => {
    try {
      el.textContent = await invoke("fx_status");
      refreshOsTransparency();
    } catch { el.textContent = ""; }
  }, 350);
}

/* công tắc Transparency effects của Windows (dòng riêng + nút Bật/Tắt) */
export async function refreshOsTransparency() {
  const row = $("#os-transparency-row"); if (!row) return;
  let st = null;
  try { st = await invoke("transparency_status"); } catch { row.hidden = true; return; }
  row.hidden = !st.supported;
  const pill = $("#os-transparency-state"), btn = $("#os-transparency-btn");
  if (st.enabled === true) { pill.textContent = "BẬT"; pill.className = "fx-pill on"; btn.textContent = "Tắt"; }
  else if (st.enabled === false) { pill.textContent = "TẮT"; pill.className = "fx-pill off"; btn.textContent = "Bật"; }
  else { pill.textContent = "Không rõ"; pill.className = "fx-pill unknown"; btn.textContent = "Bật"; }
}

/* hỏi người dùng bật Transparency effects (điều kiện bắt buộc để Acrylic hiển thị) */
/** Đọc trạng thái autostart THẬT từ OS và đồng bộ UI (gọi khi mở màn Cài đặt). */
export async function syncAutostartControl() {
  try { _autostartOn = await invoke("autostart_get"); } catch { _autostartOn = false; }
  const cb = $("#set-autostart"); if (cb) cb.checked = !!_autostartOn;
  const row = $("#set-hidden-autostart-row"); if (row) row.hidden = !_autostartOn;
}

export function renderHotkeyStatusFromCmd(st, toggleEvent) {
  renderHotkeyCaps(st.hotkey || "Ctrl+Alt+T");
  $("#set-hotkey-enabled").checked = !!st.enabled;
  $("#set-hotkey-row").classList.toggle("is-off", !st.enabled);
  const hb = $("#set-hotkey-reset"); if (hb) hb.hidden = (st.hotkey || "Ctrl+Alt+T") === "Ctrl+Alt+T";
  const el = $("#hotkey-status"); if (el) {
    if (!st.enabled) { el.textContent = "Đã tắt"; el.className = "hotkey-status is-off"; }
    else if (st.active) { el.textContent = "Đang hoạt động"; el.className = "hotkey-status is-ok"; }
    else { el.textContent = "Bị phần mềm khác chiếm"; el.className = "hotkey-status is-bad"; }
  }
  if (toggleEvent && !st.enabled && toggleEvent.target.checked) {
    notify({ kind: "error", title: "Không bật được phím tắt toàn cục", body: "Tổ hợp đang bị phần mềm khác chiếm" });
  }
}

/** Áp tổ hợp mới — backend rollback + báo lỗi nếu bị chiếm. */
export async function applyHotkeyChange(spec) {
  cancelHotkeyCapture();
  try { const st = await invoke("set_global_hotkey", { spec }); renderHotkeyStatusFromCmd(st, null); }
  catch (err) {
    notify({ kind: "error", title: "Không dùng được tổ hợp này", body: String(err && err.message ? err.message : err) });
    syncHotkeyStatus(true);
  }
}

function startHotkeyCapture() {
  const btn = $("#set-hotkey-change"); if (!btn) return;
  cancelHotkeyCapture();
  btn.textContent = "Nhấn tổ hợp… (Esc để hủy)";
  const onKey = ev => {
    ev.preventDefault(); ev.stopPropagation();
    const keyName = ev.key;
    if (keyName === "Escape") { cancelHotkeyCapture(); return; }
    if (keyName === "Backspace" || keyName === "Delete") { applyHotkeyChange("Ctrl+Alt+T"); return; }
    const combo = comboFromEvent(ev);
    if (!combo) return;             // chỉ modifier / phím ngoài phạm vi → chờ tiếp
    if (combo.error === "modifier") { notify({ kind: "info", title: "Cần ít nhất một phím Ctrl, Alt, Shift hoặc Win", sound: "none" }); return; }
    applyHotkeyChange(combo.spec);
  };
  hotkeyCapture = { onKey };
  document.addEventListener("keydown", onKey, true);
}

/* modal mở bất kỳ ⇒ hủy chế độ chờ tổ hợp (tránh nuốt phím) */
document.addEventListener("taskora:modal-open", () => cancelHotkeyCapture());
/* rời màn hoặc cửa sổ mất focus ⇒ hủy chế độ chờ */
document.addEventListener("visibilitychange", () => { if (document.hidden) cancelHotkeyCapture(); });
window.addEventListener("blur", () => cancelHotkeyCapture());

export function openTransparencyDialog() {
  openModal(`<h2><svg class="ic accent-ic"><use href="#i-sun"/></svg>Cần bật Transparency effects</h2>
    <p>Để cửa sổ Taskora nhìn xuyên được, Windows cần công tắc <strong>Transparency effects</strong> (Settings → Personalization → Colors) được bật. Hiện nó đang tắt nên Acrylic không thể hiển thị.</p>
    <p style="margin-top:8px;color:var(--text-weak)">Taskora có thể bật giúp bạn ngay — chỉ ảnh hưởng tài khoản Windows hiện tại, tắt lại được bất cứ lúc nào (nút ngay trong Cài đặt → Giao diện).</p>
    <div class="modal-actions"><button class="btn-cancel" id="os-tr-decline">Không, dùng nền đặc</button><button class="btn-save" id="os-tr-enable">Bật ngay</button></div>`);
}

export function syncSettingsControls(s) {
  const st = s.settings;
  if (!st || !$("#view-settings")) return;
  $$("#set-theme button").forEach(b => b.classList.toggle("on", (b.dataset.dark === "1") === !!st.dark));
  $$("#accent-swatches .swatch").forEach(b => b.classList.toggle("on", String(b.dataset.accent || "").toLowerCase() === String(st.accent || "").toLowerCase()));
  const hexEl = $("#accent-hex");
  if (document.activeElement !== hexEl) hexEl.value = String(st.accent || "").replace(/^#/, "");
  const pk = $("#accent-picker");
  if (pk && document.activeElement !== pk && /^#[0-9a-fA-F]{6}$/.test(st.accent || "")) pk.value = st.accent;
  $("#set-transparent").checked = !!st.transparent;
  const alpha = st.acrylic_alpha ?? 110;
  $("#set-alpha").value = alpha; $("#set-alpha-val").textContent = alpha;
  $("#set-reduce-motion").checked = !!st.reduce_motion;
  $("#set-sort").value = st.sort;
  $("#set-hide-done").checked = !!st.hide_completed;
  $("#set-qa-preview").checked = !!st.qa_preview;
  $("#set-backup-on-exit").checked = !!st.backup_on_exit;
  $("#set-perf").checked = !!st.perf_mode;
  $("#set-adhd").checked = !!st.adhd_mode;
  const snd = $("#set-sound"); if (snd) snd.checked = st.sound_on !== false;
  const fm = $("#set-focus-min"); if (fm) fm.value = st.focus_min ?? 25;
  syncMinuteChips("focus", st.focus_min ?? 25);
  const brm = $("#set-break-min"); if (brm) brm.value = st.break_min ?? 5;
  syncMinuteChips("break", st.break_min ?? 5);
  const lbm = $("#set-long-break-min"); if (lbm) lbm.value = st.long_break_min ?? 15;
  syncMinuteChips("long", st.long_break_min ?? 15);
  const lbe = $("#set-long-break-every"); if (lbe) lbe.value = String(st.long_break_every ?? 4);
  const asb = $("#set-auto-start-break"); if (asb) asb.checked = !!st.auto_start_break;
  const asf = $("#set-auto-start-focus"); if (asf) asf.checked = !!st.auto_start_focus;
  const er = $("#set-eye-reminder"); if (er) er.checked = st.eye_reminder !== false;
  const fcd = $("#focus-clock-display"); if (fcd) fcd.value = clockDisplay();
  syncNotifyControls(st);
  /* một lần duy nhất sau khi mở app: field focus_clock_display — nếu dữ liệu cũ chưa có, ghi lại giá trị suy từ legacy */
  if (!_clockDisplayMigrated && st && st.focus_clock_display == null) {
    _clockDisplayMigrated = true;
    patchSettings({ focus_clock_display: st.focus_auto_open_timer === false ? "overlay" : "window" });
  }
  $$("#set-chime button").forEach(b => b.classList.toggle("on", (st.chime || "soft") === b.dataset.chime));
  /* v2.12.0 — Nhóm 0 */
  const cb = st.close_behavior || "ask";
  $$("#set-close-behavior button").forEach(b => b.classList.toggle("on", b.dataset.behavior === cb));
  $("#set-hidden-autostart").checked = st.hidden_on_autostart !== false;
  $("#set-hidden-autostart-row").hidden = !_autostartOn; // ẩn nếu autostart đang tắt (hoặc chưa đọc được trạng thái thật)
  const hkEnabled = st.global_hotkey_enabled !== false;
  $("#set-hotkey-enabled").checked = hkEnabled;
  const hkSpec = st.global_hotkey || "Ctrl+Alt+T";
  renderHotkeyCaps(hkSpec);
  $("#set-hotkey-row").classList.toggle("is-off", !hkEnabled);
  const hb = $("#set-hotkey-reset"); if (hb) hb.hidden = hkSpec === "Ctrl+Alt+T";
  syncHotkeyStatus(true);
}

/* ─────────── v2.12.0 — phím tắt toàn cục ─────────── */
let _hotkeyStatusReq = 0;
let hotkeyCapture = null; // { onKey } khi đang chờ tổ hợp mới
let _autostartOn = false;

export function renderHotkeyCaps(spec) {
  const el = $("#hotkey-caps"); if (!el) return;
  const parts = String(spec || "Ctrl+Alt+T").split("+");
  el.innerHTML = parts.map(p => `<kbd class="modal-kbd">${esc(p)}</kbd>`).join("");
}

export async function syncHotkeyStatus(silent) {
  const req = ++_hotkeyStatusReq;
  let st = null;
  try { st = await invoke("global_hotkey_status"); } catch { return; }
  if (req !== _hotkeyStatusReq) return;
  renderHotkeyCaps(st.hotkey || "Ctrl+Alt+T");
  $("#set-hotkey-enabled").checked = !!st.enabled;
  $("#set-hotkey-row").classList.toggle("is-off", !st.enabled);
  const hb = $("#set-hotkey-reset"); if (hb) hb.hidden = (st.hotkey || "Ctrl+Alt+T") === "Ctrl+Alt+T";
  const el = $("#hotkey-status"); if (!el) return;
  if (!st.enabled) {
    el.textContent = "Đã tắt"; el.className = "hotkey-status is-off";
  } else if (st.active) {
    el.textContent = "Đang hoạt động"; el.className = "hotkey-status is-ok";
  } else {
    el.textContent = "Bị phần mềm khác chiếm"; el.className = "hotkey-status is-bad";
  }
}

export function cancelHotkeyCapture() {
  if (hotkeyCapture) {
    const hk = $("#set-hotkey-change");
    if (hk) hk.textContent = "Đổi…";
    document.removeEventListener("keydown", hotkeyCapture.onKey, true);
    hotkeyCapture = null;
  }
}

export function syncMinuteChips(group, val) {
  $$(`.minute-chip[data-group="${group}"]`).forEach(b => b.classList.toggle("on", Number(b.dataset.value) === Number(val)));
}

/* ─────────── NƠI LƯU DỮ LIỆU ─────────── */
export let storageInfo = null;

export async function refreshStoragePanel() {
  try { storageInfo = await invoke("storage_info"); } catch { return; }
  renderStoragePanel(storageInfo);
}
export function renderStoragePanel(info) {
  if (!info || !$("#storage-mode")) return;
  const badge = $("#storage-mode");
  badge.textContent = info.mode === "portable" ? "Portable" : info.mode === "custom" ? "Tùy chỉnh" : "Mặc định";
  badge.classList.toggle("portable", info.mode === "portable");
  badge.classList.toggle("custom", info.mode === "custom");
  $("#storage-path").textContent = info.dir;
  $("#storage-warn").hidden = info.exe_dir_writable;
  const toggle = $("#set-portable");
  toggle.checked = !!info.portable;
  toggle.disabled = !info.exe_dir_writable && !info.portable;
  $("#storage-default").hidden = info.mode === "default";
}
export const pickFolder = async () => {
  try {
    const sel = await window.__TAURI__?.dialog?.open?.({ directory: true, multiple: false, title: "Chọn thư mục lưu dữ liệu" });
    return typeof sel === "string" ? sel : null;
  } catch { return null; }
};
export function openStorageConfirm(choice, customPath) {
  const dest = choice === "portable" ? "thư mục chứa Taskora.exe" : choice === "default" ? "%APPDATA%\\Taskora" : (customPath || "");
  openModal(`<h2><svg class="ic accent-ic"><use href="#i-folder"/></svg>Chuyển nơi lưu dữ liệu?</h2>
    <p>Taskora sẽ lưu dữ liệu tại:</p>
    <div class="storage-path">${esc(dest)}</div>
    <p style="margin-top:10px">Bạn muốn xử lý dữ liệu hiện tại thế nào?</p>
    <div class="modal-actions"><button class="btn-cancel" data-close-modal="1">Hủy</button>
      <button class="btn-ghost" id="storage-fresh">Bắt đầu mới trống</button>
      <button class="btn-save" id="storage-migrate"><svg class="ic small"><use href="#i-archive"/></svg>Chuyển dữ liệu sang</button></div>`);
  S.storagePending = { choice, custom_path: customPath || null };
}
export function openStorageCustomModal() {
  openModal(`<h2><svg class="ic accent-ic"><use href="#i-folder"/></svg>Đổi thư mục lưu</h2>
    <p>Nhập đường dẫn thư mục — Taskora sẽ tự tạo nếu chưa tồn tại.</p>
    <input class="modal-input" id="storage-custom-input" type="text" spellcheck="false" placeholder="D:\\TaskoraData" autocomplete="off" />
    <div class="modal-actions"><button class="btn-cancel" data-close-modal="1">Hủy</button>
      <button class="btn-ghost" id="storage-custom-browse"><svg class="ic small"><use href="#i-folder"/></svg>Duyệt…</button>
      <button class="btn-save" id="storage-custom-next">Tiếp tục</button></div>`);
  setTimeout(() => $("#storage-custom-input")?.focus(), 60);
}
export async function runStorageSwitch(migrate) {
  const p = S.storagePending; if (!p) return;
  closeModal();
  try {
    const res = await invoke("storage_switch", { req: { choice: p.choice, custom_path: p.custom_path, migrate } });
    postSnap(res.snapshot);
    renderStoragePanel(res.info);
  } catch (err) {
    notify({ kind: "error", title: typeof err === "string" ? err : "Không đổi được nơi lưu" });
    refreshStoragePanel();
  }
}
export async function runStorageMergeLegacy() {
  closeModal();
  try {
    const res = await invoke("storage_merge_legacy");
    postSnap(res.snapshot);
    renderStoragePanel(res.info);
  } catch (err) { notify({ kind: "error", title: typeof err === "string" ? err : "Gộp thất bại" }); }
}
export async function runStorageImportOrphan() {
  closeModal();
  try {
    const res = await invoke("storage_import_orphan");
    postSnap(res.snapshot);
    renderStoragePanel(res.info);
  } catch (err) { notify({ kind: "error", title: typeof err === "string" ? err : "Chuyển thất bại" }); }
}
export async function checkStoragePrompts() {
  if (S._storagePromptDone) return;
  S._storagePromptDone = true;
  let info;
  try { info = await invoke("storage_startup"); } catch { return; }
  renderStoragePanel(info);
  if (info.moved) notify({ kind: "info", title: "Taskora đã được di chuyển", body: "Dữ liệu vẫn đi theo file thực thi", sound: "none" });
  if (info.orphan_portable) {
    S._orphanDir = info.orphan_portable;
    openModal(`<h2><svg class="ic accent-ic"><use href="#i-folder"/></svg>Taskora đã được di chuyển?</h2>
      <p>Phát hiện dữ liệu portable tại:</p>
      <div class="storage-path">${esc(info.orphan_portable)}</div>
      <p style="margin-top:10px">Chuyển toàn bộ dữ liệu sang vị trí mới (cạnh file thực thi hiện tại)?</p>
      <div class="modal-actions"><button class="btn-cancel" data-close-modal="1">Để sau</button>
        <button class="btn-save" id="orphan-import"><svg class="ic small"><use href="#i-archive"/></svg>Chuyển dữ liệu sang đây</button></div>`);
    return;
  }
  if (info.legacy_dir) {
    S._legacyDir = info.legacy_dir;
    openModal(`<h2><svg class="ic accent-ic"><use href="#i-archive"/></svg>Phát hiện dữ liệu cũ</h2>
      <p>Tìm thấy <strong>${info.legacy_tasks} việc</strong> · <strong>${info.legacy_lists} danh sách</strong> tại <code>%APPDATA%\Taskora</code>, trong khi bạn đang dùng nơi lưu khác.</p>
      <div class="modal-actions"><button class="btn-cancel" id="legacy-keep">Giữ riêng</button>
        <button class="btn-save" id="legacy-merge"><svg class="ic small"><use href="#i-arrow-counter-clockwise"/></svg>Gộp vào dữ liệu hiện tại</button></div>`);
  }
}

/* ─────────── NHÓM "THÔNG BÁO" (v2.11.0) ─────────── */
let _clockDisplayMigrated = false;

const HIDE_CHOICES = [3, 5, 8, 10];

/* Đồng bộ mọi control trong nhóm Thông báo từ settings */
export function syncNotifyControls(st) {
  if (!st) return;
  const setChk = (id, v) => { const el = $(id); if (el) el.checked = v !== false; };
  setChk("#notify-enabled", st.notify_enabled !== false);
  setChk("#notify-autohide", st.notify_autohide !== false);
  setChk("#notify-sound", st.notify_sound_on !== false);
  const secs = HIDE_CHOICES.includes(Number(st.notify_hide_secs)) ? Number(st.notify_hide_secs) : 5;
  $$("#notify-hide-secs button").forEach(b => b.classList.toggle("on", Number(b.dataset.secs) === secs));
  const wrap = $("#notify-hide-secs"); if (wrap) wrap.classList.toggle("is-disabled", st.notify_autohide === false);
  /* hàng theo từng loại — dựng lại mỗi lần (idempotent, rẻ) */
  renderNotifyKindRows(st);
}

const SOUND_OPTIONS = [
  ["default", "Mặc định"],
  ["soft", "3 nốt"],
  ["wind", "Chuông gió"],
  ["none", "Không"],
  ["custom", "Tùy chỉnh…"],
];

function renderNotifyKindRows(st) {
  const box = $("#notify-kind-rows");
  if (!box) return;
  const prefs = st.notify_prefs || {};
  const customs = st.notify_custom_sounds || {};
  box.innerHTML = NOTIFY_KINDS.map(k => {
    const p = prefs[k.key] || {};
    const on = p.on !== false;
    const sound = typeof p.sound === "string" ? p.sound : "default";
    const customName = customs[k.key] ? esc((S.customSoundNames && S.customSoundNames[k.key]) || "tệp của bạn") : null;
    const opts = SOUND_OPTIONS.map(([v, label]) => {
      const sel = sound === v ? " selected" : "";
      const customLabel = v === "custom" && customName ? `Tùy chỉnh: ${customName}` : label;
      return `<option value="${v}"${sel}>${customLabel}</option>`;
    }).join("");
    const force = k.key === "storage_error";
    return `<div class="notify-kind-row" data-kind="${k.key}">
      <div class="notify-kind-ic"><svg class="ic"><use href="${esc(k.icon)}"/></svg></div>
      <div class="notify-kind-info">
        <div class="notify-kind-title">${esc(k.label)}</div>
        <div class="notify-kind-desc">${esc(k.desc)}</div>
      </div>
      <select class="notify-sound-select" data-kind="${k.key}" aria-label="Âm thanh cho ${esc(k.label)}">${opts}</select>
      <button class="notify-preview-btn icon-btn" type="button" data-kind="${k.key}" title="Nghe thử" aria-label="Nghe thử âm thanh"><svg class="ic small"><use href="#i-speaker-high"/></svg></button>
      <label class="toggle-wrap"><input type="checkbox" class="notify-kind-on" data-kind="${k.key}" ${on ? "checked" : ""} ${force ? 'disabled title="Lỗi dữ liệu luôn hiện"' : ""} /><span class="toggle-ui"></span></label>
    </div>`;
  }).join("");
}

/* file picker cho âm tùy chỉnh — mp3/wav/ogg ≤ 256 KB, lưu data URI vào data.json */
const MAX_CUSTOM_SOUNDS = 4;
const MAX_CUSTOM_BYTES = 256 * 1024;

function pickSoundFile() {
  return new Promise(resolve => {
    const inp = document.createElement("input");
    inp.type = "file";
    inp.accept = "audio/mpeg,audio/wav,audio/ogg,audio/x-m4a,.mp3,.wav,.ogg,.m4a";
    inp.addEventListener("change", () => resolve(inp.files && inp.files[0] ? inp.files[0] : null), { once: true });
    inp.addEventListener("cancel", () => resolve(null), { once: true });
    inp.click();
  });
}

async function attachCustomSound(kind, file) {
  if (!file) return null;
  if (file.size > MAX_CUSTOM_BYTES) {
    notify({ kind: "error", title: "Tệp âm thanh quá lớn", body: "Tối đa 256 KB mỗi tệp" });
    return null;
  }
  const st = S.snap && S.snap.settings ? S.snap.settings : {};
  const customs = { ...(st.notify_custom_sounds || {}) };
  if (!customs[kind] && Object.keys(customs).length >= MAX_CUSTOM_SOUNDS) {
    notify({ kind: "error", title: "Đã đủ 4 tệp âm tùy chỉnh", body: "Xóa một tệp đang dùng trước khi thêm mới" });
    return null;
  }
  const dataUri = await new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result || ""));
    r.onerror = () => reject(new Error("read"));
    r.readAsDataURL(file);
  }).catch(() => null);
  if (!dataUri || !dataUri.startsWith("data:audio/")) {
    notify({ kind: "error", title: "Không đọc được tệp âm thanh" });
    return null;
  }
  customs[kind] = dataUri;
  return { dataUri, name: file.name };
}

function bindNotifyEvents() {
  $("#notify-enabled")?.addEventListener("change", e => patchSettings({ notify_enabled: e.target.checked }));
  $("#notify-sound")?.addEventListener("change", e => patchSettings({ notify_sound_on: e.target.checked }));
  $("#notify-autohide")?.addEventListener("change", e => patchSettings({ notify_autohide: e.target.checked }));
  $$("#notify-hide-secs button").forEach(b => b.addEventListener("click", () => patchSettings({ notify_hide_secs: Number(b.dataset.secs) })));
  $("#notify-test")?.addEventListener("click", () => notify({ kind: "info", title: "Thông báo thử ✦", body: "Như vậy là mọi thứ đang hoạt động đúng phong cách app" }));

  /* delegation cho các hàng theo loại (dựng lại nhiều lần) */
  $("#notify-kind-rows")?.addEventListener("change", async e => {
    const onBox = e.target.closest(".notify-kind-on");
    if (onBox) {
      const kind = onBox.dataset.kind;
      const st = S.snap && S.snap.settings ? S.snap.settings : {};
      const prefs = { ...(st.notify_prefs || {}) };
      const cur = { on: true, sound: "default", ...(prefs[kind] || {}) };
      prefs[kind] = { ...cur, on: onBox.checked };
      patchSettings({ notify_prefs: prefs });
      return;
    }
    const sel = e.target.closest(".notify-sound-select");
    if (sel) {
      const kind = sel.dataset.kind;
      const v = sel.value;
      if (v === "custom") {
        const file = await pickSoundFile();
        if (!file) { syncNotifyControls(S.snap && S.snap.settings); return; }
        const st = S.snap && S.snap.settings ? S.snap.settings : {};
        const attached = await attachCustomSound(kind, file);
        if (!attached) { syncNotifyControls(st); return; }
        const customs = { ...(st.notify_custom_sounds || {}), [kind]: attached.dataUri };
        const prefs = { ...(st.notify_prefs || {}) };
        const cur = { on: true, sound: "default", ...(prefs[kind] || {}) };
        prefs[kind] = { ...cur, sound: "custom" };
        /* tên file chỉ để hiển thị trong phiên này — data.json chỉ giữ data URI */
        (S.customSoundNames ||= {})[kind] = attached.name;
        patchSettings({ notify_custom_sounds: customs, notify_prefs: prefs });
        return;
      }
      const st = S.snap && S.snap.settings ? S.snap.settings : {};
      const prefs = { ...(st.notify_prefs || {}) };
      const cur = { on: true, sound: "default", ...(prefs[kind] || {}) };
      prefs[kind] = { ...cur, sound: v };
      if (v === "none" || v === "default" || v === "soft" || v === "wind") patchSettings({ notify_prefs: prefs });
      return;
    }
  });
  $("#notify-kind-rows")?.addEventListener("click", e => {
    const btn = e.target.closest(".notify-preview-btn");
    if (!btn) return;
    const sel = btn.parentElement.querySelector(".notify-sound-select");
    previewNotifySound(btn.dataset.kind, sel ? sel.value : undefined);
  });
}

/* ── accordion cho MỌI nhóm trong Cài đặt (C.3) ── */
const COLLAPSE_KEY = "taskora.settings.collapsed";

function readCollapsed() {
  try { return new Set(JSON.parse(localStorage.getItem(COLLAPSE_KEY) || "[]")); } catch { return new Set(); }
}
function writeCollapsed(set) {
  try { localStorage.setItem(COLLAPSE_KEY, JSON.stringify([...set])); } catch { /* ignore */ }
}

export function initSettingsAccordion() {
  const collapsed = readCollapsed();
  $$("#view-settings .settings-group").forEach(group => {
    const head = group.querySelector(".settings-group-head");
    const body = group.querySelector(".settings-group-body");
    if (!head || !body) return;
    const id = group.id;
    const count = group.querySelectorAll(".setting-row").length;
    const badge = head.querySelector(".settings-group-count");
    if (badge) badge.textContent = count === 1 ? "1 dòng" : `${count} dòng`;
    const apply = () => {
      const closed = collapsed.has(id);
      group.classList.toggle("is-collapsed", closed);
      head.setAttribute("aria-expanded", String(!closed));
    };
    head.addEventListener("click", () => {
      if (collapsed.has(id)) collapsed.delete(id); else collapsed.add(id);
      writeCollapsed(collapsed);
      apply();
    });
    head.addEventListener("keydown", e => {
      if (e.key === "Enter" || e.key === " ") { e.preventDefault(); head.click(); }
    });
    apply();
  });
}

/* ── settings wiring (tách từ bindEvents) ── */
export const patchSettings = p => go(invoke("update_settings", { patch: p }));

export function bindSettingsEvents() {
  bindNotifyEvents();
  /* cài đặt v2.1 */
  const ACCENTS = ["#6366f1", "#8b5cf6", "#3b82f6", "#06b6d4", "#10b981", "#f43f5e", "#f59e0b", "#64748b"];
  const swWrap = $("#accent-swatches");
  swWrap.innerHTML = ACCENTS.map(c => `<button class="swatch" data-accent="${c}" style="background:${c}" title="${c}" aria-label="Màu ${c}"></button>`).join("");
  swWrap.addEventListener("click", e => { const b = e.target.closest("[data-accent]"); if (b) patchSettings({ accent: b.dataset.accent }); });
  $("#accent-picker").addEventListener("input", e => applyAccent(e.target.value));
  $("#accent-picker").addEventListener("change", e => patchSettings({ accent: e.target.value }));
  let hexTimer = null;
  $("#accent-hex").addEventListener("input", e => {
    const raw = e.target.value.trim().replace(/^#/, "");
    const ok = /^[0-9a-fA-F]{6}$/.test(raw);
    e.target.closest(".hex-wrap").classList.toggle("bad", !ok && raw.length > 0);
    $("#accent-hex-ok").hidden = !ok;
    if (!ok) return;
    const v = "#" + raw.toLowerCase();
    applyAccent(v);
    clearTimeout(hexTimer);
    hexTimer = setTimeout(() => patchSettings({ accent: v }), 350);
  });
  $$("#set-theme button").forEach(b => b.addEventListener("click", () => patchSettings({ dark: b.dataset.dark === "1" })));
  $("#os-transparency-btn").addEventListener("click", async () => {
    let st = null;
    try { st = await invoke("transparency_status"); } catch { notify({ kind: "error", title: "Không đọc được Transparency effects" }); return; }
    const on = !(st && st.enabled === true);
    try {
      const snap = await invoke("set_transparency", { on });
      postSnap(snap);
      notify({ kind: "info", title: on ? "Đã bật Transparency effects" : "Đã tắt Transparency effects", body: on ? "Acrylic có thể hiển thị" : "Taskora chuyển nền đặc", sound: "none" });
    } catch (err) { notify({ kind: "error", title: String(err && err.message ? err.message : err) }); }
    refreshOsTransparency();
  });
  $("#set-transparent").addEventListener("change", async e => {
    const want = e.target.checked;
    if (!want) { patchSettings({ transparent: false }); return; }
    let os = null;
    try { os = await invoke("transparency_status"); } catch { os = null; }
    if (os && os.supported && os.enabled === false) {
      e.target.checked = false; // chưa được phép bật — hỏi người dùng trước
      openTransparencyDialog();
      return;
    }
    patchSettings({ transparent: true });
    if (os && os.supported && os.enabled == null) {
      notify({ kind: "info", title: "Không đọc được Transparency effects", body: "Nếu nền vẫn đục, hãy kiểm tra Settings → Personalization → Colors", sound: "none" });
    }
  });
  $("#set-alpha").addEventListener("input", e => { $("#set-alpha-val").textContent = e.target.value; document.documentElement.style.setProperty("--cov", covOf(e.target.value).toFixed(3)); });
  $("#set-alpha").addEventListener("change", e => patchSettings({ acrylic_alpha: Number(e.target.value) }));
  $("#set-reduce-motion").addEventListener("change", e => patchSettings({ reduce_motion: e.target.checked }));
  $("#set-sort").addEventListener("change", e => patchSettings({ sort: e.target.value }));
  $("#set-hide-done").addEventListener("change", e => patchSettings({ hide_completed: e.target.checked }));
  $("#set-qa-preview").addEventListener("change", e => patchSettings({ qa_preview: e.target.checked }));
  $("#set-backup-on-exit").addEventListener("change", e => patchSettings({ backup_on_exit: e.target.checked }));
  $("#set-export").addEventListener("click", async () => { try { const name = await invoke("export_backup"); notify({ kind: "info", title: "Đã xuất " + name, sound: "none" }); } catch { notify({ kind: "error", title: "Xuất thất bại" }); } });
  $("#set-import").addEventListener("click", openBackups);
  $("#set-open-dir").addEventListener("click", () => invoke("open_data_dir"));
  $("#set-reset").addEventListener("click", () => {
    openModal(`<h2><svg class="ic danger"><use href="#i-warning"/></svg>Đặt lại toàn bộ cài đặt?</h2>
      <p>Mọi tùy chỉnh giao diện và hành vi sẽ trở về mặc định. Việc làm, danh sách và thẻ của bạn được giữ nguyên.</p>
      <div class="modal-actions"><button class="btn-cancel" data-close-modal="1">Hủy</button><button class="btn-danger" id="confirm-reset-settings">Đặt lại cài đặt</button></div>`);
  });
  $("#set-open-help").addEventListener("click", openHelp);
  $("#set-open-about").addEventListener("click", openAbout);
  $("#set-perf").addEventListener("change", e => patchSettings({ perf_mode: e.target.checked }));
  $("#set-sound").addEventListener("change", e => { patchSettings({ sound_on: e.target.checked }); notify({ kind: "info", title: e.target.checked ? "Âm thanh bật" : "Âm thanh tắt", sound: "none" }); });
  $("#set-adhd").addEventListener("change", e => {
    patchSettings({ adhd_mode: e.target.checked });
    notify({ kind: "info", title: e.target.checked ? "Chế độ ADHD bật — một việc tại một thời điểm ✦" : "Chế độ ADHD tắt", sound: "none" });
  });

  /* ───────── Nhóm GIAO DIỆN (v2.12.0 — Nhóm 0) ───────── */
  $$("#set-close-behavior button").forEach(btn => btn.addEventListener("click", async () => {
    const v = btn.dataset.behavior;
    try { const snap = await invoke("set_close_behavior", { behavior: v }); postSnap(snap); }
    catch (err) { notify({ kind: "error", title: String(err && err.message ? err.message : err) }); }
  }));
  $("#set-autostart")?.addEventListener("change", async e => {
    const want = e.target.checked;
    try {
      _autostartOn = await invoke("autostart_set", { enabled: want });
    } catch (err) {
      _autostartOn = !want; // rollback hiển thị
      notify({ kind: "error", title: "Không đổi được tự khởi động", body: String(err && err.message ? err.message : err) });
    }
    e.target.checked = _autostartOn;
    const row = $("#set-hidden-autostart-row"); if (row) row.hidden = !_autostartOn;
    notify({ kind: "info", title: _autostartOn ? "Taskora sẽ mở cùng Windows" : "Taskora sẽ không tự mở cùng Windows", sound: "none" });
  });
  $("#set-hidden-autostart")?.addEventListener("change", e => patchSettings({ hidden_on_autostart: e.target.checked }));
  $("#set-hotkey-enabled")?.addEventListener("change", async e => {
    try { const st = await invoke("set_global_hotkey_enabled", { enabled: e.target.checked }); renderHotkeyStatusFromCmd(st, e); }
    catch (err) { e.target.checked = false; notify({ kind: "error", title: String(err && err.message ? err.message : err) }); syncHotkeyStatus(true); }
  });
  $("#set-hotkey-change")?.addEventListener("click", startHotkeyCapture);
  $("#set-hotkey-reset")?.addEventListener("click", () => applyHotkeyChange("Ctrl+Alt+T"));

  /* ───────── Nhóm TẬP TRUNG (v2.10.0) ───────── */
  const minuteCfg = [
    { group: "focus", input: "#set-focus-min", key: "focus_min", min: 5, max: 180 },
    { group: "break", input: "#set-break-min", key: "break_min", min: 1, max: 60 },
    { group: "long", input: "#set-long-break-min", key: "long_break_min", min: 5, max: 60 },
  ];
  for (const c of minuteCfg) {
    const input = $(c.input);
    if (!input) continue;
    const apply = () => {
      let v = Math.round(Number(input.value) || 0);
      v = Math.min(c.max, Math.max(c.min, v));
      input.value = String(v);
      syncMinuteChips(c.group, v);
      patchSettings({ [c.key]: v });
    };
    input.addEventListener("change", apply);
    /* gõ tới đâu vá tới đó — không cần blur mới có tác dụng */
    let debounce = null;
    input.addEventListener("input", () => {
      const v = Math.round(Number(input.value) || 0);
      if (v < c.min || v > c.max) { syncMinuteChips(c.group, -1); return; }
      clearTimeout(debounce);
      debounce = setTimeout(apply, 450);
    });
  }
  $$(".minute-chip").forEach(b => b.addEventListener("click", () => {
    const c = minuteCfg.find(x => x.group === b.dataset.group);
    if (!c) return;
    const v = Number(b.dataset.value);
    const input = $(c.input); if (input) input.value = String(v);
    syncMinuteChips(c.group, v);
    patchSettings({ [c.key]: v });
  }));
  $("#set-long-break-every")?.addEventListener("change", e => patchSettings({ long_break_every: Number(e.target.value) }));
  $("#set-auto-start-break")?.addEventListener("change", e => patchSettings({ auto_start_break: e.target.checked }));
  $("#set-auto-start-focus")?.addEventListener("change", e => patchSettings({ auto_start_focus: e.target.checked }));
  $("#set-eye-reminder")?.addEventListener("change", e => patchSettings({ eye_reminder: e.target.checked }));
  $("#focus-clock-display")?.addEventListener("change", e => {
    const v = e.target.value;
    patchSettings({ focus_clock_display: v });
    const label = { window: "Chỉ ở cửa sổ riêng", overlay: "Trên app chính (overlay)", both: "Cả hai" }[v] || v;
    notify({ kind: "info", title: "Hiển thị đồng hồ: " + label, sound: "none" });
  });
  $$("#set-chime button").forEach(b => b.addEventListener("click", () => patchSettings({ chime: b.dataset.chime })));
  $("#set-chime-test")?.addEventListener("click", () => {
    const sel = ($$("#set-chime button.on")[0] || {}).dataset?.chime || (S.snap?.settings?.chime) || "soft";
    playChime(sel, true);
  });
  $("#storage-open").addEventListener("click", () => invoke("open_data_dir"));
  $("#storage-browse").addEventListener("click", openStorageCustomModal);
  $("#storage-default").addEventListener("click", () => openStorageConfirm("default", null));
  $("#set-portable").addEventListener("change", e => {
    const want = e.target.checked;
    openStorageConfirm(want ? "portable" : "default", null);
  });

  /* ───────── modal actions (delegation) ───────── */
}
