/* Taskora — Chế độ ADHD: hero, nächste bước, brain-dump, chia nhỏ */
import { $, closeModal, esc, hi, invoke, openModal, strip, viewWire } from "./dom.js";
import { ADHD_QA, F, S, adhdHm, dueChip, isCompleted, isDeleted, repeatMeta, s_isAdhd, subtaskMeta, tagsMeta, taskById } from "./state.js";
import { notify } from "./notify.js";
import { confettiBurst } from "./fx.js";
import { focusBreakStart, focusRemainingNow, focusReset, focusStart, focusStop, focusTogglePause } from "./focus.js";
import { go, postSnap } from "./snapshot.js";

export let qaTimer = null, qaIdx = 0;

export function setupAdhdPlaceholder() {
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

export function nextAdhdTask() {
  if (!["inbox", "today", "upcoming", "starred", "list"].includes(S.view.type)) return null;
  for (const id of S.visibleIds) {
    const t = taskById(id);
    if (t && !isCompleted(t) && !isDeleted(t)) return t;
  }
  return null;
}

/* CTA của hero theo trạng thái phiên — đang chạy chỉ còn tĩnh + lối tắt mở Đồng hồ (spec A.2.6) */
function focusCtaHtml() {
  const focusMin = (S.snap && S.snap.settings && S.snap.settings.focus_min) || 25;
  if (F.active || F.phaseDone) {
    if (F.phaseDone) return `<span class="adhd-cta is-running" aria-disabled="true"><svg class="ic"><use href="#i-check-circle"/></svg>Xong phiên — nghỉ chút</span>`;
    const rem = focusRemainingNow();
    const mm = Math.floor(rem / 60), ss = String(Math.floor(rem % 60)).padStart(2, "0");
    return `<span class="adhd-cta is-running" aria-disabled="true"><svg class="ic"><use href="#i-clock"/></svg>Đang tập trung · <span id="adhd-hero-timer">${mm}:${ss}</span></span>
      <button class="btn-adhd-open" data-adhd-open-timer="1" type="button"><svg class="ic"><use href="#i-arrows-out"/></svg>Mở đồng hồ</button>`;
  }
  const t = nextAdhdTask();
  return `<button class="adhd-cta" data-adhd-focus="${t ? t.id : ""}"><svg class="ic"><use href="#i-clock"/></svg>Tập trung ${focusMin} phút</button>`;
}

export function renderNextUp() {
  const el = $("#adhd-next");
  if (!el) return;
  if (!s_isAdhd() || !["inbox", "today", "upcoming", "starred", "list"].includes(S.view.type)) { el.hidden = true; return; }
  const doneToday = (S.snap && S.snap.counts && S.snap.counts.done_today) || 0;
  const focusToday = (S.snap && S.snap.counts && S.snap.counts.focus_today) || 0;
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
      ${focusCtaHtml()}
      <button class="btn-adhd-done xl" data-adhd-done="${t.id}" title="Xong luôn việc này"><svg class="ic"><use href="#i-check"/></svg>Xong</button>
    </div>
    <div class="adhd-done-line"><svg class="ic tiny"><use href="#i-check-circle"/></svg><span>Hôm nay đã xong <b>${doneToday}</b> việc${focusSuffix}</span></div>`;
  startAdhdClock();
}

export function bindAdhd() {
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
      if (rows.children.length >= 12) { notify({ kind: "error", title: "Tối đa 12 bước nhỏ" }); return; }
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
        if (deleted) notify({ kind: "info", title: `Đã xóa mẫu “${deleted.name}”`, sound: "none", actions: [{ label: "Hoàn tác", onClick: () => { go(invoke("save_step_preset", { name: deleted.name, steps: deleted.steps.slice() })).then(() => t && renderSplitSuggest(splitRows(box) || [])); } }] });
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
      if (!name) { notify({ kind: "error", title: "Đặt tên cho mẫu đã" }); return; }
      if (!steps.length) { notify({ kind: "error", title: "Mẫu phải có ít nhất 1 bước" }); return; }
      go(invoke("save_step_preset", { name, steps })).then(() => renderSplitSuggest(steps));
      return;
    }

    if (e.target.closest("#split-add") && t) {
      const titles = splitRows(box);
      if (!titles.length) { notify({ kind: "error", title: "Ít nhất 1 bước nhỏ" }); return; }
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
    const ot = e.target.closest("[data-adhd-open-timer]");
    if (ot) {
      invoke("focus_open_timer").catch(err => {
        const msg = typeof err === "string" ? err : (err && (err.message || err.toString())) || "không rõ lý do";
        notify({ kind: "error", title: "Không mở được cửa sổ Đồng hồ", body: msg });
      });
      return;
    }
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
    notify({ kind: "error", title: "Không mở được cửa sổ Đồng hồ", body: msg });
  }));
  $("#focus-stop")?.addEventListener("click", focusStop);
  $("#focus-break")?.addEventListener("click", focusBreakStart);
  $("#focus-next")?.addEventListener("click", focusStop);
}

/* ĐỒNG HỒ LIVE (mỏ neo thời gian — chống time blindness) */
export let clockTimer = null;
export function startAdhdClock() {
  if (clockTimer) return;
  const tick = () => {
    const now = new Date();
    const hm = now.toLocaleTimeString("vi-VN", { hour: "2-digit", minute: "2-digit" });
    const el = $("#adhd-clock"); if (el) el.textContent = hm;
    const fn = $("#focus-now"); if (fn && F.active) fn.textContent = `Bây giờ là ${hm}`;
    if (F.active) {
      const ht = $("#adhd-hero-timer");
      if (ht) { const rem = focusRemainingNow(); ht.textContent = `${Math.floor(rem / 60)}:${String(Math.floor(rem % 60)).padStart(2, "0")}`; }
    }
  };
  tick();
  clockTimer = setInterval(tick, 1000);
}
export function stopAdhdClock() { clearInterval(clockTimer); clockTimer = null; }

/* Brain-dump — mỗi dòng một việc, parse chung parser quick-add */
export function openBrainDump() {
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
    if (!n) { notify({ kind: "error", title: "Chưa có gì để đổ ra", body: "Viết mỗi dòng một việc" }); return; }
    try {
      const snap = await invoke("brain_dump", { input, view: viewWire(S.view) });
      closeModal();
      postSnap(snap);
      if (S.snap.settings.adhd_mode) confettiBurst(window.innerWidth / 2, window.innerHeight / 2 - 60);
    } catch (e) { notify({ kind: "error", title: String(e) }); }
  });
}

/* Hộp xác nhận xóa vĩnh viễn (dùng chung: detail + menu chuột phải + nút hàng) */
export function openPurgeConfirm(task) {
  openModal(`<h2><svg class="ic danger"><use href="#i-warning"/></svg>Xóa vĩnh viễn?</h2>
    <p>“${esc(task.title)}” sẽ bị xóa khỏi thùng rác. Vẫn có thể bấm <strong>Ctrl+Z</strong> ngay sau đó để lấy lại — nhưng đừng tin vào may mắn.</p>
    <div class="modal-actions"><button class="btn-cancel" data-close-modal="1">Hủy</button><button class="btn-danger" id="confirm-purge" data-id="${task.id}">Xóa vĩnh viễn</button></div>`);
}

/* Chia nhỏ việc — từ điển pattern cục bộ (KHÔNG AI) + mẫu riêng của người dùng */
export function splitSteps(title) {
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

export const splitRowHtml = (text, idx) => `<div class="split-row"><span class="split-num">${idx + 1}</span><input type="text" class="split-suggest-input" value="${esc(text)}" maxlength="140" autocomplete="off" spellcheck="false" /><button class="split-row-del" type="button" title="Bỏ bước này"><svg class="ic tiny"><use href="#i-x"/></svg></button></div>`;
export const splitRows = box => [...box.querySelectorAll(".split-suggest-input")].map(i => i.value.trim()).filter(Boolean);

export function renderSplitSuggest(steps) {
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

export function renumberSplitRows(box) {
  const inputs = [...box.querySelectorAll(".split-row")];
  inputs.forEach((row, i) => { const n = row.querySelector(".split-num"); if (n) n.textContent = String(i + 1); });
  const save = box.querySelector("#split-add");
  if (save) save.textContent = `Thêm ${splitRows(box).length} bước nhỏ này`;
}

export function wireSplitSuggest(task) {
  renderSplitSuggest(splitSteps(task.title).slice());
}
