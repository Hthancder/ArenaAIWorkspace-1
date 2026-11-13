/* Taskora — Sidebar / danh sách / chi tiết / palette / modal */
import { $, $$, addDaysLocalISO, esc, fmtViDate, fmtViTime, hi, invoke, localISODate, openModal, parseYmd, strip, viDayMonth, viDowShort, viFullDayMonth, viewWire } from "./dom.js";
import { F, S, VIEW_META, dueChip, dueDiffDays, isCompleted, isDeleted, repeatMeta, s_isAdhd, subtaskMeta, summarizeRule, tagsMeta, taskById, viewKey } from "./state.js";
import { notify } from "./notify.js";
import { renderStats } from "./stats.js";
import { refreshStoragePanel } from "./settings.js";
import { openRecurrenceModal } from "./recurrence.js";
import { openBrainDump, renderNextUp } from "./adhd.js";
import { go } from "./snapshot.js";


/* ─────────── SIDEBAR ─────────── */
export const LIST_DOT_FALLBACK = "#6366f1";
export function renderSidebar() {
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

export function renderCounts() {
  const c = S.snap.counts;
  $("#sb-active").textContent = `${c.active} đang làm`;
  $("#sb-overdue-wrap").hidden = c.overdue === 0;
  $("#sb-overdue").textContent = `${c.overdue} quá hạn`;
  const total = c.today + c.done_today;
  $("#sb-today").textContent = `${c.done_today}/${total} hôm nay`;
  $("#active-count").textContent = `${c.active} việc đang làm`;
}

export function crumbFor(view) {
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

export function renderViewHead() {
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

export function setCrumb(icon, title, count) {
  $("#crumb-use").setAttribute("href", "#i-" + icon);
  $("#crumb-text").textContent = title;
  const pill = $("#crumb-count");
  pill.textContent = count;
  pill.hidden = count === "" || count == null;
}

export function setView(view) {
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
export function agendaHtml(tasks, q) {
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

export async function renderTaskList() {
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

export function rowHtml(t, q, opts = {}) {
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

export function updateBulkUI() {
  const bulk = S.bulk;
  $("#toolbar").style.display = bulk ? "none" : "";
  $("#bulkbar").hidden = !bulk;
  $("#bulk-count").textContent = `${S.bulkSel.size} đã chọn`;
  $$(".bulk-box").forEach(el => el.classList.toggle("bulk-on", S.bulkSel.has(Number(el.dataset.bulkbox))));
  $$(".task-row[data-id]").forEach(el => el.classList.toggle("bulk-sel", bulk && S.bulkSel.has(Number(el.dataset.id))));
}

export function selectTask(id, { openDetail = true } = {}) {
  S.selected = id;
  $$(".task-row[data-id]").forEach(el => el.classList.toggle("selected", Number(el.dataset.id) === id));
  if (openDetail) $("#detail").classList.add("open");
  renderDetail();
}

/* ─────────── DETAIL PANEL ─────────── */
export function renderDetail() {
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

/* ─────────── CONTEXT MENU ─────────── */
export let ctxFor = null;
export function closeCtxMenu() { $("#ctx-menu").hidden = true; ctxFor = null; }
export function openCtxMenu(html, x, y) {
  const menu = $("#ctx-menu");
  menu.innerHTML = html;
  menu.hidden = false;
  const rect = menu.getBoundingClientRect();
  menu.style.left = Math.min(x, window.innerWidth - rect.width - 10) + "px";
  menu.style.top = Math.min(y, window.innerHeight - rect.height - 10) + "px";
}
export function taskCtxItems(t) {
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

export function openListDialog(editing) {
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
export const LIST_PALETTE_JS = [[99,102,241],[16,185,129],[245,158,11],[239,68,68],[14,165,233],[168,85,247],[236,72,153],[107,114,128]];

export async function openBackups() {
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
export function openConfirmEmptyTrash() {
  const n = S.snap.counts.trash;
  if (n === 0) { notify({ kind: "info", title: "Thùng rác đã trống", sound: "none" }); return; }
  openModal(`<h2><svg class="ic danger"><use href="#i-warning"/></svg>Xóa vĩnh viễn ${n} việc?</h2>
    <p>Toàn bộ việc trong thùng rác sẽ bị xóa vĩnh viễn, không thể hoàn tác bằng Ctrl+Z sau khi xác nhận.</p>
    <div class="modal-actions"><button class="btn-cancel" data-close-modal="1">Hủy</button><button class="btn-danger" id="confirm-empty-trash">Xóa vĩnh viễn</button></div>`);
}
export function openHelp() {
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
export function openAbout() {
  openModal(`<div class="about-center"><img class="about-logo" src="assets/logo.png" alt="Taskora" />
      <h2 style="justify-content:center">Taskora <span style="color:var(--text-faint);font-weight:500">v2.11.1</span></h2>
      <p>Quản lý công việc cho Windows — nhẹ, nhanh, đẹp.<br>Viết bằng Rust + Tauri, giao diện liquid glass.</p>
      <p>Font <strong>Be Vietnam Pro</strong> (OFL) · Icon <strong>Phosphor</strong> (MIT)</p>
      <p style="color:var(--text-faint)">MIT License © Hthancder</p>
    </div>
    <div class="modal-actions"><button class="btn-save" data-close-modal="1">Đóng</button></div>`);
}

/* ─────────── COMMAND PALETTE ─────────── */
export const PALETTE_ACTIONS = [
  { icon: "tray", label: "Đi tới: Hộp thư", hint: "Ctrl+1", run: () => setView({ type: "inbox" }) },
  { icon: "calendar-check", label: "Đi tới: Hôm nay", hint: "Ctrl+2", run: () => setView({ type: "today" }) },
  { icon: "calendar-blank", label: "Đi tới: Sắp tới", hint: "Ctrl+3", run: () => setView({ type: "upcoming" }) },
  { icon: "star", label: "Đi tới: Đã ghim", hint: "Ctrl+4", run: () => setView({ type: "starred" }) },
  { icon: "check-circle", label: "Đi tới: Đã hoàn thành", hint: "Ctrl+5", run: () => setView({ type: "completed" }) },
  { icon: "trash", label: "Đi tới: Thùng rác", hint: "Ctrl+6", run: () => setView({ type: "trash" }) },
  { icon: "chart-bar", label: "Đi tới: Thống kê", hint: "Ctrl+7", run: () => setView({ type: "stats" }) },
  { icon: "gear", label: "Đi tới: Cài đặt", hint: "Ctrl+8", run: () => setView({ type: "settings" }) },
  { icon: "repeat", label: "Lặp lại… (việc đang chọn)", hint: "", run: () => { if (S.selected != null) openRecurrenceModal(S.selected); else notify({ kind: "info", title: "Chọn một việc trước đã", sound: "none" }); } },
  { icon: "clock", label: "Mở cửa sổ đồng hồ", hint: "", run: () => invoke("focus_open_timer").catch(e => { const msg = typeof e === "string" ? e : (e && (e.message || e.toString())) || "không rõ lý do"; notify({ kind: "error", title: "Không mở được cửa sổ Đồng hồ", body: msg }); }) },
  { icon: "note-pencil", label: "Brain-dump — đổ việc nhanh", hint: "Ctrl+Shift+N", run: openBrainDump },
  { icon: "plus", label: "Thêm việc mới", hint: "Ctrl+N", run: () => { setView(S.view.type === "stats" || S.view.type === "trash" || S.view.type === "completed" ? { type: "inbox" } : S.view); setTimeout(() => $("#quickadd-input").focus(), 60); } },
  { icon: "sun", label: "Bật/tắt giao diện tối–sáng", hint: "Ctrl+D", run: () => go(invoke("toggle_dark")) },
  { icon: "archive", label: "Xuất bản sao lưu", hint: "", run: async () => { try { const name = await invoke("export_backup"); notify({ kind: "info", title: "Đã xuất " + name, sound: "none" }); } catch (e) { notify({ kind: "error", title: "Xuất thất bại" }); } } },
  { icon: "arrow-counter-clockwise", label: "Khôi phục từ bản sao lưu…", hint: "", run: openBackups },
  { icon: "folder", label: "Mở thư mục dữ liệu", hint: "", run: () => invoke("open_data_dir") },
  { icon: "keyboard", label: "Xem phím tắt", hint: "", run: openHelp },
];
export function openPalette() {
  const p = $("#palette");
  p.hidden = false;
  $("#palette-input").value = "";
  S.paletteIdx = 0;
  renderPalette("");
  setTimeout(() => $("#palette-input").focus(), 30);
}
export function closePalette() { $("#palette").hidden = true; }
export function renderPalette(query) {
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
export function runPaletteItem(i) {
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
