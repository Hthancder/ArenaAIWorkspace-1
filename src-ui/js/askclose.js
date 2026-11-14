/* Taskora — hỏi khi đóng cửa sổ chính ("Đóng Taskora?") + cầu nối sự kiện khay (v2.12.0) */
import { $, closeModal, invoke, openModal } from "./dom.js";
import { S } from "./state.js";
import { notify } from "./notify.js";
import { setView } from "./tasks.js";
import { patchSettings } from "./settings.js";
import { postSnap } from "./snapshot.js";

export let askCloseOpen = false; // chặn double-emit main:ask-close

/** Gọi một lần khi boot: nghe sự kiện Rust→JS. */
export function initAskCloseBridge() {
  const ev = window.__TAURI__?.event;
  try { ev?.listen?.("tray:today", () => setView({ type: "today" })); } catch { /* ngoài Tauri */ }
  try { ev?.listen?.("main:ask-close", () => openAskCloseModal()); } catch { /* ngoài Tauri */ }
  // mọi đường đóng modal (backdrop / Esc / nút) đều qua closeModal → tắt cờ
  document.addEventListener("taskora:modal-close", () => { askCloseOpen = false; });
}

function openAskCloseModal() {
  if (askCloseOpen) return; // bấm X liên tục — không chồng modal
  askCloseOpen = true;
  openModal(`<h2>Đóng Taskora?</h2>
    <p>App tự lưu liên tục — thoát không mất dữ liệu.</p>
    <label class="ask-remember"><input type="checkbox" id="ask-remember" checked /> <span>Ghi nhớ <span class="muted">(đổi lại trong Cài đặt → Giao diện bất kỳ lúc nào)</span></span></label>
    <div class="modal-actions">
      <button class="btn-ghost" data-ask-choice="exit" type="button">Thoát hẳn</button>
      <button class="btn-save" data-ask-choice="tray" type="button">Thu vào khay</button>
    </div>`);
  const primary = document.querySelector('[data-ask-choice="tray"]');
  if (primary) primary.focus();
}

/** Người dùng chọn trong modal — set_close_behavior (nếu ghi nhớ) rồi close_choice (thực thi). */
export async function chooseAskClose(choice) {
  const remember = ($("#ask-remember") && $("#ask-remember").checked) === true;
  const c = choice === "exit" ? "exit" : "tray";
  if (remember) {
    try { const snap = await invoke("set_close_behavior", { behavior: c }); postSnap(snap); }
    catch (err) { notify({ kind: "error", title: "Không lưu được lựa chọn", body: String(err && err.message ? err.message : err) }); /* vẫn thực thi đóng */ }
  }
  closeModal();
  if (c === "tray" && S.snap && S.snap.settings && S.snap.settings.close_hint_shown === false) {
    notify({ kind: "info", title: "Taskora vẫn chạy ở khay", body: "Bấm chuột trái icon khay để hiện/ẩn · chuột phải để thoát", sound: "none" });
    patchSettings({ close_hint_shown: true });
  }
  try { await invoke("close_choice", { choice: c }); }
  catch (err) { notify({ kind: "error", title: "Không đóng được", body: String(err && err.message ? err.message : err) }); }
}
