/* Taskora — Hậu xử lý snapshot + điều hướng dữ liệu (go/refresh) */
import { $, hi, invoke, localISODate, pick } from "./dom.js";
import { ADHD_PRAISE, F, S } from "./state.js";
import { notify } from "./notify.js";
import { confettiBurst } from "./fx.js";
import { renderStats } from "./stats.js";
import { applyAccent, covOf } from "./accent.js";
import { applyTheme, markTransparencyChecked, refreshFxStatus, syncAutostartControl, syncSettingsControls } from "./settings.js";
import { renderCounts, renderDetail, renderSidebar, renderTaskList, renderViewHead, setView } from "./tasks.js";
import { focusStop, renderFocus } from "./focus.js";
import { setupAdhdPlaceholder, startAdhdClock, stopAdhdClock } from "./adhd.js";

export let remindShown = false;

/* Hậu xử lý sau MỖI lần snapshot (kể cả từ IPC bất kỳ) */
export function postSnap(snap) {
  S.snap = snap;
  const s = snap;
  if (s.flash) notify({ kind: "info", title: "Đã đổi", body: s.flash, sound: "none", actions: s.undo_len ? [{ label: "Hoàn tác", onClick: () => go(invoke("undo")) }] : [] });
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
  syncAutostartControl();
  refreshFxStatus();
  if (markTransparencyChecked()) {
    (async () => {
      try {
        const os = await invoke("transparency_status");
        if (os.supported && os.enabled === false && S.snap && S.snap.settings.transparent) {
          go(invoke("update_settings", { patch: { transparent: false } }));
          notify({ kind: "info", title: "Transparency effects đang TẮT", body: "Taskora chuyển nền đặc. Bật lại trong Cài đặt → Giao diện để dùng trong suốt.", sound: "none" });
        }
      } catch { /* không đọc được → giữ nguyên lựa chọn của người dùng */ }
    })();
  }
  // tóm tắt khi mở app — mỗi loại tối đa 1 lần/ngày (stamp localStorage), bấm để xem
  if (!remindShown) {
    const todayYmd = s.today || localISODate();
    let stamp = null;
    try { stamp = localStorage.getItem("taskora.launchSummaryDate"); } catch { /* chế độ không có localStorage */ }
    if (stamp !== todayYmd) {
      remindShown = true;
      try { localStorage.setItem("taskora.launchSummaryDate", todayYmd); } catch { /* ignore */ }
      const todayN = (s.counts && s.counts.today) || 0;
      const overdueN = (s.counts && s.counts.overdue) || 0;
      if (todayN > 0 || overdueN > 0) {
        setTimeout(() => {
          if (todayN > 0) notify({ kind: "due_today", title: `Hôm nay bạn có ${todayN} việc đến hạn`, actions: [{ label: "Xem hôm nay", onClick: () => setView({ type: "today" }) }] });
          else notify({ kind: "overdue", title: `${overdueN} việc quá hạn`, body: "Việc lỡ hẹn — bấm để xem và dời hạn", actions: [{ label: "Xem quá hạn", onClick: () => setView({ type: "today" }) }] });
        }, 650);
      }
    }
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
          notify({ kind: "info", title: pick(ADHD_PRAISE) });
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
  if (F.active || F.phaseDone) renderFocus();
  // cửa sổ title cũng được backend cập nhật sẵn
}

export async function refresh() {
  const snap = await invoke("snapshot");
  postSnap(snap);
}
export async function go(promise) {
  try { postSnap(await promise); }
  catch (e) { notify({ kind: "error", title: typeof e === "string" ? e : "Có lỗi xảy ra" }); }
}
