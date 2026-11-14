//! Hiệu ứng cửa sổ — Acrylic native.
//!
//! Hai đường, chọn theo máy (tự thích ứng qua HRESULT, không cần dò build):
//!  1) Windows 11 22H2+ (build ≥ 22523): DWMSBT_TRANSIENTWINDOW — DWM tự xử lý,
//!     GPU-composited, KHÔNG bị khựng khi kéo cửa sổ (đường được Microsoft khuyến nghị).
//!     Tint bị DWM bỏ qua — độ "trong" do thanh Độ phủ điều khiển lớp giao diện (--cov).
//!  2) Windows cũ hơn: SWCA ACCENT_ENABLE_ACRYLICBLURBEHIND với tint theo slider —
//!     undocumented nhưng ổn định từ Win10 1803; có thể khựng khi kéo (giới hạn của MS).
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
mod dwm {
    use std::ffi::c_void;

    #[link(name = "dwmapi")]
    extern "system" {
        fn DwmSetWindowAttribute(
            hwnd: *mut c_void,
            dwAttribute: u32,
            pvAttribute: *const c_void,
            cbAttribute: u32,
        ) -> i32;
    }

    const DWMWA_SYSTEMBACKDROP_TYPE: u32 = 38;
    const DWMSBT_DISABLE: u32 = 1;
    const DWMSBT_TRANSIENTWINDOW: u32 = 3; // Acrylic

    /// Trả về true nếu DWM chấp nhận thuộc tính (Win11 22H2+), false nếu build không hỗ trợ.
    pub fn set_backdrop(hwnd: *mut c_void, transient: bool) -> bool {
        let backdrop: u32 = if transient { DWMSBT_TRANSIENTWINDOW } else { DWMSBT_DISABLE };
        let hr = unsafe {
            DwmSetWindowAttribute(
                hwnd,
                DWMWA_SYSTEMBACKDROP_TYPE,
                &backdrop as *const u32 as *const c_void,
                4,
            )
        };
        hr == 0
    }
}

#[cfg(windows)]
mod swca {
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

    /// Trả về false nếu API không tồn tại trên máy này.
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
            // BGRA, alpha ở byte cao
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
        // Đường 1: DWMSBT_TRANSIENTWINDOW (Win11 22H2+) — DWM xử lý, không khựng khi kéo
        let dwm_ok = hwnd.map(|h| dwm::set_backdrop(h, true)).unwrap_or(false);
        if dwm_ok {
            // Vô hiệu hóa SWCA để không xung đột với backdrop của DWM
            if let Some(h) = hwnd {
                let _ = swca::set_accent(h, swca::ACCENT_DISABLED, None);
            }
            set_status("Acrylic đang bật (DWM) — mượt khi kéo cửa sổ".to_string());
            return Ok(());
        }
        // Đường 2 (fallback): SWCA acrylic — có tint theo thanh Độ phủ
        let tint = Some((16u8, 19u8, 37u8, alpha.clamp(10, 250)));
        let swca_ok = hwnd
            .map(|h| swca::set_accent(h, swca::ACCENT_ENABLE_ACRYLICBLURBEHIND, tint))
            .unwrap_or(false);
        if swca_ok {
            set_status(format!(
                "Acrylic đang bật (SWCA) — độ phủ theo thanh trượt ({alpha}); có thể khựng khi kéo (giới hạn của Windows này)"
            ));
            return Ok(());
        }
        // Đường 3: blur thường làm chốt chặn cuối
        match window_vibrancy::apply_blur(window, tint) {
            Ok(()) => {
                set_status("Acrylic không khả dụng, đang dùng Blur — có thể khựng khi kéo".to_string());
                Ok(())
            }
            Err(e) => {
                set_status(format!("Không bật được trong suốt: {e}"));
                Err(format!("Trong suốt thất bại: {e}"))
            }
        }
    } else {
        if let Some(h) = hwnd {
            let _ = dwm::set_backdrop(h, false); // DWMSBT_DISABLE
            let _ = swca::set_accent(h, swca::ACCENT_DISABLED, None);
        }
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
