//! Hiệu ứng cửa sổ — Acrylic/Blur thật qua DWM (Windows), trong suốt màu navy.
#![allow(dead_code)]

#[cfg(windows)]
pub fn apply_effect(window: &tauri::WebviewWindow, transparent: bool, alpha: u8) -> Result<(), String> {
    if transparent {
        let tint = Some((16, 19, 37, alpha));
        window_vibrancy::apply_acrylic(window, tint)
            .or_else(|_| window_vibrancy::apply_blur(window, tint))
            .map_err(|e| format!("Acrylic/Blur không được hệ thống hỗ trợ: {e}"))
    } else {
        let _ = window_vibrancy::clear_acrylic(window);
        let _ = window_vibrancy::clear_blur(window);
        Ok(())
    }
}

#[cfg(not(windows))]
pub fn apply_effect(_window: &tauri::WebviewWindow, _transparent: bool, _alpha: u8) -> Result<(), String> {
    Ok(()) // Linux/macOS: dùng mặc định của hệ thống
}
