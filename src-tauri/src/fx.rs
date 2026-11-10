//! Hiệu ứng cửa sổ — Acrylic/Blur thật qua DWM (Windows), trong suốt màu navy.
#![allow(dead_code)]

use std::sync::{Mutex, OnceLock};

static FX_STATUS: OnceLock<Mutex<String>> = OnceLock::new();

fn status_cell() -> &'static Mutex<String> {
    FX_STATUS.get_or_init(|| Mutex::new("Chưa áp dụng".to_string()))
}

/// Trạng thái hiệu ứng gần nhất (hiển thị trong Cài đặt).
pub fn status() -> String {
    status_cell().lock().unwrap().clone()
}

fn set_status(s: impl Into<String>) {
    *status_cell().lock().unwrap() = s.into();
}

#[cfg(windows)]
pub fn apply_effect(window: &tauri::WebviewWindow, transparent: bool, alpha: u8) -> Result<(), String> {
    if transparent {
        let tint = Some((16, 19, 37, alpha));
        match window_vibrancy::apply_acrylic(window, tint) {
            Ok(()) => {
                set_status("Acrylic (DWM) đang bật");
                Ok(())
            }
            Err(e_acrylic) => match window_vibrancy::apply_blur(window, tint) {
                Ok(()) => {
                    set_status(format!("Acrylic không khả dụng, đang dùng Blur. ({e_acrylic})"));
                    Ok(())
                }
                Err(e_blur) => {
                    set_status(format!(
                        "Không bật được trong suốt: {e_blur}. (Acrylic: {e_acrylic})"
                    ));
                    Err(format!("Acrylic: {e_acrylic} | Blur: {e_blur}"))
                }
            },
        }
    } else {
        let _ = window_vibrancy::clear_acrylic(window);
        let _ = window_vibrancy::clear_blur(window);
        set_status("Đang tắt trong suốt (nền đặc)");
        Ok(())
    }
}

#[cfg(not(windows))]
pub fn apply_effect(_window: &tauri::WebviewWindow, transparent: bool, _alpha: u8) -> Result<(), String> {
    set_status(if transparent {
        "Acrylic chỉ có trên Windows"
    } else {
        "Đang tắt trong suốt (nền đặc)"
    });
    Ok(())
}
