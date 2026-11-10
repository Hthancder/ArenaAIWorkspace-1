//! Taskora v2 — Rust + Tauri, giao diện liquid glass (xem src-ui/).
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod commands;
mod fx;
mod models;
mod parser;
mod state;
mod stats;
mod storage;

use tauri::Manager;

fn main() {
    tauri::Builder::default()
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
            commands::preview_parse,
            commands::visible_ids,
            commands::set_task_title,
            commands::set_task_notes,
            commands::set_task_repeat,
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
