/* Taskora — Thống kê */
import { $, esc, invoke } from "./dom.js";
import { notify } from "./notify.js";


/* ─────────── STATS VIEW ─────────── */
export async function renderStats(force) {
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
    notify({ kind: "error", title: "Không tải được thống kê" });
  }
}
