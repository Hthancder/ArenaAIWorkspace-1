//! Taskora v2 — Rust + Tauri, giao diện liquid glass (xem src-ui/).
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod bootstrap;
mod commands;
mod fx;
mod models;
mod parser;
mod state;
mod stats;
mod storage;
mod transparency;

use tauri::Manager;

fn main() {
    // Xác định nơi lưu dữ liệu TRƯỚC khi nạp store
    bootstrap::init();
    tauri::Builder::default().plugin(tauri_plugin_dialog::init())
        .manage(state::AppState::new())
        .setup(|app| {
            // Áp dụng Acrylic/Blur theo cài đặt đã lưu (Windows)
            let settings = app.state::<state::AppState>().lock().store.settings.clone();
            if let Some(w) = app.get_webview_window("main") {
                if let Err(e) = fx::apply_effect(&w, settings.transparent, settings.acrylic_alpha) {
                    eprintln!("[Taskora] Không bật được hiệu ứng Acrylic: {e}");
                }
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::snapshot,
            commands::act,
            commands::quick_add,
            commands::brain_dump,
            commands::log_focus_session,
            commands::save_step_preset,
            commands::delete_step_preset,
            commands::preview_parse,
            commands::visible_ids,
            commands::set_task_title,
            commands::set_task_notes,
            commands::set_task_repeat,
            commands::set_task_recurrence,
            commands::skip_occurrence,
            commands::preview_occurrences,
            commands::next_occurrence,
            commands::toggle_subtask,
            commands::set_subtask_title,
            commands::remove_subtask,
            commands::add_task_tag,
            commands::remove_task_tag,
            commands::undo,
            commands::redo,
            commands::set_sort,
            commands::set_hide_completed,
            commands::toggle_dark,
            commands::create_list,
            commands::rename_list,
            commands::delete_list,
            commands::stats,
            commands::export_backup,
            commands::list_backups,
            commands::import_backup,
            commands::open_data_dir,
            commands::save_now,
            commands::update_settings,
            commands::reset_settings,
            commands::set_last_view,
            commands::storage_info,
            commands::storage_startup,
            commands::storage_switch,
            commands::storage_merge_legacy,
            commands::storage_import_orphan,
            commands::storage_dismiss,
            commands::fx_status,
            commands::transparency_status,
            commands::set_transparency,
        ])
        .build(tauri::generate_context!())
        .expect("không khởi động được Taskora")
        .run(|app, event| {
            if let tauri::RunEvent::Exit = event {
                if let Some(s) = app.try_state::<state::AppState>() {
                    let on = { s.lock().store.settings.backup_on_exit };
                    if on {
                        let i = s.lock();
                        let _ = storage::export_backup(&i.store);
                    }
                    s.flush();
                }
            }
        });
}
