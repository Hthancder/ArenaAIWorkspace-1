//! Hiệu ứng cửa sổ — Acrylic thật, chỉnh được độ phủ trên MỌI bản Windows.
//!
//! Vì sao không giao hết cho window-vibrancy:
//! trên Windows 11 22H2+ (build ≥ 22523) apply_acrylic() gọi DWMSBT_TRANSIENTWINDOW
//! (DWM system backdrop) — DWM hoàn toàn BỎ QUA màu/alpha tint, nên thanh
//! "Độ phủ Acrylic" không bao giờ có tác dụng. Ở đây ta tự gọi
//! SetWindowCompositionAttribute(ACCENT_ENABLE_ACRYLICBLURBEHIND) — undocumented nhưng ổn định
//! từ Win10 1803 tới Win11 hiện tại — với tint lấy thẳng từ slider (BGRA, alpha byte cao).
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
mod win {
    use std::ffi::c_void;

    #[repr(C)]
    struct AccentPolicy {
        accent_state: u32,
        accent_flags: u32,
        gradient_color: u32,
        animation_id: u32,
    }

    #[repr(C)]
    struct WindowCompositionAttribData {
        attrib: u32,
        pv_data: *mut c_void,
        cb_data: usize,
    }

    pub const ACCENT_DISABLED: u32 = 0;
    pub const ACCENT_ENABLE_ACRYLICBLURBEHIND: u32 = 4;
    const WCA_ACCENT_POLICY: u32 = 0x13;

    #[link(name = "kernel32")]
    extern "system" {
        fn LoadLibraryW(name: *const u16) -> *mut c_void;
        fn GetProcAddress(module: *mut c_void, name: *const u8) -> *const c_void;
    }

    type SetWindowCompositionAttributeFn =
        unsafe extern "system" fn(*mut c_void, *mut WindowCompositionAttribData) -> i32;

    fn wide(s: &str) -> Vec<u16> {
        s.encode_utf16().chain(std::iter::once(0)).collect()
    }

    /// Gọi SetWindowCompositionAttribute với ACCENT_POLICY. Trả về false nếu API không tồn tại.
    pub fn set_accent(hwnd: *mut c_void, state: u32, rgba: Option<(u8, u8, u8, u8)>) -> bool {
        let lib = unsafe { LoadLibraryW(wide("user32.dll").as_ptr()) };
        if lib.is_null() {
            return false;
        }
        let raw = unsafe { GetProcAddress(lib, b"SetWindowCompositionAttribute\0".as_ptr()) };
        if raw.is_null() {
            return false;
        }
        let set_fn: SetWindowCompositionAttributeFn = unsafe { std::mem::transmute(raw) };
        let (r, g, b, a) = rgba.unwrap_or((0, 0, 0, 0));
        let mut policy = AccentPolicy {
            accent_state: state,
            accent_flags: 0, // 0 = acrylic (2 = blur)
            // BGRA, alpha ở byte cao — đúng định dạng API mong đợi
            gradient_color: (r as u32)
                | ((g as u32) << 8)
                | ((b as u32) << 16)
                | ((a as u32) << 24),
            animation_id: 0,
        };
        let mut data = WindowCompositionAttribData {
            attrib: WCA_ACCENT_POLICY,
            pv_data: &mut policy as *mut AccentPolicy as *mut c_void,
            cb_data: std::mem::size_of::<AccentPolicy>(),
        };
        unsafe { set_fn(hwnd, &mut data) != 0 }
    }
}

#[cfg(windows)]
fn hwnd_ptr(window: &tauri::WebviewWindow) -> Option<*mut std::ffi::c_void> {
    window.hwnd().ok().map(|h| h.0 as *mut std::ffi::c_void)
}

#[cfg(windows)]
pub fn apply_effect(window: &tauri::WebviewWindow, transparent: bool, alpha: u8) -> Result<(), String> {
    let hwnd = hwnd_ptr(window);
    if transparent {
        // vỏ màu xanh-than (giữ đúng tinh thần bản cũ), độ phủ = alpha từ slider
        let tint = Some((16u8, 19u8, 37u8, alpha.clamp(10, 250)));
        let swca_ok = hwnd
            .map(|h| win::set_accent(h, win::ACCENT_ENABLE_ACRYLICBLURBEHIND, tint))
            .unwrap_or(false);
        if swca_ok {
            set_status(format!(
                "Acrylic đang bật — độ phủ theo thanh trượt ({alpha})"
            ));
            Ok(())
        } else {
            // Fallback hiếm gặp: API không tồn tại → để hệ thống tự quyết định
            match window_vibrancy::apply_acrylic(window, tint) {
                Ok(()) => {
                    set_status(
                        "Acrylic hệ thống (DWM) đang bật — độ phủ do Windows quyết định"
                            .to_string(),
                    );
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
        }
    } else {
        if let Some(h) = hwnd {
            let _ = win::set_accent(h, win::ACCENT_DISABLED, None);
        }
        let _ = window_vibrancy::clear_acrylic(window); // dọn DWMSBT nếu bản cũ đã đặt
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
