/* Taskora — state dùng chung toàn app (singleton) */
import { esc, parseYmd, splitISOLocal, viDayMonth } from "./dom.js";

export const F = { active: false, mode: "focus", taskId: null, taskTitle: "", totalSecs: 1500, endsAtMs: null, remainingSecs: 1500, paused: false, phaseDone: false, cycleCount: 0, nextBreakLong: false, soundOn: true, chime: "soft", timer: null, eyeShown: false, completing: false, breakDoneFlag: false };
export const ADHD_QA = ["Chỉ cần 1 việc nhỏ nhất thôi…", "Viết 1 dòng — cứ ngắn và xấu cũng được", "Việc 2 phút cũng đáng kể", "Ném vào đây rồi tính sau"];
export const ADHD_PRAISE = ["Xong rồi! Một điểm cộng nữa ✦", "Tốt! Bạn đang lấy đà.", "Thêm một việc được xử đẹp.", "Đã xong — thưởng cho mình một hơi thở sâu.", "Tuyệt, việc tiếp theo thôi."];
const pick = arr => arr[Math.floor(Math.random() * arr.length)];


export const S = {
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


export const VIEW_META = {
  inbox: { icon: "tray", title: "Hộp thư", sub: "Việc chưa phân vào danh sách nào" },
  today: { icon: "calendar-check", title: "Hôm nay", sub: "Đến hạn hôm nay và các việc quá hạn" },
  upcoming: { icon: "calendar-blank", title: "Sắp tới", sub: "Việc đã đặt hạn chót trong tương lai" },
  starred: { icon: "star", title: "Đã ghim", sub: "Những việc bạn đang ưu tiên" },
  completed: { icon: "check-circle", title: "Đã hoàn thành", sub: "Việc đã xong — bấm để mở lại nếu cần" },
  trash: { icon: "trash", title: "Thùng rác", sub: "Việc đã xóa — khôi phục hoặc xóa vĩnh viễn" },
  stats: { icon: "chart-bar", title: "Thống kê", sub: "Bức tranh hoạt động của bạn" },
  settings: { icon: "gear", title: "Cài đặt", sub: "Tùy chỉnh giao diện, hành vi và dữ liệu" },
};
export const PRIO_LABEL = { P1: "P1", P2: "P2", P3: "P3", P4: "P4" };

/* ─────────── tiện ích ─────────── */

export const taskById = id => (S.snap.tasks || []).find(t => t.id === id);
export const isCompleted = t => !!t.completed_at;
export const isDeleted = t => !!t.deleted_at;
export const isActive = t => !isCompleted(t) && !isDeleted(t);

export function dueDiffDays(due) { // số ngày so với hôm nay (+ tương lai / - quá khứ)
  if (!due || !S.snap) return null;
  return Math.round((parseYmd(due.slice(0, 10)) - parseYmd(S.snap.today)) / 86400000);
}
export function dueChip(t) {
  if (!t.due) return "";
  const diff = dueDiffDays(t.due);
  const [, m, d] = t.due.slice(0, 10).split("-").map(Number);
  const md = d.toString().padStart(2, "0") + "/" + m.toString().padStart(2, "0");
  if (diff < 0) return `<span class="meta-chip due-overdue"><svg class="ic"><use href="#i-warning"/></svg>${md} · quá hạn ${-diff} ngày</span>`;
  if (diff === 0) return `<span class="meta-chip due-today"><svg class="ic"><use href="#i-calendar-check"/></svg>Hôm nay</span>`;
  if (diff === 1) return `<span class="meta-chip due-upcoming"><svg class="ic"><use href="#i-calendar-blank"/></svg>Mai · ${md}</span>`;
  return `<span class="meta-chip due-upcoming"><svg class="ic"><use href="#i-calendar"/></svg>${md}</span>`;
}
export function subtaskMeta(t) {
  const n = (t.subtasks || []).length;
  if (!n) return "";
  const done = t.subtasks.filter(s => s.done).length;
  const pct = Math.round((done / n) * 100);
  return `<span class="subtask-mini"><svg class="ic"><use href="#i-list-checks"/></svg>${done}/${n}<span class="mini-track"><span class="mini-fill" style="width:${pct}%"></span></span></span>`;
}
export const REPEAT_LABELS = { Daily: "Hàng ngày", Weekdays: "T2–T6", Weekly: "Hàng tuần", Monthly: "Hàng tháng" };
export const VI_DOW_SHORT = ["CN", "T2", "T3", "T4", "T5", "T6", "T7"]; // Date.getDay(): 0=CN
export const VI_DOW_FULL = ["Chủ Nhật", "Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy"];


export const DOW_LETTERS = ["T2", "T3", "T4", "T5", "T6", "T7", "CN"]; // bit0..bit6 (Mon..Sun)
export const WD_WEEKDAYS_MASK = 0b0011111;

export function ruleDowLetters(mask) {
  const out = [];
  for (let b = 0; b < 7; b++) if (mask & (1 << b)) out.push(DOW_LETTERS[b]);
  return out;
}

/** Tóm tắt rule cho UI (hiển thị, không phải thuật toán). Trả {main, endTxt} hoặc null. */
export function summarizeRule(rule, dueIso) {
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
export function summarizeRuleLine(rule, dueIso) {
  const s = summarizeRule(rule, dueIso);
  if (!s) return "";
  return s.endTxt ? `${s.main} · ${s.endTxt}` : s.main;
}

export function repeatMeta(t) {
  if (t.recurrence) {
    const line = summarizeRuleLine(t.recurrence, t.due);
    return `<span class="meta-chip repeat-chip"><svg class="ic"><use href="#i-repeat"/></svg>${esc(line)}</span>`;
  }
  if (!t.repeat || t.repeat === "None") return "";
  return `<span class="meta-chip repeat-chip"><svg class="ic"><use href="#i-repeat"/></svg>Lặp: ${REPEAT_LABELS[t.repeat] || t.repeat}</span>`;
}
export function tagsMeta(t) {
  return (t.tags || []).slice(0, 4).map(g => `<span class="meta-tag">#${esc(g)}</span>`).join("");
}

/* ─────────── thông báo + lưu snapshot ─────────── */

/* Đồng hồ hiển thị ở đâu — suy từ focus_clock_display; legacy: focus_auto_open_timer=false ⇒ overlay */
export function clockDisplay() {
  const st = S.snap && S.snap.settings ? S.snap.settings : {};
  const cd = st.focus_clock_display;
  if (cd === "window" || cd === "overlay" || cd === "both") return cd;
  return st.focus_auto_open_timer === false ? "overlay" : "window";
}
export const s_isAdhd = () => !!(S.snap && S.snap.settings && S.snap.settings.adhd_mode);
export const adhdHm = () => new Date().toLocaleTimeString("vi-VN", { hour: "2-digit", minute: "2-digit" });
export const CIRC = 2 * Math.PI * 52;

export function viewKey(v) { return v.type === "list" ? `list:${v.id}` : v.type; }
export function parseViewKey(k) {
  if (!k) return null;
  if (k.startsWith("list:")) { const id = Number(k.slice(5)); return Number.isFinite(id) ? { type: "list", id } : null; }
  return ["inbox", "today", "upcoming", "starred", "completed", "trash", "stats", "settings"].includes(k) ? { type: k } : null;
}
