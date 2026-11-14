/* Taskora — Lặp lại hạng nhất: modal quy tắc + xem trước */
import { $, $$, addDaysLocalISO, closeModal, esc, hi, invoke, localISODate, makeISOLocal, openModal, splitISOLocal, viDayMonth, viFullDayMonth } from "./dom.js";
import { S, summarizeRule, taskById } from "./state.js";
import { postSnap } from "./snapshot.js";


/* ─────────── modal Lặp lại (v2.9.0) — ghost calendar, until/after, preview từ Rust ─────────── */
export const RM_WEEKDAYS = [["T2", 0], ["T3", 1], ["T4", 2], ["T5", 3], ["T6", 4], ["T7", 5], ["CN", 6]];
export const RM_UNIT = { Day: "ngày", Week: "tuần", Month: "tháng", Year: "năm" };
export const RM_FREQ_LABEL = { Day: "Ngày", Week: "Tuần", Month: "Tháng", Year: "Năm" };

/** ISO cộng n tháng, kẹp theo ngày cuối tháng (an toàn trong JS, chỉ hiển thị/đặt until). */
export function addMonthsClampedISO(iso, n) {
  const { y, m, d } = splitISOLocal(iso);
  const total = y * 12 + (m - 1) + n;
  const ty = Math.floor(total / 12), tm = ((total % 12) + 12) % 12;
  const dim = new Date(ty, tm + 1, 0).getDate();
  return makeISOLocal(ty, tm, Math.min(d, dim));
}

export function openRecurrenceModal(taskId) {
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

export function rmDraftError() {
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
export function rmRule() {
  const d = S.rm.draft;
  const rule = { freq: d.freq, interval: Math.max(1, Math.min(99, Number(d.interval) || 1)) };
  if (d.freq === "Week") rule.by_day = d.by_day == null ? 0 : d.by_day;
  if (d.freq === "Month" || d.freq === "Year") rule.month_day = d.month_day == null ? undefined : d.month_day;
  if (d.endsKind === "until") rule.ends = d.until ? { kind: "until", date: d.until } : { kind: "never" };
  else if (d.endsKind === "after") rule.ends = { kind: "after", total: Math.max(1, Number(d.afterTotal) || 1), done: d.afterDone || 0 };
  else rule.ends = { kind: "never" };
  return rule;
}

export function rmWarningHtml(d) {
  if (d.freq !== "Week" || !d.by_day || !S.rm?.dueIso) return "";
  const { y, m, d: dd } = splitISOLocal(S.rm.dueIso);
  const bit = (new Date(y, m - 1, dd).getDay() + 6) % 7; // JS 0=CN → bit0=T2
  if (d.by_day & (1 << bit)) return "";
  const name = ["Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy", "Chủ Nhật"][bit];
  return `<div class="rm-warn">Lần hiện tại (${name}) không nằm trong lịch lặp — chuỗi bắt đầu từ lần sau.</div>`;
}

export function rmMonthDayHtml(d, base) {
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

export function ghostCalendarHtml(rm) {
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

export function renderRecurrenceModal() {
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

export function bindRecurrenceModal() {
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

export function schedulePreview() {
  const rm = S.rm;
  if (!rm) return;
  clearTimeout(rm.timer);
  rm.timer = setTimeout(fetchOccurrences, 120);
}

export async function fetchOccurrences() {
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

export function paintOccurrences() {
  const rm = S.rm;
  if (!rm) return;
  $$("#gcal-grid .gcal-cell").forEach(cell => {
    cell.classList.toggle("occ", rm.occurrences.has(cell.dataset.iso));
  });
}

export function updateLiveSummary(count) {
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

export async function saveRecurrenceModal() {
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
