//! Taskora v2 — Rust + Tauri, giao diện liquid glass (xem src-ui/).
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod bootstrap;
mod commands;
mod focus;
mod fx;
mod hotkey;
mod models;
mod parser;
mod state;
mod stats;
mod storage;
mod transparency;
mod tray;

use tauri::Manager;

fn main() {
    // Xác định nơi lưu dữ liệu TRƯỚC khi nạp store
    bootstrap::init();
    // `--minimized`: được truyền khi app tự khởi động cùng Windows (autostart) — mở ẩn vào khay
    let minimized = std::env::args().any(|a| a == "--minimized");
    tauri::Builder::default().plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_autostart::init(tauri_plugin_autostart::MacosLauncher::LaunchAgent, Some(vec!["--minimized"])))
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .manage(commands::HotkeyState(std::sync::atomic::AtomicBool::new(false)))
        .manage(state::AppState::new())
        .manage(commands::NotifyState::default())
        .setup(move |app| {
            // Áp dụng Acrylic/Blur theo cài đặt đã lưu (Windows)
            let settings = app.state::<state::AppState>().lock().store.settings.clone();
            if let Some(w) = app.get_webview_window("main") {
                if let Err(e) = fx::apply_effect(&w, settings.transparent, settings.acrylic_alpha) {
                    eprintln!("[Taskora] Không bật được hiệu ứng Acrylic: {e}");
                }
            }
            // Pre-tạo cửa sổ THÔNG BÁO (ẩn) — thông báo đầu tiên không phải chờ tạo webview
            let handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                if let Err(e) = commands::ensure_notify_window(&handle).await {
                    eprintln!("[Taskora] Không tạo được cửa sổ Thông báo (sẽ thử lại khi cần): {e}");
                }
            });
            // Tự khởi động cùng Windows: nếu người dùng chọn "Mở ẩn trong khay" thì ẩn cửa sổ ngay (trước event loop).
            // Arg `--minimized` luôn được đăng ký khi autostart — quyết định thật nằm ở cài đặt hidden_on_autostart.
            if minimized {
                let hidden = app.state::<state::AppState>().lock().store.settings.hidden_on_autostart;
                if hidden {
                    if let Some(w) = app.get_webview_window("main") {
                        let _ = w.hide();
                    }
                }
            }
            // Autostart tự chữa đường dẫn: luôn enable() lại lúc khởi động (exe có thể đã di chuyển)
            {
                use tauri_plugin_autostart::ManagerExt;
                let al = app.autolaunch();
                if al.is_enabled().unwrap_or(false) {
                    let _ = al.enable();
                }
            }
            // Khay hệ thống (tray) — luôn hiện
            if let Err(e) = tray::setup(&handle) {
                eprintln!("[Taskora] Không tạo được tray (app vẫn chạy bình thường): {e}");
            }
            // Phím tắt toàn cục theo cấu hình đang lưu
            {
                let (spec, enabled) = {
                    let st = app.state::<state::AppState>().lock();
                    (st.store.settings.global_hotkey.clone(), st.store.settings.global_hotkey_enabled)
                };
                if enabled {
                    match hotkey::register(&handle, &spec) {
                        Ok(()) => app.state::<commands::HotkeyState>().0.store(true, std::sync::atomic::Ordering::SeqCst),
                        Err(e) => eprintln!("[Taskora] Không đăng ký được phím tắt toàn cục '{spec}' (có thể bị app khác chiếm): {e}"),
                    }
                }
            }
            Ok(())
        })
        .on_window_event(|window, event| {
            if window.label() != "main" {
                return;
            }
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                let behavior = window
                    .app_handle()
                    .try_state::<state::AppState>()
                    .map(|s| s.lock().store.settings.close_behavior.clone())
                    .unwrap_or_else(|| "ask".to_string());
                api.prevent_close();
                match behavior.as_str() {
                    "tray" => {
                        let _ = window.hide();
                    }
                    "exit" => {
                        window.app_handle().exit(0);
                    }
                    _ => {
                        use tauri::Emitter;
                        let _ = window.app_handle().emit("main:ask-close", ());
                    }
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            commands::snapshot,
            commands::act,
            commands::quick_add,
            commands::brain_dump,
            commands::log_focus_session,
            commands::focus_start,
            commands::focus_stop,
            commands::focus_pause_toggle,
            commands::focus_reset,
            commands::focus_break_start,
            commands::focus_complete,
            commands::focus_state,
            commands::focus_open_timer,
            commands::focus_timer_close,
            commands::focus_timer_pin,
            commands::focus_open_main,
            commands::notify_push,
            commands::notify_ready,
            commands::notify_layout,
            commands::notify_prefs,
            commands::notify_action,
            commands::notify_clear,
            commands::set_close_behavior,
            commands::close_choice,
            commands::autostart_get,
            commands::autostart_set,
            commands::set_global_hotkey,
            commands::set_global_hotkey_enabled,
            commands::global_hotkey_status,
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
