//! Khay hệ thống (Windows) — tray icon luôn hiện.
//! Click trái: bật/tắt cửa sổ chính · Click phải: menu chuẩn
//! (header “Taskora — N việc hôm nay[ · M quá hạn]” · Việc hôm nay · Mở Taskora · Thoát).
//! Header/tooltip cùng nguồn dữ liệu với topbar — cập nhật trong `finish()`.
use crate::models::Counts;
use tauri::{
    menu::{Menu, MenuItem, MenuItemBuilder, PredefinedMenuItem},
    tray::{MouseButton, MouseButtonState, TrayIcon, TrayIconBuilder, TrayIconEvent},
    AppHandle, Emitter, Manager, Wry,
};

/// Menu id
const ID_HEADER: &str = "taskora-header";
const ID_TODAY: &str = "taskora-today";
const ID_OPEN: &str = "taskora-open";
const ID_QUIT: &str = "taskora-quit";
const TRAY_ID: &str = "taskora-tray";

/// Handle của item header — lưu lúc setup để `refresh` cập nhật văn bản.
pub struct TrayState {
    pub header: MenuItem<Wry>,
    pub tray: TrayIcon<Wry>,
}

pub fn header_text(counts: &Counts) -> String {
    if counts.overdue > 0 {
        format!("Taskora — {} việc hôm nay · {} quá hạn", counts.today, counts.overdue)
    } else {
        format!("Taskora — {} việc hôm nay", counts.today)
    }
}

pub fn setup(app: &AppHandle) -> tauri::Result<()> {
    let header = MenuItemBuilder::with_id(ID_HEADER, "Taskora").enabled(false).build(app)?;
    let today = MenuItemBuilder::with_id(ID_TODAY, "Việc hôm nay").build(app)?;
    let open = MenuItemBuilder::with_id(ID_OPEN, "Mở Taskora").build(app)?;
    let sep = PredefinedMenuItem::separator(app)?;
    let quit = MenuItemBuilder::with_id(ID_QUIT, "Thoát").build(app)?;
    let menu = Menu::with_items(app, &[&header, &today, &open, &sep, &quit])?;

    let icon = app.default_window_icon().cloned();
    let mut builder = TrayIconBuilder::with_id(TRAY_ID)
        .menu(&menu)
        .tooltip("Taskora")
        .show_menu_on_left_click(false); // click trái = bật/tắt cửa sổ, click phải = menu
    if let Some(icon) = icon {
        builder = builder.icon(icon);
    }
    builder = builder.on_menu_event(|app, event| match event.id().as_ref() {
        ID_TODAY => {
            show_main(app);
            let _ = app.emit("tray:today", ());
        }
        ID_OPEN => show_main(app),
        ID_QUIT => app.exit(0),
        _ => {}
    });
    let app_click = app.clone();
    builder = builder.on_tray_icon_event(move |_tray, event| {
        if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = event {
            crate::hotkey::toggle_main(&app_click);
        }
    });
    let tray = builder.build(app)?;

    app.manage(TrayState { header, tray });
    Ok(())
}

/// Hiện + focus cửa sổ chính (giữ nguyên view đang mở).
pub fn show_main(app: &AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.show();
        let _ = w.unminimize();
        let _ = w.set_focus();
    }
}

/// Cập nhật header + tooltip sau mỗi mutation (gọi từ `finish()`). Best-effort.
pub fn refresh(app: &AppHandle, counts: &Counts) {
    let text = header_text(counts);
    if let Some(state) = app.try_state::<TrayState>() {
        let _ = state.header.set_text(&text);
    }
    if let Some(state) = app.try_state::<TrayState>() {
        let _ = state.tray.set_tooltip(Some(text.as_str()));
    }
}
