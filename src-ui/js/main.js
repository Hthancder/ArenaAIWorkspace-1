/* Taskora — bootstrap: bindEvents, phím tắt, INIT */
import { $, $$, closeModal, esc, invoke, isTyping, openModal, parseYmd, viewWire } from "./dom.js";
import { F, REPEAT_LABELS, S, isCompleted, isDeleted, parseViewKey, summarizeRuleLine, taskById, viewKey } from "./state.js";
import { notify } from "./notify.js";
import { bindSettingsEvents, checkStoragePrompts, initSettingsAccordion, openStorageConfirm, patchSettings, pickFolder, refreshOsTransparency, refreshStoragePanel, runStorageImportOrphan, runStorageMergeLegacy, runStorageSwitch } from "./settings.js";
import { closeCtxMenu, closePalette, ctxFor, openAbout, openBackups, openConfirmEmptyTrash, openCtxMenu, openHelp, openListDialog, openPalette, renderPalette, renderTaskList, runPaletteItem, selectTask, setView, taskCtxItems, updateBulkUI } from "./tasks.js";
import { openRecurrenceModal } from "./recurrence.js";
import { applyFocusPayload, focusReset, focusStop, focusTickStart, focusTogglePause } from "./focus.js";
import { bindAdhd, openBrainDump, openPurgeConfirm, wireSplitSuggest } from "./adhd.js";
import { go, postSnap, refresh } from "./snapshot.js";


/* ─────────── QUICK ADD + PREVIEW ─────────── */
export function updateQaPreview() {
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

export async function submitQuick() {
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
    notify({ kind: "error", title: typeof e === "string" ? e : "Không thêm được việc" });
  }
}

/* ─────────── SỰ KIỆN TOÀN CỤC ─────────── */
export function bindEvents() {
  bindAdhd();
  initSettingsAccordion();
  /* chip phiên trên topbar — bấm = hiện cửa sổ Đồng hồ */
  $("#focus-chip")?.addEventListener("click", () => {
    invoke("focus_open_timer").catch(e => {
      const msg = typeof e === "string" ? e : (e && (e.message || e.toString())) || "không rõ lý do";
      notify({ kind: "error", title: "Không mở được cửa sổ Đồng hồ", body: msg });
    });
  });
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
    if (k === "export") { try { const name = await invoke("export_backup"); notify({ kind: "info", title: "Đã xuất " + name, sound: "none" }); } catch (err) { notify({ kind: "error", title: "Xuất thất bại" }); } }
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

  bindSettingsEvents();

  $("#modal").addEventListener("click", async e => {
    if (e.target.closest("[data-close-modal]")) { closeModal(); if ($("#view-settings")?.classList.contains("active")) refreshStoragePanel(); return; }
    if (e.target.closest("#list-save")) {
      const name = ($("#list-name")?.value || "").trim();
      if (!name) { notify({ kind: "error", title: "Nhập tên danh sách" }); return; }
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
        notify({ kind: "info", title: "Đã bật Transparency effects", body: "Acrylic đang hoạt động", sound: "none" });
      } catch (err) { notify({ kind: "error", title: String(err && err.message ? err.message : err) }); }
      return;
    }
    const osDecline = e.target.closest("#os-tr-decline");
    if (osDecline) {
      closeModal();
      patchSettings({ transparent: false }); // từ chối → tuyệt đối không dùng nền trong suốt
      notify({ kind: "info", title: "Taskora giữ nền đặc", body: "Bật lại bất cứ lúc nào trong Cài đặt → Giao diện.", sound: "none" });
      return;
    }
    const confirmReset = e.target.closest("#confirm-reset-settings");
    if (confirmReset) { closeModal(); go(invoke("reset_settings")); return; }
    const browseBtn = e.target.closest("#storage-custom-browse");
    if (browseBtn) {
      const picked = await pickFolder();
      if (picked) { const inp = $("#storage-custom-input"); if (inp) inp.value = picked; }
      else notify({ kind: "error", title: "Không mở được hộp chọn thư mục", body: "Hãy nhập đường dẫn" });
      return;
    }
    const customNext = e.target.closest("#storage-custom-next");
    if (customNext) {
      const p = ($("#storage-custom-input")?.value || "").trim();
      if (!p) { notify({ kind: "error", title: "Nhập đường dẫn thư mục" }); return; }
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
    if (exportBtn) { try { const name = await invoke("export_backup"); notify({ kind: "info", title: "Đã xuất " + name, sound: "none" }); } catch (err) { notify({ kind: "error", title: "Xuất thất bại" }); } return; }
    const restoreBtn = e.target.closest("[data-restore-backup]");
    if (restoreBtn) {
      closeModal();
      try { postSnap(await invoke("import_backup", { name: restoreBtn.dataset.restoreBackup })); }
      catch (err) { notify({ kind: "error", title: typeof err === "string" ? err : "Khôi phục thất bại" }); }
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
export function globalKeys(e) {
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
    if (S.tag || S.prio) { S.tag = null; S.prio = null; $("#tag-chip").hidden = true; $$("#prio-filter .prio-chip").forEach(x => x.classList.remove("on")); $("#prio-clear").hidden = true; renderTaskList(); notify({ kind: "info", title: "Đã bỏ bộ lọc", sound: "none" }); return; }
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
