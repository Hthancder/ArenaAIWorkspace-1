/* Taskora v2 — IPC (Tauri core) + toàn bộ hành vi UI */
"use strict";
const invoke = (cmd, args) => window.__TAURI__.core.invoke(cmd, args);
/// View gửi lên backend — backend không biết "stats"/"settings" cho các lệnh act/…
/// → quy về inbox (đếm theo view không ảnh hưởng).
const viewWire = v => (v && (v.type === "stats" || v.type === "settings")) ? { type: "inbox" } : v;
const $ = (sel, root) => (root || document).querySelector(sel);
const $$ = (sel, root) => [...(root || document).querySelectorAll(sel)];
const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const hi = (text, q) => {
  const e = esc(text);
  if (!q) return e;
  const qe = esc(q).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return e.replace(new RegExp("(" + qe + ")", "ig"), "<mark>$1</mark>");
};
const parseYmd = s => { const [y, m, d] = s.split("-").map(Number); return Date.UTC(y, m - 1, d); };
const fmtViDate = d => d.toLocaleDateString("vi-VN", { weekday: "short", day: "numeric", month: "numeric", year: "numeric" });
const fmtViTime = d => d.toLocaleString("vi-VN", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });
const strip = s => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();

/* Chế độ ADHD — trạng thái phiên tập trung (không persist) */
const F = { active: false, mode: "focus", taskId: null, taskTitle: "", totalSecs: 1500, endsAtMs: null, remainingSecs: 1500, paused: false, phaseDone: false, cycleCount: 0, nextBreakLong: false, soundOn: true, chime: "soft", timer: null, eyeShown: false, completing: false, breakDoneFlag: false };
const ADHD_QA = ["Chỉ cần 1 việc nhỏ nhất thôi…", "Viết 1 dòng — cứ ngắn và xấu cũng được", "Việc 2 phút cũng đáng kể", "Ném vào đây rồi tính sau"];
const ADHD_PRAISE = ["Xong rồi! Một điểm cộng nữa ✦", "Tốt! Bạn đang lấy đà.", "Thêm một việc được xử đẹp.", "Đã xong — thưởng cho mình một hơi thở sâu.", "Tuyệt, việc tiếp theo thôi."];
const pick = arr => arr[Math.floor(Math.random() * arr.length)];

const S = {
  snap: null,
  view: { type: "inbox" },
  search: "",
  tag: null,
  prio: null,
  selected: null,
  sort: "Manual",
  hideDone: true,
  visibleIds: [],
  bulk: false,
  bulkSel: new Set(),
  paletteIdx: 0,
  paletteItems: [],
  dragId: null,
  statsKey: "",
};

const VIEW_META = {
  inbox: { icon: "tray", title: "Hộp thư", sub: "Việc chưa phân vào danh sách nào" },
  today: { icon: "calendar-check", title: "Hôm nay", sub: "Đến hạn hôm nay và các việc quá hạn" },
  upcoming: { icon: "calendar-blank", title: "Sắp tới", sub: "Việc đã đặt hạn chót trong tương lai" },
  starred: { icon: "star", title: "Đã ghim", sub: "Những việc bạn đang ưu tiên" },
  completed: { icon: "check-circle", title: "Đã hoàn thành", sub: "Việc đã xong — bấm để mở lại nếu cần" },
  trash: { icon: "trash", title: "Thùng rác", sub: "Việc đã xóa — khôi phục hoặc xóa vĩnh viễn" },
  stats: { icon: "chart-bar", title: "Thống kê", sub: "Bức tranh hoạt động của bạn" },
  settings: { icon: "gear", title: "Cài đặt", sub: "Tùy chỉnh giao diện, hành vi và dữ liệu" },
};
const PRIO_LABEL = { P1: "P1", P2: "P2", P3: "P3", P4: "P4" };

/* ─────────── tiện ích ─────────── */
const taskById = id => (S.snap.tasks || []).find(t => t.id === id);
const isCompleted = t => !!t.completed_at;
const isDeleted = t => !!t.deleted_at;
const isActive = t => !isCompleted(t) && !isDeleted(t);

function dueDiffDays(due) { // số ngày so với hôm nay (+ tương lai / - quá khứ)
  if (!due || !S.snap) return null;
  return Math.round((parseYmd(due.slice(0, 10)) - parseYmd(S.snap.today)) / 86400000);
}
function dueChip(t) {
  if (!t.due) return "";
  const diff = dueDiffDays(t.due);
  const [, m, d] = t.due.slice(0, 10).split("-").map(Number);
  const md = d.toString().padStart(2, "0") + "/" + m.toString().padStart(2, "0");
  if (diff < 0) return `<span class="meta-chip due-overdue"><svg class="ic"><use href="#i-warning"/></svg>${md} · quá hạn ${-diff} ngày</span>`;
  if (diff === 0) return `<span class="meta-chip due-today"><svg class="ic"><use href="#i-calendar-check"/></svg>Hôm nay</span>`;
  if (diff === 1) return `<span class="meta-chip due-upcoming"><svg class="ic"><use href="#i-calendar-blank"/></svg>Mai · ${md}</span>`;
  return `<span class="meta-chip due-upcoming"><svg class="ic"><use href="#i-calendar"/></svg>${md}</span>`;
}
function subtaskMeta(t) {
  const n = (t.subtasks || []).length;
  if (!n) return "";
  const done = t.subtasks.filter(s => s.done).length;
  const pct = Math.round((done / n) * 100);
  return `<span class="subtask-mini"><svg class="ic"><use href="#i-list-checks"/></svg>${done}/${n}<span class="mini-track"><span class="mini-fill" style="width:${pct}%"></span></span></span>`;
}
const REPEAT_LABELS = { Daily: "Hàng ngày", Weekdays: "T2–T6", Weekly: "Hàng tuần", Monthly: "Hàng tháng" };
const VI_DOW_SHORT = ["CN", "T2", "T3", "T4", "T5", "T6", "T7"]; // Date.getDay(): 0=CN
const VI_DOW_FULL = ["Chủ Nhật", "Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy"];

function splitISOLocal(iso) { const [y, m, d] = String(iso).slice(0, 10).split("-").map(Number); return { y, m, d }; }
function makeISOLocal(y, m0, d) { return `${y}-${String(m0 + 1).padStart(2, "0")}-${String(d).padStart(2, "0")}`; }
function addDaysLocalISO(iso, n) { const { y, m, d } = splitISOLocal(iso); const dt = new Date(y, m - 1, d + n); return makeISOLocal(dt.getFullYear(), dt.getMonth(), dt.getDate()); }
function lastDayOfMonth(y, m0) { return new Date(y, m0 + 1, 0).getDate(); }
function localISODate() { const n = new Date(); return makeISOLocal(n.getFullYear(), n.getMonth(), n.getDate()); }
function viDayMonth(iso) { const { y, m, d } = splitISOLocal(iso); return `${String(d).padStart(2, "0")}/${String(m).padStart(2, "0")}/${y}`; }
function viDowShort(iso) { const { y, m, d } = splitISOLocal(iso); return VI_DOW_SHORT[new Date(y, m - 1, d).getDay()]; }
function viFullDayMonth(iso) { const { y, m, d } = splitISOLocal(iso); return `${VI_DOW_FULL[new Date(y, m - 1, d).getDay()]}, ${viDayMonth(iso)}`; }

/* ─────────── lặp lại hạng nhất (v2.9.0) ─────────── */
const DOW_LETTERS = ["T2", "T3", "T4", "T5", "T6", "T7", "CN"]; // bit0..bit6 (Mon..Sun)
const WD_WEEKDAYS_MASK = 0b0011111;

function ruleDowLetters(mask) {
  const out = [];
  for (let b = 0; b < 7; b++) if (mask & (1 << b)) out.push(DOW_LETTERS[b]);
  return out;
}

/** Tóm tắt rule cho UI (hiển thị, không phải thuật toán). Trả {main, endTxt} hoặc null. */
function summarizeRule(rule, dueIso) {
  if (!rule) return null;
  const iv = Math.max(1, Math.min(99, Number(rule.interval) || 1));
  const unitName = f => ({ Day: "ngày", Week: "tuần", Month: "tháng", Year: "năm" }[f] || "ngày");
  const everyN = f => (iv === 1 ? `Mỗi ${unitName(f)}` : `Mỗi ${iv} ${unitName(f)}`);
  let main = everyN(rule.freq);
  if (rule.freq === "Day" && rule.by_day) {
    main = rule.by_day === WD_WEEKDAYS_MASK ? "Mỗi ngày trong tuần (T2–T6)" : `Mỗi ngày vào ${ruleDowLetters(rule.by_day).join(" & ")}`;
  } else if (rule.freq === "Week" && rule.by_day) {
    main += ` · ${ruleDowLetters(rule.by_day).join(" & ")}`;
  } else if (rule.freq === "Month") {
    if (rule.month_day === -1) main += " · ngày cuối tháng";
    else if (rule.month_day) main += ` · ngày ${rule.month_day}`;
  } else if (rule.freq === "Year") {
    const { m } = dueIso ? splitISOLocal(dueIso) : { m: 1 };
    if (rule.month_day === -1) main += ` · cuối tháng ${m}`;
    else if (rule.month_day) main += ` · ${rule.month_day}/${String(m).padStart(2, "0")}`;
  }
  const ends = rule.ends || { kind: "never" };
  let endTxt = "";
  if (ends.kind === "until" && ends.date) endTxt = `đến ${viDayMonth(ends.date)}`;
  else if (ends.kind === "after") {
    const left = Math.max(0, (ends.total || 0) - (ends.done || 0));
    endTxt = `${left}/${ends.total || 0} lần còn lại`;
  }
  return { main, endTxt };
}
function summarizeRuleLine(rule, dueIso) {
  const s = summarizeRule(rule, dueIso);
  if (!s) return "";
  return s.endTxt ? `${s.main} · ${s.endTxt}` : s.main;
}

function repeatMeta(t) {
  if (t.recurrence) {
    const line = summarizeRuleLine(t.recurrence, t.due);
    return `<span class="meta-chip repeat-chip"><svg class="ic"><use href="#i-repeat"/></svg>${esc(line)}</span>`;
  }
  if (!t.repeat || t.repeat === "None") return "";
  return `<span class="meta-chip repeat-chip"><svg class="ic"><use href="#i-repeat"/></svg>Lặp: ${REPEAT_LABELS[t.repeat] || t.repeat}</span>`;
}
function tagsMeta(t) {
  return (t.tags || []).slice(0, 4).map(g => `<span class="meta-tag">#${esc(g)}</span>`).join("");
}

/* ─────────── toast + lưu snapshot ─────────── */
let toastTimer = null;
let remindShown = false;
function toast(msg, kind, action) {
  /* action: hoặc { label, onClick } (nút), hoặc số (ms thời lượng) */
  let duration = null;
  if (typeof action === "number") { duration = action; action = null; }
  const el = $("#toast");
  el.textContent = "";
  const span = document.createElement("span");
  span.textContent = msg;
  el.appendChild(span);
  if (action && action.label) {
    const btn = document.createElement("button");
    btn.className = "toast-btn";
    btn.textContent = action.label;
    btn.addEventListener("click", () => { el.classList.remove("show"); try { action.onClick(); } catch (e) { console.error(e); } });
    el.appendChild(btn);
  }
  el.classList.toggle("err", kind === "err");
  el.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove("show"), duration ?? (action ? 6000 : 2600));
}

let lastTheme = null;
let themeAnimT = null;
function applyTheme(dark) {
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

/* ── màu: đổi HEX bất kỳ → bộ biến accent đồng bộ toàn app ── */
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const covOf = a => clamp((Number(a ?? 110) - 40) / 130, 0, 1); // 0 = trong suốt nhất, 1 = phủ kín nhất
const hexToRgb = hex => { const n = parseInt(String(hex).replace("#", ""), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; };
function rgbToHsl(r, g, b) {
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
function hslToHex(h, s, l) {
  s /= 100; l /= 100;
  const c = (1 - Math.abs(2 * l - 1)) * s, x = c * (1 - Math.abs(((h / 60) % 2) - 1)), m = l - c / 2;
  let r, g, b;
  if (h < 60) { r = c; g = x; b = 0; } else if (h < 120) { r = x; g = c; b = 0; } else if (h < 180) { r = 0; g = c; b = x; }
  else if (h < 240) { r = 0; g = x; b = c; } else if (h < 300) { r = x; g = 0; b = c; } else { r = c; g = 0; b = x; }
  const to = v => Math.round((v + m) * 255).toString(16).padStart(2, "0");
  return "#" + to(r) + to(g) + to(b);
}
function applyAccent(hex) {
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
  // nền aurora đi theo hue của màu nhấn (sáng + nền sâu)
  el.style.setProperty("--bg-h", String(Math.round(h)));
  el.style.setProperty("--bg-s", clamp(s, 35, 78).toFixed(1) + "%");
  el.style.setProperty("--bg-ds", clamp(s * 0.55, 22, 48).toFixed(1) + "%");
}

/* ─────────── thanh cuộn tự ẩn (g-scroll): hiện khi lăn chuột hoặc rê vào lề ─────────── */
const G_SCROLLS = () => [...document.querySelectorAll(".g-scroll")];
function markScrollOn(el) {
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
let edgeRaf = null;
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

/* trạng thái hiệu ứng Acrylic/Blur (chỉ hiển thị trong Cài đặt) */
let fxStatusTimer = null;
function refreshFxStatus() {
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
async function refreshOsTransparency() {
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
function openTransparencyDialog() {
  openModal(`<h2><svg class="ic accent-ic"><use href="#i-sun"/></svg>Cần bật Transparency effects</h2>
    <p>Để cửa sổ Taskora nhìn xuyên được, Windows cần công tắc <strong>Transparency effects</strong> (Settings → Personalization → Colors) được bật. Hiện nó đang tắt nên Acrylic không thể hiển thị.</p>
    <p style="margin-top:8px;color:var(--text-weak)">Taskora có thể bật giúp bạn ngay — chỉ ảnh hưởng tài khoản Windows hiện tại, tắt lại được bất cứ lúc nào (nút ngay trong Cài đặt → Giao diện).</p>
    <div class="modal-actions"><button class="btn-cancel" id="os-tr-decline">Không, dùng nền đặc</button><button class="btn-save" id="os-tr-enable">Bật ngay</button></div>`);
}

/* Hậu xử lý sau MỖI lần snapshot (kể cả từ IPC bất kỳ) */
function postSnap(snap) {
  S.snap = snap;
  const s = snap;
  if (s.flash) toast(s.flash, undefined, s.undo_len ? { label: "Hoàn tác", onClick: () => go(invoke("undo")) } : null);
  S.sort = s.settings.sort;
  S.hideDone = s.settings.hide_completed;
  applyTheme(s.settings.dark);
  applyAccent(s.settings.accent);
  document.documentElement.toggleAttribute("data-transparent", !!s.settings.transparent);
  document.documentElement.style.setProperty("--cov", covOf(s.settings.acrylic_alpha).toFixed(3));
  document.body.classList.toggle("reduce-motion", !!s.settings.reduce_motion);
  document.body.classList.toggle("perf", !!s.settings.perf_mode);
  document.body.classList.toggle("adhd", !!s.settings.adhd_mode);
  if (!s.settings.adhd_mode && F.active) focusStop();
  if (s.settings.adhd_mode) startAdhdClock(); else stopAdhdClock();
  setupAdhdPlaceholder();
  syncSettingsControls(s);
  refreshFxStatus();
  if (!osTransparencyVerified) {
    osTransparencyVerified = true;
    (async () => {
      try {
        const os = await invoke("transparency_status");
        if (os.supported && os.enabled === false && S.snap && S.snap.settings.transparent) {
          go(invoke("update_settings", { patch: { transparent: false } }));
          toast("Transparency effects đang TẮT — Taskora chuyển nền đặc. Bật lại trong Cài đặt → Giao diện để dùng trong suốt.");
        }
      } catch { /* không đọc được → giữ nguyên lựa chọn của người dùng */ }
    })();
  }
  // nhắc số việc hôm nay — chỉ một lần mỗi phiên mở app
  if (!remindShown && s.settings.remind_today && s.counts && s.counts.today > 0) {
    remindShown = true;
    setTimeout(() => toast(`Hôm nay bạn có ${s.counts.today} việc đến hạn`), 650);
  }
  // view mồ côi (danh sách đã bị xóa) → về Hộp thư
  if (S.view.type === "list" && !s.lists.some(l => l.id === S.view.id)) {
    S.view = { type: "inbox" };
  }
  // hiệu ứng thỏa mãn: pop checkbox / strike-through / star sau khi render lại
  if (S.pendingPop || S.pendingStar != null) {
    const pop = S.pendingPop, starId = S.pendingStar;
    S.pendingPop = null; S.pendingStar = null;
    requestAnimationFrame(() => {
      if (pop) {
        const row = document.querySelector(`.task-row[data-id="${pop.id}"]`);
        if (row) { row.classList.add(pop.kind === "done" ? "just-done" : "just-undone"); setTimeout(() => row.classList.remove("just-done", "just-undone"), 750); }
        if (pop.kind === "done" && S.snap && S.snap.settings.adhd_mode) {
          const tcheck = row ? row.querySelector(".tcheck") : null;
          const rect = tcheck ? tcheck.getBoundingClientRect() : null;
          confettiBurst(rect ? rect.left + 12 : window.innerWidth / 2, rect ? rect.top + 12 : window.innerHeight / 2);
          toast(pick(ADHD_PRAISE));
        }
      }
      if (starId != null) {
        const btn = document.querySelector(`.tstar[data-star="${starId}"]`);
        const row = btn && btn.closest(".task-row");
        if (row) { row.classList.add("just-starred"); setTimeout(() => row.classList.remove("just-starred"), 650); }
      }
    });
  }
  $("#sort-select").value = S.sort;
  $("#hide-done").checked = S.hideDone;
  $("#btn-undo").style.opacity = s.undo_len ? "1" : ".35";
  $("#btn-redo").style.opacity = s.redo_len ? "1" : ".35";
  renderSidebar();
  renderViewHead();
  renderCounts();
  renderTaskList();
  renderDetail();
  if (S.view.type === "stats") renderStats();
  // cửa sổ title cũng được backend cập nhật sẵn
}

async function refresh() {
  const snap = await invoke("snapshot");
  postSnap(snap);
}
async function go(promise) {
  try { postSnap(await promise); }
  catch (e) { toast(typeof e === "string" ? e : "Có lỗi xảy ra", "err"); }
}

/* ─────────── SIDEBAR ─────────── */
const LIST_DOT_FALLBACK = "#6366f1";
function renderSidebar() {
  const s = S.snap;
  const setCount = (id, n) => { const el = $(id); if (el) el.textContent = n; };
  setCount("#c-inbox", s.counts.inbox);
  setCount("#c-today", s.counts.today);
  setCount("#c-upcoming", s.counts.upcoming);
  setCount("#c-starred", s.counts.starred);
  setCount("#c-completed", s.counts.completed);
  setCount("#c-trash", s.counts.trash);
  // active row
  $$(".nav-item[data-view]").forEach(b => {
    const v = b.dataset.view;
    b.classList.toggle("active", S.view.type === v || (v === "stats" && S.view.type === "stats"));
  });
  // danh sách
  const lm = $("#list-nav");
  lm.innerHTML = s.lists.map(l => {
    const hit = (s.counts.by_list || []).find(([lid]) => lid === l.id);
    const n = hit ? hit[1] : 0;
    const active = S.view.type === "list" && S.view.id === l.id;
    const dot = `rgb(${l.color[0]},${l.color[1]},${l.color[2]})`;
    return `<div class="list-row${active ? " active" : ""}" data-list="${l.id}" role="button" tabindex="0">
      <span class="list-dot" style="background:${dot}; color:${dot}"></span>
      <span class="list-name">${esc(l.name)}</span>
      <span class="list-count">${n}</span>
      <span class="list-tools">
        <button class="icon-btn tiny list-edit" data-edit-list="${l.id}" title="Đổi tên / màu"><svg class="ic"><use href="#i-pencil-simple"/></svg></button>
        <button class="icon-btn tiny list-del" data-del-list="${l.id}" title="Xóa danh sách"><svg class="ic"><use href="#i-trash-simple"/></svg></button>
      </span>
    </div>`;
  }).join("");
  // thẻ Hôm nay
  const total = s.counts.today + s.counts.done_today;
  $("#today-num").textContent = `${s.counts.done_today}/${total}`;
  $("#today-bar").style.width = total ? `${Math.round((s.counts.done_today / total) * 100)}%` : "0%";
}

function renderCounts() {
  const c = S.snap.counts;
  $("#sb-active").textContent = `${c.active} đang làm`;
  $("#sb-overdue-wrap").hidden = c.overdue === 0;
  $("#sb-overdue").textContent = `${c.overdue} quá hạn`;
  const total = c.today + c.done_today;
  $("#sb-today").textContent = `${c.done_today}/${total} hôm nay`;
  $("#active-count").textContent = `${c.active} việc đang làm`;
}

function crumbFor(view) {
  if (view.type === "list") {
    const l = S.snap.lists.find(x => x.id === view.id);
    const title = l ? l.name : "Danh sách";
    const hit = (S.snap.counts.by_list || []).find(([lid]) => lid === view.id);
    return { icon: "folder", title, count: hit ? hit[1] : 0 };
  }
  const m = VIEW_META[view.type] || VIEW_META.inbox;
  const counts = S.snap.counts;
  const count = view.type === "inbox" ? counts.inbox : view.type === "today" ? counts.today : view.type === "upcoming" ? counts.upcoming : view.type === "starred" ? counts.starred : view.type === "completed" ? counts.completed : view.type === "trash" ? counts.trash : counts.active;
  return { icon: m.icon, title: m.title, count };
}

function renderViewHead() {
  const view = S.view;
  const isStats = view.type === "stats";
  const isSettings = view.type === "settings";
  const full = isStats || isSettings;
  $("#view-tasks").classList.toggle("active", !full);
  $("#view-stats").classList.toggle("active", isStats);
  $("#view-settings").classList.toggle("active", isSettings);
  if (isStats) { setCrumb("chart-bar", "Thống kê", S.snap.counts.active); return; }
  if (isSettings) { setCrumb("gear", "Cài đặt", ""); refreshStoragePanel(); return; }
  const meta = crumbFor(view);
  $("#crumb-use").setAttribute("href", "#i-" + meta.icon);
  $("#crumb-text").textContent = meta.title;
  $("#crumb-count").textContent = meta.count;
  $("#page-icon-use").setAttribute("href", "#i-" + meta.icon);
  $("#page-title").textContent = meta.title;
  if (view.type === "list") {
    $("#page-sub").textContent = "Danh sách tùy chỉnh";
  } else {
    $("#page-sub").textContent = (VIEW_META[view.type] || VIEW_META.inbox).sub;
  }
  // banner quá hạn chỉ ở Today/Inbox/Upcoming/Starred/List
  const showBanner = ["inbox", "today", "upcoming", "starred", "list"].includes(view.type) && S.snap.counts.overdue > 0;
  $("#overdue-banner").hidden = !showBanner;
  if (showBanner) {
    if (s_isAdhd()) $("#overdue-text").textContent = `Chưa kịp lần này — ${S.snap.counts.overdue} việc chờ tới lúc bạn sẵn sàng`;
    else $("#overdue-text").textContent = `${S.snap.counts.overdue} việc quá hạn`;
  }
  // quick add chỉ cho phép ở các view có ý nghĩa
  const allowQuick = !["completed", "trash", "stats", "settings"].includes(view.type);
  $("#quickadd").style.display = allowQuick ? "" : "none";
  // bulk ẩn khi rời khỏi view
  $("#bulkbar").hidden = !S.bulk;
}

function syncSettingsControls(s) {
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
  $("#set-remind-today").checked = !!st.remind_today;
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
  $$("#set-chime button").forEach(b => b.classList.toggle("on", (st.chime || "soft") === b.dataset.chime));
}

function syncMinuteChips(group, val) {
  $$(`.minute-chip[data-group="${group}"]`).forEach(b => b.classList.toggle("on", Number(b.dataset.value) === Number(val)));
}

/* ─────────── NƠI LƯU DỮ LIỆU ─────────── */
let storageInfo = null;

async function refreshStoragePanel() {
  try { storageInfo = await invoke("storage_info"); } catch { return; }
  renderStoragePanel(storageInfo);
}
function renderStoragePanel(info) {
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
const pickFolder = async () => {
  try {
    const sel = await window.__TAURI__?.dialog?.open?.({ directory: true, multiple: false, title: "Chọn thư mục lưu dữ liệu" });
    return typeof sel === "string" ? sel : null;
  } catch { return null; }
};
function openStorageConfirm(choice, customPath) {
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
function openStorageCustomModal() {
  openModal(`<h2><svg class="ic accent-ic"><use href="#i-folder"/></svg>Đổi thư mục lưu</h2>
    <p>Nhập đường dẫn thư mục — Taskora sẽ tự tạo nếu chưa tồn tại.</p>
    <input class="modal-input" id="storage-custom-input" type="text" spellcheck="false" placeholder="D:\\TaskoraData" autocomplete="off" />
    <div class="modal-actions"><button class="btn-cancel" data-close-modal="1">Hủy</button>
      <button class="btn-ghost" id="storage-custom-browse"><svg class="ic small"><use href="#i-folder"/></svg>Duyệt…</button>
      <button class="btn-save" id="storage-custom-next">Tiếp tục</button></div>`);
  setTimeout(() => $("#storage-custom-input")?.focus(), 60);
}
async function runStorageSwitch(migrate) {
  const p = S.storagePending; if (!p) return;
  closeModal();
  try {
    const res = await invoke("storage_switch", { req: { choice: p.choice, custom_path: p.custom_path, migrate } });
    postSnap(res.snapshot);
    renderStoragePanel(res.info);
  } catch (err) {
    toast(typeof err === "string" ? err : "Không đổi được nơi lưu", "err");
    refreshStoragePanel();
  }
}
async function runStorageMergeLegacy() {
  closeModal();
  try {
    const res = await invoke("storage_merge_legacy");
    postSnap(res.snapshot);
    renderStoragePanel(res.info);
  } catch (err) { toast(typeof err === "string" ? err : "Gộp thất bại", "err"); }
}
async function runStorageImportOrphan() {
  closeModal();
  try {
    const res = await invoke("storage_import_orphan");
    postSnap(res.snapshot);
    renderStoragePanel(res.info);
  } catch (err) { toast(typeof err === "string" ? err : "Chuyển thất bại", "err"); }
}
async function checkStoragePrompts() {
  if (S._storagePromptDone) return;
  S._storagePromptDone = true;
  let info;
  try { info = await invoke("storage_startup"); } catch { return; }
  renderStoragePanel(info);
  if (info.moved) toast("Taskora đã được di chuyển — dữ liệu vẫn đi theo file thực thi");
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

function setCrumb(icon, title, count) {
  $("#crumb-use").setAttribute("href", "#i-" + icon);
  $("#crumb-text").textContent = title;
  const pill = $("#crumb-count");
  pill.textContent = count;
  pill.hidden = count === "" || count == null;
}

function viewKey(v) { return v.type === "list" ? `list:${v.id}` : v.type; }
function parseViewKey(k) {
  if (!k) return null;
  if (k.startsWith("list:")) { const id = Number(k.slice(5)); return Number.isFinite(id) ? { type: "list", id } : null; }
  return ["inbox", "today", "upcoming", "starred", "completed", "trash", "stats", "settings"].includes(k) ? { type: k } : null;
}

function setView(view) {
  S.view = view;
  invoke("set_last_view", { view: viewKey(view) }).catch(() => {});
  S.selected = null;
  S.tag = null;
  S.prio = null;
  S.bulk = false;
  S.bulkSel.clear();
  $("#search-input").value = "";
  S.search = "";
  $("#search-clear").style.display = "none";
  renderViewHead();
  renderSidebar();
  renderTaskList();
  renderDetail();
  if (view.type === "stats") renderStats(true);
  closePalette();
}

/* ─────────── TASK LIST ─────────── */
function agendaHtml(tasks, q) {
  // gom theo hạn chót; view Sắp tới luôn có hạn nên an toàn.
  // trong ngày giữ nguyên thứ tự từ visible_ids (tức là sort đang chọn).
  const byDay = new Map();
  for (const t of tasks) {
    const key = (t.due || "9999").slice(0, 10);
    if (!byDay.has(key)) byDay.set(key, []);
    byDay.get(key).push(t);
  }
  const days = [...byDay.keys()].sort();
  const tomorrow = addDaysLocalISO(localISODate(), 1);
  let out = "";
  for (const key of days) {
    const group = byDay.get(key);
    const label = key === tomorrow ? `Ngày mai · ${viDayMonth(key)}` : `${viDowShort(key)} · ${viDayMonth(key)}`;
    out += `<div class="agenda-day"><span class="agenda-day-label">${esc(label)}</span><span class="agenda-day-count">${group.length} việc</span></div>`;
    out += group.map(t => rowHtml(t, q, { draggable: false })).join("");
  }
  return out;
}

async function renderTaskList() {
  if (!S.snap) return;
  const listEl = $("#tasklist");
  if (S.view.type === "stats" || S.view.type === "settings") { listEl.innerHTML = ""; $("#empty-state").hidden = true; const note = $("#agenda-note"); if (note) note.hidden = true; S.visibleIds = []; renderNextUp(); return; }
  const q = S.search.trim();
  S.visibleIds = await invoke("visible_ids", {
    view: viewWire(S.view), search: S.search, tag: S.tag, prio: S.prio,
    sort: S.sort, hideCompleted: S.hideDone,
  });
  const visibleTasks = S.visibleIds.map(id => taskById(id)).filter(Boolean);
  const isAgenda = S.view.type === "upcoming";
  listEl.innerHTML = isAgenda ? agendaHtml(visibleTasks, q) : visibleTasks.map(t => rowHtml(t, q)).join("");
  // dòng chú thích cho view có việc lặp lại
  const note = $("#agenda-note");
  if (note) {
    const hasRepeat = visibleTasks.some(t => t.repeat && t.repeat !== "None");
    note.hidden = !((S.view.type === "today" || S.view.type === "upcoming") && hasRepeat);
  }
  const empty = S.visibleIds.length === 0;
  $("#empty-state").hidden = !empty;
  if (empty) {
    const actionable = ["inbox", "today", "upcoming", "starred", "list"].includes(S.view.type);
    const meta = (s_isAdhd() && actionable) ? ["Xong hết rồi ✦", "Nghỉ thật sự — không còn gì chờ bạn"] : S.view.type === "list" ? { title: "Danh sách trống", sub: "Thêm việc nhanh ở ô phía trên" } : {
      inbox: ["Hộp thư trống", "Thêm việc đầu tiên bằng ô phía trên (Ctrl+N)"],
      today: ["Không có việc nào hôm nay", "Việc quá hạn cũng sẽ hiển thị ở đây"],
      upcoming: ["Chưa có việc sắp tới", "Đặt hạn chót để xuất hiện trong view này"],
      starred: ["Chưa ghim việc nào", "Bấm ngôi sao ở panel chi tiết để ghim"],
      completed: ["Chưa có việc hoàn thành", "Hoàn thành việc để xem tại đây"],
      trash: ["Thùng rác trống", "Việc đã xóa sẽ nằm ở đây trước khi xóa vĩnh viễn"],
    }[S.view.type] || ["Trống", ""];
    $("#empty-title").textContent = Array.isArray(meta) ? meta[0] : meta.title;
    $("#empty-sub").textContent = Array.isArray(meta) ? meta[1] : meta.sub;
  }
  // khôi phục trạng thái chọn
  if (S.selected != null) {
    $(`.task-row[data-id="${S.selected}"]`)?.classList.add("selected");
  }
  renderNextUp();
  updateBulkUI();
}

function rowHtml(t, q, opts = {}) {
  if (!t) return "";
  const draggable = opts.draggable != null ? opts.draggable : S.sort === "Manual";
  const done = isCompleted(t);
  const pr = t.priority || "P4";
  const star = `<button class="tstar${t.starred ? " on" : ""}" data-star="${t.id}" title="${t.starred ? "Bỏ ghim" : "Ghim việc"}"><svg class="ic"><use href="#i-star${t.starred ? "-fill" : ""}"/></svg></button>`;
  const bulkBox = S.bulk ? `<span class="tcheck bulk-box${S.bulkSel.has(t.id) ? " bulk-on" : ""}" data-bulkbox="${t.id}"><svg class="ic tiny"><use href="#i-check"/></svg></span>` : "";
  const prioCls = pr === "P1" ? "prio-1" : pr === "P2" ? "prio-2" : pr === "P3" ? "prio-3" : "prio-4";
  const restore = isDeleted(t)
    ? `<button class="icon-btn" data-restore="${t.id}" title="Khôi phục"><svg class="ic"><use href="#i-arrow-counter-clockwise"/></svg></button>`
    : "";
  return `<div class="task-row ${prioCls}${done ? " done" : ""}${S.bulk && S.bulkSel.has(t.id) ? " bulk-sel" : ""}" data-id="${t.id}" draggable="${draggable}">
    ${S.bulk ? bulkBox : `<button class="tcheck" data-toggle="${t.id}" title="Bật/tắt hoàn thành (Space)"><svg class="ic tiny"><use href="#i-check"/></svg></button>`}
    <div class="tmain">
      <div class="tline"><span class="ttitle">${hi(t.title, q)}</span>${star}</div>
      <div class="tmeta">${dueChip(t)}${repeatMeta(t)}${subtaskMeta(t)}${tagsMeta(t)}</div>
    </div>
    <div class="tactions">${restore}
      <button class="icon-btn" data-duplicate="${t.id}" title="Nhân bản"><svg class="ic"><use href="#i-copy"/></svg></button>
      <button class="icon-btn" data-delete="${t.id}" title="${isDeleted(t) ? "Xóa vĩnh viễn" : "Xóa"}"><svg class="ic"><use href="#i-trash"/></svg></button>
    </div>
  </div>`;
}

function updateBulkUI() {
  const bulk = S.bulk;
  $("#toolbar").style.display = bulk ? "none" : "";
  $("#bulkbar").hidden = !bulk;
  $("#bulk-count").textContent = `${S.bulkSel.size} đã chọn`;
  $$(".bulk-box").forEach(el => el.classList.toggle("bulk-on", S.bulkSel.has(Number(el.dataset.bulkbox))));
  $$(".task-row[data-id]").forEach(el => el.classList.toggle("bulk-sel", bulk && S.bulkSel.has(Number(el.dataset.id))));
}

function selectTask(id, { openDetail = true } = {}) {
  S.selected = id;
  $$(".task-row[data-id]").forEach(el => el.classList.toggle("selected", Number(el.dataset.id) === id));
  if (openDetail) $("#detail").classList.add("open");
  renderDetail();
}

/* ─────────── DETAIL PANEL ─────────── */
function renderDetail() {
  const ss = $("#d-split-suggest"); if (ss) ss.hidden = true;
  const panel = $("#detail");
  const t = S.selected != null ? taskById(S.selected) : null;
  if (!t) { panel.classList.remove("open"); return; }
  panel.classList.add("open");
  const activeEl = document.activeElement;
  const setVal = (sel, v) => { const el = $(sel); if (el && el !== activeEl && el.value !== v) el.value = v; };
  setVal("#d-title", t.title);
  setVal("#d-notes", t.notes || "");
  // hoàn thành
  const done = isCompleted(t);
  $("#d-complete").classList.toggle("done", done);
  $("#d-complete-text").textContent = done ? "Đã hoàn thành" : "Đánh dấu hoàn thành";
  // ghim
  $("#d-star").classList.toggle("on", !!t.starred);
  $("#d-star-use").setAttribute("href", t.starred ? "#i-star-fill" : "#i-star");
  $("#d-star-text").textContent = t.starred ? "Đã ghim" : "Ghim việc";
  // lặp lại — panel tóm tắt (v2.9.0)
  const rule = t.recurrence || null;
  const flag = $("#d-repeat-flag");
  const sumEl = $("#d-recur-title");
  const subEl = $("#d-recur-sub");
  const actionsEl = $("#d-recur-actions");
  const repHint = $("#d-repeat-hint");
  if (rule) {
    const { main, endTxt } = summarizeRule(rule, t.due);
    sumEl.textContent = `↻ ${main}`;
    subEl.textContent = endTxt || "";
    subEl.hidden = !endTxt;
    flag.hidden = false;
    $("#d-repeat-flag-text").textContent = `Lặp: ${main}`;
    flag.title = "Bấm để chỉnh lặp lại\nHoàn thành xong sẽ tự tạo lần tiếp theo (Ctrl+Z hủy cả hoàn thành lẫn lần vừa tạo)";
    actionsEl.hidden = false;
    repHint.innerHTML = `Hoàn thành xong → lần tiếp theo: <b>…</b>`;
    repHint.hidden = false;
    const myId = t.id;
    const fromIso = t.due || localISODate();
    invoke("next_occurrence", { rule, from: fromIso }).then(iso => {
      if (S.selected !== myId) return; // đã chọn việc khác
      const hint = $("#d-repeat-hint");
      const skipBtn = $("#d-recur-skip");
      if (!hint) return;
      if (iso) {
        hint.innerHTML = `Hoàn thành xong → lần tiếp theo: <b>${esc(viFullDayMonth(iso))}</b> <span class="hint-dim">(Ctrl+Z hủy cả hoàn thành lẫn lần vừa tạo)</span>`;
        if (skipBtn) { skipBtn.disabled = false; skipBtn.title = "Bỏ qua lần sắp tới, giữ chuỗi (Ctrl+Z hoàn tác được)"; }
      } else {
        hint.innerHTML = `<span class="hint-dim">Chuỗi lặp đã kết thúc — việc này sẽ không sinh thêm lần nào</span>`;
        if (skipBtn) { skipBtn.disabled = true; skipBtn.title = "Sắp hết lặp — không còn lần nào để bỏ qua"; }
      }
    }).catch(() => { const hint = $("#d-repeat-hint"); if (hint) hint.hidden = true; });
  } else {
    sumEl.textContent = "Không lặp";
    subEl.hidden = true;
    actionsEl.hidden = true;
    repHint.hidden = true;
    flag.hidden = true;
  }
  // hạn chót
  const dueTxt = $("#d-due-text");
  if (t.due) {
    const d = new Date(parseYmd(t.due.slice(0, 10)) + 12 * 3600 * 1000);
    dueTxt.textContent = fmtViDate(d);
    dueTxt.style.color = dueDiffDays(t.due) < 0 ? "#fca5a5" : dueDiffDays(t.due) === 0 ? "#fcd34d" : "";
    $("#d-due-input").value = t.due.slice(0, 10);
    $("#d-due-clear").hidden = false;
  } else {
    dueTxt.textContent = "Chưa đặt";
    dueTxt.style.color = "";
    $("#d-due-input").value = "";
    $("#d-due-clear").hidden = true;
  }
  // ưu tiên
  $$("#d-prio .prio-chip").forEach(b => b.classList.toggle("on", (t.priority || "P4") === b.dataset.prio));
  // danh sách
  const sel = $("#d-list");
  if (sel.dataset.built !== "1" || sel.dataset.sel !== String(t.list_id)) {
    sel.innerHTML = `<option value="">Hộp thư (không danh sách)</option>` +
      S.snap.lists.map(l => `<option value="${l.id}"${t.list_id === l.id ? " selected" : ""}>${esc(l.name)}</option>`).join("");
    sel.dataset.built = "1";
    sel.dataset.sel = String(t.list_id);
  }
  sel.value = t.list_id == null ? "" : String(t.list_id);
  // thẻ
  $("#d-tags").innerHTML = (t.tags || []).map(g =>
    `<span class="d-tag">#${esc(g)}<button data-untag="${esc(g)}" title="Bỏ thẻ"><svg class="ic tiny"><use href="#i-x"/></svg></button></span>`
  ).join("");
  // việc nhỏ
  const subs = t.subtasks || [];
  const doneN = subs.filter(s => s.done).length;
  $("#d-sub-progress").textContent = `${doneN}/${subs.length}`;
  $("#d-sub-bar").style.width = subs.length ? `${(doneN / subs.length) * 100}%` : "0%";
  $("#d-subtasks").innerHTML = subs.map(s => `<div class="subtask-row${s.done ? " done" : ""}" data-sid="${s.id}">
      <button class="st-check${s.done ? " on" : ""}" data-st-toggle="${s.id}" title="Bật/tắt"><svg class="ic tiny"><use href="#i-check"/></svg></button>
      <input type="text" value="${esc(s.title)}" placeholder="Việc nhỏ…" data-st-title="${s.id}" autocomplete="off" spellcheck="false" />
      <button class="icon-btn tiny" data-st-del="${s.id}" title="Xóa việc nhỏ"><svg class="ic tiny"><use href="#i-x"/></svg></button>
    </div>`).join("");
  // mốc thời gian
  const created = new Date(t.created_at);
  $("#d-created").textContent = `Tạo lúc ${fmtViTime(created)}`;
  const ca = t.completed_at ? new Date(t.completed_at) : null;
  $("#d-completed-at").hidden = !ca;
  if (ca) $("#d-completed-at").textContent = `Hoàn thành ${fmtViTime(ca)}`;
  // hành động
  const del = $("#d-delete");
  del.querySelector("#d-delete-text").textContent = isDeleted(t) ? "Xóa vĩnh viễn" : "Xóa";
  $("#d-duplicate").hidden = isDeleted(t);
  $("#d-restore").hidden = !isDeleted(t);
}

/* ─────────── STATS VIEW ─────────── */
async function renderStats(force) {
  try {
    const st = await invoke("stats");
    $("#st-active").textContent = st.active;
    $("#st-done-today").textContent = st.done_today;
    $("#st-overdue").textContent = st.overdue;
    $("#st-streak").textContent = st.streak;
    const sft = $("#st-focus-today"); if (sft) sft.textContent = st.focus_today ?? 0;
    const sfw = $("#st-focus-week"); if (sfw) sfw.textContent = st.focus_week ?? 0;
    $("#stat-rate").textContent = Math.round(st.rate * 100) + "%";
    $("#stat-done-total").textContent = `${st.done_all}/${st.total_all} việc đã xong`;
    // thanh tiến độ hero (animate qua rAF)
    requestAnimationFrame(() => { $("#stat-rate-bar").style.width = (st.rate * 100).toFixed(1) + "%"; });
    // biểu đồ 14 ngày
    const max = Math.max(1, ...st.series.map(p => p.n));
    $("#chart-14").innerHTML = st.series.map((p, idx) => `<div class="chart-col${idx === st.series.length - 1 ? " today" : ""}" title="${esc(p.label)}: ${p.n} việc">
        <span class="chart-n">${p.n || ""}</span>
        <div class="chart-bar" style="height:${Math.max(2, (p.n / max) * 100)}%; animation-delay:${idx * 34}ms"></div>
        <span class="chart-day">${esc(p.label.slice(0, 5))}</span>
      </div>`).join("");
    // theo danh sách
    const listsEl = $("#stat-lists");
    listsEl.innerHTML = st.lists.length ? st.lists.map(l => {
      const pct = l.total ? Math.round((l.done / l.total) * 100) : 0;
      const dot = `rgb(${l.color[0]},${l.color[1]},${l.color[2]})`;
      return `<div class="stat-list-row"><span class="stat-list-name"><span class="list-dot" style="background:${dot}"></span>${esc(l.name)}</span>
        <div class="progress-track"><div class="progress-fill" style="width:${pct}%"></div></div>
        <span class="stat-list-nums">${l.done}/${l.total}</span></div>`;
    }).join("") : `<p class="empty-inline">Chưa có danh sách nào</p>`;
    // theo thẻ
    $("#stat-tags").innerHTML = st.tags.length ? st.tags.map(tg =>
      `<span class="stat-tag">#${esc(tg.tag)}<b>${tg.count}</b></span>`).join("")
      : `<p class="empty-inline">Chưa gắn thẻ nào</p>`;
  } catch (e) {
    toast("Không tải được thống kê", "err");
  }
}

/* ─────────── QUICK ADD + PREVIEW ─────────── */
function updateQaPreview() {
  const v = $("#quickadd-input").value.trim();
  $("#qa-examples").hidden = v.length > 0;
  const prev = $("#qa-preview");
  if (S.snap && S.snap.settings && !S.snap.settings.qa_preview) { prev.hidden = true; prev.innerHTML = ""; return; }
  if (!v) { prev.hidden = true; prev.innerHTML = ""; return; }
  // phân tích xem trước (debounce nhẹ qua rAF-style)
  invoke("preview_parse", { input: v }).then(p => {
    if (($("#quickadd-input").value.trim()) !== v) return; // đã gõ tiếp, bỏ qua kết quả cũ
    const chips = [];
    if (p.due) chips.push(`<span class="qa-prev-chip due"><svg class="ic small"><use href="#i-calendar"/></svg>${esc(p.due)}</span>`);
    if (p.priority) chips.push(`<span class="qa-prev-chip prio"><svg class="ic small"><use href="#i-flag-banner"/></svg>${esc(p.priority)}</span>`);
    if (p.recurrence) chips.push(`<span class="qa-prev-chip rep"><svg class="ic small"><use href="#i-repeat"/></svg>${esc(summarizeRuleLine(p.recurrence))}</span>`);
    else if (p.repeat) chips.push(`<span class="qa-prev-chip rep"><svg class="ic small"><use href="#i-repeat"/></svg>${esc(REPEAT_LABELS[p.repeat] || p.repeat)}</span>`);
    for (const t of p.tags.slice(0, 4)) chips.push(`<span class="qa-prev-chip"><svg class="ic small"><use href="#i-hash"/></svg>${esc(t)}</span>`);
    prev.innerHTML = chips.join("") + (p.title ? `<span class="qa-title-preview">“${esc(p.title)}”</span>` : "");
    prev.hidden = chips.length === 0 && !p.title;
  }).catch(() => { prev.hidden = true; });
}

async function submitQuick() {
  const input = $("#quickadd-input");
  const v = input.value.trim();
  if (!v) return;
  try {
    const snap = await invoke("quick_add", { input: v, view: viewWire(S.view) });
    input.value = "";
    updateQaPreview();
    postSnap(snap);
    if (snap.last_added) {
      S.selected = snap.last_added;
      $$(".task-row[data-id]").forEach(el => el.classList.toggle("selected", Number(el.dataset.id) === snap.last_added));
    }
    input.focus();
  } catch (e) {
    toast(typeof e === "string" ? e : "Không thêm được việc", "err");
  }
}

/* ─────────── CONTEXT MENU ─────────── */
let ctxFor = null;
function closeCtxMenu() { $("#ctx-menu").hidden = true; ctxFor = null; }
function openCtxMenu(html, x, y) {
  const menu = $("#ctx-menu");
  menu.innerHTML = html;
  menu.hidden = false;
  const rect = menu.getBoundingClientRect();
  menu.style.left = Math.min(x, window.innerWidth - rect.width - 10) + "px";
  menu.style.top = Math.min(y, window.innerHeight - rect.height - 10) + "px";
}
function taskCtxItems(t) {
  const items = [];
  items.push(`<button class="ctx-item" data-ctx="toggle"><svg class="ic"><use href="#i-check-circle"/></svg>${isCompleted(t) ? "Bỏ hoàn thành" : "Đánh dấu hoàn thành"}</button>`);
  items.push(`<button class="ctx-item" data-ctx="star"><svg class="ic"><use href="#i-star"/></svg>${t.starred ? "Bỏ ghim" : "Ghim việc"}</button>`);
  const others = S.snap.lists.filter(l => l.id !== t.list_id).slice(0, 6);
  if (others.length) {
    items.push(`<div class="ctx-label">Chuyển sang</div>`);
    for (const l of others) {
      const dot = `rgb(${l.color[0]},${l.color[1]},${l.color[2]})`;
      items.push(`<button class="ctx-item" data-ctx-move="${l.id}"><span class="list-dot" style="background:${dot}"></span>${esc(l.name)}</button>`);
    }
    if (t.list_id != null) items.push(`<button class="ctx-item" data-ctx-move="inbox"><svg class="ic"><use href="#i-tray"/></svg>Hộp thư</button>`);
  }
  items.push(`<div class="ctx-sep"></div>`);
  items.push(`<button class="ctx-item" data-ctx="duplicate"><svg class="ic"><use href="#i-copy"/></svg>Nhân bản</button>`);
  if (isDeleted(t)) {
    items.push(`<button class="ctx-item" data-ctx="restore"><svg class="ic"><use href="#i-arrow-counter-clockwise"/></svg>Khôi phục</button>`);
    items.push(`<button class="ctx-item danger" data-ctx="delete"><svg class="ic"><use href="#i-trash"/></svg>Xóa vĩnh viễn</button>`);
  } else {
    items.push(`<button class="ctx-item danger" data-ctx="delete"><svg class="ic"><use href="#i-trash"/></svg>Chuyển vào thùng rác</button>`);
  }
  return items.join("");
}

/* ─────────── MODALS ─────────── */
function openModal(html) {
  const m = $("#modal");
  m.innerHTML = `<div class="modal-backdrop" data-close-modal="1"></div><div class="modal-panel">${html}</div>`;
  // lớp phủ nền mờ phía sau (giữ .overlay flex center)
  m.hidden = false;
}
function closeModal() { const m = $("#modal"); m.hidden = true; m.innerHTML = ""; }

function openListDialog(editing) {
  const list = editing != null ? S.snap.lists.find(l => l.id === editing) : null;
  const title = list ? "Đổi tên danh sách" : "Danh sách mới";
  openModal(`<h2><svg class="ic accent-ic"><use href="#i-folder"/></svg>${title}</h2>
    <input class="modal-input" id="list-name" type="text" maxlength="48" placeholder="Tên danh sách…" value="${list ? esc(list.name) : ""}" autocomplete="off" spellcheck="false" />
    <div class="swatches" id="list-swatches">
      ${LIST_PALETTE_JS.map((rgb, i) => `<button class="swatch${(list ? list.color[0] : 99) === rgb[0] && (list ? list.color[1] : 102) === rgb[1] ? " on" : ""}" data-swatch="${i}" style="background:rgb(${rgb[0]},${rgb[1]},${rgb[2]})" title="Màu ${i + 1}"></button>`).join("")}
    </div>
    <div class="modal-actions">
      <button class="btn-cancel" data-close-modal="1">Hủy</button>
      <button class="btn-save" id="list-save">${list ? "Lưu" : "Tạo danh sách"}</button>
    </div>`);
  const input = $("#list-name");
  input.focus(); input.select();
  S.modalList = { editing: editing ?? null, colorIdx: list ? LIST_PALETTE_JS.findIndex(c => c[0] === list.color[0] && c[1] === list.color[1]) : 0 };
  $$("#list-swatches .swatch").forEach(sw => sw.addEventListener("click", () => {
    $$("#list-swatches .swatch").forEach(x => x.classList.remove("on"));
    sw.classList.add("on");
    S.modalList.colorIdx = Number(sw.dataset.swatch);
  }));
}
const LIST_PALETTE_JS = [[99,102,241],[16,185,129],[245,158,11],[239,68,68],[14,165,233],[168,85,247],[236,72,153],[107,114,128]];

async function openBackups() {
  const list = await invoke("list_backups");
  const rows = list.length ? list.map(b => `<div class="backup-row">
      <svg class="ic accent-ic"><use href="#i-archive"/></svg>
      <div style="min-width:0"><div class="b-name">${esc(b.name)}</div><div class="b-meta">${esc(b.modified)} · ${Math.ceil(b.size / 1024)} KB</div></div>
      <button class="chip-btn ok" data-restore-backup="${esc(b.name)}">Khôi phục</button>
    </div>`).join("") : `<p>Chưa có bản sao lưu nào. Bấm “Xuất bản sao lưu” để tạo.</p>`;
  openModal(`<h2><svg class="ic accent-ic"><use href="#i-archive"/></svg>Bản sao lưu</h2>
    <div class="modal-actions" style="justify-content:flex-start"><button class="btn-save" id="do-export"><svg class="ic small"><use href="#i-archive"/></svg>&nbsp;Xuất bản sao lưu ngay</button></div>
    <div class="backup-list g-scroll">${rows}</div>
    <div class="modal-actions"><button class="btn-cancel" data-close-modal="1">Đóng</button></div>`);
}
function openConfirmEmptyTrash() {
  const n = S.snap.counts.trash;
  if (n === 0) { toast("Thùng rác đã trống"); return; }
  openModal(`<h2><svg class="ic danger"><use href="#i-warning"/></svg>Xóa vĩnh viễn ${n} việc?</h2>
    <p>Toàn bộ việc trong thùng rác sẽ bị xóa vĩnh viễn, không thể hoàn tác bằng Ctrl+Z sau khi xác nhận.</p>
    <div class="modal-actions"><button class="btn-cancel" data-close-modal="1">Hủy</button><button class="btn-danger" id="confirm-empty-trash">Xóa vĩnh viễn</button></div>`);
}
function openHelp() {
  const rows = [
    ["Ctrl + N", "Thêm việc mới (focus ô thêm nhanh)"],
    ["Ctrl + K / Ctrl + F", "Tìm kiếm · bảng lệnh nhanh"],
    ["Ctrl + Z / Ctrl + Y", "Hoàn tác / Làm lại"],
    ["Ctrl + D", "Bật/tắt giao diện tối–sáng"],
    ["Ctrl + S", "Lưu ngay"],
    ["Space", "Bật/tắt hoàn thành việc đang chọn"],
    ["↑ ↓", "Di chuyển chọn việc"],
    ["Alt + ↑ ↓", "Đổi thứ tự việc (Thủ công)"],
    ["Delete", "Xóa việc đang chọn"],
    ["Ctrl + 1…7", "Hộp thư · Hôm nay · Sắp tới · Ghim · Hoàn thành · Thùng rác · Thống kê"],
    ["Ctrl + 8", "Cài đặt"],
    ["Esc", "Đóng bảng / bỏ chọn / bỏ bộ lọc"],
    ["Space (phiên ADHD)", "Tạm dừng / tiếp tục phiên tập trung"],
    ["R (phiên ADHD)", "Bắt đầu lại đồng hồ"],
  ];
  openModal(`<h2><svg class="ic accent-ic"><use href="#i-keyboard"/></svg>Phím tắt & mẹo</h2>
    <div class="shortcut-list g-scroll">${rows.map(([k, d]) => `<div class="shortcut-row"><kbd class="modal-kbd">${k}</kbd><span class="b-meta" style="font-size:12px">${d}</span></div>`).join("")}</div>
    <div class="help-tip"><div class="help-tip-title"><svg class="ic small"><use href="#i-repeat"/></svg>Việc lặp lại</div>
      <p>Gõ <kbd class="modal-kbd">*hàng ngày</kbd> hoặc <kbd class="modal-kbd">*hàng tuần</kbd> khi thêm nhanh (cũng hiểu <em>*daily / *weekly</em>, <em>*hàng tháng</em>). Muốn <strong>khoảng lặp tùy ý</strong>: <kbd class="modal-kbd">*mỗi 3 ngày</kbd> · <kbd class="modal-kbd">*mỗi 2 tuần</kbd> · <kbd class="modal-kbd">*mỗi 6 tháng</kbd> · <kbd class="modal-kbd">*mỗi 2 năm</kbd> (thiếu số = 1). Nhấn <strong>Chỉnh…</strong> trong Chi tiết để đặt thứ trong tuần, ngày trong tháng, kết thúc (đến ngày / sau N lần) và xem trước lịch lặp. Việc lặp chỉ hiện <strong>một lần</strong> — hoàn thành xong sẽ tự tạo lần tiếp theo vào đúng ngày.</p>
      <p>Đổi tần suất / dừng hẳn: panel chi tiết việc → ô <strong>Lặp lại</strong> → chọn tần suất khác hoặc <strong>“Không lặp”</strong>. Ctrl+Z hủy cả hoàn thành lẫn lần vừa tạo.</p>
      <p>View <strong>Sắp tới</strong> gom việc theo từng ngày (agenda) — việc quá hạn nằm ở <strong>Hôm nay</strong>.</p>
      <p>Dọn các lần lặp cũ đã hoàn thành: tab <strong>Đã hoàn thành</strong> → nút <strong>Chọn</strong> → tick các dòng → <strong>Xóa</strong>.</p>
    </div>
    <div class="modal-actions"><button class="btn-save" data-close-modal="1">Xong</button></div>`);
}
function openAbout() {
  openModal(`<div class="about-center"><img class="about-logo" src="assets/logo.png" alt="Taskora" />
      <h2 style="justify-content:center">Taskora <span style="color:var(--text-faint);font-weight:500">v2.10.0</span></h2>
      <p>Quản lý công việc cho Windows — nhẹ, nhanh, đẹp.<br>Viết bằng Rust + Tauri, giao diện liquid glass.</p>
      <p>Font <strong>Be Vietnam Pro</strong> (OFL) · Icon <strong>Phosphor</strong> (MIT)</p>
      <p style="color:var(--text-faint)">MIT License © Hthancder</p>
    </div>
    <div class="modal-actions"><button class="btn-save" data-close-modal="1">Đóng</button></div>`);
}

/* ─────────── COMMAND PALETTE ─────────── */
const PALETTE_ACTIONS = [
  { icon: "tray", label: "Đi tới: Hộp thư", hint: "Ctrl+1", run: () => setView({ type: "inbox" }) },
  { icon: "calendar-check", label: "Đi tới: Hôm nay", hint: "Ctrl+2", run: () => setView({ type: "today" }) },
  { icon: "calendar-blank", label: "Đi tới: Sắp tới", hint: "Ctrl+3", run: () => setView({ type: "upcoming" }) },
  { icon: "star", label: "Đi tới: Đã ghim", hint: "Ctrl+4", run: () => setView({ type: "starred" }) },
  { icon: "check-circle", label: "Đi tới: Đã hoàn thành", hint: "Ctrl+5", run: () => setView({ type: "completed" }) },
  { icon: "trash", label: "Đi tới: Thùng rác", hint: "Ctrl+6", run: () => setView({ type: "trash" }) },
  { icon: "chart-bar", label: "Đi tới: Thống kê", hint: "Ctrl+7", run: () => setView({ type: "stats" }) },
  { icon: "gear", label: "Đi tới: Cài đặt", hint: "Ctrl+8", run: () => setView({ type: "settings" }) },
  { icon: "repeat", label: "Lặp lại… (việc đang chọn)", hint: "", run: () => { if (S.selected != null) openRecurrenceModal(S.selected); else toast("Chọn một việc trước đã"); } },
  { icon: "clock", label: "Mở cửa sổ đồng hồ", hint: "", run: () => invoke("focus_open_timer").catch(e => { const msg = typeof e === "string" ? e : (e && (e.message || e.toString())) || "không rõ lý do"; toast("Không mở được cửa sổ Đồng hồ: " + msg, "err", 6000); }) },
  { icon: "note-pencil", label: "Brain-dump — đổ việc nhanh", hint: "Ctrl+Shift+N", run: openBrainDump },
  { icon: "plus", label: "Thêm việc mới", hint: "Ctrl+N", run: () => { setView(S.view.type === "stats" || S.view.type === "trash" || S.view.type === "completed" ? { type: "inbox" } : S.view); setTimeout(() => $("#quickadd-input").focus(), 60); } },
  { icon: "sun", label: "Bật/tắt giao diện tối–sáng", hint: "Ctrl+D", run: () => go(invoke("toggle_dark")) },
  { icon: "archive", label: "Xuất bản sao lưu", hint: "", run: async () => { try { const name = await invoke("export_backup"); toast("Đã xuất " + name); } catch (e) { toast("Xuất thất bại", "err"); } } },
  { icon: "arrow-counter-clockwise", label: "Khôi phục từ bản sao lưu…", hint: "", run: openBackups },
  { icon: "folder", label: "Mở thư mục dữ liệu", hint: "", run: () => invoke("open_data_dir") },
  { icon: "keyboard", label: "Xem phím tắt", hint: "", run: openHelp },
];
function openPalette() {
  const p = $("#palette");
  p.hidden = false;
  $("#palette-input").value = "";
  S.paletteIdx = 0;
  renderPalette("");
  setTimeout(() => $("#palette-input").focus(), 30);
}
function closePalette() { $("#palette").hidden = true; }
function renderPalette(query) {
  const q = strip(query.trim());
  const box = $("#palette-results");
  const items = [];
  for (const a of PALETTE_ACTIONS) {
    if (!q || strip(a.label).includes(q)) items.push({ kind: "cmd", icon: a.icon, label: a.label, hint: a.hint, run: a.run });
  }
  if (q) {
    const matches = (S.snap.tasks || [])
      .filter(t => !isDeleted(t) && strip(t.title).includes(q))
      .slice(0, 6)
      .map(t => ({ kind: "task", icon: "check-circle", label: t.title, hint: "việc", task: t }));
    items.push(...matches);
  }
  S.paletteItems = items;
  if (S.paletteIdx >= items.length) S.paletteIdx = 0;
  box.innerHTML = items.length
    ? items.map((it, i) => `<button class="pal-item${i === S.paletteIdx ? " active" : ""}" data-pal="${i}"><svg class="ic"><use href="#i-${it.icon}"/></svg><span>${esc(it.label)}</span>${it.hint ? `<small>${esc(it.hint)}</small>` : ""}</button>`).join("")
    : `<div class="empty-inline" style="padding:18px 14px">Không tìm thấy kết quả</div>`;
}
function runPaletteItem(i) {
  const it = S.paletteItems[i];
  if (!it) return;
  closePalette();
  if (it.kind === "cmd") { it.run(); return; }
  const t = it.task;
  // chọn view phù hợp rồi mở chi tiết
  if (isDeleted(t)) setView({ type: "trash" });
  else if (isCompleted(t)) setView({ type: "completed" });
  else if (t.list_id != null) setView({ type: "list", id: t.list_id });
  else if (t.due && dueDiffDays(t.due) <= 0) setView({ type: "today" });
  else setView({ type: "inbox" });
  setTimeout(() => selectTask(t.id), 60);
}

/* ─────────── SỰ KIỆN TOÀN CỤC ─────────── */
function bindEvents() {
  bindAdhd();
  /* sidebar: điều hướng */
  document.addEventListener("click", e => {
    const nav = e.target.closest(".nav-item[data-view]");
    if (nav) { setView({ type: nav.dataset.view }); return; }
    const row = e.target.closest(".list-row[data-list]");
    if (row && !e.target.closest(".list-edit,.list-del")) { setView({ type: "list", id: Number(row.dataset.list) }); return; }
    const edit = e.target.closest("[data-edit-list]");
    if (edit) { e.stopPropagation(); openListDialog(Number(edit.dataset.editList)); return; }
    const del = e.target.closest("[data-del-list]");
    if (del) {
      e.stopPropagation();
      const id = Number(del.dataset.delList);
      openModal(`<h2><svg class="ic accent-ic"><use href="#i-folder"/></svg>Xóa danh sách?</h2><p>Các việc trong danh sách sẽ trở về <strong>Hộp thư</strong> (không mất việc). Thao tác này có thể hoàn tác bằng Ctrl+Z.</p><div class="modal-actions"><button class="btn-cancel" data-close-modal="1">Hủy</button><button class="btn-danger" id="confirm-del-list" data-id="${id}">Xóa danh sách</button></div>`);
      return;
    }
  });

  $("#qa-dump")?.addEventListener("click", openBrainDump);
  $("#d-split")?.addEventListener("click", () => {
    if (S.selected == null) return;
    const t = taskById(S.selected);
    if (t) wireSplitSuggest(t);
  });

  /* topbar */
  $("#btn-theme").addEventListener("click", () => go(invoke("toggle_dark")));
  $("#btn-undo").addEventListener("click", () => go(invoke("undo")));
  $("#btn-redo").addEventListener("click", () => go(invoke("redo")));
  $("#btn-add-top").addEventListener("click", () => {
    if (["stats", "settings", "trash", "completed"].includes(S.view.type)) setView({ type: "inbox" });
    setTimeout(() => $("#quickadd-input").focus(), 60);
  });
  $("#btn-menu").addEventListener("click", e => { e.stopPropagation(); $("#main-menu").hidden = !$("#main-menu").hidden; });
  $("#main-menu").addEventListener("click", async e => {
    const item = e.target.closest("[data-menu]"); if (!item) return;
    $("#main-menu").hidden = true;
    const k = item.dataset.menu;
    if (k === "export") { try { const name = await invoke("export_backup"); toast("Đã xuất " + name); } catch (err) { toast("Xuất thất bại", "err"); } }
    else if (k === "import") openBackups();
    else if (k === "open-dir") invoke("open_data_dir");
    else if (k === "empty-trash") openConfirmEmptyTrash();
    else if (k === "help") openHelp();
    else if (k === "about") openAbout();
  });
  document.addEventListener("click", e => { if (!e.target.closest("#main-menu") && !e.target.closest("#btn-menu")) $("#main-menu").hidden = true; });

  /* tìm kiếm */
  let searchDebounce = null;
  $("#search-input").addEventListener("input", e => {
    $("#search-clear").style.display = e.target.value ? "flex" : "none";
    clearTimeout(searchDebounce);
    searchDebounce = setTimeout(() => { S.search = e.target.value; renderTaskList(); }, 120);
  });
  $("#search-clear").addEventListener("click", () => { $("#search-input").value = ""; S.search = ""; $("#search-clear").style.display = "none"; renderTaskList(); });

  /* quick add */
  $("#quickadd-input").addEventListener("input", updateQaPreview);
  $("#quickadd-input").addEventListener("keydown", e => { if (e.key === "Enter") { e.preventDefault(); submitQuick(); } });
  $("#quickadd-enter").addEventListener("click", submitQuick);
  $$(".qa-chip").forEach(b => b.addEventListener("click", () => { $("#quickadd-input").value = b.dataset.example; updateQaPreview(); $("#quickadd-input").focus(); }));

  /* toolbar */
  $("#sort-select").addEventListener("change", e => go(invoke("set_sort", { mode: e.target.value })));
  $("#hide-done").addEventListener("change", e => go(invoke("set_hide_completed", { hide: e.target.checked })));
  $$("#prio-filter .prio-chip").forEach(b => b.addEventListener("click", () => {
    const p = b.dataset.prio;
    S.prio = S.prio === p ? null : p;
    $$("#prio-filter .prio-chip").forEach(x => x.classList.toggle("on", x.dataset.prio === S.prio));
    $("#prio-clear").hidden = !S.prio;
    renderTaskList();
  }));
  $("#prio-clear").addEventListener("click", () => { S.prio = null; $$("#prio-filter .prio-chip").forEach(x => x.classList.remove("on")); $("#prio-clear").hidden = true; renderTaskList(); });
  $("#tag-chip").addEventListener("click", () => { S.tag = null; $("#tag-chip").hidden = true; renderTaskList(); });
  $("#btn-clear-completed").addEventListener("click", () => go(invoke("act", { action: { type: "clear_completed" }, view: viewWire(S.view) })));
  $("#btn-bulk").addEventListener("click", () => {
    S.bulk = !S.bulk; S.bulkSel.clear();
    $("#btn-bulk").classList.toggle("active-mode", S.bulk);
    updateBulkUI(); renderTaskList();
  });

  /* bulk bar */
  $("#bulk-exit").addEventListener("click", () => { S.bulk = false; S.bulkSel.clear(); $("#btn-bulk").classList.remove("active-mode"); updateBulkUI(); renderTaskList(); });
  $("#bulk-complete").addEventListener("click", () => { if (!S.bulkSel.size) return; go(invoke("act", { action: { type: "bulk_complete", ids: [...S.bulkSel] }, view: viewWire(S.view) })); S.bulkSel.clear(); updateBulkUI(); });
  $("#bulk-star").addEventListener("click", () => { if (!S.bulkSel.size) return; go(invoke("act", { action: { type: "bulk_star", ids: [...S.bulkSel] }, view: viewWire(S.view) })); S.bulkSel.clear(); updateBulkUI(); });
  $("#bulk-delete").addEventListener("click", () => { if (!S.bulkSel.size) return; go(invoke("act", { action: { type: "bulk_delete", ids: [...S.bulkSel] }, view: viewWire(S.view) })); S.bulkSel.clear(); updateBulkUI(); });

  /* banner quá hạn */
  $("#overdue-today").addEventListener("click", () => go(invoke("act", { action: { type: "defer_overdue", target: S.snap ? S.snap.today : "" }, view: viewWire(S.view) })));
  $("#overdue-tomorrow").addEventListener("click", () => {
    const t = new Date(parseYmd(S.snap.today) + 86400000 + 12 * 3600 * 1000);
    const iso = t.toISOString().slice(0, 10);
    go(invoke("act", { action: { type: "defer_overdue", target: iso }, view: viewWire(S.view) }));
  });

  /* danh sách: thêm */
  $("#btn-new-list").addEventListener("click", () => openListDialog(null));

  /* ───────── tasklist: click / dblclick / toggle / star / delete / context / DnD ───────── */
  const list = $("#tasklist");
  list.addEventListener("click", e => {
    const toggle = e.target.closest("[data-toggle]");
    if (toggle) {
      const id = Number(toggle.dataset.toggle);
      const t = taskById(id);
      S.pendingPop = { id, kind: t && isCompleted(t) ? "undone" : "done" };
      go(invoke("act", { action: { type: "toggle", id }, view: viewWire(S.view) }));
      return;
    }
    const bulkbox = e.target.closest("[data-bulkbox]");
    if (bulkbox) {
      const id = Number(bulkbox.dataset.bulkbox);
      S.bulkSel.has(id) ? S.bulkSel.delete(id) : S.bulkSel.add(id);
      updateBulkUI(); return;
    }
    const star = e.target.closest("[data-star]");
    if (star) {
      const id = Number(star.dataset.star);
      S.pendingStar = id;
      go(invoke("act", { action: { type: "star", id }, view: viewWire(S.view) }));
      return;
    }
    const dup = e.target.closest("[data-duplicate]");
    if (dup) { go(invoke("act", { action: { type: "duplicate", id: Number(dup.dataset.duplicate) }, view: viewWire(S.view) })); return; }
    const del = e.target.closest("[data-delete]");
    if (del) {
      const id = Number(del.dataset.delete);
      const t = taskById(id);
      if (t && isDeleted(t)) { openPurgeConfirm(t); return; }
      go(invoke("act", { action: { type: "delete", id }, view: viewWire(S.view) }));
      return;
    }
    const res = e.target.closest("[data-restore]");
    if (res) { go(invoke("act", { action: { type: "restore", id: Number(res.dataset.restore) }, view: viewWire(S.view) })); return; }
    const row = e.target.closest(".task-row[data-id]");
    if (row) {
      const id = Number(row.dataset.id);
      if (S.bulk) { S.bulkSel.has(id) ? S.bulkSel.delete(id) : S.bulkSel.add(id); updateBulkUI(); return; }
      selectTask(id);
    }
  });
  list.addEventListener("dblclick", e => {
    const row = e.target.closest(".task-row[data-id]");
    if (row && e.target.closest(".ttitle")) { selectTask(Number(row.dataset.id)); setTimeout(() => $("#d-title").focus(), 60); }
  });
  list.addEventListener("contextmenu", e => {
    const row = e.target.closest(".task-row[data-id]");
    if (!row) return;
    e.preventDefault();
    const t = taskById(Number(row.dataset.id));
    if (!t) return;
    selectTask(t.id, { openDetail: false });
    ctxFor = t.id;
    openCtxMenu(taskCtxItems(t), e.clientX, e.clientY);
  });
  /* kéo thả sắp xếp (Manual) */
  list.addEventListener("dragstart", e => {
    const row = e.target.closest(".task-row[data-id]");
    if (!row || S.sort !== "Manual") { e.preventDefault(); return; }
    S.dragId = Number(row.dataset.id);
    e.dataTransfer.effectAllowed = "move";
    e.dataTransfer.setData("text/plain", String(S.dragId));
    row.style.opacity = ".55";
  });
  list.addEventListener("dragend", e => {
    const row = e.target.closest(".task-row[data-id]");
    if (row) row.style.opacity = "";
    $$(".task-row.drag-over", list).forEach(r => r.classList.remove("drag-over"));
    S.dragId = null;
  });
  list.addEventListener("dragover", e => {
    if (S.dragId == null) return;
    const row = e.target.closest(".task-row[data-id]");
    e.preventDefault();
    $$(".task-row.drag-over", list).forEach(r => r.classList.remove("drag-over"));
    if (row && Number(row.dataset.id) !== S.dragId) row.classList.add("drag-over");
  });
  list.addEventListener("drop", e => {
    const row = e.target.closest(".task-row[data-id]");
    e.preventDefault();
    if (S.dragId == null || !row) return;
    const dstId = Number(row.dataset.id);
    if (dstId === S.dragId) return;
    const r = row.getBoundingClientRect();
    const before = (e.clientY - r.top) < r.height / 2;
    go(invoke("act", { action: { type: "drop", src: S.dragId, dst: dstId, before }, view: viewWire(S.view) }));
    S.dragId = null;
  });

  /* context menu clicks */
  $("#ctx-menu").addEventListener("click", e => {
    const item = e.target.closest("[data-ctx]");
    const move = e.target.closest("[data-ctx-move]");
    const id = ctxFor;
    closeCtxMenu();
    if (!id) return;
    if (move) {
      const v = move.dataset.ctxMove;
      const listId = v === "inbox" ? null : Number(v);
      go(invoke("act", { action: { type: "move_to_list", id, list: listId }, view: viewWire(S.view) }));
      return;
    }
    if (!item) return;
    const k = item.dataset.ctx;
    if (k === "delete") {
      const t = taskById(id);
      if (t && isDeleted(t)) { openPurgeConfirm(t); return; }
    }
    const map = { toggle: "toggle", star: "star", duplicate: "duplicate", delete: "delete", restore: "restore" };
    if (map[k]) go(invoke("act", { action: { type: map[k], id }, view: viewWire(S.view) }));
  });
  document.addEventListener("click", e => { if (!e.target.closest("#ctx-menu")) closeCtxMenu(); }, true);

  /* ───────── detail: mọi tương tác ───────── */
  $("#detail-close").addEventListener("click", () => { $("#detail").classList.remove("open"); S.selected = null; $$(".task-row.selected").forEach(r => r.classList.remove("selected")); });
  $("#d-title").addEventListener("change", e => { const v = e.target.value.trim(); if (v && S.selected != null) go(invoke("set_task_title", { id: S.selected, title: v })); });
  $("#d-notes").addEventListener("change", e => { if (S.selected != null) go(invoke("set_task_notes", { id: S.selected, notes: e.target.value })); });
  $("#d-complete").addEventListener("click", () => {
    if (S.selected == null) return;
    const t = taskById(S.selected);
    S.pendingPop = { id: S.selected, kind: t && isCompleted(t) ? "undone" : "done" };
    go(invoke("act", { action: { type: "toggle", id: S.selected }, view: viewWire(S.view) }));
  });
  $("#d-star").addEventListener("click", () => { if (S.selected != null) go(invoke("act", { action: { type: "star", id: S.selected }, view: viewWire(S.view) })); });
  $("#d-restore").addEventListener("click", () => { if (S.selected != null) go(invoke("act", { action: { type: "restore", id: S.selected }, view: viewWire(S.view) })); });
  $("#d-duplicate").addEventListener("click", () => { if (S.selected != null) go(invoke("act", { action: { type: "duplicate", id: S.selected }, view: viewWire(S.view) })); });
  $("#d-delete").addEventListener("click", () => {
    if (S.selected == null) return;
    const t = taskById(S.selected);
    if (t && isDeleted(t)) { openPurgeConfirm(t); return; }
    go(invoke("act", { action: { type: "delete", id: S.selected }, view: viewWire(S.view) }));
  });
  $("#d-due-btn").addEventListener("click", () => $("#d-due-input").classList.toggle("show"));
  $("#d-due-input").addEventListener("change", e => { if (S.selected != null && e.target.value) { go(invoke("act", { action: { type: "set_due", id: S.selected, due: e.target.value }, view: viewWire(S.view) })); e.target.classList.remove("show"); } });
  $("#d-due-clear").addEventListener("click", () => { if (S.selected != null) go(invoke("act", { action: { type: "set_due", id: S.selected, due: null }, view: viewWire(S.view) })); });
  $$("#d-prio .prio-chip").forEach(b => b.addEventListener("click", () => { if (S.selected != null) go(invoke("act", { action: { type: "set_priority", id: S.selected, priority: b.dataset.prio }, view: viewWire(S.view) })); }));
  $("#d-recur").addEventListener("click", () => { if (S.selected != null) openRecurrenceModal(S.selected); });
  $("#d-recur-edit").addEventListener("click", () => { if (S.selected != null) openRecurrenceModal(S.selected); });
  $("#d-repeat-flag").addEventListener("click", () => { if (S.selected != null) openRecurrenceModal(S.selected); });
  $("#d-recur-skip").addEventListener("click", () => { if (S.selected != null) go(invoke("skip_occurrence", { id: S.selected })); });
  $("#d-recur-stop").addEventListener("click", () => { if (S.selected != null) go(invoke("set_task_recurrence", { id: S.selected, rule: null })); });
  $("#d-list").addEventListener("change", e => { if (S.selected != null) { const v = e.target.value; go(invoke("act", { action: { type: "move_to_list", id: S.selected, list: v === "" ? null : Number(v) }, view: viewWire(S.view) })); $("#d-list").dataset.built = "0"; } });
  $("#d-tag-input").addEventListener("keydown", e => {
    if (e.key === "Enter" && S.selected != null) {
      e.preventDefault();
      const v = e.target.value.trim();
      if (v) { go(invoke("add_task_tag", { id: S.selected, tag: v })); e.target.value = ""; }
    }
  });
  $("#d-tags").addEventListener("click", e => {
    const btn = e.target.closest("[data-untag]");
    if (btn && S.selected != null) go(invoke("remove_task_tag", { id: S.selected, tag: btn.dataset.untag }));
  });
  $("#d-add-subtask").addEventListener("click", () => { if (S.selected != null) go(invoke("act", { action: { type: "add_subtask", id: S.selected }, view: viewWire(S.view) })); });
  $("#d-subtasks").addEventListener("click", e => {
    if (S.selected == null) return;
    const tg = e.target.closest("[data-st-toggle]");
    if (tg) { go(invoke("toggle_subtask", { id: S.selected, sid: Number(tg.dataset.stToggle) })); return; }
    const del = e.target.closest("[data-st-del]");
    if (del) { go(invoke("remove_subtask", { id: S.selected, sid: Number(del.dataset.stDel) })); return; }
  });
  $("#d-subtasks").addEventListener("change", e => {
    const inp = e.target.closest("[data-st-title]");
    if (inp && S.selected != null) go(invoke("set_subtask_title", { id: S.selected, sid: Number(inp.dataset.stTitle), title: inp.value }));
  });

  /* cài đặt v2.1 */
  const patchSettings = p => go(invoke("update_settings", { patch: p }));
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
    try { st = await invoke("transparency_status"); } catch { toast("Không đọc được Transparency effects", "err"); return; }
    const on = !(st && st.enabled === true);
    try {
      const snap = await invoke("set_transparency", { on });
      postSnap(snap);
      toast(on ? "Đã bật Transparency effects — Acrylic có thể hiển thị" : "Đã tắt Transparency effects — Taskora chuyển nền đặc");
    } catch (err) { toast(String(err && err.message ? err.message : err), "err"); }
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
      toast("Không đọc được Transparency effects — nếu nền vẫn đục, hãy kiểm tra Settings → Personalization → Colors");
    }
  });
  $("#set-alpha").addEventListener("input", e => { $("#set-alpha-val").textContent = e.target.value; document.documentElement.style.setProperty("--cov", covOf(e.target.value).toFixed(3)); });
  $("#set-alpha").addEventListener("change", e => patchSettings({ acrylic_alpha: Number(e.target.value) }));
  $("#set-reduce-motion").addEventListener("change", e => patchSettings({ reduce_motion: e.target.checked }));
  $("#set-sort").addEventListener("change", e => patchSettings({ sort: e.target.value }));
  $("#set-hide-done").addEventListener("change", e => patchSettings({ hide_completed: e.target.checked }));
  $("#set-qa-preview").addEventListener("change", e => patchSettings({ qa_preview: e.target.checked }));
  $("#set-remind-today").addEventListener("change", e => patchSettings({ remind_today: e.target.checked }));
  $("#set-backup-on-exit").addEventListener("change", e => patchSettings({ backup_on_exit: e.target.checked }));
  $("#set-export").addEventListener("click", async () => { try { const name = await invoke("export_backup"); toast("Đã xuất " + name); } catch { toast("Xuất thất bại", "err"); } });
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
  $("#set-sound").addEventListener("change", e => { patchSettings({ sound_on: e.target.checked }); toast(e.target.checked ? "Âm thanh bật" : "Âm thanh tắt"); });
  $("#set-adhd").addEventListener("change", e => {
    patchSettings({ adhd_mode: e.target.checked });
    toast(e.target.checked ? "Chế độ ADHD bật — một việc tại một thời điểm ✦" : "Chế độ ADHD tắt");
  });

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
  $("#modal").addEventListener("click", async e => {
    if (e.target.closest("[data-close-modal]")) { closeModal(); if ($("#view-settings")?.classList.contains("active")) refreshStoragePanel(); return; }
    if (e.target.closest("#list-save")) {
      const name = ($("#list-name")?.value || "").trim();
      if (!name) { toast("Nhập tên danh sách", "err"); return; }
      const { editing, colorIdx } = S.modalList;
      closeModal();
      if (editing != null) go(invoke("rename_list", { id: editing, name, colorIdx }));
      else go(invoke("create_list", { name, colorIdx }));
      return;
    }
    const confirmDel = e.target.closest("#confirm-del-list");
    if (confirmDel) { closeModal(); go(invoke("delete_list", { id: Number(confirmDel.dataset.id) })); return; }
    const confirmPurge = e.target.closest("#confirm-purge");
    if (confirmPurge) { const id = Number(confirmPurge.dataset.id); closeModal(); go(invoke("act", { action: { type: "purge", id }, view: viewWire(S.view) })); return; }
    const confirmTrash = e.target.closest("#confirm-empty-trash");
    if (confirmTrash) { closeModal(); go(invoke("act", { action: { type: "purge_trash" }, view: viewWire(S.view) })); return; }
    const osEnable = e.target.closest("#os-tr-enable");
    if (osEnable) {
      closeModal();
      try {
        const snap = await invoke("set_transparency", { on: true });
        postSnap(snap);
        patchSettings({ transparent: true }); // chỉ bật trong suốt SAU khi điều kiện được đảm bảo
        refreshOsTransparency(); // cập nhật pill/nút ngay, không đợi debounce
        toast("Đã bật Transparency effects — Acrylic đang hoạt động");
      } catch (err) { toast(String(err && err.message ? err.message : err), "err"); }
      return;
    }
    const osDecline = e.target.closest("#os-tr-decline");
    if (osDecline) {
      closeModal();
      patchSettings({ transparent: false }); // từ chối → tuyệt đối không dùng nền trong suốt
      toast("Taskora giữ nền đặc — bật lại bất cứ lúc nào trong Cài đặt → Giao diện.");
      return;
    }
    const confirmReset = e.target.closest("#confirm-reset-settings");
    if (confirmReset) { closeModal(); go(invoke("reset_settings")); return; }
    const browseBtn = e.target.closest("#storage-custom-browse");
    if (browseBtn) {
      const picked = await pickFolder();
      if (picked) { const inp = $("#storage-custom-input"); if (inp) inp.value = picked; }
      else toast("Không mở được hộp chọn thư mục — hãy nhập đường dẫn", "err");
      return;
    }
    const customNext = e.target.closest("#storage-custom-next");
    if (customNext) {
      const p = ($("#storage-custom-input")?.value || "").trim();
      if (!p) { toast("Nhập đường dẫn thư mục", "err"); return; }
      closeModal();
      openStorageConfirm("custom", p);
      return;
    }
    if (e.target.closest("#storage-migrate")) { runStorageSwitch(true); return; }
    if (e.target.closest("#storage-fresh")) { runStorageSwitch(false); return; }
    if (e.target.closest("#orphan-import")) { runStorageImportOrphan(); return; }
    if (e.target.closest("#legacy-merge")) { runStorageMergeLegacy(); return; }
    const legacyKeep = e.target.closest("#legacy-keep");
    if (legacyKeep) { closeModal(); if (S._legacyDir) invoke("storage_dismiss", { kind: "merge", src_dir: S._legacyDir }).catch(() => {}); return; }
    const exportBtn = e.target.closest("#do-export");
    if (exportBtn) { try { const name = await invoke("export_backup"); toast("Đã xuất " + name); } catch (err) { toast("Xuất thất bại", "err"); } return; }
    const restoreBtn = e.target.closest("[data-restore-backup]");
    if (restoreBtn) {
      closeModal();
      try { postSnap(await invoke("import_backup", { name: restoreBtn.dataset.restoreBackup })); }
      catch (err) { toast(typeof err === "string" ? err : "Khôi phục thất bại", "err"); }
      return;
    }
  });
  $("#modal").addEventListener("keydown", e => {
    if (e.key === "Enter" && e.target.matches(".modal-input")) { e.preventDefault(); $("#list-save")?.click(); }
    // Ctrl+Enter = lưu (modal Lặp lại)
    if (e.ctrlKey && e.key === "Enter" && $("#rm-save")) { e.preventDefault(); $("#rm-save").click(); return; }
    // focus trap: Tab chuyển vòng trong modal
    if (e.key === "Tab" && !$("#modal").hidden) {
      const panel = $("#modal .modal-panel");
      if (!panel) return;
      const focusables = [...panel.querySelectorAll('button:not([disabled]), input:not([disabled]), select:not([disabled]), [tabindex]:not([tabindex="-1"])')].filter(el => el.offsetParent !== null || el === document.activeElement);
      if (!focusables.length) return;
      const idx = focusables.indexOf(document.activeElement);
      if (e.shiftKey) { if (idx <= 0) { e.preventDefault(); focusables[focusables.length - 1].focus(); } }
      else if (idx === focusables.length - 1 || idx === -1) { e.preventDefault(); focusables[0].focus(); }
    }
  });

  /* ───────── palette ───────── */
  $("#palette-input").addEventListener("input", e => { S.paletteIdx = 0; renderPalette(e.target.value); });
  $("#palette-input").addEventListener("keydown", e => {
    const items = S.paletteItems;
    if (e.key === "ArrowDown") { e.preventDefault(); S.paletteIdx = Math.min(items.length - 1, S.paletteIdx + 1); renderPalette($("#palette-input").value); }
    else if (e.key === "ArrowUp") { e.preventDefault(); S.paletteIdx = Math.max(0, S.paletteIdx - 1); renderPalette($("#palette-input").value); }
    else if (e.key === "Enter") { e.preventDefault(); runPaletteItem(S.paletteIdx); }
  });
  $("#palette-results").addEventListener("click", e => {
    const item = e.target.closest("[data-pal]");
    if (item) runPaletteItem(Number(item.dataset.pal));
  });
  $("#palette").addEventListener("click", e => { if (e.target.id === "palette") closePalette(); });
}

/* ─────────── PHÍM TẮT TOÀN CỤC ─────────── */
function isTyping() {
  const a = document.activeElement;
  return a && (a.tagName === "INPUT" || a.tagName === "TEXTAREA" || a.tagName === "SELECT" || a.isContentEditable);
}
function globalKeys(e) {
  const typing = isTyping();
  const mod = e.ctrlKey || e.metaKey;
  const key = e.key.toLowerCase();
  const modalOpen = !$("#modal").hidden;
  const paletteOpen = !$("#palette").hidden;
  const focusOpen = !$("#focus-overlay").hidden;
  if (focusOpen) {
    if (key === "escape") { e.preventDefault(); focusStop(); return; }
    if (key === " ") { e.preventDefault(); if (F.mode === "focus") focusTogglePause(); return; }
    if (key === "r") { e.preventDefault(); focusReset(); return; }
    return; // đang tập trung — chặn mọi phím tắt khác
  }

  if (key === "escape") {
    if (!$("#ctx-menu").hidden) { closeCtxMenu(); return; }
    if (paletteOpen) { closePalette(); return; }
    if (modalOpen) { closeModal(); return; }
    if (S.tag || S.prio) { S.tag = null; S.prio = null; $("#tag-chip").hidden = true; $$("#prio-filter .prio-chip").forEach(x => x.classList.remove("on")); $("#prio-clear").hidden = true; renderTaskList(); toast("Đã bỏ bộ lọc"); return; }
    if (S.selected != null) { S.selected = null; $("#detail").classList.remove("open"); $$(".task-row.selected").forEach(r => r.classList.remove("selected")); return; }
    $("#main-menu").hidden = true;
    return;
  }
  if (mod && key === "k") { e.preventDefault(); paletteOpen ? closePalette() : openPalette(); return; }
  if (mod && key === "f" && !typing) { e.preventDefault(); $("#search-input").focus(); return; }
  if (mod && e.shiftKey && key === "n") { e.preventDefault(); openBrainDump(); return; }
  if (mod && key === "n") {
    e.preventDefault();
    if (["stats", "settings", "trash", "completed"].includes(S.view.type)) setView({ type: "inbox" });
    $("#quickadd-input")?.focus();
    return;
  }
  if (mod && key === "d") { e.preventDefault(); go(invoke("toggle_dark")); return; }
  if (mod && key === "s") { e.preventDefault(); go(invoke("save_now")); return; }
  if (mod && (key === "z" || key === "y")) {
    if (typing) return;
    e.preventDefault();
    if (key === "y" || e.shiftKey) go(invoke("redo")); else go(invoke("undo"));
    return;
  }
  if (mod && /^[1-8]$/.test(key)) {
    e.preventDefault();
    const views = ["inbox", "today", "upcoming", "starred", "completed", "trash", "stats", "settings"];
    setView({ type: views[Number(key) - 1] });
    return;
  }
  if (typing) return;
  if (key === " " && S.selected != null) { e.preventDefault(); go(invoke("act", { action: { type: "toggle", id: S.selected }, view: viewWire(S.view) })); return; }
  if ((key === "delete" || key === "backspace") && S.selected != null) { e.preventDefault(); go(invoke("act", { action: { type: "delete", id: S.selected }, view: viewWire(S.view) })); return; }
  if (key === "arrowup" || key === "arrowdown") {
    if (!S.visibleIds.length) return;
    e.preventDefault();
    const cur = S.selected != null ? S.visibleIds.indexOf(S.selected) : -1;
    let next;
    if (e.altKey) {
      if (S.selected != null) go(invoke("act", { action: { type: key === "arrowup" ? "move_up" : "move_down", id: S.selected }, view: viewWire(S.view) }));
      return;
    }
    if (key === "arrowup") next = cur <= 0 ? 0 : cur - 1;
    else next = cur < 0 ? 0 : Math.min(S.visibleIds.length - 1, cur + 1);
    selectTask(S.visibleIds[next], { openDetail: false });
    $(`.task-row[data-id="${S.visibleIds[next]}"]`)?.scrollIntoView({ block: "nearest" });
  }
}

/* ─────────── INIT ─────────── */
document.addEventListener("DOMContentLoaded", async () => {
  bindEvents();
  try {
    window.__TAURI__?.event?.listen?.("focus:change", e => applyFocusPayload(e.payload));
  } catch { /* môi trường không hỗ trợ event — overlay vẫn tự sync qua invoke */ }
  focusTickStart();
  document.addEventListener("keydown", globalKeys);
  try {
    await refresh();
    const lv = S.snap?.settings?.last_view;
    const parsed = parseViewKey(lv);
    if (parsed) {
      if (parsed.type === "list" && !(S.snap.lists || []).some(l => l.id === parsed.id)) setView({ type: "inbox" });
      else if (viewKey(S.view) !== viewKey(parsed)) setView(parsed);
    }
    checkStoragePrompts();
  } catch (e) {
    console.error(e);
    document.body.insertAdjacentHTML("afterbegin", `<div class="fatal">Không tải được dữ liệu: ${esc(String(e))}</div>`);
  }
});

/* ─────────── CHẾ ĐỘ ADHD — một việc một lúc, thưởng tức thì, không phán xét ─────────── */
const s_isAdhd = () => !!(S.snap && S.snap.settings && S.snap.settings.adhd_mode);
const adhdHm = () => new Date().toLocaleTimeString("vi-VN", { hour: "2-digit", minute: "2-digit" });
const CIRC = 2 * Math.PI * 52;
let qaTimer = null, qaIdx = 0;

function setupAdhdPlaceholder() {
  const input = $("#quickadd-input");
  if (!input) return;
  if (!s_isAdhd()) {
    if (qaTimer) { clearInterval(qaTimer); qaTimer = null; }
    input.placeholder = "Thêm việc… ví dụ: “Mua sữa ngày mai #nhà !p1”";
    return;
  }
  if (qaTimer) return; /* đang xoay rồi — giữ nhịp */
  qaIdx = 0;
  input.placeholder = ADHD_QA[0];
  qaTimer = setInterval(() => { qaIdx = (qaIdx + 1) % ADHD_QA.length; input.placeholder = ADHD_QA[qaIdx]; }, 8000);
}

function nextAdhdTask() {
  if (!["inbox", "today", "upcoming", "starred", "list"].includes(S.view.type)) return null;
  for (const id of S.visibleIds) {
    const t = taskById(id);
    if (t && !isCompleted(t) && !isDeleted(t)) return t;
  }
  return null;
}

function renderNextUp() {
  const el = $("#adhd-next");
  if (!el) return;
  if (!s_isAdhd() || !["inbox", "today", "upcoming", "starred", "list"].includes(S.view.type)) { el.hidden = true; return; }
  const doneToday = (S.snap && S.snap.counts && S.snap.counts.done_today) || 0;
  const focusToday = (S.snap && S.snap.counts && S.snap.counts.focus_today) || 0;
  const focusMin = (S.snap && S.snap.settings && S.snap.settings.focus_min) || 25;
  const focusSuffix = focusToday > 0 ? ` · ${focusToday} phiên` : "";
  const t = nextAdhdTask();
  el.hidden = false;
  if (!t) {
    el.innerHTML = `<div class="adhd-hero-top"><span class="adhd-next-label"><svg class="ic tiny"><use href="#i-lightning"/></svg>TIẾP THEO</span><span class="adhd-clock" id="adhd-clock">${adhdHm()}</span></div>
      <div class="adhd-hero-empty"><svg class="ic adhd-hero-empty-ic"><use href="#i-seal-check-fill"/></svg>
        <div class="adhd-hero-empty-title">Xong hết rồi ✦</div>
        <div class="adhd-hero-empty-sub">Nghỉ thật sự — không còn gì chờ bạn</div>
      </div>`;
    startAdhdClock();
    return;
  }
  el.innerHTML = `<div class="adhd-hero-top"><span class="adhd-next-label"><svg class="ic tiny"><use href="#i-lightning"/></svg>VIỆC TIẾP THEO — CHỈ MỘT VIỆC NÀY</span><span class="adhd-clock" id="adhd-clock">${adhdHm()}</span></div>
    <div class="adhd-hero-title">${esc(t.title)}</div>
    <div class="adhd-next-meta">${dueChip(t)}${repeatMeta(t)}${subtaskMeta(t)}${tagsMeta(t)}</div>
    <div class="adhd-hero-actions">
      <button class="adhd-cta" data-adhd-focus="${t.id}"><svg class="ic"><use href="#i-clock"/></svg>Tập trung ${focusMin} phút</button>
      <button class="btn-adhd-done xl" data-adhd-done="${t.id}" title="Xong luôn việc này"><svg class="ic"><use href="#i-check"/></svg>Xong</button>
    </div>
    <div class="adhd-done-line"><svg class="ic tiny"><use href="#i-check-circle"/></svg><span>Hôm nay đã xong <b>${doneToday}</b> việc${focusSuffix}</span></div>`;
  startAdhdClock();
}

function confettiBurst(x, y) {
  if (!s_isAdhd()) return;
  if (S.snap?.settings?.reduce_motion) return;
  if (window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  const colors = ["#818cf8", "#c084fc", "#facc15", "#34d399", "#fb7185", "#38bdf8"];
  for (let i = 0; i < 26; i++) {
    const p = document.createElement("div");
    p.className = "confetti-piece";
    p.style.background = colors[i % colors.length];
    document.body.appendChild(p);
    const ang = Math.random() * Math.PI * 2, v = 110 + Math.random() * 230;
    const dx = Math.cos(ang) * v, dy = Math.sin(ang) * v - 70, rot = Math.random() * 720 - 360;
    if (typeof p.animate === "function") {
      const anim = p.animate([
        { transform: `translate(${x}px, ${y}px) rotate(0deg)`, opacity: 1 },
        { transform: `translate(${x + dx}px, ${y + dy + 340}px) rotate(${rot}deg)`, opacity: 0 }
      ], { duration: 950 + Math.random() * 300, easing: "cubic-bezier(.16,.84,.3,1)" });
      anim.onfinish = () => p.remove();
    } else { setTimeout(() => p.remove(), 1000); }
  }
}

function applyFocusPayload(p) {
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

function focusRemainingNow() {
  if (F.endsAtMs == null) return F.remainingSecs;
  return Math.max(0, Math.ceil((F.endsAtMs - Date.now()) / 1000));
}

function drawFocusRing(rem) {
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

const focusEyeHide = () => { const e = $("#eye-pill"); if (e) e.hidden = true; clearInterval(eyeTimer); };

function renderFocus() {
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
  /* overlay đóng/mở theo engine */
  const ov = $("#focus-overlay");
  const show = F.active || F.phaseDone;
  if (ov) {
    if (show && ov.hidden) ov.hidden = false;
    else if (!show && !ov.hidden) ov.hidden = true;
  }
  /* nghỉ xong → toast + dừng engine (overlay đóng ở cả hai cửa sổ qua event) */
  const breakDone = F.phaseDone && F.mode !== "focus";
  if (breakDone && !F.breakDoneFlag) {
    F.breakDoneFlag = true;
    toast("Nghỉ xong rồi — việc tiếp theo nhé ✦");
    focusStop(true);
  } else if (!breakDone) {
    F.breakDoneFlag = false;
  }
}

function focusTickStart() {
  clearInterval(F.timer);
  F.timer = setInterval(() => {
    if (!F.active) return;
    const rem = focusRemainingNow();
    const ov = $("#focus-overlay");
    if (ov && !ov.hidden) drawFocusRing(rem);
    const s = S.snap && S.snap.settings ? S.snap.settings : {};
    if (F.mode === "focus" && !F.eyeShown && !F.paused && s.eye_reminder !== false && (F.totalSecs - rem) >= 1200) showEyePill();
    if (rem <= 0 && !F.phaseDone && F.endsAtMs != null && !F.completing) {
      F.completing = true;
      invoke("focus_complete")
        .then(p => {
          applyFocusPayload(p);
          if (p && p.transitioned) {
            playChime(p.chime, p.soundOn !== false);
            if (p.completedFocus) { refresh(); if (s_isAdhd()) confettiBurst(window.innerWidth / 2, Math.max(120, window.innerHeight / 2 - 80)); }
          }
        })
        .catch(() => {})
        .finally(() => { F.completing = false; });
    }
  }, 500);
}

const focusSync = () => invoke("focus_state").then(applyFocusPayload).catch(() => {});

async function focusStart(taskId) {
  const t = taskById(taskId);
  if (!t) return;
  F.eyeShown = false;
  focusEyeHide();
  try { postSnap(await invoke("focus_start", { taskId })); }
  catch { toast("Không bắt đầu được phiên tập trung", "err"); return; }
  focusSync();
  focusTickStart();
}

function focusStop(silent) {
  const wasBreak = F.mode !== "focus";
  focusEyeHide();
  invoke("focus_stop").then(s => { postSnap(s); focusSync(); }).catch(() => {});
  if (wasBreak && !silent) toast("Về lại việc thôi ✦");
}

function focusTogglePause() {
  if (!F.active || F.phaseDone) return;
  invoke("focus_pause_toggle").then(applyFocusPayload).catch(() => {});
}

function focusReset() {
  if (!F.active) return;
  F.eyeShown = false;
  focusEyeHide();
  invoke("focus_reset").then(applyFocusPayload).catch(() => {});
}

function focusBreakStart() {
  invoke("focus_break_start").then(applyFocusPayload).catch(() => {});
}

function bindAdhd() {
  /* hộp Chia nhỏ — delegation cho toàn bộ nút/ô bên trong (render lại nhiều lần) */
  $("#d-split-suggest")?.addEventListener("click", e => {
    const box = $("#d-split-suggest");
    if (!box) return;
    const taskId = S.selected;
    const t = taskId != null ? taskById(taskId) : null;

    if (e.target.closest("#split-close")) { box.hidden = true; return; }

    const delRow = e.target.closest(".split-row-del");
    if (delRow) { delRow.closest(".split-row").remove(); renumberSplitRows(box); return; }

    if (e.target.closest("#split-add-row")) {
      const rows = box.querySelector("#split-rows");
      if (rows.children.length >= 12) { toast("Tối đa 12 bước nhỏ", "err"); return; }
      rows.insertAdjacentHTML("beforeend", splitRowHtml("", rows.children.length));
      renumberSplitRows(box);
      rows.lastElementChild.querySelector(".split-suggest-input").focus();
      return;
    }

    const presetDel = e.target.closest("[data-preset-del]");
    if (presetDel) {
      e.stopPropagation();
      const delId = Number(presetDel.dataset.presetDel);
      const deleted = (S.snap.step_presets || []).find(x => x.id === delId);
      go(invoke("delete_step_preset", { id: delId })).then(() => {
        if (t) renderSplitSuggest(splitRows(box) || []);
        if (deleted) toast(`Đã xóa mẫu “${deleted.name}”`, undefined, { label: "Hoàn tác", onClick: () => { go(invoke("save_step_preset", { name: deleted.name, steps: deleted.steps.slice() })).then(() => t && renderSplitSuggest(splitRows(box) || [])); } });
      });
      return;
    }
    const presetChip = e.target.closest("[data-preset-id]");
    if (presetChip && t) {
      const p = (S.snap.step_presets || []).find(x => x.id === Number(presetChip.dataset.presetId));
      if (p) renderSplitSuggest(p.steps.slice());
      return;
    }
    if (e.target.closest('[data-preset="__dict__"]') && t) { renderSplitSuggest(splitSteps(t.title).slice()); return; }

    if (e.target.closest("#split-save-preset")) {
      const wrap = box.querySelector("#split-preset-save");
      if (wrap) { wrap.hidden = false; box.querySelector("#split-preset-name")?.focus(); }
      return;
    }
    if (e.target.closest("#split-preset-save-cancel")) { const wrap = box.querySelector("#split-preset-save"); if (wrap) wrap.hidden = true; return; }
    if (e.target.closest("#split-preset-save-btn") && t) {
      const nameInput = box.querySelector("#split-preset-name");
      const name = (nameInput?.value || "").trim();
      const steps = splitRows(box);
      if (!name) { toast("Đặt tên cho mẫu đã", "err"); return; }
      if (!steps.length) { toast("Mẫu phải có ít nhất 1 bước", "err"); return; }
      go(invoke("save_step_preset", { name, steps })).then(() => renderSplitSuggest(steps));
      return;
    }

    if (e.target.closest("#split-add") && t) {
      const titles = splitRows(box);
      if (!titles.length) { toast("Ít nhất 1 bước nhỏ", "err"); return; }
      box.hidden = true;
      go(invoke("act", { action: { type: "add_subtasks", id: t.id, titles }, view: viewWire(S.view) }));
      return;
    }
  });
  /* đếm ngược số bước ngay khi gõ/sửa */
  $("#d-split-suggest")?.addEventListener("input", e => {
    if (e.target.closest(".split-suggest-input")) renumberSplitRows($("#d-split-suggest"));
  });
  document.addEventListener("click", e => {
    const f = e.target.closest("[data-adhd-focus]");
    if (f) { focusStart(Number(f.dataset.adhdFocus)); return; }
    const d = e.target.closest("[data-adhd-done]");
    if (d) {
      const id = Number(d.dataset.adhdDone);
      const t = taskById(id);
      S.pendingPop = { id, kind: t && isCompleted(t) ? "undone" : "done" };
      go(invoke("act", { action: { type: "toggle", id }, view: viewWire(S.view) }));
      return;
    }
  });
  $("#focus-pause")?.addEventListener("click", focusTogglePause);
  $("#focus-reset")?.addEventListener("click", focusReset);
  $("#focus-open-timer")?.addEventListener("click", () => invoke("focus_open_timer").catch(e => {
    const msg = typeof e === "string" ? e : (e && (e.message || e.toString())) || "không rõ lý do";
    toast("Không mở được cửa sổ Đồng hồ: " + msg, "err", 6000);
  }));
  $("#focus-stop")?.addEventListener("click", focusStop);
  $("#focus-break")?.addEventListener("click", focusBreakStart);
  $("#focus-next")?.addEventListener("click", focusStop);
}

/* ĐỒNG HỒ LIVE (mỏ neo thời gian — chống time blindness) */
let clockTimer = null;
function startAdhdClock() {
  if (clockTimer) return;
  const tick = () => {
    const now = new Date();
    const hm = now.toLocaleTimeString("vi-VN", { hour: "2-digit", minute: "2-digit" });
    const el = $("#adhd-clock"); if (el) el.textContent = hm;
    const fn = $("#focus-now"); if (fn && F.active) fn.textContent = `Bây giờ là ${hm}`;
  };
  tick();
  clockTimer = setInterval(tick, 1000);
}
function stopAdhdClock() { clearInterval(clockTimer); clockTimer = null; }

/* VÒNG THỞ khi nghỉ — điều tiết thần kinh, không phải đếm ngược */
let breathTimer = null, breathInhale = true;
function startBreath() {
  stopBreath(); breathInhale = true;
  const set = () => { const el = $("#focus-breath-text"); if (el) el.textContent = breathInhale ? "Hít vào… (4 giây)" : "Thở ra… thật chậm (6 giây)"; };
  set();
  breathTimer = setInterval(() => { breathInhale = !breathInhale; set(); }, 5000);
}
function stopBreath() { clearInterval(breathTimer); breathTimer = null; }

/* ═══════════ v2.5–v2.8.0 — Brain-dump · Chia nhỏ · Chime · 20-20-20 · Agenda/Lặp lại ═══════════ */

/* Chime 3 nốt nhẹ nhàng — Web Audio, offline, không cần file */
function playChime(style, on) {
  if (on === false) return;
  style = style || (S.snap && S.snap.settings && S.snap.settings.chime) || "soft";
  if (style === "none") return;
  if (on === undefined && S.snap && S.snap.settings && S.snap.settings.sound_on === false) return;
  try {
    const Ctx = window.AudioContext || window.webkitAudioContext;
    if (!Ctx) return;
    const ctx = playChime._ctx || (playChime._ctx = new Ctx());
    const wind = style === "wind";
    const notes = wind ? [1318.51, 1567.98, 2093.0] : [784, 659.25, 523.25]; // wind: E6 → G6 → C7
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

/* 20-20-20 — một lần mỗi phiên, đúng mốc 20:00 */
let eyeTimer = null;
function showEyePill() {
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

/* Brain-dump — mỗi dòng một việc, parse chung parser quick-add */
function openBrainDump() {
  openModal(`<h2><svg class="ic accent-ic"><use href="#i-note-pencil"/></svg>Brain-dump — cứ đổ ra đi</h2>
    <p>Mỗi dòng một thứ. Không cần đẹp, không cần đúng, không cần sắp xếp — giống viết riêng cho mình.</p>
    <textarea id="dump-area" class="dump-area" rows="8" autocomplete="off" spellcheck="false" placeholder="Mua sữa ngày mai #nhà !p2
Gọi cho sếp về hợp đồng
Ý tưởng: làm dashboard sáng tạo
Đọc 10 trang sách — bước hồi phục
"></textarea>
    <div class="dump-foot"><span id="dump-count"><b>0</b> việc</span><span class="dump-hint">Mỗi dòng = 1 việc · nhận diện ngày/#tag/!p1</span></div>
    <div class="modal-actions"><button class="btn-cancel" data-close-modal="1">Hủy</button><button class="btn-save" id="dump-save">Đổ vào Hộp thư</button></div>`);
  const area = $("#dump-area");
  const countEl = $("#dump-count");
  const update = () => { const n = area.value.split(/\n/).map(l => l.trim()).filter(Boolean).length; countEl.innerHTML = `<b>${n}</b> việc`; };
  area.addEventListener("input", update);
  area.addEventListener("keydown", e => { if ((e.ctrlKey || e.metaKey) && e.key === "Enter") { e.preventDefault(); $("#dump-save").click(); } });
  area.focus();
  $("#dump-save").addEventListener("click", async () => {
    const input = area.value;
    const n = input.split(/\n/).map(l => l.trim()).filter(Boolean).length;
    if (!n) { toast("Chưa có gì để đổ ra — viết mỗi dòng một việc", "err"); return; }
    try {
      const snap = await invoke("brain_dump", { input, view: viewWire(S.view) });
      closeModal();
      postSnap(snap);
      if (S.snap.settings.adhd_mode) confettiBurst(window.innerWidth / 2, window.innerHeight / 2 - 60);
    } catch (e) { toast(String(e), "err"); }
  });
}

/* Hộp xác nhận xóa vĩnh viễn (dùng chung: detail + menu chuột phải + nút hàng) */
function openPurgeConfirm(task) {
  openModal(`<h2><svg class="ic danger"><use href="#i-warning"/></svg>Xóa vĩnh viễn?</h2>
    <p>“${esc(task.title)}” sẽ bị xóa khỏi thùng rác. Vẫn có thể bấm <strong>Ctrl+Z</strong> ngay sau đó để lấy lại — nhưng đừng tin vào may mắn.</p>
    <div class="modal-actions"><button class="btn-cancel" data-close-modal="1">Hủy</button><button class="btn-danger" id="confirm-purge" data-id="${task.id}">Xóa vĩnh viễn</button></div>`);
}

/* Chia nhỏ việc — từ điển pattern cục bộ (KHÔNG AI) + mẫu riêng của người dùng */
function splitSteps(title) {
  const t = strip(String(title || ""));
  const dict = [
    [/(viet|lam|soan).{0,24}(bao cao|report)/, ["Mở file báo cáo và đặt tên", "Ghi dàn ý 3 mục chính", "Viết mục 1 — chỉ cần ra chữ, chưa cần hay", "Viết mục 2", "Viết mục 3", "Đọc lại 5 phút và sửa"]],
    [/(hoc|on).{0,16}(thi|kiem tra|deadline)?/, ["Chuẩn bị tài liệu và bàn học", "Chọn 1 chương nhỏ nhất để bắt đầu", "Học 25 phút tập trung", "Tự kiểm tra / làm 2 câu hỏi", "Ghi lại chỗ chưa hiểu hỏi ai đó"]],
    [/(goi|dien thoai)/, ["Tìm số điện thoại", "Viết 3 ý chính cần nói", "Gọi ngay", "Ghi lại kết quả trong 1 dòng"]],
    [/(mua|sam)/, ["Liệt kê những gì cần mua", "Kiểm tra đã có gì ở nhà", "Chọn nơi mua gần nhất", "Mua xong — cất đúng chỗ"]],
    [/(email|mail)/, ["Viết tiêu đề rõ ràng", "Viết 1 câu hỏi/trả lời chính", "Đọc lại, sửa lỗi chính tả", "Gửi và đóng tab"]],
    [/(nop|gui).{0,12}(file|tai lieu|bai|ho so)/, ["Kiểm tra lại yêu cầu nộp", "Chuẩn bị file/tài liệu đúng định dạng", "Nộp xong — xác nhận lại"]],
    [/(hop|meeting)/, ["Viết agenda 3 ý", "Chuẩn bị số liệu/tài liệu mang theo", "Vào họp đúng giờ", "Ghi biên bản 3 dòng + ai làm gì"]],
    [/doc/, ["Chọn tài liệu và trang bắt đầu", "Tắt mọi thứ khác 25 phút", "Đọc 10 trang", "Ghi 2 dòng tóm tắt"]],
    [/(don|quet|don dep|don nha)/, ["Chọn góc nhỏ nhất để bắt đầu", "Dọn 15 phút — thôi", "Bỏ rác / đồ không cần", "Chụp ảnh kết quả (động lực)"]],
    [/(review|xem lai|check)/, ["Biết mình cần tìm gì khi review", "Review từng phần nhỏ, đánh dấu chỗ nghi vấn", "Ghi lại 3 vấn đề cần sửa", "Sửa hoặc báo cáo lại"]],
  ];
  for (const [re, steps] of dict) if (re.test(t)) return steps;
  return ["Mở đúng tài liệu/phần mềm cần dùng", "Làm 5 phút xấu nhất chấp nhận được", "Bật Tập trung 25′ (thẻ TIẾP THEO)", "Đánh dấu bước kế tiếp khi dừng"];
}

const splitRowHtml = (text, idx) => `<div class="split-row"><span class="split-num">${idx + 1}</span><input type="text" class="split-suggest-input" value="${esc(text)}" maxlength="140" autocomplete="off" spellcheck="false" /><button class="split-row-del" type="button" title="Bỏ bước này"><svg class="ic tiny"><use href="#i-x"/></svg></button></div>`;
const splitRows = box => [...box.querySelectorAll(".split-suggest-input")].map(i => i.value.trim()).filter(Boolean);

function renderSplitSuggest(steps) {
  const box = $("#d-split-suggest");
  if (!box) return;
  const presets = (S.snap && S.snap.step_presets) || [];
  const cleanSteps = steps.length ? steps : ["", "", ""];
  box.innerHTML = `
    <div class="split-head"><span>Bước nhỏ gợi ý — sửa gì cũng được</span><button class="icon-btn tiny" id="split-close" title="Đóng"><svg class="ic tiny"><use href="#i-x"/></svg></button></div>
    <div class="split-chips">
      <button class="split-chip" data-preset="__dict__" title="Theo từ điển dựng sẵn khớp với tên việc">Tự động</button>
      ${presets.map(p => `<button class="split-chip user" data-preset-id="${p.id}" title="Mẫu của bạn — bấm để áp dụng">${esc(p.name)}<span class="split-chip-del" data-preset-del="${p.id}" title="Xóa mẫu này"><svg class="ic tiny"><use href="#i-x"/></svg></span></button>`).join("")}
    </div>
    <div class="split-rows" id="split-rows">${cleanSteps.map((x, i) => splitRowHtml(x, i)).join("")}</div>
    <button class="split-add-row" id="split-add-row" type="button"><svg class="ic tiny"><use href="#i-plus"/></svg>Thêm dòng</button>
    <div class="split-preset-save" id="split-preset-save" hidden>
      <input type="text" id="split-preset-name" maxlength="40" placeholder="Tên mẫu… ví dụ: Viết báo cáo" autocomplete="off" spellcheck="false" />
      <button class="btn-save small" id="split-preset-save-btn" type="button">Lưu mẫu</button>
      <button class="btn-cancel small" id="split-preset-save-cancel" type="button">Thôi</button>
    </div>
    <div class="split-actions">
      <button class="btn-ghost small" id="split-save-preset" type="button"><svg class="ic small"><use href="#i-star"/></svg>Lưu thành mẫu riêng</button>
      <button class="btn-save" id="split-add" type="button">Thêm ${cleanSteps.length} bước nhỏ này</button>
    </div>`;
  box.hidden = false;
}

function renumberSplitRows(box) {
  const inputs = [...box.querySelectorAll(".split-row")];
  inputs.forEach((row, i) => { const n = row.querySelector(".split-num"); if (n) n.textContent = String(i + 1); });
  const save = box.querySelector("#split-add");
  if (save) save.textContent = `Thêm ${splitRows(box).length} bước nhỏ này`;
}

function wireSplitSuggest(task) {
  renderSplitSuggest(splitSteps(task.title).slice());
}

/* ─────────── modal Lặp lại (v2.9.0) — ghost calendar, until/after, preview từ Rust ─────────── */
const RM_WEEKDAYS = [["T2", 0], ["T3", 1], ["T4", 2], ["T5", 3], ["T6", 4], ["T7", 5], ["CN", 6]];
const RM_UNIT = { Day: "ngày", Week: "tuần", Month: "tháng", Year: "năm" };
const RM_FREQ_LABEL = { Day: "Ngày", Week: "Tuần", Month: "Tháng", Year: "Năm" };

/** ISO cộng n tháng, kẹp theo ngày cuối tháng (an toàn trong JS, chỉ hiển thị/đặt until). */
function addMonthsClampedISO(iso, n) {
  const { y, m, d } = splitISOLocal(iso);
  const total = y * 12 + (m - 1) + n;
  const ty = Math.floor(total / 12), tm = ((total % 12) + 12) % 12;
  const dim = new Date(ty, tm + 1, 0).getDate();
  return makeISOLocal(ty, tm, Math.min(d, dim));
}

function openRecurrenceModal(taskId) {
  const t = taskById(taskId);
  if (!t) return;
  const dueIso = t.due ? String(t.due).slice(0, 10) : localISODate();
  const r = t.recurrence || null;
  const endsKind = r?.ends?.kind === "until" ? "until" : r?.ends?.kind === "after" ? "after" : "never";
  const draft = r ? {
    freq: r.freq,
    interval: r.interval || 1,
    by_day: r.by_day ?? null,
    month_day: r.month_day ?? null,
    endsKind,
    until: r.ends?.kind === "until" ? String(r.ends.date).slice(0, 10) : "",
    afterTotal: r.ends?.kind === "after" ? r.ends.total : 10,
    afterDone: r.ends?.kind === "after" ? (r.ends.done || 0) : 0,
  } : {
    freq: "Day", interval: 1, by_day: null, month_day: null,
    endsKind: "never", until: "", afterTotal: 10, afterDone: 0,
  };
  const vm = splitISOLocal(dueIso);
  S.rm = { taskId, title: t.title, dueIso, draft, viewY: vm.y, viewM: vm.m, occurrences: new Set(), timer: null, previewSeq: 0 };
  renderRecurrenceModal();
}

function rmDraftError() {
  const d = S.rm.draft;
  const tdy = localISODate();
  if (d.freq === "Week" && !d.by_day) return "Chọn ít nhất 1 thứ trong tuần";
  if (d.endsKind === "until") {
    if (!d.until) return "Chọn ngày kết thúc (hoặc bấm vào lịch bên dưới)";
    if (d.until < tdy) return "Ngày kết thúc phải ở tương lai";
  }
  if (d.endsKind === "after" && (!(d.afterTotal >= 1))) return "Sau ít nhất 1 lần hoàn thành";
  return "";
}

/** Rule từ draft — gửi cho backend. month_day null ⇒ backend đóng băng từ due (anchor ổn định). */
function rmRule() {
  const d = S.rm.draft;
  const rule = { freq: d.freq, interval: Math.max(1, Math.min(99, Number(d.interval) || 1)) };
  if (d.freq === "Week") rule.by_day = d.by_day == null ? 0 : d.by_day;
  if (d.freq === "Month" || d.freq === "Year") rule.month_day = d.month_day == null ? undefined : d.month_day;
  if (d.endsKind === "until") rule.ends = d.until ? { kind: "until", date: d.until } : { kind: "never" };
  else if (d.endsKind === "after") rule.ends = { kind: "after", total: Math.max(1, Number(d.afterTotal) || 1), done: d.afterDone || 0 };
  else rule.ends = { kind: "never" };
  return rule;
}

function rmWarningHtml(d) {
  if (d.freq !== "Week" || !d.by_day || !S.rm?.dueIso) return "";
  const { y, m, d: dd } = splitISOLocal(S.rm.dueIso);
  const bit = (new Date(y, m - 1, dd).getDay() + 6) % 7; // JS 0=CN → bit0=T2
  if (d.by_day & (1 << bit)) return "";
  const name = ["Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy", "Chủ Nhật"][bit];
  return `<div class="rm-warn">Lần hiện tại (${name}) không nằm trong lịch lặp — chuỗi bắt đầu từ lần sau.</div>`;
}

function rmMonthDayHtml(d, base) {
  let opts = "";
  for (let i = 1; i <= 31; i++) opts += `<option value="${i}" ${d.month_day === i ? "selected" : ""}>Ngày ${i}</option>`;
  opts += `<option value="-1" ${d.month_day === -1 ? "selected" : ""}>Ngày cuối cùng</option>`;
  const kind = d.freq === "Month" ? "tháng" : "năm";
  let hint = "";
  if (d.month_day == null) hint = `<div class="rm-hint-line">Mặc định: ngày ${base.d} (đóng băng theo hạn chót khi lưu)</div>`;
  else if (d.freq === "Year") hint = `<div class="rm-hint-line">Mỗi ${kind} vào ngày ${d.month_day === -1 ? `cuối tháng ${base.m}` : `${d.month_day} tháng ${base.m}`}</div>`;
  return `<div class="rm-block">
    <div class="rm-label">Ngày trong ${kind}</div>
    <select id="rm-monthday" class="d-select rm-monthday-select">${opts}</select>
    ${hint}
  </div>`;
}

function ghostCalendarHtml(rm) {
  const { viewY, viewM } = rm;
  const tdy = localISODate();
  const startDow = (new Date(viewY, viewM - 1, 1).getDay() + 6) % 7; // Monday-first
  const start = new Date(viewY, viewM - 1, 1 - startDow);
  const until = rm.draft.endsKind === "until" ? rm.draft.until : "";
  let cells = "";
  for (let i = 0; i < 42; i++) {
    const dt = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
    const iso = makeISOLocal(dt.getFullYear(), dt.getMonth(), dt.getDate());
    const other = dt.getMonth() !== viewM - 1;
    const isToday = iso === tdy;
    const isPast = iso < tdy;
    const isUntil = !!until && iso === until;
    const isAfterUntil = !!until && iso > until;
    const isOcc = rm.occurrences.has(iso);
    const cls = ["gcal-cell"];
    if (other) cls.push("other");
    if (isPast && !isToday) cls.push("past");
    if (isToday) cls.push("today");
    if (isUntil) cls.push("until");
    else if (isAfterUntil) cls.push("after-until");
    if (isOcc) cls.push("occ");
    const label = esc(viFullDayMonth(iso));
    cells += `<button class="${cls.join(" ")}" data-iso="${iso}" role="gridcell" type="button" style="--d:${i * 6}ms" aria-label="${label}${isOcc ? " — sẽ xuất hiện" : ""}" aria-selected="${isUntil ? "true" : "false"}" title="${isOcc ? `Sẽ xuất hiện vào ${label}` : label}"><span class="gcal-num">${dt.getDate()}</span><span class="gcal-dot" aria-hidden="true"></span></button>`;
  }
  const cur = splitISOLocal(tdy);
  const prevDisabled = viewY < cur.y || (viewY === cur.y && viewM <= cur.m);
  const maxDt = new Date(cur.y, cur.m - 1 + 24, 1);
  let nextDisabled = new Date(viewY, viewM - 1, 1) >= maxDt;
  if (until) {
    const u = splitISOLocal(until);
    if (new Date(viewY, viewM - 1, 1) >= new Date(u.y, u.m - 1, 1)) nextDisabled = true;
  }
  return `<div class="gcal" id="gcal">
    <div class="gcal-head">
      <button class="icon-btn tiny gcal-nav" id="gcal-prev" type="button" ${prevDisabled ? "disabled" : ""} aria-label="Tháng trước">‹</button>
      <div class="gcal-title">tháng ${viewM} / ${viewY}</div>
      <button class="icon-btn tiny gcal-nav" id="gcal-next" type="button" ${nextDisabled ? "disabled" : ""} aria-label="Tháng sau">›</button>
    </div>
    <div class="gcal-dow" aria-hidden="true">${["T2", "T3", "T4", "T5", "T6", "T7", "CN"].map(x => `<span>${x}</span>`).join("")}</div>
    <div class="gcal-grid" id="gcal-grid" role="grid" aria-label="Lịch lặp — chấm tím là ngày việc sẽ xuất hiện">${cells}</div>
  </div>`;
}

function renderRecurrenceModal() {
  const rm = S.rm;
  if (!rm) return;
  const d = rm.draft;
  const err = rmDraftError();
  const base = splitISOLocal(rm.dueIso);
  const tdy = localISODate();
  const defUntil = addMonthsClampedISO(tdy, 1);
  const html = `
  <div class="rm-head">
    <h2><svg class="ic accent-ic"><use href="#i-repeat"/></svg>Lặp lại: “${esc(String(rm.title).slice(0, 60))}”</h2>
    <button class="icon-btn" data-close-modal="1" aria-label="Đóng" type="button"><svg class="ic"><use href="#i-x"/></svg></button>
  </div>
  <div class="rm-summary" id="rm-summary" aria-live="polite"><span class="rm-summary-main" id="rm-summary-main"></span><span class="rm-summary-count" id="rm-summary-count"></span></div>
  <div class="rm-body g-scroll">
    <div class="rm-block">
      <div class="rm-label">Tần suất</div>
      <div class="rm-seg" id="rm-freq" role="group" aria-label="Tần suất lặp">
        ${["Day", "Week", "Month", "Year"].map(f => `<button class="rm-seg-btn${f === d.freq ? " on" : ""}" data-freq="${f}" type="button" aria-pressed="${f === d.freq}">${RM_FREQ_LABEL[f]}</button>`).join("")}
      </div>
    </div>
    <div class="rm-block rm-interval-row">
      <div class="rm-label">Lặp mỗi</div>
      <div class="stepper">
        <button class="step-btn" id="rm-int-minus" type="button" aria-label="Giảm">−</button>
        <input class="step-input" id="rm-int" type="number" min="1" max="99" value="${d.interval}" inputmode="numeric" aria-label="Khoảng lặp">
        <button class="step-btn" id="rm-int-plus" type="button" aria-label="Tăng">+</button>
      </div>
      <span class="rm-unit">${RM_UNIT[d.freq]}</span>
    </div>
    ${d.freq === "Week" ? `
    <div class="rm-block">
      <div class="rm-label">Lặp vào <span class="rm-label-dim">(chọn ít nhất 1 thứ)</span></div>
      <div class="rm-dows" id="rm-dows">
        ${RM_WEEKDAYS.map(([lb, bit]) => `<button class="rm-dow${d.by_day & (1 << bit) ? " on" : ""}" data-bit="${bit}" type="button" aria-pressed="${!!(d.by_day & (1 << bit))}">${lb}</button>`).join("")}
      </div>
      ${rmWarningHtml(d)}
    </div>` : ""}
    ${(d.freq === "Month" || d.freq === "Year") ? rmMonthDayHtml(d, base) : ""}
    <div class="rm-block">
      <div class="rm-label">Lịch lặp <span class="rm-label-dim">(chấm tím = ngày việc xuất hiện${d.endsKind === "until" ? " — bấm vào ngày để đặt ngày kết thúc" : ""})</span></div>
      ${ghostCalendarHtml(rm)}
      <div class="rm-cal-foot"><span id="rm-count"></span></div>
    </div>
    <div class="rm-block">
      <div class="rm-label">Kết thúc</div>
      <label class="rm-radio"><input type="radio" name="rm-ends" value="never" ${d.endsKind === "never" ? "checked" : ""}> <span>Không bao giờ</span></label>
      <label class="rm-radio"><input type="radio" name="rm-ends" value="until" ${d.endsKind === "until" ? "checked" : ""}> <span>Đến ngày</span>
        <span class="rm-until-row">
          <input type="date" id="rm-until" class="rm-until-input" value="${esc(d.until || (d.endsKind === "until" ? defUntil : ""))}" min="${tdy}" aria-label="Ngày kết thúc">
          <span class="rm-chips">
            <button class="rm-chip" data-addmonths="1" type="button">+1 tháng</button>
            <button class="rm-chip" data-addmonths="3" type="button">+3 tháng</button>
            <button class="rm-chip" data-addmonths="6" type="button">+6 tháng</button>
            <button class="rm-chip" data-yearend="1" type="button">Cuối năm</button>
          </span>
        </span>
      </label>
      <label class="rm-radio"><input type="radio" name="rm-ends" value="after" ${d.endsKind === "after" ? "checked" : ""}> <span>Sau</span>
        <span class="stepper small">
          <button class="step-btn" id="rm-after-minus" type="button" aria-label="Giảm">−</button>
          <input class="step-input" id="rm-after" type="number" min="1" max="999" value="${d.afterTotal}" inputmode="numeric" aria-label="Số lần hoàn thành">
          <button class="step-btn" id="rm-after-plus" type="button" aria-label="Tăng">+</button>
        </span>
        <span>lần hoàn thành</span>
      </label>
    </div>
  </div>
  <div class="rm-foot">
    <div class="rm-error" id="rm-error" role="alert">${esc(err)}</div>
    <div class="rm-foot-btns">
      <button class="btn-cancel" data-close-modal="1" type="button">Hủy</button>
      <button class="btn-save" id="rm-save" type="button" ${err ? "disabled" : ""}><svg class="ic small"><use href="#i-repeat"/></svg>&nbsp;Lưu lặp lại</button>
    </div>
  </div>`;
  openModal(html);
  bindRecurrenceModal();
  updateLiveSummary(null);
  schedulePreview();
}

function bindRecurrenceModal() {
  const rm = S.rm;
  if (!rm) return;
  const d = rm.draft;
  const tdy = localISODate();
  const rerender = () => renderRecurrenceModal();

  $("#rm-freq").addEventListener("click", e => {
    const b = e.target.closest("[data-freq]");
    if (!b) return;
    d.freq = b.dataset.freq;
    rerender();
  });
  const clampInt = v => Math.max(1, Math.min(99, Number(v) || 1));
  $("#rm-int").addEventListener("change", e => { d.interval = clampInt(e.target.value); rerender(); });
  $("#rm-int-minus").addEventListener("click", () => { d.interval = clampInt((Number(d.interval) || 1) - 1); rerender(); });
  $("#rm-int-plus").addEventListener("click", () => { d.interval = clampInt((Number(d.interval) || 1) + 1); rerender(); });

  $("#rm-dows")?.addEventListener("click", e => {
    const b = e.target.closest("[data-bit]");
    if (!b) return;
    const bit = 1 << Number(b.dataset.bit);
    const cur = d.by_day || 0;
    d.by_day = (cur & bit) ? (cur & ~bit) : (cur | bit);
    rerender();
  });

  $("#rm-monthday")?.addEventListener("change", e => { d.month_day = Number(e.target.value); rerender(); });

  // ends radios
  $$('#modal input[name="rm-ends"]').forEach(radio => {
    radio.addEventListener("change", () => {
      d.endsKind = radio.value;
      if (d.endsKind === "until" && !d.until) d.until = addMonthsClampedISO(tdy, 1);
      rerender();
    });
  });
  $("#rm-until")?.addEventListener("change", e => { d.until = e.target.value; rerender(); });
  $$("#modal .rm-until-row .rm-chip[data-addmonths]").forEach(btn => {
    btn.addEventListener("click", () => { d.endsKind = "until"; d.until = addMonthsClampedISO(tdy, Number(btn.dataset.addmonths)); rerender(); });
  });
  $$("#modal .rm-until-row .rm-chip[data-yearend]").forEach(btn => {
    btn.addEventListener("click", () => { d.endsKind = "until"; d.until = `${tdy.slice(0, 4)}-12-31`; rerender(); });
  });
  const clampAfter = v => Math.max(1, Math.min(999, Number(v) || 1));
  $("#rm-after")?.addEventListener("change", e => { d.afterTotal = clampAfter(e.target.value); rerender(); });
  $("#rm-after-minus")?.addEventListener("click", () => { d.afterTotal = clampAfter(d.afterTotal - 1); rerender(); });
  $("#rm-after-plus")?.addEventListener("click", () => { d.afterTotal = clampAfter(d.afterTotal + 1); rerender(); });

  // ghost calendar nav
  $("#gcal-prev")?.addEventListener("click", () => {
    const t = new Date(rm.viewY, rm.viewM - 2, 1);
    rm.viewY = t.getFullYear(); rm.viewM = t.getMonth() + 1;
    rerender();
  });
  $("#gcal-next")?.addEventListener("click", () => {
    const t = new Date(rm.viewY, rm.viewM, 1);
    rm.viewY = t.getFullYear(); rm.viewM = t.getMonth() + 1;
    rerender();
  });
  const setUntilFromCell = iso => { if (d.endsKind === "until") { d.until = iso; rerender(); } };
  $("#gcal-grid")?.addEventListener("click", e => {
    const cell = e.target.closest(".gcal-cell");
    if (cell && cell.dataset.iso) setUntilFromCell(cell.dataset.iso);
  });
  $("#gcal-grid")?.addEventListener("keydown", e => {
    const cell = e.target.closest(".gcal-cell");
    if (!cell) return;
    const iso = cell.dataset.iso;
    const move = deltaDays => {
      e.preventDefault();
      const target = addDaysLocalISO(iso, deltaDays);
      const tCell = $(`#gcal-grid .gcal-cell[data-iso="${target}"]`);
      if (tCell) tCell.focus();
      else {
        // đi qua mốc tháng → đổi view rồi focus lại
        const t = splitISOLocal(target);
        rm.viewY = t.y; rm.viewM = t.m;
        rerender();
        setTimeout(() => $(`#gcal-grid .gcal-cell[data-iso="${target}"]`)?.focus(), 0);
      }
    };
    switch (e.key) {
      case "ArrowLeft": move(-1); break;
      case "ArrowRight": move(1); break;
      case "ArrowUp": move(-7); break;
      case "ArrowDown": move(7); break;
      case "Home": e.preventDefault(); move(-((new Date(splitISOLocal(iso).y, splitISOLocal(iso).m - 1, splitISOLocal(iso).d).getDay() + 6) % 7)); break;
      case "End": e.preventDefault(); { const wd = (new Date(splitISOLocal(iso).y, splitISOLocal(iso).m - 1, splitISOLocal(iso).d).getDay() + 6) % 7; move(6 - wd); break; }
      case "PageUp": e.preventDefault(); { const t = new Date(rm.viewY, rm.viewM - 2, 1); rm.viewY = t.getFullYear(); rm.viewM = t.getMonth() + 1; rerender(); break; }
      case "PageDown": e.preventDefault(); { const t = new Date(rm.viewY, rm.viewM, 1); rm.viewY = t.getFullYear(); rm.viewM = t.getMonth() + 1; rerender(); break; }
      case "Enter": case " ": e.preventDefault(); setUntilFromCell(iso); break;
    }
  });

  $("#rm-save").addEventListener("click", saveRecurrenceModal);
}

function schedulePreview() {
  const rm = S.rm;
  if (!rm) return;
  clearTimeout(rm.timer);
  rm.timer = setTimeout(fetchOccurrences, 120);
}

async function fetchOccurrences() {
  const rm = S.rm;
  if (!rm) return;
  const seq = ++rm.previewSeq;
  const d = rm.draft;
  const rule = rmRule();
  const withoutUntil = d.endsKind === "until" && !d.until;
  try {
    if (withoutUntil || (d.freq === "Week" && !d.by_day)) throw new Error("chưa đủ thông tin");
    const list = await invoke("preview_occurrences", { rule, from: rm.dueIso, max: 200 });
    if (!S.rm || S.rm.previewSeq !== seq) return;
    rm.occurrences = new Set(list || []);
    if (rm.dueIso) rm.occurrences.add(rm.dueIso);
    paintOccurrences();
    updateLiveSummary(rm.occurrences.size >= 200 ? 200 : rm.occurrences.size);
    const countEl = $("#rm-count");
    if (countEl) countEl.textContent = rm.occurrences.size >= 200 ? "≈ 200+ lần nữa trong 24 tháng tới" : `≈ ${rm.occurrences.size} lần nữa`;
  } catch (_) {
    if (!S.rm || S.rm.previewSeq !== seq) return;
    rm.occurrences = new Set(rm.dueIso ? [rm.dueIso] : []);
    paintOccurrences();
    updateLiveSummary(null);
    const countEl = $("#rm-count");
    if (countEl) countEl.textContent = "";
  }
}

function paintOccurrences() {
  const rm = S.rm;
  if (!rm) return;
  $$("#gcal-grid .gcal-cell").forEach(cell => {
    cell.classList.toggle("occ", rm.occurrences.has(cell.dataset.iso));
  });
}

function updateLiveSummary(count) {
  const rm = S.rm;
  if (!rm) return;
  const rule = rmRule();
  const s = summarizeRule(rule, rm.dueIso);
  const mainEl = $("#rm-summary-main");
  const countEl = $("#rm-summary-count");
  const d = rm.draft;
  if (mainEl) {
    let line = s ? s.main : "";
    if (d.endsKind === "until" && d.until) line += ` · đến ${viDayMonth(d.until)}`;
    else if (d.endsKind === "after") line += ` · tối đa ${Math.max(1, d.afterTotal)} lần`;
    mainEl.textContent = line;
  }
  if (countEl) countEl.textContent = count == null ? "" : count >= 200 ? "≈ 200+ lần nữa" : `≈ ${count} lần nữa`;
}

async function saveRecurrenceModal() {
  const rm = S.rm;
  if (!rm) return;
  const err = rmDraftError();
  if (err) {
    const errEl = $("#rm-error");
    if (errEl) errEl.textContent = err;
    return;
  }
  const rule = rmRule();
  if (rule.month_day === undefined) delete rule.month_day;
  try {
    const snap = await invoke("set_task_recurrence", { id: rm.taskId, rule });
    S.rm = null;
    closeModal();
    postSnap(snap);
  } catch (e) {
    const errEl = $("#rm-error");
    if (errEl) errEl.textContent = typeof e === "string" ? e : "Không lưu được — kiểm tra lại thiết lập";
  }
}
